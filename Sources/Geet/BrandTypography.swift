import CoreText
import SwiftUI

enum BrandTypography {
    // Resolve the bundled font once, when a branded heading is first displayed.
    // A menu-bar-only launch doesn't need to register or load any custom fonts.
    private static let descriptor: CTFontDescriptor = {
        guard let url = Bundle.module.url(forResource: "Newsreader", withExtension: "ttf"),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            preconditionFailure("The bundled Newsreader brand font is missing or invalid")
        }
        return descriptor
    }()

    static let editorial = heading(size: 24)
    static let category = heading(size: 22)

    private static func heading(size: CGFloat) -> Font {
        let variations: [NSNumber: NSNumber] = [
            0x77676874: 400, // wght: Regular
            0x6F70737A: NSNumber(value: Double(min(72, max(6, size)))) // opsz
        ]
        let configured = CTFontDescriptorCreateCopyWithAttributes(descriptor,
            [kCTFontVariationAttribute: variations] as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(configured, size, nil))
    }
}
