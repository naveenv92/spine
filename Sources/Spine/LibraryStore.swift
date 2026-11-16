import Foundation

struct LibraryStore {
    let root: URL

    func file(_ id: String) -> URL { root.appendingPathComponent(id) }
    func cover(_ id: String) -> URL { root.appendingPathComponent(".spine").appendingPathComponent(id).deletingPathExtension().appendingPathExtension("cover") }
    func metadata(_ id: String) -> URL { root.appendingPathComponent(".spine").appendingPathComponent(id).appendingPathExtension("json") }

    private struct CachedBook: Codable {
        let book: Book
        let modified: Date
        let size: Int
        let hasCover: Bool
    }

    private func writeCache(_ book: Book, from epub: EPUB) throws {
        try prepareMetadata(book.id)
        let attributes = try file(book.id).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard let modified = attributes.contentModificationDate, let size = attributes.fileSize else { throw CocoaError(.fileReadUnknown) }
        let artwork = try? epub.cover()
        if let artwork { try artwork.write(to: cover(book.id), options: .atomic) }
        else if FileManager.default.fileExists(atPath: cover(book.id).path) { try FileManager.default.removeItem(at: cover(book.id)) }
        let cached = CachedBook(book: try epub.book(id: book.id), modified: modified, size: size, hasCover: artwork != nil)
        try JSONEncoder().encode(cached).write(to: metadata(book.id), options: .atomic)
    }

    private func prepareMetadata(_ id: String) throws {
        try checkLocation(cover(id))
        try checkLocation(metadata(id))
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

    static func bookName(_ text: String, fallback: String) -> String {
        var name = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
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
        let title = Self.bookName(book.title, fallback: "untitled")
        let authorDirectory = root.appendingPathComponent(author, isDirectory: true)
        try checkLocation(authorDirectory)
        var destination = authorDirectory.appendingPathComponent(title + ".epub")
        var number = 2
        while [destination, cover(id(for: destination))].contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            destination = authorDirectory.appendingPathComponent("\(title)-\(number).epub")
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
        try? writeCache(book, from: epub)
        return book
    }

    func save(_ book: Book) throws -> Book {
        try validate()
        let source = file(book.id)
        try checkLocation(source)
        let epub = try EPUB(source); defer { epub.clean() }
        let original = try epub.book(id: book.id)
        let authorChanged = Self.authorFolder(original.author) != Self.authorFolder(book.author)
        let titleChanged = Self.bookName(original.title, fallback: "untitled") != Self.bookName(book.title, fallback: "untitled")
        guard authorChanged || titleChanged else {
            try prepareMetadata(book.id)
            try epub.save(book, to: source)
            try? writeCache(book, from: epub)
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
            try? writeCache(updated, from: epub)
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
        try? writeCache(epub.book(id: book.id), from: epub)
    }

    static func epubFiles(in selections: [URL], excluding library: URL? = nil) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        let excluded = library?.resolvingSymlinksInPath().standardizedFileURL.path
        var result = Set<URL>()
        func isExcluded(_ url: URL) -> Bool {
            guard let excluded else { return false }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            return path == excluded || path.hasPrefix(excluded == "/" ? "/" : excluded + "/")
        }
        func add(_ url: URL, values: URLResourceValues) {
            if values.isSymbolicLink != true, values.isRegularFile == true, url.pathExtension.lowercased() == "epub" {
                result.insert(url.resolvingSymlinksInPath().standardizedFileURL)
            }
        }
        for selection in selections {
            guard !isExcluded(selection) else { continue }
            let values = try selection.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { continue }
            if values.isDirectory != true { add(selection, values: values); continue }
            var scanError: Error?
            guard let files = FileManager.default.enumerator(at: selection, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles], errorHandler: { _, error in scanError = error; return false }) else {
                throw CocoaError(.fileReadUnknown)
            }
            for case let url as URL in files {
                if isExcluded(url) { files.skipDescendants(); continue }
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true { files.skipDescendants(); continue }
                add(url, values: values)
            }
            if let scanError { throw scanError }
        }
        return result.sorted { $0.path < $1.path }
    }

    func load() throws -> [Book] {
        try validate()
        var books: [Book] = []
        for url in try Self.epubFiles(in: [root]) {
            try checkLocation(url)
            let id = id(for: url)
            try checkLocation(metadata(id))
            try checkLocation(cover(id))
            let attributes = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            // shortcut: use size and modification time; add hashes if external tools preserve both.
            if let data = try? Data(contentsOf: metadata(id)),
               let cached = try? JSONDecoder().decode(CachedBook.self, from: data), cached.book.id == id,
               cached.modified == attributes.contentModificationDate, cached.size == attributes.fileSize,
               !cached.hasCover || FileManager.default.fileExists(atPath: cover(id).path) {
                books.append(cached.book)
                continue
            }
            guard let epub = try? EPUB(url) else { continue }; defer { epub.clean() }
            if let book = try? epub.book(id: id) {
                try? writeCache(book, from: epub)
                books.append(book)
            }
        }
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
        let files = [book, cover(id), metadata(id)]
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
