import XCTest
@testable import Spine

final class LibraryTests: XCTestCase {
    func testSearchAndSort() {
        let books = [Book(id: "1", title: "Dune", author: "Frank Herbert"),
                     Book(id: "2", title: "Piranesi", author: "Susanna Clarke"),
                     Book(id: "3", title: "Circe", author: "Madeline Miller")]
        XCTAssertEqual(Book.library(books, search: "", sort: .title).map(\.id), ["3", "1", "2"])
        XCTAssertEqual(Book.library(books, search: "", sort: .authorFirstName).map(\.id), ["1", "3", "2"])
        XCTAssertEqual(Book.library(books, search: "HERBERT", sort: .title).map(\.id), ["1"])
        XCTAssertEqual(Book.library(books, search: "circe", sort: .authorFirstName).map(\.id), ["3"])
        XCTAssertTrue(Book.library(books, search: "missing", sort: .title).isEmpty)
        XCTAssertEqual(Book.library(books, search: "", sort: .authorLastName).map(\.id), ["2", "1", "3"])
    }

    func testAuthorSortUsesPrimaryAuthorAndHandlesCommaNamesAndTies() {
        let books = [Book(id: "1", title: "Z Book", author: "Terry Pratchett; Aaron Adams"),
                     Book(id: "2", title: "B Book", author: "Gaiman, Neil"),
                     Book(id: "3", title: "A Book", author: "neil gaiman"),
                     Book(id: "4", title: "Solo", author: "Plato"),
                     Book(id: "5", title: "Unknown", author: "")]
        XCTAssertEqual(Book.library(books, search: "", sort: .authorFirstName).map(\.id), ["5", "3", "2", "4", "1"])
        XCTAssertEqual(Book.library(books, search: "", sort: .authorLastName).map(\.id), ["5", "3", "2", "4", "1"])
        XCTAssertEqual(LibrarySort.authorLastName.key(for: Book(id: "6", title: "", author: "J. R. R. Tolkien")), "Tolkien J. R. R.")
    }

    func testMostRecentSortsNewestFirstWithTitleTiesAndUndatedBooksLast() {
        let books = [Book(id: "1", title: "Old", author: "", addedAt: Date(timeIntervalSince1970: 10)),
                     Book(id: "2", title: "Z New", author: "", addedAt: Date(timeIntervalSince1970: 20)),
                     Book(id: "3", title: "A New", author: "", addedAt: Date(timeIntervalSince1970: 20)),
                     Book(id: "4", title: "Undated", author: "")]
        XCTAssertEqual(Book.library(books, search: "", sort: .mostRecent).map(\.id), ["3", "2", "1", "4"])
        XCTAssertEqual(Book.library(books, search: "new", sort: .mostRecent).map(\.id), ["3", "2"])
    }
}
