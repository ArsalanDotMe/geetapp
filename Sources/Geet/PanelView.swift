import SwiftUI
import ServiceManagement
import GeetCore

struct PanelView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var player: Player
    let height: CGFloat
    var startingScreen: String? = nil
    @State private var tab = 0
    @State private var detail: String?
    @State private var settings = false
    @State private var adding = false
    @State private var searching = false
    @State private var search = ""
    @State private var link = ""
    @FocusState private var linkFocused: Bool
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            header
            if settings { settingsView }
            else if let id = detail, let collection = store.collection(for: id) { detailView(collection) }
            else {
                CollectionPicker(selection: $tab).frame(height: 32)
                if searching {
                    TextField(tab == 0 ? "Search your library" : "Search Discover", text: $search).textFieldStyle(.roundedBorder).focused($searchFocused)
                        .accessibilityIdentifier("playlist-search").onAppear { searchFocused = true }
                        .onExitCommand { searching = false; search = "" }
                }
                if tab == 0 {
                    ScrollView { libraryView }.scrollIndicators(.never).frame(maxHeight: .infinity)
                } else {
                    DiscoverBrowser(store: store, player: player, search: search).frame(maxHeight: .infinity)
                }
                if let copied = store.clipboardLink, !store.busy {
                    HStack {
                        Button { store.add(copied) } label: { Label("Add copied link", systemImage: "link") }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button { store.clipboardLink = nil } label: { Image(systemName: "xmark").font(.system(size: 10)).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Dismiss copied link").accessibilityIdentifier("dismiss-copied-link")
                    }.padding(10).background(.quaternary, in: .rect(cornerRadius: 10))
                }
            }
            if store.busy {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(store.importingCollectionID == nil ? "Refreshing playlist…" : "Adding to your library…").font(.system(size: 12))
                    Spacer()
                    Button("Cancel", action: store.cancelImport).buttonStyle(.plain).font(.system(size: 12)).accessibilityIdentifier("cancel-import")
                }
            }
            if player.track != nil || store.preview {
                TransportView(player: player, clock: player.clock, artwork: store.artwork, preview: store.preview, acceptsSpace: !adding && !searching,
                              compact: tab == 1 && detail == nil && !settings,
                              showQueue: {
                                  let queueID = player.collectionID ?? store.library.collections.first?.id
                                  let isShowingQueue = !settings && detail != nil && detail == queueID
                                  settings = false
                                  detail = isShowingQueue ? nil : queueID
                              })
            }
        }
        .padding(GeetStyle.inset)
        .frame(width: GeetStyle.panelWidth, height: height)
        .tint(GeetStyle.accent)
        .foregroundStyle(GeetStyle.ink)
        .background(GeetStyle.panel.opacity(0.58))
        .allowsHitTesting(!adding)
        .accessibilityHidden(adding)
        .overlay { if adding { addOverlay } }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: tab)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: detail)
        .alert("geet", isPresented: Binding(get: { store.message != nil || player.error != nil }, set: { if !$0 { store.message = nil; player.error = nil } })) {
            Button("OK") { store.message = nil; player.error = nil }
        } message: { Text(store.message ?? player.error ?? "") }
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            if provider.canLoadObject(ofClass: NSURL.self) {
                _ = provider.loadObject(ofClass: NSURL.self) { value, _ in
                    if let value = value as? URL { Task { @MainActor in store.add(value.absoluteString) } }
                }
            } else {
                _ = provider.loadObject(ofClass: String.self) { value, _ in
                    if let value { Task { @MainActor in store.add(value) } }
                }
            }
            return true
        }
        .onAppear {
            #if DEBUG
            let index = CommandLine.arguments.firstIndex(of: "--capture-screen")
            if let screen = startingScreen ?? index.flatMap({ CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil }) {
                switch screen {
                case "discover": tab = 1
                case "settings": settings = true
                case "detail": detail = store.library.collections.first?.id
                case "add": adding = true; linkFocused = true
                case "search": searching = true; search = "Chillhop"
                case "empty": if store.preview { store.library.collections = [] }
                case "no-results": searching = true; search = "no matching music"
                default: break
                }
            }
            #endif
        }
    }
    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if detail != nil || settings {
                    Button { detail = nil; settings = false } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13, weight: .medium))
                            .frame(width: 32, height: 32).contentShape(Circle())
                    }.buttonStyle(.plain).geetGlass(in: Circle(), interactive: true)
                        .help(tab == 1 ? "Back to Discover" : "Back to library").accessibilityLabel(tab == 1 ? "Back to Discover" : "Back to library").accessibilityIdentifier("back-to-library")
                } else {
                    ListenerMark().frame(width: 30, height: 30)
                }
                if settings {
                    Text("Settings").font(BrandTypography.editorial)
                }
                Spacer()
                if !settings && detail == nil {
                    Button { searching.toggle(); if !searching { search = "" } } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 14)).frame(width: 32, height: 32).contentShape(Circle())
                    }.buttonStyle(.plain).geetGlass(in: Circle(), interactive: true)
                        .help("Search playlists").accessibilityLabel("Search playlists").accessibilityIdentifier("search-playlists")
                    Button { adding = true; linkFocused = true } label: {
                        Image(systemName: "plus").font(.system(size: 17)).frame(width: 32, height: 32).contentShape(Circle())
                    }.buttonStyle(.plain).geetGlass(in: Circle(), interactive: true)
                        .help("Add a YouTube link").accessibilityLabel("Add a YouTube link").accessibilityIdentifier("add-playlist")
                }
                Menu {
                    Button("Settings…") { settings = true; detail = nil }
                    Divider()
                    Button("Quit geet", role: .destructive) { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: {
                    Image(systemName: "gearshape").font(.system(size: 15)).frame(width: 32, height: 32)
                        .geetGlass(in: Circle(), interactive: true).contentShape(Circle())
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Settings and more").accessibilityLabel("Settings and more").accessibilityIdentifier("settings-menu")
            }
        }.foregroundStyle(GeetStyle.ink).frame(height: 32)
    }
    private var filtered: [Collection] { store.library.collections.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.creator.localizedCaseInsensitiveContains(search) } }
    @ViewBuilder private var libraryView: some View {
        if filtered.isEmpty {
            VStack(spacing: 18) {
                Text(search.isEmpty ? "Your library is empty." : "No playlists found")
                    .font(BrandTypography.editorial).multilineTextAlignment(.center).padding(.horizontal, 18)
                Text(search.isEmpty ? "Add your favourites or head over to Discover to start listening." : "Try another title or creator.")
                    .font(.system(size: 13)).foregroundStyle(GeetStyle.secondary).multilineTextAlignment(.center).padding(.horizontal, 26)
                if search.isEmpty {
                    Button { adding = true; linkFocused = true } label: { Label("Add a playlist", systemImage: "plus") }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    Button("Browse Discover") { tab = 1 }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(GeetStyle.secondary)
                }
            }.padding(.top, 40).padding(.bottom, 18)
        } else {
            LazyVStack(spacing: 7) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, collection in
                    if index == 0 { hero(collection) } else { playlistBand(collection) }
                }
            }
        }
    }
    private func hero(_ collection: Collection) -> some View {
        ZStack(alignment: .bottom) {
            CoverArt(url: collection.thumbnail, store: store.artwork, seed: collection.id).frame(height: 180).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.85)], startPoint: .center, endPoint: .bottom).allowsHitTesting(false)
            HStack(alignment: .bottom, spacing: 10) {
                Button { detail = collection.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            if player.collectionID == collection.id || store.preview && collection.id == "late" {
                                Image(systemName: "waveform").accessibilityLabel("Current playlist")
                            }
                            Text(collection.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                        }
                        Text(collection.subtitle).font(.system(size: 12)).opacity(0.9).lineLimit(1)
                        if let progress = store.downloads[collection.id] {
                            ProgressView(value: progress).tint(.white)
                                .accessibilityLabel("Saving playlist offline")
                        }
                    }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("View tracks").accessibilityIdentifier("library-open-\(collection.id)")
                HStack(spacing: 10) {
                    playButton(collection, prominent: true)
                    collectionMenu(collection, light: true)
                }.frame(height: 40)
            }.padding(14)
        }
        .frame(height: 180).clipShape(.rect(cornerRadius: GeetStyle.cardRadius))
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(collection.title)
    }
    private func playlistBand(_ collection: Collection) -> some View {
        ZStack {
            CoverArt(url: collection.thumbnail, store: store.artwork, seed: collection.id)
            ArtworkFade()
            HStack(spacing: 10) {
                Button { detail = collection.id } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collection.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(collection.subtitle).lineLimit(1)
                            if collection.tracks.allSatisfy({ store.savedTrackIDs.contains($0.id) }) || store.preview && collection.keepsOffline {
                                Image(systemName: "arrow.down.circle.fill").foregroundStyle(GeetStyle.accent).help("Available offline")
                            }
                        }.font(.system(size: 12)).foregroundStyle(GeetStyle.secondary)
                        if let progress = store.downloads[collection.id] { ProgressView(value: progress).frame(width: 140).tint(GeetStyle.accent) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("View tracks").accessibilityIdentifier("library-open-\(collection.id)")
                playButton(collection)
                Button { detail = collection.id } label: {
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2).frame(width: 28, height: 32).contentShape(Rectangle())
                }.buttonStyle(.plain).help("View tracks in \(collection.title)").accessibilityLabel("View tracks in \(collection.title)")
            }.padding(.horizontal, 13)
        }
        .frame(height: 64).clipShape(.rect(cornerRadius: GeetStyle.cardRadius))
        .contentShape(Rectangle())
        .contextMenu { collectionMenuItems(collection) }
    }
    private func playButton(_ collection: Collection, prominent: Bool = false) -> some View {
        let active = player.collectionID == collection.id && (player.isPlaying || player.isLoading)
        let selectedPreview = store.preview && collection.id == "late"
        return Button { store.play(collection) } label: {
            Group {
                if player.collectionID == collection.id && player.isLoading { ProgressView().controlSize(.small) }
                else { Image(systemName: active || selectedPreview ? "pause.fill" : "play.fill").font(.system(size: prominent ? 16 : 13, weight: .semibold)).offset(x: active || selectedPreview ? 0 : 1) }
            }.foregroundStyle(GeetStyle.artworkControlInk).frame(width: prominent ? 40 : 34, height: prominent ? 40 : 34)
                .geetGlass(in: Circle(), interactive: true, tint: GeetStyle.artworkControlFill)
        }.buttonStyle(PressScale()).help(active ? "Pause \(collection.title)" : "Play \(collection.title)")
            .accessibilityLabel(active ? "Pause \(collection.title)" : "Play \(collection.title)")
            .accessibilityIdentifier("library-play-\(collection.id)")
    }
    private func collectionMenu(_ collection: Collection, light: Bool = false) -> some View {
        Menu { collectionMenuItems(collection) } label: {
            Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(GeetStyle.artworkControlInk)
                .frame(width: 30, height: 34).geetGlass(in: Circle(), interactive: true, tint: GeetStyle.artworkControlFill).contentShape(Circle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(light ? .white : .primary).fixedSize().help("Playlist options").accessibilityLabel("Options for \(collection.title)").accessibilityIdentifier("collection-options-\(collection.id)")
    }
    @ViewBuilder private func collectionMenuItems(_ collection: Collection) -> some View {
        Button("Play from beginning") { store.play(collection, beginning: true) }
        Button("View tracks") { detail = collection.id }
        if collection.id.hasPrefix("discover:") {
            if let pick = store.discoverFeed.categories.flatMap(\.items).first(where: { $0.url == collection.source }) {
                Button(store.savedCollection(for: pick) == nil ? "Add to library" : "In your library") { store.addDiscover(pick) }
                    .disabled(store.savedCollection(for: pick) != nil || store.busy)
            }
            Button("Open on YouTube") { NSWorkspace.shared.open(collection.source) }
        } else {
        Button("Move to top") { store.moveToTop(collection) }
        Divider()
        Button(collection.keepsOffline ? "Stop keeping offline" : "Keep offline") {
            if collection.keepsOffline { store.removeOffline(collection) } else { store.keepOffline(collection) }
        }
        if store.downloads[collection.id] != nil {
            Button("Cancel download", action: store.cancelDownload)
        } else if collection.keepsOffline && collection.tracks.contains(where: { !$0.isLive && !store.savedTrackIDs.contains($0.id) }) {
            Button("Finish saving offline") { store.keepOffline(collection) }
        }
        Button("Refresh playlist") { store.refresh(collection) }
        Button("Open on YouTube") { NSWorkspace.shared.open(collection.source) }
        Divider()
        Button("Remove from library", role: .destructive) { store.remove(collection) }
        }
    }
    private func detailView(_ collection: Collection) -> some View {
        VStack(spacing: 12) {
            hero(collection)
            HStack {
                Text("\(collection.tracks.count) \(collection.tracks.count == 1 ? "track" : "tracks")").font(.system(size: 12)).foregroundStyle(GeetStyle.secondary)
                Spacer(); collectionMenu(collection)
            }
            if collection.truncated { Text("Showing the first 1,000 tracks.").font(.system(size: 12)).foregroundStyle(GeetStyle.secondary) }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(collection.tracks.enumerated()), id: \.offset) { index, track in
                        Button { store.play(collection, index: index) } label: {
                            HStack(spacing: 10) {
                                if player.collectionID == collection.id && player.currentIndex == index {
                                    Image(systemName: "waveform").foregroundStyle(GeetStyle.accent).frame(width: 24).accessibilityLabel("Current track")
                                } else {
                                    Text(String(index + 1)).font(.system(size: 11).monospacedDigit()).foregroundStyle(GeetStyle.secondary).frame(width: 24)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Text(track.artist).font(.system(size: 12)).foregroundStyle(GeetStyle.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if store.savedTrackIDs.contains(track.id) { Image(systemName: "arrow.down.circle.fill").foregroundStyle(GeetStyle.accent).font(.system(size: 11)) }
                                Text(track.isLive ? "Live" : timeLabel(track.duration ?? 0)).font(.system(size: 11).monospacedDigit()).foregroundStyle(GeetStyle.secondary)
                            }.padding(.vertical, 9).padding(.horizontal, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .background(player.collectionID == collection.id && player.currentIndex == index ? GeetStyle.accent.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
                    }
                }
            }.scrollIndicators(.never)
        }.frame(maxHeight: .infinity)
    }
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Open at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: store.setLogin))
                        Text("geet opens quietly in your menu bar.").font(.system(size: 12)).foregroundStyle(GeetStyle.secondary)
                    }.padding(8)
                }
                GroupBox("Offline listening") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Save music as I listen", isOn: Binding(get: { store.library.automaticCache }, set: store.setAutomaticCache)).disabled(!store.offlineEnabled)
                        Text("Save up to 2 GB as you listen. Music you keep offline shares a 10 GB total limit.")
                            .font(.system(size: 12)).foregroundStyle(GeetStyle.secondary)
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: store.storageBytes, countStyle: .file)).font(.system(size: 13, weight: .medium))
                            Spacer(); Button("Clear listening cache") { store.clearAutomaticCache() }
                        }
                        if !store.downloads.isEmpty { Button("Cancel download") { store.cancelDownload() } }
                        if !store.offlineEnabled { Text("Offline listening is coming soon").font(.system(size: 12)).foregroundStyle(GeetStyle.secondary) }
                        #if DEBUG
                        Text("Development build: offline listening is enabled for testing.").font(.system(size: 11)).foregroundStyle(GeetStyle.secondary)
                        #endif
                    }.padding(8)
                }
                GroupBox("YouTube playback") {
                    HStack {
                        Text(store.dependencyText).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(); Button("Check again") { store.recheck() }
                    }.padding(8)
                }
                Text("geet 0.1").font(.system(size: 11)).foregroundStyle(GeetStyle.secondary)
            }.padding(.top, 6).padding(.bottom, 4)
                .groupBoxStyle(GeetSettingsGroupStyle()).toggleStyle(.switch).controlSize(.small)
        }.scrollIndicators(.never).frame(maxHeight: .infinity)
    }
    private var addOverlay: some View {
        ZStack {
            Color.black.opacity(0.16).onTapGesture { adding = false }
            VStack(alignment: .leading, spacing: 17) {
                HStack { Text("Add your music").font(BrandTypography.editorial); Spacer(); Button { adding = false } label: { Image(systemName: "xmark").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("close-add") }
                Text("Paste a YouTube playlist, mix, or live radio link.").font(.system(size: 13)).foregroundStyle(GeetStyle.secondary)
                TextField("YouTube link", text: $link).textFieldStyle(.roundedBorder).focused($linkFocused)
                    .onSubmit { submitLink() }.accessibilityIdentifier("youtube-link")
                HStack {
                    Button("Paste") { link = NSPasteboard.general.string(forType: .string) ?? "" }.buttonStyle(.plain)
                    Spacer(); Button("Add to library") { submitLink() }.buttonStyle(.glassProminent).disabled(store.busy || link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("confirm-add")
                }
            }.padding(24).frame(width: 382).background(GeetStyle.panel, in: .rect(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(GeetStyle.secondary.opacity(0.22), lineWidth: 0.5).allowsHitTesting(false))
                .shadow(color: GeetStyle.ink.opacity(0.15), radius: 24, y: 10)
        }.onExitCommand { adding = false }.task {
            // Wait for the overlay's native field to join the key window.
            linkFocused = false
            try? await Task.sleep(for: .milliseconds(100))
            if !Task.isCancelled { linkFocused = true }
        }
    }
    private func submitLink() { guard !store.busy else { return }; store.add(link); if (try? YouTubeLink(link)) != nil { adding = false; link = "" } }
}

struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        // Glass draws the circle but does not make its transparent padding clickable.
        configuration.label.contentShape(Circle()).scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1).animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TransportView: View {
    @ObservedObject var player: Player
    @ObservedObject var clock: PlayerClock
    let artwork: ArtworkStore
    let preview: Bool
    var acceptsSpace = true
    var compact = false
    let showQueue: () -> Void
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    @State private var volumeOpen = false
    private var elapsed: Double { preview ? 754 : scrubbing ? scrubPosition : clock.position }
    private var duration: Double { preview ? 2538 : max(clock.duration, 1) }
    var body: some View {
        VStack(spacing: compact ? 4 : 7) {
            HStack(spacing: 10) {
                CoverArt(url: player.track?.thumbnail, store: artwork).frame(width: compact ? 32 : 43, height: compact ? 32 : 43).clipShape(.rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.track?.title ?? "After Hours").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(preview ? "Late Night Coding" : player.collectionTitle).font(.system(size: 12)).foregroundStyle(GeetStyle.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Button(action: showQueue) { Image(systemName: "list.bullet").font(.system(size: 15)).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).help("View playlist tracks").accessibilityLabel("View playlist tracks").accessibilityIdentifier("show-queue")
            }
            if player.track?.isLive == true {
                HStack(spacing: 5) { Circle().fill(GeetStyle.accent).frame(width: 5, height: 5); Text("Live radio").font(.system(size: 10)); Spacer() }.padding(.vertical, 3)
            } else {
                HStack(spacing: 9) {
                    Text(timeLabel(elapsed)).frame(minWidth: 31, alignment: .leading)
                    Slider(value: Binding(get: { elapsed }, set: { scrubPosition = $0 }), in: 0...duration, onEditingChanged: { editing in
                        if editing { scrubPosition = clock.position; scrubbing = true }
                        else { player.seek(scrubPosition); scrubbing = false }
                    }).controlSize(.mini).accessibilityLabel("Playback position")
                    Text(timeLabel(preview ? 2538 : clock.duration)).frame(minWidth: 31, alignment: .trailing)
                }.font(.system(size: 10).monospacedDigit()).foregroundStyle(GeetStyle.secondary)
            }
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                transportButton("shuffle", label: "Shuffle", active: player.shuffle, state: player.shuffle ? "On" : "Off", action: player.toggleShuffle)
                transportButton("backward.end.fill", label: "Previous", action: player.previous)
                Button { player.toggle() } label: {
                    Group { if player.isLoading { ProgressView().controlSize(.small) } else { Image(systemName: player.isPlaying || preview ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .medium)) } }
                        .foregroundStyle(GeetStyle.accentInk).frame(width: compact ? 36 : 43, height: compact ? 36 : 43)
                        .glassEffect(.regular.tint(GeetStyle.accent).interactive(), in: Circle())
                }.buttonStyle(PressScale()).help(player.isLoading ? "Cancel playback" : player.isPlaying ? "Pause" : "Play").accessibilityLabel(player.isLoading ? "Cancel playback" : player.isPlaying ? "Pause" : "Play")
                    .keyboardShortcut(acceptsSpace ? KeyboardShortcut(.space, modifiers: []) : nil)
                    .accessibilityIdentifier("transport-play")
                transportButton("forward.end.fill", label: "Next", action: { player.next() })
                transportButton(player.repeatMode == .one ? "repeat.1" : "repeat", label: player.repeatMode == .off ? "Repeat off" : player.repeatMode == .all ? "Repeat playlist" : "Repeat track", active: player.repeatMode != .off, action: player.cycleRepeat)
                Button { volumeOpen.toggle() } label: { Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 12)).frame(width: 28, height: 32).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Volume").accessibilityLabel("Volume")
                    .popover(isPresented: $volumeOpen) {
                        HStack {
                            Button { player.volume = player.volume == 0 ? 0.8 : 0 } label: { Image(systemName: player.volume == 0 ? "speaker.slash" : "speaker.wave.2").frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).help("Mute or unmute").accessibilityLabel("Mute or unmute").accessibilityIdentifier("mute")
                            Slider(value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }), in: 0...1).accessibilityLabel("Volume level")
                        }.padding(14).frame(width: 190)
                    }
                Spacer(minLength: 0)
            }
        }.padding(compact ? 8 : 14)
            .geetGlass(in: RoundedRectangle(cornerRadius: 18))
    }
    private func transportButton(_ symbol: String, label: String, active: Bool = false, state: String = "", action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(active ? GeetStyle.accent : Color.primary.opacity(0.7)).frame(width: 28, height: 32).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label).accessibilityValue(state)
    }
}

private struct CollectionPicker: View {
    @Binding var selection: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<2) { index in
                Button {
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.2)) { selection = index }
                } label: {
                    Group {
                        if selection == index {
                            Text(index == 0 ? "Library" : "Discover").frame(maxWidth: .infinity).frame(height: 28)
                                .geetGlass(in: RoundedRectangle(cornerRadius: 9), interactive: true, tint: GeetStyle.selection.opacity(0.65))
                        } else {
                            Text(index == 0 ? "Library" : "Discover").frame(maxWidth: .infinity).frame(height: 28)
                        }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).font(.system(size: 13, weight: selection == index ? .medium : .regular))
                    .foregroundStyle(selection == index ? GeetStyle.ink : GeetStyle.secondary)
                    .accessibilityAddTraits(selection == index ? .isSelected : [])
                    .accessibilityIdentifier(index == 0 ? "library-tab" : "discover-tab")
            }
        }.padding(2).background(GeetStyle.surface.opacity(0.55), in: .rect(cornerRadius: 11))
            .accessibilityElement(children: .contain).accessibilityLabel("Library and Discover").accessibilityIdentifier("collection-tabs")
    }
}

func timeLabel(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let seconds = Int(value)
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
}
