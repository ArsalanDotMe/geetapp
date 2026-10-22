import Foundation
import Testing
@testable import GeetCore

@Suite struct LinkTests {
    @Test func normalizesPlaylistInsteadOfWatchContext() throws {
        let link = try YouTubeLink(" https://www.youtube.com/watch?v=xyEpFjZ_uiE&list=PL_test-123&index=8 ")
        #expect(link.isPlaylist); #expect(link.url.absoluteString == "https://www.youtube.com/playlist?list=PL_test-123")
    }
    @Test(arguments: ["https://youtu.be/xyEpFjZ_uiE?t=50", "https://youtube.com/live/xyEpFjZ_uiE", "https://music.youtube.com/watch?v=xyEpFjZ_uiE"])
    func normalizesVideos(_ text: String) throws { #expect(try YouTubeLink(text).id == "xyEpFjZ_uiE") }
    @Test(arguments: ["https://youtube.com.evil.test/watch?v=xyEpFjZ_uiE", "file:///tmp/video", "https://youtube.com/@LofiGirl", "https://user@youtube.com/watch?v=xyEpFjZ_uiE", "https://youtube.com:444/watch?v=xyEpFjZ_uiE", "https://youtu.be/../../tmp", "https://youtube.com/playlist?list=bad%3Btouch"])
    func rejectsUnsupportedOrUnsafeLinks(_ text: String) { #expect(throws: (any Error).self) { try YouTubeLink(text) } }
}

@Suite struct QueueTests {
    @Test func preservesOccurrencesAndHistory() {
        var queue = PlaybackQueue(); queue.reset(count: 8, start: 3, shuffled: true)
        #expect(queue.current == 3); #expect(Set(queue.order).count == 8)
        let next = queue.moveNext(repeatMode: .off)
        #expect(next != 3); #expect(queue.movePrevious() == 3)
    }
    @Test func repeatsAndStops() {
        var queue = PlaybackQueue(); queue.reset(count: 2, start: 0, shuffled: false)
        #expect(queue.moveNext(repeatMode: .one, automatic: true) == 0)
        #expect(queue.moveNext(repeatMode: .one) == 1)
        #expect(queue.moveNext(repeatMode: .off, automatic: true) == nil)
        #expect(queue.moveNext(repeatMode: .all) == 0)
        #expect(RepeatMode.off.next == .all); #expect(RepeatMode.all.next == .one); #expect(RepeatMode.one.next == .off)
    }
    @Test(arguments: RepeatMode.allCases, [false, true])
    func manualNavigationLoops(mode: RepeatMode, shuffled: Bool) {
        var queue = PlaybackQueue()
        queue.reset(count: 5, start: 0, shuffled: shuffled)
        let order = queue.order
        #expect(queue.movePrevious() == order.last)
        #expect(queue.moveNext(repeatMode: mode) == order.first)
        for expected in order.dropFirst() {
            #expect(queue.moveNext(repeatMode: mode) == expected)
        }
        #expect(queue.moveNext(repeatMode: mode) == order.first)
        for expected in order.reversed() {
            #expect(queue.movePrevious() == expected)
        }
    }
    @Test(arguments: RepeatMode.allCases)
    func emptyAndSingleTrackNavigation(mode: RepeatMode) {
        var queue = PlaybackQueue()
        #expect(queue.moveNext(repeatMode: mode) == nil)
        #expect(queue.movePrevious() == nil)
        queue.reset(count: 1, start: 0, shuffled: false)
        #expect(queue.moveNext(repeatMode: mode) == 0)
        #expect(queue.movePrevious() == 0)
        #expect(queue.moveNext(repeatMode: mode, automatic: true) == (mode == .off ? nil : 0))
    }
    @Test func emptyQueueAndInvalidSavedIndex() {
        var queue = PlaybackQueue(); queue.reset(count: 0, start: 30, shuffled: true); #expect(queue.current == nil)
        queue.reset(count: 2, start: 100, shuffled: false); #expect(queue.current == 1)
    }
    @Test func automaticRecoveryIsCappedPerTrack() {
        var budget = RecoveryBudget()
        let attempts = (0..<3).map { _ in budget.permit("one") }
        #expect(attempts == [true, true, false])
        let second = budget.permit("two"), exhausted = budget.permit("one")
        #expect(second); #expect(!exhausted)
        budget.reset("one"); let fresh = budget.permit("one"); #expect(fresh)
    }
}

@Suite struct MetadataTests {
    @Test func unavailableEntriesAreExcludedButDuplicatesSurvive() throws {
        let data = Data(#"{"title":"Study","uploader":"Creator","playlist_count":1001,"entries":[{"id":"xyEpFjZ_uiE","title":"One","duration":42},{"id":"xyEpFjZ_uiE","title":"One","duration":42},{"id":"01234567890","title":"[Private video]"}]}"#.utf8)
        let result = try Resolver.parseCollection(data, link: YouTubeLink("https://youtube.com/playlist?list=PL_test"))
        #expect(result.tracks.count == 2); #expect(result.tracks[0].id == result.tracks[1].id)
        #expect(result.truncated); #expect(result.title == "Study")
    }
    @Test func expiredURLsCannotBeUsedForInstantResume() throws {
        let data = Data(#"{"id":"xyEpFjZ_uiE","title":"One","url":"https://cdn.example/audio?expire=1","format_id":"140","protocol":"https"}"#.utf8)
        let stream = try Resolver.parseStream(data, fallback: Track(id: "xyEpFjZ_uiE", title: "One"))
        #expect(!stream.isValid)
    }
    @Test func liveHLSIsRecognized() throws {
        let data = Data(#"{"id":"xyEpFjZ_uiE","title":"Radio","is_live":true,"url":"https://cdn.example/live.m3u8","protocol":"m3u8_native"}"#.utf8)
        let stream = try Resolver.parseStream(data, fallback: Track(id: "xyEpFjZ_uiE", title: "One"))
        #expect(stream.isHLS); #expect(stream.track.isLive)
    }
}

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("geet-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true); return directory
}
private func script(_ directory: URL, body: String) throws -> URL {
    let url = directory.appendingPathComponent("helper")
    try ("#!/bin/sh\n" + body + "\n").write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path); return url
}

@Suite struct ProcessTests {
    @Test func serializesConcurrentCalls() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try script(root, body: "echo start >> '\(root.path)/events'\nsleep 0.1\necho end >> '\(root.path)/events'\necho done")
        let runner = ProcessRunner()
        async let one = runner.run(helper, arguments: [])
        async let two = runner.run(helper, arguments: [])
        _ = try await (one, two)
        let events = try String(contentsOf: root.appendingPathComponent("events"), encoding: .utf8)
        #expect(events == "start\nend\nstart\nend\n")
        #expect(await runner.starts == 2)
    }
    @Test func foregroundPreemptsSpeculativeWork() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try script(root, body: "if [ \"$1\" = slow ]; then sleep 1; fi\necho done")
        let runner = ProcessRunner()
        let background = Task { try await runner.run(helper, arguments: ["slow"], priority: .background) }
        try await Task.sleep(for: .milliseconds(100))
        let foreground = try await runner.run(helper, arguments: ["fast"])
        #expect(String(decoding: foreground, as: UTF8.self).contains("done"))
        do { _ = try await background.value; Issue.record("Speculative process should have been cancelled") } catch is CancellationError {} catch { Issue.record("Expected cancellation, got \(error)") }
    }
    @Test func cancelledQueuedRequestDoesNotRun() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try script(root, body: "sleep 0.3\necho done")
        let runner = ProcessRunner()
        let first = Task { try await runner.run(helper, arguments: []) }
        try await Task.sleep(for: .milliseconds(50))
        let cancelled = Task { try await runner.run(helper, arguments: []) }
        try await Task.sleep(for: .milliseconds(30)); cancelled.cancel()
        _ = try await first.value
        _ = try? await cancelled.value
        #expect(await runner.starts == 1)
    }
}

@Suite struct DependencyAndCooldownTests {
    @Test func concurrentRequestsForOneStreamShareOneResolve() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("tools"); try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let helper = try script(root, body: "if [ \"$2\" = --version ]; then echo 2026.10; else sleep 0.1; echo '{\"id\":\"xyEpFjZ_uiE\",\"title\":\"One\",\"url\":\"https://example.com/audio\",\"protocol\":\"https\"}'; fi")
        try FileManager.default.copyItem(at: helper, to: tools.appendingPathComponent("yt-dlp"))
        let runner = ProcessRunner(), track = Track(id: "xyEpFjZ_uiE", title: "One")
        let resolver = Resolver(root: root, bundledTools: tools, runner: runner)
        async let first = resolver.resolve(track)
        async let second = resolver.resolve(track)
        let values = try await (first, second)
        #expect(values.0.url == values.1.url); #expect(await runner.starts == 2)
        // Simulate another launch with a valid, unchanged persisted dependency.
        let nextRunner = ProcessRunner()
        let next = Resolver(root: root, bundledTools: tools, runner: nextRunner)
        _ = try await next.importCollection(YouTubeLink("https://youtu.be/xyEpFjZ_uiE"))
        #expect(await nextRunner.starts == 1)
        #expect(await next.dependencyStatus()?.version == "2026.10")
    }
    @Test func startupDoesNotSpawnAnything() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let runner = ProcessRunner()
        let resolver = Resolver(root: root, runner: runner)
        _ = await resolver.dependencyStatus()
        #expect(await runner.starts == 0)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("dependency.json").path))
    }
    @Test func probeExpiresAfter24HoursAndValidatesFileAttributes() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let helper = try script(root, body: "echo version")
        let attrs = try FileManager.default.attributesOfItem(atPath: helper.path)
        let now = Date()
        let probe = DependencyProbe(path: helper.path, version: "2026.10", modified: attrs[.modificationDate] as! Date,
                                    size: (attrs[.size] as! NSNumber).uint64Value, checked: now)
        #expect(probe.usable(now: now.addingTimeInterval(86_399)))
        #expect(!probe.usable(now: now.addingTimeInterval(86_400)))
        try "changed".write(to: helper, atomically: true, encoding: .utf8)
        #expect(!probe.usable())
    }
    @Test func failureCooldownPreventsRespawning() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("tools"); try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let helper = try script(root, body: "if [ \"$2\" = --version ]; then echo 2026.10; else echo 'ERROR: unavailable' >&2; exit 1; fi")
        try FileManager.default.copyItem(at: helper, to: tools.appendingPathComponent("yt-dlp"))
        let runner = ProcessRunner(), track = Track(id: "xyEpFjZ_uiE", title: "One")
        let resolver = Resolver(root: root, bundledTools: tools, runner: runner)
        _ = try? await resolver.resolve(track)
        #expect(await runner.starts == 2)
        _ = try? await resolver.resolve(track)
        #expect(await runner.starts == 2)
        _ = try await resolver.recheck()
        #expect(await runner.starts == 3)
    }
    @Test func persistedStreamCacheIsBoundedAndReusedWithoutProbe() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        var streams: [String: ResolvedStream] = [:]
        for index in 0..<200 {
            let track = Track(id: String(format: "%011d", index), title: "Mix \(index)")
            streams[track.id] = ResolvedStream(track: track, url: URL(string: "https://example.com/audio")!)
        }
        try Paths.write(streams, to: root.appendingPathComponent("streams.json"))
        let runner = ProcessRunner()
        let resolver = Resolver(root: root, runner: runner)
        var found = 0
        for id in streams.keys { if await resolver.cached(id) != nil { found += 1 } }
        #expect(found == 64); #expect(await runner.starts == 0)
    }
}

