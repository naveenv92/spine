import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Book: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var author: String
    var description: String = ""
    var publisher: String = ""
    var language: String = ""
    var tags: String = ""
    var addedAt: Date?
}
struct EPUB {
    let directory: URL
    let package: URL
    let xml: XMLDocument
    @discardableResult static func command(_ executable: String, _ arguments: [String], at directory: URL? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe(); process.standardOutput = output; process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "EPUB", code: 1, userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)]) }
        return String(decoding: data, as: UTF8.self)
    }
    init(_ source: URL) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let listing = try Self.command("/usr/bin/unzip", ["-Z1", source.path])
        guard listing.split(separator: "\n").allSatisfy({ path in
            !path.hasPrefix("/") && !path.split(separator: "/").contains("..")
        }) else { throw CocoaError(.fileReadCorruptFile) }
        // shortcut: no archive expansion limit yet; only import trusted local EPUBs.
        try Self.command("/usr/bin/unzip", ["-qq", source.path, "-d", directory.path])
        let container = try XMLDocument(contentsOf: directory.appendingPathComponent("META-INF/container.xml"), options: [.nodeLoadExternalEntitiesNever])
        guard let path = try container.nodes(forXPath: "//*[local-name()='rootfile']/@full-path").first?.stringValue,
              !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw CocoaError(.fileReadCorruptFile) }
        package = directory.appendingPathComponent(path)
        xml = try XMLDocument(contentsOf: package, options: [.nodeLoadExternalEntitiesNever])
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func values(_ name: String) throws -> [XMLNode] { try xml.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='\(name)']") }
    func book(id: String) throws -> Book {
        func value(_ name: String) throws -> String { try values(name).compactMap(\.stringValue).joined(separator: "; ") }
        return try Book(id: id, title: value("title"), author: value("creator"), description: value("description"), publisher: value("publisher"), language: value("language"), tags: value("subject"))
    }
    private func coverItem() throws -> XMLElement? {
        let coverID = try xml.nodes(forXPath: "//*[local-name()='meta'][@name='cover']/@content").first?.stringValue
        let items = try xml.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']").compactMap { $0 as? XMLElement }
        return items.first { ($0.attribute(forName: "properties")?.stringValue ?? "").split(separator: " ").contains("cover-image") }
            ?? items.first { coverID != nil && $0.attribute(forName: "id")?.stringValue == coverID }
    }

    private func resource(_ href: String) throws -> URL {
        guard let decoded = href.removingPercentEncoding, !decoded.hasPrefix("/"),
              !decoded.contains(":") else { throw CocoaError(.fileReadCorruptFile) }
        let url = package.deletingLastPathComponent().appendingPathComponent(decoded)
        let base = directory.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base) else { throw CocoaError(.fileReadCorruptFile) }
        return url
    }

    func cover() throws -> Data? {
        guard let href = try coverItem()?.attribute(forName: "href")?.stringValue else { return nil }
        return try Data(contentsOf: resource(href))
    }

    static func coverImage(_ data: Data) throws -> NSBitmapImageRep {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source),
              [UTType.png.identifier, UTType.jpeg.identifier].contains(type as String),
              let image = NSBitmapImageRep(data: data), image.pixelsWide > 0, image.pixelsHigh > 0 else {
            throw NSError(domain: "EPUB", code: 2, userInfo: [NSLocalizedDescriptionKey: "Choose a valid PNG or JPEG image."])
        }
        return image
    }

    func replaceCover(_ data: Data) throws {
        let image = try Self.coverImage(data)
        if let item = try coverItem() {
            guard let href = item.attribute(forName: "href")?.stringValue else { throw CocoaError(.fileReadCorruptFile) }
            let format: NSBitmapImageRep.FileType
            switch item.attribute(forName: "media-type")?.stringValue {
            case "image/jpeg": format = .jpeg
            case "image/png": format = .png
            case "image/gif": format = .gif
            default:
                // shortcut: preserve raster image paths; SVG cover replacement needs reference rewriting.
                throw NSError(domain: "EPUB", code: 3, userInfo: [NSLocalizedDescriptionKey: "Replacing this cover format is not supported yet. JPEG, PNG, and GIF covers are supported."])
            }
            let url = try resource(href)
            guard var pixels = image.cgImage else { throw CocoaError(.fileReadCorruptFile) }
            // Flatten transparency onto white when the existing cover is JPEG.
            if format == .jpeg {
                guard let context = CGContext(data: nil, width: pixels.width, height: pixels.height, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let rect = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
                context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect); context.draw(pixels, in: rect)
                guard let opaque = context.makeImage() else { throw CocoaError(.fileWriteUnknown) }
                pixels = opaque
            }
            let type = format == .jpeg ? UTType.jpeg : (format == .gif ? UTType.gif : UTType.png)
            let replacement = NSMutableData()
            guard let output = CGImageDestinationCreateWithData(replacement, type.identifier as CFString, 1, nil) else { throw CocoaError(.fileWriteUnknown) }
            CGImageDestinationAddImage(output, pixels, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(output) else { throw CocoaError(.fileWriteUnknown) }
            try (replacement as Data).write(to: url, options: .atomic)
        } else {
            guard let manifest = try xml.nodes(forXPath: "//*[local-name()='manifest']").first as? XMLElement,
                  let metadata = try xml.nodes(forXPath: "//*[local-name()='metadata']").first as? XMLElement,
                  let png = image.representation(using: .png, properties: [:]) else { throw CocoaError(.fileReadCorruptFile) }
            let id = "spine-cover-" + UUID().uuidString.lowercased()
            let href = id + ".png"
            let item = XMLElement(name: "item", uri: manifest.uri)
            for (name, value) in [("id", id), ("href", href), ("media-type", "image/png")] {
                item.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
            }
            if xml.rootElement()?.attribute(forName: "version")?.stringValue?.hasPrefix("3") == true {
                item.addAttribute(XMLNode.attribute(withName: "properties", stringValue: "cover-image") as! XMLNode)
            }
            manifest.addChild(item)
            let existing = try xml.nodes(forXPath: "//*[local-name()='metadata']/*[local-name()='meta'][@name='cover']")
            existing.forEach { $0.detach() }
            let meta = XMLElement(name: "meta", uri: metadata.uri)
            meta.addAttribute(XMLNode.attribute(withName: "name", stringValue: "cover") as! XMLNode)
            meta.addAttribute(XMLNode.attribute(withName: "content", stringValue: id) as! XMLNode)
            metadata.addChild(meta)
            try png.write(to: resource(href), options: .atomic)
        }
    }
    func save(_ book: Book, to destination: URL) throws {
        guard let metadata = try xml.nodes(forXPath: "//*[local-name()='metadata']").first as? XMLElement else { throw CocoaError(.fileReadCorruptFile) }
        for (name, text) in [("title",book.title),("creator",book.author),("description",book.description),("publisher",book.publisher),("language",book.language),("subject",book.tags)] {
            let existing = try values(name)
            if existing.compactMap(\.stringValue).joined(separator: "; ") == text { continue }
            existing.forEach { $0.detach() }
            let parts = ["creator", "subject"].contains(name) ? text.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) } : [text]
            for part in parts where !part.isEmpty {
                let node = XMLElement(name: "dc:\(name)", uri: "http://purl.org/dc/elements/1.1/")
                node.stringValue = part; metadata.addChild(node)
            }
        }
        try xml.xmlData.write(to: package)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".epub")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.command("/usr/bin/zip", ["-q", "-0", temporary.path, "mimetype"], at: directory)
        try Self.command("/usr/bin/zip", ["-q", "-r", temporary.path, ".", "-x", "mimetype"], at: directory)
        let check = try EPUB(temporary); defer { check.clean() }
        _ = try check.book(id: book.id)
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
    }
}
