import Foundation

public struct DependencyProbe: Codable, Sendable {
    public var path: String
    public var version: String
    public var modified: Date
    public var size: UInt64
    public var checked: Date
    public func usable(now: Date = Date()) -> Bool {
        guard now.timeIntervalSince(checked) < 86_400, now >= checked,
              FileManager.default.isExecutableFile(atPath: path),
              let attrs = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return attrs[.modificationDate] as? Date == modified && (attrs[.size] as? NSNumber)?.uint64Value == size
    }
}

public actor Resolver {
    public let runner: ProcessRunner
    private let root: URL
    private var streams: [String: ResolvedStream]
    private var failedUntil: [String: Date] = [:]
    private var probe: DependencyProbe?
    private var probeTask: Task<URL, Error>?
    private var pendingStreams: [String: (UUID, ResolvePriority, Task<ResolvedStream, Error>)] = [:]
    private let bundledTools: URL?
    public init(root: URL = Paths.support, bundledTools: URL? = nil, runner: ProcessRunner = ProcessRunner()) {
        self.root = root; self.runner = runner; self.bundledTools = bundledTools
        self.probe = Paths.read(DependencyProbe.self, from: root.appendingPathComponent("dependency.json"))
        let stored = Paths.read([String: ResolvedStream].self, from: root.appendingPathComponent("streams.json")) ?? [:]
        self.streams = stored.filter { $0.value.isValid }.sorted { $0.value.resolvedAt > $1.value.resolvedAt }.prefix(64).reduce(into: [:]) { $0[$1.key] = $1.value }
        // No probes, tasks, network requests, or processes here. Startup is inert.
    }

    public func dependencyStatus() -> DependencyProbe? { probe }
    public func recheck() async throws -> DependencyProbe {
        probeTask?.cancel(); probeTask = nil; probe = nil
        _ = try await executable(force: true, priority: .foreground)
        return probe!
    }

    private func executable(force: Bool = false, priority: ResolvePriority) async throws -> URL {
        if !force, let probe, probe.usable() { return URL(fileURLWithPath: probe.path) }
        if let probeTask { return try await probeTask.value }
        let candidates = [bundledTools?.appendingPathComponent("yt-dlp").path,
                          ProcessInfo.processInfo.environment["GEET_YTDLP"],
                          "/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp",
                          FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/yt-dlp").path].compactMap { $0 }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw GeetError.message("Geet needs yt-dlp to open YouTube links. Install it with ‘brew install yt-dlp deno’, then choose Recheck in Settings.")
        }
        let runner = runner
        let task = Task { () throws -> URL in
            let url = URL(fileURLWithPath: path)
            let data = try await runner.run(url, arguments: ["--ignore-config", "--version"], priority: .foreground)
            let version = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !version.isEmpty, version.count < 80 else { throw GeetError.message("The installed yt-dlp didn’t return a valid version.") }
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let result = DependencyProbe(path: path, version: version, modified: attrs[.modificationDate] as? Date ?? .distantPast,
                                         size: (attrs[.size] as? NSNumber)?.uint64Value ?? 0, checked: Date())
            self.storeProbe(result)
            return url
        }
        probeTask = task
        defer { probeTask = nil }
        return try await task.value
    }
    private func storeProbe(_ value: DependencyProbe) { probe = value; try? Paths.write(value, to: root.appendingPathComponent("dependency.json")) }

    private func baseArguments() -> [String] {
        var args = ["--ignore-config", "--no-cache-dir", "--no-update", "--no-warnings", "--skip-download", "--socket-timeout", "15", "--retries", "0", "--extractor-retries", "0"]
        let deno = [bundledTools?.appendingPathComponent("deno").path, "/opt/homebrew/bin/deno", "/usr/local/bin/deno"].compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0) }
        if let deno { args += ["--js-runtimes", "deno:\(deno)"] }
        return args
    }

    public func importCollection(_ link: YouTubeLink, priority: ResolvePriority = .foreground) async throws -> Collection {
        let failureKey = link.isPlaylist ? "playlist:\(link.id)" : link.id
        try checkFailure(failureKey)
        do {
            let exe = try await executable(priority: priority)
            let args = baseArguments() + ["--flat-playlist", "--playlist-end", "1000", "--dump-single-json", "--", link.url.absoluteString]
            let data = try await runner.run(exe, arguments: args, priority: priority)
            return try Self.parseCollection(data, link: link)
        } catch {
            if !(error is CancellationError) { recordFailure(failureKey) }; throw error
        }
    }

    public func resolve(_ track: Track, priority: ResolvePriority = .foreground, fresh: Bool = false) async throws -> ResolvedStream {
        if !fresh, let stream = streams[track.id], stream.isValid { return stream }
        if let pending = pendingStreams[track.id] {
            if priority == .foreground && pending.1 == .background {
                pending.2.cancel(); await runner.cancelBackground(); _ = try? await pending.2.value
            } else { return try await pending.2.value }
        }
        let id = UUID()
        let task = Task { try await self.performResolve(track, priority: priority, fresh: fresh) }
        pendingStreams[track.id] = (id, priority, task)
        defer { if pendingStreams[track.id]?.0 == id { pendingStreams.removeValue(forKey: track.id) } }
        return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
    }
    private func performResolve(_ track: Track, priority: ResolvePriority, fresh: Bool) async throws -> ResolvedStream {
        if !fresh, let stream = streams[track.id], stream.isValid { return stream }
        try checkFailure(track.id)
        do {
            let exe = try await executable(priority: priority)
            // HLS live streams may expose muxed renditions only. AVPlayer consumes them
            // without a video layer; prefer the lowest-bandwidth native HLS fallback.
            let format = "bestaudio[ext=m4a]/bestaudio[acodec^=mp4a]/bestaudio[protocol*=m3u8]/worst[protocol*=m3u8][acodec^=mp4a]"
            let data = try await runner.run(exe, arguments: baseArguments() + ["--no-playlist", "-f", format, "--dump-single-json", "--", track.url.absoluteString], priority: priority)
            let result = try Self.parseStream(data, fallback: track)
            streams[track.id] = result
            if streams.count > 64, let oldest = streams.min(by: { $0.value.resolvedAt < $1.value.resolvedAt })?.key { streams.removeValue(forKey: oldest) }
            try? Paths.write(streams, to: root.appendingPathComponent("streams.json"))
            return result
        } catch {
            if !(error is CancellationError) { recordFailure(track.id) }; throw error
        }
    }
    public func cached(_ id: String) -> ResolvedStream? { streams[id].flatMap { $0.isValid ? $0 : nil } }
    public func cancelBackground() async { await runner.cancelBackground() }
    private func checkFailure(_ id: String) throws {
        if let until = failedUntil[id], until > Date() { throw GeetError.message("This link failed recently. It can be tried again in \(max(1, Int(until.timeIntervalSinceNow / 60) + 1)) minutes.") }
    }
    private func recordFailure(_ id: String) {
        failedUntil = failedUntil.filter { $0.value > Date() }
        if failedUntil.count >= 128 { failedUntil.removeValue(forKey: failedUntil.min { $0.value < $1.value }!.key) }
        failedUntil[id] = Date().addingTimeInterval(600)
    }

    public static func parseCollection(_ data: Data, link: YouTubeLink) throws -> Collection {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw GeetError.message("YouTube returned unreadable playlist information.") }
        let items = json["entries"] as? [[String: Any]] ?? [json]
        let tracks = items.prefix(1000).compactMap(parseTrack)
        guard !tracks.isEmpty else { throw GeetError.message("This playlist has no available tracks. It may be private or empty.") }
        let title = json["title"] as? String ?? tracks[0].title
        var collection = Collection(id: link.isPlaylist ? "playlist:\(link.id)" : "video:\(link.id)", title: title,
                                    creator: json["uploader"] as? String ?? json["channel"] as? String ?? tracks[0].artist,
                                    source: link.url, thumbnail: thumbnail(json) ?? tracks[0].thumbnail, tracks: tracks)
        collection.truncated = (json["playlist_count"] as? Int ?? tracks.count) > 1000
        return collection
    }
    public static func parseTrack(_ json: [String: Any]) -> Track? {
        guard let id = json["id"] as? String, id.count == 11,
              let title = json["title"] as? String,
              !["[Private video]", "[Deleted video]"].contains(title),
              !["private", "premium_only", "subscriber_only"].contains(json["availability"] as? String ?? "") else { return nil }
        return Track(id: id, title: title, artist: json["channel"] as? String ?? json["uploader"] as? String ?? "YouTube",
                     duration: json["duration"] as? Double, thumbnail: thumbnail(json) ?? URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"),
                     isLive: json["is_live"] as? Bool == true || json["live_status"] as? String == "is_live")
    }
    public static func parseStream(_ data: Data, fallback: Track) throws -> ResolvedStream {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["url"] as? String, let url = URL(string: text), url.scheme == "https" else {
            throw GeetError.message("No native audio stream is available for this video.")
        }
        let expiry = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "expire" }?.value.flatMap(Double.init)
        return ResolvedStream(track: parseTrack(json) ?? fallback, url: url, headers: json["http_headers"] as? [String: String] ?? [:],
                              formatID: json["format_id"] as? String ?? "140",
                              expiresAt: expiry.map(Date.init(timeIntervalSince1970:)) ?? Date().addingTimeInterval(3600),
                              isHLS: (json["protocol"] as? String ?? "").contains("m3u8"))
    }
    private static func thumbnail(_ json: [String: Any]) -> URL? {
        if let thumbs = json["thumbnails"] as? [[String: Any]],
           let best = thumbs.filter({ ($0["width"] as? Int ?? 480) <= 1280 }).last,
           let text = best["url"] as? String { return URL(string: text) }
        return (json["thumbnail"] as? String).flatMap(URL.init(string:))
    }
}
