import XCTest
@testable import Spine

final class EReaderTransferTests: XCTestCase {
    private let settings = EReaderSettings(host: "192.168.0.24", port: "2222")

    private func library() throws -> LibraryStore {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return LibraryStore(root: root)
    }

    func testSettingsDefaultsAndValidation() throws {
        let blank = EReaderSettings()
        XCTAssertEqual(blank.host, ""); XCTAssertEqual(blank.port, "")
        XCTAssertEqual(blank.user, "root"); XCTAssertEqual(blank.destination, "/mnt/us/books/")
        XCTAssertThrowsError(try blank.validate())
        XCTAssertNoThrow(try settings.validate())
        for port in ["", "0", "65536", "22 -oProxyCommand=bad", "abc"] {
            var changed = settings; changed.port = port
            XCTAssertThrowsError(try changed.validate())
        }
        for host in ["-bad", "host;touch bad", "user@host", "host\nother"] {
            var changed = settings; changed.host = host
            XCTAssertThrowsError(try changed.validate())
        }
        for path in ["relative", "/books/../other", "/books\nother"] {
            var changed = settings; changed.destination = path
            XCTAssertThrowsError(try changed.validate())
        }
        var changed = settings; changed.user = "root;bad"
        XCTAssertThrowsError(try changed.validate())
    }

    func testDestinationsAndDuplicateSelectionSafety() throws {
        let store = try library()
        let source = store.root.appendingPathComponent("book's name.epub")
        try Data("EPUB contents".utf8).write(to: source)
        let book = Book(id: source.lastPathComponent, title: "Book", author: "Eugene O'Neill; Other Author")
        let transfer = EReaderTransfer(settings: settings)
        let item = try XCTUnwrap(transfer.items(for: [book], library: store).first)
        XCTAssertEqual(item.destination, "/mnt/us/books/Eugene O'Neill/book's name.epub")
        XCTAssertEqual(item.source, source)
        XCTAssertThrowsError(try transfer.items(for: [book, book], library: store))
        var outside = book; outside.id = "../outside.epub"
        XCTAssertThrowsError(try transfer.items(for: [outside], library: store))
        let link = store.root.appendingPathComponent("linked.epub")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        var linked = book; linked.id = link.lastPathComponent
        XCTAssertThrowsError(try transfer.items(for: [linked], library: store))
    }

    func testRemotePathsAreQuotedAsSingleShellArguments() throws {
        XCTAssertEqual(EReaderTransfer.quote("O'Neill"), "'O'\"'\"'Neill'")
        let value = "/books/O'Neill/$(printf INJECTED); book.epub"
        // Verify quoting with a harmless local shell; nothing in the value executes.
        let result = try EPUB.command("/bin/sh", ["-c", "printf %s " + EReaderTransfer.quote(value)])
        XCTAssertEqual(result, value)
    }

    func testPreflightFindsConflictsAndBlocksUnsafeDestinations() throws {
        let first = EReaderItem(source: URL(fileURLWithPath: "/tmp/a.epub"), destination: "/books/Author/a.epub")
        let second = EReaderItem(source: URL(fileURLWithPath: "/tmp/b.epub"), destination: "/books/Author/b.epub")
        var calls = 0
        let transfer = EReaderTransfer(settings: settings, run: { executable, arguments in
            XCTAssertEqual(executable, "/usr/bin/ssh")
            XCTAssertTrue(arguments.contains("BatchMode=yes"))
            XCTAssertTrue(arguments.contains("StrictHostKeyChecking=yes"))
            XCTAssertEqual(arguments[arguments.count - 2], "root@192.168.0.24")
            calls += 1
            if calls > 1 { XCTAssertTrue(arguments.last!.contains("test -L '/books/Author'")) }
            return calls == 1 ? "" : (calls == 2 ? "exists" : "missing")
        })
        XCTAssertEqual(try transfer.conflicts(in: [first, second]), [first])
        XCTAssertEqual(calls, 3)
        let blocked = EReaderTransfer(settings: settings, run: { _, args in args.last == "true" ? "" : "blocked" })
        XCTAssertThrowsError(try blocked.conflicts(in: [first]))
        let disconnected = EReaderTransfer(settings: settings, run: { _, _ in throw EReaderSettings.error("Connection refused") })
        XCTAssertThrowsError(try disconnected.conflicts(in: [first]))
    }

    func testSendUsesTemporaryUploadAndOnlyOverwritesWhenApproved() throws {
        let item = EReaderItem(source: URL(fileURLWithPath: "/tmp/a book.epub"), destination: "/mnt/us/books/Author/a book.epub")
        for replacing in [false, true] {
            var commands: [(String, [String])] = []
            let transfer = EReaderTransfer(settings: settings, run: { executable, arguments in
                commands.append((executable, arguments)); return ""
            })
            try transfer.send(item, replacing: replacing)
            XCTAssertEqual(commands.map { $0.0 }, ["/usr/bin/ssh", "/usr/bin/scp", "/usr/bin/ssh"])
            XCTAssertEqual(commands[1].1.suffix(2).first, item.source.path)
            let remote = try XCTUnwrap(commands[1].1.last)
            XCTAssertTrue(remote.hasPrefix("root@192.168.0.24:/mnt/us/books/.spine-transfer-"))
            XCTAssertFalse(remote.contains("a book.epub"))
            XCTAssertTrue(commands[2].1.last!.contains(replacing ? "mv -f --" : "mv -n --"))
            XCTAssertTrue(commands[2].1.last!.contains("test ! -L"))
        }
    }

