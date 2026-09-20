import Foundation

/// The transport result retains completeness; a regenerating (206) home feed is
/// usable content, but must never close a gap or advance a verified checkpoint.
struct TimelinePage {
    let statuses: [Status]
    var isPartial = false
    var nextMaxID: String?
}

struct TimelineGap: Codable, Equatable, Identifiable {
    var id = UUID()
    var afterID: String
    var beforeID: String
    var maxID: String
    let sinceID: String
    let targetHeadID: String
    let sequence: UInt64
}

struct TimelineReadingAnchor: Codable, Equatable {
    let statusID: String
    let viewportOffset: Double
}

struct TimelineLiveMetadata: Codable {
    var version = 1
    var checkpointID: String?
    var fetchedHeadID: String?
    var gaps: [TimelineGap] = []
    var newIDs: [String: UInt64] = [:]
    var sequence: UInt64 = 0
    var acknowledgedSequence: UInt64 = 0
    var overflowSequence: UInt64?
    var readingAnchor: TimelineReadingAnchor?
}

/// Value-state shared by every home-page source. Receiving content does not
/// publish a SwiftUI array; the page applies a snapshot when it can preserve its
/// reading position. All IDs are local-server status IDs, including boost rows.
struct TimelineLiveUpdates {
    private(set) var statuses: [Status]
    private(set) var metadata: TimelineLiveMetadata
    private var deletedIDs: Set<String> = []
    private var deletedOrder: [String] = []
    private var deletedBoundaryReplacements: [String: String] = [:]

    init(statuses: [Status], metadata: TimelineLiveMetadata? = nil) {
        self.statuses = Self.unique(statuses)
        self.metadata = metadata?.version == 1 ? metadata! : TimelineLiveMetadata(
            checkpointID: statuses.first?.id, fetchedHeadID: statuses.first?.id)
        let ids = Set(self.statuses.map(\.id))
        self.metadata.newIDs = self.metadata.newIDs.filter { ids.contains($0.key) }
        self.metadata.gaps.removeAll { !ids.contains($0.afterID) || !ids.contains($0.beforeID) }
    }

    var newCount: Int { metadata.newIDs.count }
    var hasMoreNew: Bool {
        metadata.gaps.contains { $0.sequence > metadata.acknowledgedSequence }
            || (metadata.overflowSequence.map { $0 > metadata.acknowledgedSequence } ?? false)
    }

    mutating func receive(_ status: Status, currentAccountID: String?) {
        guard !isDeleted(status) else { return }
        if statuses.contains(where: { $0.id == status.id }) {
            update(status)
            return
        }
        statuses.insert(status, at: 0)
        recordNew(status, currentAccountID: currentAccountID)
    }

    /// Page order determines where new rows go. Existing stream/local rows are
    /// retained between overlapping server rows rather than sorted by created_at.
    @discardableResult
    mutating func receiveHead(
        _ page: TimelinePage, sinceID: String?, currentAccountID: String?
    ) -> Int {
        let baselineRow = sinceID.flatMap { baseline in
            statuses.contains { $0.id == baseline } ? baseline : deletedBoundaryReplacements[baseline]
        }
        let previousHead = baselineRow ?? statuses.first?.id
        let pageStatuses = Self.unique(page.statuses.filter { !isDeleted($0) })
        let inserted = merge(pageStatuses, before: previousHead, currentAccountID: currentAccountID)
        guard let newest = page.statuses.first?.id else { return inserted }

        if !page.isPartial { metadata.fetchedHeadID = newest }
        if let baseline = sinceID, baseline != newest,
            !page.statuses.contains(where: { $0.id == baseline }),
            let oldest = pageStatuses.last,
            let baselineRow, statuses.contains(where: { $0.id == baselineRow }),
            !metadata.gaps.contains(where: { $0.sinceID == baseline && $0.targetHeadID == newest })
        {
            metadata.gaps.append(TimelineGap(
                afterID: oldest.id, beforeID: baselineRow,
                maxID: page.nextMaxID ?? oldest.id, sinceID: baseline,
                targetHeadID: newest, sequence: metadata.sequence))
        } else if page.isPartial, let baseline = sinceID,
            let oldest = pageStatuses.last, oldest.id != baseline,
            let baselineRow, statuses.contains(where: { $0.id == baselineRow })
        {
            metadata.gaps.append(TimelineGap(
                afterID: oldest.id, beforeID: baselineRow, maxID: oldest.id,
                sinceID: baseline, targetHeadID: newest, sequence: metadata.sequence))
        }
        if metadata.gaps.isEmpty && !page.isPartial {
            metadata.checkpointID = metadata.fetchedHeadID
        }
        return inserted
    }

