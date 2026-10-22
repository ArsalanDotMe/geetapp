import Foundation
import CoreText
import CoreGraphics

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let fonts = directory.appendingPathComponent("fonts", isDirectory: true)

func axis(_ name: String) -> NSNumber {
    NSNumber(value: name.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
}

func font(_ filename: String, size: CGFloat, variations: [String: Double] = [:]) -> CTFont {
    let url = fonts.appendingPathComponent(filename)
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
          let descriptor = descriptors.first else { fatalError("Cannot load \(filename)") }
    let values = Dictionary(uniqueKeysWithValues: variations.map { (axis($0.key), NSNumber(value: $0.value)) })
    let configured = CTFontDescriptorCreateCopyWithAttributes(descriptor,
        [kCTFontVariationAttribute: values] as CFDictionary)
    let result = CTFontCreateWithFontDescriptor(configured, size, nil)
    print("\(filename): \(CTFontCopyPostScriptName(result)); axes=\(CTFontCopyVariation(result) as Any)")
    return result
}

func number(_ value: CGFloat) -> String { String(format: "%.4f", Double(value)) }

func glyphPath(_ path: CGPath) -> String {
    var result = ""
    path.applyWithBlock { pointer in
        let element = pointer.pointee
        let p = element.points
        switch element.type {
        case .moveToPoint: result += "M\(number(p[0].x)) \(number(p[0].y))"
        case .addLineToPoint: result += "L\(number(p[0].x)) \(number(p[0].y))"
        case .addQuadCurveToPoint:
            result += "Q\(number(p[0].x)) \(number(p[0].y)) \(number(p[1].x)) \(number(p[1].y))"
        case .addCurveToPoint:
            result += "C\(number(p[0].x)) \(number(p[0].y)) \(number(p[1].x)) \(number(p[1].y)) \(number(p[2].x)) \(number(p[2].y))"
        case .closeSubpath: result += "Z"
        @unknown default: fatalError("Unsupported path element")
        }
    }
    return result
}

func textPaths(_ text: String, font: CTFont, center: CGFloat, baseline: CGFloat, color: String) -> String {
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    var result = "<g fill=\"\(color)\" transform=\"translate(\(number(center - width / 2)) \(number(baseline))) scale(1 -1)\">"
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let count = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: count)
        var positions = [CGPoint](repeating: .zero, count: count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
        for i in 0..<count {
            guard let path = CTFontCreatePathForGlyph(font, glyphs[i], nil) else { continue }
            result += "<path transform=\"translate(\(number(positions[i].x)) \(number(positions[i].y)))\" d=\"\(glyphPath(path))\"/>"
        }
    }
    return result + "</g>"
}

let samples: [(String, CTFont)] = [
    ("Instrument Serif", font("InstrumentSerif-Regular.ttf", size: 200)),
    ("Fraunces", font("Fraunces[SOFT,WONK,opsz,wght].ttf", size: 200,
                      variations: ["wght": 400, "opsz": 72, "SOFT": 50, "WONK": 1])),
    ("Newsreader", font("Newsreader[opsz,wght].ttf", size: 200,
                       variations: ["wght": 400, "opsz": 72]))
]
let label = CTFontCreateUIFontForLanguage(.system, 24, nil)!
var content = "<rect width=\"1920\" height=\"580\" fill=\"#F4F0E7\"/>"
content += "<path d=\"M640 90V470M1280 90V470\" stroke=\"#DCD7CA\" stroke-width=\"1\"/>"
for (i, sample) in samples.enumerated() {
    let center = CGFloat(i * 640 + 320)
    content += textPaths("geet", font: sample.1, center: center, baseline: 310, color: "#20211C")
    content += textPaths(sample.0, font: label, center: center, baseline: 425, color: "#355A48")
}
let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="580" viewBox="0 0 1920 580" role="img" aria-label="geet in Instrument Serif, Fraunces, and Newsreader">
<title>geet typeface comparison</title>
\(content)
</svg>

"""
try svg.write(to: directory.appendingPathComponent("geet-typeface-comparison.svg"), atomically: true, encoding: .utf8)
