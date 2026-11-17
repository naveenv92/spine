import SwiftUI
import CoreText

enum Typography {
    private static let descriptors: [String: CTFontDescriptor] = {
        var result: [String: CTFontDescriptor] = [:]
        for name in ["Fraunces", "DMSans"] {
            if let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"),
               let fonts = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
               let descriptor = fonts.first { result[name] = descriptor }
        }
        return result
    }()

    static func font(_ name: String, size: CGFloat, weight: Double) -> CTFont {
        let base = descriptors[name] ?? CTFontDescriptorCreateWithNameAndSize("Helvetica" as CFString, size)
        let variations: [NSNumber: Double] = [NSNumber(value: 0x77676874): weight, NSNumber(value: 0x6f70737a): Double(size)]
        let descriptor = CTFontDescriptorCreateCopyWithAttributes(base, [kCTFontVariationAttribute: variations] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    static func heading(_ size: CGFloat) -> Font { Font(font("Fraunces", size: size, weight: 600)) }
    static func ui(_ size: CGFloat = 13, weight: Double = 400) -> Font { Font(font("DMSans", size: size, weight: weight)) }

    static let webCSS: String = ["DMSans", "DMSans-Italic"].compactMap { name in
        guard let url = Bundle.module.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts"),
              let data = try? Data(contentsOf: url) else { return nil }
        let style = name.hasSuffix("Italic") ? "italic" : "normal"
        return "@font-face { font-family: 'DM Sans'; font-style: \(style); font-weight: 100 1000; src: url(data:font/ttf;base64,\(data.base64EncodedString())) format('truetype'); }"
    }.joined(separator: "\n")
}
