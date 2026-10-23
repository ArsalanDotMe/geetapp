import Foundation
import Testing
@testable import GeetCore

@Suite struct AudioIndexTests {
    private func number(_ value: UInt64, _ width: Int = 4) -> Data {
        Data((0..<width).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private func atom(_ name: String, _ payload: Data) -> Data { number(UInt64(payload.count + 8)) + Data(name.utf8) + payload }
    private func fixture(version: UInt8 = 0, hierarchical: Bool = false, skip: UInt64 = 0) -> Data {
        let head = Data([version, 0, 0, 0]) + number(1) + number(1000)
        let timing = number(0, version == 1 ? 8 : 4) + number(skip, version == 1 ? 8 : 4)
        let references = number(0, 2) + number(2, 2) + number(hierarchical ? 0x8000_000A : 10) + number(9500) + number(0) + number(15) + number(500) + number(0)
        return atom("ftyp", Data("dash".utf8)) + atom("moov", Data()) + atom("sidx", head + timing + references)
    }
    @Test(arguments: [UInt8(0), UInt8(1)]) func mapsSIDXToVODWithoutChangingFragmentOffsets(_ version: UInt8) throws {
        let data = fixture(version: version, skip: 3)
        let parsed = try #require(DASHAudioIndex.parse(data, length: Int64(data.count + 28)))
        #expect(parsed.duration == 10)
        #expect(parsed.segments.map(\.offset) == [Int64(data.count + 3), Int64(data.count + 13)])
        #expect(parsed.segments.map(\.length) == [10, 15])
        #expect(parsed.initialization == data.prefix(20))
        let playlist = String(decoding: parsed.playlist, as: UTF8.self)
        #expect(playlist.contains("#EXT-X-TARGETDURATION:10\n"))
        #expect(playlist.contains("#EXT-X-MAP:URI=\"init.mp4\"\n"))
        #expect(playlist.contains("#EXTINF:9.500000000,\n#EXT-X-BYTERANGE:10@\(data.count + 3)\n"))
        #expect(playlist.hasSuffix("#EXT-X-ENDLIST\n"))
    }
    @Test func rejectsIncompleteHierarchicalAndOutOfBoundsIndexes() {
        let data = fixture()
        for size in 0..<data.count { #expect(DASHAudioIndex.parse(Data(data.prefix(size)), length: Int64(data.count + 25)) == nil) }
        #expect(DASHAudioIndex.parse(data, length: Int64(data.count + 24)) == nil)
        #expect(DASHAudioIndex.parse(data, length: -1) == nil)
        #expect(DASHAudioIndex.parse(fixture(hierarchical: true), length: 1000) == nil)
        #expect(DASHAudioIndex.parse(fixture(version: 1, skip: UInt64.max), length: Int64.max) == nil)
    }
    @Test func parsesOnlyValidSatisfiableSingleRanges() {
        #expect(HTTPByteRange.parse(nil, length: 100) == 0...99)
        #expect(HTTPByteRange.parse("bytes=10-20", length: 100) == 10...20)
        #expect(HTTPByteRange.parse("bytes=90-200", length: 100) == 90...99)
        #expect(HTTPByteRange.parse("bytes=90-", length: 100) == 90...99)
        #expect(HTTPByteRange.parse("bytes=-20", length: 100) == 80...99)
        #expect(HTTPByteRange.parse("bytes=-200", length: 100) == 0...99)
        for header in ["bytes=100-", "bytes=20-10", "bytes=-0", "bytes=+1-2", "bytes=1-+2", "bytes=1-2,3-4", "bytes=1-9223372036854775808", "bytes=-", "bytes= 1-2", "items=1-2"] {
            #expect(HTTPByteRange.parse(header, length: 100) == nil)
        }
        #expect(HTTPByteRange.parse(nil, length: 0) == nil)
    }
}

@Suite struct MP4AudioTests {
    private func atom(_ name: String, _ payload: Data) -> Data {
        var size = UInt32(payload.count + 8).bigEndian
        return withUnsafeBytes(of: &size) { Data($0) } + Data(name.utf8) + payload
    }
    private func movie(version: UInt8 = 0, dash: Bool = true, fragmented: Bool = true, baseSamples: Bool = false) -> Data {
        func header(_ name: String) -> Data {
            var data = Data(repeating: 0, count: 100); data[0] = version
            let offset = name == "tkhd" ? (version == 1 ? 28 : 20) : (version == 1 ? 24 : 16)
            let count = version == 1 ? 8 : 4
            data.replaceSubrange(offset..<(offset + count), with: repeatElement(UInt8(1), count: count))
            return atom(name, data)
        }
        let type = atom("ftyp", Data((dash ? "dash\0\0\0\0iso6" : "M4A \0\0\0\0mp42").utf8))
        var timing = Data(repeating: 0, count: 8); timing[7] = baseSamples ? 1 : 0
        let track = atom("trak", header("tkhd") + atom("mdia", header("mdhd") + atom("minf", atom("stbl", atom("stts", timing)))))
        return type + atom("moov", header("mvhd") + track + (fragmented ? atom("mvex", Data()) : Data())) + atom("mdat", Data([7, 8, 9]))
    }
    @Test(arguments: [UInt8(0), UInt8(1)]) func clearsRedundantDASHDurationsWithoutMovingAudio(_ version: UInt8) {
        let input = movie(version: version), output = MP4Audio.normalizedHeader(input)
        #expect(input.count == output.count)
        #expect(input.suffix(11) == output.suffix(11))
        let differences = zip(input, output).filter { $0 != $1 }
        #expect(differences.count == (version == 1 ? 24 : 12))
        #expect(differences.allSatisfy { $0 == 1 && $1 == 0 })
        #expect(MP4Audio.normalizedHeader(output) == output)
    }
    @Test func ordinaryAndUnfragmentedFilesStayUnchanged() {
        for input in [movie(dash: false), movie(fragmented: false), movie(baseSamples: true)] { #expect(MP4Audio.normalizedHeader(input) == input) }
    }
    @Test func truncatedAndOversizedAtomsCannotEscapeBuffer() {
        let valid = movie()
        for count in 0..<valid.count { _ = MP4Audio.normalizedHeader(Data(valid.prefix(count))) }
        let malformed = Data([255, 255, 255, 255]) + Data("moov".utf8)
        #expect(MP4Audio.normalizedHeader(malformed) == malformed)
    }
}

private final class AudioRangeProtocol: URLProtocol, @unchecked Sendable {
    static let audio = Data(repeating: 7, count: Int(MediaCache.chunkSize) + 100)
    private var pending: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "audio.geet.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.url?.path == "/slow" {
            let work = DispatchWorkItem { [weak self] in self?.deliver() }
            pending = work
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3, execute: work)
        } else { deliver() }
    }
    private func deliver() {
        let range = request.value(forHTTPHeaderField: "Range")!.dropFirst(6).split(separator: "-")
        let start = Int(range[0])!, end = min(Int(range[1])!, Self.audio.count - 1)
        let data = Self.audio.subdata(in: start..<(end + 1))
        let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: "HTTP/1.1", headerFields: [
            "Content-Range": "bytes \(start)-\(end)/\(Self.audio.count)", "Content-Length": "\(data.count)"] )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { pending?.cancel(); pending = nil }
}

@Suite struct StreamingRetentionTests {
    @Test func cancellingDownloadDoesNotCancelSharedPlaybackRange() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geet-shared-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [AudioRangeProtocol.self]
        let cache = MediaCache(root: root, configuration: configuration)
        let stream = ResolvedStream(track: Track(id: "xyEpFjZ_uiE", title: "Shared audio"), url: URL(string: "https://audio.geet.test/slow")!)
        let key = MediaCache.key(trackID: stream.track.id, formatID: stream.formatID)
        let download = Task { try await cache.chunk(key: key, index: 0, stream: stream) }
        try await Task.sleep(for: .milliseconds(50))
        let playback = Task { try await cache.chunk(key: key, index: 0, stream: stream, retaining: false) }
        try await Task.sleep(for: .milliseconds(50)); download.cancel()
        let bytes = try await playback.value
        #expect(bytes.0.count == Int(MediaCache.chunkSize))
        #expect(await cache.networkRequests == 1)
        #expect(await cache.snapshot().isEmpty)
        do { _ = try await download.value; Issue.record("A cancelled download must stop without storing audio.") }
        catch { #expect(error is CancellationError) }
    }
    @Test func streamingStaysInMemoryAndCanBeSavedWithoutAnotherRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("geet-retention-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [AudioRangeProtocol.self]
        let cache = MediaCache(root: root, configuration: configuration)
        let stream = ResolvedStream(track: Track(id: "xyEpFjZ_uiE", title: "Test audio"), url: URL(string: "https://audio.geet.test/audio")!)
        let key = MediaCache.key(trackID: stream.track.id, formatID: stream.formatID)
        for index in 0...1 { _ = try await cache.chunk(key: key, index: index, stream: stream, retaining: false) }
        #expect(await cache.networkRequests == 2)
        #expect(await cache.snapshot().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(await cache.memoryBytes() <= 6 * Int(MediaCache.chunkSize))
        try await cache.download(stream, pinned: true) { _ in }
        #expect(await cache.networkRequests == 2)
        #expect(await cache.isComplete(trackID: stream.track.id))
        let reopened = MediaCache(root: root)
        #expect(await reopened.isComplete(trackID: stream.track.id))
        #expect(await reopened.snapshot().first?.pinned == true)
        let (data, _) = try await reopened.chunk(key: key, index: 1, stream: nil)
        #expect(data.count == 100)
        #expect(await reopened.networkRequests == 0)
    }
}
