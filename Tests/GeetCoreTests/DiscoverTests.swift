import Foundation
import Testing
@testable import GeetCore

@Suite struct DiscoverSchemaTests {
    @Test func bundledFeedHasMultiplePlayableKinds() throws {
        let feed = try DiscoverFeed.bundled.validated()
        #expect(feed.categories.count >= 2)
        #expect(feed.categories.flatMap(\.items).contains { $0.kind == .radio })
        #expect(feed.categories.flatMap(\.items).contains { $0.kind == .playlist })
        let decoded = try DiscoverFeed.decode(JSONEncoder().encode(feed))
        #expect(decoded.categories.map(\.id) == feed.categories.map(\.id))
    }
    @Test func fiveCategoriesOfTenMixedItemsAndOptionalSubtitles() throws {
        let items = (0..<10).map { index in
            DiscoverPick(id: "item-\(index)", title: "Listen \(index)", creator: "Creator", mood: "A quiet moment",
                         kind: index % 3 == 0 ? .radio : index % 3 == 1 ? .mix : .playlist,
                         videoID: "mypnwpywaaw", playlistID: index % 3 == 2 ? "PL_test" : nil)
        }
        let categories = (0..<5).map { DiscoverCategory(id: "category-\($0)", title: "Category \($0)", subtitle: $0.isMultiple(of: 2) ? nil : "Subtitle", items: items) }
        let feed = try DiscoverFeed.decode(JSONEncoder().encode(DiscoverFeed(categories: categories)))
        #expect(feed.categories.count == 5)
        #expect(feed.categories.flatMap(\.items).count == 50)
        #expect(feed.categories[0].subtitle == nil)
        #expect(feed.categories[1].subtitle == "Subtitle")
        #expect(Set(feed.categories[0].items.map(\.kind)).count == 3)
    }
    @Test func rejectsMalformedVersionsBoundsDuplicatesAndLinks() throws {
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(DiscoverFeed.bundled)) as! [String: Any]
        func rejects(_ mutate: (inout [String: Any]) -> Void) throws {
            var json = original; mutate(&json)
            let data = try JSONSerialization.data(withJSONObject: json)
            #expect(throws: (any Error).self) { try DiscoverFeed.decode(data) }
        }
        try rejects { $0["schemaVersion"] = 2 }
        try rejects { $0["categories"] = [] }
        let category = (original["categories"] as! [[String: Any]])[0]
        try rejects { $0["categories"] = Array(repeating: category, count: 6) }
        for count in [0, 2, 11] {
            try rejects { json in
                var changed = category
                let item = (category["items"] as! [[String: Any]])[0]
                changed["items"] = (0..<count).map { i in var copy = item; copy["id"] = "item-\(i)"; return copy }
                json["categories"] = [changed]
            }
        }
        for field in ["videoID", "id", "title", "creator", "kind"] {
            try rejects { json in
                var changed = category, items = category["items"] as! [[String: Any]]
                items[0][field] = field == "videoID" ? "bad&list=PL_injected" : ""
                changed["items"] = items; json["categories"] = [changed]
            }
        }
        try rejects { json in
            var changed = category, items = category["items"] as! [[String: Any]]
            items[1]["id"] = items[0]["id"]; changed["items"] = items; json["categories"] = [changed]
        }
        #expect(throws: (any Error).self) { try DiscoverFeed.decode(Data(repeating: 32, count: DiscoverFeed.maximumBytes + 1)) }
    }
    @Test func playingIsEphemeralAndSavingCopiesWithoutReidentifyingThePreview() {
        let pick = DiscoverFeed.bundled.categories[0].items[0]
        var original = Collection(id: pick.collectionID, title: pick.title, creator: pick.creator, source: pick.url,
                                  tracks: [Track(id: pick.videoID, title: pick.title, isLive: true)], keepsOffline: true)
        original.resumeIndex = 3; original.resumePosition = 95
        let preview = DiscoverPlayback.preview(original)
        #expect(preview.id == pick.previewID)
        #expect(preview.id != original.id)
        #expect(!preview.keepsOffline && preview.resumeIndex == 0 && preview.resumePosition == 0)
        let saved = DiscoverPlayback.savedCopy(preview, for: pick)
        #expect(saved.id == pick.collectionID && saved.source == original.source)
        #expect(preview.id == pick.previewID)
        #expect(original.keepsOffline && original.resumePosition == 95)
        #expect(!saved.keepsOffline)
    }
}

