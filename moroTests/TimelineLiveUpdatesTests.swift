import Foundation
import Testing
import UIKit
import SwiftUI
import Combine
@testable import moro

@Suite(.serialized) @MainActor
struct TimelineLiveUpdatesTests {
    private func post(_ id: String, own: Bool = false) -> Status {
        ThreadReadingFixtures.status(id, own: own, content: "<p>Complete body \(id)</p>")
    }

    @Test func fullBodiesMergeWithoutDuplicateEventsOrLosingTheirContent() {
        var state = TimelineLiveUpdates(statuses: [post("100")])
        state.receive(post("101"), currentAccountID: nil)
        state.receive(post("101"), currentAccountID: nil)
        state.receiveHead(TimelinePage(statuses: [post("102"), post("101")]), sinceID: "100", currentAccountID: nil)
        #expect(state.statuses.map(\.id) == ["102", "101", "100"])
        #expect(state.newCount == 2)
        #expect(state.statuses.first?.content == "<p>Complete body 102</p>")
        #expect(state.metadata.checkpointID == "100")
    }

    @Test func ownPostNeverSkipsAnUnfetchedRemotePost() {
        var state = TimelineLiveUpdates(statuses: [post("100")])
        state.receive(post("102", own: true), currentAccountID: ThreadReadingFixtures.author.id)
        #expect(state.newCount == 0)
        #expect(state.metadata.fetchedHeadID == "100")
        state.receiveHead(TimelinePage(statuses: [post("102", own: true), post("101")]), sinceID: "100", currentAccountID: ThreadReadingFixtures.author.id)
        #expect(state.statuses.map(\.id) == ["102", "101", "100"])
        #expect(state.newCount == 1)
        #expect(state.metadata.checkpointID == "100")
    }

    @Test func lateRestPageKeepsNewerLocalRowsAboveItsOldBaseline() {
        var state = TimelineLiveUpdates(statuses: [post("100")])
        state.receive(post("102", own: true), currentAccountID: ThreadReadingFixtures.author.id)
        state.receiveHead(TimelinePage(statuses: [post("101")]), sinceID: "100", currentAccountID: nil)
        #expect(state.statuses.map(\.id) == ["102", "101", "100"])
    }

    @Test func onlyAcknowledgedBatchClearsAndLateGapPostsStayHistorical() throws {
        var state = TimelineLiveUpdates(statuses: [post("100")])
        state.receiveHead(TimelinePage(statuses: [post("104"), post("103")]), sinceID: "100", currentAccountID: nil)
        let firstSequence = state.metadata.sequence
        let gap = try #require(state.metadata.gaps.first)
        state.receive(post("105"), currentAccountID: nil)
        state.acknowledge(through: firstSequence)
        #expect(state.newCount == 1)
        let progressed1 = state.fillGap(gap.id, page: TimelinePage(statuses: [post("102"), post("101")]), currentAccountID: nil)
        #expect(progressed1)
        #expect(state.newCount == 1)
        #expect(state.metadata.checkpointID == "100")
        let progressed2 = state.fillGap(gap.id, page: TimelinePage(statuses: []), currentAccountID: nil)
        #expect(progressed2)
        #expect(state.metadata.checkpointID == "104")
        #expect(state.statuses.map(\.id) == ["105", "104", "103", "102", "101", "100"])
    }

    @Test func partialAndRepeatedPagesNeverFalselyCloseAGap() throws {
        var state = TimelineLiveUpdates(statuses: [post("100")])
        state.receiveHead(TimelinePage(statuses: [post("104")], isPartial: true), sinceID: "100", currentAccountID: nil)
        let gap = try #require(state.metadata.gaps.first)
        #expect(state.metadata.fetchedHeadID == "100")
        let progressed3 = !state.fillGap(gap.id, page: TimelinePage(statuses: [], isPartial: true), currentAccountID: nil)
        #expect(progressed3)
        let progressed4 = !state.fillGap(gap.id, page: TimelinePage(statuses: [post("104")]), currentAccountID: nil)
        #expect(progressed4)
        #expect(state.metadata.gaps.count == 1)
        #expect(state.metadata.checkpointID == "100")
    }

