import Foundation
import Network
import GeetCore

/// A private loopback range endpoint preserves native AVPlayer buffering and
/// TCP backpressure. No listener exists before Play or after pipeline teardown.
@MainActor
final class AudioStreamServer {
    var retaining: Bool
    var offline: Bool { stream == nil }
    private let cache: MediaCache
    private let key: String
    private let stream: ResolvedStream?
    private let path = "/\(UUID().uuidString)\(UUID().uuidString)/"
    private let queue = DispatchQueue(label: "app.geet.audio-ranges", qos: .utility)
    private var listener: NWListener?
    private var starting: CheckedContinuation<URL, Error>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var jobs: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var firstChunk = Data()
    private var index: DASHAudioIndex?
    private var length: Int64 = 0
    private var stopped = false

    init(cache: MediaCache, key: String, stream: ResolvedStream?, retaining: Bool = true) {
        self.cache = cache; self.key = key; self.stream = stream; self.retaining = retaining
    }
    func start() async throws -> URL {
        let (data, total) = try await cache.chunk(key: key, index: 0, stream: stream, retaining: retaining)
        try Task.checkCancellation()
        firstChunk = data; length = total
        index = DASHAudioIndex.parse(data, length: total)
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in Task { @MainActor in self?.accept(connection) } }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                guard !stopped, !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                starting = continuation
                listener.stateUpdateHandler = { [weak self] state in
                    Task { @MainActor in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            if let port = listener.port, !self.stopped {
                                let url = URL(string: "http://127.0.0.1:\(port.rawValue)\(self.path)\(self.index == nil ? "audio.m4a" : "playlist.m3u8")")!
                                #if DEBUG
                                if ProcessInfo.processInfo.environment["GEET_TRACE_AUDIO"] != nil { print("AUDIO_ENDPOINT \(url.absoluteString)"); fflush(stdout) }
                                #endif
                                self.starting?.resume(returning: url)
                                self.starting = nil
                            }
                        case .failed(let error): self.finishStarting(error)
                        case .cancelled: self.finishStarting(CancellationError())
                        default: break
                        }
                    }
                }
                listener.start(queue: queue)
            }
        }, onCancel: { Task { @MainActor in self.stop() } })
    }
    func stop() {
        stopped = true; finishStarting(CancellationError())
        listener?.stateUpdateHandler = nil; listener?.newConnectionHandler = nil
        listener?.cancel(); listener = nil
        jobs.values.forEach { $0.cancel() }; jobs.removeAll()
        connections.values.forEach { $0.cancel() }; connections.removeAll()
        firstChunk = Data()
        index = nil
    }
    private func finishStarting(_ error: Error) { starting?.resume(throwing: error); starting = nil }
    private func accept(_ connection: NWConnection) {
        guard !stopped, connections.count < 4 else { connection.cancel(); return }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.start(queue: queue)
        jobs[id] = Task { [weak self] in
            guard let self else { connection.cancel(); return }
            defer { connection.cancel(); self.connections.removeValue(forKey: id); self.jobs.removeValue(forKey: id) }
            do { try await self.serve(connection) } catch { /* AVPlayer cancels ranges when its buffer fills. */ }
        }
    }
    private func serve(_ connection: NWConnection) async throws {
        var request = Data()
        while request.range(of: Data("\r\n\r\n".utf8)) == nil {
            try Task.checkCancellation()
            guard request.count < 16_384 else { return }
            request.append(try await receive(connection))
        }
        let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
        let first = (lines.first ?? "").split(separator: " ")
        guard first.count == 3, [path + "audio.m4a", path + "init.mp4", path + "playlist.m3u8"].contains(String(first[1])), ["GET", "HEAD"].contains(first[0]) else {
            try await send(Data("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), on: connection, final: true); return
        }
        let range = lines.dropFirst().first { $0.lowercased().hasPrefix("range:") }?.split(separator: ":", maxSplits: 1).last.map { String($0).trimmingCharacters(in: .whitespaces) }
        if let index, first[1] == path + "playlist.m3u8" {
            try await serveStatic(index.playlist, type: "application/vnd.apple.mpegurl", range: range, head: first[0] == "HEAD", connection: connection); return
        }
        if let index, first[1] == path + "init.mp4" {
            try await serveStatic(index.initialization, type: "audio/mp4", range: range, head: first[0] == "HEAD", connection: connection); return
        }
        guard let bytes = HTTPByteRange.parse(range, length: length) else {
            try await send(Data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */\(length)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), on: connection, final: true); return
        }
        let status = range == nil ? "200 OK" : "206 Partial Content"
        var headers = "HTTP/1.1 \(status)\r\nContent-Type: audio/mp4\r\nAccept-Ranges: bytes\r\nContent-Length: \(bytes.upperBound - bytes.lowerBound + 1)\r\nCache-Control: no-store\r\nConnection: close\r\n"
        if range != nil { headers += "Content-Range: bytes \(bytes.lowerBound)-\(bytes.upperBound)/\(length)\r\n" }
        let head = first[0] == "HEAD"
        try await send(Data((headers + "\r\n").utf8), on: connection, final: head)
        guard !head else { return }
        var cursor = bytes.lowerBound
        while cursor <= bytes.upperBound {
            try Task.checkCancellation()
            let index = Int(cursor / MediaCache.chunkSize)
            let data: Data
            if index == 0 { data = firstChunk }
            else { data = try await cache.chunk(key: key, index: index, stream: stream, retaining: retaining).0 }
            let offset = Int(cursor % MediaCache.chunkSize)
            let count = min(data.count - offset, Int(bytes.upperBound - cursor + 1))
            guard count > 0 else { throw GeetError.message("The audio segment is incomplete.") }
            try await send(data.subdata(in: offset..<(offset + count)), on: connection, final: cursor + Int64(count) > bytes.upperBound)
            cursor += Int64(count)
        }
    }
    private func serveStatic(_ data: Data, type: String, range: String?, head: Bool, connection: NWConnection) async throws {
        guard let bytes = HTTPByteRange.parse(range, length: Int64(data.count)) else {
            try await send(Data("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), on: connection, final: true); return
        }
        let body = data.subdata(in: Int(bytes.lowerBound)..<(Int(bytes.upperBound) + 1))
        var headers = "HTTP/1.1 \(range == nil ? "200 OK" : "206 Partial Content")\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n"
        if range != nil { headers += "Content-Range: bytes \(bytes.lowerBound)-\(bytes.upperBound)/\(data.count)\r\n" }
        try await send(Data((headers + "\r\n").utf8), on: connection, final: head)
        if !head { try await send(body, on: connection, final: true) }
    }
    private func receive(_ connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8_192) { data, _, _, error in
                if let error { continuation.resume(throwing: error) }
                else if let data, !data.isEmpty { continuation.resume(returning: data) }
                else { continuation.resume(throwing: CancellationError()) }
            }
        }
    }
    private func send(_ data: Data, on connection: NWConnection, final: Bool = false) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, contentContext: final ? .finalMessage : .defaultMessage, isComplete: true, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        }, onCancel: { connection.cancel() })
    }
}
