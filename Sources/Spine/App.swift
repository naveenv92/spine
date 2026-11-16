import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM launches a bare executable, so opt into normal Mac app activation.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main struct SpineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { LibraryView() }.defaultSize(width: 1000, height: 720) }
}
struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var selected: Book?
    @State private var search = ""
    @State private var error: String?
    // Keep the original library location so existing imports remain available.
    private let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MinimalBooks")
    private func file(_ id: String) -> URL { root.appendingPathComponent(id + ".epub") }
    var body: some View {
        NavigationSplitView {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 24) {
                    ForEach(books.filter { search.isEmpty || ($0.title + $0.author).localizedCaseInsensitiveContains(search) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) { book in
                        Button { selected = book } label: {
                            VStack {
                                if let image = NSImage(contentsOf: root.appendingPathComponent(book.id + ".cover")) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(height: 165)
                                } else { Image(systemName: "book.closed").font(.system(size: 70)).frame(height: 165) }
                                Text(book.title).lineLimit(2)
                                Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }.frame(maxWidth: .infinity)
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }.searchable(text: $search).navigationTitle("Spine")
            .toolbar { Button("Import", systemImage: "plus") { importBooks() } }
        } detail: {
            if let book = selected {
                Editor(book: book, save: { updated in
                    do {
                        let epub = try EPUB(file(updated.id)); defer { epub.clean() }
                        try epub.save(updated, to: file(updated.id)); load(); selected = updated
                        return true
                    } catch { self.error = error.localizedDescription; return false }
                }, open: { NSWorkspace.shared.open(file(book.id)) }, export: {
                    let panel = NSSavePanel(); panel.nameFieldStringValue = book.title + ".epub"
                    if panel.runModal() == .OK, let url = panel.url {
                        do { try FileManager.default.copyItem(at: file(book.id), to: url) } catch { self.error = error.localizedDescription }
                    }
                }).id(book.id)
            } else { ContentUnavailableView("Your EPUB library", systemImage: "books.vertical", description: Text("Import books to get started.")) }
        }.task { load() }
        .alert("Unable to complete action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
    private func load() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            books = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }.compactMap { url in
                guard let epub = try? EPUB(url) else { return nil }; defer { epub.clean() }
                let id = url.deletingPathExtension().lastPathComponent
                if let cover = try? epub.cover() { try? cover.write(to: root.appendingPathComponent(id + ".cover")) }
                return try? epub.book(id: id)
            }
        } catch { self.error = error.localizedDescription }
    }
    private func importBooks() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [UTType(filenameExtension: "epub")!]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                let epub = try EPUB(url); defer { epub.clean() }; _ = try epub.book(id: "")
                try FileManager.default.copyItem(at: url, to: file(UUID().uuidString))
            } catch { self.error = error.localizedDescription }
        }
        load()
    }
}
struct Editor: View {
    @State var book: Book
    @State private var editingDescription = false
    @State private var original: Book?
    @State private var isEditing = false
    let save: (Book) -> Bool
    let open: () -> Void
    let export: () -> Void
    var body: some View {
        Form {
            if isEditing {
            TextField("Title", text: $book.title)
            TextField("Authors (semicolon separated)", text: $book.author)
            TextField("Publisher", text: $book.publisher)
            TextField("Language", text: $book.language)
            TextField("Tags (semicolon separated)", text: $book.tags)
            } else {
                LabeledContent("Title", value: book.title)
                LabeledContent("Authors", value: book.author)
                LabeledContent("Publisher", value: book.publisher)
                LabeledContent("Language", value: book.language)
                LabeledContent("Tags", value: book.tags)
            }
            Section("Description") {
                if isEditing { Toggle("Edit HTML source", isOn: $editingDescription) }
                if isEditing && editingDescription {
                    TextField("Description HTML", text: $book.description, axis: .vertical).lineLimit(5...12)
                } else {
                    DescriptionView(html: book.description).frame(height: 220)
                        .accessibilityLabel("Book description")
                }
            }
            HStack {
                if isEditing {
                    Button("Save") {
                        if save(book) { isEditing = false; editingDescription = false; original = nil }
                    }.keyboardShortcut("s")
                    Button("Cancel") {
                        if let original { book = original }
                        isEditing = false; editingDescription = false; original = nil
                    }.keyboardShortcut(.cancelAction)
                } else {
                    Button("Edit") { original = book; isEditing = true }
                }
                Button("Open", action: open)
                Button("Export", action: export)
            }
        }.formStyle(.grouped).padding()
    }
}