    @Test func deletingBothGapAnchorsRetargetsRowsButPreservesServerCursors() throws {
        var state = TimelineLiveUpdates(statuses: [post("100"), post("99")])
        state.receiveHead(TimelinePage(statuses: [post("104"), post("103")]), sinceID: "100", currentAccountID: nil)
        state.remove("103")
        state.remove("100")
        let gap = try #require(state.metadata.gaps.first)
        #expect(gap.afterID == "104")
        #expect(gap.beforeID == "99")
        #expect(gap.maxID == "103")
        #expect(gap.sinceID == "100")
        state.receive(post("103"), currentAccountID: nil)
        #expect(!state.statuses.contains { $0.id == "103" })
        #expect(state.newCount == 1)
    }

    @Test func incomingCapPreservesVisibleRowsAndCreatesAnHonestGap() {
        var state = TimelineLiveUpdates(statuses: [post("100"), post("99")])
        for id in 101...350 { state.receive(post("\(id)"), currentAccountID: nil) }
        state.trimUnapplied(presentedIDs: ["100", "99"])
        #expect(state.statuses.count == 202)
        #expect(state.statuses.suffix(2).map(\.id) == ["100", "99"])
        #expect(state.hasMoreNew)
        #expect(state.newCount <= 200)
        #expect(state.metadata.gaps.first?.beforeID == "100")
    }

    @Test func incomingCapNeverTreatsDeferredCachedTailAsNewIncomingContent() {
        var state = TimelineLiveUpdates(statuses: (1...300).reversed().map { post("\($0)") })
        state.receive(post("301"), currentAccountID: nil)
        state.trimUnapplied(presentedIDs: ["300", "299"])
        #expect(state.statuses.count == 301)
        #expect(state.metadata.gaps.isEmpty)
    }

