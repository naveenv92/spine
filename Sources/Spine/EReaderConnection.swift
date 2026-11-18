import Foundation
import Combine

enum EReaderFilter: String, CaseIterable {
    case all = "All Books"
    case onReader = "On E-Reader"
    case notOnReader = "Not on E-Reader"
}

@MainActor final class EReaderConnection: ObservableObject {
    @Published private(set) var settings: EReaderSettings?
    @Published private(set) var paths: Set<String> = []
    @Published private(set) var checkedAt: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var error: String?
    private var requestID = UUID()

    func disconnect() {
        requestID = UUID()
        settings = nil
        paths = []
        checkedAt = nil
        isRefreshing = false
        error = nil
    }

    func invalidate(ifChanged current: EReaderSettings) {
        if let settings, settings != current { disconnect() }
    }

    func contains(_ book: Book) -> Bool {
        guard checkedAt != nil, let settings else { return false }
        return paths.contains(EReaderTransfer.pathKey(EReaderTransfer(settings: settings).destination(for: book)))
    }

    func filter(_ books: [Book], by filter: EReaderFilter) -> [Book] {
        guard checkedAt != nil, filter != .all else { return books }
        return books.filter { contains($0) == (filter == .onReader) }
    }

    func refresh(_ settings: EReaderSettings, inventory: @escaping @Sendable (EReaderSettings) async throws -> Set<String> = { settings in
        try await Task.detached(priority: .userInitiated) { try EReaderTransfer(settings: settings).inventory() }.value
    }) async {
        if self.settings != settings { disconnect() }
        let request = UUID()
        requestID = request
        self.settings = settings
        isRefreshing = true
        error = nil
        do {
            try settings.validate()
            let paths = try await inventory(settings)
            guard requestID == request else { return }
            self.paths = Set(paths.map(EReaderTransfer.pathKey))
            checkedAt = Date()
            isRefreshing = false
        } catch {
            guard requestID == request else { return }
            disconnect()
            self.error = error.localizedDescription
        }
    }
}