    /// Filling an acknowledged gap is historical loading, even if its body was
    /// first downloaded after the user returned to the latest batch.
    @discardableResult
    mutating func fillGap(_ id: UUID, page: TimelinePage, currentAccountID: String?) -> Bool {
        guard let index = metadata.gaps.firstIndex(where: { $0.id == id }) else { return false }
        let gap = metadata.gaps[index]
        let countsAsNew = gap.sequence > metadata.acknowledgedSequence
        let pageStatuses = Self.unique(page.statuses.filter { !isDeleted($0) })
        _ = merge(pageStatuses, before: gap.beforeID,
            currentAccountID: currentAccountID, countsAsNew: countsAsNew,
            sequence: gap.sequence)

        let reachedBoundary = page.statuses.contains { $0.id == gap.sinceID || $0.id == gap.beforeID }
        let exhausted = page.statuses.isEmpty && !page.isPartial
        if !page.isPartial && (reachedBoundary || exhausted) {
            metadata.gaps.remove(at: index)
            if metadata.gaps.isEmpty {
                metadata.checkpointID = metadata.fetchedHeadID
                metadata.overflowSequence = nil
            }
            return true
        }
        guard let next = page.nextMaxID ?? page.statuses.last?.id,
            next != gap.maxID, next != gap.sinceID
        else { return false }
        metadata.gaps[index].maxID = next
        if let last = pageStatuses.last, last.id != gap.beforeID {
            metadata.gaps[index].afterID = last.id
        }
        return true
    }

    mutating func appendOlder(_ page: [Status]) {
        let existing = Set(statuses.map(\.id))
        statuses.append(contentsOf: Self.unique(page).filter { !existing.contains($0.id) && !isDeleted($0) })
    }

    mutating func update(_ status: Status) {
        for index in statuses.indices
        where statuses[index].id == status.id || statuses[index].displayStatus.id == status.id {
            if let edited = statuses[index].displayStatus.editedAt,
                edited > (status.displayStatus.editedAt ?? .distantPast) { continue }
            statuses[index] = statuses[index].incorporatingDisplayStatusUpdate(status)
        }
    }

    mutating func remove(_ id: String) {
        if deletedIDs.insert(id).inserted { deletedOrder.append(id) }
        if deletedOrder.count > 800 {
            let expired = deletedOrder.removeFirst()
            deletedIDs.remove(expired)
            deletedBoundaryReplacements[expired] = nil
        }
        let removed = Set(statuses.filter { $0.id == id || $0.displayStatus.id == id }.map(\.id))
        for rowID in removed {
            metadata.newIDs[rowID] = nil
            if let index = statuses.firstIndex(where: { $0.id == rowID }),
                let next = statuses.dropFirst(index + 1).first(where: { !removed.contains($0.id) }) {
                deletedBoundaryReplacements[rowID] = next.id
                for (old, replacement) in deletedBoundaryReplacements where replacement == rowID {
                    deletedBoundaryReplacements[old] = next.id
                }
            }
        }
        // Retarget gap presentation to a surviving neighbor; the server cursors
        // remain valid bounds even when their original status has been deleted.
        for index in metadata.gaps.indices where removed.contains(metadata.gaps[index].afterID) {
            if let position = statuses.firstIndex(where: { $0.id == metadata.gaps[index].afterID }),
                let previous = statuses[..<position].last(where: { !removed.contains($0.id) }) {
                metadata.gaps[index].afterID = previous.id
            }
        }
        for index in metadata.gaps.indices where removed.contains(metadata.gaps[index].beforeID) {
            if let position = statuses.firstIndex(where: { $0.id == metadata.gaps[index].beforeID }),
                let next = statuses.dropFirst(position + 1).first(where: { !removed.contains($0.id) }) {
                metadata.gaps[index].beforeID = next.id
            }
        }
        statuses.removeAll { removed.contains($0.id) }
        let retained = Set(statuses.map(\.id))
        metadata.gaps.removeAll { !retained.contains($0.afterID) || !retained.contains($0.beforeID) }
    }

