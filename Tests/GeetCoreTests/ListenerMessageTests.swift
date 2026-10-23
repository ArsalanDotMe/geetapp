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
