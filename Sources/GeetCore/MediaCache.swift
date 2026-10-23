import Foundation

public struct CacheEntry: Codable, Sendable {
    public var key: String
    public var trackID: String
    public var formatID: String
    public var length: Int64
    public var chunks: Set<Int>
    public var pinned: Bool
    public var touched: Date
    public var complete: Bool { length > 0 && chunks.count == Int((length + MediaCache.chunkSize - 1) / MediaCache.chunkSize) }
    public var storedBytes: Int64 { chunks.reduce(0) { $0 + min(MediaCache.chunkSize, length - Int64($1) * MediaCache.chunkSize) } }
}

/// Range-based disk storage. Playback and explicit downloads share the same byte
/// requests, so automatic caching never downloads the audio a second time.
public actor MediaCache {
    public static let chunkSize: Int64 = 512 * 1024
    public static let automaticLimit: Int64 = 2 * 1024 * 1024 * 1024
    public static let totalLimit: Int64 = 10 * 1024 * 1024 * 1024
    private let root: URL
    private var entries: [String: CacheEntry]
    private var memory: [String: (data: Data, length: Int64, touched: UInt64)] = [:]
    private var tick: UInt64 = 0
    private struct Transfer {
        let id = UUID()
        let task: Task<(Data, Int64), Error>
        var waiters: Set<UUID>
    }
    private var inflight: [String: Transfer] = [:]
    public private(set) var networkRequests = 0
    private let session: URLSession
    public init(root: URL = Paths.support.appendingPathComponent("Media", isDirectory: true), configuration: URLSessionConfiguration? = nil) {
        self.root = root
        entries = Paths.read([String: CacheEntry].self, from: root.appendingPathComponent("index.json")) ?? [:]
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config, delegate: RangeResponseGuard(), delegateQueue: nil)
    }
    public static func key(trackID: String, formatID: String) -> String {
        let safe = (trackID + "-" + formatID).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        return String(safe.prefix(100))
    }
    public func snapshot() -> [CacheEntry] { Array(entries.values) }
    public func completedEntry(for trackID: String) -> CacheEntry? { entries.values.first { $0.trackID == trackID && $0.complete } }
    public func length(key: String) -> Int64? { entries[key]?.length }
    public func isComplete(trackID: String) -> Bool { completedEntry(for: trackID) != nil }
    public func memoryBytes() -> Int { memory.values.reduce(0) { $0 + $1.0.count } }

    public func chunk(key: String, index: Int, stream: ResolvedStream?, retaining: Bool = true) async throws -> (Data, Int64) {
        try Task.checkCancellation()
        let name = "\(key)/\(index)"
        tick &+= 1
        if let saved = memory[name] {
            if retaining, entries[key]?.chunks.contains(index) != true, let stream {
                try store(saved.data, total: saved.length, key: key, index: index, stream: stream)
            }
            memory[name] = (saved.data, saved.length, tick); return (saved.data, saved.length)
        }
        let file = fileURL(key: key, index: index)
        if let entry = entries[key], entry.chunks.contains(index),
           let data = try? Data(contentsOf: file), data.count == Int(min(Self.chunkSize, entry.length - Int64(index) * Self.chunkSize)) {
            remember(name, data, length: entry.length); return (data, entry.length)
        }
        if entries[key]?.chunks.contains(index) == true {
            entries[key]?.chunks.remove(index); persist()
        }
        guard let stream, stream.isValid, !stream.isHLS else { throw GeetError.message("This part of the mix isn’t saved offline yet.") }
        let waiter = UUID()
        let transfer: Transfer
        if var running = inflight[name], !running.task.isCancelled {
            running.waiters.insert(waiter); inflight[name] = running; transfer = running
        } else {
            let session = session
            networkRequests += 1
            let task = Task<(Data, Int64), Error> {
                let start = Int64(index) * Self.chunkSize
                var request = URLRequest(url: stream.url)
                stream.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                request.setValue("bytes=\(start)-\(start + Self.chunkSize - 1)", forHTTPHeaderField: "Range")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 206,
                      let range = http.value(forHTTPHeaderField: "Content-Range"),
                      let total = Int64(range.split(separator: "/").last ?? ""), total > start,
                      range.hasPrefix("bytes \(start)-"), !data.isEmpty, data.count <= Int(Self.chunkSize),
                      data.count == Int(min(Self.chunkSize, total - start)) else {
                    throw GeetError.message("The audio server couldn’t provide a complete audio segment.")
                }
                return (data, total)
            }
            transfer = Transfer(task: task, waiters: [waiter])
            inflight[name] = transfer
        }
        defer { releaseWaiter(name, transferID: transfer.id, waiter: waiter) }
        let (data, total) = try await withTaskCancellationHandler(operation: { try await transfer.task.value }, onCancel: {
            Task { await self.releaseWaiter(name, transferID: transfer.id, waiter: waiter) }
        })
        try Task.checkCancellation()
        if retaining { try store(data, total: total, key: key, index: index, stream: stream) }
        remember(name, data, length: total)
        return (data, total)
    }

    private func releaseWaiter(_ name: String, transferID: UUID, waiter: UUID) {
        guard var transfer = inflight[name], transfer.id == transferID else { return }
        transfer.waiters.remove(waiter)
        if transfer.waiters.isEmpty { transfer.task.cancel(); inflight.removeValue(forKey: name) }
        else { inflight[name] = transfer }
    }

    private func store(_ data: Data, total: Int64, key: String, index: Int, stream: ResolvedStream) throws {
        if let old = entries[key], old.length != total {
            // Signed URLs may change, but bytes from different resources never mix.
            remove(key)
        }
        if entries[key] == nil {
            if entries.count >= 2048 {
                guard let oldest = entries.values.filter({ !$0.pinned && $0.key != key }).min(by: { $0.touched < $1.touched }) else {
                    throw GeetError.message("The offline library has reached its 2,048-track limit. Remove a saved playlist to make room.")
                }; remove(oldest.key)
            }
            entries[key] = CacheEntry(key: key, trackID: stream.track.id, formatID: stream.formatID, length: total, chunks: [], pinned: false, touched: Date())
        }
        guard entries[key]?.chunks.contains(index) != true else { return }
        try makeRoom(bytes: Int64(data.count), protecting: key)
        let file = fileURL(key: key, index: index)
        Paths.ensure(file.deletingLastPathComponent())
        try data.write(to: file, options: .atomic)
        entries[key]?.chunks.insert(index); entries[key]?.touched = Date()
        persist()
    }

    public func download(_ stream: ResolvedStream, pinned: Bool, progress: @Sendable (Double) -> Void) async throws {
        guard !stream.track.isLive, !stream.isHLS else { throw GeetError.message("Live radio is available online only.") }
        let key = Self.key(trackID: stream.track.id, formatID: stream.formatID)
        let (_, total) = try await chunk(key: key, index: 0, stream: stream)
        entries[key]?.pinned = pinned; persist()
        let count = Int((total + Self.chunkSize - 1) / Self.chunkSize)
        for index in 0..<count {
            try Task.checkCancellation()
            _ = try await chunk(key: key, index: index, stream: stream)
            progress(Double(entries[key]?.chunks.count ?? 0) / Double(count))
        }
    }
    public func setPinned(trackIDs: Set<String>) {
        for key in Array(entries.keys) {
            guard var entry = entries[key] else { continue }
            entry.pinned = trackIDs.contains(entry.trackID)
            entries[key] = entry
        }
        persist()
    }
    public func clearAutomatic() {
        for entry in Array(entries.values) where !entry.pinned { remove(entry.key) }; persist()
    }
    public func removeUnpinned(trackIDs: Set<String>) {
        for entry in Array(entries.values) where trackIDs.contains(entry.trackID) && !entry.pinned { remove(entry.key) }
        persist()
    }
    public func removeAll() { for key in Array(entries.keys) { remove(key) }; persist() }
    public func cancelTransfers() { inflight.values.forEach { $0.task.cancel() }; inflight.removeAll() }
    private func fileURL(key: String, index: Int) -> URL { root.appendingPathComponent(key, isDirectory: true).appendingPathComponent("\(index).chunk") }
    private func remember(_ name: String, _ data: Data, length: Int64) {
        tick &+= 1; memory[name] = (data, length, tick)
        while memory.count > 6, let oldest = memory.min(by: { $0.value.touched < $1.value.touched })?.key { memory.removeValue(forKey: oldest) }
    }
    private func remove(_ key: String) {
        entries.removeValue(forKey: key)
        for name in Array(memory.keys) where name.hasPrefix(key + "/") { memory.removeValue(forKey: name) }
        try? FileManager.default.removeItem(at: root.appendingPathComponent(key, isDirectory: true))
    }
    private func makeRoom(bytes: Int64, protecting key: String) throws {
        var automatic = entries.values.filter { !$0.pinned }.reduce(Int64(0)) { $0 + $1.storedBytes }
        var total = entries.values.reduce(Int64(0)) { $0 + $1.storedBytes }
        let pinned = entries[key]?.pinned == true
        for candidate in entries.values.filter({ !$0.pinned && $0.key != key }).sorted(by: { $0.touched < $1.touched }) {
            if total + bytes <= Self.totalLimit && (pinned || automatic + bytes <= Self.automaticLimit) { break }
            automatic -= candidate.storedBytes; total -= candidate.storedBytes; remove(candidate.key)
        }
        guard total + bytes <= Self.totalLimit, pinned || automatic + bytes <= Self.automaticLimit else {
            throw GeetError.message("Offline storage is full. Remove saved music in Settings to make room.")
        }
    }
    private func persist() { try? Paths.write(entries, to: root.appendingPathComponent("index.json")) }
}

/// Prevents URLSession from buffering an unbounded response when a server ignores
/// a Range header. Each accepted response is at most one 512 KB chunk.
private final class RangeResponseGuard: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        completionHandler(http?.statusCode == 206 && response.expectedContentLength > 0 && response.expectedContentLength <= MediaCache.chunkSize ? .allow : .cancel)
    }
}