    mutating func acknowledge(through sequence: UInt64) {
        metadata.acknowledgedSequence = max(metadata.acknowledgedSequence, sequence)
        metadata.newIDs = metadata.newIDs.filter { $0.value > sequence }
    }

    mutating func setReadingAnchor(_ anchor: TimelineReadingAnchor?) {
        metadata.readingAnchor = anchor
    }

    /// Bound bodies that arrived while a page was dragging or offscreen. Preserve
    /// every already-presented row; the omitted range stays explicitly pageable.
    mutating func trimUnapplied(presentedIDs: Set<String>, limit: Int = 200) {
        let incoming = statuses.prefix { !presentedIDs.contains($0.id) }
        guard incoming.count > limit else { return }
        let keep = Array(incoming.prefix(limit))
        let dropped = Set(incoming.dropFirst(limit).map(\.id))
        if let upper = keep.last?.id, let lower = statuses.first(where: { presentedIDs.contains($0.id) })?.id {
            metadata.gaps.removeAll { dropped.contains($0.afterID) || dropped.contains($0.beforeID) }
            if !metadata.gaps.contains(where: { $0.afterID == upper && $0.beforeID == lower }) {
                metadata.gaps.append(TimelineGap(afterID: upper, beforeID: lower,
                    maxID: upper, sinceID: lower,
                    targetHeadID: keep.first!.id, sequence: metadata.sequence))
            }
        }
        statuses.removeAll { dropped.contains($0.id) }
        metadata.newIDs = metadata.newIDs.filter { !dropped.contains($0.key) }
        metadata.overflowSequence = metadata.sequence
    }

    private mutating func merge(
        _ page: [Status], before fallbackID: String?, currentAccountID: String?,
        countsAsNew: Bool = true, sequence: UInt64? = nil
    ) -> Int {
        var anchor = fallbackID
        var inserted = 0
        for status in page.reversed() {
            if statuses.contains(where: { $0.id == status.id }) {
                update(status)
            } else {
                let index = anchor.flatMap { id in statuses.firstIndex { $0.id == id } } ?? 0
                statuses.insert(status, at: index)
                inserted += 1
                if countsAsNew { recordNew(status, currentAccountID: currentAccountID, sequence: sequence) }
            }
            anchor = status.id
        }
        return inserted
    }

    private mutating func recordNew(_ status: Status, currentAccountID: String?, sequence: UInt64? = nil) {
        metadata.sequence &+= 1
        guard status.account.id != currentAccountID else { return }
        metadata.newIDs[status.id] = sequence ?? metadata.sequence
        // The notice only displays 99+. Keep a bounded, truthful lower bound.
        if metadata.newIDs.count > 200 {
            let oldest = metadata.newIDs.min { $0.value < $1.value }!.key
            metadata.newIDs[oldest] = nil
            metadata.overflowSequence = metadata.sequence
        }
    }

    private func isDeleted(_ status: Status) -> Bool {
        deletedIDs.contains(status.id) || deletedIDs.contains(status.displayStatus.id)
    }

    private static func unique(_ statuses: [Status]) -> [Status] {
        var ids = Set<String>()
        return statuses.filter { ids.insert($0.id).inserted }
    }
}
