import Foundation

/// A closed set of product messages. Provider and operating-system diagnostics
/// remain in the original error, rather than becoming the alert's primary copy.
public enum ListenerMessage {
    public enum Operation: CaseIterable, Sendable {
        case importLibrary, playback, download, saveLibrary, loginSetting, dependency, other
    }

    public static func forError(_ error: Error, during operation: Operation) -> String {
        if let error = error as? GeetError, case let .message(diagnostic) = error {
            if let message = knownMessages[diagnostic] { return message }
            if diagnostic.hasPrefix("geet needs yt-dlp ") || diagnostic.hasPrefix("The installed yt-dlp ") {
                return "YouTube playback isn't available. Please reinstall geet."
            }
            let prefix = "This link failed recently. It can be tried again in "
            let suffix = " minutes."
            if diagnostic.hasPrefix(prefix), diagnostic.hasSuffix(suffix),
               let minutes = Int(diagnostic.dropFirst(prefix.count).dropLast(suffix.count)), minutes > 0 {
                return "This link couldn't play recently. Try again in \(minutes) \(minutes == 1 ? "minute" : "minutes")."
            }
        }
        switch operation {
        case .importLibrary: return "This link couldn't be opened. Check that it's public or unlisted."
        case .playback: return "This track couldn't be played. Try again."
        case .download: return "This playlist couldn't be saved offline. Try again."
        case .saveLibrary: return "Your library couldn't be saved. Try again."
        case .loginSetting: return "geet couldn't change this setting. Try again in System Settings."
        case .dependency: return "YouTube playback isn't available. Please reinstall geet."
        case .other: return "Something couldn't be completed. Please try again."
        }
    }

    private static let knownMessages: [String: String] = [
        "Paste a YouTube playlist, mix, or live video link.": "Paste a YouTube playlist, mix, or live radio link.",
        "That link doesn’t contain a playlist or video. Copy its Share link from YouTube.": "This link doesn't contain a playlist or video. Copy the Share link from YouTube.",
        "Live radio is available online only.": "Live radio needs an internet connection.",
        "This part of the mix isn’t saved offline yet.": "This part of the mix isn't saved offline yet.",
        "The audio server couldn’t provide a complete audio segment.": "This track couldn't finish loading. Try again.",
        "The audio segment is incomplete.": "This track couldn't finish loading. Try again.",
        "The offline library has reached its 2,048-track limit. Remove a saved playlist to make room.": "You've reached the limit of 2,048 saved tracks. Remove a saved playlist to make room.",
        "Offline storage is full. Remove saved music in Settings to make room.": "Offline storage is full. Remove saved music to make room.",
        "YouTube returned unreadable playlist information.": "This playlist couldn't be loaded. Try again.",
        "This playlist has no available tracks. It may be private or empty.": "This playlist has no available tracks. It may be private or empty.",
        "No native audio stream is available for this video.": "This video can't be played in geet. Try another link.",
        "YouTube took too long to respond. Try again in a moment.": "YouTube took too long to respond. Try again in a moment.",
        "That playlist is too large to import safely.": "This playlist is too large to add. Try a smaller playlist."
    ]
}