@Suite struct CacheTests {
    @Test func pinChangesProtectSharedAudioAndAllowRemoval() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let saved = CacheEntry(key: "saved-140", trackID: "saved", formatID: "140", length: 3, chunks: [0], pinned: false, touched: Date())
        let other = CacheEntry(key: "other-140", trackID: "other", formatID: "140", length: 3, chunks: [0], pinned: true, touched: Date())
        for entry in [saved, other] {
            let directory = root.appendingPathComponent(entry.key)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent("0.chunk"))
        }
        try Paths.write([saved.key: saved, other.key: other], to: root.appendingPathComponent("index.json"))
        let cache = MediaCache(root: root)
        await cache.setPinned(trackIDs: ["saved"])
        let entries = await cache.snapshot()
        #expect(entries.first(where: { $0.trackID == "saved" })?.pinned == true)
        #expect(entries.first(where: { $0.trackID == "other" })?.pinned == false)
        await cache.clearAutomatic()
        #expect(await cache.isComplete(trackID: "saved"))
        #expect(!(await cache.isComplete(trackID: "other")))
        // Another collection can retain a shared track until the last pin goes.
        await cache.removeUnpinned(trackIDs: ["saved"])
        #expect(await cache.isComplete(trackID: "saved"))
        await cache.setPinned(trackIDs: [])
        await cache.removeUnpinned(trackIDs: ["saved"])
        #expect(!(await cache.isComplete(trackID: "saved")))
    }
    @Test func corruptOfflineFileIsNoLongerAdvertisedAsComplete() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let entry = CacheEntry(key: "broken", trackID: "track", formatID: "140", length: 10, chunks: [0], pinned: true, touched: Date())
        try Paths.write(["broken": entry], to: root.appendingPathComponent("index.json"))
        let cache = MediaCache(root: root)
        do { _ = try await cache.chunk(key: "broken", index: 0, stream: nil); Issue.record("Missing audio must not be read successfully") } catch {}
        #expect(!(await cache.isComplete(trackID: "track")))
    }
    @Test func doesNotAdvertisePartialAudioAsOffline() {
        var entry = CacheEntry(key: "one", trackID: "one", formatID: "140", length: MediaCache.chunkSize + 10, chunks: [0], pinned: false, touched: Date())
        #expect(!entry.complete); #expect(entry.storedBytes == MediaCache.chunkSize)
        entry.chunks.insert(1); #expect(entry.complete); #expect(entry.storedBytes == MediaCache.chunkSize + 10)
    }
    @Test func unsafeFormatCannotEscapeCacheDirectory() {
        #expect(!MediaCache.key(trackID: "track", formatID: "../../evil/").contains("/"))
        #expect(MediaCache.key(trackID: "track", formatID: String(repeating: "a", count: 1000)).count == 100)
    }
    @Test func diskReadsHaveFixedMemoryLimitAndWorkWithoutNetwork() async throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let key = "track-140", length = MediaCache.chunkSize * 10
        var entry = CacheEntry(key: key, trackID: "track", formatID: "140", length: length, chunks: [], pinned: true, touched: Date())
        let directory = root.appendingPathComponent(key); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<10 {
            try Data(repeating: UInt8(index), count: Int(MediaCache.chunkSize)).write(to: directory.appendingPathComponent("\(index).chunk"))
            entry.chunks.insert(index)
        }
        try Paths.write([key: entry], to: root.appendingPathComponent("index.json"))
        let cache = MediaCache(root: root)
        for index in 0..<10 {
            let (data, total) = try await cache.chunk(key: key, index: index, stream: nil)
            #expect(data.first == UInt8(index)); #expect(total == length)
        }
        #expect(await cache.memoryBytes() <= 6 * Int(MediaCache.chunkSize))
        #expect(await cache.isComplete(trackID: "track"))
        await cache.clearAutomatic()
        #expect(await cache.isComplete(trackID: "track"))
    }
}
