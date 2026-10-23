import Foundation

public struct DiscoverCategory: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String?
    public let items: [DiscoverPick]

    public init(id: String, title: String, subtitle: String? = nil, items: [DiscoverPick]) {
        self.id = id; self.title = title; self.subtitle = subtitle; self.items = items
    }
}

public struct DiscoverFeed: Codable, Sendable {
    public static let maximumBytes = 256 * 1024
    public let schemaVersion: Int
    public let categories: [DiscoverCategory]

    public init(schemaVersion: Int = 1, categories: [DiscoverCategory]) {
        self.schemaVersion = schemaVersion; self.categories = categories
    }

    public static let bundled: DiscoverFeed = {
        guard let url = Bundle.module.url(forResource: "discover-v1", withExtension: "json"),
              let data = try? Data(contentsOf: url), let feed = try? decode(data) else {
            preconditionFailure("The bundled Discover feed is missing or invalid")
        }
        return feed
    }()

    public static func decode(_ data: Data) throws -> DiscoverFeed {
        guard data.count <= maximumBytes else { throw DiscoverFeedError.invalidFeed }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }

    public func validated() throws -> Self {
        guard schemaVersion == 1, (1...5).contains(categories.count),
              Set(categories.map(\.id)).count == categories.count else { throw DiscoverFeedError.invalidFeed }
        for category in categories {
            guard Self.validID(category.id), Self.validText(category.title, limit: 100),
                  category.subtitle.map({ Self.validText($0, limit: 180) }) ?? true,
                  (3...10).contains(category.items.count),
                  Set(category.items.map(\.id)).count == category.items.count else { throw DiscoverFeedError.invalidFeed }
            for pick in category.items {
                guard Self.validID(pick.id), Self.validText(pick.title, limit: 120),
                      Self.validText(pick.creator, limit: 100),
                      pick.mood.map({ Self.validText($0, limit: 180) }) ?? true,
                      (try? YouTubeLink("https://www.youtube.com/watch?v=\(pick.videoID)"))?.id == pick.videoID,
                      pick.kind != .playlist || pick.playlistID != nil,
                      pick.kind != .radio || pick.playlistID == nil else { throw DiscoverFeedError.invalidFeed }
                if let id = pick.playlistID {
                    guard (try? YouTubeLink("https://www.youtube.com/playlist?list=\(id)"))?.id == id else { throw DiscoverFeedError.invalidFeed }
                }
            }
        }
        return self
    }

    private static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 80 && value.utf8.allSatisfy {
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95
        }
    }
    private static func validText(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= limit &&
            !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

public enum DiscoverFeedError: Error { case invalidFeed, invalidEndpoint, invalidResponse }

/// Preview identity cannot collide with a saved collection. Saving makes a copy;
/// the running preview and its queue keep their identity and playback position.
public enum DiscoverPlayback {
    public static func preview(_ collection: Collection) -> Collection {
        var copy = collection
        copy.id = "discover:\(collection.id)"; copy.keepsOffline = false
        copy.resumeIndex = 0; copy.resumePosition = 0
        return copy
    }
    public static func savedCopy(_ preview: Collection, for pick: DiscoverPick) -> Collection {
        var copy = preview
        copy.id = pick.collectionID; copy.keepsOffline = false
        copy.resumeIndex = 0; copy.resumePosition = 0; copy.addedAt = Date()
        return copy
    }
}

public actor DiscoverFeedClient {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private struct Cache: Codable {
        var endpoint: URL
        var feed: DiscoverFeed
        var etag: String?
        var modified: String?
        var checked: Date
    }
    private let endpoint: URL
    private let file: URL
    private let transport: Transport
    private var cache: Cache?
    public static let refreshInterval: TimeInterval = 30 * 60

    public init(endpoint: URL, cacheFile: URL, transport: @escaping Transport = { try await DiscoverFeedClient.download($0) }) {
        self.endpoint = endpoint; self.file = cacheFile; self.transport = transport
        cache = Self.readCache(cacheFile, endpoint: endpoint)
    }

    public nonisolated static func cachedFeed(at file: URL, endpoint: URL) -> DiscoverFeed? {
        readCache(file, endpoint: endpoint)?.feed
    }
    private nonisolated static func readCache(_ file: URL, endpoint: URL) -> Cache? {
        guard let data = try? Data(contentsOf: file), data.count <= DiscoverFeed.maximumBytes * 2,
              let cached = try? JSONDecoder().decode(Cache.self, from: data), cached.endpoint == endpoint,
              (try? cached.feed.validated()) != nil else { return nil }
        return cached
    }

    public func refresh(force: Bool = false, now: Date = Date()) async throws -> DiscoverFeed {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil else {
            throw DiscoverFeedError.invalidEndpoint
        }
        if !force, let cache, (0..<Self.refreshInterval).contains(now.timeIntervalSince(cache.checked)) { return cache.feed }
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if force { request.setValue("no-cache", forHTTPHeaderField: "Cache-Control") }
        if let etag = cache?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = cache?.modified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await transport(request)
        try Task.checkCancellation()
        guard response.url?.scheme == "https" else { throw DiscoverFeedError.invalidResponse }
        let next: Cache
        if response.statusCode == 304, var previous = cache {
            previous.checked = now; next = previous
        } else {
            guard response.statusCode == 200,
                  response.mimeType == "application/json" else { throw DiscoverFeedError.invalidResponse }
            let feed = try DiscoverFeed.decode(data)
            next = Cache(endpoint: endpoint, feed: feed, etag: response.value(forHTTPHeaderField: "ETag"),
                         modified: response.value(forHTTPHeaderField: "Last-Modified"), checked: now)
        }
        cache = next
        // A full disk must not discard a successfully fetched feed in memory.
        try? Paths.write(next, to: file)
        return next.feed
    }

    public nonisolated static func download(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength <= DiscoverFeed.maximumBytes else { throw DiscoverFeedError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < DiscoverFeed.maximumBytes else { throw DiscoverFeedError.invalidFeed }
            data.append(byte)
        }
        return (data, response)
    }
}
