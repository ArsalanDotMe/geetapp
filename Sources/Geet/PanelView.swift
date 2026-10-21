import SwiftUI
import ServiceManagement
import GeetCore

private let sage = Color(red: 0.32, green: 0.40, blue: 0.29)

struct PanelView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var player: Player
    let height: CGFloat
    @State private var tab = 0
    @State private var detail: String?
    @State private var settings = false
    @State private var support = false
    @State private var adding = false
    @State private var searching = false
    @State private var search = ""
    @State private var link = ""
    @FocusState private var linkFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 12) {
            header
            if settings { settingsView }
            else if support { supportView }
            else if let id = detail, let collection = store.library.collections.first(where: { $0.id == id }) { detailView(collection) }
            else {
                CollectionPicker(selection: $tab).frame(height: 28)
                if searching {
                    TextField("Search playlists", text: $search).textFieldStyle(.roundedBorder)
                        .onExitCommand { searching = false; search = "" }
                }
                ScrollView {
                    if tab == 0 { libraryView } else { discoverView }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: .infinity)
                if store.busy { HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Opening your link…").font(.system(size: 12)); Spacer() } }
                if let copied = store.clipboardLink, !store.busy {
                    HStack {
                        Button { store.add(copied) } label: { Label("Add copied link", systemImage: "link") }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        Spacer()
                        Button { store.clipboardLink = nil } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain)
                    }.padding(10).background(.quaternary, in: .rect(cornerRadius: 10))
                }
                if player.track != nil || store.preview {
                    TransportView(player: player, clock: player.clock, artwork: store.artwork, preview: store.preview, acceptsSpace: !adding && !searching,
                                  showQueue: { detail = player.collectionID ?? store.library.collections.first?.id })
                } else {
                    HStack(spacing: 7) { Image(systemName: "waveform"); Text("A little room for your music.") }
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(height: 30)
                }
            }
        }
        .padding(18)
        .frame(width: 450, height: height)
        .tint(sage)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.30))
        .overlay { if adding { addOverlay } }
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: tab)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: detail)
        .alert("Geet", isPresented: Binding(get: { store.message != nil || player.error != nil }, set: { if !$0 { store.message = nil; player.error = nil } })) {
            Button("OK") { store.message = nil; player.error = nil }
        } message: { Text(store.message ?? player.error ?? "") }
        .onDrop(of: [.url, .plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: String.self) { value, _ in
                if let value { Task { @MainActor in store.add(value) } }
            }; return true
        }
        .onAppear {
            #if DEBUG
            if let index = CommandLine.arguments.firstIndex(of: "--capture-screen"), CommandLine.arguments.indices.contains(index + 1) {
                switch CommandLine.arguments[index + 1] {
                case "discover": tab = 1
                case "settings": settings = true
                case "detail": detail = store.library.collections.first?.id
                case "add": adding = true; linkFocused = true
                default: break
                }
            }
            #endif
        }
    }
    private var header: some View {
        HStack(spacing: 14) {
            if detail != nil || settings || support {
                Button { detail = nil; settings = false; support = false } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)) }
                    .buttonStyle(.plain).help("Back to your library")
            }
            Text(settings ? "Settings" : support ? "Support Geet" : "Geet")
                .font(.system(size: 22, weight: .bold, design: .rounded)).tracking(-0.5)
            Spacer()
            if !settings && !support {
                Button { searching.toggle(); if !searching { search = "" } } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain).help("Search playlists").accessibilityLabel("Search playlists")
                Button { adding = true; linkFocused = true } label: { Image(systemName: "plus").font(.system(size: 20, weight: .regular)) }
                    .buttonStyle(.plain).help("Add a YouTube link").accessibilityLabel("Add playlist").accessibilityIdentifier("add-playlist")
            }
            Menu {
                Button("Settings…") { settings = true; support = false; detail = nil }
                Button("Support Geet…") { support = true; settings = false; detail = nil }
                Divider()
                Button("Quit Geet", role: .destructive) { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape").font(.system(size: 17)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).tint(.primary).fixedSize().help("Settings and more").accessibilityLabel("Settings and more")
        }.foregroundStyle(.primary).frame(height: 29)
    }
    private var filtered: [Collection] { store.library.collections.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.creator.localizedCaseInsensitiveContains(search) } }
    @ViewBuilder private var libraryView: some View {
        if filtered.isEmpty {
            VStack(spacing: 18) {
                CoverArt(url: nil, store: store.artwork).frame(height: 190).clipShape(.rect(cornerRadius: 13))
                Text(search.isEmpty ? "Make yourself a little music library." : "No playlists found.")
                    .font(.system(size: 21, weight: .semibold, design: .rounded)).multilineTextAlignment(.center).padding(.horizontal, 18)
                Text(search.isEmpty ? "Bring a YouTube playlist or a favourite long mix. Your next good listening session starts here." : "Try a different name or creator.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 26)
                if search.isEmpty {
                    Button { adding = true; linkFocused = true } label: { Label("Add a playlist", systemImage: "plus") }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    Button("Find something in Discover") { tab = 1 }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }.padding(.bottom, 18)
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
            CoverArt(url: collection.thumbnail, store: store.artwork, seed: collection.id).frame(height: 190).clipped()
            LinearGradient(colors: [.clear, .black.opacity(0.12), .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
            HStack(alignment: .bottom, spacing: 10) {
                Button { detail = collection.id } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(collection.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                        Text(collection.subtitle).font(.system(size: 12)).opacity(0.9).lineLimit(1)
                    }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("View tracks")
                HStack(spacing: 10) {
                    playButton(collection, prominent: true)
                    collectionMenu(collection, light: true)
                }.frame(height: 40)
            }.padding(14)
        }
        .frame(height: 190).clipShape(.rect(cornerRadius: 13))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(collection.title)
    }
    @Environment(\.colorScheme) private var colorScheme
    private func playlistBand(_ collection: Collection) -> some View {
        let base = colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color(red: 0.96, green: 0.94, blue: 0.89)
        return ZStack {
            CoverArt(url: collection.thumbnail, store: store.artwork, seed: collection.id)
            LinearGradient(stops: [.init(color: base, location: 0), .init(color: base.opacity(0.99), location: 0.27),
                                   .init(color: base.opacity(0.86), location: 0.5), .init(color: base.opacity(0.08), location: 1)], startPoint: .leading, endPoint: .trailing)
            HStack(spacing: 10) {
                Button { detail = collection.id } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(collection.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        HStack(spacing: 4) {
                            Text(collection.subtitle).lineLimit(1)
                            if collection.tracks.allSatisfy({ store.savedTrackIDs.contains($0.id) }) || store.preview && collection.keepsOffline {
                                Image(systemName: "arrow.down.circle.fill").foregroundStyle(sage).help("Available offline")
                            }
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                        if let progress = store.downloads[collection.id] { ProgressView(value: progress).frame(width: 140).tint(sage) }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help("View tracks")
                playButton(collection)
                Button { detail = collection.id } label: { Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary) }
                    .buttonStyle(.plain).help("View tracks in \(collection.title)")
            }.padding(.horizontal, 13)
        }
        .frame(height: 66).clipShape(.rect(cornerRadius: 11))
        .contextMenu { collectionMenuItems(collection) }
    }
    private func playButton(_ collection: Collection, prominent: Bool = false) -> some View {
        let active = player.collectionID == collection.id && (player.isPlaying || player.isLoading)
        let selectedPreview = store.preview && collection.id == "late"
        return Button { store.play(collection) } label: {
            Group {
                if player.collectionID == collection.id && player.isLoading { ProgressView().controlSize(.small) }
                else { Image(systemName: active || selectedPreview ? "pause.fill" : "play.fill").font(.system(size: prominent ? 16 : 13, weight: .semibold)).offset(x: active || selectedPreview ? 0 : 1) }
            }.foregroundStyle(Color.black.opacity(0.85)).frame(width: prominent ? 40 : 34, height: prominent ? 40 : 34)
                .background(.white.opacity(prominent ? 0.94 : 0.89), in: Circle())
        }.buttonStyle(PressScale()).help(active ? "Pause \(collection.title)" : "Play \(collection.title)")
            .accessibilityLabel(active ? "Pause \(collection.title)" : "Play \(collection.title)")
    }
    private func collectionMenu(_ collection: Collection, light: Bool = false) -> some View {
        Menu { collectionMenuItems(collection) } label: {
            Image(systemName: "ellipsis").font(.system(size: 15)).foregroundStyle(light ? .white : .primary)
                .frame(width: 30, height: 34).background(.white.opacity(light ? 0.16 : 0), in: Circle())
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).tint(light ? .white : .primary).fixedSize().help("Playlist options")
    }
    @ViewBuilder private func collectionMenuItems(_ collection: Collection) -> some View {
        Button("Play from beginning") { store.play(collection, beginning: true) }
        Button("View tracks") { detail = collection.id }
        Button("Move to top") { store.moveToTop(collection) }
        Divider()
        Button(collection.keepsOffline ? "Stop keeping offline" : "Keep offline") {
            if collection.keepsOffline { store.removeOffline(collection) } else { store.keepOffline(collection) }
        }
        Button("Refresh playlist") { store.refresh(collection) }
        Button("Open on YouTube") { NSWorkspace.shared.open(collection.source) }
        Divider()
        Button("Remove from library", role: .destructive) { store.remove(collection) }
    }
    private var discoverView: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            Text("Settle into something good.").font(.system(size: 21, weight: .semibold, design: .rounded)).padding(.top, 5)
            Text("A few places to find your focus.").font(.system(size: 13)).foregroundStyle(.secondary)
            ForEach(AppStore.discover) { pick in
                VStack(alignment: .leading, spacing: 0) {
                    CoverArt(url: pick.thumbnail, store: store.artwork).frame(height: 145).clipped()
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(pick.title).font(.system(size: 14, weight: .semibold))
                            Text(pick.creator).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { store.add(pick.url.absoluteString, playAfter: true) } label: { Image(systemName: "play.fill").frame(width: 27, height: 27) }.buttonStyle(.glass).buttonBorderShape(.circle).help("Play and add to library")
                        Button { store.add(pick.url.absoluteString) } label: { Image(systemName: "plus").frame(width: 24, height: 24) }.buttonStyle(.plain).help("Add to library")
                    }.padding(12)
                }.background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 12)).clipShape(.rect(cornerRadius: 12))
            }
            Text("Selections are curated, not a live popularity chart.").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.bottom, 8)
        }
    }
    private func detailView(_ collection: Collection) -> some View {
        VStack(spacing: 12) {
            hero(collection)
            HStack {
                Text("\(collection.tracks.count) \(collection.tracks.count == 1 ? "item" : "tracks")").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer(); collectionMenu(collection)
            }
            if collection.truncated { Text("Showing the first 1,000 tracks.").font(.system(size: 12)).foregroundStyle(.secondary) }
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(collection.tracks.enumerated()), id: \.offset) { index, track in
                        Button { store.play(collection, index: index) } label: {
                            HStack(spacing: 10) {
                                Text(String(index + 1)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                                    Text(track.artist).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                if store.savedTrackIDs.contains(track.id) { Image(systemName: "arrow.down.circle.fill").foregroundStyle(sage).font(.system(size: 11)) }
                                Text(track.isLive ? "Live" : timeLabel(track.duration ?? 0)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                            }.padding(.vertical, 9).padding(.horizontal, 6).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.scrollIndicators(.hidden)
            if player.track != nil { TransportView(player: player, clock: player.clock, artwork: store.artwork, preview: false, acceptsSpace: !adding, showQueue: {}) }
        }.frame(maxHeight: .infinity)
    }
    private var settingsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle("Open at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: store.setLogin))
                        Text("Geet stays in your menu bar and waits until you press Play.").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(8)
                }
                GroupBox("Offline listening") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Save audio as I listen", isOn: Binding(get: { store.library.automaticCache }, set: store.setAutomaticCache)).disabled(!store.offlineEnabled)
                        Text("The listening cache keeps up to 2 GB. Playlists you choose to keep offline stay saved, within 10 GB total.")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        HStack {
                            Text(ByteCountFormatter.string(fromByteCount: store.storageBytes, countStyle: .file)).font(.system(size: 13, weight: .medium))
                            Spacer(); Button("Clear listening cache") { store.clearAutomaticCache() }
                        }
                        if !store.downloads.isEmpty { Button("Cancel download") { store.cancelDownload() } }
                        if !store.offlineEnabled { Button("Unlock offline listening") { settings = false; support = true } }
                        #if DEBUG
                        Text("Development build: offline listening is enabled for testing.").font(.system(size: 11)).foregroundStyle(.secondary)
                        #endif
                    }.padding(8)
                }
                GroupBox("YouTube playback") {
                    HStack {
                        Text(store.dependencyText).font(.system(size: 12)).textSelection(.enabled)
                        Spacer(); Button("Recheck") { store.recheck() }
                    }.padding(8)
                }
                Button("Support Geet") { settings = false; support = true }.buttonStyle(.plain).foregroundStyle(sage)
                Text("Geet 0.1 · Made for a quieter desktop").font(.system(size: 11)).foregroundStyle(.tertiary)
            }.padding(.top, 10)
        }.frame(maxHeight: .infinity)
    }
    private var supportView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "heart.circle").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(sage)
            Text("Keep your music close.").font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("A one-time $5 contribution unlocks offline listening and helps keep Geet going.")
                .font(.system(size: 14)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 28)
            Text("Checkout is coming soon. Streaming is free.").font(.system(size: 12)).foregroundStyle(.secondary)
            Button("Back to my music") { support = false }.buttonStyle(.glassProminent).controlSize(.large)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var addOverlay: some View {
        ZStack {
            Color.black.opacity(0.16).onTapGesture { adding = false }
            VStack(alignment: .leading, spacing: 17) {
                HStack { Text("Bring your music.").font(.system(size: 22, weight: .semibold, design: .rounded)); Spacer(); Button { adding = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close") }
                Text("Paste a YouTube playlist, a long mix, or a live radio link.").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("https://youtube.com/playlist?list=…", text: $link).textFieldStyle(.roundedBorder).focused($linkFocused)
                    .onSubmit { submitLink() }.accessibilityIdentifier("youtube-link")
                HStack {
                    Button("Paste") { link = NSPasteboard.general.string(forType: .string) ?? "" }.buttonStyle(.plain)
                    Spacer(); Button("Add to library") { submitLink() }.buttonStyle(.glassProminent).disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 382).background(.regularMaterial, in: .rect(cornerRadius: 20)).shadow(color: .black.opacity(0.12), radius: 24, y: 10)
        }.onExitCommand { adding = false }
    }
    private func submitLink() { store.add(link); if (try? YouTubeLink(link)) != nil { adding = false; link = "" } }
}

private struct PressScale: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1).animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct TransportView: View {
    @ObservedObject var player: Player
    @ObservedObject var clock: PlayerClock
    let artwork: ArtworkStore
    let preview: Bool
    var acceptsSpace = true
    let showQueue: () -> Void
    @State private var scrubbing = false
    @State private var scrubPosition = 0.0
    @State private var volumeOpen = false
    private var elapsed: Double { preview ? 754 : scrubbing ? scrubPosition : clock.position }
    private var duration: Double { preview ? 2538 : max(clock.duration, 1) }
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                CoverArt(url: player.track?.thumbnail, store: artwork).frame(width: 43, height: 43).clipShape(.rect(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(player.track?.title ?? "After Hours").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(preview ? "Late Night Coding" : player.collectionTitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Button(action: showQueue) { Image(systemName: "list.bullet").font(.system(size: 15)) }.buttonStyle(.plain).help("View playlist tracks").accessibilityLabel("View playlist tracks")
            }
            if player.track?.isLive == true {
                HStack(spacing: 5) { Circle().fill(sage).frame(width: 5, height: 5); Text("Live radio").font(.system(size: 10)); Spacer() }.padding(.vertical, 3)
            } else {
                HStack(spacing: 9) {
                    Text(timeLabel(elapsed)).frame(minWidth: 31, alignment: .leading)
                    Slider(value: Binding(get: { elapsed }, set: { scrubPosition = $0 }), in: 0...duration, onEditingChanged: { editing in
                        if editing { scrubPosition = clock.position; scrubbing = true }
                        else { player.seek(scrubPosition); scrubbing = false }
                    }).controlSize(.mini).accessibilityLabel("Playback position")
                    Text(timeLabel(preview ? 2538 : clock.duration)).frame(minWidth: 31, alignment: .trailing)
                }.font(.system(size: 9).monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 24) {
                Spacer(minLength: 0)
                transportButton("shuffle", label: "Shuffle", active: player.shuffle, action: player.toggleShuffle)
                transportButton("backward.end.fill", label: "Previous", action: player.previous)
                Button { player.toggle() } label: {
                    Group { if player.isLoading { ProgressView().controlSize(.small) } else { Image(systemName: player.isPlaying || preview ? "pause.fill" : "play.fill").font(.system(size: 18, weight: .medium)) } }
                        .foregroundStyle(.white).frame(width: 43, height: 43).background(sage, in: Circle())
                }.buttonStyle(PressScale()).help(player.isPlaying ? "Pause" : "Play").accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                    .keyboardShortcut(acceptsSpace ? KeyboardShortcut(.space, modifiers: []) : nil)
                transportButton("forward.end.fill", label: "Next", action: { player.next() })
                transportButton(player.repeatMode == .one ? "repeat.1" : "repeat", label: "Repeat: \(player.repeatMode.rawValue)", active: player.repeatMode != .off, action: player.cycleRepeat)
                Button { volumeOpen.toggle() } label: { Image(systemName: player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill").font(.system(size: 12)) }
                    .buttonStyle(.plain).help("Volume").accessibilityLabel("Volume")
                    .popover(isPresented: $volumeOpen) {
                        HStack {
                            Button { player.volume = player.volume == 0 ? 0.8 : 0 } label: { Image(systemName: player.volume == 0 ? "speaker.slash" : "speaker.wave.2") }.buttonStyle(.plain).help("Mute or unmute")
                            Slider(value: Binding(get: { Double(player.volume) }, set: { player.volume = Float($0) }), in: 0...1).accessibilityLabel("Volume level")
                        }.padding(14).frame(width: 190)
                    }
                Spacer(minLength: 0)
            }
        }.padding(12)
            .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
    }
    private func transportButton(_ symbol: String, label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(active ? sage : Color.primary.opacity(0.7)) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
}

private struct CollectionPicker: NSViewRepresentable {
    @Binding var selection: Int
    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["Library", "Discover"], trackingMode: .selectOne, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentStyle = .rounded; control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.font = .systemFont(ofSize: 13, weight: .medium)
        control.setAccessibilityLabel("Library and Discover"); control.setAccessibilityIdentifier("collection-tabs")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection; control.selectedSegment = selection
    }
    final class Coordinator: NSObject {
        var selection: Binding<Int>
        init(selection: Binding<Int>) { self.selection = selection }
        @objc func changed(_ sender: NSSegmentedControl) { selection.wrappedValue = sender.selectedSegment }
    }
}

func timeLabel(_ value: Double) -> String {
    guard value.isFinite, value >= 0 else { return "0:00" }
    let seconds = Int(value)
    return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60) : String(format: "%d:%02d", seconds / 60, seconds % 60)
}
