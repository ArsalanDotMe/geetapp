import AppKit
import SwiftUI

/// Mist & Slate. Dynamic colors resolve in the view's effective appearance.
enum GeetStyle {
    static let panel = color(light: 0xEEF3F8, dark: 0x131C29)
    static let surface = color(light: 0xDFE8F1, dark: 0x263346)
    static let ink = color(light: 0x233246, dark: 0xEDF2F8)
    static let secondary = color(light: 0x536981, dark: 0xACBED2)
    static let accent = color(light: 0x4C6E93, dark: 0xA7C4E4)
    static let accentInk = color(light: 0xFFFFFF, dark: 0x131C29)
    static let selection = color(light: 0xF8FBFF, dark: 0x40546D)
    // A chromatic near-white is amplified by the system's glass tinting over
    // artwork. Neutral white keeps these controls silver in both appearances.
    static let artworkControlFill = Color.white
    static let artworkControlInk = Color(red: 0.137, green: 0.196, blue: 0.275)
    static let glassTint = nativeColor(light: 0xDFE8F1, dark: 0x263346)
    static let panelWidth: CGFloat = 450
    static let inset: CGFloat = 18
    static let cardRadius: CGFloat = 14

    private static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: nativeColor(light: light, dark: dark))
    }

    private static func nativeColor(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        }
    }
}
