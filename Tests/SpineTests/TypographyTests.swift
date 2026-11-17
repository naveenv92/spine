import CoreText
import XCTest
@testable import Spine

final class TypographyTests: XCTestCase {
    func testBundledFontsUseTheRequestedFamiliesAndWeights() throws {
        for (name, family, weight) in [("Fraunces", "Fraunces", 600.0), ("DMSans", "DM Sans", 400.0), ("DMSans", "DM Sans", 700.0)] {
            let font = Typography.font(name, size: 32, weight: weight)
            XCTAssertTrue((CTFontCopyFamilyName(font) as String).hasPrefix(family))
            let axes = try XCTUnwrap(CTFontCopyVariation(font) as? [NSNumber: NSNumber])
            let definitions = try XCTUnwrap(CTFontCopyVariationAxes(font) as? [[String: Any]])
            let weightAxis = try XCTUnwrap(definitions.first {
                ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.uint32Value == 0x77676874
            })
            let actual = axes[NSNumber(value: 0x77676874)] ?? weightAxis[kCTFontVariationAxisDefaultValueKey as String] as? NSNumber
            XCTAssertEqual(try XCTUnwrap(actual).doubleValue, weight, accuracy: 0.01)
        }
    }

    func testDescriptionEmbedsRegularAndItalicFontsWithoutExternalRequests() {
        let document = DescriptionView.document("<p><em>Book description</em></p>")
        XCTAssertEqual(Typography.webCSS.components(separatedBy: "data:font/ttf;base64,").count - 1, 2)
        XCTAssertTrue(document.contains("font-style: italic"))
        XCTAssertTrue(document.contains("font-src data:"))
        XCTAssertTrue(document.contains("default-src 'none'"))
    }
}
