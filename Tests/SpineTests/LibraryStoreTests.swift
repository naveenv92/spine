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

    func testFolderNamesAreLowercaseSafeAndBounded() {
        XCTAssertEqual(LibraryStore.folderName("Susanna Clarke", fallback: "unknown"), "susanna_clarke")
        XCTAssertEqual(LibraryStore.folderName("../Café: A / Book?!", fallback: "unknown"), "cafe_a_book")
        XCTAssertEqual(LibraryStore.folderName("... /", fallback: "untitled"), "untitled")
        XCTAssertEqual(LibraryStore.folderName("東京", fallback: "unknown"), "東京")
        XCTAssertLessThanOrEqual(LibraryStore.folderName(String(repeating: "本", count: 300), fallback: "unknown").utf8.count, 180)
    }

    func testImportsCopiesWithoutOverwritingAndLoadsNestedAndLegacyBooks() throws {
        let directory = try temporaryDirectory()
        let source = try epub(in: directory)
        let original = try Data(contentsOf: source)
        let root = directory.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        let first = try store.importBook(source)
        XCTAssertEqual(first.id, "susanna_clarke/piranesi/piranesi.epub")
        XCTAssertEqual(try Data(contentsOf: store.file(first.id)), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        let second = try store.importBook(source)
        XCTAssertEqual(second.id, "susanna_clarke/piranesi_2/piranesi.epub")
        XCTAssertEqual(try Data(contentsOf: store.file(first.id)), original)
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("old-id.epub"))
        XCTAssertEqual(Set(try store.load().map(\.id)), Set([first.id, second.id, "old-id.epub"]))
        XCTAssertEqual(store.cover(first.id).lastPathComponent, "piranesi.cover")

        var updated = first
        updated.title = "Updated title"
        let archive = try EPUB(store.file(first.id)); defer { archive.clean() }
        try archive.save(updated, to: store.file(first.id))
        XCTAssertEqual(try store.load().first { $0.id == first.id }?.title, "Updated title")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.file(first.id).path + ".backup"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: store.file(first.id).path + ".backup")), original)
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
        XCTAssertEqual(try LibraryStore(root: root).importBook(source).id, "unknown_author/untitled/untitled.epub")
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
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("susanna_clarke"), withDestinationURL: outside)
        let store = LibraryStore(root: root)
        XCTAssertThrowsError(try store.importBook(source))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.epub"), withDestinationURL: source)
        XCTAssertTrue(try store.load().isEmpty)
    }
}
