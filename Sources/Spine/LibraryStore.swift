import Foundation

struct LibraryStore {
    let root: URL

    func file(_ id: String) -> URL { root.appendingPathComponent(id) }
    func cover(_ id: String) -> URL { file(id).deletingPathExtension().appendingPathExtension("cover") }

    static func folderName(_ text: String, fallback: String) -> String {
        var name = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "_")
        // Leave room for file extensions and backup names within filesystem limits.
        while name.utf8.count > 180 { name.removeLast() }
        return name.isEmpty ? fallback : name
    }

    func validate() throws {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
    }

    private func checkLocation(_ url: URL) throws {
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard path.hasPrefix(base == "/" ? "/" : base + "/") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
    }

    @discardableResult func importBook(_ source: URL) throws -> Book {
        try validate()
        let epub = try EPUB(source); defer { epub.clean() }
        var book = try epub.book(id: "")
        let author = Self.folderName(book.author, fallback: "unknown_author")
        let title = Self.folderName(book.title, fallback: "untitled")
        let authorDirectory = root.appendingPathComponent(author, isDirectory: true)
        try checkLocation(authorDirectory)
        var directory = authorDirectory.appendingPathComponent(title, isDirectory: true)
        var number = 2
        while FileManager.default.fileExists(atPath: directory.path) {
            directory = authorDirectory.appendingPathComponent("\(title)_\(number)", isDirectory: true)
            number += 1
        }
        try checkLocation(directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(title + ".epub")
        try FileManager.default.copyItem(at: source, to: destination)
        book.id = "\(author)/\(directory.lastPathComponent)/\(destination.lastPathComponent)"
        return book
    }

    func load() throws -> [Book] {
        try validate()
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        var scanError: Error?
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else {
            throw CocoaError(.fileReadUnknown)
        }
        var books: [Book] = []
        for case let url as URL in files {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true, values.isRegularFile == true,
                  url.pathExtension.lowercased() == "epub" else { continue }
            try checkLocation(url)
            guard let epub = try? EPUB(url) else { continue }; defer { epub.clean() }
            let id = url.resolvingSymlinksInPath().pathComponents
                .dropFirst(root.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
            if let book = try? epub.book(id: id) {
                if let data = try? epub.cover() { try? data.write(to: cover(id), options: .atomic) }
                books.append(book)
            }
        }
        if let scanError { throw scanError }
        return books
    }
}
