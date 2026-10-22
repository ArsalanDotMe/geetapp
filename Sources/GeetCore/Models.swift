import Foundation

public enum GeetError: LocalizedError, Equatable {
    case message(String)
    public var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

public struct YouTubeLink: Hashable, Sendable {
    public let id: String
    public let isPlaylist: Bool
    public var url: URL {
        URL(string: isPlaylist ? "https://www.youtube.com/playlist?list=\(id)" : "https://www.youtube.com/watch?v=\(id)")!
    }
    public init(_ text: String) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), let host = url.host?.lowercased(),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be"].contains(host),
              url.user == nil, url.password == nil, url.port == nil else {
            throw GeetError.message("Paste a YouTube playlist, mix, or live video link.")
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let list = query.first(where: { $0.name == "list" })?.value, Self.valid(list), list.count <= 150 {
            id = list; isPlaylist = true; return
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String?
        if host.hasSuffix("youtu.be") { candidate = parts.first }
        else if ["live", "shorts", "embed"].contains(parts.first ?? "") { candidate = parts.dropFirst().first }
        else { candidate = query.first(where: { $0.name == "v" })?.value }
        guard let candidate, candidate.count == 11, Self.valid(candidate) else {
            throw GeetError.message("That link doesn’t contain a playlist or video. Copy its Share link from YouTube.")
        }
        id = candidate; isPlaylist = false
    }
    private static func valid(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }
}

public struct Track: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var duration: Double?
    public var thumbnail: URL?
    public var isLive: Bool
    public var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }
    public init(id: String, title: String, artist: String = "YouTube", duration: Double? = nil, thumbnail: URL? = nil, isLive: Bool = false) {
        self.id = id; self.title = title; self.artist = artist; self.duration = duration; self.thumbnail = thumbnail; self.isLive = isLive
    }
}

public struct Collection: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var creator: String
    public var source: URL
    public var thumbnail: URL?
    public var tracks: [Track]
    public var addedAt: Date
    public var keepsOffline: Bool
    public var resumeIndex: Int
    public var resumePosition: Double
    public var truncated: Bool
    public var subtitle: String { tracks.count == 1 && tracks[0].isLive ? "\(creator) · Live" : "\(creator) · \(tracks.count) \(tracks.count == 1 ? "mix" : "tracks")" }
    public init(id: String, title: String, creator: String, source: URL, thumbnail: URL? = nil, tracks: [Track], keepsOffline: Bool = false) {
        self.id = id; self.title = title; self.creator = creator; self.source = source; self.thumbnail = thumbnail; self.tracks = tracks
        self.addedAt = Date(); self.keepsOffline = keepsOffline; self.resumeIndex = 0; self.resumePosition = 0; self.truncated = false
    }
}

public struct ResolvedStream: Codable, Sendable {
    public var track: Track
    public var url: URL
    public var headers: [String: String]
    public var formatID: String
    public var expiresAt: Date
    public var resolvedAt: Date
    public var isHLS: Bool
    public var isValid: Bool { expiresAt.timeIntervalSinceNow > 120 }
    public init(track: Track, url: URL, headers: [String: String] = [:], formatID: String = "140", expiresAt: Date = Date().addingTimeInterval(3600), isHLS: Bool = false) {
        self.track = track; self.url = url; self.headers = headers; self.formatID = formatID; self.expiresAt = expiresAt; self.resolvedAt = Date(); self.isHLS = isHLS
    }
}

public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one
    public var next: Self { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % 3] }
}

/// Queue entries are occurrence indices, preserving intentional duplicate videos.
public struct PlaybackQueue: Sendable {
    public private(set) var order: [Int] = []
    public private(set) var cursor = 0
    public var current: Int? { order.indices.contains(cursor) ? order[cursor] : nil }
    public init() {}
    public mutating func reset(count: Int, start: Int, shuffled: Bool) {
        guard count > 0 else { order = []; cursor = 0; return }
        let start = min(max(start, 0), count - 1)
        if shuffled { order = [start] + (0..<count).filter { $0 != start }.shuffled(); cursor = 0 }
        else { order = Array(0..<count); cursor = start }
    }
    /// Manual skips wrap; only natural track endings follow the repeat setting.
    public mutating func moveNext(repeatMode: RepeatMode, automatic: Bool = false) -> Int? {
        guard !order.isEmpty else { return nil }
        if automatic && repeatMode == .one { return current }
        if cursor + 1 < order.count { cursor += 1; return current }
        if !automatic || repeatMode == .all { cursor = 0; return current }
        return nil
    }
    public mutating func movePrevious() -> Int? {
        guard !order.isEmpty else { return nil }
        cursor = cursor > 0 ? cursor - 1 : order.count - 1
        return current
    }
    public func peekNext(repeatMode: RepeatMode) -> Int? {
        if repeatMode == .one { return current }
        if cursor + 1 < order.count { return order[cursor + 1] }
        return repeatMode == .all ? order.first : nil
    }
}

public struct RecoveryBudget: Sendable {
    private var attempts: [String: Int] = [:]
    public init() {}
    public mutating func permit(_ trackID: String) -> Bool {
        let count = attempts[trackID, default: 0]
        guard count < 2 else { return false }
        if attempts.count >= 128 { attempts.removeAll() }
        attempts[trackID] = count + 1; return true
    }
    public mutating func reset(_ trackID: String) { attempts.removeValue(forKey: trackID) }
}

public enum Paths {
    public static var support: URL {
        if let override = ProcessInfo.processInfo.environment["GEET_DATA_DIR"] { return URL(fileURLWithPath: override, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Geet", isDirectory: true)
    }
    public static func ensure(_ url: URL) { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    public static func write<T: Encodable>(_ value: T, to url: URL) throws {
        ensure(url.deletingLastPathComponent()); try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }
    public static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }; return try? JSONDecoder().decode(type, from: data)
    }
}
