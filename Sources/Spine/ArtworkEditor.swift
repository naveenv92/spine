import SwiftUI

struct ArtworkEditor: View {
    let data: Data
    let save: () throws -> Void
    let cancel: () -> Void
    @State private var error: String?
    @State private var confirmSave = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Replace Cover Artwork").font(Typography.ui(22, weight: 600))
            if let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("New cover preview")
            }
            Text("This image will replace the cover inside the EPUB. No backup will be kept.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save Artwork") { confirmSave = true }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .confirmationDialog("Replace cover artwork?", isPresented: $confirmSave, titleVisibility: .visible) {
                        Button("Save Artwork", role: .destructive) {
                            do { try save() }
                            catch { self.error = error.localizedDescription }
                        }
                        Button("Keep Previewing", role: .cancel) {}
                    } message: {
                        Text("The current cover will be replaced without a backup. This cannot be undone in Spine.")
                    }
            }.controlSize(.large)
        }.font(Typography.ui()).padding(24).frame(width: 440, height: 560)
            .alert("Unable to replace cover", isPresented: Binding(
                get: { error != nil }, set: { if !$0 { error = nil } }
            )) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
