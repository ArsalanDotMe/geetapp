#if DEBUG
import AppKit
import AVFoundation
import GeetCore

/// Muted playback and persistence checks use isolated test state. No writes to
/// the owner's library or changes to system input permissions.
@MainActor enum DiscoverValidation {
    static func run(store: AppStore, capture: (String) async throws -> Void) async -> Bool {
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GEET_VALIDATION_DIR"]!)
        Paths.ensure(output)
        var report: [String: String] = [:]
        func record(_ name: String, _ passed: Bool, _ detail: String = "") throws {
            report[name] = (passed ? "PASS" : "FAIL") + (detail.isEmpty ? "" : ": " + detail)
            try Paths.write(report, to: output.appendingPathComponent("discover-report.json"))
            if !passed { throw GeetError.message("Discover validation failed: \(name)") }
        }
        func until(_ seconds: Double = 60, _ predicate: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(seconds)
            while !predicate() {
                if let error = store.message ?? store.player.error { throw GeetError.message(error) }
                guard Date() < deadline else { throw GeetError.message("Discover validation timed out") }
                try await Task.sleep(for: .milliseconds(80))
            }
        }
        let player = store.player
        player.volume = 0; player.automaticCache = false
        defer { store.shutdown() }
        do {
            try record("isolated_library_starts_empty", store.library.collections.isEmpty)
            try await until(25) { !store.discoverRefreshing }
            try record("live_feed_fetched", store.discoverError == nil && FileManager.default.fileExists(atPath: store.root.appendingPathComponent("discover-cache.json").path))
            try await Task.sleep(for: .milliseconds(500))
            // The same card actions used by the interface play real native audio
            // for each kind, without creating a saved collection.
            for kind in [DiscoverPick.Kind.radio, .mix, .playlist] {
                let pick = store.discoverFeed.categories.flatMap(\.items).first { $0.kind == kind }!
                store.playDiscover(pick)
                try await until(90) { store.discoverLoadingID == nil && player.isPlaying && player.media?.timeControlStatus == .playing && (player.media?.currentTime().seconds ?? 0) > 0.2 }
                try record("\(kind.rawValue)_preview_plays_without_library_add", player.collectionID == pick.previewID && store.library.collections.isEmpty && store.library.selectedID == nil)
                store.flushSave()
                let persisted = Paths.read(LibraryDocument.self, from: store.root.appendingPathComponent("library.json"))
                try record("\(kind.rawValue)_preview_does_not_persist", persisted?.collections.isEmpty == true && persisted?.selectedID == nil)
                store.playDiscover(pick)
                try record("\(kind.rawValue)_preview_pauses", !player.isPlaying && !player.isLoading)
                store.playDiscover(pick)
                try await until { player.isPlaying }
                try record("\(kind.rawValue)_preview_resumes", player.collectionID == pick.previewID)
                player.pause()
            }
            let pick = store.discoverFeed.categories.flatMap(\.items).first { $0.kind == .playlist }!
            let identity = player.collectionID, item = player.media?.currentItem
            store.addDiscover(pick)
            try record("add_is_separate_and_preserves_preview_queue", store.library.collections.count == 1 && store.savedCollection(for: pick)?.id == pick.collectionID && player.collectionID == identity && player.media?.currentItem === item)
            store.addDiscover(pick)
            try record("duplicate_add_does_not_duplicate", store.library.collections.count == 1)
            store.flushSave()
            let reloaded = AppStore(root: store.root)
            try record("only_explicit_add_survives_restart", reloaded.library.collections.count == 1 && reloaded.library.collections.first?.id == pick.collectionID)
            reloaded.shutdown()
            // A new selection supersedes a pending preview, even if metadata
            // finishes late. A library Play cancels pending Discover work too.
            let slow = store.discoverFeed.categories[0].items[0]
            let isolated = AppStore(root: output.appendingPathComponent("cancellation"), discoverImporter: { link in
                try? await Task.sleep(for: .milliseconds(300))
                return Collection(id: "video:\(link.id)", title: "Delayed", creator: "Test", source: link.url, tracks: [Track(id: link.id, title: "Delayed")])
            })
            isolated.playDiscover(slow); isolated.playDiscover(slow)
            try await Task.sleep(for: .milliseconds(450))
            try record("cancelled_preview_cannot_start_late", isolated.player.track == nil && isolated.discoverLoadingID == nil && isolated.library.collections.isEmpty)
            isolated.shutdown()
            try await capture("preview-after-add")
            try record("finished", true)
            return true
        } catch {
            report["error"] = "FAIL: \(error.localizedDescription)"
            try? Paths.write(report, to: output.appendingPathComponent("discover-report.json"))
            return false
        }
    }

}
#endif
