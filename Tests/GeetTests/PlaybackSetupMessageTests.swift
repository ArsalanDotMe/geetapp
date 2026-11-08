import Foundation
import Testing
@testable import GeetCore
@testable import Geet

@Suite @MainActor struct PlaybackSetupMessageTests {
    @Test(arguments: [false, true])
    func backgroundFailureIsVisibleWithoutAnAlert(existingTool: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geet-setup-message-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let tools = root.appendingPathComponent("tools")
        if existingTool {
            try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
            let tool = tools.appendingPathComponent("yt-dlp")
            try "#!/bin/sh\necho 2026.01.01\n".write(to: tool, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        }
        let updater = ExtractorUpdater(root: root, transport: { _, _ in throw URLError(.notConnectedToInternet) }, validate: { _, _ in })
        let resolver = Resolver(root: root, bundledTools: tools, allowExternalTools: false, updater: updater)
        let store = AppStore(root: root, playbackResolver: resolver)
        defer { store.shutdown() }
        store.preparePlayback()
        #expect(store.checkingPlayback)
        try await finished(store)
        #expect(store.dependencyText.contains("internet connection"))
        #expect(store.dependencyText.contains("Check again"))
        #expect(store.dependencyText.hasPrefix("Playback is ready.") == existingTool)
        #expect(store.message == nil)
        #expect(store.player.error == nil)
        store.recheck()
        try await finished(store)
        #expect(store.dependencyText.contains("internet connection"))
        #expect(store.dependencyText.hasPrefix("Playback is ready.") == existingTool)
        #expect(store.message == nil)
    }
    private func finished(_ store: AppStore) async throws {
        let deadline = Date().addingTimeInterval(5)
        while store.checkingPlayback {
            guard Date() < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
