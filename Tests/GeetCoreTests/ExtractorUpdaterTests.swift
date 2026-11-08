import Foundation
import Testing
@testable import GeetCore

private actor UpdateFixture {
    var version = "2026.01.01"
    var body: String = "echo '{\"id\":\"xyEpFjZ_uiE\",\"title\":\"One\",\"url\":\"https://example.com/audio\"}'"
    var badDigest = false
    var badSize = false
    var badURL = false
    var offline = false
    var validations = 0
    var metadataRequests = 0
    var assetRequests = 0
    var cachedArchive: Data?
    var requests = 0
    func configure(version: String? = nil, body: String? = nil, badDigest: Bool = false,
                   badSize: Bool = false, badURL: Bool = false, offline: Bool = false) {
        if let version { self.version = version }
        if let body { self.body = body }
        cachedArchive = nil
        self.badDigest = badDigest; self.badSize = badSize; self.badURL = badURL; self.offline = offline
    }
    func bytes() throws -> Data {
        if let cachedArchive { return cachedArchive }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geet-zip-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = root.appendingPathComponent("runtime")
        try FileManager.default.createDirectory(at: runtime.appendingPathComponent("_internal"), withIntermediateDirectories: true)
        try Data("runtime fixture".utf8).write(to: runtime.appendingPathComponent("_internal/notice.txt"))
        let executable = runtime.appendingPathComponent("yt-dlp_macos")
        try Data("#!/bin/sh\ncase \"$*\" in *--version*) echo \(version);; *) \(body);; esac\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let archive = root.appendingPathComponent("runtime.zip")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", runtime.path, archive.path]
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ExtractorUpdater.UpdateError.invalidDownload }
        let bytes = try Data(contentsOf: archive)
        cachedArchive = bytes
        return bytes
    }
    func download(_ url: URL, limit: Int) async throws -> Data {
        requests += 1
        if offline { throw URLError(.notConnectedToInternet) }
        if url == ExtractorUpdater.endpoint {
            metadataRequests += 1
            // Exercise coalescing while the transport is suspended.
            try await Task.sleep(for: .milliseconds(20))
            let data = try bytes()
            return try JSONSerialization.data(withJSONObject: [
                "tag_name": version, "draft": false, "prerelease": false,
                "assets": [["name": "yt-dlp_macos.zip", "size": data.count + (badSize ? 1 : 0),
                            "digest": "sha256:" + (badDigest ? String(repeating: "0", count: 64) : ExtractorUpdater.digest(data)),
                            "browser_download_url": badURL ? "https://evil.test/yt-dlp_macos.zip" : "https://github.com/yt-dlp/yt-dlp/releases/download/\(version)/yt-dlp_macos.zip"]]
            ])
        }
        assetRequests += 1
        return try bytes()
    }
    func validate(_ url: URL, version: String) async throws {
        validations += 1
        let result = try await ProcessRunner().run(url, arguments: ["--ignore-config", "--no-update", "--version"])
        guard String(decoding: result, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == version else {
            throw ExtractorUpdater.UpdateError.versionMismatch
        }
    }
    func updater(_ root: URL) -> ExtractorUpdater {
        ExtractorUpdater(root: root, transport: { try await self.download($0, limit: $1) },
                         validate: { try await self.validate($0, version: $1) })
    }
}

