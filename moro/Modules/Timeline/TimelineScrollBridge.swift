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

struct TimelinePullRefreshVisualState {
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
    private final class WeakScrollView {
        weak var value: UIScrollView?

        init(_ value: UIScrollView) {
            self.value = value
        }
    }

    /// Whether each timeline is scrolled to the very top.
    @Published var atTop: [TimelineType: Bool] = [.home: true, .local: true, .federated: true]

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

    func isAtTop(_ timeline: TimelineType) -> Bool { atTop[timeline] ?? true }

    func setAtTop(_ value: Bool, for timeline: TimelineType) {
        guard atTop[timeline] != value else { return }
        atTop[timeline] = value
    }

    func register(_ proxy: ScrollViewProxy, for timeline: TimelineType) {
        proxies[timeline] = proxy
    }

    func register(_ scrollView: UIScrollView, for timeline: TimelineType) {
        nativeScrollViews[timeline] = WeakScrollView(scrollView)
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
        presentedTimeline = timeline
        let restoredFraction = chromeFractions[timeline] ?? 0
        let shouldBroadcast = abs(restoredFraction - chromeFraction) > chromeEpsilon
        chromeFraction = restoredFraction
        chromeNeedsSync = true
        if shouldBroadcast {
            chromeFractionSubject.send(restoredFraction)
        }
        return restoredFraction
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
        proxies[timeline]?.scrollTo("timeline-top", anchor: .top)
    }

    func restoreScrollPosition(_ timeline: TimelineType, targetID: String) {
        proxies[timeline]?.scrollTo(targetID, anchor: .top)
    }

    func updatePullRefreshDistance(
        _ distance: CGFloat,
        threshold: CGFloat,
        for timeline: TimelineType,
        isSelected: Bool
    ) -> Bool {
        guard isSelected else { return false }
        var state = pullRefreshStates[timeline] ?? TimelinePullRefreshState()
        guard state.phase != .refreshing else { return false }

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
        pullRefreshSubject(for: timeline).send(
            TimelinePullRefreshVisualState(
                distance: state.distance,
                threshold: threshold,
                isRefreshing: false,
                isPinned: false
            )
        )
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

    func cancelUnarmedPullRefresh(for timeline: TimelineType) {
        guard pullRefreshStates[timeline]?.phase != .refreshing else { return }
        finishPullRefresh(for: timeline)
    }

    func finishPullRefresh(for timeline: TimelineType) {
        pullRefreshStates[timeline] = TimelinePullRefreshState()
        pullRefreshSubject(for: timeline).send(.idle)
    }
}

final class TimelineScrollResolverView: UIView {
    weak var bridge: TimelineScrollBridge?
    var timeline: TimelineType = .home
    private var remainingResolveAttempts = 8

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

        guard remainingResolveAttempts > 0 else { return }
        remainingResolveAttempts -= 1
        DispatchQueue.main.async { [weak self] in
            guard self?.window != nil else { return }
            self?.resolveScrollView()
        }
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
