import XCTest
@testable import Spine

final class LibraryTests: XCTestCase {
    func testSearchAndSort() {
        let books = [Book(id: "1", title: "Dune", author: "Frank Herbert"),
                     Book(id: "2", title: "Piranesi", author: "Susanna Clarke"),
                     Book(id: "3", title: "Circe", author: "Madeline Miller")]
        XCTAssertEqual(Book.library(books, search: "", sortByAuthor: false).map(\.id), ["3", "1", "2"])
        XCTAssertEqual(Book.library(books, search: "", sortByAuthor: true).map(\.id), ["1", "3", "2"])
        XCTAssertEqual(Book.library(books, search: "HERBERT", sortByAuthor: false).map(\.id), ["1"])
        XCTAssertEqual(Book.library(books, search: "circe", sortByAuthor: true).map(\.id), ["3"])
        XCTAssertTrue(Book.library(books, search: "missing", sortByAuthor: false).isEmpty)
    }
}
