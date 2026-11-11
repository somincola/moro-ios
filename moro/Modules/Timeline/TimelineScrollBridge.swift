//
//  TimelineScrollBridge.swift
//  moro
//
//  Shared scroll/header state for the home timelines.
//
//  The iOS timeline pager (TimelinePagerHost) hosts each timeline in its own
//  UIHostingController — a separate SwiftUI tree — so @State mutated inside a hosted
//  scroll view (scroll proxy, header visibility, at-top flags) never propagates back to
//  TimelineHomeView's own tree. Routing that state through a shared *reference* (this
//  ObservableObject, held once by TimelineHomeView and reached via the captured `self`
//  inside each hosted page) bridges the two trees, so tap-to-top and the scroll-driven
//  header hide/show actually take effect.
//

import Combine
import SwiftUI
import UIKit

struct TimelinePullRefreshVisualState: Equatable {
    let distance: CGFloat
    let threshold: CGFloat
    let isRefreshing: Bool
    let isPinned: Bool

    static let idle = TimelinePullRefreshVisualState(
        distance: 0,
        threshold: 1,
        isRefreshing: false,
        isPinned: false
    )
}

private enum TimelinePullRefreshPhase {
    case idle
    case pulling
    case armed
    case refreshing
}

private struct TimelinePullRefreshState {
    var distance: CGFloat = 0
    var phase: TimelinePullRefreshPhase = .idle
}

@MainActor
final class TimelineScrollBridge: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private final class WeakScrollView {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        weak var value: UIScrollView?

