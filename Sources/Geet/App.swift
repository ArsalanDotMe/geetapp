import AppKit
import SwiftUI
import GeetCore
#if DEBUG
import ScreenCaptureKit
#endif

@main
enum GeetMain {
    @MainActor static func main() {
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
            button.toolTip = "Geet"; button.setAccessibilityIdentifier("geet-status-item")
        }
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        #if DEBUG
        if CommandLine.arguments.contains("--capture") { popover.behavior = .applicationDefined }
        if let index = CommandLine.arguments.firstIndex(of: "--appearance"), CommandLine.arguments.indices.contains(index + 1) {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments[index + 1] == "dark" ? .darkAqua : .aqua)
            popover.appearance = NSApp.appearance
        }
        if CommandLine.arguments.contains("--validate-runtime") {
            Task { await RuntimeValidation.run(tools: Bundle.main.resourceURL!.appendingPathComponent("Tools")); NSApp.terminate(nil) }
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
    @objc private func toggle() { if popover.isShown { popover.performClose(nil) } else { show() } }
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
    private func show() {
        guard let button = status.button else { return }
        let height = min(760, (button.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900) - 40)
        let root = PanelView(store: store, player: store.player, height: height)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(x: 0, y: 0, width: 450, height: height)
        let glass = NSGlassEffectView(frame: host.frame)
        glass.style = .regular; glass.cornerRadius = 24; glass.contentView = host
        let controller = NSViewController(); controller.view = glass
        popover.contentViewController = controller; popover.contentSize = host.frame.size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        store.panelOpened()
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.indices.contains(index + 1) {
            let destination = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                Task { @MainActor in
                    do {
                        let content = try await SCShareableContent.currentProcess
                        let number = self.popover.contentViewController?.view.window?.windowNumber ?? host.window?.windowNumber ?? -1
                        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(max(0, number)) }) else {
                            throw GeetError.message("Own window \(number); available windows \(content.windows.map(\.windowID))")
                        }
                        let config = SCStreamConfiguration()
                        config.width = Int(window.frame.width * 2); config.height = Int(window.frame.height * 2)
                        config.showsCursor = false; config.ignoreShadowsSingleWindow = true
                        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
                        let bitmap = NSBitmapImageRep(cgImage: image)
                        if let png = bitmap.representation(using: .png, properties: [:]) {
                            try png.write(to: URL(fileURLWithPath: destination))
                            try? FileManager.default.removeItem(atPath: destination + ".error.txt")
                        }
                    } catch {
                        try? error.localizedDescription.write(to: URL(fileURLWithPath: destination + ".error.txt"), atomically: true, encoding: .utf8)
                    }
                    if CommandLine.arguments.contains("--quit-after-capture") { NSApp.terminate(nil) }
                }
            }
        }
        #endif
    }
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
