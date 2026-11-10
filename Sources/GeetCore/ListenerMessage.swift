import Foundation

/// A closed set of product messages. Provider and operating-system diagnostics
/// remain in the original error, rather than becoming the alert's primary copy.
public enum ListenerMessage {
    public enum Operation: CaseIterable, Sendable {
        case importLibrary, playback, download, saveLibrary, loginSetting, dependency, other
    }

    public static func forError(_ error: Error, during operation: Operation) -> String {
        if let setup = error as? ExtractorSetupFailure { return setupMessage(setup, update: false) }
        if let youtube = error as? YouTubeFailure {
            switch youtube {
            case .unreadableResponse: return "YouTube sent a response geet couldn't read. Choose Check again in Settings, then retry the link."
            case .audioRejected: return "YouTube refused this audio stream. Try again later or try another link."
            case .rateLimited: return "YouTube is limiting requests. Wait a few minutes, then try again."
            case .temporarilyUnavailable: return "YouTube isn't responding right now. Try again in a few minutes."
            }
        }
        let system = error as NSError
        if system.domain == NSURLErrorDomain {
            if system.code == URLError.timedOut.rawValue { return "The connection took too long. Try again in a moment." }
            if [URLError.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].map(\.rawValue).contains(system.code) {
                return "Couldn't connect. Check your internet connection and try again."
            }
        }
        if system.domain == NSCocoaErrorDomain, system.code == NSFileWriteOutOfSpaceError {
            return "Your Mac is out of space. Free up some space and try again."
        }
        if let error = error as? GeetError, case let .message(diagnostic) = error {
            if let message = knownMessages[diagnostic] { return message }
            if diagnostic.hasPrefix("geet needs yt-dlp ") || diagnostic.hasPrefix("The installed yt-dlp ") {
                return "YouTube playback isn't ready. Choose Check again in Settings."
            }
            let prefix = "This link failed recently. It can be tried again in "
            let suffix = " minutes."
            if diagnostic.hasPrefix(prefix), diagnostic.hasSuffix(suffix),
               let minutes = Int(diagnostic.dropFirst(prefix.count).dropLast(suffix.count)), minutes > 0 {
                return "This link couldn't play recently. Try again in \(minutes) \(minutes == 1 ? "minute" : "minutes")."
            }
            if let message = youtubeMessage(diagnostic) { return message }
        }
        switch operation {
        case .importLibrary: return "This link couldn't be opened. Check that it's public or unlisted."
        case .playback: return "This track couldn't be played. Try again."
        case .download: return "This playlist couldn't be saved offline. Try again."
        case .saveLibrary: return "Your library couldn't be saved. Try again."
        case .loginSetting: return "geet couldn't change this setting. Try again in System Settings."
        case .dependency: return "Couldn't prepare YouTube playback. Choose Check again in Settings."
        case .other: return "Something couldn't be completed. Please try again."
        }
    }

    public static func playbackUpdateFailure(_ error: Error, playbackAvailable: Bool) -> String {
        guard playbackAvailable else { return forError(error, during: .dependency) }
        let detail = (error as? ExtractorSetupFailure).map { setupMessage($0, update: true) }
            ?? "Couldn't check for playback updates. Try Check again later."
        return "Playback is ready. " + detail
    }

    private static func setupMessage(_ failure: ExtractorSetupFailure, update: Bool) -> String {
        let files = update ? "the playback update" : "playback files"
        switch failure {
        case .offline: return "Couldn't download \(files). Check your internet connection, then choose Check again in Settings."
        case .timedOut: return "Downloading \(files) took too long. Choose Check again in Settings to retry."
        case .verification: return "The playback download couldn't be verified and wasn't installed. Choose Check again in Settings to retry."
        case .diskFull: return "There isn't enough space for \(files). Free up some space, then choose Check again in Settings."
        case .cannotSave: return "geet couldn't save \(files). Check your Mac's storage and permissions, then choose Check again in Settings."
        case .incompatible: return "The new playback files couldn't run on this Mac. Choose Check again in Settings, or check for a newer geet release."
        case .unavailable: return "The playback download isn't available right now. Choose Check again in Settings in a few minutes."
        }
    }

    private static func youtubeMessage(_ diagnostic: String) -> String? {
        let text = diagnostic.lowercased()
        if text.contains("private video") { return "This video is private. Try a public or unlisted link." }
        if text.contains("not available in your country") || text.contains("geo restricted") {
            return "This video isn't available in your country. Try another link."
        }
        if text.contains("members-only") || text.contains("join this channel") {
            return "This video requires a YouTube membership and can't be played in geet."
        }
        if text.contains("sign in") || text.contains("login required") {
            return "YouTube is asking you to sign in for this video. Try another link."
        }
        if text.contains("http error 429") || text.contains("too many requests") {
            return "YouTube is limiting requests. Wait a few minutes, then try again."
        }
        if text.contains("video unavailable") || text.contains("has been removed") || text.contains("deleted video") {
            return "This video isn't available. Try another link."
        }
        if text.contains("requested format is not available") || text.contains("no video formats found") || text.contains("extraction failed") {
            return "geet couldn't get playable audio from YouTube. Choose Check again in Settings, then retry the link."
        }
        if text.contains("timed out") { return "YouTube took too long to respond. Try again in a moment." }
        if text.contains("unable to download webpage") || text.contains("unable to connect") || text.contains("network is unreachable") {
            return "Couldn't connect to YouTube. Check your internet connection and try again."
        }
        if text.contains("http error 403") { return "YouTube refused the audio request. Wait a few minutes, then try again." }
        return nil
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
        "YouTube returned unreadable playlist information.": "YouTube sent a response geet couldn't read. Choose Check again in Settings, then retry the link.",
        "This playlist has no available tracks. It may be private or empty.": "This playlist has no available tracks. It may be private or empty.",
        "No native audio stream is available for this video.": "This video can't be played in geet. Try another link.",
        "YouTube took too long to respond. Try again in a moment.": "YouTube took too long to respond. Try again in a moment.",
        "That playlist is too large to import safely.": "This playlist is too large to add. Try a smaller playlist."
    ]
}
