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

    private func destination(for book: Book) throws -> URL {
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
        return directory.appendingPathComponent(title + ".epub")
    }

    private func id(for url: URL) -> String {
        url.resolvingSymlinksInPath().pathComponents
            .dropFirst(root.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/")
    }

    @discardableResult func importBook(_ source: URL) throws -> Book {
        try validate()
        let epub = try EPUB(source); defer { epub.clean() }
        var book = try epub.book(id: "")
        let destination = try destination(for: book)
        try FileManager.default.copyItem(at: source, to: destination)
        book.id = id(for: destination)
        return book
    }

    func save(_ book: Book) throws -> Book {
        try validate()
        let source = file(book.id)
        try checkLocation(source)
        let epub = try EPUB(source); defer { epub.clean() }
        let original = try epub.book(id: book.id)
        let authorChanged = Self.folderName(original.author, fallback: "unknown_author") != Self.folderName(book.author, fallback: "unknown_author")
        let titleChanged = Self.folderName(original.title, fallback: "untitled") != Self.folderName(book.title, fallback: "untitled")
        guard authorChanged || titleChanged else {
            try epub.save(book, to: source)
            return book
        }
        try checkLocation(cover(book.id))
        try checkLocation(source.appendingPathExtension("backup"))
        let destination = try destination(for: book)
        var updated = book
        updated.id = id(for: destination)
        var saved = false
        do {
            try FileManager.default.copyItem(at: source, to: destination)
            if FileManager.default.fileExists(atPath: cover(book.id).path) {
                try FileManager.default.copyItem(at: cover(book.id), to: cover(updated.id))
            }
            try epub.save(updated, to: destination)
            saved = true
            // The new EPUB and its pre-edit backup are safe before removing old files.
            try remove(book.id) { try FileManager.default.removeItem(at: $0) }
        } catch {
            if !saved { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }
            throw error
        }
        return updated
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
            let id = id(for: url)
            if let book = try? epub.book(id: id) {
                if let data = try? epub.cover() { try? data.write(to: cover(id), options: .atomic) }
                books.append(book)
            }
        }
        if let scanError { throw scanError }
        return books
    }

    func remove(_ id: String, trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws {
        try validate()
        let book = file(id).standardizedFileURL
        try checkLocation(book)
        guard book.pathExtension.lowercased() == "epub",
              try book.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]).isRegularFile == true,
              try book.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        let manager = FileManager.default
        let files = [book, cover(id), book.appendingPathExtension("backup")]
            .filter { manager.fileExists(atPath: $0.path) }
        for url in files { try checkLocation(url) }
        var directory = book.deletingLastPathComponent()
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let contents = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        // Only trash a whole folder when it contains this book's files alone.
        if directory.resolvingSymlinksInPath().standardizedFileURL != base,
           contents.allSatisfy({ files.contains($0.standardizedFileURL) || $0.lastPathComponent == ".DS_Store" }) {
            try trash(directory)
            directory.deleteLastPathComponent()
        } else {
            for url in files { try trash(url) }
        }
        while directory.resolvingSymlinksInPath().standardizedFileURL != base {
            try checkLocation(directory)
            let remaining = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            guard remaining.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) else { break }
            try trash(directory)
            directory.deleteLastPathComponent()
        }
    }
}
