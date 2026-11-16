import Foundation

struct Book: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var author: String
    var description: String = ""
    var publisher: String = ""
    var language: String = ""
    var tags: String = ""
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
    func cover() throws -> Data? {
        let coverID = try xml.nodes(forXPath: "//*[local-name()='meta'][@name='cover']/@content").first?.stringValue
        let items = try xml.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")
        guard let item = items.compactMap({ $0 as? XMLElement }).first(where: { $0.attribute(forName: "id")?.stringValue == coverID || ($0.attribute(forName: "properties")?.stringValue ?? "").split(separator: " ").contains("cover-image") }), let href = item.attribute(forName: "href")?.stringValue else { return nil }
        return try Data(contentsOf: package.deletingLastPathComponent().appendingPathComponent(href.removingPercentEncoding ?? href))
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
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary, backupItemName: destination.lastPathComponent + ".backup", options: .withoutDeletingBackupItem)
    }
}
