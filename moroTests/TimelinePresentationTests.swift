import Combine
import SwiftUI
import Testing
import UIKit
@testable import moro

@Suite(.serialized) @MainActor
struct TimelinePresentationTests {
    @Test(arguments: 0..<3, 0..<3)
    func switchingRegistersTheDisplayedPageBeforeSuspending(fromIndex: Int, toIndex: Int) {
        let from = TimelineType.builtin[fromIndex]
        let to = TimelineType.builtin[toIndex]
        guard from != to else { return }
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 400, height: 3000)
        window.addSubview(scroll)
        window.isHidden = false
        defer { window.isHidden = true }
        let bridge = TimelineScrollBridge()
        bridge.setActive(true)
        bridge.register(scroll, for: to)
        bridge.setPresentedTimeline(from)
        bridge.setFrozen(true, for: from)
        bridge.updatePhase(.decelerating, for: to)

        let presentation = bridge.beginPresentation(for: to)
        #expect(bridge.isPresented(to))
        #expect(!bridge.isPresented(from))
        #expect(!bridge.canPresentUpdates(for: to))
        #expect(bridge.finishPresentation(presentation))
        #expect(bridge.canPresentUpdates(for: to))

        scroll.contentOffset.y = 600
        bridge.scrollToTop(from)
        #expect(scroll.contentOffset.y == 600)
        bridge.scrollToTop(to)
        #expect(scroll.contentOffset.y == -scroll.adjustedContentInset.top)
        #expect(bridge.commitPullRefresh(for: to, threshold: 40, isSelected: true) == false)
        #expect(bridge.updatePullRefreshDistance(60, threshold: 40, for: to, isSelected: true, isDragging: true))
        #expect(bridge.commitPullRefresh(for: to, threshold: 40, isSelected: true))
        bridge.finishPullRefresh(for: to)
    }

    @Test func supersededTasksCannotFinishANewerPresentationOfTheSamePage() {
        let bridge = TimelineScrollBridge()
        let first = bridge.beginPresentation(for: .home)
        let second = bridge.beginPresentation(for: .local)
        let latest = bridge.beginPresentation(for: .home)
        #expect(!bridge.isCurrentPresentation(first))
        #expect(!bridge.finishPresentation(first))
        #expect(!bridge.finishPresentation(second))
        #expect(bridge.isCurrentPresentation(latest))
        #expect(bridge.finishPresentation(latest))
        #expect(!bridge.finishPresentation(latest))
        #expect(bridge.isPresented(.home))
    }

    @Test func appearingDoesNotCancelThePagersPendingPositionRestoration() {
        let bridge = TimelineScrollBridge()
        let presentation = bridge.beginPresentation(for: .federated)
        bridge.resumePresentation(for: .federated)
        #expect(bridge.isCurrentPresentation(presentation))
        #expect(bridge.finishPresentation(presentation))
        bridge.setActive(false)
        bridge.setActive(true)
        bridge.resumePresentation(for: .federated)
        #expect(bridge.isPresented(.federated))
    }

    @Test func finishingBeforeTheScrollViewRegistersDoesNotLeaveThePageFrozen() {
        let bridge = TimelineScrollBridge()
        bridge.setActive(true)
        let presentation = bridge.beginPresentation(for: .local)
        #expect(bridge.finishPresentation(presentation))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        window.addSubview(scroll)
        window.isHidden = false
        defer { window.isHidden = true }
        bridge.register(scroll, for: .local)
        #expect(bridge.canPresentUpdates(for: .local))
    }

    @Test func refreshFinishWaitsForTheReadersGestureToSettle() async {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 400, height: 3000)
        window.addSubview(scroll)
        window.isHidden = false
        defer { window.isHidden = true }
        let bridge = TimelineScrollBridge()
        bridge.setActive(true)
        bridge.register(scroll, for: .home)
        #expect(bridge.updatePullRefreshDistance(60, threshold: 40, for: .home, isSelected: true, isDragging: true))
        #expect(bridge.commitPullRefresh(for: .home, threshold: 40, isSelected: true))
        bridge.updatePhase(.interacting, for: .home)
        bridge.finishPullRefresh(for: .home)
        #expect(bridge.pullRefreshSubject(for: .home).value.isRefreshing)
        let events = AsyncStream<TimelineType>.makeStream()
        let subscription = bridge.layoutEvents.sink { events.continuation.yield($0) }
        defer { subscription.cancel() }
        var iterator = events.stream.makeAsyncIterator()
        bridge.updatePhase(.idle, for: .home)
        _ = await iterator.next()
        #expect(!bridge.pullRefreshSubject(for: .home).value.isRefreshing)
    }

    @Test(arguments: [false, true], [false, true])
    func refreshCollapsePreservesTheReaderAfterLayout(insertsHead: Bool, switchesAway: Bool) async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 400, height: 3000)
        window.addSubview(scroll)
        window.isHidden = false
        defer { window.isHidden = true }
        let bridge = TimelineScrollBridge()
        bridge.setActive(true)
        bridge.setPresentedTimeline(.local)
        bridge.register(scroll, for: .local)
        let row = TimelineRowAnchorView(frame: CGRect(x: 0, y: 680, width: 400, height: 200))
        row.statusID = "reader"
        row.timeline = .local
        row.bridge = bridge
        scroll.addSubview(row)
        scroll.contentOffset.y = 500
        bridge.updateGeometry(for: .local, headerHeight: 48)
        row.setNeedsLayout()
        row.layoutIfNeeded()
        let events = AsyncStream<TimelineType>.makeStream()
        let subscription = bridge.layoutEvents.sink { events.continuation.yield($0) }
        defer { subscription.cancel() }
        var iterator = events.stream.makeAsyncIterator()
        let anchor = try #require(bridge.readingAnchors(for: .local).first)
        #expect(bridge.updatePullRefreshDistance(60, threshold: 40, for: .local, isSelected: true, isDragging: true))
        #expect(bridge.commitPullRefresh(for: .local, threshold: 40, isSelected: true))
        if insertsHead {
            #expect(bridge.prepareContentUpdate(for: .local, revision: 1, retainedIDs: ["reader"]))
        }
        bridge.finishPullRefresh(for: .local, preserving: anchor, revision: insertsHead ? 1 : 0)
        row.frame.origin.y += insertsHead ? 160 : -40
        row.revision = insertsHead ? 1 : 0
        row.setNeedsLayout()
        row.layoutIfNeeded()
        _ = await iterator.next()
        #expect(scroll.contentOffset.y == 500, "Wait for the slot's actual collapsed layout")
        if switchesAway {
            bridge.setFrozen(true, for: .local)
            bridge.setActive(false)
            bridge.setPresentedTimeline(.home)
        }
        bridge.pullRefreshSlotDidCollapse(for: .local)
        _ = await iterator.next()
        if switchesAway {
            #expect(scroll.contentOffset.y == 500)
            bridge.setActive(true)
            let presentation = bridge.beginPresentation(for: .local)
            bridge.finishPresentation(presentation)
            // A home layout may already be queued; wait for the returning page.
            while let timeline = await iterator.next(), timeline != .local {}
        }
        #expect(bridge.readingAnchors(for: .local).first?.viewportOffset == anchor.viewportOffset)
        #expect(bridge.canPresentUpdates(for: .local))
    }
}
