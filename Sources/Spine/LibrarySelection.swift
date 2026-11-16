struct LibrarySelection {
    private(set) var ids: Set<String> = []
    private(set) var activeID: String?

    mutating func select(_ id: String, extending: Bool = false) {
        if extending, ids.contains(id) {
            ids.remove(id)
            if activeID == id { activeID = ids.sorted().first }
        } else {
            if !extending { ids = [] }
            ids.insert(id)
            activeID = id
        }
    }

    mutating func move(_ offset: Int, in orderedIDs: [String]) {
        guard !orderedIDs.isEmpty else { return }
        let index = activeID.flatMap { orderedIDs.firstIndex(of: $0) }
        let next = index.map { min(max($0 + offset, 0), orderedIDs.count - 1) } ?? 0
        select(orderedIDs[next])
    }

    mutating func reconcile(with orderedIDs: [String]) {
        ids.formIntersection(orderedIDs)
        if let activeID, !ids.contains(activeID) { self.activeID = orderedIDs.first { ids.contains($0) } }
    }
}
