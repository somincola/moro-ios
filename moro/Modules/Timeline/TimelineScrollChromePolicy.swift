//
//  TimelineScrollChromePolicy.swift
//  moro
//
//  Pure value-type scroll policies for the home timeline's collapsing header and
//  auto-hiding compose button. Kept UI-free so every gesture edge case is
//  deterministically unit-testable.
//

import CoreGraphics
import SwiftUI

/// Snapshot describing how the home timeline's floating header should render.
struct TimelineChromeState: Equatable, Sendable {
    /// `0` = fully visible, `1` = fully collapsed above the viewport.
    var headerFraction: CGFloat = 0
    /// `true` when scrolled past the top of the feed (strengthens the header hairline).
    var isScrolledFromTop: Bool = false
    /// `true` when transitioning via a settle snap or reset so the view animates smoothly.
    var isAnimated: Bool = false

    static let expanded = TimelineChromeState()
}

/// Interactive scroll policy for the home timeline header.
///
/// Tracks `minY`-style scroll offsets (`0` at top, negative scrolling down, positive pulling down):
/// - Follows the finger 1:1 while scrolling so the header feels attached to content.
/// - Clamps pull-to-refresh overscroll rebound (`> 0` returning to `0`) so releasing a pull
///   never collapses the header.
/// - Snaps partial fractions cleanly to `0` or `1` when scrolling settles to `.idle`, using
///   directional hysteresis and keeping the header open near the top of the feed.
struct TimelineHeaderScrollPolicy: Sendable {
    enum Direction: Equatable, Sendable {
        case none
        case down
        case up
    }

    private(set) var state = TimelineChromeState.expanded
    private var lastOffset: CGFloat = 0
    private var needsBaselineSync = false
    private var lastDirection: Direction = .none

    private let jitterThreshold: CGFloat = 0.25
    private let fractionEpsilon: CGFloat = 0.0005

    /// Update the header fraction from a new `minY`-style offset.
    /// `minOffset` (optional, `<= 0`) is the deepest resting offset (`-maxScrollDown`); any
    /// rubber-band overscroll past `minOffset` and its rebound back to `minOffset` are clamped
    /// so hitting the bottom of a feed never falsely reopens the collapsed header.
    /// Returns a new `TimelineChromeState` when the visual state changed.
    mutating func update(
        offset: CGFloat,
        headerHeight: CGFloat,
        minOffset: CGFloat? = nil,
        isUserDriving: Bool = true,
        assistiveLocked: Bool = false
    ) -> TimelineChromeState? {
        if assistiveLocked {
            lastOffset = offset
            return resetIfNeeded(animated: true)
        }

        if needsBaselineSync {
            needsBaselineSync = false
            lastOffset = offset
            let scrolled = offset < -4
            if state.isScrolledFromTop != scrolled {
                state = TimelineChromeState(
                    headerFraction: state.headerFraction,
                    isScrolledFromTop: scrolled,
                    isAnimated: false
                )
                return state
            }
            return nil
        }

        // Clamp both top pull-to-refresh overscroll (> 0) and bottom rubber-band bounce (< minOffset).
        let lowerBound = min(minOffset ?? -.greatestFiniteMagnitude, 0)
        let effectivePrevious = min(max(lastOffset, lowerBound), 0)
        let effectiveCurrent = min(max(offset, lowerBound), 0)
        lastOffset = offset

        let isScrolled = offset < -4
        if offset >= 0 {
            lastDirection = .up
            return applyState(
                TimelineChromeState(
                    headerFraction: 0,
                    isScrolledFromTop: false,
                    isAnimated: false
                )
            )
        }

        guard headerHeight > 0 else {
            return applyState(
                TimelineChromeState(
                    headerFraction: 0,
                    isScrolledFromTop: isScrolled,
                    isAnimated: false
                )
            )
        }

        let delta = effectiveCurrent - effectivePrevious
        guard abs(delta) > jitterThreshold else {
            if state.isScrolledFromTop != isScrolled {
                return applyState(
                    TimelineChromeState(
                        headerFraction: state.headerFraction,
                        isScrolledFromTop: isScrolled,
                        isAnimated: false
                    )
                )
            }
            return nil
        }

        // Never collapse the header from programmatic layout adjustments or reading-position
        // restores; upward motion (such as status-bar scroll-to-top) always expands it.
        if delta < 0, !isUserDriving {
            if state.isScrolledFromTop != isScrolled {
                return applyState(
                    TimelineChromeState(
                        headerFraction: state.headerFraction,
                        isScrolledFromTop: isScrolled,
                        isAnimated: false
                    )
                )
            }
            return nil
        }

        lastDirection = delta < 0 ? .down : .up
        let nextFraction = min(max(state.headerFraction - delta / headerHeight, 0), 1)
        return applyState(
            TimelineChromeState(
                headerFraction: nextFraction,
                isScrolledFromTop: isScrolled,
                isAnimated: false
            )
        )
    }

