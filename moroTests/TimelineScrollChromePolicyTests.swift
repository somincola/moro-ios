//
//  TimelineScrollChromePolicyTests.swift
//  moroTests
//
//  Tests for the home timeline collapsing header policy, scroll-driven compose button
//  visibility policy, and TimelineScrollBridge integration.
//

import Combine
import CoreGraphics
import SwiftUI
import Testing
import XCTest
@testable import moro

@MainActor
struct TimelineScrollChromePolicyTests {
    @Test func headerCollapsesInteractivelyOnDownwardScrollAndExpandsOnUpwardScroll() {
        var policy = TimelineHeaderScrollPolicy()

        let mid = policy.update(offset: -24, headerHeight: 48)
        #expect(mid != nil)
        #expect(abs((mid?.headerFraction ?? 0) - 0.5) < 0.001)
        #expect(mid?.isScrolledFromTop == true)
        #expect(mid?.isAnimated == false)

        let hidden = policy.update(offset: -60, headerHeight: 48)
        #expect(hidden?.headerFraction == 1)
        #expect(hidden?.isAnimated == false)

        // Small upward scroll reveals proportionally.
        let revealing = policy.update(offset: -36, headerHeight: 48)
        #expect(abs((revealing?.headerFraction ?? 0) - 0.5) < 0.001)

        // Returning to top always restores fraction = 0.
        let top = policy.update(offset: 0, headerHeight: 48)
        #expect(top?.headerFraction == 0)
        #expect(top?.isScrolledFromTop == false)
    }

    @Test func pullToRefreshReboundNeverCollapsesHeader() {
        var policy = TimelineHeaderScrollPolicy()

        // Pull down past top (+56pt) then rebound past 0 to -3pt.
        _ = policy.update(offset: 56, headerHeight: 48)
        #expect(policy.state.headerFraction == 0)

        let reboundAtZero = policy.update(offset: 0, headerHeight: 48)
        #expect(reboundAtZero == nil)
        #expect(policy.state.headerFraction == 0)

        let slightOvershoot = policy.update(offset: -3, headerHeight: 48)
        // Only -3 / 48 = 0.0625 instead of -59 / 48 = 1.0!
        #expect((slightOvershoot?.headerFraction ?? 0) < 0.1)
    }

    @Test func headerSettleSnapsWithDirectionalHysteresisAndStaysOpenNearTop() {
        var policy = TimelineHeaderScrollPolicy()

        // Barely scrolled past top: settle snaps back open even past 50%.
        _ = policy.update(offset: -32, headerHeight: 48)
        let nearTopSnap = policy.settle(offset: -32, headerHeight: 48)
        #expect(nearTopSnap?.headerFraction == 0)
        #expect(nearTopSnap?.isAnimated == true)

        // Deeper in feed: hiding >= 35% downward commits to collapsed.
        _ = policy.update(offset: -100, headerHeight: 48, isUserDriving: false)
        _ = policy.update(offset: -120, headerHeight: 48, isUserDriving: true) // ~41.7%
        let downSnap = policy.settle(offset: -120, headerHeight: 48)
        #expect(downSnap?.headerFraction == 1)
        #expect(downSnap?.isAnimated == true)

        // Upward drag revealing >= 30% commits to fully open.
        _ = policy.update(offset: -104, headerHeight: 48, isUserDriving: true) // 1 - 16/48 = 0.667 <= 0.70
        let upSnap = policy.settle(offset: -104, headerHeight: 48)
        #expect(upSnap?.headerFraction == 0)
        #expect(upSnap?.isAnimated == true)
    }

    @Test func bottomRubberBandBounceNeverReopensHeaderOrComposeButton() {
        var headerPolicy = TimelineHeaderScrollPolicy()
        var composePolicy = ComposeButtonScrollPolicy()
        let bottomLimit: CGFloat = -460

        _ = headerPolicy.update(offset: -460, headerHeight: 48, minOffset: bottomLimit)
        _ = composePolicy.update(offset: -460, minOffset: bottomLimit, isUserDriving: true)
        #expect(headerPolicy.state.headerFraction == 1)
        #expect(composePolicy.isVisible == false)

        // Overscrolling past the bottom (-560) and rebounding back to -460 must not reopen chrome.
        _ = headerPolicy.update(offset: -560, headerHeight: 48, minOffset: bottomLimit)
        _ = composePolicy.update(offset: -560, minOffset: bottomLimit, isUserDriving: true)
        _ = headerPolicy.update(offset: -460, headerHeight: 48, minOffset: bottomLimit)
        let rebound = composePolicy.update(offset: -460, minOffset: bottomLimit, isUserDriving: true)
        #expect(headerPolicy.state.headerFraction == 1)
        #expect(rebound.isVisible == false)

        // Intentional upward drag above the bottom edge immediately reveals both.
        let headerUp = headerPolicy.update(offset: -412, headerHeight: 48, minOffset: bottomLimit)
        let composeUp = composePolicy.update(offset: -412, minOffset: bottomLimit, isUserDriving: true)
        #expect(headerUp?.headerFraction == 0)
        #expect(composeUp.isVisible == true)
    }

