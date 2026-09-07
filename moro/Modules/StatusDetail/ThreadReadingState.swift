import Foundation

struct ThreadReadingState {
    private(set) var authorOnly = false
    private(set) var collapsedIDs = Set<String>()

    mutating func setAuthorOnly(_ value: Bool) {
        authorOnly = value
        collapsedIDs.removeAll()
    }

    mutating func toggleBranch(_ id: String) {
        if !collapsedIDs.insert(id).inserted { collapsedIDs.remove(id) }
    }

    mutating func expandAll() { collapsedIDs.removeAll() }
}

struct ThreadReadingRow: Identifiable {
    let item: ThreadItem
    let replyCount: Int
    var id: String { item.id }
    var isNestedReply: Bool { item.replyGroupRootID.map { $0 != id } ?? false }

    func showsBranchControl(isCollapsed: Bool) -> Bool {
        // Keep hidden replies reachable if a refresh reduces an already collapsed branch.
        replyCount >= 3 || (isCollapsed && replyCount > 0)
    }
}

/// The conversation model owns ordering and branch membership. Reading controls only
/// filter those rows; each independent discussion has a single collapse boundary.
struct ThreadReadingProjection {
    let rows: [ThreadReadingRow]

    init(items: [ThreadItem], authorID: String, state: ThreadReadingState) {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        let eligible = unique.filter { !state.authorOnly || $0.status.account.id == authorID }
        var counts: [String: Int] = [:]
        for item in eligible {
            if let branchID = item.replyBranchID, branchID != item.id {
                counts[branchID, default: 0] += 1
            }
        }
        rows = eligible.compactMap { item in
            if let branchID = item.replyBranchID, branchID != item.id,
                state.collapsedIDs.contains(branchID) { return nil }
            return ThreadReadingRow(item: item, replyCount: counts[item.id] ?? 0)
        }
    }
}