        init(_ value: UIScrollView) {
            self.value = value
        }
    }

    /// Whether each timeline is scrolled to the very top.
    /// Not `@Published`: geometry callbacks write this during view updates. The new-posts
    /// notice observes `atTopEvents` locally, the same way chrome uses `chromeFractionSubject`.
    private var atTop: [TimelineType: Bool] = [:]
    let atTopEvents = PassthroughSubject<TimelineType, Never>()
    let layoutEvents = PassthroughSubject<TimelineType, Never>()
    let userScrollEvents = PassthroughSubject<TimelineType, Never>()
    private var rows: [TimelineType: [String: WeakRow]] = [:]
    private var phases: [TimelineType: ScrollPhase] = [:]
    /// Timelines that will reopen at a saved reading position. Their list stays transparent
    /// from the first row layout until that position lands, so no frame shows the top first.
    private var awaitingRestore: Set<TimelineType> = []
    private var veiledTimelines: Set<TimelineType> = []
    private let restoreVeilLimit: TimeInterval = 0.8
    private var headerHeights: [TimelineType: CGFloat] = [:]
    private var pendingLayouts: [TimelineType: PendingLayout] = [:]
    private var scheduledLayoutEvents: Set<TimelineType> = []
    private var waitingForTop: Set<TimelineType> = []
    private var frozenTimelines: Set<TimelineType> = []
    /// After returning from the background, a timeline left at the very top keeps the post
    /// that was showing instead of following the newest one; new posts wait behind the
    /// notice. Released per timeline as soon as the reader scrolls or jumps to the latest.
    private var holdsPositionAfterResume = false
    private var releasedFromResumeHold: Set<TimelineType> = []
    /// Timelines whose saved reading position was just restored; same release rules.
    private var heldTimelines: Set<TimelineType> = []
    /// After an anchored update, rows above the reader can still change height for a
    /// moment (newly inserted rows finishing layout, a gap marker, media sizing). Keep the
    /// reading anchor in place for a short settle window, until the reader touches the list.
    private var settlingAnchors: [TimelineType: (anchor: TimelineReadingAnchor, until: Date)] = [:]
    private let anchorSettleDuration: TimeInterval = 1.0
    /// The same settle window for a jump to the latest: rows at the top can still grow
    /// (media, cards) right after the jump, which would leave the list a little short of it.
    private var settlingTop: [TimelineType: Date] = [:]
    /// SwiftUI can re-apply its own scroll position after ours without any row
    /// re-laying out, so a settle window is checked every frame, not only on layout
    /// events. It runs only while a window is open (about a second).
    private var settleTicker: CADisplayLink?
    private var suppressChrome: Set<TimelineType> = []
    private var active = false
    private var playbackScopes: [TimelineType: MediaPlaybackScope] = [:]

    func playbackScope(for timeline: TimelineType) -> MediaPlaybackScope {
        if let scope = playbackScopes[timeline] { return scope }
        let scope = MediaPlaybackScope(isActive: active && isPresented(timeline) && !frozenTimelines.contains(timeline),
                                       allowsAnimatedAvatars: true)
        scope.isScrolling = phases[timeline].map { $0 != .idle } ?? false
        playbackScopes[timeline] = scope
        return scope
    }

    private func updatePlaybackScopes() {
        for (timeline, scope) in playbackScopes {
            scope.isActive = active && isPresented(timeline) && !frozenTimelines.contains(timeline)
            scope.isScrolling = phases[timeline].map { $0 != .idle } ?? false
        }
    }

    /// Owned by the bridge, not SwiftUI's onChange cycle. The pager reports the
    /// displayed controller before its parent's selection onChange can run.
    struct Presentation: Equatable {
        let timeline: TimelineType
        fileprivate let id = UUID()
    }
    private var presentation: Presentation?
    private var pendingPullRefreshFinishes: [TimelineType: (anchor: TimelineReadingAnchor?, revision: UInt64)] = [:]

    func beginPresentation(for timeline: TimelineType) -> Presentation {
        let transaction = Presentation(timeline: timeline)
        presentation = transaction
        selectPresentedTimeline(timeline)
        setFrozen(true, for: timeline)
        return transaction
    }

    func isCurrentPresentation(_ transaction: Presentation) -> Bool {
        presentation == transaction && isPresented(transaction.timeline)
    }

    @discardableResult
    func finishPresentation(_ transaction: Presentation) -> Bool {
        guard isCurrentPresentation(transaction) else { return false }
        presentation = nil
        // A retained page can disappear while SwiftUI still reports deceleration.
        // Trust its settled native scroll view when it is presented again.
        if let scroll = nativeScrollViews[transaction.timeline]?.value,
            !scroll.isTracking && !scroll.isDragging && !scroll.isDecelerating {
            phases[transaction.timeline] = .idle
        }
        setFrozen(false, for: transaction.timeline)
        return true
    }

    /// Reactivation keeps the existing position. Do not supersede an in-flight
    /// pager restoration for this same page (onAppear can run after the pager).
    func resumePresentation(for timeline: TimelineType) {
        if let presentation, presentation.timeline == timeline { return }
        let transaction = beginPresentation(for: timeline)
        setPresentedTimeline(timeline)
        finishPresentation(transaction)
    }

    private struct PendingLayout {
        let revision: UInt64
        let anchors: [TimelineReadingAnchor]
        let followsLatest: Bool
        var requestedAnchorLayout = false
        var includesRefreshCollapse = false
        var waitsForRefreshCollapse = false
    }
    private final class WeakRow {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        weak var value: TimelineRowAnchorView?
        init(_ value: TimelineRowAnchorView) { self.value = value }
    }

    func setActive(_ value: Bool) {
        active = value
        updatePlaybackScopes()
        if !value {
            pendingLayouts = pendingLayouts.filter { $0.value.includesRefreshCollapse }
            waitingForTop.removeAll()
        } else { scheduleLayoutEvent(for: presentedTimeline) }
    }

    func setFrozen(_ frozen: Bool, for timeline: TimelineType) {
        if frozen {
            frozenTimelines.insert(timeline)
            if pendingLayouts[timeline]?.includesRefreshCollapse != true {
                pendingLayouts[timeline] = nil
            }
            waitingForTop.remove(timeline)
        } else {
            frozenTimelines.remove(timeline)
            scheduleLayoutEvent(for: timeline)
        }
        updatePlaybackScopes()
    }

    /// A saved reading position was restored on this timeline: until the reader scrolls,
    /// new posts must not pull the view to the latest, even if the restore briefly
    /// reported the top.
    func holdReadingPosition(for timeline: TimelineType) {
        heldTimelines.insert(timeline)
    }

    private func releaseHold(for timeline: TimelineType) {
        releasedFromResumeHold.insert(timeline)
        heldTimelines.remove(timeline)
        settlingAnchors[timeline] = nil
        settlingTop[timeline] = nil
    }

    /// Called when the app returns to the foreground.
    func holdReadingPositionAfterResume() {
        holdsPositionAfterResume = true
        releasedFromResumeHold.removeAll()
    }

    private func followsLatestAtTop(_ timeline: TimelineType) -> Bool {
        isAtTop(timeline) && !heldTimelines.contains(timeline)
            && !(holdsPositionAfterResume && !releasedFromResumeHold.contains(timeline))
    }

    func updatePhase(_ phase: ScrollPhase, for timeline: TimelineType) {
        phases[timeline] = phase
        updatePlaybackScopes()
        if phase == .tracking || phase == .interacting {
            pendingLayouts[timeline] = nil
            waitingForTop.remove(timeline)
            releaseHold(for: timeline)
        }
        if phase == .interacting, active, isPresented(timeline) {
            userScrollEvents.send(timeline)
        }
        if phase == .idle { scheduleLayoutEvent(for: timeline) }
    }

    /// A finger is on the timeline right now (UIKit's own flags, so it does not wait for
    /// SwiftUI's phase callback).
    func isUserDragging(_ timeline: TimelineType) -> Bool {
        if let view = nativeScrollViews[timeline]?.value, view.isTracking || view.isDragging { return true }
        let phase = phases[timeline, default: .idle]
        return phase == .tracking || phase == .interacting
    }

    func isUserScrolling(_ timeline: TimelineType) -> Bool {
        phases[timeline] == .interacting || phases[timeline] == .decelerating
    }

    func updateGeometry(for timeline: TimelineType, headerHeight: CGFloat) {
        headerHeights[timeline] = headerHeight
        guard let scrollView = nativeScrollViews[timeline]?.value else { return }
        updateTopPosition(for: timeline, scrollView: scrollView)
        if !scrollView.isDragging && !scrollView.isDecelerating {
            scheduleLayoutEvent(for: timeline)
        }
    }

    private func updateTopPosition(for timeline: TimelineType, scrollView: UIScrollView) {
        let distance = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        setAtTop(abs(distance) <= 2, for: timeline)
        if abs(distance) <= 2, phases[timeline, default: .idle] == .idle {
            waitingForTop.remove(timeline)
        }
    }

    func canPresentUpdates(for timeline: TimelineType) -> Bool {
        guard active, isPresented(timeline), !frozenTimelines.contains(timeline),
            pendingLayouts[timeline] == nil, !waitingForTop.contains(timeline),
            phases[timeline, default: .idle] == .idle,
            let view = nativeScrollViews[timeline]?.value, view.window != nil
        else { return false }
        return !view.isTracking && !view.isDragging && !view.isDecelerating
    }

    func readingAnchors(for timeline: TimelineType, onlyVisible: Bool = true) -> [TimelineReadingAnchor] {
        guard let scrollView = nativeScrollViews[timeline]?.value else { return [] }
        let header = headerHeights[timeline, default: 48]
        return rows[timeline, default: [:]].values.compactMap { row -> TimelineReadingAnchor? in
            guard let view = row.value, view.window != nil else { return nil }
            let frame = view.convert(view.bounds, to: scrollView)
            let y = frame.minY - scrollView.contentOffset.y
            if onlyVisible && (y + frame.height <= header || y >= scrollView.bounds.height) { return nil }
            return TimelineReadingAnchor(statusID: view.statusID, viewportOffset: Double(y - header))
        }.sorted { $0.viewportOffset < $1.viewportOffset }
    }

    @discardableResult
    func prepareContentUpdate(for timeline: TimelineType, revision: UInt64, jumpToLatest: Bool = false, retainedIDs: Set<String>? = nil) -> Bool {
        guard active, isPresented(timeline) else { return false }
        if !jumpToLatest && !canPresentUpdates(for: timeline) { return false }
        let followsLatest = jumpToLatest || followsLatestAtTop(timeline)
        let candidates = readingAnchors(for: timeline, onlyVisible: false)
        let visibleIDs = Set(readingAnchors(for: timeline).map(\.statusID))
        let survivors = candidates.filter { retainedIDs?.contains($0.statusID) ?? true }
        let visible = survivors.filter { visibleIDs.contains($0.statusID) }
        let anchors = visible.isEmpty ? Array(survivors.sorted { abs($0.viewportOffset) < abs($1.viewportOffset) }.prefix(1)) : visible
        guard followsLatest || !anchors.isEmpty || retainedIDs?.isEmpty == true else { return false }
        settlingAnchors[timeline] = nil
        pendingLayouts[timeline] = PendingLayout(revision: revision, anchors: anchors,
            followsLatest: followsLatest)
        scheduleLayoutEvent(for: timeline)
        return true
    }

    func latestIsVisible(for timeline: TimelineType, statusID: String?, revision: UInt64) -> Bool {
        guard canPresentUpdates(for: timeline), isAtTop(timeline), let statusID,
            let view = rows[timeline]?[statusID]?.value,
            view.window != nil, view.laidOutRevision >= revision else { return false }
        return readingAnchors(for: timeline).contains { $0.statusID == statusID }
    }

    func restoreReadingAnchor(_ anchor: TimelineReadingAnchor, for timeline: TimelineType) {
        guard let view = rows[timeline]?[anchor.statusID]?.value,
            let scrollView = nativeScrollViews[timeline]?.value else {
            proxies[timeline]?.scrollTo(anchor.statusID, anchor: .top)
            pendingLayouts[timeline] = PendingLayout(revision: 0, anchors: [anchor], followsLatest: false)
            return
        }
        let y = view.convert(view.bounds, to: scrollView).minY
        let offset = y - headerHeights[timeline, default: 48] - CGFloat(anchor.viewportOffset)
        suppressChrome.insert(timeline)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: offset), animated: false)
        // Same transaction as the offset: the first visible frame is already in place.
        endRestoreVeil(for: timeline)
    }

    /// Call before a timeline's rows first appear when it will reopen at a saved position.
    func expectReadingRestore(for timeline: TimelineType) {
        guard !veiledTimelines.contains(timeline) else { return }
        awaitingRestore.insert(timeline)
    }

    /// Shows the list again: the restore landed, was not needed, or took too long.
    func endRestoreVeil(for timeline: TimelineType) {
        awaitingRestore.remove(timeline)
        guard veiledTimelines.remove(timeline) != nil else { return }
        nativeScrollViews[timeline]?.value?.alpha = 1
    }

    private func veilUntilRestored(_ timeline: TimelineType) {
        // Runs from row layout, inside the transaction that would first draw the rows.
        guard let scrollView = nativeScrollViews[timeline]?.value,
            awaitingRestore.remove(timeline) != nil else { return }
        veiledTimelines.insert(timeline)
        scrollView.alpha = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreVeilLimit) { [weak self] in
            self?.endRestoreVeil(for: timeline)
        }
    }

    func rowDidLayout(_ row: TimelineRowAnchorView, for timeline: TimelineType) {
        rows[timeline, default: [:]][row.statusID] = WeakRow(row)
        if awaitingRestore.contains(timeline) { veilUntilRestored(timeline) }
        #if DEBUG
        startCommitProbeIfRequested()
        #endif
        scheduleLayoutEvent(for: timeline)
    }

    #if DEBUG
    /// UI-test probe: the largest reading-anchor displacement that was actually committed
    /// to the screen while a content update was still waiting for its offset correction.
    static var probeEnabled = false
    static private(set) var maxCommittedAnchorDisplacement: CGFloat = 0
    static func resetCommitProbe() { maxCommittedAnchorDisplacement = 0 }
    private var commitObserver: CFRunLoopObserver?

    private func startCommitProbeIfRequested() {
        guard Self.probeEnabled, commitObserver == nil else { return }
        // Core Animation commits in a before-waiting observer of order 2_000_000; running
        // right after it sees exactly what was handed to the render server this frame.
        let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue,
            true, 2_000_001) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.probeCommittedDisplacement() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        commitObserver = observer
    }

    /// Watches one visible post across arbitrary transitions (e.g. background → foreground)
    /// and records how far it ever moved on screen, frame by frame.
    static private var watchRequested = false
    static private var watched: TimelineReadingAnchor?
    static private(set) var maxWatchedDeviation: CGFloat = 0
    static private(set) var watchedFrames = 0
    static func beginWatch() { watchRequested = true; watched = nil; maxWatchedDeviation = 0; watchedFrames = 0 }

    private func probeWatchedPost() {
        guard Self.watchRequested else { return }
        let timeline = presentedTimeline
        guard let watched = Self.watched else {
            Self.watched = readingAnchors(for: timeline).first
            return
        }
        guard let row = rows[timeline]?[watched.statusID]?.value, row.window != nil,
            let scrollView = nativeScrollViews[timeline]?.value else { return }
        let y = row.convert(row.bounds, to: scrollView).minY - scrollView.contentOffset.y
            - headerHeights[timeline, default: 48]
        Self.watchedFrames += 1
        Self.maxWatchedDeviation = max(Self.maxWatchedDeviation, abs(y - CGFloat(watched.viewportOffset)))
    }

    private func probeCommittedDisplacement() {
        probeWatchedPost()
        for (timeline, pending) in pendingLayouts where !pending.followsLatest {
            guard let scrollView = nativeScrollViews[timeline]?.value else { continue }
            let header = headerHeights[timeline, default: 48]
            for anchor in pending.anchors {
                guard let row = rows[timeline]?[anchor.statusID]?.value, row.window != nil,
                    row.laidOutRevision >= pending.revision else { continue }
                let y = row.convert(row.bounds, to: scrollView).minY - scrollView.contentOffset.y - header
                Self.maxCommittedAnchorDisplacement = max(Self.maxCommittedAnchorDisplacement,
                    abs(y - CGFloat(anchor.viewportOffset)))
                break
            }
        }
    }
    #endif

    private func scheduleLayoutEvent(for timeline: TimelineType) {
        guard scheduledLayoutEvents.insert(timeline).inserted else { return }
        // A single layout completion turn, not a timer or scroll retry loop.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scheduledLayoutEvents.remove(timeline)
            self.rows[timeline] = self.rows[timeline]?.filter { $0.value.value?.window != nil }
            self.completeLayout(for: timeline)
            self.settleAnchorIfNeeded(for: timeline)
            // Native scrolling can settle after SwiftUI's last geometry callback.
            // Recheck on the existing idle/layout completion before acknowledging
            // the latest batch; reading the position must not enqueue another event.
            if let scrollView = self.nativeScrollViews[timeline]?.value {
                self.updateTopPosition(for: timeline, scrollView: scrollView)
                if let finish = self.pendingPullRefreshFinishes[timeline],
                    self.phases[timeline, default: .idle] == .idle,
                    !scrollView.isTracking && !scrollView.isDragging && !scrollView.isDecelerating {
                    self.finishPullRefresh(for: timeline, preserving: finish.anchor, revision: finish.revision)
                }
            }
            self.layoutEvents.send(timeline)
        }
    }

    private func settleAnchorIfNeeded(for timeline: TimelineType) {
        settleTopIfNeeded(for: timeline)
        guard let settling = settlingAnchors[timeline] else { return }
        guard Date() < settling.until, active, isPresented(timeline),
            !frozenTimelines.contains(timeline), pendingLayouts[timeline] == nil,
            !isUserDragging(timeline),
            let row = rows[timeline]?[settling.anchor.statusID]?.value, row.window != nil,
            let scrollView = nativeScrollViews[timeline]?.value else {
            if Date() >= settling.until { settlingAnchors[timeline] = nil }
            return
        }
        let y = row.convert(row.bounds, to: scrollView).minY - scrollView.contentOffset.y
            - headerHeights[timeline, default: 48]
        guard abs(y - CGFloat(settling.anchor.viewportOffset)) > 0.5 else { return }
        restoreReadingAnchor(settling.anchor, for: timeline)
    }

    private func startSettleTicker() {
        guard settleTicker == nil else { return }
        let target = TimelineSettleTickTarget { [weak self] in self?.settleTick() }
        let link = CADisplayLink(target: target, selector: #selector(TimelineSettleTickTarget.tick))
        link.add(to: .main, forMode: .common)
        settleTicker = link
    }

    private func settleTick() {
        for timeline in Set(settlingAnchors.keys).union(settlingTop.keys) {
            settleAnchorIfNeeded(for: timeline)
        }
        let now = Date()
        settlingAnchors = settlingAnchors.filter { $0.value.until > now }
        settlingTop = settlingTop.filter { $0.value > now }
        if settlingAnchors.isEmpty, settlingTop.isEmpty {
            settleTicker?.invalidate()
            settleTicker = nil
        }
    }

    private func settleTopIfNeeded(for timeline: TimelineType) {
        guard let until = settlingTop[timeline] else { return }
        guard Date() < until else { settlingTop[timeline] = nil; return }
        guard active, isPresented(timeline), !frozenTimelines.contains(timeline),
            pendingLayouts[timeline] == nil, !isUserDragging(timeline),
            let view = nativeScrollViews[timeline]?.value, !view.isDecelerating else { return }
        let top = -view.adjustedContentInset.top
        guard abs(view.contentOffset.y - top) > 0.5 else { return }
        view.setContentOffset(CGPoint(x: view.contentOffset.x, y: top), animated: false)
        updateTopPosition(for: timeline, scrollView: view)
    }

    private func completeLayout(for timeline: TimelineType) {
        guard active, isPresented(timeline), !frozenTimelines.contains(timeline),
            let pending = pendingLayouts[timeline] else { return }
        guard !pending.waitsForRefreshCollapse else { return }
        if pending.anchors.isEmpty, !pending.followsLatest {
            pendingLayouts[timeline] = nil
            return
        }
        guard rows[timeline, default: [:]].values.contains(where: { ($0.value?.laidOutRevision ?? 0) >= pending.revision }) else { return }
        if pending.followsLatest {
            pendingLayouts[timeline] = nil
            scrollToTop(timeline)
        } else if let anchor = pending.anchors.first(where: {
            guard let row = rows[timeline]?[$0.statusID]?.value else { return false }
            return row.laidOutRevision >= pending.revision
        }) {
            pendingLayouts[timeline] = nil
            restoreReadingAnchor(anchor, for: timeline)
            settlingAnchors[timeline] = (anchor, Date().addingTimeInterval(anchorSettleDuration))
            startSettleTicker()
        } else if !pending.requestedAnchorLayout, let anchor = pending.anchors.first,
            let proxy = proxies[timeline] {
            // Prepending a large batch may evict every old visible lazy row.
            // Materialize the stable ID once, then finish its intra-row offset
            // from the matching layout callback. Never poll or repeat scrollTo.
            pendingLayouts[timeline]?.requestedAnchorLayout = true
            proxy.scrollTo(anchor.statusID, anchor: .top)
        }
    }

    /// Set once the Home timeline has been scrolled at all (gates some startup work).
    @Published var hasScrolledHome = false

    /// Live scroll offset per timeline and the header's last toggle anchor — internal
    /// hysteresis state for the show/hide logic, not observed by any view.
    var offsets: [TimelineType: CGFloat] = [:]
    var headerAnchors: [TimelineType: CGFloat] = [:]

    private var proxies: [TimelineType: ScrollViewProxy] = [:]
    private var nativeScrollViews: [TimelineType: WeakScrollView] = [:]
    private(set) var presentedTimeline: TimelineType = .home

    // MARK: - Interactive chrome collapse

    /// Broadcasts the chrome-collapse fraction (0 = header/tab bar fully shown, 1 = fully
    /// hidden) on every scroll tick. It's a Combine Subject, *not* @Published, on purpose:
    /// subscribers (.onReceive in the header, the shell for the tab bar) update locally
    /// without re-rendering TimelineHomeView's body — so the pager is never rebuilt mid-scroll
    /// and the collapse stays buttery.
    let chromeFractionSubject = PassthroughSubject<CGFloat, Never>()
    private var pullRefreshSubjects: [TimelineType: CurrentValueSubject<TimelinePullRefreshVisualState, Never>] = [:]

    private var lastChromeOffset: CGFloat = 0
    private var chromeFraction: CGFloat = 0
    private var chromeFractions: [TimelineType: CGFloat] = [:]
    private var chromeNeedsSync = false
    private let chromeEpsilon: CGFloat = 0.0005
    private var pullRefreshStates: [TimelineType: TimelinePullRefreshState] = [:]

    /// Fold a fresh scroll offset (minY-style: 0 at top, more negative scrolling down) into the
    /// chrome fraction interactively — scrolling down nudges it toward hidden, up toward shown —
    /// and broadcast the result over `chromeFractionSubject`. Only the visible timeline drives the
    /// chrome. Nothing here is @Published, so a scroll never re-renders the body / rebuilds the
    /// pager — header and tab bar both react off the subject. Returns the fraction.
    @discardableResult
    func updateChrome(
        offset: CGFloat,
        headerHeight: CGFloat,
        timeline: TimelineType,
        isSelected: Bool
    ) -> CGFloat {
        guard isSelected else { return chromeFraction }
        if suppressChrome.remove(timeline) != nil {
            lastChromeOffset = offset
            return chromeFraction
        }

        // First tick after a timeline switch: adopt the new page's offset as the baseline so a
        // large position difference doesn't get accumulated into a sudden collapse.
        if chromeNeedsSync {
            chromeNeedsSync = false
            lastChromeOffset = offset
            return chromeFraction
        }

        let delta = offset - lastChromeOffset
        lastChromeOffset = offset
        guard abs(delta) > 0.25 else { return chromeFraction }

        let previousFraction = chromeFraction
        var fraction = chromeFraction - delta / max(headerHeight, 1)
        if offset >= 0 { fraction = 0 }  // at/above the top → always fully shown
        fraction = min(max(fraction, 0), 1)
        chromeFraction = fraction
        chromeFractions[timeline] = fraction
        if abs(fraction - previousFraction) > chromeEpsilon {
            chromeFractionSubject.send(fraction)
        }
        return fraction
    }

    /// Snap the chrome back to fully shown (scroll-to-top or a timeline switch) and resync the
    /// scroll baseline on the next tick.
    func resetChrome() {
        let shouldBroadcast = abs(chromeFraction) > chromeEpsilon
        chromeFraction = 0
        chromeFractions[presentedTimeline] = 0
        chromeNeedsSync = true
        if shouldBroadcast {
            chromeFractionSubject.send(0)
        }
    }

    /// Keep the current visual chrome state while adopting the newly selected page's
    /// offset as the next scroll baseline. This avoids a header flash on every switch.
    func prepareForTimelineSwitch() {
        chromeNeedsSync = true
    }

    func isAtTop(_ timeline: TimelineType) -> Bool { atTop[timeline] ?? false }

    func setAtTop(_ value: Bool, for timeline: TimelineType) {
        guard isAtTop(timeline) != value else { return }
        atTop[timeline] = value
        atTopEvents.send(timeline)
    }

    func register(_ proxy: ScrollViewProxy, for timeline: TimelineType) {
        proxies[timeline] = proxy
    }

    func register(_ scrollView: UIScrollView, for timeline: TimelineType) {
        nativeScrollViews[timeline] = WeakScrollView(scrollView)
        updateGeometry(for: timeline, headerHeight: headerHeights[timeline, default: 48])
        if waitingForTop.contains(timeline) { scrollToTop(timeline) }
    }

    func nativeContentOffset(for timeline: TimelineType) -> CGPoint? {
        nativeScrollViews[timeline]?.value?.contentOffset
    }

    @discardableResult
    func restoreNativeContentOffset(_ offset: CGPoint, for timeline: TimelineType) -> Bool {
        guard let scrollView = nativeScrollViews[timeline]?.value else { return false }
        scrollView.setContentOffset(offset, animated: false)
        return true
    }

    @discardableResult
    func setPresentedTimeline(_ timeline: TimelineType) -> CGFloat {
        selectPresentedTimeline(timeline)
        let restoredFraction = chromeFractions[timeline] ?? 0
        let shouldBroadcast = abs(restoredFraction - chromeFraction) > chromeEpsilon
        chromeFraction = restoredFraction
        chromeNeedsSync = true
        if shouldBroadcast {
            chromeFractionSubject.send(restoredFraction)
        }
        return restoredFraction
    }

    private func selectPresentedTimeline(_ timeline: TimelineType) {
        if presentedTimeline != timeline {
            pendingLayouts = pendingLayouts.filter { $0.value.includesRefreshCollapse }
            waitingForTop.removeAll()
            chromeNeedsSync = true
        }
        presentedTimeline = timeline
        updatePlaybackScopes()
    }

    func isPresented(_ timeline: TimelineType) -> Bool {
        presentedTimeline == timeline
    }

    func pullRefreshSubject(
        for timeline: TimelineType
    ) -> CurrentValueSubject<TimelinePullRefreshVisualState, Never> {
        if let subject = pullRefreshSubjects[timeline] {
            return subject
        }
        let subject = CurrentValueSubject<TimelinePullRefreshVisualState, Never>(.idle)
        pullRefreshSubjects[timeline] = subject
        return subject
    }

    /// Scroll the given timeline back to its top anchor. Uses that timeline's own proxy,
    /// so it always scrolls the visible page (not whichever one registered last).
    func scrollToTop(_ timeline: TimelineType) {
        guard active, isPresented(timeline) else { return }
        releaseHold(for: timeline) // The reader asked for the latest.
        settlingTop[timeline] = Date().addingTimeInterval(anchorSettleDuration)
        startSettleTicker()
        waitingForTop.insert(timeline)
        resetChrome()
        if let view = nativeScrollViews[timeline]?.value {
            // Direct local positioning avoids animating through hundreds of lazy rows.
            view.setContentOffset(CGPoint(x: view.contentOffset.x, y: -view.adjustedContentInset.top), animated: false)
            updateGeometry(for: timeline, headerHeight: headerHeights[timeline, default: 48])
        } else {
            proxies[timeline]?.scrollTo("timeline-top", anchor: .top)
        }
    }

    func restoreScrollPosition(_ timeline: TimelineType, targetID: String) {
        proxies[timeline]?.scrollTo(targetID, anchor: .top)
    }

    /// `isDragging`: a finger is on the timeline now (see `isUserDragging`).
    func updatePullRefreshDistance(
        _ distance: CGFloat,
        threshold: CGFloat,
        for timeline: TimelineType,
        isSelected: Bool,
        isDragging: Bool
    ) -> Bool {
        guard isSelected else { return false }
        var state = pullRefreshStates[timeline] ?? TimelinePullRefreshState()
        guard state.phase != .refreshing else { return false }
        // Only the reader's finger starts a pull. Jumping to the newest post, a lazy-row height
        // correction or a bounce can briefly overscroll the top; without this the slot would
        // open with them and push the rows down under a loading indicator.
        guard state.phase != .idle || isDragging else { return false }

        let wasArmed = state.phase == .armed
        state.distance = max(0, distance)
        if state.distance <= 0 {
            state.phase = .idle
        } else if state.distance >= threshold {
            state.phase = .armed
        } else {
            state.phase = .pulling
        }
        pullRefreshStates[timeline] = state
        let visual = TimelinePullRefreshVisualState(
            distance: state.distance,
            threshold: threshold,
            isRefreshing: false,
            isPinned: false
        )
        // Called on every scroll frame; while reading (distance 0) nothing changes.
        let subject = pullRefreshSubject(for: timeline)
        if subject.value != visual { subject.send(visual) }
        return state.phase == .armed && !wasArmed
    }

    func commitPullRefresh(
        for timeline: TimelineType,
        threshold: CGFloat,
        isSelected: Bool
    ) -> Bool {
        guard isSelected else { return false }
        var state = pullRefreshStates[timeline] ?? TimelinePullRefreshState()
        guard state.phase == .armed, state.distance >= threshold else {
            cancelUnarmedPullRefresh(for: timeline)
            return false
        }

        state.phase = .refreshing
        state.distance = threshold
        pullRefreshStates[timeline] = state
        pullRefreshSubject(for: timeline).send(
            TimelinePullRefreshVisualState(
                distance: threshold,
                threshold: threshold,
                isRefreshing: true,
                isPinned: true
            )
        )
        return true
    }

    /// Re-tapping the tab at the top: the same pinned slot a released pull leaves, so the
    /// refresh looks and finishes exactly like a pull. False while one is already running.
    func beginProgrammaticPullRefresh(
        for timeline: TimelineType,
        threshold: CGFloat,
        isSelected: Bool
    ) -> Bool {
        guard isSelected else { return false }
        var state = pullRefreshStates[timeline] ?? TimelinePullRefreshState()
        guard state.phase != .refreshing else { return false }
        state.phase = .refreshing
        state.distance = threshold
        pullRefreshStates[timeline] = state
        pullRefreshSubject(for: timeline).send(
            TimelinePullRefreshVisualState(
                distance: threshold,
                threshold: threshold,
                isRefreshing: true,
                isPinned: true
            )
        )
        return true
    }

    func cancelUnarmedPullRefresh(for timeline: TimelineType) {
        guard pullRefreshStates[timeline]?.phase != .refreshing else { return }
        finishPullRefresh(for: timeline)
    }

    func finishPullRefresh(
        for timeline: TimelineType,
        preserving fallbackAnchor: TimelineReadingAnchor? = nil,
        revision: UInt64 = 0
    ) {
        if pullRefreshSubject(for: timeline).value.isPinned,
            phases[timeline, default: .idle] != .idle {
            // Keep the off-screen slot until the reader's gesture settles. Its
            // collapse must not fight a drag or deceleration already in progress.
            pendingPullRefreshFinishes[timeline] = (fallbackAnchor, revision)
            return
        }
        pendingPullRefreshFinishes[timeline] = nil
        if pullRefreshSubject(for: timeline).value.isPinned, !isAtTop(timeline) {
            // Removing the 40pt refresh slot is a content-layout change too. Keep
            // the pre-update anchor if a head insertion is already being laid out.
            // Otherwise capture the current reader, or the saved off-screen reader.
            if pendingLayouts[timeline] == nil {
                let visible = readingAnchors(for: timeline)
                let anchors = visible.isEmpty ? fallbackAnchor.map { [$0] } ?? [] : visible
                if !anchors.isEmpty {
                    pendingLayouts[timeline] = PendingLayout(revision: revision,
                        anchors: anchors, followsLatest: false)
                }
            }
            pendingLayouts[timeline]?.includesRefreshCollapse = true
            pendingLayouts[timeline]?.waitsForRefreshCollapse = true
        }
        pullRefreshStates[timeline] = TimelinePullRefreshState()
        pullRefreshSubject(for: timeline).send(.idle)
    }

    func pullRefreshSlotDidCollapse(for timeline: TimelineType) {
        guard pendingLayouts[timeline]?.waitsForRefreshCollapse == true else { return }
        pendingLayouts[timeline]?.waitsForRefreshCollapse = false
        scheduleLayoutEvent(for: timeline)
    }
}

