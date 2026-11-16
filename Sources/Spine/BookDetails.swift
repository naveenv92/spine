import SwiftUI

struct BookDetails<Cover: View>: View {
    @State var book: Book
    let cover: Cover
    let back: () -> Void
    let save: (Book) -> Bool
    let open: () -> Void
    let export: () -> Void
    @State private var original: Book?
    @State private var isEditing = false
    @State private var editingDescription = false
    @State private var confirmDiscard = false
    @State private var descriptionHeight: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            Button {
                if isEditing && original != book { confirmDiscard = true }
                else { back() }
            } label: {
                Label("Back to Library", systemImage: "arrow.left").font(.headline)
            }.controlSize(.large)
                .confirmationDialog("Discard unsaved changes?", isPresented: $confirmDiscard) {
                    Button("Discard Changes", role: .destructive, action: back)
                    Button("Keep Editing", role: .cancel) {}
                }
            GeometryReader { geometry in
                ScrollView {
                    HStack(alignment: .top, spacing: 32) {
                        VStack(spacing: 24) {
                            cover.aspectRatio(0.7, contentMode: .fit)
                            VStack(spacing: 14) {
                                metadata("Title", value: book.title, icon: "book")
                                Divider()
                                metadata("Author", value: book.author, icon: "person")
                                Divider()
                                metadata("Publisher", value: book.publisher, icon: "building.2")
                                Divider()
                                metadata("Language", value: book.language, icon: "globe")
                                Divider()
                                metadata("Tags", value: book.tags, icon: "tag")
                            }.font(.callout).padding(16)
                                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.12)) }
                        }.frame(width: min(300, geometry.size.width * 0.34))
                        VStack(alignment: .leading, spacing: 24) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(book.title).font(.system(size: 38, weight: .bold)).textSelection(.enabled)
                                Text(book.author).font(.title2).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                            if isEditing {
                                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                    field("Title", text: $book.title)
                                    field("Authors", text: $book.author)
                                    field("Publisher", text: $book.publisher)
                                    field("Language", text: $book.language)
                                    field("Tags", text: $book.tags)
                                }.textFieldStyle(.roundedBorder)
                                Text("Separate authors and tags with semicolons.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    Label(book.publisher.isEmpty ? "Unknown publisher" : book.publisher, systemImage: "building.2")
                                    Label(book.language.isEmpty ? "Unknown language" : book.language, systemImage: "globe")
                                }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                            }
                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 12) { actions }
                                VStack(alignment: .leading, spacing: 12) { actions }
                            }.controlSize(.large)
                            Divider().padding(.vertical, 4)
                            Text("Description").font(.title2.bold())
                            if isEditing {
                                Toggle("Edit HTML source", isOn: $editingDescription)
                            }
                            if isEditing && editingDescription {
                                TextEditor(text: $book.description).font(.body.monospaced()).frame(height: 360)
                                    .accessibilityLabel("Description HTML")
                            } else if book.description.isEmpty {
                                Text("No description available.").foregroundStyle(.secondary)
                            } else {
                                DescriptionView(html: book.description, height: $descriptionHeight).frame(height: descriptionHeight)
                                    .accessibilityLabel("Book description")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.bottom, 24)
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        if isEditing {
            Button("Save Changes") {
                if save(book) { isEditing = false; editingDescription = false; original = nil }
            }.buttonStyle(.borderedProminent).keyboardShortcut("s")
            Button("Cancel") {
                if let original { book = original }
                isEditing = false; editingDescription = false; original = nil
            }
        } else {
            Button {
                original = book; isEditing = true
            } label: { Label("Edit Metadata", systemImage: "pencil") }
                .buttonStyle(.borderedProminent)
        }
        Button(action: open) { Label("Open Book", systemImage: "book") }
        Button(action: export) { Label("Export", systemImage: "square.and.arrow.up") }
    }

    private func metadata(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value.isEmpty ? "—" : value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            TextField(title, text: text).labelsHidden().accessibilityLabel(title)
        }
    }
}
