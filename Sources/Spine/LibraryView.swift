import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @State private var books: [Book] = []
    @State private var selected: Book?
    @State private var selection = LibrarySelection()
    @State private var previewBook: Book?
    @State private var editMetadataOnOpen = false
    @State private var gridColumnCount = 1
    @FocusState private var libraryFocused: Bool
    @State private var search = ""
    @State private var sort = LibrarySort.title
    @State private var listView = false
    @State private var error: String?
    @State private var bookToRemove: Book?
    @State private var artworkData: Data?
    @State private var isImporting = false
    @State private var isLoading = false
    @State private var importTotal: Int?
    @State private var importCompleted = 0
    @State private var importStatus = ""
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
                            editMetadataOnOpen = false
                            load(selecting: saved)
                            return true
                        } catch {
                            self.error = error.localizedDescription
                            if !FileManager.default.fileExists(atPath: file(updated.id).path) { load() }
                            return false
                        }
                    }, open: { openBook(book) }, export: {
                        let panel = NSSavePanel(); panel.nameFieldStringValue = book.title + ".epub"
                        if panel.runModal() == .OK, let url = panel.url {
                            do { try FileManager.default.copyItem(at: file(book.id), to: url) }
                            catch { self.error = error.localizedDescription }
                        }
                    }, remove: { bookToRemove = book }, editArtwork: chooseArtwork, startEditing: editMetadataOnOpen).id(book.id)
                } else {
                    library
                }
            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(red: 0.045, green: 0.05, blue: 0.055))
        }
        .frame(minWidth: 850, minHeight: 580)
        .preferredColorScheme(.dark)
        .font(Typography.ui())
        .tint(accent)
        .task(id: libraryFolder) {
            selected = nil
            selection = LibrarySelection()
            books = []
            guard !libraryFolder.isEmpty else { isLoading = false; return }
            isLoading = true
            defer { if !Task.isCancelled { isLoading = false } }
            let readingStore = store
            do {
                let refreshed = try await Task.detached(priority: .userInitiated) { try readingStore.load() }.value
                guard !Task.isCancelled else { return }
                books = refreshed
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: Binding(get: { artworkData != nil }, set: { if !$0 { artworkData = nil } })) {
            if let data = artworkData, let book = selected {
                ArtworkEditor(data: data, save: {
                    try store.replaceCover(data, for: book)
                    load(selecting: book)
                    artworkData = nil
                }, cancel: { artworkData = nil })
            }
        }
        .sheet(item: $previewBook) { book in
            BookPreview(book: book, coverURL: store.cover(book.id), read: { openBook(book) }, details: {
                previewBook = nil
                showDetails(book)
            }, close: { previewBook = nil })
        }
        .sheet(isPresented: $isImporting) {
            VStack(spacing: 18) {
                Text("Importing Books").font(Typography.ui(22, weight: 600))
                if let total = importTotal {
                    ProgressView(value: Double(importCompleted), total: Double(total))
                    Text("\(importCompleted) of \(total) files processed").monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(importStatus).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }.padding(28).frame(width: 380)
                .interactiveDismissDisabled()
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
                Text("All Books").font(Typography.ui(13, weight: 600)).padding(.horizontal, 14).padding(.bottom, 14)
                    .overlay(alignment: .bottom) { Capsule().fill(accent).frame(height: 3) }
                Spacer()
                Picker("Sort by", selection: $sort) {
                    ForEach(LibrarySort.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }.frame(width: 245)
                Picker("Layout", selection: $listView) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 90)
                Button {
                    if let book = activeBook { showDetails(book) }
                } label: { Image(systemName: "info.circle") }
                    .disabled(activeBook == nil)
                    .keyboardShortcut("i")
                    .help("View Details (⌘I)")
                    .accessibilityLabel("View book details")
            }
            .overlay(alignment: .bottom) { Divider().offset(y: 1) }
            collection
                .focusable().focused($libraryFocused)
                .focusEffectDisabled()
                .onAppear { libraryFocused = true }
                .onKeyPress(.return) {
                    guard let book = activeBook else { return .ignored }
                    openBook(book); return .handled
                }
                .onKeyPress(.space) {
                    guard let book = activeBook else { return .ignored }
                    previewBook = book; return .handled
                }
                .onMoveCommand { direction in
                    let visible = Book.library(books, search: search, sort: sort)
                    let stride = listView ? 1 : gridColumnCount
                    let offset = direction == .up ? -stride : (direction == .down ? stride : (direction == .left ? -1 : 1))
                    selection.move(offset, in: visible.map(\.id))
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.size.width, initial: true) {
                            gridColumnCount = max(1, Int((geometry.size.width + 28) / (160 + 28)))
                        }
                    }
                }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            Label("Spine", systemImage: "book.pages").font(Typography.heading(22)).padding(.bottom, 12)
            Label("Library", systemImage: "book").font(Typography.ui(13, weight: 600))
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            Divider()
            Text("MY LIBRARY").font(Typography.ui(11, weight: 600)).foregroundStyle(.secondary)
            HStack {
                Label("All Books", systemImage: "books.vertical")
                Spacer()
                Text("\(books.count)").font(Typography.ui(11, weight: 700)).padding(.horizontal, 8).padding(.vertical, 4)
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
            Text("My Library").font(Typography.heading(32))
            Text("\(books.count) \(books.count == 1 ? "book" : "books") in your collection")
                .foregroundStyle(.secondary)
        }.fixedSize(horizontal: true, vertical: false)
    }

    private var importButton: some View {
        Button(action: importBooks) {
            Label("Import New Books", systemImage: "plus").font(Typography.ui(13, weight: 600)).padding(.horizontal, 10).padding(.vertical, 8)
        }.buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut("o")
            .disabled(isLoading)
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
        let visible = Book.library(books, search: search, sort: sort)
        return Group {
            if isLoading {
                ProgressView("Loading library…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if books.isEmpty {
                ContentUnavailableView {
                    Label("Your next chapter starts here", systemImage: "books.vertical")
                } description: {
                    Text("Import EPUB books to build your personal library.")
                } actions: { importButton }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                ContentUnavailableView.search(text: search).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        Group {
                            if listView {
                                LazyVStack(spacing: 12) {
                                    ForEach(visible) { book in
                                        libraryItem(book) {
                                            HStack(spacing: 20) {
                                                cover(book).frame(width: 52, height: 74)
                                                bookText(book)
                                                Spacer()
                                            }.padding(12).padding(.trailing, 44).contentShape(Rectangle())
                                                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                        }
                                    }
                                }
                            } else {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 230), spacing: 28, alignment: .top)], alignment: .leading, spacing: 28) {
                                    ForEach(visible) { book in
                                        libraryItem(book) {
                                            VStack(alignment: .leading, spacing: 12) {
                                                cover(book).aspectRatio(0.7, contentMode: .fit)
                                                bookText(book)
                                            }.contentShape(Rectangle())
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                        .background {
                            Color.clear.contentShape(Rectangle()).onTapGesture {
                                selection = LibrarySelection()
                                libraryFocused = true
                            }
                        }
                    }
                }
            }
        }
    }

    private var activeBook: Book? {
        Book.library(books, search: search, sort: sort).first { $0.id == selection.activeID }
    }

    private func selectBook(_ book: Book) {
        selection.select(book.id, extending: NSEvent.modifierFlags.contains(.command))
        libraryFocused = true
    }

    private func showDetails(_ book: Book, editing: Bool = false) {
        selection.select(book.id)
        editMetadataOnOpen = editing
        selected = book
    }

    private func openBook(_ book: Book) {
        if !NSWorkspace.shared.open(file(book.id)) {
            error = "Unable to open “\(book.title)” in the default reader."
        }
    }

    private func libraryItem<Content: View>(_ book: Book, @ViewBuilder content: () -> Content) -> some View {
        content().padding(4)
            .background(selection.ids.contains(book.id) ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selection.ids.contains(book.id) ? accent : .clear, lineWidth: 2) }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { selection.select(book.id); libraryFocused = true; openBook(book) }
            .simultaneousGesture(TapGesture().onEnded { selectBook(book) })
            .overlay(alignment: .topTrailing) {
                if selection.ids.contains(book.id) {
                    Button { showDetails(book) } label: {
                        Image(systemName: "info.circle.fill").font(.title2)
                            .padding(6).background(.regularMaterial, in: Circle())
                    }.buttonStyle(.plain).padding(8)
                        .help("View Details (⌘I)").accessibilityLabel("View details for \(book.title)")
                }
            }
            .contextMenu {
                Button("Read (Open in Default App)") { openBook(book) }
                Button("View Details…") { showDetails(book) }
                Button("Edit Metadata…") { showDetails(book, editing: true) }
                Button("Edit Cover…") { showDetails(book); chooseArtwork() }
                Divider()
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file(book.id)]) }
                Button("Remove book", role: .destructive) { bookToRemove = book }
            }
            .help("Click to select, double-click to read. Space previews; ⌘I opens details.")
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(book.title), \(book.author)")
            .accessibilityAddTraits(selection.ids.contains(book.id) ? [.isSelected] : [])
            .accessibilityAction { selectBook(book) }
            .accessibilityAction(named: "Read") { openBook(book) }
            .accessibilityAction(named: "View Details") { showDetails(book) }
    }

    private func bookText(_ book: Book) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(book.title).font(Typography.heading(13)).lineLimit(2)
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

    private func load(selecting book: Book? = nil) {
        guard !libraryFolder.isEmpty else { return }
        do {
            let refreshed = try store.load()
            books = refreshed
            selected = book
            if let book { selection.select(book.id) }
            else { selection.reconcile(with: refreshed.map(\.id)) }
        }
        catch { self.error = error.localizedDescription }
    }

    private func importBooks() {
        guard !isImporting, !isLoading else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [UTType(filenameExtension: "epub")!]
        panel.title = "Import EPUB Files or Folders"
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        let selections = panel.urls
        let importStore = store
        importTotal = nil
        importCompleted = 0
        importStatus = "Finding EPUB files…"
        isImporting = true
        Task { @MainActor in
            defer { isImporting = false }
            do {
                let files = try await Task.detached(priority: .userInitiated) {
                    try LibraryStore.epubFiles(in: selections, excluding: importStore.root)
                }.value
                guard !files.isEmpty else {
                    error = "No EPUB files found outside the current library."
                    return
                }
                importTotal = files.count
                var failures: [String] = []
                for url in files {
                    importStatus = url.lastPathComponent
                    let result = await Task.detached(priority: .userInitiated) {
                        Result { try importStore.importBook(url) }
                    }.value
                    if case .failure(let error) = result {
                        failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                    importCompleted += 1
                    assert(importCompleted <= files.count)
                }
                importTotal = nil
                importStatus = "Refreshing library…"
                let refreshed = try await Task.detached(priority: .userInitiated) {
                    try importStore.load()
                }.value
                books = refreshed
                selected = nil
                if !failures.isEmpty { error = "Some books could not be imported:\n" + failures.joined(separator: "\n") }
            } catch {
                self.error = error.localizedDescription
            }
        }
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

enum LibrarySort: String, CaseIterable {
    case title = "Title"
    case mostRecent = "Most Recent"
    case authorFirstName = "Author First Name"
    case authorLastName = "Author Last Name"

    func key(for book: Book) -> String {
        guard self != .title && self != .mostRecent else { return book.title }
        let author = book.author.components(separatedBy: ";")
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let commaParts = author.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if commaParts.count == 2 {
            return self == .authorFirstName ? commaParts[1] + " " + commaParts[0] : commaParts[0] + " " + commaParts[1]
        }
        let words = author.split(whereSeparator: \.isWhitespace)
        if self == .authorLastName, let last = words.last {
            return ([String(last)] + words.dropLast().map(String.init)).joined(separator: " ")
        }
        return words.joined(separator: " ")
    }
}

extension Book {
    static func library(_ books: [Book], search: String, sort: LibrarySort) -> [Book] {
        books.filter { search.isEmpty || ($0.title + " " + $0.author).localizedCaseInsensitiveContains(search) }
            .sorted {
                if sort == .mostRecent {
                    let left = $0.addedAt ?? .distantPast
                    let right = $1.addedAt ?? .distantPast
                    if left != right { return left > right }
                }
                let comparison = sort.key(for: $0).localizedStandardCompare(sort.key(for: $1))
                if comparison != .orderedSame { return comparison == .orderedAscending }
                let titleComparison = $0.title.localizedStandardCompare($1.title)
                return titleComparison == .orderedSame ? $0.id < $1.id : titleComparison == .orderedAscending
            }
    }
}
