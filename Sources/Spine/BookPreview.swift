import SwiftUI

struct BookPreview: View {
    let book: Book
    let coverURL: URL
    let read: () -> Void
    let details: () -> Void
    let close: () -> Void
    @State private var descriptionHeight: CGFloat = 1

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Book Preview").font(.headline)
                Spacer()
                Button("Close", action: close).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let cover = NSImage(contentsOf: coverURL) {
                        Image(nsImage: cover).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 260)
                    }
                    Text(book.title).font(.title.bold())
                    Text(book.author).font(.title3).foregroundStyle(.secondary)
                    DescriptionView(html: book.description, height: $descriptionHeight).frame(height: descriptionHeight)
                }
            }
            HStack {
                Button("View Details", action: details).keyboardShortcut("i")
                Button("Read", action: read).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.controlSize(.large)
        }.padding(24).frame(width: 560, height: 650)
            .onKeyPress(.space) { close(); return .handled }
    }
}
