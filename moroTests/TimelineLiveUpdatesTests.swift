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

    @Test(arguments: [
        ["100", "102", "205", "204"],
        ["98", "999", "1001", "1000"],
        ["18446744073709551615", "18446744073709551616", "18446744073709551700", "18446744073709551699"],
    ])
    func laterRemoteHeadOvertakesLocallyCreatedReply(ids: [String]) {
        let baseline = ids[0], replyID = ids[1], newest = ids[2], older = ids[3]
        let reply = ThreadReadingFixtures.status(replyID, parent: "parent", own: true)
        var state = TimelineLiveUpdates(statuses: [post(baseline)])
        state.receive(reply, currentAccountID: ThreadReadingFixtures.author.id)
        #expect(state.statuses.first?.id == replyID)
        #expect(state.metadata.fetchedHeadID == baseline)

        state.receiveHead(TimelinePage(statuses: [post(newest), post(older)]),
            sinceID: baseline, currentAccountID: ThreadReadingFixtures.author.id)

        #expect(state.statuses.map(\.id) == [newest, older, replyID, baseline])
        #expect(state.newCount == 2)
        #expect(state.statuses.first { $0.id == replyID }?.inReplyToID == "parent")
    }

    @Test func remotePageInterleavesWithUnconfirmedLocalRows() {
        var state = TimelineLiveUpdates(statuses: [post("100")])
        state.receive(post("103", own: true), currentAccountID: ThreadReadingFixtures.author.id)
        state.receiveHead(TimelinePage(statuses: [post("104"), post("102")]),
            sinceID: "100", currentAccountID: ThreadReadingFixtures.author.id)
        #expect(state.statuses.map(\.id) == ["104", "103", "102", "100"])
        #expect(state.newCount == 2)
    }

    @Test(arguments: [false, true])
    func legacyCacheMovesOldReplyBelowConfirmedHead(isOffline: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clientID = UUID().uuidString
        let cache = TimelineCache(directory: directory)
        let reply = ThreadReadingFixtures.status("102", parent: "parent", own: true)
        let anchor = TimelineReadingAnchor(statusID: "102", viewportOffset: -120)
        let metadata = TimelineLiveMetadata(checkpointID: "100", fetchedHeadID: "205",
            gaps: [TimelineGap(afterID: "204", beforeID: "100", maxID: "204",
                sinceID: "100", targetHeadID: "205", sequence: 2)],
            newIDs: ["205": 1, "204": 2], sequence: 2, readingAnchor: anchor)
        await cache.setLiveSnapshot(statuses: [reply, post("205"), post("204"), post("100")],
            live: metadata, for: clientID, filter: .home)
        await cache.flushPendingWrites()

        let cold = TimelineCache(directory: directory)
        let api = MockMastodonAPI()
        api.fetchHomeTimelineHandler = { _, _, _ in
            if isOffline { throw URLError(.notConnectedToInternet) }
            return [post("206"), post("205"), post("204")]
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            timelineCache: cold, cacheClientID: clientID, defersLivePresentation: true)
        defer { model.clearStatuses() }
        await model.loadInitial()
        #expect(model.statuses.map(\.id) == ["205", "204", "102", "100"])
        model.applyLiveUpdates()
        let expected = isOffline ? ["205", "204", "102", "100"] : ["206", "205", "204", "102", "100"]
        #expect(model.statuses.map(\.id) == expected)
        #expect(model.savedReadingAnchor == anchor)
        #expect(model.gaps.first?.beforeID == "100")
        await model.flushCacheWrites()
        let restored = TimelineCache(directory: directory)
        #expect(await restored.getStatuses(for: clientID, filter: .home)?.map(\.id) == expected)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), timelineCache: TimelineCache(directory: directory),
            cacheClientID: UUID().uuidString, defersLivePresentation: true)
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), timelineCache: TimelineCache(directory: directory),
            cacheClientID: UUID().uuidString, defersLivePresentation: true)
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

    @Test func streamedPostsStillGetAQuietCompletenessProbe() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchHomeTimelineHandler = { maxID, sinceID, _ in
            #expect(maxID == "101" && sinceID == "100")
            requests += 1
            return []
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory), cacheClientID: UUID().uuidString)
        defer { model.clearStatuses() }
        model.statuses = [post("100")]
        model.receiveLiveStatus(post("101"))
        let inserted = model.receiveDetectedPage(TimelinePage(statuses: [post("101")]), sinceID: "100")
        #expect(inserted == 0 && model.gaps.count == 1)

        model.fillRecentGapsIfNeeded()
        try await waitForGapWork { model.gaps.isEmpty }
        #expect(requests == 1)
        #expect(model.statuses.map(\.id) == ["101", "100"])
        #expect(model.failedGapIDs.isEmpty)
    }

    @Test func approachingAGapContinuesBeyondTheBackgroundProbeBudget() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockMastodonAPI()
        var cursors: [String?] = []
        api.fetchHomeTimelineHandler = { maxID, sinceID, _ in
            #expect(sinceID == "100")
            cursors.append(maxID)
            switch maxID {
            case "107": return [post("106"), post("105")]
            case "105": return [post("104"), post("103")]
            case "103": return [post("102"), post("101")]
            default: return []
            }
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory), cacheClientID: UUID().uuidString)
        defer { model.clearStatuses() }
        model.statuses = [post("100")]
        model.receiveDetectedPage(TimelinePage(statuses: [post("108"), post("107")]), sinceID: "100")
        model.fillRecentGapsIfNeeded()
        try await waitForGapWork { cursors.count == 2 && model.loadingGapIDs.isEmpty }
        #expect(model.gaps.count == 1)
        #expect(model.statuses.count == 7)

        model.fillRecentGapsIfNeeded(near: ["103", "100"])
        try await waitForGapWork { model.gaps.isEmpty }
        #expect(cursors == ["107", "105", "103", "101"])
        let expectedIDs = (100...108).reversed().map { String($0) }
        #expect(model.statuses.map(\.id) == expectedIDs)
    }

    @Test func gapFailuresWaitForAnchoredPresentationAndAnExplicitRetry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockMastodonAPI()
        var requests = 0
        api.fetchHomeTimelineHandler = { _, _, _ in
            requests += 1
            if requests == 1 { throw URLError(.notConnectedToInternet) }
            return []
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory),
            cacheClientID: UUID().uuidString, defersLivePresentation: true)
        defer { model.clearStatuses() }
        model.statuses = [post("100")]
        model.receiveDetectedPage(TimelinePage(statuses: [post("101")]), sinceID: "100")
        model.applyLiveUpdates()
        let gap = try #require(model.gaps.first)
        #expect(await model.loadGap(id: gap.id) == false)
        #expect(model.failedGapIDs.isEmpty)
        #expect(model.hasUnappliedUpdates)
        model.applyLiveUpdates()
        #expect(model.failedGapIDs == [gap.id])

        model.fillRecentGapsIfNeeded(near: ["101", "100"])
        await Task.yield()
        #expect(requests == 1)
        #expect(await model.loadGap(id: gap.id))
        // Removing the retry row also waits for the view to preserve its anchor.
        #expect(model.failedGapIDs == [gap.id])
        model.applyLiveUpdates()
        #expect(model.failedGapIDs.isEmpty && model.gaps.isEmpty)
        #expect(requests == 2)
    }

    @Test func gapAndOlderPageRequestsQueueInOrderAndCoalesceRepeatedTaps() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockMastodonAPI()
        typealias Request = (maxID: String?, sinceID: String?, reply: CheckedContinuation<[Status], Error>)
        let requests = AsyncStream<Request>.makeStream()
        api.fetchHomeTimelineHandler = { maxID, sinceID, _ in
            try await withCheckedThrowingContinuation { requests.continuation.yield((maxID, sinceID, $0)) }
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory), cacheClientID: UUID().uuidString)
        defer { model.clearStatuses(); requests.continuation.finish() }
        model.statuses = [post("100")]
        model.receiveDetectedPage(TimelinePage(statuses: [post("102"), post("101")]), sinceID: "100")
        model.receiveDetectedPage(TimelinePage(statuses: [post("104"), post("103")]), sinceID: "102")
        let firstGap = try #require(model.gaps.first)
        let secondGap = try #require(model.gaps.last)
        let first = Task { await model.loadGap(id: firstGap.id) }
        var iterator = requests.stream.makeAsyncIterator()
        let request1 = try #require(await iterator.next())
        // A failed wait must also release the mock response held by the queued tasks.
        var pendingReply: CheckedContinuation<[Status], Error>? = request1.reply
        defer { pendingReply?.resume(throwing: CancellationError()) }
        #expect(request1.maxID == "101" && request1.sinceID == "100")
        let older = Task { await model.loadMore() }
        try await waitForGapWork { if case .loading = model.paginationState { return true }; return false }
        let second = Task { await model.loadGap(id: secondGap.id) }
        try await waitForGapWork { model.loadingGapIDs.count == 2 }
        let repeated = Task { await model.loadGap(id: firstGap.id) }
        await Task.yield()

        request1.reply.resume(returning: [])
        pendingReply = nil
        let request2 = try #require(await iterator.next())
        #expect(request2.maxID == "100" && request2.sinceID == nil)
        request2.reply.resume(returning: [post("99")])
        let request3 = try #require(await iterator.next())
        #expect(request3.maxID == "103" && request3.sinceID == "102")
        request3.reply.resume(returning: [])
        #expect(await first.value)
        #expect(await repeated.value)
        #expect(await second.value)
        await older.value
        #expect(model.loadingGapIDs.isEmpty && model.failedGapIDs.isEmpty && model.gaps.isEmpty)
        #expect(model.statuses.map(\.id) == ["104", "103", "102", "101", "100", "99"])
    }

    @Test func resetCancelsQueuedGapAndPaginationRequestsBeforeTheyReachTheServer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockMastodonAPI()
        let requests = AsyncStream<CheckedContinuation<[Status], Error>>.makeStream()
        var requestCount = 0
        api.fetchHomeTimelineHandler = { _, _, _ in
            requestCount += 1
            return try await withCheckedThrowingContinuation { requests.continuation.yield($0) }
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory), cacheClientID: UUID().uuidString)
        defer { model.clearStatuses(); requests.continuation.finish() }
        model.statuses = [post("100")]
        model.receiveDetectedPage(TimelinePage(statuses: [post("102"), post("101")]), sinceID: "100")
        model.receiveDetectedPage(TimelinePage(statuses: [post("104"), post("103")]), sinceID: "102")
        let firstGap = try #require(model.gaps.first)
        let secondGap = try #require(model.gaps.last)
        let first = Task { await model.loadGap(id: firstGap.id) }
        var iterator = requests.stream.makeAsyncIterator()
        let reply = try #require(await iterator.next())
        var pendingReply: CheckedContinuation<[Status], Error>? = reply
        defer { pendingReply?.resume(throwing: CancellationError()) }
        let older = Task { await model.loadMore() }
        try await waitForGapWork { if case .loading = model.paginationState { return true }; return false }
        let second = Task { await model.loadGap(id: secondGap.id) }
        try await waitForGapWork { model.loadingGapIDs.count == 2 }
        model.clearStatuses()
        reply.resume(returning: [post("101")])
        pendingReply = nil
        #expect(await first.value == false)
        #expect(await second.value == false)
        await older.value
        #expect(requestCount == 1)
        #expect(model.statuses.isEmpty && model.gaps.isEmpty && model.loadingGapIDs.isEmpty)
        #expect(model.failedGapIDs.isEmpty && !model.hasUnappliedUpdates)
    }

    private func waitForGapWork(_ condition: () -> Bool) async throws {
        // Returns as soon as the work settles; the generous limit only matters when the
        // whole suite runs in parallel and the main actor is busy.
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
            if condition() { return }
        }
        try #require(condition(), "Timeline gap work did not settle")
    }

    @Test func cancelledRefreshCannotReviveContentAfterHardReset() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockMastodonAPI()
        let requests = AsyncStream<CheckedContinuation<[Status], Error>>.makeStream()
        api.fetchHomeTimelineHandler = { _, _, _ in
            try await withCheckedThrowingContinuation { requests.continuation.yield($0) }
        }
        let model = TimelineViewModel(apiClient: api, feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory),
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory.appendingPathComponent("current"))
        let model = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), timelineCache: cache, cacheClientID: UUID().uuidString)
        let other = TimelineViewModel(apiClient: ListCacheFixtureProtocol.makeClient(),
            feedCoordinator: FeedCoordinator(), timelineCache: TimelineCache(directory: directory.appendingPathComponent("other")),
            cacheClientID: UUID().uuidString)
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

    @Test func atTopUpdatesSynchronouslyAndKeepsTheLastWrite() {
        let bridge = TimelineScrollBridge()
        var events: [TimelineType] = []
        let subscription = bridge.atTopEvents.sink { events.append($0) }
        defer { subscription.cancel() }

        #expect(!bridge.isAtTop(.home))
        bridge.setAtTop(false, for: .home)
        bridge.setAtTop(true, for: .home)
        bridge.setAtTop(true, for: .home)
        bridge.setAtTop(false, for: .home)
        bridge.setAtTop(true, for: .home)

        #expect(bridge.isAtTop(.home))
        #expect(events == [.home, .home, .home])
    }

    @Test func idleScrollConfirmsLatestFromFinalNativePosition() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 400, height: 3000)
        window.addSubview(scroll)
        window.isHidden = false
        defer { window.isHidden = true }
        let bridge = TimelineScrollBridge()
        bridge.setActive(true)
        bridge.register(scroll, for: .home)
        let row = TimelineRowAnchorView(frame: CGRect(x: 0, y: 48, width: 400, height: 200))
        row.statusID = "latest"
        row.revision = 1
        row.bridge = bridge
        scroll.addSubview(row)
        row.setNeedsLayout()
        row.layoutIfNeeded()
        scroll.contentOffset.y = 200
        bridge.updateGeometry(for: .home, headerHeight: 48)
        bridge.updatePhase(.decelerating, for: .home)
        #expect(!bridge.isAtTop(.home))

        let events = AsyncStream<TimelineType>.makeStream()
        let subscription = bridge.layoutEvents.sink { events.continuation.yield($0) }
        defer { subscription.cancel() }
        // The final native offset can settle after the last SwiftUI geometry callback.
        scroll.contentOffset.y = -scroll.adjustedContentInset.top
        bridge.updatePhase(.idle, for: .home)
        var iterator = events.stream.makeAsyncIterator()
        _ = await iterator.next()
        #expect(bridge.isAtTop(.home))
        #expect(bridge.latestIsVisible(for: .home, statusID: "latest", revision: 1))
    }

    @Test func onlyUserStreamAdditionsBelongInHome() {
        let event = StreamEvent.update(status: post("101"))
        #expect(SourcedStreamEvent(event: event, streams: ["user"]).canInsertIntoHome)
        #expect(!SourcedStreamEvent(event: event, streams: ["public", "local"]).canInsertIntoHome)
        #expect(!SourcedStreamEvent(event: event, streams: ["list", "alpha"]).canInsertIntoHome)
        #expect(!SourcedStreamEvent(event: event, streams: []).canInsertIntoHome)
    }

}
