import AppKit
import ImageIO
import XCTest
@testable import Spine

final class CoverTests: XCTestCase {
    private func image(_ color: NSColor = .red, format: NSBitmapImageRep.FileType = .png) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(try XCTUnwrap(color.usingColorSpace(.deviceRGB)).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 6))
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage()))
        return try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
    }

    private func fixture(version: String, type: String? = nil, href: String = "images/cover.png") throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("OEBPS/images"), withIntermediateDirectories: true)
        try Data("application/epub+zip".utf8).write(to: source.appendingPathComponent("mimetype"))
        try Data("<container><rootfiles><rootfile full-path='OEBPS/book.opf'/></rootfiles></container>".utf8)
            .write(to: source.appendingPathComponent("META-INF/container.xml"))
        let meta = type != nil && version == "2.0" ? "<meta name='cover' content='art'/>" : ""
        let properties = version == "3.0" ? " properties='cover-image'" : ""
        let item = type.map { "<item id='art' href='\(href)' media-type='\($0)'\(properties)/>" } ?? ""
        let opf = """
        <package xmlns="http://www.idpf.org/2007/opf" version="\(version)" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <metadata><dc:title>Test Book</dc:title><dc:creator>Test Author</dc:creator>\(meta)</metadata>
        <manifest>\(item)<item id="page" href="cover.xhtml" media-type="application/xhtml+xml"/></manifest>
        <spine><itemref idref="page"/></spine></package>
        """
        try Data(opf.utf8).write(to: source.appendingPathComponent("OEBPS/book.opf"))
        try Data("<html xmlns='http://www.w3.org/1999/xhtml'><body><img src='\(href)' alt='Cover'/></body></html>".utf8)
            .write(to: source.appendingPathComponent("OEBPS/cover.xhtml"))
        try image(.blue).write(to: source.appendingPathComponent("OEBPS/images/cover.png"))
        let url = directory.appendingPathComponent("book.epub")
        try EPUB.command("/usr/bin/zip", ["-q", "-0", url.path, "mimetype"], at: source)
        try EPUB.command("/usr/bin/zip", ["-q", "-r", url.path, "META-INF", "OEBPS"], at: source)
        return url
    }

    func testExistingRasterCoversKeepReferencesAndUseCorrectEncoding() throws {
        for (version, type, expected) in [("2.0", "image/jpeg", "public.jpeg"), ("3.0", "image/png", "public.png"), ("3.0", "image/gif", "com.compuserve.gif")] {
            let url = try fixture(version: version, type: type)
            let original = try Data(contentsOf: url)
            let epub = try EPUB(url); defer { epub.clean() }
            let page = try Data(contentsOf: epub.directory.appendingPathComponent("OEBPS/cover.xhtml"))
            let metadata = try epub.book(id: "book.epub")
            try epub.replaceCover(image())
            try epub.save(metadata, to: url)
            let saved = try EPUB(url); defer { saved.clean() }
            let data = try XCTUnwrap(saved.cover())
            let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
            XCTAssertEqual(CGImageSourceGetType(source) as String?, expected)
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(bitmap.pixelsWide, 4); XCTAssertEqual(bitmap.pixelsHigh, 6)
            XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB)).redComponent, 0.8)
            XCTAssertEqual(try Data(contentsOf: saved.directory.appendingPathComponent("OEBPS/cover.xhtml")), page)
            XCTAssertEqual(try saved.book(id: metadata.id), metadata)
            XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("backup")), original)
        }
    }

    func testAddsMissingCoverForEPUB2And3AndRefreshesCache() throws {
        for version in ["2.0", "3.0"] {
            let url = try fixture(version: version)
            let store = LibraryStore(root: url.deletingLastPathComponent())
            let epub = try EPUB(url); defer { epub.clean() }
            XCTAssertNil(try epub.cover())
            let book = try epub.book(id: "book.epub")
            try store.replaceCover(image(), for: book)
            let saved = try EPUB(url); defer { saved.clean() }
            let data = try XCTUnwrap(saved.cover())
            XCTAssertNotNil(NSBitmapImageRep(data: data))
            XCTAssertEqual(try saved.xml.nodes(forXPath: "//*[local-name()='meta'][@name='cover']").count, 1)
            XCTAssertEqual(try saved.xml.nodes(forXPath: "//*[local-name()='item'][@properties='cover-image']").count, version == "3.0" ? 1 : 0)
            XCTAssertEqual(try saved.xml.nodes(forXPath: "//*[local-name()='spine']/*").count, 1)
            _ = try store.load()
            XCTAssertEqual(try Data(contentsOf: store.cover(book.id)), data)
        }
    }

    func testJPEGReplacementFlattensTransparencyOnWhite() throws {
        let url = try fixture(version: "2.0", type: "image/jpeg")
        let epub = try EPUB(url); defer { epub.clean() }
        try epub.replaceCover(image(.clear))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(epub.cover())))
        let color = try XCTUnwrap(bitmap.colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.9)
        XCTAssertGreaterThan(color.greenComponent, 0.9)
        XCTAssertGreaterThan(color.blueComponent, 0.9)
    }

    func testInvalidImagesUnsupportedCoversAndEscapingPathsLeaveOriginalUntouched() throws {
        let url = try fixture(version: "3.0", type: "image/png")
        let store = LibraryStore(root: url.deletingLastPathComponent())
        let original = try Data(contentsOf: url)
        let book = Book(id: "book.epub", title: "Test Book", author: "Test Author")
        XCTAssertThrowsError(try store.replaceCover(Data("not an image".utf8), for: book))
        XCTAssertEqual(try Data(contentsOf: url), original)
        for (type, href) in [("image/svg+xml", "images/cover.png"), ("image/png", "../../outside.png")] {
            let unsafe = try fixture(version: "3.0", type: type, href: href)
            let bytes = try Data(contentsOf: unsafe)
            let library = LibraryStore(root: unsafe.deletingLastPathComponent())
            XCTAssertThrowsError(try library.replaceCover(image(), for: book))
            XCTAssertEqual(try Data(contentsOf: unsafe), bytes)
        }
    }
}
