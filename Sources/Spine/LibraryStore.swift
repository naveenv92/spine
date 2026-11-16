import Foundation

struct LibraryStore {
    let root: URL

    func file(_ id: String) -> URL { root.appendingPathComponent(id) }
    func cover(_ id: String) -> URL { root.appendingPathComponent(".spine").appendingPathComponent(id).deletingPathExtension().appendingPathExtension("cover") }

    private func prepareMetadata(_ id: String) throws {
        try checkLocation(cover(id))
        try FileManager.default.createDirectory(at: cover(id).deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    static func authorFolder(_ text: String) -> String {
        let invalid = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        var name = text.components(separatedBy: invalid).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
            .capitalized(with: Locale(identifier: "en_US_POSIX"))
        while name.utf8.count > 180 { name.removeLast() }
        return name.rangeOfCharacter(from: .alphanumerics) == nil ? "Unknown Author" : name
    }

    static func folderName(_ text: String, fallback: String) -> String {
        var name = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "_")
        // Leave room for file extensions within filesystem limits.
        while name.utf8.count > 180 { name.removeLast() }
        return name.isEmpty ? fallback : name
    }

    func validate() throws {
        let values = try root.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { throw CocoaError(.fileReadUnsupportedScheme) }
    }

    private func checkLocation(_ url: URL) throws {
        let base = root.standardizedFileURL
        var ancestor = url.standardizedFileURL
        guard ancestor.path.hasPrefix(base.path == "/" ? "/" : base.path + "/"), ancestor.path != base.path else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        // Inspect existing ancestors too: resolving a missing leaf can miss parent symlinks.
        while ancestor.path != base.path {
            if (try? ancestor.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            ancestor.deleteLastPathComponent()
        }
    }

    private func destination(for book: Book) throws -> URL {
        let author = Self.authorFolder(book.author)
        let title = Self.folderName(book.title, fallback: "untitled")
        let authorDirectory = root.appendingPathComponent(author, isDirectory: true)
        try checkLocation(authorDirectory)
        var destination = authorDirectory.appendingPathComponent(title + ".epub")
        var number = 2
        while [destination, cover(id(for: destination))].contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            destination = authorDirectory.appendingPathComponent("\(title)_\(number).epub")
            number += 1
        }
        try checkLocation(destination)
        try FileManager.default.createDirectory(at: authorDirectory, withIntermediateDirectories: true)
        return destination
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
        book.id = id(for: destination)
        try prepareMetadata(book.id)
        try FileManager.default.copyItem(at: source, to: destination)
        return book
    }

    func save(_ book: Book) throws -> Book {
        try validate()
        let source = file(book.id)
        try checkLocation(source)
        let epub = try EPUB(source); defer { epub.clean() }
        let original = try epub.book(id: book.id)
        let authorChanged = Self.authorFolder(original.author) != Self.authorFolder(book.author)
        let titleChanged = Self.folderName(original.title, fallback: "untitled") != Self.folderName(book.title, fallback: "untitled")
        guard authorChanged || titleChanged else {
            try prepareMetadata(book.id)
            try epub.save(book, to: source)
            return book
        }
        try checkLocation(cover(book.id))
        let destination = try destination(for: book)
        var updated = book
        updated.id = id(for: destination)
        var saved = false
        do {
            try prepareMetadata(updated.id)
            try FileManager.default.copyItem(at: source, to: destination)
            if FileManager.default.fileExists(atPath: cover(book.id).path) {
                try FileManager.default.copyItem(at: cover(book.id), to: cover(updated.id))
            }
            try epub.save(updated, to: destination)
            saved = true
            // The updated EPUB is safe before removing old files.
            try remove(book.id) { try FileManager.default.removeItem(at: $0) }
        } catch {
            if !saved, FileManager.default.fileExists(atPath: destination.path) {
                try? remove(updated.id) { try FileManager.default.removeItem(at: $0) }
            }
            throw error
        }
        return updated
    }

    func replaceCover(_ data: Data, for book: Book) throws {
        try validate()
        let url = file(book.id)
        try checkLocation(url)
        let epub = try EPUB(url); defer { epub.clean() }
        try epub.replaceCover(data)
        try prepareMetadata(book.id)
        try epub.save(epub.book(id: book.id), to: url)
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
                if let data = try? epub.cover() {
                    try prepareMetadata(id)
                    try data.write(to: cover(id), options: .atomic)
                }
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
        let files = [book, cover(id)]
            .filter { manager.fileExists(atPath: $0.path) }
        for url in files { try checkLocation(url) }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        for url in files { try trash(url) }
        for parent in [book.deletingLastPathComponent(), cover(id).deletingLastPathComponent()] {
            var directory = parent
            while directory.resolvingSymlinksInPath().standardizedFileURL != base,
                  manager.fileExists(atPath: directory.path) {
                try checkLocation(directory)
                let remaining = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                guard remaining.allSatisfy({ $0.lastPathComponent == ".DS_Store" }) else { break }
                try trash(directory)
                directory.deleteLastPathComponent()
            }
        }
    }
}
