import XCTest
@testable import Spine
final class EPUBTests: XCTestCase {
    func testDescriptionDocumentPreservesMarkupAndBlocksResources() {
        let document = DescriptionView.document("<p>Hello <strong>reader</strong> &amp; friends</p>")
        XCTAssertTrue(document.contains("<strong>reader</strong> &amp; friends"))
        XCTAssertTrue(document.contains("default-src 'none'"))
        XCTAssertTrue(document.contains("charset=\"utf-8\""))
    }
    func testRejectsNonArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not an EPUB".utf8).write(to: url)
        XCTAssertThrowsError(try EPUB(url))
    }
}
