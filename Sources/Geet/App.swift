import AppKit
import SwiftUI
import GeetCore
#if DEBUG
import ScreenCaptureKit
#endif

@main
enum GeetMain {
    @MainActor static func main() {
        if let index = CommandLine.arguments.firstIndex(of: "--validate-discover-feed"), CommandLine.arguments.indices.contains(index + 1) {
            do {
                let feed = try DiscoverFeed.decode(Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
                print("Valid Discover feed: \(feed.categories.count) categories, \(feed.categories.flatMap(\.items).count) items")
                exit(0)
            } catch {
                fputs("Invalid Discover feed. Check schemaVersion, category limits, item fields, and YouTube IDs.\n", stderr)
                exit(1)
            }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var status: NSStatusItem!
    private let popover = NSPopover()
    private var store: AppStore!
    #if DEBUG
    private var captureSignal: DispatchSourceSignal?
    private var captureSequence = 0
    private var keyMonitor: Any?
    private var keyEvents: [String] = []
    #endif
    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        store = AppStore(preview: CommandLine.arguments.contains("--design-preview"))
        #else
        store = AppStore()
        #endif
        installMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = status.button {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Geet")!
            image.isTemplate = true; button.image = image; button.target = self; button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Geet"; button.setAccessibilityIdentifier("geet-status-item")
        }
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        #if DEBUG
        if CommandLine.arguments.contains("--interactive-validation"), let directory = ProcessInfo.processInfo.environment["GEET_VALIDATION_DIR"] {
            let output = URL(fileURLWithPath: directory)
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
                self?.keyEvents.append("\(event.type.rawValue):\(event.keyCode):\(event.modifierFlags.rawValue):\(event.characters ?? "")")
                if let self, self.keyEvents.count > 20 { self.keyEvents.removeFirst(self.keyEvents.count - 20) }
                return event
            }
            signal(SIGUSR1, SIG_IGN)
            captureSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
            captureSignal?.setEventHandler { [weak self] in
                guard let self else { return }
                self.captureSequence += 1
                let sequence = self.captureSequence
                Task { @MainActor in
                    var state: [String: String] = ["panel_visible": String(self.popover.isShown), "playing": String(self.store.player.isPlaying),
                        "loading": String(self.store.player.isLoading), "discover_loading": self.store.discoverLoadingID ?? "", "collection_id": self.store.player.collectionID ?? "", "pipeline": String(self.store.player.hasMediaPipeline),
                        "progress_observer": String(self.store.player.hasProgressObserver), "collections": String(self.store.library.collections.count),
                        "track": self.store.player.track?.title ?? "", "position": String(self.store.player.media?.currentTime().seconds ?? 0),
                        "active": String(NSApp.isActive), "key_window": String(NSApp.keyWindow?.windowNumber ?? -1),
                        "first_responder": String(describing: NSApp.keyWindow?.firstResponder), "key_events": self.keyEvents.joined(separator: "|")]
                    if let view = self.popover.contentViewController?.view {
                        state["shelf_offsets"] = self.shelfOffsets(view).joined(separator: "|")
                    }
                    do { try await self.captureWindow(to: output.appendingPathComponent("ui-\(sequence).png")) }
                    catch { state["capture_error"] = error.localizedDescription }
                    try? Paths.write(state, to: output.appendingPathComponent("ui-\(sequence).json"))
                }
            }
            captureSignal?.resume()
            print("Interactive validation PID: \(ProcessInfo.processInfo.processIdentifier)"); fflush(stdout)
        }
        if CommandLine.arguments.contains("--capture") || CommandLine.arguments.contains("--validate-library") || CommandLine.arguments.contains("--validate-discover") || CommandLine.arguments.contains("--interactive-validation") {
            popover.behavior = .applicationDefined
        }
        if let index = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.indices.contains(index + 1) {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments[index + 1] == "dark" ? .darkAqua : .aqua)
            popover.appearance = NSApp.appearance
        }
        if CommandLine.arguments.contains("--validate-runtime") {
            Task {
                let passed = await RuntimeValidation.run(tools: Bundle.main.resourceURL!.appendingPathComponent("Tools"))
                store.shutdown(); exit(passed ? 0 : 1)
            }
        }
        if CommandLine.arguments.contains("--validate-audio") {
            Task {
                let passed = await CompletionValidation.verifyAudio(tools: Bundle.main.resourceURL!.appendingPathComponent("Tools"))
                store.shutdown(); exit(passed ? 0 : 1)
            }
        }
        if CommandLine.arguments.contains("--validate-library") {
            Task {
                // The status item's native host is installed after launch returns.
                try? await Task.sleep(for: .milliseconds(300))
                let passed = await CompletionValidation.run(store: store) { screen, destination in
                    if self.popover.contentViewController != nil {
                        self.popover.performClose(nil)
                        // Wait for popoverDidClose to release the old view before
                        // installing a new one. Close animations are asynchronous.
                        for _ in 0..<50 {
                            if self.popover.contentViewController == nil { break }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                    }
                    self.show(screen: screen, inspectClipboard: false)
                    try await Task.sleep(for: .seconds(2))
                    try await self.captureWindow(to: destination)
                }
                exit(passed ? 0 : 1)
            }
        }
        if CommandLine.arguments.contains("--validate-discover"), let directory = ProcessInfo.processInfo.environment["GEET_VALIDATION_DIR"] {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                self.show(screen: "discover", inspectClipboard: false)
                try? await Task.sleep(for: .seconds(1))
                let passed = await DiscoverValidation.run(store: store) { name in
                    try await self.captureWindow(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
                }
                exit(passed ? 0 : 1)
            }
        }
        if CommandLine.arguments.contains("--verify-deep-idle") {
            Task {
                let passed = await CompletionValidation.verifyDeepIdle(tools: Bundle.main.resourceURL!.appendingPathComponent("Tools"))
                store.shutdown(); exit(passed ? 0 : 1)
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--measure-idle"), CommandLine.arguments.indices.contains(index + 1) {
            RuntimeValidation.measureIdle(store: store, destination: CommandLine.arguments[index + 1])
        }
        #endif
        if CommandLine.arguments.contains("--show") || store.preview {
            // Status-item hosting reaches WindowServer after the launch callback.
            // This one-shot only exists for an explicitly requested first panel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.show() }
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--verify-popover"), CommandLine.arguments.indices.contains(index + 1) {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.show() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                let report: [String: String] = ["shown": String(self.popover.isShown),
                    "window_visible": String(self.popover.contentViewController?.view.window?.isVisible ?? false),
                    "status_frame": NSStringFromRect(self.status.button?.window?.frame ?? .zero),
                    "panel_size": NSStringFromSize(self.popover.contentSize),
                    "anchor_visible": String(self.status.button?.window?.isVisible ?? false),
                    "button_hidden": String(self.status.button?.isHiddenOrHasHiddenAncestor ?? true),
                    "application_active": String(NSApp.isActive)]
                try? Paths.write(report, to: URL(fileURLWithPath: path))
                NSApp.terminate(nil)
            }
        }
        #endif
    }
    @objc private func toggle() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp || event.modifierFlags.contains(.control),
           let button = status.button {
            if popover.isShown { popover.performClose(nil) }
            let menu = NSMenu()
            let quit = NSMenuItem(title: "Quit geet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
            status.menu = menu
            button.performClick(nil)
            status.menu = nil
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }
    private func installMenu() {
        let main = NSMenu()
        let application = NSMenuItem(); main.addItem(application)
        let appMenu = NSMenu(title: "Geet")
        appMenu.addItem(withTitle: "Quit Geet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = appMenu
        let editing = NSMenuItem(); main.addItem(editing)
        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
                                      ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
                                      ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        editing.submenu = edit; NSApp.mainMenu = main
    }
    private func show(screen: String? = nil, inspectClipboard: Bool = true) {
        guard !popover.isShown, popover.contentViewController == nil else { return }
        guard let button = status.button else { return }
        let height = min(760, (button.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900) - 40)
        let root = PanelView(store: store, player: store.player, height: height, startingScreen: screen)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 450, height: height)
        let glass = NSGlassEffectView(frame: host.frame)
        glass.style = .regular; glass.cornerRadius = 24; glass.contentView = host
        let controller = NSViewController(); controller.view = glass
        popover.contentViewController = controller; popover.contentSize = host.frame.size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        controller.view.window?.makeKey()
        store.panelOpened(inspectClipboard: inspectClipboard)
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.indices.contains(index + 1) {
            let destination = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task { @MainActor in
                    do {
                        try await self.captureWindow(to: URL(fileURLWithPath: destination))
                        try? FileManager.default.removeItem(atPath: destination + ".error.txt")
                    } catch {
                        try? error.localizedDescription.write(to: URL(fileURLWithPath: destination + ".error.txt"), atomically: true, encoding: .utf8)
                    }
                    if CommandLine.arguments.contains("--quit-after-capture") { NSApp.terminate(nil) }
                }
            }
        }
        #endif
    }
    #if DEBUG
    private func shelfOffsets(_ view: NSView) -> [String] {
        let own = (view as? DraggableShelfScrollView).map { ["\($0.identifier?.rawValue ?? "shelf"):\($0.contentView.bounds.origin.x)"] } ?? []
        return own + view.subviews.flatMap(shelfOffsets)
    }
    private func captureWindow(to destination: URL) async throws {
        let content = try await SCShareableContent.currentProcess
        let number = popover.contentViewController?.view.window?.windowNumber ?? -1
        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(max(0, number)) }) else {
            throw GeetError.message("The app’s panel is not visible.")
        }
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * 2); config.height = Int(window.frame.height * 2)
        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
        let capture = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: capture)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw GeetError.message("The capture couldn’t be saved.") }
        Paths.ensure(destination.deletingLastPathComponent())
        try png.write(to: destination)
    }
    #endif
    func popoverDidClose(_ notification: Notification) {
        store.panelClosed()
        // Destroy the SwiftUI tree: invisible controls cannot render or animate.
        popover.contentViewController = nil
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { show() }; return false
    }
    func applicationWillTerminate(_ notification: Notification) { store.shutdown() }
}
