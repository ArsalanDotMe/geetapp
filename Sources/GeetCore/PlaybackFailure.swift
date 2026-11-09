import Foundation

public enum ExtractorSetupFailure: String, Error, Codable, Sendable, CaseIterable {
    case offline, timedOut, verification, diskFull, cannotSave, incompatible, unavailable

    static func classify(_ error: Error) -> Self {
        if let failure = error as? Self { return failure }
        if let failure = error as? ExtractorUpdater.UpdateError {
            return failure == .versionMismatch ? .incompatible : .verification
        }
        if error is DecodingError { return .verification }
        let system = error as NSError
        if system.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: system.code) {
            case .timedOut: return .timedOut
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return .offline
            case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .secureConnectionFailed: return .verification
            default: return .unavailable
            }
        }
        if (system.domain == NSCocoaErrorDomain && system.code == NSFileWriteOutOfSpaceError) ||
            (system.domain == NSPOSIXErrorDomain && system.code == 28) { return .diskFull }
        if system.domain == NSCocoaErrorDomain,
           (0..<1024).contains(system.code) { return .cannotSave }
        if system.domain == NSPOSIXErrorDomain, [1, 13, 30].contains(system.code) { return .cannotSave }
        if system.domain == NSPOSIXErrorDomain { return .incompatible }
        return .unavailable
    }
}

public enum YouTubeFailure: Error, Sendable, Equatable {
    case unreadableResponse, audioRejected, rateLimited, temporarilyUnavailable
}
