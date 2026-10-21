import AppKit
import ApplicationServices
import Darwin

// Opt-in developer tool. It only targets a Geet app built in this checkout.
let arguments = CommandLine.arguments
func fail(_ message: String) -> Never { fputs(message + "\n", stderr); exit(1) }
guard arguments.count >= 3, let pid = Int32(arguments[1]) else { fail("Usage: geet-ax PID snapshot|press|set|key [index] [value]") }
var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { fail("The target process is not running.") }
let executable = URL(fileURLWithPath: String(cString: path))
let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
guard executable.path.hasPrefix(checkout.appendingPathComponent("build").path + "/"),
      Bundle(url: bundle)?.bundleIdentifier == "app.geet.mac" else { fail("Refusing a process outside this checkout's Geet builds.") }
guard AXIsProcessTrusted() else { fail("Accessibility access is unavailable for this CLI's responsible application.") }
if arguments[2] == "capture" {
    guard kill(pid, SIGUSR1) == 0 else { fail("Could not signal the Geet test process.") }
    exit(0)
}
if arguments[2] == "activate" {
    guard NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows]) == true else { fail("Could not activate Geet.") }
    for _ in 0..<20 {
        if NSRunningApplication(processIdentifier: pid)?.isActive == true { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    print("Geet active: \(NSRunningApplication(processIdentifier: pid)?.isActive == true)")
    exit(0)
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 3)
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success ? result : nil
}
func string(_ element: AXUIElement, _ name: String) -> String { attribute(element, name) as? String ?? "" }
func actions(_ element: AXUIElement) -> [String] {
    var values: CFArray?
    AXUIElementCopyActionNames(element, &values)
    return values as? [String] ?? []
}
func postToFocusedGeet(_ event: CGEvent) {
    let system = AXUIElementCreateSystemWide()
    guard let focused = attribute(system, "AXFocusedUIElement") ?? attribute(system, "AXFocusedApplication"), CFGetTypeID(focused) == AXUIElementGetTypeID() else { fail("No focused Geet control.") }
    var focusedPID: pid_t = 0
    AXUIElementGetPid(unsafeBitCast(focused, to: AXUIElement.self), &focusedPID)
    guard focusedPID == pid else { fail("Keyboard input refused because focus is outside Geet.") }
    event.flags = []
    event.post(tap: .cghidEventTap)
}
var elements: [AXUIElement] = [], rows: [[String: Any]] = []
var visited = Set<CFHashCode>()
func walk(_ element: AXUIElement, depth: Int) {
    // The standard Apple menu exposes system-wide recents and commands. It is
    // outside the app under test, even though macOS attaches it to each menu bar.
    if string(element, "AXRole") == "AXMenuBarItem", string(element, "AXTitle") == "Apple" { return }
    if string(element, "AXIdentifier") == "_NSMenuItemAutoFillIdentifier" { return }
    guard depth < 25, rows.count < 1500, visited.insert(CFHash(element)).inserted else { return }
    elements.append(element)
    var row: [String: Any] = ["index": elements.count - 1, "depth": depth,
        "role": string(element, "AXRole"), "label": string(element, "AXDescription"),
        "title": string(element, "AXTitle"), "identifier": string(element, "AXIdentifier"), "actions": actions(element)]
    if depth == 0 {
        row["active"] = NSRunningApplication(processIdentifier: pid)?.isActive ?? false
        row["post_event_access"] = CGPreflightPostEventAccess()
        if let focused = attribute(element, "AXFocusedUIElement"), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            row["focused_identifier"] = string(unsafeBitCast(focused, to: AXUIElement.self), "AXIdentifier")
        }
    }
    if let value = attribute(element, "AXValue") as? String { row["value"] = String(value.prefix(250)) }
    else if let value = attribute(element, "AXValue") as? NSNumber { row["value"] = value }
    if let value = attribute(element, "AXFocused") as? Bool { row["focused"] = value }
    if let value = attribute(element, "AXEnabled") as? Bool { row["enabled"] = value }
    rows.append(row)
    for name in ["AXChildren", "AXWindows", "AXMenuBar", "AXExtrasMenuBar"] {
        if let children = attribute(element, name) as? [AXUIElement] { children.forEach { walk($0, depth: depth + 1) } }
        else if let child = attribute(element, name), CFGetTypeID(child) == AXUIElementGetTypeID() { walk(unsafeBitCast(child, to: AXUIElement.self), depth: depth + 1) }
    }
}
walk(app, depth: 0)
if arguments[2] == "snapshot" {
    let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self)); exit(0)
}
if arguments[2] == "key" {
    guard arguments.count == 4, let key = UInt16(arguments[3]) else { fail("key requires a macOS virtual key code.") }
    _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    for _ in 0..<20 {
        if NSRunningApplication(processIdentifier: pid)?.isActive == true { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    // Each event requires the focused UI element to belong to the verified PID.
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down) else { fail("Could not create key event.") }
        postToFocusedGeet(event)
    }
    exit(0)
}
guard arguments.count >= 4 else { fail("Choose an index or identifier from a fresh Geet snapshot.") }
let selected = Int(arguments[3]) ?? elements.firstIndex { string($0, "AXIdentifier") == arguments[3] }
guard let index = selected, elements.indices.contains(index) else { fail("The Geet control is no longer present.") }
let element = elements[index]
let result: AXError
switch arguments[2] {
case "press": result = AXUIElementPerformAction(element, kAXPressAction as CFString)
case "focus":
    guard string(element, "AXRole") == "AXTextField" else { fail("Only Geet text fields can be focused.") }
    result = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
case "type":
    guard arguments.count == 5, string(element, "AXRole") == "AXTextField" else { fail("type requires a Geet text field and value.") }
    guard AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success else { fail("Could not focus the Geet text field.") }
    _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateAllWindows])
    for _ in 0..<20 {
        if NSRunningApplication(processIdentifier: pid)?.isActive == true { break }
        Thread.sleep(forTimeInterval: 0.05)
    }
    print("Geet active while typing: \(NSRunningApplication(processIdentifier: pid)?.isActive == true)")
    let text = Array(arguments[4].utf16)
    for offset in stride(from: 0, to: text.count, by: 16) {
        let chunk = Array(text[offset..<min(offset + 16, text.count)])
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down) else { fail("Could not create Geet text event.") }
            chunk.withUnsafeBufferPointer { event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: $0.baseAddress) }
            postToFocusedGeet(event)
        }
        Thread.sleep(forTimeInterval: 0.03)
    }
    exit(0)
case "set":
    guard arguments.count == 5, string(element, "AXRole") == "AXTextField" else { fail("set requires a Geet text field and value.") }
    result = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, arguments[4] as CFString)
default: fail("Unknown action.")
}
guard result == .success else { fail("Accessibility action failed: \(result.rawValue)") }
print("OK")
