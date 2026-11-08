import Foundation
import Testing
@testable import GeetCore

@Suite struct ListenerMessageTests {
    @Test func systemAndProviderDetailsNeverReachThePrimaryMessage() {
        let diagnostic = "private-title https://media.example/audio?token=secret /Users/listener/library"
        let errors: [Error] = [GeetError.message(diagnostic), NSError(domain: "provider", code: 403,
            userInfo: [NSLocalizedDescriptionKey: diagnostic])]
        for operation in ListenerMessage.Operation.allCases {
            for error in errors {
                let message = ListenerMessage.forError(error, during: operation)
                #expect(!message.contains("private-title"))
                #expect(!message.contains("secret"))
                #expect(!message.contains("/Users/"))
                #expect(!message.contains("https://"))
                #expect(!message.isEmpty)
            }
        }
    }

    @Test func actionableFailuresKeepTheirMeaningAcrossOperations() {
        for operation in [ListenerMessage.Operation.importLibrary, .playback, .download] {
            #expect(ListenerMessage.forError(GeetError.message("Live radio is available online only."), during: operation)
                == "Live radio needs an internet connection.")
            #expect(ListenerMessage.forError(GeetError.message("Offline storage is full. Remove saved music in Settings to make room."), during: operation)
                == "Offline storage is full. Remove saved music to make room.")
        }
    }

    @Test func cooldownHasCorrectGrammarAndRejectsUnstructuredDetails() {
        #expect(ListenerMessage.forError(GeetError.message("This link failed recently. It can be tried again in 1 minutes."), during: .playback)
            == "This link couldn't play recently. Try again in 1 minute.")
        #expect(ListenerMessage.forError(GeetError.message("This link failed recently. It can be tried again in 7 minutes."), during: .playback)
            == "This link couldn't play recently. Try again in 7 minutes.")
        let malformed = GeetError.message("This link failed recently. It can be tried again in https://secret minutes.")
        #expect(ListenerMessage.forError(malformed, during: .playback) == "This track couldn't be played. Try again.")
    }

    @Test func fallbackMatchesTheOperation() {
        let error = NSError(domain: "unknown", code: -1)
        #expect(ListenerMessage.forError(error, during: .saveLibrary) == "Your library couldn't be saved. Try again.")
        #expect(ListenerMessage.forError(error, during: .loginSetting) == "geet couldn't change this setting. Try again in System Settings.")
        #expect(ListenerMessage.forError(error, during: .importLibrary) == "This link couldn't be opened. Check that it's public or unlisted.")
    }
}

@Suite struct PlaybackFailureMessageTests {
    @Test(arguments: ExtractorSetupFailure.allCases)
    func setupFailuresExplainRecoveryWithoutTechnicalDetails(failure: ExtractorSetupFailure) {
        for operation in ListenerMessage.Operation.allCases {
            let message = ListenerMessage.forError(failure, during: operation)
            #expect(message.contains("Check again in Settings"))
            #expect(!message.contains("yt-dlp"))
            #expect(!message.contains("SHA"))
            #expect(!message.contains("reinstall"))
        }
        let background = ListenerMessage.playbackUpdateFailure(failure, playbackAvailable: true)
        #expect(background.hasPrefix("Playback is ready. "))
        #expect(ListenerMessage.playbackUpdateFailure(failure, playbackAvailable: false) == ListenerMessage.forError(failure, during: .dependency))
    }

    @Test(arguments: [
        ("ERROR: Private video. Sign in", "This video is private."),
        ("ERROR: This video is not available in your country", "This video isn't available in your country."),
        ("ERROR: Sign in to confirm you're not a bot", "YouTube is asking you to sign in"),
        ("ERROR: HTTP Error 429: Too Many Requests", "YouTube is limiting requests."),
        ("ERROR: Video unavailable", "This video isn't available."),
        ("ERROR: Requested format is not available", "geet couldn't get playable audio"),
        ("ERROR: Unable to download webpage: timed out", "YouTube took too long"),
        ("ERROR: HTTP Error 403: Forbidden", "YouTube refused the audio request.")
    ])
    func providerFailuresBecomePlainMessages(diagnostic: String, expected: String) {
        let message = ListenerMessage.forError(GeetError.message(diagnostic + " https://media.test/?token=secret /Users/listener"), during: .playback)
        #expect(message.hasPrefix(expected))
        #expect(!message.contains("secret")); #expect(!message.contains("/Users/")); #expect(!message.contains("ERROR:"))
    }

    @Test(arguments: ["not JSON", "[]", "null"])
    func unreadableResponsesExplainTheNextStep(json: String) throws {
        let data = Data(json.utf8), track = Track(id: "xyEpFjZ_uiE", title: "One")
        let link = try YouTubeLink("https://youtu.be/xyEpFjZ_uiE")
        for parse in [{ _ = try Resolver.parseStream(data, fallback: track) }, { _ = try Resolver.parseCollection(data, link: link) }] {
            do { try parse(); Issue.record("Invalid YouTube output must fail") }
            catch {
                #expect(error is YouTubeFailure)
                #expect(ListenerMessage.forError(error, during: .importLibrary).contains("couldn't read"))
                #expect(ListenerMessage.forError(error, during: .importLibrary).contains("Check again in Settings"))
            }
        }
    }

    @Test func downloadFailureClassificationPreservesTheCause() {
        #expect(ExtractorSetupFailure.classify(URLError(.notConnectedToInternet)) == .offline)
        #expect(ExtractorSetupFailure.classify(URLError(.timedOut)) == .timedOut)
        #expect(ExtractorSetupFailure.classify(URLError(.serverCertificateUntrusted)) == .verification)
        #expect(ExtractorSetupFailure.classify(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)) == .diskFull)
        #expect(ExtractorSetupFailure.classify(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)) == .cannotSave)
        #expect(ExtractorSetupFailure.classify(ExtractorUpdater.UpdateError.versionMismatch) == .incompatible)
        #expect(ExtractorSetupFailure.classify(ExtractorUpdater.UpdateError.checksumMismatch) == .verification)
        #expect(ListenerMessage.forError(URLError(.notConnectedToInternet), during: .playback).contains("internet connection"))
    }
}
