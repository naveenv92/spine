import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var selected: Book?
    @State private var search = ""
    @State private var sortByAuthor = false
    @State private var listView = false
    @State private var error: String?
    @State private var bookToRemove: Book?
    @State private var artworkData: Data?
    private let accent = Color(red: 0.48, green: 0.37, blue: 0.92)
    @AppStorage("libraryFolder") private var libraryFolder = ""
    private var store: LibraryStore { LibraryStore(root: URL(fileURLWithPath: libraryFolder, isDirectory: true)) }
    private let previousLibrary = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Spine")
    private func file(_ id: String) -> URL { store.file(id) }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            Group {
                if libraryFolder.isEmpty {
                    setup
                } else if let book = selected {
                    BookDetails(book: book, cover: cover(book), back: { selected = nil }, save: { updated in
                        do {
                            let saved = try store.save(updated)
                            load(); selected = saved
                            return true
                        } catch {
                            self.error = error.localizedDescription
                            if !FileManager.default.fileExists(atPath: file(updated.id).path) { load() }
                            return false
                        }
                    }, open: { NSWorkspace.shared.open(file(book.id)) }, export: {
                        let panel = NSSavePanel(); panel.nameFieldStringValue = book.title + ".epub"
                        if panel.runModal() == .OK, let url = panel.url {
                            do { try FileManager.default.copyItem(at: file(book.id), to: url) }
                            catch { self.error = error.localizedDescription }
                        }
                    }, remove: { bookToRemove = book }, editArtwork: chooseArtwork).id(book.id)
                } else {
                    library
                }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.045, green: 0.05, blue: 0.055))
        }
        .frame(minWidth: 850, minHeight: 580)
        .preferredColorScheme(.dark)
        .tint(accent)
        .onChange(of: libraryFolder, initial: true) { load() }
        .sheet(isPresented: Binding(get: { artworkData != nil }, set: { if !$0 { artworkData = nil } })) {
            if let data = artworkData, let book = selected {
                ArtworkEditor(data: data, save: {
                    try store.replaceCover(data, for: book)
                    load(); selected = book
                    artworkData = nil
                }, cancel: { artworkData = nil })
            }
        }
        .alert("Unable to complete action", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } }
        )) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .confirmationDialog("Remove book from library?", isPresented: Binding(
            get: { bookToRemove != nil }, set: { if !$0 { bookToRemove = nil } }
        ), titleVisibility: .visible, presenting: bookToRemove) { book in
            Button("Move to Trash", role: .destructive) {
                do { try store.remove(book.id) }
                catch { self.error = error.localizedDescription }
                bookToRemove = nil
                load()
            }
            Button("Cancel", role: .cancel) { bookToRemove = nil }
        } message: { book in
            Text("“\(book.title)” and its library files will be moved to Trash. You can restore them from Trash.")
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            HStack {
                Text("All Books").font(.headline).padding(.horizontal, 14).padding(.bottom, 14)
                    .overlay(alignment: .bottom) { Capsule().fill(accent).frame(height: 3) }
                Spacer()
                Picker("Sort by", selection: $sortByAuthor) {
                    Text("Title").tag(false)
                    Text("Author").tag(true)
                }.frame(width: 160)
                Picker("Layout", selection: $listView) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
            }
            .overlay(alignment: .bottom) { Divider().offset(y: 1) }
            collection
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            Label("Spine", systemImage: "book.pages").font(.title2.bold()).padding(.bottom, 12)
            Label("Library", systemImage: "book").font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            Divider()
            Text("MY LIBRARY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                Label("All Books", systemImage: "books.vertical")
                Spacer()
                Text("\(books.count)").font(.caption.bold()).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            Spacer()
            if !libraryFolder.isEmpty {
                Button(action: chooseLibrary) {
                    Label("Library Folder…", systemImage: "folder")
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(libraryFolder)
                    .disabled(selected != nil)
            }
        }.padding(20).frame(width: 190).frame(maxHeight: .infinity)
            .background(Color(red: 0.065, green: 0.07, blue: 0.075))
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 24) {
                heading
                Spacer(minLength: 10)
                importButton
                searchField.frame(width: 230)
            }
            VStack(alignment: .leading, spacing: 20) {
                heading
                HStack(spacing: 20) { importButton; searchField }
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("My Library").font(.system(size: 32, weight: .bold))
            Text("\(books.count) \(books.count == 1 ? "book" : "books") in your collection")
                .foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var importButton: some View {
        Button(action: importBooks) {
            Label("Import New Books", systemImage: "plus").font(.headline).padding(.horizontal, 10).padding(.vertical, 8)
        }.buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut("o")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search library…", text: $search).textFieldStyle(.plain)
                .accessibilityLabel("Search library")
        }.padding(12).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)) }
    }

    private var collection: some View {
        let visible = Book.library(books, search: search, sortByAuthor: sortByAuthor)
        return Group {
            if books.isEmpty {
                ContentUnavailableView {
                    Label("Your next chapter starts here", systemImage: "books.vertical")
                } description: {
                    Text("Import EPUB books to build your personal library.")
                } actions: { importButton }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: search).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    if listView {
                        LazyVStack(spacing: 12) {
                            ForEach(visible) { book in
                                Button { selected = book } label: {
                                    HStack(spacing: 20) {
                                        cover(book).frame(width: 52, height: 74)
                                        bookText(book)
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }.padding(12).contentShape(Rectangle())
                                        .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                                    .contextMenu { Button("Remove book", role: .destructive) { bookToRemove = book } }
                            }
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 28, alignment: .top)], alignment: .leading, spacing: 28) {
                            ForEach(visible) { book in
                                Button { selected = book } label: {
                                    VStack(alignment: .leading, spacing: 12) {
                                        cover(book).aspectRatio(0.7, contentMode: .fit)
                                        bookText(book)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                    .contextMenu { Button("Remove book", role: .destructive) { bookToRemove = book } }
                            }
                        }
                    }
                }
            }
        }
    }

    private func bookText(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(book.title).font(.headline).lineLimit(2)
            Text(book.author).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
    }

    private func cover(_ book: Book) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
            if let image = NSImage(contentsOf: store.cover(book.id)) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "book.closed").font(.system(size: 38)).foregroundStyle(accent)
                    .accessibilityLabel("No cover available")
            }
        }.clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14)) }
    }

    private var setup: some View {
        ContentUnavailableView {
            Label("Choose your library folder", systemImage: "folder.badge.plus")
        } description: {
            Text("Spine copies imported books into this folder, organized by author and title. Your original files stay where they are.")
        } actions: {
            Button(action: chooseLibrary) {
                Text("Choose Library Folder…").frame(width: 180)
            }.buttonStyle(.borderedProminent).controlSize(.large)
            if FileManager.default.fileExists(atPath: previousLibrary.path) {
                Button {
                    setLibrary(previousLibrary)
                } label: {
                    Text("Use Previous Library").frame(width: 180)
                }.buttonStyle(.bordered).controlSize(.large)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "Choose Your Library Folder"
        panel.prompt = "Use Library Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = libraryFolder.isEmpty ? nil : store.root
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setLibrary(url)
    }

    private func setLibrary(_ url: URL) {
        do {
            try LibraryStore(root: url).validate()
            let path = url.standardizedFileURL.path
            if libraryFolder == path { load() }
            else { libraryFolder = path }
        } catch { self.error = error.localizedDescription }
    }

    private func load() {
        selected = nil
        books = []
        guard !libraryFolder.isEmpty else { return }
        do { books = try store.load() }
        catch { self.error = error.localizedDescription }
    }

    private func importBooks() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [UTType(filenameExtension: "epub")!]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do { try store.importBook(url) }
            catch { self.error = error.localizedDescription }
        }
        load()
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.title = "Choose Cover Artwork"
        panel.allowedContentTypes = [.png, .jpeg]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            _ = try EPUB.coverImage(data)
            artworkData = data
        } catch { self.error = error.localizedDescription }
    }
}

extension Book {
    static func library(_ books: [Book], search: String, sortByAuthor: Bool) -> [Book] {
        books.filter { search.isEmpty || ($0.title + " " + $0.author).localizedCaseInsensitiveContains(search) }
            .sorted {
                let left = sortByAuthor ? $0.author : $0.title
                let right = sortByAuthor ? $1.author : $1.title
                if left == right { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                return left.localizedStandardCompare(right) == .orderedAscending
            }
    }
}
