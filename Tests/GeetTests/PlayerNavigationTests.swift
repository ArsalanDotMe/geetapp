import Foundation
import Testing
import GeetCore
@testable import Geet

@Suite @MainActor struct PlayerNavigationTests {
    @Test(arguments: RepeatMode.allCases)
    func buttonsWrapAndPreviousMovesAfterThreeSeconds(mode: RepeatMode) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let player = Player(resolver: Resolver(root: root), cache: MediaCache(root: root), mediaCommands: false)
        defer { player.shutdown() }
        let tracks = (0..<3).map { Track(id: "track-\($0)", title: "Track \($0)", duration: 60) }
        let collection = Collection(id: "navigation", title: "Navigation", creator: "", source: tracks[0].url, tracks: tracks)
        player.repeatMode = mode
        player.play(collection, index: 2)
        player.next()
        #expect(player.currentIndex == 0)
        #expect(player.track?.id == tracks[0].id)
        player.seek(10)
        player.previous()
        #expect(player.currentIndex == 2)
        #expect(player.track?.id == tracks[2].id)
        #expect(player.clock.position == 0)
        player.previous()
        #expect(player.currentIndex == 1)
        player.next()
        #expect(player.currentIndex == 2)
        player.stop()
        player.next()
        player.previous()
        #expect(player.track == nil)
    }
}
