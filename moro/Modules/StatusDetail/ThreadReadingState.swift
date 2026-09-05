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
}

/// Builds a cycle-safe forest once, then computes visibility and reply counts in linear time.
/// Filtering never changes the server thread or the original ordering.
struct ThreadReadingProjection {
    let rows: [ThreadReadingRow]

    init(items: [ThreadItem], authorID: String, state: ThreadReadingState) {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        let byID = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0) })
        let eligible = Set(unique.filter { !state.authorOnly || $0.status.account.id == authorID }.map(\.id))
        var children: [String: [String]] = [:]
        for item in unique {
            if let parent = item.status.inReplyToID, parent != item.id {
                children[parent, default: []].append(item.id)
            }
        }
        let roots = unique.filter { item in
            item.status.inReplyToID.flatMap { byID[$0] } == nil || item.status.inReplyToID == item.id
        }.map(\.id)
        var visited = Set<String>()
        var visible = Set<String>()
        var traversal: [String] = []
        var forestChildren: [String: [String]] = [:]
        // A second pass preserves disconnected or malformed cyclic replies.
        for root in roots + unique.map(\.id) {
            guard !visited.contains(root) else { continue }
            var stack: [(id: String, parent: String?, hidden: Bool)] = [(root, nil, false)]
            while let node = stack.popLast() {
                guard visited.insert(node.id).inserted else { continue }
                traversal.append(node.id)
                if let parent = node.parent { forestChildren[parent, default: []].append(node.id) }
                if !node.hidden, eligible.contains(node.id) { visible.insert(node.id) }
                let hidesChildren = node.hidden || state.collapsedIDs.contains(node.id)
                for child in (children[node.id] ?? []).reversed() {
                    stack.append((child, node.id, hidesChildren))
                }
            }
        }
        var counts: [String: Int] = [:]
        for id in traversal.reversed() {
            counts[id] = (forestChildren[id] ?? []).reduce(0) {
                $0 + (eligible.contains($1) ? 1 : 0) + (counts[$1] ?? 0)
            }
        }
        rows = unique.filter { visible.contains($0.id) }.map {
            ThreadReadingRow(item: $0, replyCount: counts[$0.id] ?? 0)
        }
    }
}