@Suite struct ExtractorUpdaterTests {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geet-updater-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func firstInstallIsVerifiedPersistedAndCoalesced() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        #expect(await updater.executable() == nil)
        #expect(await fixture.metadataRequests == 0)
        async let one = updater.refresh()
        async let two = updater.refresh()
        _ = try await (one, two)
        let executable = try #require(await updater.executable())
        #expect(executable.path.hasPrefix(root.path + "/ExtractorUpdates/"))
        #expect(await fixture.metadataRequests == 1)
        #expect(await fixture.assetRequests == 1)
        #expect(await fixture.validations == 1)
        let restarted = await fixture.updater(root)
        #expect(await restarted.executable() == executable)
        #expect(try await restarted.refresh() == false)
        #expect(await fixture.metadataRequests == 1)
    }

    @Test(arguments: ["digest", "size", "url", "version", "probe"])
    func unverifiedOrUnusableDownloadsNeverActivate(failure: String) async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        try await updater.refresh()
        let before = try #require(await updater.executable())
        await fixture.configure(version: failure == "version" ? "../escape" : "2026.02.01",
                                badDigest: failure == "digest", badSize: failure == "size", badURL: failure == "url")
        let candidate: ExtractorUpdater
        if failure == "probe" {
            candidate = ExtractorUpdater(root: root, transport: { try await fixture.download($0, limit: $1) },
                                         validate: { _, _ in throw ExtractorUpdater.UpdateError.versionMismatch })
        } else { candidate = updater }
        await #expect(throws: (any Error).self) { try await candidate.refresh(force: true) }
        #expect(await candidate.executable() == before)
        #expect(await fixture.validations == 1)
        let directories = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("ExtractorUpdates"), includingPropertiesForKeys: nil)
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
        #expect(directories.count == 1)
    }

    @Test func failedCheckUsesExistingInstallAndRetriesAreThrottled() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        let now = Date()
        try await updater.refresh(now: now)
        let executable = await updater.executable()
        #expect(try await updater.refresh(now: now.addingTimeInterval(86_399)) == false)
        await fixture.configure(offline: true)
        await #expect(throws: (any Error).self) { try await updater.refresh(now: now.addingTimeInterval(86_400)) }
        #expect(await updater.executable() == executable)
        await #expect(throws: ExtractorSetupFailure.offline) { try await updater.refresh(now: now.addingTimeInterval(86_500)) }
        await fixture.configure(version: "2026.02.01")
        #expect(try await updater.refresh(now: now.addingTimeInterval(90_001)))
    }

    @Test(arguments: ["exit", "json"])
    func extractionRegressionRollsBackAndRejectsReleaseAcrossLaunches(failure: String) async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        try await updater.refresh()
        let previous = try #require(await updater.executable())
        await fixture.configure(version: "2026.02.01", body: failure == "exit" ? "echo 'ERROR: broken extractor' >&2; exit 1" : "echo 'not JSON'")
        try await updater.refresh(force: true)
        let resolver = Resolver(root: root, allowExternalTools: false, updater: updater)
        let result = try await resolver.resolve(Track(id: "xyEpFjZ_uiE", title: "One"))
        #expect(result.url.host == "example.com")
        #expect(await updater.executable() == previous)
        let restarted = await fixture.updater(root)
        #expect(await restarted.executable() == previous)
        #expect(try await restarted.refresh(force: true) == false)
        #expect(await fixture.assetRequests == 2)
        // A later release can still be adopted after rollback.
        await fixture.configure(version: "2026.03.01", body: "echo '{}' ")
        #expect(try await restarted.refresh(force: true))
    }

    @Test func untriedUpdatesPreserveTheLastSuccessfulExtractor() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        let resolver = Resolver(root: root, allowExternalTools: false, updater: updater)
        let track = Track(id: "xyEpFjZ_uiE", title: "One")
        _ = try await resolver.resolve(track)
        let working = try #require(await updater.executable())
        await fixture.configure(version: "2026.02.01")
        try await updater.refresh(force: true)
        // Another update arrives before this one has ever extracted a link.
        await fixture.configure(version: "2026.03.01", body: "exit 1")
        try await updater.refresh(force: true)
        _ = try await resolver.resolve(track, fresh: true)
        #expect(await updater.executable() == working)
    }

    @Test func unavailableVideoDoesNotBlacklistUpdate() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        await fixture.configure(body: "exit 1")
        try await updater.refresh()
        await fixture.configure(version: "2026.02.01")
        try await updater.refresh(force: true)
        let current = await updater.executable()
        let resolver = Resolver(root: root, allowExternalTools: false, updater: updater)
        await #expect(throws: (any Error).self) { try await resolver.resolve(Track(id: "xyEpFjZ_uiE", title: "One")) }
        #expect(await updater.executable() == current)
    }

    @Test func corruptCurrentFallsBackWithoutExecutingIt() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        try await updater.refresh()
        let previous = try #require(await updater.executable())
        await fixture.configure(version: "2026.02.01")
        try await updater.refresh(force: true)
        let current = try #require(await updater.executable())
        try Data("corrupt".utf8).write(to: current)
        #expect(await updater.executable() == previous)
        let restarted = await fixture.updater(root)
        #expect(await restarted.executable() == previous)
    }

    @Test func recheckInstallsFixAndClearsFailureCooldown() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        await fixture.configure(body: "exit 1")
        let resolver = Resolver(root: root, allowExternalTools: false, updater: updater)
        let track = Track(id: "xyEpFjZ_uiE", title: "One")
        await #expect(throws: (any Error).self) { try await resolver.resolve(track) }
        await fixture.configure(version: "2026.02.01", body: "echo '{\"id\":\"xyEpFjZ_uiE\",\"url\":\"https://example.com/audio\"}'")
        let probe = try await resolver.recheck()
        #expect(probe.version == "2026.02.01")
        #expect(try await resolver.resolve(track).url.host == "example.com")
    }

    @Test func failedFirstSetupDoesNotRunAnyHelper() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        await fixture.configure(offline: true)
        let runner = ProcessRunner(), resolver = Resolver(root: root, runner: runner, allowExternalTools: false, updater: updater)
        let track = Track(id: "xyEpFjZ_uiE", title: "One")
        await #expect(throws: ExtractorSetupFailure.offline) { try await resolver.resolve(track) }
        await #expect(throws: ExtractorSetupFailure.offline) { try await resolver.resolve(track) }
        #expect(await runner.starts == 0)
        #expect(await updater.executable() == nil)
        #expect(await fixture.requests == 1)
        let restarted = await fixture.updater(root)
        await #expect(throws: ExtractorSetupFailure.offline) { try await restarted.refresh() }
        #expect(await fixture.requests == 1)
    }

    @Test func checkAgainClearsCachedStreamLinksEvenWithoutANewRelease() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        let response = root.appendingPathComponent("response.json")
        try Data(#"{"id":"xyEpFjZ_uiE","url":"https://old.example/audio"}"#.utf8).write(to: response)
        await fixture.configure(body: "cat '\(response.path)'")
        let resolver = Resolver(root: root, allowExternalTools: false, updater: updater)
        let track = Track(id: "xyEpFjZ_uiE", title: "One")
        #expect(try await resolver.resolve(track).url.host == "old.example")
        try Data(#"{"id":"xyEpFjZ_uiE","url":"https://fresh.example/audio"}"#.utf8).write(to: response)
        _ = try await resolver.recheck()
        #expect(try await resolver.resolve(track).url.host == "fresh.example")
        #expect(await fixture.assetRequests == 1)
    }

    @Test func missingInstallationIsRestoredWithoutWaitingADay() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let fixture = UpdateFixture(), updater = await fixture.updater(root)
        try await updater.refresh()
        let executable = try #require(await updater.executable())
        try FileManager.default.removeItem(at: executable)
        #expect(try await updater.refresh())
        #expect(await updater.executable() != nil)
        #expect(await fixture.assetRequests == 2)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GEET_TEST_EXTRACTOR_UPDATE"] == "1"))
    func officialReleaseDownloadsAndRunsWithoutHomebrew() async throws {
        let root = try temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let updater = ExtractorUpdater(root: root)
        try await updater.refresh()
        let resolver = Resolver(root: root, allowExternalTools: false, updater: updater)
        let probe = try await resolver.recheck()
        print("VERIFIED_EXTRACTOR version=\(probe.version) path=\(probe.path)")
        #expect(probe.path.hasPrefix(root.path + "/ExtractorUpdates/"))
        #expect(await updater.executable()?.path == probe.path)
    }
}
