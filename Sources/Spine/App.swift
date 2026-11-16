import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM launches a bare executable, so opt into normal Mac app activation.
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main struct SpineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { LibraryView() }.defaultSize(width: 1280, height: 850) }
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
