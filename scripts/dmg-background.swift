// Regenerate the installer's background: swift scripts/dmg-background.swift
import AppKit

let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("assets")
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for scale in [1, 2] {
    let width = 640, height = 380
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale,
        pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let cream = NSColor(srgbRed: 0.976, green: 0.965, blue: 0.937, alpha: 1)
    let sage = NSColor(srgbRed: 0.920, green: 0.937, blue: 0.898, alpha: 1)
    NSGradient(starting: sage, ending: cream)!.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)
    NSColor(srgbRed: 0.34, green: 0.44, blue: 0.37, alpha: 0.55).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 2
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    // Finder icon coordinates run downwards from the top of the content area.
    let y: CGFloat = 210
    arrow.move(to: NSPoint(x: 298, y: y))
    arrow.line(to: NSPoint(x: 342, y: y))
    arrow.move(to: NSPoint(x: 333, y: y + 9))
    arrow.line(to: NSPoint(x: 342, y: y))
    arrow.line(to: NSPoint(x: 333, y: y - 9))
    arrow.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 1 ? "" : "@2x"
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("dmg-background\(suffix).png"))
}