    @Test func programmaticOffsetJumpDoesNotCollapseHeader() {
        var policy = TimelineHeaderScrollPolicy()

        let restored = policy.update(offset: -400, headerHeight: 48, isUserDriving: false)
        #expect(restored?.headerFraction == 0)
        #expect(restored?.isScrolledFromTop == true)
    }

    @Test func composeButtonHidesOnDownwardScrollRevealsImmediatelyOnUpwardScrollAndSchedulesIdleReveal() {
        var policy = ComposeButtonScrollPolicy()

        // Small nudge below hide threshold keeps button visible.
        let smallDown = policy.update(offset: -20, isUserDriving: true)
        #expect(smallDown.isVisible == true)
        #expect(smallDown.visibilityChanged == false)

        // Crossing 28pt downward travel hides the compose button.
        let hideUpdate = policy.update(offset: -40, isUserDriving: true)
        #expect(hideUpdate.isVisible == false)
        #expect(hideUpdate.visibilityChanged == true)
        #expect(hideUpdate.idleTimer == .cancelReveal)

        // Stopping scroll schedules a delayed reveal.
        let idleUpdate = policy.phaseChanged(.idle)
        #expect(idleUpdate.isVisible == false)
        #expect(idleUpdate.idleTimer == .scheduleReveal)

        // Resuming scroll before the timer fires cancels the reveal so the button never flickers.
        let resumedUpdate = policy.phaseChanged(.interacting)
        #expect(resumedUpdate.isVisible == false)
        #expect(resumedUpdate.idleTimer == .cancelReveal)

        // An upward scroll of >= 10pt immediately reveals the compose button.
        let upwardReveal = policy.update(offset: -28, isUserDriving: true)
        #expect(upwardReveal.isVisible == true)
        #expect(upwardReveal.visibilityChanged == true)
        #expect(upwardReveal.idleTimer == .cancelReveal)
    }

    @Test func composeButtonRevealsWhenIdleTimerFiresAndStaysLockedUnderAssistiveTech() {
        var policy = ComposeButtonScrollPolicy()

        _ = policy.update(offset: -60, isUserDriving: true)
        #expect(policy.isVisible == false)

        let scheduled = policy.phaseChanged(.idle)
        #expect(scheduled.idleTimer == .scheduleReveal)

        let fired = policy.idleRevealFired()
        #expect(fired.isVisible == true)
        #expect(fired.visibilityChanged == true)

        // Assistive mode always keeps compose visible.
        let assistiveDown = policy.update(offset: -200, isUserDriving: true, assistiveLocked: true)
        #expect(assistiveDown.isVisible == true)
        #expect(assistiveDown.visibilityChanged == false)
    }

    @Test func scrollBridgeCoordinatesHeaderSnapAndDelayedComposeReveal() async throws {
        let bridge = TimelineScrollBridge()
        bridge.composeIdleRevealDelayNanoseconds = 10_000_000
        bridge.setActive(true)
        _ = bridge.setPresentedTimeline(.home)

        var chromeStates: [TimelineChromeState] = []
        var composeEvents: [Bool] = []
        var cancellables: Set<AnyCancellable> = []

        bridge.chromeStateSubject.sink { chromeStates.append($0) }.store(in: &cancellables)
        bridge.composeVisibilitySubject.sink { composeEvents.append($0) }.store(in: &cancellables)

        // Establish resting top baseline before dragging downward.
        _ = bridge.updateChrome(offset: 0, headerHeight: 48, timeline: .home, isSelected: true)

        bridge.updatePhase(.interacting, for: .home)
        _ = bridge.updateChrome(offset: -80, headerHeight: 48, timeline: .home, isSelected: true)
        #expect(bridge.currentChromeState.headerFraction == 1)
        #expect(bridge.isComposeButtonVisible == false)
        #expect(composeEvents == [false])

        // Partial upward drag then release: header snaps open and compose button reveals immediately.
        _ = bridge.updateChrome(offset: -62, headerHeight: 48, timeline: .home, isSelected: true)
        #expect(bridge.isComposeButtonVisible == true)
        #expect(composeEvents == [false, true])

        bridge.offsets[.home] = -62
        bridge.updatePhase(.idle, for: .home)
        #expect(bridge.currentChromeState.headerFraction == 0)
        #expect(chromeStates.last?.isAnimated == true)

        // Scroll down again and observe the next reveal, after the transition to idle.
        bridge.updatePhase(.interacting, for: .home)
        _ = bridge.updateChrome(offset: -140, headerHeight: 48, timeline: .home, isSelected: true)
        #expect(bridge.isComposeButtonVisible == false)

        bridge.offsets[.home] = -140
        let idleReveal = XCTestExpectation(description: "Compose becomes visible after scrolling stops")
        bridge.composeVisibilitySubject.filter { $0 }.first().sink { _ in idleReveal.fulfill() }
            .store(in: &cancellables)
        bridge.updatePhase(.idle, for: .home)
        let result = await XCTWaiter.fulfillment(of: [idleReveal], timeout: 60)
        #expect(result == .completed)
        #expect(bridge.isComposeButtonVisible == true)
    }
}
