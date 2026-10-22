#if DEBUG
import AppKit
import AVFoundation
import MediaPlayer
import GeetCore

/// Exercises the same store actions used by the native interface. All state is
/// isolated under GEET_DATA_DIR. Private test links arrive through the environment
/// and are never copied into the shareable report or screenshots.
@MainActor
enum CompletionValidation {
    static func run(store: AppStore, capture: (String, URL) async throws -> Void) async -> Bool {
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GEET_VALIDATION_DIR"] ?? "/tmp/geet-completion")
        Paths.ensure(output)
        var report: [String: String] = [:]
        func record(_ key: String, _ passed: Bool, _ detail: String = "") {
            report[key] = (passed ? "PASS" : "FAIL") + (detail.isEmpty ? "" : ": " + detail)
            try? Paths.write(report, to: output.appendingPathComponent("library-report.json"))
        }
        func check(_ key: String, _ passed: Bool) throws {
            record(key, passed)
            if !passed { throw GeetError.message("Check failed: \(key)") }
        }
        func snapshot(_ screen: String, _ name: String) async throws {
            try await capture(screen, output.appendingPathComponent(name + ".png"))
        }
        func importLink(_ text: String) async throws {
            store.message = nil; store.add(text)
            try await until(seconds: 90) { !store.busy }
            if store.message != nil { throw GeetError.message("The test link could not be imported.") }
        }
        let player = store.player
        player.volume = 0
        defer { store.shutdown() }
        do {
            try check("fresh_library_is_empty", store.library.collections.isEmpty)
            try check("launch_does_not_spawn", await store.resolver.runner.starts == 0)
            try check("launch_has_no_player_or_clock", !player.hasMediaPipeline && !player.hasProgressObserver)
            try await snapshot("library", "03-empty-library")
            store.add("https://example.com/not-youtube")
            try check("invalid_link_has_error_without_process", store.message != nil && !store.busy)
            try check("invalid_link_no_process", await store.resolver.runner.starts == 0)
            store.message = nil
            try await snapshot("add", "04-add-link")

            // The curated card uses exactly the import/play path below.
            let pick = AppStore.discover.first { $0.id == "classroom" }!
            try await importLink(pick.url.absoluteString)
            guard let playlist = store.savedCollection(for: pick) else { throw GeetError.message("Discover import did not appear in the library.") }
            try check("discover_add_to_library", playlist.tracks.count > 1)
            let beforeDuplicate = await store.resolver.runner.starts
            store.add(pick.url.absoluteString)
            try check("duplicate_add_keeps_one_collection", store.library.collections.count == 1 && store.message != nil)
            try check("duplicate_add_does_not_resolve", await store.resolver.runner.starts == beforeDuplicate)
            store.message = nil
            try await importLink("https://www.youtube.com/watch?v=jNQXAC9IVRw")
            guard let short = store.library.collections.last else { throw GeetError.message("Video import is missing.") }
            store.moveToTop(short)
            try check("move_collection_to_top", store.library.collections.first?.id == short.id)
            store.flushSave()
            let restored = AppStore(root: store.root)
            try check("library_survives_relaunch", restored.library.collections.map(\.id) == store.library.collections.map(\.id))
            try check("relaunch_does_not_probe", await restored.resolver.runner.starts == 0)
            restored.shutdown()

            player.automaticCache = true
            store.play(short)
            try await ready(player)
            try check("library_video_native_playback", player.track?.id == short.tracks.first?.id)
            try check("now_playing_metadata", MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String == player.track?.title)
            try await snapshot("library", "05-library-playing")
            player.seek(5)
            try check("seek_saves_destination_immediately", (store.library.collections.first(where: { $0.id == short.id })?.resumePosition ?? 0) >= 4.9)
            try await until { (player.media?.currentTime().seconds ?? 0) >= 4.9 }
            player.pause(); store.flushSave()
            try check("pause_saves_position", (store.library.collections.first(where: { $0.id == short.id })?.resumePosition ?? 0) >= 4.9)
            player.enterDeepIdle()
            player.resume(); try await ready(player)
            try check("resume_restores_position", (player.media?.currentTime().seconds ?? 0) >= 4.9)
            player.pause(); player.enterDeepIdle()
            store.keepOffline(short)
            try await until(seconds: 90) { store.downloads.isEmpty }
            try check("keep_offline_finishes", await store.cache.isComplete(trackID: short.tracks[0].id))
            let offlineRequests = await store.cache.networkRequests, offlineStarts = await store.resolver.runner.starts
            player.resume(); try await ready(player)
            let resumedRequests = await store.cache.networkRequests, resumedStarts = await store.resolver.runner.starts
            let assetURL = (player.media?.currentItem?.asset as? AVURLAsset)?.url
            try check("saved_audio_needs_no_network_or_helper", resumedRequests == offlineRequests && resumedStarts == offlineStarts && assetURL?.host == "127.0.0.1" && player.usesOfflineAudio)
            player.pause(); player.enterDeepIdle()
            await store.cache.clearAutomatic()
            try check("clear_cache_preserves_pinned_audio", await store.cache.isComplete(trackID: short.tracks[0].id))
            store.removeOffline(short)
            try await until { !store.savedTrackIDs.contains(short.tracks[0].id) }
            try check("remove_offline_clears_saved_audio", !(await store.cache.isComplete(trackID: short.tracks[0].id)))
            store.remove(short)
            try check("remove_current_collection_clears_player", player.track == nil && !player.hasMediaPipeline && player.collectionID == nil)

            // Exercise every curated card as a real native stream, including radio.
            for candidate in AppStore.discover {
                do {
                    if store.savedCollection(for: candidate) == nil { try await importLink(candidate.url.absoluteString) }
                    guard let saved = store.savedCollection(for: candidate) else { throw GeetError.message("Missing curated collection.") }
                    let libraryCount = store.library.collections.count
                    store.playDiscover(candidate)
                    try await ready(player, seconds: 65)
                    try check("discover_\(candidate.id)_preview_is_separate", player.collectionID == candidate.previewID && store.library.collections.count == libraryCount)
                    record("discover_\(candidate.id)_native_playback", true, "\(saved.tracks.count) available entries")
                    store.playDiscover(candidate)
                    try check("discover_\(candidate.id)_pause_matches_icon", !player.isPlaying)
                    player.enterDeepIdle()
                } catch {
                    record("discover_\(candidate.id)_native_playback", false, "The curated link could not be played.")
                    player.stop(); store.message = nil; player.error = nil
                }
            }
            store.moveToTop(playlist)
            store.play(playlist, index: 1); try await ready(player, seconds: 65)
            player.toggleShuffle()
            let shuffledStart = player.currentIndex
            player.next(); try await ready(player, seconds: 65)
            try check("shuffle_advances_to_different_occurrence", player.currentIndex != shuffledStart)
            player.seek(0); player.previous(); try await ready(player, seconds: 65)
            try check("shuffle_previous_restores_history", player.currentIndex == shuffledStart)
            player.toggleShuffle()
            try await snapshot("detail", "06-current-track")
            try await snapshot("settings", "07-settings-with-transport")
            try await snapshot("discover", "08-discover-saved")
            try await snapshot("search", "09-library-search")
            player.pause(); player.enterDeepIdle()
            let row = store.library.collections.firstIndex(where: { $0.id == playlist.id })!
            store.library.collections[row].resumeIndex = 1
            store.library.collections[row].resumePosition = 12
            let originalDate = store.library.collections[row].addedAt
            store.refresh(store.library.collections[row])
            try await until(seconds: 90) { !store.busy }
            let refreshed = store.library.collections.first { $0.id == playlist.id }
            try check("refresh_preserves_resume_and_order", store.message == nil && refreshed?.resumeIndex == 1 && refreshed?.resumePosition == 12 && refreshed?.addedAt == originalDate)

            store.add(AppStore.discover[0].url.absoluteString)
            store.message = nil
            store.add("https://www.youtube.com/watch?v=aqz-KE-bpKQ")
            store.cancelImport()
            try await Task.sleep(for: .milliseconds(300))
            try check("cancel_import_leaves_no_busy_state", !store.busy && !store.library.collections.contains(where: { $0.id == "video:aqz-KE-bpKQ" }))

            if let privateLink = ProcessInfo.processInfo.environment["GEET_UNLISTED_URL"] {
                do {
                    try await importLink(privateLink)
                    let link = try YouTubeLink(privateLink)
                    guard let saved = store.library.collections.first(where: { $0.source == link.url }), saved.tracks.count > 1 else {
                        throw GeetError.message("The private test playlist is missing.")
                    }
                    record("unlisted_playlist_import", true)
                    store.play(saved, index: 0); try await ready(player, seconds: 65)
                    record("unlisted_playlist_native_playback", true)
                    store.remove(saved)
                } catch {
                    // No private title, URL, identifier, or extractor error in the report.
                    try? (store.message ?? player.error ?? error.localizedDescription).write(to: output.appendingPathComponent("private-test-error.txt"), atomically: true, encoding: .utf8)
                    record("unlisted_playlist_native_playback", false, "The provided test playlist could not be played.")
                    player.stop(); store.message = nil; player.error = nil
                }
            } else { report["unlisted_playlist_native_playback"] = "NOT RUN: supply GEET_UNLISTED_URL" }
            record("final_pipeline_released", !player.hasMediaPipeline && !player.hasProgressObserver)
        } catch {
            record("suite_error", false, error.localizedDescription)
        }
        report["finished"] = ISO8601DateFormatter().string(from: Date())
        try? Paths.write(report, to: output.appendingPathComponent("library-report.json"))
        return report["final_pipeline_released"] == "PASS" && !report.values.contains(where: { $0.hasPrefix("FAIL") })
    }

