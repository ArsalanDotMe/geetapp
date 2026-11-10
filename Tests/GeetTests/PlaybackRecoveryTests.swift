import Foundation
import Testing
import GeetCore
@testable import Geet

private final class RecoveryAudioProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "recovery.geet.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let accepted = request.url?.path == "/fresh"
        let data = Data(repeating: 0, count: accepted ? 32 : 0)
        let headers = accepted ? ["Content-Length": "32", "Content-Range": "bytes 0-31/32"] : ["Content-Length": "0"]
        let response = HTTPURLResponse(url: request.url!, statusCode: accepted ? 206 : 403, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if accepted { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite @MainActor struct PlaybackRecoveryTests {
    @Test(arguments: [false, true])
    func initialRejectionRetriesFreshOnce(rejectFresh: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geet-retry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let tools = root.appendingPathComponent("tools")
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let executable = tools.appendingPathComponent("yt-dlp")
        let endpoint = rejectFresh ? "rejected" : "fresh"
        let script = """
        #!/bin/sh
        if [ "$2" = "--version" ]; then echo 2026.10
        elif printf '%s\\n' "$@" | grep -qx 'youtube:player_client=visionos'; then echo '{"id":"xyEpFjZ_uiE","title":"Test","url":"https://recovery.geet.test/\(endpoint)","format_id":"140","protocol":"https"}'
        else exit 1; fi
        """
        try script.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let track = Track(id: "xyEpFjZ_uiE", title: "Test")
        let stale = ResolvedStream(track: track, url: URL(string: "https://recovery.geet.test/rejected")!)
        try Paths.write([track.id: stale], to: root.appendingPathComponent("streams.json"))
        let resolver = Resolver(root: root, bundledTools: tools, allowExternalTools: false)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [RecoveryAudioProtocol.self]
        let cache = MediaCache(root: root.appendingPathComponent("Media"), configuration: config)
        let player = Player(resolver: resolver, cache: cache, mediaCommands: false)
        defer { player.shutdown() }
        let collection = Collection(id: "test", title: "Test", creator: "", source: track.url, tracks: [track])
        player.play(collection, index: 0)
        let deadline = Date().addingTimeInterval(10)
        while await cache.networkRequests < 2 || (rejectFresh ? player.error == nil : player.media == nil && player.error == nil) {
            guard Date() < deadline else { throw URLError(.timedOut) }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await resolver.runner.starts == 2)
        #expect(await cache.networkRequests == 2)
        #expect(await resolver.cached(track.id)?.url.path == "/\(endpoint)")
        if rejectFresh { #expect(player.error == "YouTube refused this audio stream. Try again later or try another link.") }
        else { #expect(player.media != nil); #expect(player.error == nil) }
    }
}