    @Test func deferredPresentationRequiresApplyBeforeAcknowledging() {
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), cacheClientID: UUID().uuidString, defersLivePresentation: true)
        model.statuses = [post("100")]
        model.receiveLiveStatus(post("101"))
        #expect(model.statuses.map(\.id) == ["100"])
        model.acknowledgePresentedUpdates(through: 1)
        #expect(model.applyLiveUpdates())
        #expect(model.newPostCount == 1)
        #expect(model.statuses.first?.content == "<p>Complete body 101</p>")
        let applied = model.presentedSequence
        model.receiveLiveStatus(post("102"))
        model.acknowledgePresentedUpdates(through: applied)
        #expect(model.applyLiveUpdates())
        #expect(model.newPostCount == 1)
        model.acknowledgePresentedUpdates(through: model.presentedSequence)
        #expect(model.newPostCount == 0)
        model.clearStatuses()
    }

    @Test func boundedNoticeDoesNotAccumulatePreviouslyDroppedIDs() {
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), cacheClientID: UUID().uuidString, defersLivePresentation: true)
        model.statuses = [post("100")]
        for id in 101...350 {
            model.receiveLiveStatus(post("\(id)"))
            if id % 25 == 0 { model.applyLiveUpdates() }
        }
        model.applyLiveUpdates()
        #expect(model.newPostCount <= 200)
        #expect(model.newPostsHaveMore)
        model.clearStatuses()
    }

    @Test func cacheRestoresAnchorGapAndBatchTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        var state = TimelineLiveUpdates(statuses: [post("100"), post("99")])
        state.receiveHead(TimelinePage(statuses: [post("104")]), sinceID: "100", currentAccountID: nil)
        state.setReadingAnchor(.init(statusID: "99", viewportOffset: -120))
        await cache.setLiveSnapshot(statuses: state.statuses, live: state.metadata, for: "a", filter: .home)
        await cache.flushPendingWrites()
        let cold = TimelineCache(directory: directory)
        let metadata = try #require(await cold.getLiveMetadata(for: "a", filter: .home))
        #expect(metadata.readingAnchor?.viewportOffset == -120)
        #expect(metadata.gaps.count == 1)
        #expect(metadata.newIDs.count == 1)
        #expect(await cold.getLiveMetadata(for: "b", filter: .home) == nil)
        try await cold.clearContentCache()
        #expect(await cold.getLiveMetadata(for: "a", filter: .home) == nil)
    }
    @Test func cancelledRefreshCannotReviveContentAfterHardReset() async throws {
        let api = MockMastodonAPI()
        let requests = AsyncStream<CheckedContinuation<[Status], Error>>.makeStream()
        api.fetchHomeTimelineHandler = { _, _, _ in
            try await withCheckedThrowingContinuation { requests.continuation.yield($0) }
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            cacheClientID: UUID().uuidString, defersLivePresentation: true)
        model.statuses = [post("100")]
        let refresh = Task { await model.refresh() }
        var iterator = requests.stream.makeAsyncIterator()
        let reply = try #require(await iterator.next())
        model.clearStatuses()
        reply.resume(returning: [post("101")])
        let result = await refresh.value
        if case .cancelled = result {} else { Issue.record("Old generation accepted a response") }
        #expect(model.statuses.isEmpty)
        #expect(model.newPostCount == 0)
        #expect(!model.hasUnappliedUpdates)
    }

    @Test func contentClearResetsOnlyModelsUsingThatCache() {
        let cache = TimelineCache()
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), timelineCache: cache, cacheClientID: UUID().uuidString)
        let other = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), timelineCache: TimelineCache(), cacheClientID: UUID().uuidString)
        model.statuses = [post("100")]
        other.statuses = [post("other")]
        NotificationCenter.default.post(name: .timelineContentWillClear, object: cache)
        #expect(model.statuses.isEmpty)
        #expect(other.statuses.count == 1)
    }

    @Test func nativeAnchorKeepsOffsetAndUserGestureCancelsPendingCorrection() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 400, height: 3000)
        window.addSubview(scroll)
        window.isHidden = false
        defer { window.isHidden = true }
        let bridge = TimelineScrollBridge()
        bridge.setActive(true)
        bridge.register(scroll, for: .home)
        let row = TimelineRowAnchorView(frame: CGRect(x: 0, y: 480, width: 400, height: 700))
        row.statusID = "long-post"
        row.bridge = bridge
        scroll.addSubview(row)
        scroll.contentOffset.y = 500
        bridge.updateGeometry(for: .home, headerHeight: 48)
        row.setNeedsLayout()
        row.layoutIfNeeded()
        let events = AsyncStream<TimelineType>.makeStream()
        let subscription = bridge.layoutEvents.sink { events.continuation.yield($0) }
        defer { subscription.cancel() }
        let before = try #require(bridge.readingAnchors(for: .home).first)
        #expect(before.viewportOffset == -68)
        #expect(bridge.prepareContentUpdate(for: .home, revision: 1, retainedIDs: ["long-post"]))
        row.frame.origin.y += 300
        row.revision = 1
        row.setNeedsLayout()
        row.layoutIfNeeded()
        var iterator = events.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(scroll.contentOffset.y == 800)
        #expect(bridge.readingAnchors(for: .home).first?.viewportOffset == before.viewportOffset)
        #expect(bridge.prepareContentUpdate(for: .home, revision: 2, retainedIDs: ["long-post"]))
        bridge.updatePhase(.tracking, for: .home)
        row.frame.origin.y += 300
        row.revision = 2
        row.setNeedsLayout()
        row.layoutIfNeeded()
        _ = await iterator.next()
        #expect(scroll.contentOffset.y == 800)
        #expect(!bridge.canPresentUpdates(for: .home))
        bridge.setPresentedTimeline(.local)
        bridge.scrollToTop(.home)
        #expect(scroll.contentOffset.y == 800)
    }

    @Test func onlyUserStreamAdditionsBelongInHome() {
        let event = StreamEvent.update(status: post("101"))
        #expect(SourcedStreamEvent(event: event, streams: ["user"]).canInsertIntoHome)
        #expect(!SourcedStreamEvent(event: event, streams: ["public", "local"]).canInsertIntoHome)
        #expect(!SourcedStreamEvent(event: event, streams: ["list", "alpha"]).canInsertIntoHome)
        #expect(!SourcedStreamEvent(event: event, streams: []).canInsertIntoHome)
    }

}