final class TimelineScrollResolverView: UIView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    weak var bridge: TimelineScrollBridge?
    var timeline: TimelineType = .home

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        resolveScrollView()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        resolveScrollView()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        resolveScrollView()
    }

    private func resolveScrollView() {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                bridge?.register(scrollView, for: timeline)
                return
            }
            ancestor = current.superview
        }

    }
}

final class TimelineRowAnchorView: UIView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    weak var bridge: TimelineScrollBridge?
    var timeline: TimelineType = .home
    var statusID = ""
    var revision: UInt64 = 0
    private(set) var laidOutRevision: UInt64 = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        laidOutRevision = revision
        bridge?.rowDidLayout(self, for: timeline)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { setNeedsLayout() }
    }
}

struct TimelineRowAnchor: UIViewRepresentable {
    let statusID: String
    let timeline: TimelineType
    let revision: UInt64
    let bridge: TimelineScrollBridge

    func makeUIView(context: Context) -> TimelineRowAnchorView {
        let view = TimelineRowAnchorView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }
    func updateUIView(_ view: TimelineRowAnchorView, context: Context) {
        let changed = view.statusID != statusID || view.timeline != timeline || view.revision != revision
        view.statusID = statusID
        view.timeline = timeline
        view.bridge = bridge
        view.revision = revision
        if changed { view.setNeedsLayout() }
    }
}

struct TimelineScrollViewResolver: UIViewRepresentable {
    let timeline: TimelineType
    let bridge: TimelineScrollBridge

    func makeUIView(context: Context) -> TimelineScrollResolverView {
        let view = TimelineScrollResolverView()
        view.timeline = timeline
        view.bridge = bridge
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: TimelineScrollResolverView, context: Context) {
        uiView.timeline = timeline
        uiView.bridge = bridge
    }
}


/// CADisplayLink retains its target; this small target keeps the bridge itself out of
/// that cycle and is released when the settle ticker is invalidated.
private final class TimelineSettleTickTarget: NSObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func tick() { action() }
}
