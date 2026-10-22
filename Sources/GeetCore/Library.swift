import Foundation

public struct LibraryDocument: Codable, Sendable {
    public var collections: [Collection] = []
    public var selectedID: String?
    public var shuffle = false
    public var repeatMode: RepeatMode = .off
    public var volume: Float = 0.8
    public var automaticCache = false
    public init() {}
}

public struct DiscoverPick: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case radio = "Radio"
        case playlist = "Playlist"
        case mix = "Mix"
    }

    public let id: String
    public let title: String
    public let creator: String
    public let mood: String
    public let kind: Kind
    public let videoID: String
    public let playlistID: String?
    public var thumbnail: URL { URL(string: "https://i.ytimg.com/vi/\(videoID)/maxresdefault.jpg")! }
    public var url: URL { URL(string: playlistID.map { "https://www.youtube.com/playlist?list=\($0)" } ?? "https://www.youtube.com/watch?v=\(videoID)")! }
    public init(id: String, title: String, creator: String, mood: String, kind: Kind, videoID: String, playlistID: String? = nil) {
        self.id = id; self.title = title; self.creator = creator; self.mood = mood; self.kind = kind; self.videoID = videoID; self.playlistID = playlistID
    }
}
