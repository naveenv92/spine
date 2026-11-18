import SwiftUI

struct EReaderSettingsFields: View {
    @Binding var settings: EReaderSettings
    var body: some View {
        Form {
            TextField("Host", text: $settings.host, prompt: Text("Hostname or IPv4 address"))
            TextField("Port", text: $settings.port, prompt: Text("SSH port"))
            TextField("User", text: $settings.user)
            TextField("Destination", text: $settings.destination)
        }.textFieldStyle(.roundedBorder)
    }
}

struct EReaderSettingsView: View {
    @State private var settings = EReaderSettings.load()
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("E-Reader Settings").font(Typography.heading(24))
            EReaderSettingsFields(settings: $settings)
            Text("Uses your Mac’s SSH configuration and agent. Enable the reader’s SSH server before sending.")
                .foregroundStyle(.secondary)
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Spacer()
                Button("Cancel") { NSApp.keyWindow?.close() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    do { try settings.validate(); settings.save(); NSApp.keyWindow?.close() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.font(Typography.ui()).padding(24).frame(width: 460)
            .onAppear { settings = EReaderSettings.load(); error = nil }
    }
}

struct EReaderSendView: View {
    let books: [Book]
    let library: LibraryStore
    var onComplete: (EReaderSettings) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var settings = EReaderSettings.load()
    @State private var phase = Phase.ready
    @State private var items: [EReaderItem] = []
    @State private var conflicts: [EReaderItem] = []
    @State private var completed = 0
    @State private var sent = 0
    @State private var status = ""
    @State private var failures: [String] = []
    @State private var error: String?
    private enum Phase { case ready, checking, conflicts, sending, finished }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Send to E-Reader").font(Typography.heading(24))
            if phase == .ready {
                Text("Send \(books.count) \(books.count == 1 ? "book" : "books") in author folders.")
                EReaderSettingsFields(settings: $settings)
                Text("Only EPUB files are sent. Uses passwordless SSH and your existing trusted host keys. If connection fails, verify the same connection in Terminal first.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error { Text(error).foregroundStyle(.red).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Send", action: check).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            } else if phase == .conflicts {
                Text(conflicts.count == 1 ? "This book already exists on the reader:" : "These \(conflicts.count) books already exist on the reader:")
                ScrollView {
                    Text(conflicts.map(\.destination).joined(separator: "\n"))
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: min(200, max(80, CGFloat(conflicts.count) * 44)))
                Text("Replacing them cannot be undone in Spine. Other books on the reader stay in place.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Replace Existing & Send", role: .destructive) { send() }.buttonStyle(.borderedProminent)
                }
            } else if phase == .finished {
                Text("Sent \(sent) of \(items.count) books.").font(Typography.ui(17, weight: 600))
                if !failures.isEmpty {
                    ScrollView {
                        Text(failures.joined(separator: "\n\n")).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 240)
                }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            } else {
                if phase == .sending {
                    ProgressView(value: Double(completed), total: Double(max(items.count, 1)))
                    Text("\(completed) of \(items.count) books processed").monospacedDigit()
                } else { ProgressView().controlSize(.small) }
                Text(status).foregroundStyle(.secondary).lineLimit(2)
            }
        }.font(Typography.ui()).padding(24).frame(width: 520).fixedSize(horizontal: false, vertical: true)
            .interactiveDismissDisabled(phase != .ready && phase != .finished && phase != .conflicts)
    }

    private func check() {
        do {
            try settings.validate()
            settings.save()
            let transfer = EReaderTransfer(settings: settings)
            items = try transfer.items(for: books, library: library)
            error = nil
            phase = .checking
            status = "Connecting and checking destination files…"
            Task { @MainActor in
                do {
                    let snapshot = items
                    conflicts = try await Task.detached { try transfer.conflicts(in: snapshot) }.value
                    if conflicts.isEmpty { send() } else { phase = .conflicts }
                } catch { self.error = error.localizedDescription; phase = .ready }
            }
        } catch { self.error = error.localizedDescription }
    }

    private func send() {
        let transfer = EReaderTransfer(settings: settings)
        let approved = Set(conflicts.map(\.destination))
        phase = .sending
        Task { @MainActor in
            for item in items {
                status = item.source.lastPathComponent
                let replacing = approved.contains(item.destination)
                let result = await Task.detached { Result { try transfer.send(item, replacing: replacing) } }.value
                switch result {
                case .success: sent += 1
                case .failure(let error): failures.append("\(item.source.lastPathComponent): \(error.localizedDescription)")
                }
                completed += 1
                assert(sent <= completed && completed <= items.count)
            }
            phase = .finished
            onComplete(settings)
        }
    }
}
