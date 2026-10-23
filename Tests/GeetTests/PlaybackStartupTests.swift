import AVFoundation
import Foundation
import Testing
import GeetCore
@testable import Geet

@Suite @MainActor struct PlaybackStartupTests {
    // Opt in to public-network/native audio measurements. Playback stays muted
    // and uses a disposable library, never the listener's saved music.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GEET_BENCHMARK_PLAYBACK"] == "1"))
    func measureNativeStartup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geet-startup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = ProcessInfo.processInfo.environment["GEET_BENCHMARK_TOOLS"].map { URL(fileURLWithPath: $0) }
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tools")
        let resolver = Resolver(root: root, bundledTools: tools, allowExternalTools: false)
        let cache = MediaCache(root: root.appendingPathComponent("Media"))
        let player = Player(resolver: resolver, cache: cache, mediaCommands: false)
        player.volume = 0
        defer { player.shutdown() }
        let denoVersion = try await resolver.runner.run(tools.appendingPathComponent("deno"), arguments: ["--version"])
        #expect(String(decoding: denoVersion, as: UTF8.self).hasPrefix("deno "))
        let ids = ["jNQXAC9IVRw", "4fWLbK1b88M"]
        for id in ids {
            let track = Track(id: id, title: "Startup measurement")
            let collection = Collection(id: id, title: "Startup measurement", creator: "", source: track.url, tracks: [track])
            for attempt in 0..<2 {
                let began = Date()
                player.play(collection, index: 0)
                var pipelineSeconds: Double?
                while (player.media?.currentTime().seconds ?? 0) < 0.1 {
                    if player.hasMediaPipeline, player.media != nil, pipelineSeconds == nil { pipelineSeconds = Date().timeIntervalSince(began) }
                    if let error = player.error { throw GeetError.message(error) }
                    guard Date().timeIntervalSince(began) < 60 else { throw GeetError.message("Startup timed out") }
                    try await Task.sleep(for: .milliseconds(20))
                }
                print("STARTUP id=\(id) attempt=\(attempt) pipeline_seconds=\(pipelineSeconds ?? -1) playing_seconds=\(Date().timeIntervalSince(began)) requests=\(await cache.networkRequests)")
                #expect(player.media?.timeControlStatus == .playing)
                let probe = try #require(await resolver.dependencyStatus())
                #expect(probe.path == tools.appendingPathComponent("yt-dlp/yt-dlp_macos").path)
                print("BUNDLED_EXTRACTOR path=\(probe.path) version=\(probe.version)")
                player.stop()
            }
        }
        // Compare import-to-play with and without the second extraction that
        // single-video Discover playback previously required.
        for duplicateExtraction in [true, false] {
            let importRoot = root.appendingPathComponent(duplicateExtraction ? "duplicate-import" : "shared-import")
            let importResolver = Resolver(root: importRoot, bundledTools: tools, allowExternalTools: false)
            let importCache = MediaCache(root: importRoot.appendingPathComponent("Media"))
            let importPlayer = Player(resolver: importResolver, cache: importCache, mediaCommands: false)
            importPlayer.volume = 0
            defer { importPlayer.shutdown() }
            let began = Date()
            let collection = try await importResolver.importCollection(YouTubeLink("https://youtube.com/watch?v=jNQXAC9IVRw"))
            if duplicateExtraction { _ = try await importResolver.resolve(collection.tracks[0], fresh: true) }
            importPlayer.play(collection, index: 0)
            while (importPlayer.media?.currentTime().seconds ?? 0) < 0.1 {
                if let error = importPlayer.error { throw GeetError.message(error) }
                guard Date().timeIntervalSince(began) < 60 else { throw GeetError.message("Import playback timed out") }
                try await Task.sleep(for: .milliseconds(20))
            }
            print("IMPORT duplicate_extraction=\(duplicateExtraction) playing_seconds=\(Date().timeIntervalSince(began)) helper_starts=\(await importResolver.runner.starts)")
            #expect(await importResolver.runner.starts == (duplicateExtraction ? 3 : 2))
            importPlayer.stop()
        }
        for warmAudio in [false, true] {
            let queueRoot = root.appendingPathComponent(warmAudio ? "warm-next" : "early-next")
            let first = try #require(await resolver.cached(ids[0]))
            try Paths.write([ids[0]: first], to: queueRoot.appendingPathComponent("streams.json"))
            let queueResolver = Resolver(root: queueRoot, bundledTools: tools, allowExternalTools: false)
            let queueCache = MediaCache(root: queueRoot.appendingPathComponent("Media"))
            let queuePlayer = Player(resolver: queueResolver, cache: queueCache, mediaCommands: false)
            queuePlayer.volume = 0
            defer { queuePlayer.shutdown() }
            let tracks = ids.map { Track(id: $0, title: "Queue startup measurement") }
            let collection = Collection(id: "queue", title: "Queue startup measurement", creator: "", source: tracks[0].url, tracks: tracks)
            queuePlayer.play(collection, index: 0)
            let deadline = Date().addingTimeInterval(60)
            while true {
                let starts = await queueResolver.runner.starts
                let bytes = await queueCache.memoryBytes()
                if starts >= 2 && (!warmAudio || bytes > Int(MediaCache.chunkSize)) { break }
                if let error = queuePlayer.error { throw GeetError.message(error) }
                guard Date() < deadline else { throw GeetError.message("Look-ahead timed out") }
                try await Task.sleep(for: .milliseconds(10))
            }
            let began = Date()
            queuePlayer.next()
            while (queuePlayer.media?.currentTime().seconds ?? 0) < 0.1 {
                if let error = queuePlayer.error { throw GeetError.message(error) }
                guard Date() < deadline else { throw GeetError.message("Next timed out") }
                try await Task.sleep(for: .milliseconds(20))
            }
            print("NEXT warmed_audio=\(warmAudio) playing_seconds=\(Date().timeIntervalSince(began)) helper_starts=\(await queueResolver.runner.starts) range_requests=\(await queueCache.networkRequests)")
            #expect(await queueResolver.runner.starts == 2) // One version probe and one extraction.
            #expect(await queueCache.networkRequests == 2) // One initial chunk per track.
            #expect(await queueCache.snapshot().isEmpty)
            #expect(await queueCache.memoryBytes() <= 6 * Int(MediaCache.chunkSize))
            queuePlayer.stop()
        }
    }
}