    static func verifyDeepIdle(tools: URL) async -> Bool {
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GEET_VALIDATION_DIR"] ?? "/tmp/geet-deep-idle")
        let resolver = Resolver(root: output, bundledTools: tools)
        let player = Player(resolver: resolver, cache: MediaCache(root: output.appendingPathComponent("Media")), mediaCommands: false)
        player.volume = 0
        var report: [String: String] = [:]
        defer { player.shutdown(); try? Paths.write(report, to: output.appendingPathComponent("deep-idle-report.json")) }
        do {
            let collection = try await resolver.importCollection(YouTubeLink("https://www.youtube.com/watch?v=jNQXAC9IVRw"))
            player.play(collection); try await ready(player)
            player.pause()
            let starts = await resolver.runner.starts, began = Date()
            report["paused_at"] = ISO8601DateFormatter().string(from: began)
            try Paths.write(report, to: output.appendingPathComponent("deep-idle-report.json"))
            try await Task.sleep(for: .seconds(540))
            let checkpoint = Date().timeIntervalSince(began)
            report["before_checkpoint_seconds"] = String(checkpoint)
            report["pipeline_retained_before_600_seconds"] = checkpoint < 600 && player.hasMediaPipeline ? "PASS" : "FAIL"
            try await Task.sleep(for: .seconds(max(1, 602 - Date().timeIntervalSince(began))))
            report["pipeline_released_after_600_seconds"] = !player.hasMediaPipeline && player.isSleeping && !player.hasProgressObserver ? "PASS" : "FAIL"
            report["paused_without_helper_launches"] = await resolver.runner.starts == starts ? "PASS" : "FAIL"
            report["elapsed_seconds"] = String(Date().timeIntervalSince(began))
            player.resume(); try await ready(player)
            report["warm_resume_without_helper"] = await resolver.runner.starts == starts ? "PASS" : "FAIL"
            player.pause(); player.enterDeepIdle()
        } catch { report["error"] = error.localizedDescription }
        report["finished"] = ISO8601DateFormatter().string(from: Date())
        return report["warm_resume_without_helper"] == "PASS" && report["pipeline_retained_before_600_seconds"] == "PASS"
            && report["pipeline_released_after_600_seconds"] == "PASS" && report["paused_without_helper_launches"] == "PASS" && report["error"] == nil
    }

