import AppKit
import Combine
import ServiceManagement
import GeetCore

@MainActor
final class AppStore: ObservableObject {
    @Published var library: LibraryDocument
    @Published var busy = false
    @Published var message: String?
    @Published var downloads: [String: Double] = [:]
    @Published var savedTrackIDs: Set<String> = []
    @Published var storageBytes: Int64 = 0
    @Published var dependencyText = "Checked when you first open a link"
    @Published var clipboardLink: String?
    @Published var offlineEnabled: Bool
    let player: Player
    let resolver: Resolver
    let cache: MediaCache
    let artwork = ArtworkStore()
    let root: URL
    let preview: Bool
    private var importTask: Task<Void, Never>?
    private var importGeneration = UUID()
    private var downloadTask: Task<Void, Never>?
    private var downloadCollectionID: String?
    private var clipboardTask: Task<Void, Never>?
    private var clipboardChange = -1
    private var saveWork: DispatchWorkItem?
    static let discover: [DiscoverPick] = [
        DiscoverPick(id: "lofi", title: "Lofi hip hop radio", creator: "Lofi Girl", mood: "A familiar place to focus", videoID: "0sfDth4lMLc"),
        DiscoverPick(id: "classroom", title: "Chillhop in the Classroom", creator: "Chillhop Music", mood: "Music to get things done", videoID: "mypnwpywaaw", playlistID: "PLt7bG0K25iXhu8bSbLsoWFBf-xSyLwy2_"),
        DiscoverPick(id: "fall", title: "Chillhop Essentials Fall", creator: "Chillhop Music", mood: "Settle into the season", videoID: "jiua2V9q9V0", playlistID: "PLt7bG0K25iXjIl0bopl1TY8_6n35gsgcd"),
        DiscoverPick(id: "winter", title: "Chillhop Essentials Winter", creator: "Chillhop Music", mood: "A slower kind of afternoon", videoID: "Zq0cZnA2Dhc", playlistID: "PLt7bG0K25iXh5RbylpYcJwsHBpM0dGc2i")
    ]
    init(preview: Bool = false, root overrideRoot: URL? = nil) {
        self.preview = preview
        self.root = overrideRoot ?? (preview ? FileManager.default.temporaryDirectory.appendingPathComponent("geet-design-preview") : Paths.support)
        #if DEBUG
        library = preview ? PreviewData.library : Paths.read(LibraryDocument.self, from: root.appendingPathComponent("library.json")) ?? LibraryDocument()
        offlineEnabled = true
        #else
        library = Paths.read(LibraryDocument.self, from: root.appendingPathComponent("library.json")) ?? LibraryDocument()
        offlineEnabled = false
        #endif
        resolver = Resolver(root: root, bundledTools: Bundle.main.resourceURL?.appendingPathComponent("Tools"))
        cache = MediaCache(root: root.appendingPathComponent("Media", isDirectory: true))
        player = Player(resolver: resolver, cache: cache)
        player.shuffle = library.shuffle; player.repeatMode = library.repeatMode; player.volume = library.volume
        player.automaticCache = library.automaticCache; player.offlineEnabled = offlineEnabled
        player.onSnapshot = { [weak self] id, index, position in
            guard let self, let row = library.collections.firstIndex(where: { $0.id == id }) else { return }
            library.collections[row].resumeIndex = index; library.collections[row].resumePosition = position
            scheduleSave()
        }
        player.onConfiguration = { [weak self] in self?.saveConfiguration() }
        player.onTrackChanged = { [weak self] track in
            guard let self else { return }
            if let row = library.collections.firstIndex(where: { $0.id == self.player.collectionID }) {
                for index in library.collections[row].tracks.indices where library.collections[row].tracks[index].id == track.id {
                    library.collections[row].tracks[index] = track
                }
                scheduleSave()
            }
            if let url = track.thumbnail {
                Task { if let image = await self.artwork.image(url) { self.player.setArtwork(image, trackID: track.id) } }
            }
        }
        // No startup Tasks, dependency probes, artwork fetches, or AVPlayer allocation.
    }
    func play(_ collection: Collection, index: Int? = nil, beginning: Bool = false) {
        library.selectedID = collection.id; scheduleSave()
        player.play(collection, index: index, fromBeginning: beginning)
    }
    func add(_ text: String, playAfter: Bool = false) {
        guard !busy else { return }
        let link: YouTubeLink
        do { link = try YouTubeLink(text) } catch { message = error.localizedDescription; return }
        let existingID = link.isPlaylist ? "playlist:\(link.id)" : "video:\(link.id)"
        if let existing = library.collections.first(where: { $0.id == existingID }) {
            if playAfter { play(existing) } else { message = "This playlist is already in your library." }; return
        }
        busy = true; message = nil
        let token = UUID(); importGeneration = token
        clipboardTask?.cancel()
        importTask = Task {
            do {
                await resolver.cancelBackground()
                let collection = try await resolver.importCollection(link)
                try Task.checkCancellation()
                guard importGeneration == token else { return }
                library.collections.append(collection); scheduleSave(); busy = false
                if playAfter { play(collection) }
                clipboardLink = nil
                await updateDependency()
            } catch {
                guard importGeneration == token else { return }
                busy = false; if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }
    func refresh(_ collection: Collection) {
        guard !busy else { return }
        busy = true
        let token = UUID(); importGeneration = token
        importTask = Task {
            do {
                var fresh = try await resolver.importCollection(YouTubeLink(collection.source.absoluteString))
                try Task.checkCancellation()
                guard importGeneration == token else { return }
                fresh.addedAt = collection.addedAt; fresh.keepsOffline = collection.keepsOffline
                if collection.tracks.indices.contains(collection.resumeIndex),
                   let index = fresh.tracks.firstIndex(where: { $0.id == collection.tracks[collection.resumeIndex].id }) {
                    fresh.resumeIndex = index; fresh.resumePosition = collection.resumePosition
                }
                if let row = library.collections.firstIndex(where: { $0.id == fresh.id }) { library.collections[row] = fresh }
                scheduleSave(); busy = false
                if fresh.keepsOffline { keepOffline(fresh) }
            } catch {
                guard importGeneration == token else { return }
                busy = false; if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }
    func remove(_ collection: Collection) {
        if downloadCollectionID == collection.id { cancelDownload() }
        if player.collectionID == collection.id { player.stop() }
        if library.selectedID == collection.id { library.selectedID = nil }
        library.collections.removeAll { $0.id == collection.id }; scheduleSave(); synchronizePins()
    }
    func moveToTop(_ collection: Collection) {
        library.collections.removeAll { $0.id == collection.id }; library.collections.insert(collection, at: 0); scheduleSave()
    }
    func keepOffline(_ collection: Collection) {
        guard offlineEnabled else { message = "Offline listening will be available with a one-time $5 contribution. Checkout is coming soon."; return }
        guard collection.tracks.contains(where: { !$0.isLive }) else { message = "Live radio is available online only."; return }
        if downloadTask != nil { message = "A playlist is already being saved. Let it finish, or cancel it first."; return }
        guard let row = library.collections.firstIndex(where: { $0.id == collection.id }) else { return }
        library.collections[row].keepsOffline = true; scheduleSave()
        downloadCollectionID = collection.id
        downloads[collection.id] = 0
        downloadTask = Task {
            defer { downloads.removeValue(forKey: collection.id); downloadTask = nil; downloadCollectionID = nil }
            let tracks = collection.tracks.filter { !$0.isLive }
            do {
                guard !tracks.isEmpty else { throw GeetError.message("Live radio is available online only.") }
                for (index, track) in tracks.enumerated() {
                    try Task.checkCancellation()
                    if await cache.isComplete(trackID: track.id) {
                        downloads[collection.id] = Double(index + 1) / Double(tracks.count)
                    } else {
                        let stream = try await resolver.resolve(track)
                        try Task.checkCancellation()
                        try await cache.download(stream, pinned: true) { [weak self] progress in
                            Task { @MainActor in
                                guard self?.downloadCollectionID == collection.id, self?.downloadTask?.isCancelled == false else { return }
                                self?.downloads[collection.id] = (Double(index) + progress) / Double(tracks.count)
                            }
                        }
                    }
                    await updateStorage()
                }
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            // A cancelled download must not repin music removed from the library.
            let pins = Set(library.collections.filter(\.keepsOffline).flatMap(\.tracks).map(\.id))
            await cache.setPinned(trackIDs: pins)
            await updateStorage()
        }
    }
    func cancelDownload() { downloadTask?.cancel() }
    func cancelImport() { importGeneration = UUID(); importTask?.cancel(); importTask = nil; busy = false }
    func removeOffline(_ collection: Collection) {
        if downloadCollectionID == collection.id { cancelDownload() }
        if let row = library.collections.firstIndex(where: { $0.id == collection.id }) { library.collections[row].keepsOffline = false }
        scheduleSave()
        let pins = Set(library.collections.filter(\.keepsOffline).flatMap(\.tracks).map(\.id))
        let removed = Set(collection.tracks.map(\.id))
        Task { await cache.setPinned(trackIDs: pins); await cache.removeUnpinned(trackIDs: removed); await updateStorage() }
    }
    func clearAutomaticCache() { Task { await cache.clearAutomatic(); await updateStorage() } }
    func synchronizePins() {
        let ids = Set(library.collections.filter(\.keepsOffline).flatMap(\.tracks).map(\.id))
        Task { await cache.setPinned(trackIDs: ids); await updateStorage() }
    }
    func setAutomaticCache(_ value: Bool) {
        guard offlineEnabled else { return }
        library.automaticCache = value; player.automaticCache = value; scheduleSave()
    }
    func savedCollection(for pick: DiscoverPick) -> Collection? {
        library.collections.first { $0.source == pick.url }
    }
    func playDiscover(_ pick: DiscoverPick) {
        if let collection = savedCollection(for: pick) { play(collection) }
        else { add(pick.url.absoluteString, playAfter: true) }
    }
    func panelOpened(inspectClipboard: Bool = true) {
        player.panelVisible(true)
        Task { await updateStorage(); await updateDependency() }
        // Clipboard access occurs once on panel opening, never via polling.
        guard !preview, inspectClipboard else { return }
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != clipboardChange else { return }
        clipboardChange = pasteboard.changeCount
        clipboardTask?.cancel()
        guard let text = pasteboard.string(forType: .string), let link = try? YouTubeLink(text) else { clipboardLink = nil; return }
        clipboardLink = link.url.absoluteString
        // Speculation is optional and only while the user is looking. It goes
        // through the same process lane and is preempted by foreground demand.
        if !link.isPlaylist && !player.isLoading {
            clipboardTask = Task { [resolver] in _ = try? await resolver.resolve(Track(id: link.id, title: "Copied link"), priority: .background) }
        }
    }
    func panelClosed() {
        player.panelVisible(false); clipboardTask?.cancel(); artwork.cancelAll(); flushSave()
    }
    func recheck() {
        dependencyText = "Checking…"
        Task {
            do { let probe = try await resolver.recheck(); dependencyText = "yt-dlp \(probe.version)" }
            catch { dependencyText = error.localizedDescription }
        }
    }
    func setLogin(_ enabled: Bool) {
        do { if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
        catch { message = error.localizedDescription }
    }
    func shutdown() { player.shutdown(); importTask?.cancel(); downloadTask?.cancel(); clipboardTask?.cancel(); flushSave() }
    private func updateStorage() async {
        let entries = await cache.snapshot()
        savedTrackIDs = Set(entries.filter(\.complete).map(\.trackID))
        storageBytes = entries.reduce(0) { $0 + $1.storedBytes }
    }
    private func updateDependency() async {
        if let probe = await resolver.dependencyStatus() { dependencyText = "yt-dlp \(probe.version)" }
    }
    private func saveConfiguration() {
        library.shuffle = player.shuffle; library.repeatMode = player.repeatMode; library.volume = player.volume; scheduleSave()
    }
    private func scheduleSave() {
        guard !preview else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushSave() }; saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }
    func flushSave() {
        saveWork?.cancel(); saveWork = nil; guard !preview else { return }
        library.volume = player.volume
        do { try Paths.write(library, to: root.appendingPathComponent("library.json")) }
        catch { message = "Your library couldn’t be saved. \(error.localizedDescription)" }
    }
}

#if DEBUG
enum PreviewData {
    static let library: LibraryDocument = {
        let rows = [("late", "Late Night Coding", "Lofi Girl", "jfKfPfyJRdk", 48),
                    ("soft", "Soft Focus", "Chillhop Music", "5yx6BWlEVcY", 32),
                    ("rain", "Rainy Sunday", "College Music", "lTRiuFIWV54", 24),
                    ("piano", "Piano for Thinking", "Ambient Notes", "4Tr0otuiQuU", 36),
                    ("radio", "Lofi Radio", "Lofi Girl", "0sfDth4lMLc", 1)]
        var document = LibraryDocument()
        document.collections = rows.map { id, title, creator, video, count in
            let track = Track(id: video, title: title == "Late Night Coding" ? "After Hours" : title, artist: creator,
                              duration: 2538, thumbnail: nil, isLive: id == "radio")
            var result = Collection(id: id, title: title, creator: creator, source: track.url, tracks: Array(repeating: track, count: count), keepsOffline: id == "rain")
            result.resumePosition = id == "late" ? 754 : 0; return result
        }
        document.selectedID = "late"; return document
    }()
}
#endif
