import AppKit
import SwiftUI
import GeetCore

struct DiscoverBrowser: View {
    @ObservedObject var store: AppStore
    @ObservedObject var player: Player
    let search: String
    @State private var categoryID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var category: DiscoverCategory? { store.discoverFeed.categories.first { $0.id == categoryID } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("Find your next listen").font(BrandTypography.editorial).accessibilityHidden(category != nil)
                        Spacer(minLength: 0)
                        Button { store.refreshDiscover(force: true) } label: {
                            Group {
                                if store.discoverRefreshing { ProgressView().controlSize(.small) }
                                else { Image(systemName: "arrow.clockwise").font(.system(size: 15)) }
                            }.frame(width: 32, height: 32).contentShape(Circle())
                        }.buttonStyle(.plain).disabled(!store.canRefreshDiscover || store.discoverRefreshing)
                            .help("Refresh Discover").accessibilityLabel("Refresh Discover").accessibilityIdentifier("discover-refresh")
                            .accessibilityHidden(category != nil)
                    }.padding(.top, 4)
                    if let error = store.discoverError {
                        Text(error).font(.system(size: 12)).foregroundStyle(GeetStyle.secondary)
                            .accessibilityIdentifier("discover-refresh-error")
                    }
                    ForEach(store.discoverFeed.categories) { section in
                        let items = matching(section)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Button { open(section.id) } label: {
                                    HStack(spacing: 10) {
                                        categoryHeading(section)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(GeetStyle.accent).frame(width: 32, height: 36)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).help("View \(section.title)")
                                    .accessibilityLabel("View \(section.title)")
                                    .accessibilityIdentifier("discover-category-\(section.id)")
                                    .accessibilityHidden(category != nil)
                                MouseShelf(label: section.title, identifier: section.id, active: category == nil) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(items) { pick in
                                            DiscoverItemCard(store: store, player: player, pick: pick, width: 164, compact: true)
                                        }
                                    }.fixedSize(horizontal: true, vertical: false)
                                }.frame(height: 190)
                            }
                        }
                    }
                    if store.discoverFeed.categories.allSatisfy({ matching($0).isEmpty }) { emptyState }
                }.padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            .accessibilityElement(children: .contain)
            .opacity(category == nil ? 1 : 0).offset(x: category == nil ? 0 : -35)
            .allowsHitTesting(category == nil).accessibilityHidden(category != nil)

            if let category {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Button { open(nil) } label: {
                            Label("Discover", systemImage: "chevron.left").font(.system(size: 13, weight: .medium))
                                .frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(GeetStyle.accent)
                            .accessibilityLabel("Back to Discover").accessibilityIdentifier("discover-back")
                        Spacer()
                    }
                    categoryHeading(category)
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 22) {
                            ForEach(matching(category)) { pick in
                                DiscoverItemCard(store: store, player: player, pick: pick, width: 198)
                            }
                        }.padding(.bottom, 8)
                        if matching(category).isEmpty { emptyState }
                    }.scrollIndicators(.never)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .trailing).combined(with: .opacity)))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("discover-category-page-\(category.id)")
                .onExitCommand { open(nil) }
            }
        }
        .clipped()
        .task { store.refreshDiscover() }
        .onChange(of: store.discoverFeed.categories.map(\.id)) { _, ids in
            if let categoryID, !ids.contains(categoryID) { open(nil) }
        }
        #if DEBUG
        .onAppear {
            if let index = CommandLine.arguments.firstIndex(of: "--discover-category"),
               CommandLine.arguments.indices.contains(index + 1) { categoryID = CommandLine.arguments[index + 1] }
        }
        #endif
    }
    private func open(_ id: String?) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.26)) { categoryID = id }
    }
    private func matching(_ category: DiscoverCategory) -> [DiscoverPick] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty || category.title.localizedCaseInsensitiveContains(query) || category.subtitle?.localizedCaseInsensitiveContains(query) == true { return category.items }
        return category.items.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.creator.localizedCaseInsensitiveContains(query) || $0.kind.rawValue.localizedCaseInsensitiveContains(query) }
    }
    private func categoryHeading(_ category: DiscoverCategory) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(category.title).font(BrandTypography.category).foregroundStyle(GeetStyle.ink)
            if let subtitle = category.subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(GeetStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No listens found").font(.system(size: 15, weight: .medium))
            Text("Try another title, creator, or category.").font(.system(size: 13)).foregroundStyle(GeetStyle.secondary)
        }.padding(.vertical, 20)
    }
}

