import Foundation

struct EReaderSettings: Equatable {
    var host = ""
    var port = ""
    var user = "root"
    var destination = "/mnt/us/books/"

    static func load() -> Self {
        let defaults = UserDefaults.standard
        return Self(host: defaults.string(forKey: "readerHost") ?? "", port: defaults.string(forKey: "readerPort") ?? "",
                    user: defaults.string(forKey: "readerUser") ?? "root", destination: defaults.string(forKey: "readerDestination") ?? "/mnt/us/books/")
    }

    func save() {
        for (key, value) in [("readerHost", host), ("readerPort", port), ("readerUser", user), ("readerDestination", destination)] {
            UserDefaults.standard.set(value, forKey: key)
        }
    }

    func validate() throws {
        let hostCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        let userCharacters = hostCharacters.union(CharacterSet(charactersIn: "_"))
        guard !host.isEmpty, !host.hasPrefix("-"), host.rangeOfCharacter(from: hostCharacters.inverted) == nil else {
            throw Self.error("Enter a hostname or IPv4 address, without a username or port.")
        }
        guard !port.isEmpty, port.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(port), (1...65535).contains(number) else {
            throw Self.error("Enter an SSH port between 1 and 65535.")
        }
        guard !user.isEmpty, !user.hasPrefix("-"), user.rangeOfCharacter(from: userCharacters.inverted) == nil else {
            throw Self.error("Enter a valid SSH username.")
        }
        guard destination.hasPrefix("/"), destination.rangeOfCharacter(from: .controlCharacters) == nil,
              !destination.split(separator: "/").contains("..") else {
            throw Self.error("Destination must be an absolute path without control characters or '..'.")
        }
    }

    static func error(_ message: String) -> NSError { NSError(domain: "EReader", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

struct EReaderItem: Equatable {
    let source: URL
    let destination: String
}

struct EReaderTransfer {
    let settings: EReaderSettings
    var run: (String, [String]) throws -> String = { try EPUB.command($0, $1) }

    static func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'" }
    private var root: String { settings.destination == "/" ? "" : "/" + settings.destination.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
    private var target: String { "\(settings.user)@\(settings.host)" }
    private var options: [String] { ["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10", "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=2"] }

    private func ssh(_ command: String) throws -> String {
        try run("/usr/bin/ssh", options + ["-p", settings.port, target, command])
    }

    func items(for books: [Book], library: LibraryStore) throws -> [EReaderItem] {
        try settings.validate()
        var destinations = Set<String>()
        return try books.map { book in
            let source = library.file(book.id)
            let base = library.root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard source.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(base),
                  attributes.isRegularFile == true, attributes.isSymbolicLink != true,
                  source.pathExtension.lowercased() == "epub" else { throw EReaderSettings.error("Book is not a regular EPUB inside the library: \(book.title)") }
            let destination = root + "/" + LibraryStore.authorFolder(book.author) + "/" + source.lastPathComponent
            guard destinations.insert(destination.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw EReaderSettings.error("Two selected books have the same destination: \(destination)") }
            return EReaderItem(source: source, destination: destination)
        }
    }

    func conflicts(in items: [EReaderItem]) throws -> [EReaderItem] {
        try settings.validate()
        _ = try ssh("true")
        return try items.filter { item in
            let path = Self.quote(item.destination)
            let parent = Self.quote((item.destination as NSString).deletingLastPathComponent)
            let status = try ssh("if test -L \(parent) || test -L \(path) || test -d \(path); then printf blocked; elif test -f \(path); then printf exists; elif test -e \(path); then printf blocked; else printf missing; fi").trimmingCharacters(in: .whitespacesAndNewlines)
            guard status == "exists" || status == "missing" else { throw EReaderSettings.error("Destination is not a regular file: \(item.destination)") }
            return status == "exists"
        }
    }

    func send(_ item: EReaderItem, replacing: Bool) throws {
        try settings.validate()
        let parent = (item.destination as NSString).deletingLastPathComponent
        let temporary = root + "/.spine-transfer-" + UUID().uuidString + ".epub"
        _ = try ssh("test ! -L \(Self.quote(parent)) && mkdir -p -- \(Self.quote(parent))")
        do {
            // macOS 14+ scp uses SFTP; keep paths literal in its argument array.
            _ = try run("/usr/bin/scp", options + ["-P", settings.port, item.source.path, target + ":" + temporary])
            let source = Self.quote(temporary)
            let destination = Self.quote(item.destination)
            let move = "test ! -L \(destination) && test ! -d \(destination) && mv \(replacing ? "-f" : "-n") -- \(source) \(destination) && test ! -e \(source)"
            _ = try ssh(move + " || { printf '%s\\n' 'Destination changed or upload could not be finalized' >&2; exit 1; }")
        } catch {
            let transferError = error
            do { _ = try ssh("rm -f -- \(Self.quote(temporary))") }
            catch { throw EReaderSettings.error("\(transferError.localizedDescription)\nCould not clean up \(temporary): \(error.localizedDescription)") }
            throw transferError
        }
    }
}