    func testFailedUploadCleansTemporaryFileWithoutCommittingAndReportsCleanupFailure() throws {
        let item = EReaderItem(source: URL(fileURLWithPath: "/tmp/a.epub"), destination: "/mnt/us/books/Author/a.epub")
        for cleanupFails in [false, true] {
            var commands: [String] = []
            let transfer = EReaderTransfer(settings: settings, run: { executable, arguments in
                commands.append(arguments.last!)
                if executable == "/usr/bin/scp" { throw EReaderSettings.error("Upload failed") }
                if cleanupFails && arguments.last!.hasPrefix("rm -f") { throw EReaderSettings.error("Offline") }
                return ""
            })
            XCTAssertThrowsError(try transfer.send(item, replacing: true)) { error in
                XCTAssertTrue(error.localizedDescription.contains("Upload failed"))
                if cleanupFails { XCTAssertTrue(error.localizedDescription.contains("Could not clean up")) }
            }
            XCTAssertTrue(commands.last!.hasPrefix("rm -f -- '/mnt/us/books/.spine-transfer-"))
            XCTAssertFalse(commands.contains { $0.contains("mv -") })
        }
    }

    func testFinalizationFailureAlsoCleansTemporaryFile() throws {
        let item = EReaderItem(source: URL(fileURLWithPath: "/tmp/a.epub"), destination: "/mnt/us/books/Author/a.epub")
        var cleaned = false
        let transfer = EReaderTransfer(settings: settings, run: { _, arguments in
            let command = arguments.last!
            if command.contains("mv -n") { throw EReaderSettings.error("Destination appeared during transfer") }
            if command.hasPrefix("rm -f") { cleaned = true }
            return ""
        })
        XCTAssertThrowsError(try transfer.send(item, replacing: false))
        XCTAssertTrue(cleaned)
    }

    func testInventoryUsesOneReadOnlyCommandAndHandlesPathsAndSymlinks() throws {
        let store = try library()
        let root = store.root
        let author = root.appendingPathComponent("Eugene O'Neill")
        let hidden = root.appendingPathComponent(".hidden")
        try FileManager.default.createDirectory(at: author, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)
        let book = author.appendingPathComponent("Café\nPart Two.EPUB")
        for url in [book, hidden.appendingPathComponent("hidden.epub"), root.appendingPathComponent(".spine-transfer-123.epub")] {
            try Data().write(to: url)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.epub"), withDestinationURL: book)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked-folder"), withDestinationURL: author)
        var configured = settings; configured.destination = root.path + "/"
        var calls = 0
        let transfer = EReaderTransfer(settings: configured, run: { executable, arguments in
            calls += 1
            XCTAssertEqual(executable, "/usr/bin/ssh")
            XCTAssertTrue(arguments.last!.contains("-print0"))
            return try EPUB.command("/bin/sh", ["-c", arguments.last!])
        })
        XCTAssertEqual(try transfer.inventory(), [EReaderTransfer.pathKey(book.path)])
        XCTAssertEqual(calls, 1)
        let sourceBook = Book(id: "Café\nPart Two.EPUB", title: "Café", author: "Eugene O'Neill")
        XCTAssertEqual(EReaderTransfer.pathKey(transfer.destination(for: sourceBook)), EReaderTransfer.pathKey(book.path))
        XCTAssertEqual(EReaderTransfer.pathKey("/books//./JOSÉ/a.epub"), EReaderTransfer.pathKey("/books/Jose\u{301}/a.epub"))
    }

    func testInventoryHandlesEmptyMissingInvalidAndOutsideResults() throws {
        let store = try library()
        var configured = settings; configured.destination = store.root.path
        let transfer = EReaderTransfer(settings: configured, run: { _, arguments in
            try EPUB.command("/bin/sh", ["-c", arguments.last!])
        })
        XCTAssertTrue(try transfer.inventory().isEmpty)
        configured.destination += "/missing"
        let missing = EReaderTransfer(settings: configured, run: transfer.run)
        XCTAssertThrowsError(try missing.inventory())
        XCTAssertFalse(FileManager.default.fileExists(atPath: configured.destination))
        for output in ["Unexpected login banner", "/outside/book.epub\0", "/mnt/us/books/../book.epub\0"] {
            let malformed = EReaderTransfer(settings: settings, run: { _, _ in output })
            XCTAssertThrowsError(try malformed.inventory())
        }
    }
}