private struct DiscoverItemCard: View {
    @ObservedObject var store: AppStore
    @ObservedObject var player: Player
    let pick: DiscoverPick
    let width: CGFloat
    var compact = false
    private var selected: Bool { player.collectionID == pick.previewID }
    private var loading: Bool { store.discoverLoadingID == pick.collectionID || selected && player.isLoading }
    private var active: Bool { loading || selected && player.isPlaying }
    private var saved: Bool { store.savedCollection(for: pick) != nil }
    private var adding: Bool { store.importingCollectionID == pick.collectionID }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomTrailing) {
                CoverArt(url: store.preview ? nil : pick.thumbnail, store: store.artwork, seed: artworkSeed)
                    .frame(width: width, height: compact ? 123 : width).clipped()
                HStack(spacing: 7) {
                    Button { store.playDiscover(pick) } label: {
                        Group {
                            if loading { ProgressView().controlSize(.small) }
                            else { Image(systemName: active ? "pause.fill" : "play.fill").font(.system(size: 13, weight: .medium)).offset(x: active ? 0 : 1) }
                        }.foregroundStyle(GeetStyle.artworkControlInk).frame(width: 32, height: 32)
                            .background(GeetStyle.artworkControlFill, in: Circle()).contentShape(Circle())
                    }.buttonStyle(PressScale())
                        .help(loading ? "Cancel preview" : active ? "Pause \(pick.title)" : "Preview \(pick.title)")
                        .accessibilityLabel(loading ? "Cancel preview of \(pick.title)" : active ? "Pause \(pick.title)" : "Preview \(pick.title)")
                        .accessibilityIdentifier("discover-play-\(pick.id)")
                    if saved {
                        Image(systemName: "checkmark").font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white).frame(width: 32, height: 32).background(.black.opacity(0.42), in: Circle())
                            .help("In your library").accessibilityLabel("In your library").accessibilityIdentifier("discover-saved-\(pick.id)")
                    } else if adding {
                        ProgressView().controlSize(.small).tint(.white).frame(width: 32, height: 32)
                            .background(.black.opacity(0.42), in: Circle()).accessibilityLabel("Adding \(pick.title) to library")
                            .accessibilityIdentifier("discover-adding-\(pick.id)")
                    } else {
                        Button { store.addDiscover(pick) } label: {
                            Image(systemName: "plus").font(.system(size: 15)).foregroundStyle(.white)
                                .frame(width: 32, height: 32).background(.black.opacity(0.42), in: Circle()).contentShape(Circle())
                        }.buttonStyle(.plain).disabled(store.busy).help("Add to library")
                            .accessibilityLabel("Add \(pick.title) to library").accessibilityIdentifier("discover-add-\(pick.id)")
                    }
                }.padding(8)
            }.clipShape(.rect(cornerRadius: 10)).padding(.bottom, 3)
            Text(pick.title).font(.system(size: 14, weight: .medium)).lineLimit(compact ? 1 : 2)
                .frame(height: compact ? 18 : 34, alignment: .topLeading).help(pick.title)
            Text(pick.creator).font(.system(size: 12)).foregroundStyle(GeetStyle.secondary).lineLimit(1)
            HStack(spacing: 4) {
                if pick.kind == .radio { Circle().fill(.red).frame(width: 5, height: 5).accessibilityHidden(true) }
                Text(pick.kind.rawValue)
            }.font(.system(size: 11)).foregroundStyle(GeetStyle.secondary)
        }.frame(width: width, alignment: .leading).foregroundStyle(GeetStyle.ink)
            .accessibilityElement(children: .contain).accessibilityLabel("\(pick.title), \(pick.kind.rawValue)")
    }
    private var artworkSeed: String {
        if pick.id.contains("synth") || pick.id.contains("winter") { return "piano" }
        if pick.id.contains("chillhop") || pick.id.contains("fall") { return "soft" }
        if pick.id.contains("classroom") { return "rain" }
        return "late"
    }
}

/// Native scrolling keeps trackpad momentum and Accessibility scroll actions.
/// Mouse events are held until the pointer resolves to a click or a drag.
/// Clicks are then delivered unchanged to SwiftUI; drags never reach its buttons.
private struct MouseShelf<Content: View>: NSViewRepresentable {
    let label: String
    let identifier: String
    let active: Bool
    @ViewBuilder let content: () -> Content

