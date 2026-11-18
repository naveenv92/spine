import XCTest
@testable import Spine

final class EReaderConnectionTests: XCTestCase {
    private let settings = EReaderSettings(host: "reader.local", port: "2222")
    private let book = Book(id: "Susanna Clarke/piranesi.epub", title: "Piranesi", author: "Susanna Clarke")

    @MainActor func testFiltersUseSuccessfulSnapshotAndPreserveOrder() async {
        let connection = EReaderConnection()
        let other = Book(id: "Frank Herbert/dune.epub", title: "Dune", author: "Frank Herbert")
        let books = [other, book]
        for filter in EReaderFilter.allCases {
            XCTAssertEqual(connection.filter(books, by: filter).map(\.id), books.map(\.id))
        }
        await connection.refresh(settings) { _ in ["/mnt/us/books/Susanna Clarke/piranesi.epub"] }
        XCTAssertEqual(connection.filter(books, by: .all).map(\.id), books.map(\.id))
        XCTAssertEqual(connection.filter(books, by: .onReader).map(\.id), [book.id])
        XCTAssertEqual(connection.filter(books, by: .notOnReader).map(\.id), [other.id])
        await connection.refresh(settings) { _ in [] }
        XCTAssertTrue(connection.filter(books, by: .onReader).isEmpty)
        XCTAssertEqual(connection.filter(books, by: .notOnReader).map(\.id), books.map(\.id))
        connection.disconnect()
        XCTAssertEqual(connection.filter(books, by: .notOnReader).map(\.id), books.map(\.id))
    }

    @MainActor func testConnectRefreshMatchingAndFailure() async {
        let connection = EReaderConnection()
        XCTAssertFalse(connection.contains(book))
        await connection.refresh(settings) { _ in ["/mnt/us/books/SUSANNA CLARKE/PIRANESI.EPUB"] }
        XCTAssertTrue(connection.contains(book))
        XCTAssertNotNil(connection.checkedAt)
        var renamed = book; renamed.id = "Susanna Clarke/renamed.epub"
        XCTAssertFalse(connection.contains(renamed))
        await connection.refresh(settings) { _ in [] }
        XCTAssertFalse(connection.contains(book))
        XCTAssertNotNil(connection.checkedAt)
        await connection.refresh(settings) { _ in throw EReaderSettings.error("Offline") }
        XCTAssertNil(connection.settings)
        XCTAssertNil(connection.checkedAt)
        XCTAssertTrue(connection.paths.isEmpty)
        XCTAssertEqual(connection.error, "Offline")
    }

    @MainActor func testDisconnectRejectsLateResults() async {
        let connection = EReaderConnection()
        let started = expectation(description: "Scan started")
        let (stream, continuation) = AsyncStream<Set<String>>.makeStream()
        let configuration = settings
        let task = Task {
            await connection.refresh(configuration) { _ in
                started.fulfill()
                for await value in stream { return value }
                return []
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(connection.isRefreshing)
        connection.disconnect()
        continuation.yield(["/mnt/us/books/Susanna Clarke/piranesi.epub"])
        continuation.finish()
        await task.value
        XCTAssertFalse(connection.contains(book))
        XCTAssertNil(connection.settings)
        XCTAssertNil(connection.checkedAt)
        XCTAssertFalse(connection.isRefreshing)
    }

    @MainActor func testSettingsChangeRejectsOldScanAndAllowsNewConnection() async {
        let connection = EReaderConnection()
        let started = expectation(description: "Old scan started")
        let (stream, continuation) = AsyncStream<Set<String>>.makeStream()
        let original = settings
        let task = Task {
            await connection.refresh(original) { _ in
                started.fulfill()
                for await value in stream { return value }
                return []
            }
        }
        await fulfillment(of: [started], timeout: 2)
        var changed = settings; changed.host = "other.local"
        connection.invalidate(ifChanged: changed)
        await connection.refresh(changed) { _ in [] }
        continuation.yield(["/mnt/us/books/Susanna Clarke/piranesi.epub"])
        continuation.finish()
        await task.value
        XCTAssertEqual(connection.settings, changed)
        XCTAssertTrue(connection.paths.isEmpty)
        XCTAssertNotNil(connection.checkedAt)
    }

    @MainActor func testRefreshKeepsSnapshotUntilFinishedAndTransfersCanRefreshIt() async {
        let connection = EReaderConnection()
        await connection.refresh(settings) { _ in ["/mnt/us/books/Susanna Clarke/piranesi.epub"] }
        connection.invalidate(ifChanged: settings)
        XCTAssertTrue(connection.contains(book))
        let started = expectation(description: "Refresh started")
        let (stream, continuation) = AsyncStream<Set<String>>.makeStream()
        let configuration = settings
        let task = Task {
            await connection.refresh(configuration) { _ in
                started.fulfill()
                for await value in stream { return value }
                return []
            }
        }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(connection.contains(book))
        continuation.yield([]); continuation.finish()
        await task.value
        XCTAssertFalse(connection.contains(book))
        await connection.refresh(settings) { _ in ["/mnt/us/books/Susanna Clarke/piranesi.epub"] }
        XCTAssertTrue(connection.contains(book))
    }
}