    static func verifyAudio(tools: URL) async -> Bool {
        let output = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GEET_VALIDATION_DIR"] ?? "/tmp/geet-audio")
        let cache = MediaCache(root: output.appendingPathComponent("Media"))
        let resolver = Resolver(root: output, bundledTools: tools)
        let player = Player(resolver: resolver, cache: cache, mediaCommands: false)
        player.volume = 0
        var report: [String: String] = [:]
        func record(_ key: String, _ passed: Bool) {
            report[key] = passed ? "PASS" : "FAIL"
            try? Paths.write(report, to: output.appendingPathComponent("audio-report.json"))
        }
        defer { player.shutdown() }
        do {
            let short = try await resolver.importCollection(YouTubeLink("https://www.youtube.com/watch?v=jNQXAC9IVRw"))
            player.play(short); try await ready(player)
            record("recorded_native_duration_matches_metadata", abs((player.media?.currentItem?.duration.seconds ?? 0) - (player.track?.duration ?? 0)) < 2)
            var savedPosition = 0.0
            player.onSnapshot = { _, _, position in savedPosition = position }
            player.seek(5); player.pause()
            record("immediate_pause_does_not_lose_seek", savedPosition >= 4.9 && savedPosition < 6)
            player.enterDeepIdle()
            let long = Collection(id: "audio-long", title: "Long mix timing", creator: "Chillhop Music", source: URL(string: "https://www.youtube.com/watch?v=4fWLbK1b88M")!,
                                  tracks: [Track(id: "4fWLbK1b88M", title: "Chill Study Beats 8", duration: 7237)])
            player.play(long); try await ready(player, seconds: 90)
            record("long_mix_native_duration_matches_metadata", abs((player.media?.currentItem?.duration.seconds ?? 0) - (player.track?.duration ?? 0)) < 2)
            let before = RuntimeValidation.sample()
            let began = Date(), clockBefore = player.media?.currentTime().seconds ?? 0
            try await Task.sleep(for: .seconds(30))
            let after = RuntimeValidation.sample()
            let elapsed = Date().timeIntervalSince(began)
            let requests = await cache.networkRequests
            report["range_requests_after_30_seconds"] = String(requests)
            report["resident_bytes_before"] = String(before.1); report["resident_bytes_after"] = String(after.1)
            report["sample_seconds"] = String(elapsed)
            report["steady_playback_cpu_percent"] = String((after.0 - before.0) / elapsed * 100)
            report["native_duration_seconds"] = String(player.media?.currentItem?.duration.seconds ?? 0)
            record("streaming_does_not_download_entire_long_mix", requests < 16)
            record("streaming_does_not_retain_audio_on_disk", await cache.snapshot().isEmpty)
            record("streaming_memory_cache_is_bounded", await cache.memoryBytes() <= 6 * Int(MediaCache.chunkSize))
            record("playback_clock_advances_in_real_time", abs((player.media?.currentTime().seconds ?? 0) - clockBefore - elapsed) < 2)
            let destination = (player.media?.currentItem?.duration.seconds ?? 7237) - 60
            let beforeSeek = await cache.networkRequests
            player.seek(destination)
            try await until { abs((player.media?.currentTime().seconds ?? 0) - destination) < 3 && player.media?.timeControlStatus == .playing }
            try await Task.sleep(for: .seconds(2))
            record("long_mix_seek_near_end", (player.media?.currentTime().seconds ?? 0) >= destination)
            record("long_mix_seek_fetches_only_needed_fragments", await cache.networkRequests - beforeSeek < 12)
            player.pause(); player.enterDeepIdle()
            record("pipeline_released", !player.hasMediaPipeline && !player.hasProgressObserver)
        } catch { report["error"] = error.localizedDescription + "; " + (player.error ?? "") }
        report["finished"] = ISO8601DateFormatter().string(from: Date())
        try? Paths.write(report, to: output.appendingPathComponent("audio-report.json"))
        return report["pipeline_released"] == "PASS" && report["error"] == nil && !report.values.contains("FAIL")
    }

    private static func ready(_ player: Player, seconds: Double = 45) async throws {
        try await until(seconds: seconds) {
            player.media?.currentItem?.status == .readyToPlay && player.media?.timeControlStatus == .playing && (player.media?.currentTime().seconds ?? 0) > 0.3
        }
    }
    private static func until(seconds: Double = 45, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw GeetError.message("A test operation did not finish within \(Int(seconds)) seconds.") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
#endif