    /// Snap any half-collapsed header to fully open or fully hidden once scrolling stops.
    mutating func settle(
        offset: CGFloat,
        headerHeight: CGFloat,
        assistiveLocked: Bool = false
    ) -> TimelineChromeState? {
        if assistiveLocked {
            return resetIfNeeded(animated: true)
        }
        guard headerHeight > 0 else { return nil }
        guard state.headerFraction > fractionEpsilon,
            state.headerFraction < 1 - fractionEpsilon
        else { return nil }

        let targetFraction: CGFloat
        if offset > -headerHeight * 1.15 {
            // Keep the header visible near the very top of the feed.
            targetFraction = 0
        } else {
            switch lastDirection {
            case .up:
                // Revealing 30% on an upward drag commits to opening.
                targetFraction = state.headerFraction <= 0.70 ? 0 : 1
            case .down:
                // Hiding 35% on a downward drag commits to collapsing.
                targetFraction = state.headerFraction >= 0.35 ? 1 : 0
            case .none:
                targetFraction = state.headerFraction >= 0.5 ? 1 : 0
            }
        }

        let next = TimelineChromeState(
            headerFraction: targetFraction,
            isScrolledFromTop: offset < -4,
            isAnimated: true
        )
        return applyState(next)
    }

    /// Snap back to fully visible and resync the next scroll baseline.
    mutating func reset(animated: Bool = true) -> TimelineChromeState? {
        needsBaselineSync = true
        lastDirection = .none
        return resetIfNeeded(animated: animated)
    }

    /// Adopt the next incoming scroll offset without accumulating a jump.
    mutating func syncBaseline() {
        needsBaselineSync = true
        lastDirection = .none
    }

    private mutating func resetIfNeeded(animated: Bool) -> TimelineChromeState? {
        let target = TimelineChromeState(
            headerFraction: 0,
            isScrolledFromTop: false,
            isAnimated: animated
        )
        return applyState(target)
    }

    private mutating func applyState(_ next: TimelineChromeState) -> TimelineChromeState? {
        let fractionChanged = abs(next.headerFraction - state.headerFraction) > fractionEpsilon
        let scrollEdgeChanged = next.isScrolledFromTop != state.isScrolledFromTop
        guard fractionChanged || scrollEdgeChanged else { return nil }
        state = next
        return next
    }
}

/// Scroll-driven visibility policy for the home floating compose button.
///
/// Behavior:
/// - Hides smoothly after intentional downward travel (`>= 28pt`) below the top.
/// - Reappears immediately on upward scroll (`>= 10pt`) or when returning near the top.
/// - Schedules a delayed reveal (`420ms`) once scrolling becomes `.idle`, cancelling that
///   timer if the user resumes scrolling before it fires so the button never flickers.
struct ComposeButtonScrollPolicy: Sendable {
    enum IdleTimerEffect: Equatable, Sendable {
        case none
        case scheduleReveal
        case cancelReveal
    }

    struct Update: Equatable, Sendable {
        let isVisible: Bool
        let visibilityChanged: Bool
        let idleTimer: IdleTimerEffect
    }

    static let defaultIdleRevealDelayNanoseconds: UInt64 = 420_000_000

    let hideDownwardThreshold: CGFloat
    let showUpwardThreshold: CGFloat
    let topAlwaysVisibleOffset: CGFloat

