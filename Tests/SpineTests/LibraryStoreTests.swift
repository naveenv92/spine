import XCTest
@testable import Spine

final class LibraryStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func epub(in directory: URL, title: String = "Piranesi", author: String = "Susanna Clarke") throws -> URL {
        let source = directory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: source.appendingPathComponent("mimetype"))
        try Data("<container><rootfiles><rootfile full-path='book.opf'/></rootfiles></container>".utf8)
            .write(to: source.appendingPathComponent("META-INF/container.xml"))
        let package = XMLElement(name: "package")
        let metadata = XMLElement(name: "metadata")
        metadata.addNamespace(XMLNode.namespace(withName: "dc", stringValue: "http://purl.org/dc/elements/1.1/") as! XMLNode)
        metadata.addChild(XMLElement(name: "dc:title", stringValue: title))
        metadata.addChild(XMLElement(name: "dc:creator", stringValue: author))
        package.addChild(metadata)
        try XMLDocument(rootElement: package).xmlData.write(to: source.appendingPathComponent("book.opf"))
        let archive = directory.appendingPathComponent("original.epub")
        try EPUB.command("/usr/bin/zip", ["-q", "-0", archive.path, "mimetype"], at: source)
        try EPUB.command("/usr/bin/zip", ["-q", "-r", archive.path, "META-INF", "book.opf"], at: source)
        return archive
    }

    func testBookNamesAreKebabCaseSafeAndBounded() {
        XCTAssertEqual(LibraryStore.bookName("Susanna Clarke", fallback: "unknown"), "susanna-clarke")
        XCTAssertEqual(LibraryStore.bookName("../Café: A / Book?!", fallback: "unknown"), "cafe-a-book")
        XCTAssertEqual(LibraryStore.bookName("... /", fallback: "untitled"), "untitled")
        XCTAssertEqual(LibraryStore.bookName("東京", fallback: "unknown"), "東京")
        XCTAssertLessThanOrEqual(LibraryStore.bookName(String(repeating: "本", count: 300), fallback: "unknown").utf8.count, 180)
    }

    func testFolderImportDiscoversNestedEPUBsWithoutHiddenLinksOrDestination() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let input = directory.appendingPathComponent("input")
        let nested = input.appendingPathComponent("nested/deeper")
        let root = input.appendingPathComponent("managed-library")
        let hidden = input.appendingPathComponent(".hidden")
        let outside = directory.appendingPathComponent("outside")
        for folder in [nested, root, hidden, outside] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let first = input.appendingPathComponent("first.epub")
        let second = nested.appendingPathComponent("second.EPUB")
        for url in [first, second, hidden.appendingPathComponent("hidden.epub"),
                    root.appendingPathComponent("already-managed.epub"), outside.appendingPathComponent("external.epub")] {
            try FileManager.default.copyItem(at: source, to: url)
        }
        try Data().write(to: input.appendingPathComponent("notes.txt"))
        try Data().write(to: input.appendingPathComponent(".hidden.epub"))
        try FileManager.default.createSymbolicLink(at: input.appendingPathComponent("link.epub"), withDestinationURL: source)
        try FileManager.default.createSymbolicLink(at: input.appendingPathComponent("linked-folder"), withDestinationURL: outside)
        let files = try LibraryStore.epubFiles(in: [input, nested, first], excluding: root)
        XCTAssertEqual(Set(files.map(\.lastPathComponent)), Set(["first.epub", "second.EPUB"]))
        let store = LibraryStore(root: root)
        let imported = try files.map { try store.importBook($0) }
        XCTAssertEqual(Set(imported.map(\.id)), Set(["Susanna Clarke/piranesi.epub", "Susanna Clarke/piranesi-2.epub"]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertEqual(try LibraryStore.epubFiles(in: [root], excluding: root), [])
    }

    func testFolderDiscoveryHandlesEmptyAndMissingSelections() throws {
        let directory = try temporaryDirectory()
        XCTAssertEqual(try LibraryStore.epubFiles(in: [directory]), [])
        XCTAssertThrowsError(try LibraryStore.epubFiles(in: [directory.appendingPathComponent("missing")]))
    }

    func testAuthorFoldersUseSafeTitleCaseNames() {
        XCTAssertEqual(LibraryStore.authorFolder("sUSANNA CLARKE"), "Susanna Clarke")
        XCTAssertEqual(LibraryStore.authorFolder("  J. R. R.   TOLKIEN  "), "J. R. R. Tolkien")
        XCTAssertEqual(LibraryStore.authorFolder("josé saramago"), "José Saramago")
        XCTAssertEqual(LibraryStore.authorFolder("../susanna/clarke:"), "Susanna Clarke")
        XCTAssertEqual(LibraryStore.authorFolder("..."), "Unknown Author")
        XCTAssertLessThanOrEqual(LibraryStore.authorFolder(String(repeating: "本", count: 300)).utf8.count, 180)
    }

    func testSameAuthorSharesFolderWhileMetadataStaysHiddenAndRemovalKeepsSibling() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        let first = try store.importBook(source)
        var second = try store.importBook(source)
        second.title = "Another Book"
        second = try store.save(second)
        XCTAssertEqual(second.id, "Susanna Clarke/another-book.epub")
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Susanna Clarke").path)), Set(["piranesi.epub", "another-book.epub"]))
        XCTAssertTrue(store.cover(second.id).path.contains("/.spine/Susanna Clarke/"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".spine"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent(".spine/not-a-library-book.epub"))
        XCTAssertEqual(Set(try store.load().map(\.id)), Set([first.id, second.id]))
        try store.remove(first.id) { try FileManager.default.removeItem(at: $0) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.file(second.id).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file(second.id).appendingPathExtension("backup").path))
    }

    func testFailedRenamedSavePreservesSharedAuthorFolder() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        let first = try store.importBook(source)
        var second = try store.importBook(source)
        // Force repackaging to fail after copying into the shared author directory.
        try EPUB.command("/usr/bin/zip", ["-d", store.file(second.id).path, "mimetype"])
        let original = try Data(contentsOf: store.file(second.id))
        second.title = "Failed Rename"
        XCTAssertThrowsError(try store.save(second))
        XCTAssertEqual(try Data(contentsOf: store.file(second.id)), original)
        XCTAssertEqual(try Data(contentsOf: store.file(first.id)), try Data(contentsOf: source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Susanna Clarke/failed-rename.epub").path))
    }

    func testHiddenMetadataCannotRedirectWritesOutsideLibrary() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(".spine"), withDestinationURL: outside)
        XCTAssertThrowsError(try LibraryStore(root: root).importBook(source))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Susanna Clarke/piranesi.epub").path))
    }

    func testImportsCopiesWithoutOverwritingAndLoadsNestedAndLegacyBooks() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let original = try Data(contentsOf: source)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        let first = try store.importBook(source)
        XCTAssertEqual(first.id, "Susanna Clarke/piranesi.epub")
        XCTAssertEqual(try Data(contentsOf: store.file(first.id)), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let second = try store.importBook(source)
        XCTAssertEqual(second.id, "Susanna Clarke/piranesi-2.epub")
        XCTAssertEqual(try Data(contentsOf: store.file(first.id)), original)
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("old-id.epub"))
        XCTAssertEqual(Set(try store.load().map(\.id)), Set([first.id, second.id, "old-id.epub"]))
        XCTAssertEqual(store.cover(first.id).lastPathComponent, "piranesi.cover")

        var updated = first
        updated.title = "Updated title"
        let archive = try EPUB(store.file(first.id)); defer { archive.clean() }
        try archive.save(updated, to: store.file(first.id))
        XCTAssertEqual(try store.load().first { $0.id == first.id }?.title, "Updated title")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.file(first.id).appendingPathExtension("backup").path))
        let saved = try EPUB(store.file(first.id)); defer { saved.clean() }
        updated.author = "Updated author"
        try saved.save(updated, to: store.file(first.id))
        XCTAssertEqual(try store.load().first { $0.id == first.id }?.author, "Updated author")
    }

    func testMissingMetadataUsesFallbackFolders() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory, title: "", author: "")
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertEqual(try LibraryStore(root: root).importBook(source).id, "Unknown Author/untitled.epub")
    }

    func testUnavailableRootIsNotSilentlyRecreated() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("missing")
        let store = LibraryStore(root: root)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.importBook(source))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSymlinkCannotRedirectImportOutsideLibrary() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Susanna Clarke"), withDestinationURL: outside)
        let store = LibraryStore(root: root)
        XCTAssertThrowsError(try store.importBook(source))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.epub"), withDestinationURL: source)
        XCTAssertTrue(try store.load().isEmpty)
    }

    func testRemovalTrashesBookFilesAndEmptyFoldersButPreservesLibraryAndOriginal() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        let book = try store.importBook(source)
        try Data("cover".utf8).write(to: store.cover(book.id))
        let trash = directory.appendingPathComponent("trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        var trashed: [URL] = []
        try store.remove(book.id) { url in
            trashed.append(url)
            let target = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
        XCTAssertEqual(trashed.map(\.lastPathComponent), ["piranesi.epub", "piranesi.cover", "Susanna Clarke", "Susanna Clarke", ".spine"])
        let names = try FileManager.default.contentsOfDirectory(atPath: trash.path)
        XCTAssertTrue(names.contains { $0.hasSuffix("-piranesi.epub") })
        XCTAssertTrue(names.contains { $0.hasSuffix("-piranesi.cover") })
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRemovalPreservesSharedFoldersAndUnrelatedFiles() throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(root: directory)
        let folder = directory.appendingPathComponent("author/shared")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["one.epub", "two.epub", "notes.txt"] {
            try Data(name.utf8).write(to: folder.appendingPathComponent(name))
        }
        let id = "author/shared/one.epub"
        try FileManager.default.createDirectory(at: store.cover(id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: store.cover(id))
        var trashed: [String] = []
        try store.remove("author/shared/one.epub") { url in
            if !url.hasDirectoryPath { trashed.append(url.lastPathComponent) }
            try FileManager.default.moveItem(at: url, to: directory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent))
        }
        XCTAssertEqual(Set(trashed), Set(["one.epub", "one.cover"]))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), Set(["two.epub", "notes.txt"]))
    }

    func testFlatBookRemovalNeverTrashesLibraryRoot() throws {
        let directory = try temporaryDirectory()
        let store = LibraryStore(root: directory)
        try Data().write(to: directory.appendingPathComponent("flat.epub"))
        let moved = directory.appendingPathComponent("trashed")
        var names: [String] = []
        try store.remove("flat.epub") { url in
            names.append(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: moved)
        }
        XCTAssertEqual(names, ["flat.epub"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
    }

    func testRemovalRejectsOutsidePathsAndPropagatesTrashFailure() throws {
        let directory = try temporaryDirectory()
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("outside.epub")
        try Data().write(to: outside)
        let store = LibraryStore(root: root)
        XCTAssertThrowsError(try store.remove("../outside.epub") { _ in XCTFail("Must not trash outside library") })
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.epub"), withDestinationURL: outside)
        XCTAssertThrowsError(try store.remove("linked.epub") { _ in XCTFail("Must not follow external symlinks") })
        try Data().write(to: root.appendingPathComponent("book.epub"))
        XCTAssertThrowsError(try store.remove("book.epub") { _ in throw CocoaError(.fileWriteNoPermission) })
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("book.epub").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testSavingRenamesAuthorTitleAndBothWhileKeepingCoverWithoutBackup() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        var book = try store.importBook(source)
        let originalBytes = try Data(contentsOf: source)
        let cover = Data("cover image".utf8)
        try cover.write(to: store.cover(book.id))
        for (author, title, expected) in [
            ("New Author", "Piranesi", "New Author/piranesi.epub"),
            ("New Author", "New Title", "New Author/new-title.epub"),
            ("Other Author", "Other Title", "Other Author/other-title.epub")
        ] {
            let previous = book
            book.author = author; book.title = title
            book = try store.save(book)
            XCTAssertEqual(book.id, expected)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.file(previous.id).path))
            XCTAssertEqual(try Data(contentsOf: store.cover(book.id)), cover)
            let saved = try EPUB(store.file(book.id)); defer { saved.clean() }
            XCTAssertEqual(try saved.book(id: book.id), book)
            XCTAssertFalse(FileManager.default.fileExists(atPath: store.file(book.id).appendingPathExtension("backup").path))
            XCTAssertEqual(try store.load().map(\.id), [expected])
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Susanna Clarke").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("New Author").path))
        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        XCTAssertFalse(files.allObjects.compactMap { $0 as? URL }.contains { $0.pathExtension == "backup" })
    }

    func testSavingIntoOccupiedNamePreservesOtherBooksAndKeepsSuffixOnLaterSaves() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        let first = try store.importBook(source)
        var second = try store.importBook(source)
        second.title = "Another Book"
        second = try store.save(second)
        second.title = first.title
        second = try store.save(second)
        XCTAssertEqual(second.id, "Susanna Clarke/piranesi-2.epub")
        XCTAssertEqual(try Data(contentsOf: store.file(first.id)), try Data(contentsOf: source))
        let id = second.id
        second.publisher = "New publisher"
        second = try store.save(second)
        XCTAssertEqual(second.id, id)
        second.author = "SUSANNA CLARKE"; second.title = "PIRANESI"
        XCTAssertEqual(try store.save(second).id, id)
    }

    func testRenamePreservesUnrelatedFilesInOldFolder() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        var book = try store.importBook(source)
        let old = store.file(book.id)
        let notes = old.deletingLastPathComponent().appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: notes)
        book.title = "New Title"
        let updated = try store.save(book)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try Data(contentsOf: notes), Data("keep".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.file(updated.id).path))
    }

    func testRenameFailureLeavesOriginalBookAndMetadataUntouched() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let root = directory.appendingPathComponent("library")
        let outside = directory.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        var book = try store.importBook(source)
        let original = try Data(contentsOf: store.file(book.id))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("New Author"), withDestinationURL: outside)
        book.author = "New Author"
        XCTAssertThrowsError(try store.save(book))
        XCTAssertEqual(try Data(contentsOf: store.file(book.id)), original)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
}