    func makeNSView(context: Context) -> DraggableShelfScrollView {
        let scroll = DraggableShelfScrollView()
        scroll.drawsBackground = false; scroll.borderType = .noBorder
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
        scroll.scrollerStyle = .overlay; scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .allowed; scroll.verticalScrollElasticity = .none
        scroll.setAccessibilityLabel(label)
        scroll.identifier = NSUserInterfaceItemIdentifier("discover-shelf-\(identifier)")
        let host = NSHostingView(rootView: content())
        host.sizingOptions = [.intrinsicContentSize]
        scroll.documentView = host
        return scroll
    }
    func updateNSView(_ view: DraggableShelfScrollView, context: Context) {
        (view.documentView as? NSHostingView<Content>)?.rootView = content()
        view.isHidden = !active
        view.setAccessibilityHidden(!active)
        view.needsLayout = true
    }
    static func dismantleNSView(_ view: DraggableShelfScrollView, coordinator: ()) {
        view.stopMouseTracking()
    }
}

final class DraggableShelfScrollView: NSScrollView {
    private struct ReplayKey: Hashable {
        let type: UInt
        let number: Int
        let timestamp: TimeInterval
        let window: Int
        init(_ event: NSEvent) {
            type = event.type.rawValue; number = event.eventNumber
            timestamp = event.timestamp; window = event.windowNumber
        }
    }
    private var mouseMonitor: Any?
    private var mouseDown: NSEvent?
    private var movement: HorizontalShelfDrag?
    private var replayedEvents = Set<ReplayKey>()

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMouseTracking()
        guard window != nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            guard let self else { return event }
            return self.handleMouse(event)
        }
    }
    func stopMouseTracking() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil; mouseDown = nil; movement = nil; replayedEvents.removeAll()
    }
    override func layout() {
        super.layout()
        guard let documentView else { return }
        let size = NSSize(width: max(contentSize.width, documentView.fittingSize.width), height: contentSize.height)
        if documentView.frame.size != size { documentView.setFrameSize(size) }
    }
    private func handleMouse(_ event: NSEvent) -> NSEvent? {
        if replayedEvents.remove(ReplayKey(event)) != nil { return event }
        guard let window, event.window === window else {
            mouseDown = nil; movement = nil; return event
        }
        if event.type == .leftMouseDown {
            guard !isHiddenOrHasHiddenAncestor, let root = window.contentView,
                  let hit = root.hitTest(root.convert(event.locationInWindow, from: nil)),
                  hit === self || hit.isDescendant(of: self) else { return event }
            let maximum = max(0, (documentView?.frame.width ?? 0) - contentSize.width)
            guard maximum > 0 else { return event }
            mouseDown = event
            movement = HorizontalShelfDrag(x: Double(event.locationInWindow.x), y: Double(event.locationInWindow.y),
                                           offset: Double(contentView.bounds.origin.x), maximumOffset: Double(maximum))
            return nil
        }
        guard let down = mouseDown, var movement else { return event }
        let offset = movement.move(x: Double(event.locationInWindow.x), y: Double(event.locationInWindow.y))
        self.movement = movement
        if let offset {
            window.makeFirstResponder(self)
            scrollHorizontally(to: CGFloat(offset))
        }
        if event.type == .leftMouseUp {
            mouseDown = nil; self.movement = nil
            if movement.shouldClick, !isHiddenOrHasHiddenAncestor {
                // Posting to this app's queue preserves normal SwiftUI hit
                // testing and button behavior. It does not inject system input.
                replayedEvents.insert(ReplayKey(down))
                replayedEvents.insert(ReplayKey(event))
                NSApp.postEvent(event, atStart: true)
                NSApp.postEvent(down, atStart: true)
            }
        }
        return nil
    }
    func scrollHorizontally(to proposed: CGFloat) {
        let maximum = max(0, (documentView?.frame.width ?? 0) - contentSize.width)
        contentView.scroll(to: NSPoint(x: min(maximum, max(0, proposed)), y: 0)); reflectScrolledClipView(contentView)
    }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || event.modifierFlags.contains(.shift) {
            super.scrollWheel(with: event)
        } else { nextResponder?.scrollWheel(with: event) }
    }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 || event.keyCode == 124 {
            scrollHorizontally(to: contentView.bounds.origin.x + (event.keyCode == 123 ? -160 : 160))
        } else { super.keyDown(with: event) }
    }
}
