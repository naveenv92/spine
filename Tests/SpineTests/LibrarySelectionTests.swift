import XCTest
@testable import Spine

final class LibrarySelectionTests: XCTestCase {
    func testClickSelectionAndCommandToggle() {
        var selection = LibrarySelection()
        selection.select("a")
        XCTAssertEqual(selection.ids, ["a"])
        selection.select("b")
        XCTAssertEqual(selection.ids, ["b"])
        selection.select("a", extending: true)
        XCTAssertEqual(selection.ids, ["a", "b"])
        XCTAssertEqual(selection.activeID, "a")
        selection.select("a", extending: true)
        XCTAssertEqual(selection.ids, ["b"])
        XCTAssertEqual(selection.activeID, "b")
        selection.select("b", extending: true)
        XCTAssertTrue(selection.ids.isEmpty)
        XCTAssertNil(selection.activeID)
    }

    func testKeyboardNavigationAndRefresh() {
        var selection = LibrarySelection()
        selection.move(1, in: [])
        XCTAssertNil(selection.activeID)
        selection.move(1, in: ["a", "b", "c"])
        XCTAssertEqual(selection.activeID, "a")
        selection.move(-1, in: ["a", "b", "c"])
        XCTAssertEqual(selection.activeID, "a")
        selection.move(1, in: ["a", "b", "c"])
        XCTAssertEqual(selection.activeID, "b")
        selection.move(5, in: ["a", "b", "c"])
        XCTAssertEqual(selection.activeID, "c")
        selection.select("b", extending: true)
        selection.reconcile(with: ["c"])
        XCTAssertEqual(selection.activeID, "c")
        XCTAssertEqual(selection.ids, ["c"])
        selection.reconcile(with: [])
        XCTAssertNil(selection.activeID)
        XCTAssertTrue(selection.ids.isEmpty)
    }
}