    private(set) var isVisible = true
    private var lastOffset: CGFloat = 0
    private var needsBaselineSync = false
    private var downwardTravel: CGFloat = 0
    private var upwardTravel: CGFloat = 0

    private let jitterThreshold: CGFloat = 0.25

    init(
        hideDownwardThreshold: CGFloat = 28,
        showUpwardThreshold: CGFloat = 10,
        topAlwaysVisibleOffset: CGFloat = -12
    ) {
        self.hideDownwardThreshold = hideDownwardThreshold
        self.showUpwardThreshold = showUpwardThreshold
        self.topAlwaysVisibleOffset = topAlwaysVisibleOffset
    }

    mutating func update(
        offset: CGFloat,
        minOffset: CGFloat? = nil,
        isUserDriving: Bool,
        assistiveLocked: Bool = false
    ) -> Update {
        if assistiveLocked {
            lastOffset = offset
            return forceVisible()
        }

        if needsBaselineSync {
            needsBaselineSync = false
            lastOffset = offset
            downwardTravel = 0
            upwardTravel = 0
            return Update(isVisible: isVisible, visibilityChanged: false, idleTimer: .none)
        }

        let lowerBound = min(minOffset ?? -.greatestFiniteMagnitude, 0)
        let effectivePrevious = min(max(lastOffset, lowerBound), 0)
        let effectiveCurrent = min(max(offset, lowerBound), 0)
        lastOffset = offset

        if offset >= topAlwaysVisibleOffset {
            downwardTravel = 0
            upwardTravel = 0
            return forceVisible()
        }

        let delta = effectiveCurrent - effectivePrevious
        guard abs(delta) > jitterThreshold else {
            return Update(isVisible: isVisible, visibilityChanged: false, idleTimer: .none)
        }

        if delta < 0 {
            downwardTravel += -delta
            upwardTravel = 0
            if isUserDriving, isVisible, downwardTravel >= hideDownwardThreshold {
                isVisible = false
                return Update(isVisible: false, visibilityChanged: true, idleTimer: .cancelReveal)
            }
            return Update(isVisible: isVisible, visibilityChanged: false, idleTimer: .none)
        } else {
            upwardTravel += delta
            downwardTravel = 0
            if !isVisible, upwardTravel >= showUpwardThreshold {
                isVisible = true
                return Update(isVisible: true, visibilityChanged: true, idleTimer: .cancelReveal)
            }
            return Update(isVisible: isVisible, visibilityChanged: false, idleTimer: .none)
        }
    }

    mutating func phaseChanged(
        _ phase: ScrollPhase,
        assistiveLocked: Bool = false
    ) -> Update {
        if assistiveLocked {
            return forceVisible()
        }
        switch phase {
        case .idle:
            downwardTravel = 0
            upwardTravel = 0
            if !isVisible {
                return Update(isVisible: false, visibilityChanged: false, idleTimer: .scheduleReveal)
            }
            return Update(isVisible: true, visibilityChanged: false, idleTimer: .none)
        case .tracking, .interacting, .decelerating:
            return Update(isVisible: isVisible, visibilityChanged: false, idleTimer: .cancelReveal)
        case .animating:
            return Update(isVisible: isVisible, visibilityChanged: false, idleTimer: .none)
        }
    }

    mutating func idleRevealFired() -> Update {
        downwardTravel = 0
        upwardTravel = 0
        guard !isVisible else {
            return Update(isVisible: true, visibilityChanged: false, idleTimer: .none)
        }
        isVisible = true
        return Update(isVisible: true, visibilityChanged: true, idleTimer: .none)
    }

    mutating func reset() -> Update {
        needsBaselineSync = true
        downwardTravel = 0
        upwardTravel = 0
        return forceVisible()
    }

    mutating func syncBaseline() {
        needsBaselineSync = true
        downwardTravel = 0
        upwardTravel = 0
    }

    private mutating func forceVisible() -> Update {
        let changed = !isVisible
        isVisible = true
        return Update(
            isVisible: true,
            visibilityChanged: changed,
            idleTimer: .cancelReveal
        )
    }
}
