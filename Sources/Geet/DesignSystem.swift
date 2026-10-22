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

extension View {
    func geetGlass<S: Shape>(in shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(GeetGlass(shape: shape, interactive: interactive, tint: tint))
    }
}

private struct GeetGlass<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(tint ?? GeetStyle.surface, in: shape)
                .overlay(shape.stroke(GeetStyle.secondary.opacity(0.4), lineWidth: 0.5).allowsHitTesting(false))
        } else {
            content.glassEffect(.regular.tint(tint ?? GeetStyle.surface.opacity(0.18)).interactive(interactive), in: shape)
                .overlay(shape.stroke(contrast == .increased ? GeetStyle.secondary.opacity(0.55)
                    : .white.opacity(colorScheme == .dark ? 0.16 : 0.65), lineWidth: 0.5).allowsHitTesting(false))
        }
    }
}

/// Source artwork remains full color; only its text legibility layer is tinted.
struct ArtworkFade: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: GeetStyle.surface, location: 0),
            .init(color: GeetStyle.surface.opacity(0.98), location: 0.28),
            .init(color: GeetStyle.surface.opacity(0.85), location: 0.45),
            .init(color: GeetStyle.surface.opacity(0.32), location: 0.68),
            .init(color: GeetStyle.surface.opacity(0), location: 0.9)
        ], startPoint: .leading, endPoint: .trailing).allowsHitTesting(false)
    }
}

struct ListenerMark: View {
    var body: some View {
        if let url = Bundle.module.url(forResource: "GeetMenuBar", withExtension: "pdf"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit()
                .foregroundStyle(GeetStyle.accent).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

struct GeetSettingsGroupStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label.font(.system(size: 14, weight: .medium)).foregroundStyle(GeetStyle.ink)
            configuration.content.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(12).background(GeetStyle.surface.opacity(0.55), in: .rect(cornerRadius: 14))
    }
}
