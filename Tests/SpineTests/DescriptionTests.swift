import SwiftUI
import WebKit
import XCTest
@testable import Spine

final class DescriptionTests: XCTestCase {
    @MainActor func testDescriptionHeightTracksContentAndWidth() async {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = DescriptionWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 1), configuration: configuration)
        let coordinator = DescriptionView.Coordinator()
        view.navigationDelegate = coordinator
        var height: CGFloat = 1
        func measuring(_ expected: XCTestExpectation) -> Binding<CGFloat> {
            Binding(get: { height }, set: { value in
                height = value
                expected.fulfill()
            })
        }
        let expanded = expectation(description: "Long description expands")
        view.contentHeight = measuring(expanded)
        let html = String(repeating: "<p>A long book description that should wrap across multiple lines when the window becomes narrower.</p>", count: 30)
        view.loadHTMLString(DescriptionView.document(html), baseURL: nil)
        await fulfillment(of: [expanded], timeout: 15)
        XCTAssertGreaterThan(height, 420)
        let wideHeight = height

        let narrowed = expectation(description: "Narrower width increases height")
        view.contentHeight = measuring(narrowed)
        view.setFrameSize(NSSize(width: 220, height: height))
        view.layoutSubtreeIfNeeded()
        await fulfillment(of: [narrowed], timeout: 15)
        XCTAssertGreaterThan(height, wideHeight)

        let shortened = expectation(description: "Shorter content shrinks")
        view.contentHeight = measuring(shortened)
        view.loadHTMLString(DescriptionView.document("<p>Short description.</p>"), baseURL: nil)
        await fulfillment(of: [shortened], timeout: 15)
        XCTAssertLessThan(height, 100)
    }
}
