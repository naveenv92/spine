import SwiftUI

struct ArtworkEditor: View {
    let data: Data
    let save: () throws -> Void
    let cancel: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Replace Cover Artwork").font(.title2.bold())
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("New cover preview")
            }
            Text("This image will replace the cover inside the EPUB. A backup of the current book will be kept.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save Artwork") {
                    do { try save() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.controlSize(.large)
        }.padding(24).frame(width: 440, height: 560)
            .alert("Unable to replace cover", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
