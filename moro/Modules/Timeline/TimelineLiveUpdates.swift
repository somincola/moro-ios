import Foundation

/// The transport result retains completeness; a regenerating (206) home feed is
/// usable content, but must never close a gap or advance a verified checkpoint.
struct TimelinePage {
    let statuses: [Status]
    var isPartial = false
    var nextMaxID: String?
    var prevMinID: String?
}

nonisolated enum TimelineGapFillDirection: Equatable, Sendable {
    case downward
    case upward
}

nonisolated enum TimelineGapFillOutcome: Equatable, Sendable {
    case progressed
    case closed
    case fallbackToDownward
    case stalled

    var didAdvance: Bool {
        self == .progressed || self == .closed
    }
}

struct TimelineGap: Codable, Equatable, Identifiable {
    var id = UUID()
    var afterID: String
    var beforeID: String
    var maxID: String
    var sinceID: String
    let targetHeadID: String
    let sequence: UInt64
}

nonisolated struct TimelineReadingAnchor: Codable, Equatable, Sendable {
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
        restoreUnconfirmedHeadOrder()
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

    /// Preserve server page order and interleave unconfirmed stream/local rows by
    /// their local-server cursors. created_at is not a timeline-ordering key.
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
            let baselineRow,
            let afterIndex = statuses.firstIndex(where: { $0.id == oldest.id }),
            let beforeIndex = statuses.firstIndex(where: { $0.id == baselineRow }),
            afterIndex < beforeIndex,
            !metadata.gaps.contains(where: { $0.sinceID == baseline && $0.targetHeadID == newest })
        {
            metadata.gaps.append(TimelineGap(
                afterID: oldest.id, beforeID: baselineRow,
                maxID: page.nextMaxID ?? oldest.id, sinceID: baseline,
                targetHeadID: newest, sequence: metadata.sequence))
        } else if page.isPartial, let baseline = sinceID,
            let oldest = pageStatuses.last, oldest.id != baseline,
            let baselineRow,
            let afterIndex = statuses.firstIndex(where: { $0.id == oldest.id }),
            let beforeIndex = statuses.firstIndex(where: { $0.id == baselineRow }),
            afterIndex < beforeIndex
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
        fillGap(id, page: page, direction: .downward, currentAccountID: currentAccountID).didAdvance
    }

    @discardableResult
    mutating func fillGap(
        _ id: UUID,
        page: TimelinePage,
        direction: TimelineGapFillDirection,
        currentAccountID: String?
    ) -> TimelineGapFillOutcome {
        guard let index = metadata.gaps.firstIndex(where: { $0.id == id }) else { return .stalled }
        let gap = metadata.gaps[index]
        let countsAsNew = gap.sequence > metadata.acknowledgedSequence

        switch direction {
        case .downward:
            let pageStatuses = Self.unique(page.statuses.filter { !isDeleted($0) })
            _ = merge(pageStatuses, before: gap.beforeID,
                currentAccountID: currentAccountID, countsAsNew: countsAsNew,
                sequence: gap.sequence)

            let reachedBoundary = page.statuses.contains { $0.id == gap.sinceID || $0.id == gap.beforeID }
            let exhausted = page.statuses.isEmpty && !page.isPartial
            if !page.isPartial && (reachedBoundary || exhausted) {
                closeGap(at: index)
                return .closed
            }
            guard let next = page.nextMaxID ?? page.statuses.last?.id,
                next != gap.maxID, next != gap.sinceID
            else { return .stalled }
            metadata.gaps[index].maxID = next
            if let last = pageStatuses.last, last.id != gap.beforeID {
                metadata.gaps[index].afterID = last.id
            }
            return .progressed

        case .upward:
            guard Self.isNumericID(gap.maxID), Self.isNumericID(gap.sinceID) else {
                return .fallbackToDownward
            }
            if page.statuses.isEmpty {
                if !page.isPartial {
                    closeGap(at: index)
                    return .closed
                }
                return .stalled
            }

            let rawInsideGap = page.statuses.filter {
                Self.isNewerID(gap.maxID, than: $0.id) && Self.isNewerID($0.id, than: gap.sinceID)
            }
            // A non-empty response containing nothing strictly inside the gap is ambiguous:
            // either the server ignored `min_id` and returned the timeline head, or the gap
            // is empty and the response ran past `maxID`. Fall back to `max_id` so we never
            // falsely close a real gap or drop posts on non-standard instances.
            guard !rawInsideGap.isEmpty else {
                return .fallbackToDownward
            }

            let upperKnownIDs: Set<String>
            if let afterIndex = statuses.firstIndex(where: { $0.id == gap.afterID }) {
                upperKnownIDs = Set(statuses[...afterIndex].map(\.id))
            } else {
                upperKnownIDs = []
            }
            let reachedUpperBoundary = page.statuses.contains {
                $0.id == gap.maxID || $0.id == gap.afterID
                    || Self.isNewerID($0.id, than: gap.maxID)
                    || upperKnownIDs.contains($0.id)
            }

            let pageStatuses = Self.unique(rawInsideGap.filter { !isDeleted($0) })
            _ = merge(pageStatuses, before: gap.beforeID,
                currentAccountID: currentAccountID, countsAsNew: countsAsNew,
                sequence: gap.sequence)

            if !page.isPartial && reachedUpperBoundary {
                closeGap(at: index)
                return .closed
            }

            let cursorCandidate: String?
            if let prev = page.prevMinID,
                Self.isNewerID(gap.maxID, than: prev),
                Self.isNewerID(prev, than: gap.sinceID)
            {
                cursorCandidate = prev
            } else {
                cursorCandidate = rawInsideGap.first?.id
            }
            guard let nextSince = cursorCandidate,
                nextSince != gap.sinceID, nextSince != gap.maxID
            else { return .stalled }
            metadata.gaps[index].sinceID = nextSince
            if let newestVisible = pageStatuses.first, newestVisible.id != gap.afterID {
                metadata.gaps[index].beforeID = newestVisible.id
            }
            return .progressed
        }
    }

    private mutating func closeGap(at index: Int) {
        metadata.gaps.remove(at: index)
        if metadata.gaps.isEmpty {
            metadata.checkpointID = metadata.fetchedHeadID
            metadata.overflowSequence = nil
        }
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

    /// Marks statuses at or older than `statusID` as already read (e.g. synced from another
    /// device via Mastodon's Marker API) so the new-posts badge reflects only truly unread items.
    mutating func markReadThrough(statusID: String) {
        metadata.newIDs = metadata.newIDs.filter { id, _ in
            id != statusID && Self.isNewerID(id, than: statusID)
        }
    }

    func gapSpanning(statusID: String) -> TimelineGap? {
        guard Self.isNumericID(statusID) else { return nil }
        return metadata.gaps.first {
            Self.isNewerID($0.maxID, than: statusID) && Self.isNewerID(statusID, than: $0.sinceID)
        }
    }

    /// Inserts a cross-gap context slice fetched around a remote Marker ID (typically from
    /// `GET /api/v1/timelines/home?min_id=<remoteID>` + `GET /api/v1/statuses/<remoteID>`),
    /// accurately splitting any spanning gap into an unread upper gap and a historical lower gap.
    /// Returns the concrete target status ID to anchor on, or `nil` if the response cannot be
    /// safely placed (e.g. a non-standard server ignored `min_id`).
    @discardableResult
    mutating func insertRemoteAnchorContext(
        remoteID: String,
        anchorStatus: Status?,
        newerPage: TimelinePage,
        currentAccountID: String?
    ) -> String? {
        guard Self.isNumericID(remoteID) else { return nil }
        if statuses.contains(where: { $0.id == remoteID }) {
            markReadThrough(statusID: remoteID)
            return remoteID
        }

        if let spanningIndex = metadata.gaps.firstIndex(where: {
            Self.isNewerID($0.maxID, than: remoteID) && Self.isNewerID(remoteID, than: $0.sinceID)
        }) {
            let originalGap = metadata.gaps[spanningIndex]
            let rawNewerInside = newerPage.statuses.filter {
                Self.isNewerID(originalGap.maxID, than: $0.id) && Self.isNewerID($0.id, than: remoteID)
            }
            let validAnchor: Status? = anchorStatus.flatMap { status in
                guard status.id == remoteID,
                    !isDeleted(status),
                    Self.isNewerID(originalGap.maxID, than: status.id),
                    Self.isNewerID(status.id, than: originalGap.sinceID)
                else { return nil }
                return status
            }

            let filteredNewer = Self.unique(rawNewerInside.filter { !isDeleted($0) })
            let fragment = filteredNewer + (validAnchor.map { [$0] } ?? [])
            guard !fragment.isEmpty else { return nil }

            let upperKnownIDs: Set<String>
            if let afterIndex = statuses.firstIndex(where: { $0.id == originalGap.afterID }) {
                upperKnownIDs = Set(statuses[...afterIndex].map(\.id))
            } else {
                upperKnownIDs = []
            }
            // Only trust `newerPage` to close the upper gap when it also returned posts
            // strictly inside the gap (proving the server honored `min_id`).
            let reachedUpperBoundary = !rawNewerInside.isEmpty && !newerPage.isPartial
                && newerPage.statuses.contains {
                    $0.id == originalGap.maxID || $0.id == originalGap.afterID
                        || Self.isNewerID($0.id, than: originalGap.maxID)
                        || upperKnownIDs.contains($0.id)
                }

            let countsAsNew = originalGap.sequence > metadata.acknowledgedSequence
            _ = merge(
                fragment,
                before: originalGap.beforeID,
                currentAccountID: currentAccountID,
                countsAsNew: countsAsNew,
                sequence: originalGap.sequence
            )

            metadata.gaps.remove(at: spanningIndex)
            let fragmentTopID = fragment.first!.id
            let fragmentBottomID = fragment.last!.id

            if !reachedUpperBoundary {
                let upperSinceID: String
                if let prev = newerPage.prevMinID,
                    Self.isNewerID(originalGap.maxID, than: prev),
                    Self.isNewerID(prev, than: remoteID)
                {
                    upperSinceID = prev
                } else {
                    upperSinceID = fragmentTopID
                }
                metadata.gaps.append(
                    TimelineGap(
                        afterID: originalGap.afterID,
                        beforeID: fragmentTopID,
                        maxID: originalGap.maxID,
                        sinceID: upperSinceID,
                        targetHeadID: originalGap.targetHeadID,
                        sequence: originalGap.sequence
                    )
                )
            }

            // Everything below the remote marker was already read on another device:
            // keep it explicitly loadable as a manual gap without inflating unread counts.
            metadata.gaps.append(
                TimelineGap(
                    afterID: fragmentBottomID,
                    beforeID: originalGap.beforeID,
                    maxID: fragmentBottomID,
                    sinceID: originalGap.sinceID,
                    targetHeadID: originalGap.targetHeadID,
                    sequence: metadata.acknowledgedSequence
                )
            )

            markReadThrough(statusID: remoteID)
            return validAnchor?.id ?? filteredNewer.last?.id
        }

        // If `remoteID` is strictly newer than our entire loaded timeline, insert the slice
        // at the head and leave a historical gap to the previous head.
        let isAheadOfHead = statuses.first.map { Self.isNewerID(remoteID, than: $0.id) } ?? true
        guard isAheadOfHead else { return nil }

        let rawNewerInside = newerPage.statuses.filter { Self.isNewerID($0.id, than: remoteID) }
        let validAnchor: Status? = anchorStatus.flatMap { status in
            status.id == remoteID && !isDeleted(status) ? status : nil
        }
        let filteredNewer = Self.unique(rawNewerInside.filter { !isDeleted($0) })
        let fragment = filteredNewer + (validAnchor.map { [$0] } ?? [])
        guard !fragment.isEmpty else { return nil }

        let previousHead = statuses.first?.id
        _ = merge(fragment, before: previousHead, currentAccountID: currentAccountID, countsAsNew: true)

        let fragmentTopID = fragment.first!.id
        let fragmentBottomID = fragment.last!.id
        if !newerPage.isPartial {
            if let existingHead = metadata.fetchedHeadID {
                if Self.isNewerID(fragmentTopID, than: existingHead) {
                    metadata.fetchedHeadID = fragmentTopID
                }
            } else {
                metadata.fetchedHeadID = fragmentTopID
            }
        }
        if let previousHead {
            metadata.gaps.append(
                TimelineGap(
                    afterID: fragmentBottomID,
                    beforeID: previousHead,
                    maxID: fragmentBottomID,
                    sinceID: previousHead,
                    targetHeadID: fragmentTopID,
                    sequence: metadata.acknowledgedSequence
                )
            )
        }
        markReadThrough(statusID: remoteID)
        return validAnchor?.id ?? filteredNewer.last?.id
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
                let anchorIndex = anchor.flatMap { id in statuses.firstIndex { $0.id == id } } ?? 0
                let index = statuses[..<anchorIndex].firstIndex {
                    Self.isNewerID(status.id, than: $0.id)
                } ?? anchorIndex
                statuses.insert(status, at: index)
                inserted += 1
                if countsAsNew { recordNew(status, currentAccountID: currentAccountID, sequence: sequence) }
            }
            anchor = status.id
        }
        return inserted
    }

    /// Older snapshots may have retained a local reply above a newer confirmed
    /// head. Repair only that unconfirmed prefix, preserving server row order.
    private mutating func restoreUnconfirmedHeadOrder() {
        guard let headID = metadata.fetchedHeadID,
            let headIndex = statuses.firstIndex(where: { $0.id == headID }), headIndex > 0
        else { return }
        let misplaced = statuses[..<headIndex].filter { Self.isNewerID(headID, than: $0.id) }
        guard !misplaced.isEmpty else { return }
        let misplacedIDs = Set(misplaced.map(\.id))
        statuses.removeAll { misplacedIDs.contains($0.id) }
        for status in misplaced.reversed() {
            let index = statuses.firstIndex { Self.isNewerID(status.id, than: $0.id) } ?? statuses.endIndex
            statuses.insert(status, at: index)
        }
    }

    nonisolated static func isNumericID(_ id: String) -> Bool {
        !id.isEmpty && id.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
    }

    nonisolated static func isNewerID(_ lhs: String, than rhs: String) -> Bool {
        // Decimal cursors can exceed UInt64. Opaque IDs retain the server's
        // anchor-based order instead of receiving an invented lexical order.
        guard isNumericID(lhs), isNumericID(rhs) else { return false }
        let left = lhs.utf8.drop(while: { $0 == 48 })
        let right = rhs.utf8.drop(while: { $0 == 48 })
        if left.count != right.count { return left.count > right.count }
        return right.lexicographicallyPrecedes(left)
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
