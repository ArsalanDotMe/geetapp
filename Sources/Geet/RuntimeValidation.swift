#if DEBUG
import AppKit
import AVFoundation
import GeetCore

/// Opt-in integration harness, excluded from release builds. Uses a short public
/// video, a private data directory, muted playback, and no changes to the library.
@MainActor
enum RuntimeValidation {
    static func measureIdle(store: AppStore, destination: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let before = sample()
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                let after = sample()
                Task { @MainActor in
                    let starts = await store.resolver.runner.starts
                    let report: [String: Double] = ["sample_seconds": 15, "cpu_seconds": after.0 - before.0,
                        "average_cpu_percent": (after.0 - before.0) / 15 * 100,
                        "resident_bytes_before": Double(before.1), "resident_bytes_after": Double(after.1),
                        "resolver_process_starts": Double(starts), "progress_observer_count": store.player.hasProgressObserver ? 1 : 0,
                        "media_pipeline_count": store.player.hasMediaPipeline ? 1 : 0]
                    try? Paths.write(report, to: URL(fileURLWithPath: destination))
                    NSApp.terminate(nil)
                }
            }
        }
    }
    static func sample() -> (Double, UInt64) {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return (cpu, info.resident_size)
    }
    static func run(tools: URL) async -> Bool {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["GEET_VALIDATION_DIR"] ?? "/tmp/geet-runtime-validation")
        Paths.ensure(root)
        var checks: [String: String] = [:]
        let runner = ProcessRunner(), cache = MediaCache(root: root.appendingPathComponent("Media"))
        let resolver = Resolver(root: root, bundledTools: tools, runner: runner)
        let player = Player(resolver: resolver, cache: cache, idleDelay: 0.25, mediaCommands: false)
        player.volume = 0
        // Keep the first pass online even when re-running with an existing cache.
        player.offlineEnabled = false
        func record(_ name: String, _ passed: Bool, _ detail: String = "") {
            checks[name] = (passed ? "PASS" : "FAIL") + (detail.isEmpty ? "" : ": " + detail)
            try? Paths.write(checks, to: root.appendingPathComponent("report.json"))
        }
        do {
            record("no_process_at_initialization", await runner.starts == 0)
            let playlist = try await resolver.importCollection(YouTubeLink("https://www.youtube.com/playlist?list=PLt7bG0K25iXhu8bSbLsoWFBf-xSyLwy2_"))
            record("public_playlist_import", playlist.tracks.count > 1, "\(playlist.tracks.count) available tracks")
            let collection = try await resolver.importCollection(YouTubeLink("https://www.youtube.com/watch?v=jNQXAC9IVRw"))
            record("real_metadata_import", collection.tracks.count == 1)
            player.play(collection)
            try await until { player.media?.currentItem?.status == .readyToPlay && player.media?.timeControlStatus == .playing && (player.media?.currentTime().seconds ?? 0) > 0.5 }
            record("native_remote_audio_playback", player.isPlaying, "AVPlayer ready; playback clock advanced")
            player.panelVisible(true)
            record("open_panel_has_progress_observer", player.hasProgressObserver)
            player.panelVisible(false)
            record("closed_panel_has_no_progress_observer", !player.hasProgressObserver)
            let playingBefore = sample()
            try await Task.sleep(for: .seconds(5))
            let playingAfter = sample()
            checks["closed_panel_playback_cpu_percent"] = String(format: "%.4f", (playingAfter.0 - playingBefore.0) / 5 * 100)
            player.pause()
            try await Task.sleep(for: .milliseconds(400))
            record("paused_deadline_releases_pipeline", player.isSleeping && !player.hasMediaPipeline && !player.hasProgressObserver, "test deadline 0.25s; production deadline 600s")
            let starts = await runner.starts
            player.resume()
            try await until { player.media?.currentItem?.status == .readyToPlay && player.isPlaying }
            record("resume_reuses_stream_without_process", await runner.starts == starts)
            player.pause(); player.enterDeepIdle()
            let track = collection.tracks[0], stream = try await resolver.resolve(collection.tracks[0])
            try await cache.download(stream, pinned: true) { _ in }
            record("offline_download_complete", await cache.isComplete(trackID: track.id))
            player.offlineEnabled = true
            let network = await cache.networkRequests, processCount = await runner.starts
            player.resume()
            try await until { player.media?.currentItem?.status == .readyToPlay && player.media?.timeControlStatus == .playing && player.isPlaying && (player.media?.currentTime().seconds ?? 0) > 0.5 }
            let offlineRequests = await cache.networkRequests, offlineProcesses = await runner.starts
            record("native_offline_playback", offlineRequests == network && offlineProcesses == processCount, "native player served saved audio without outbound network requests or yt-dlp")
            player.pause(); player.enterDeepIdle()
            record("audio_memory_bound", await cache.memoryBytes() <= 6 * Int(MediaCache.chunkSize))
            let queue = Collection(id: "validation-queue", title: "Queue check", creator: "geet", source: track.url, tracks: [track, track])
            player.repeatMode = .off; player.play(queue, index: 0)
            try await until { player.media?.timeControlStatus == .playing }
            player.seek(max(0, player.clock.duration - 0.25))
            try await until { player.currentIndex == 1 && player.media?.timeControlStatus == .playing }
            record("automatic_next_track", true)
            player.repeatMode = .one
            let repeatOneItem = player.media?.currentItem
            player.seek(max(0, player.clock.duration - 0.25))
            try await until { player.media?.currentItem !== repeatOneItem && player.currentIndex == 1 && player.media?.timeControlStatus == .playing && (player.media?.currentTime().seconds ?? 100) < 2 }
            record("native_repeat_one", true)
            player.repeatMode = .all
            player.seek(max(0, player.clock.duration - 0.25))
            try await until { player.currentIndex == 0 && player.media?.timeControlStatus == .playing }
            record("native_repeat_all", true)
            player.pause(); player.enterDeepIdle()
            let live = Collection(id: "validation-live", title: "Lofi radio", creator: "Lofi Girl", source: URL(string: "https://youtube.com/watch?v=0sfDth4lMLc")!,
                                  tracks: [Track(id: "0sfDth4lMLc", title: "Lofi radio", isLive: true)])
            player.play(live)
            try await until(seconds: 45) { player.media?.currentItem?.status == .readyToPlay && player.media?.timeControlStatus == .playing && player.isPlaying }
            record("live_radio_native_playback", player.track?.isLive == true)
            player.pause(); player.enterDeepIdle()
            record("final_pipeline_released", !player.hasMediaPipeline)
        } catch {
            record("integration_error", false, error.localizedDescription + "; player: " + (player.error ?? "no app error") + "; item: " + (player.media?.currentItem?.error?.localizedDescription ?? "none") + "; status: \(player.media?.currentItem?.status.rawValue ?? -1)")
        }
        player.shutdown()
        checks["finished"] = ISO8601DateFormatter().string(from: Date())
        try? Paths.write(checks, to: root.appendingPathComponent("report.json"))
        return checks["final_pipeline_released"] == "PASS" && !checks.values.contains(where: { $0.hasPrefix("FAIL") })
    }
    private static func until(seconds: Double = 35, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            guard Date() < deadline else { throw GeetError.message("Playback did not become ready within \(Int(seconds)) seconds.") }
            try await Task.sleep(for: .milliseconds(150))
        }
    }
}
#endif