private actor DiscoverTransport {
    var requests: [URLRequest] = []
    var responses: [(Int, Data)]
    init(_ responses: [(Int, Data)]) { self.responses = responses }
    func fetch(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, data) = responses.removeFirst()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                      headerFields: ["Content-Type": "application/json", "ETag": "\"feed-v1\""])!)
    }
}

@Suite struct DiscoverFetchTests {
    private let endpoint = URL(string: "https://feed.example/discover/v1.json")!
    private func cacheFile() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("geet-feed-\(UUID()).json") }
    @Test func cachesRevalidatesAndRecoversAfterRestart() async throws {
        let file = cacheFile(); defer { try? FileManager.default.removeItem(at: file) }
        let wire = DiscoverTransport([(200, try JSONEncoder().encode(DiscoverFeed.bundled)), (304, Data()), (304, Data())])
        let client = DiscoverFeedClient(endpoint: endpoint, cacheFile: file, transport: { try await wire.fetch($0) })
        let now = Date()
        _ = try await client.refresh(now: now)
        _ = try await client.refresh(now: now.addingTimeInterval(5))
        #expect(await wire.requests.count == 1)
        _ = try await client.refresh(force: true, now: now.addingTimeInterval(10))
        #expect(await wire.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"feed-v1\"")
        #expect(DiscoverFeedClient.cachedFeed(at: file, endpoint: endpoint)?.categories.count == DiscoverFeed.bundled.categories.count)
        let restarted = DiscoverFeedClient(endpoint: endpoint, cacheFile: file, transport: { try await wire.fetch($0) })
        _ = try await restarted.refresh(now: now.addingTimeInterval(11))
        #expect(await wire.requests.count == 2)
        _ = try await restarted.refresh(now: now.addingTimeInterval(DiscoverFeedClient.refreshInterval + 11))
        #expect(await wire.requests.count == 3)
        #expect(DiscoverFeedClient.cachedFeed(at: file, endpoint: URL(string: "https://other.example/feed")!) == nil)
    }
    @Test func invalidUpdatesNeverReplaceLastGoodDiskCache() async throws {
        let file = cacheFile(); defer { try? FileManager.default.removeItem(at: file) }
        let wire = DiscoverTransport([(200, try JSONEncoder().encode(DiscoverFeed.bundled)), (200, Data("{}".utf8)), (503, Data())])
        let client = DiscoverFeedClient(endpoint: endpoint, cacheFile: file, transport: { try await wire.fetch($0) })
        _ = try await client.refresh()
        let original = try Data(contentsOf: file)
        for _ in 0..<2 {
            await #expect(throws: (any Error).self) { try await client.refresh(force: true) }
            #expect(try Data(contentsOf: file) == original)
            #expect(DiscoverFeedClient.cachedFeed(at: file, endpoint: endpoint) != nil)
        }
    }
    @Test func rejectsInsecureEndpointBeforeRequestAnd304WithoutCache() async throws {
        let file = cacheFile(); defer { try? FileManager.default.removeItem(at: file) }
        let wire = DiscoverTransport([(304, Data())])
        let insecure = DiscoverFeedClient(endpoint: URL(string: "http://feed.example/feed")!, cacheFile: file, transport: { try await wire.fetch($0) })
        await #expect(throws: (any Error).self) { try await insecure.refresh() }
        #expect(await wire.requests.isEmpty)
        let client = DiscoverFeedClient(endpoint: endpoint, cacheFile: file, transport: { try await wire.fetch($0) })
        await #expect(throws: (any Error).self) { try await client.refresh() }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
