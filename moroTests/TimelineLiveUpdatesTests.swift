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
        await model.fillRecentGapsIfNeeded()?.value
        #expect(cursors == ["107", "105"])
        #expect(model.loadingGapIDs.isEmpty)
        #expect(model.gaps.count == 1)
        #expect(model.statuses.count == 7)

        await model.fillRecentGapsIfNeeded(near: ["103", "100"])?.value
        #expect(model.gaps.isEmpty)
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

    @Test func aLaunchRestoresTheReadingPositionOnlySoonAfterLeaving() {
        let now = Date()
        let window = TimelineLaunchPolicy.restoreWindow
        #expect(window == 30 * 60)
        #expect(!TimelineLaunchPolicy.shouldRestore(lastLeftAt: nil, now: now, window: window), "First launch")
        #expect(TimelineLaunchPolicy.shouldRestore(lastLeftAt: now.addingTimeInterval(-60), now: now, window: window))
        #expect(TimelineLaunchPolicy.shouldRestore(lastLeftAt: now.addingTimeInterval(-29 * 60), now: now, window: window))
        #expect(!TimelineLaunchPolicy.shouldRestore(lastLeftAt: now.addingTimeInterval(-31 * 60), now: now, window: window))
        #expect(!TimelineLaunchPolicy.shouldRestore(lastLeftAt: now.addingTimeInterval(600), now: now, window: window),
            "A clock set backwards is not a reason to restore")
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

    @Test func lightweightAnchorUpdatePersistsImmediatelyWithoutReencodingCachedStatuses() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clientID = UUID().uuidString
        let cache = TimelineCache(directory: directory, persistenceDelay: .seconds(60))
        let initialAnchor = TimelineReadingAnchor(statusID: "100", viewportOffset: -12)
        let metadata = TimelineLiveMetadata(
            checkpointID: "102",
            fetchedHeadID: "102",
            readingAnchor: initialAnchor
        )
        await cache.setLiveSnapshot(
            statuses: [post("102"), post("101"), post("100")],
            live: metadata,
            for: clientID,
            filter: .home
        )
        await cache.flushPendingWrites()

        let cacheURL = directory.appendingPathComponent("\(clientID)-Home.cache")
        let initialCacheModified = try #require(
            try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date
        )

        let model = TimelineViewModel(
            apiClient: MockMastodonAPI(),
            feedCoordinator: FeedCoordinator(),
            timelineCache: cache,
            cacheClientID: clientID,
            defersLivePresentation: true
        )
        defer { model.clearStatuses() }
        model.statuses = [post("102"), post("101"), post("100")]
        let updatedAnchor = TimelineReadingAnchor(statusID: "101", viewportOffset: -84)
        model.saveReadingAnchor(updatedAnchor)

        // Cold reader sees the updated anchor immediately without flushing the 60s delayed body cache.
        let cold = TimelineCache(directory: directory)
        let coldMetadata = try #require(await cold.getLiveMetadata(for: clientID, filter: .home))
        #expect(coldMetadata.readingAnchor == updatedAnchor)

        let afterCacheModified = try #require(
            try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date
        )
        #expect(afterCacheModified == initialCacheModified)
    }

    @Test func earlyLiveEventBeforeInitialCacheMergePreservesSavedAnchorAndCachedPosts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clientID = UUID().uuidString
        let cache = TimelineCache(directory: directory)
        let savedAnchor = TimelineReadingAnchor(statusID: "100", viewportOffset: -140)
        let metadata = TimelineLiveMetadata(
            checkpointID: "102",
            fetchedHeadID: "102",
            readingAnchor: savedAnchor
        )
        await cache.setLiveSnapshot(
            statuses: [post("102"), post("101"), post("100")],
            live: metadata,
            for: clientID,
            filter: .home
        )
        await cache.flushPendingWrites()

        let cold = TimelineCache(directory: directory)
        let api = MockMastodonAPI()
        let requestStarted = AsyncStream<CheckedContinuation<[Status], Error>>.makeStream()
        api.fetchHomeTimelineHandler = { _, _, _ in
            try await withCheckedThrowingContinuation { requestStarted.continuation.yield($0) }
        }
        // Short soft timeout guarantees hydration yields while we simulate an early stream event.
        let config = TimelineViewModel.BootstrapConfig(
            initialLoadLimit: 20,
            refreshLoadLimit: 20,
            paginationLoadLimit: 40,
            initialRenderCap: 24,
            cacheHydrationSoftTimeoutNanoseconds: 1,
            deferredFillBatchSize: 6,
            deferredFillStepNanoseconds: 50_000_000,
            deferredFillInitialDelayNanoseconds: 50_000_000
        )
        let model = TimelineViewModel(
            apiClient: api,
            feedCoordinator: FeedCoordinator(),
            timelineCache: cold,
            cacheClientID: clientID,
            bootstrapConfig: config,
            defersLivePresentation: true
        )
        defer { model.clearStatuses(); requestStarted.continuation.finish() }

        // Simulate a stream update arriving before loadInitial() has hydrated the cached timeline.
        model.receiveLiveStatus(post("104"))
        #expect(model.savedReadingAnchor == nil)

        let loadTask = Task { await model.loadInitial() }
        var iterator = requestStarted.stream.makeAsyncIterator()
        let reply = try #require(await iterator.next())
        reply.resume(returning: [post("104"), post("103"), post("102")])
        await loadTask.value

        #expect(model.savedReadingAnchor == savedAnchor)
        #expect(model.canonicalStatusIDs.contains("100"))
        #expect(model.canonicalStatusIDs.contains("103"))
        #expect(model.canonicalStatusIDs.contains("104"))
    }

    @Test func heldRestoredAnchorResistsPassiveDriftAndContentUpdatesUntilUserScrolls() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let scroll = UIScrollView(frame: window.bounds)
        scroll.contentSize = CGSize(width: 400, height: 5000)
        window.addSubview(scroll)
        window.isHidden = false
        defer { window.isHidden = true }

        let bridge = TimelineScrollBridge()
        bridge.setActive(true)
        bridge.register(scroll, for: .home)

        let driftedRow = TimelineRowAnchorView(frame: CGRect(x: 0, y: 400, width: 400, height: 300))
        driftedRow.statusID = "323"
        driftedRow.bridge = bridge
        scroll.addSubview(driftedRow)

        let targetRow = TimelineRowAnchorView(frame: CGRect(x: 0, y: 1200, width: 400, height: 300))
        targetRow.statusID = "267"
        targetRow.bridge = bridge
        scroll.addSubview(targetRow)

        scroll.contentOffset.y = 0
        bridge.updateGeometry(for: .home, headerHeight: 48)
        driftedRow.setNeedsLayout()
        driftedRow.layoutIfNeeded()
        targetRow.setNeedsLayout()
        targetRow.layoutIfNeeded()

        let saved = TimelineReadingAnchor(statusID: "267", viewportOffset: -120)
        bridge.holdReadingPosition(saved, for: .home)
        bridge.restoreReadingAnchor(saved, for: .home)
        // Direct restore aligns immediately: 1200 - 48 - (-120) = 1272.
        #expect(scroll.contentOffset.y == 1272)
        #expect(bridge.heldRestoredAnchor(for: .home) == saved)

        let events = AsyncStream<TimelineType>.makeStream()
        let subscription = bridge.layoutEvents.sink { events.continuation.yield($0) }
        defer { subscription.cancel() }
        var iterator = events.stream.makeAsyncIterator()

        // Simulate passive LazyVStack drift away from 267 onto 323 without user interaction.
        scroll.contentOffset.y = 430
        bridge.updateGeometry(for: .home, headerHeight: 48)
        _ = await iterator.next()
        #expect(scroll.contentOffset.y == 1272)
        #expect(bridge.heldRestoredAnchor(for: .home) == saved)

        // A content update while held must preserve 267 rather than adopting a drifted row.
        scroll.contentOffset.y = 430
        #expect(bridge.prepareContentUpdate(for: .home, revision: 1, retainedIDs: ["323", "267"]))
        targetRow.frame.origin.y += 240
        targetRow.revision = 1
        targetRow.setNeedsLayout()
        targetRow.layoutIfNeeded()
        _ = await iterator.next()
        #expect(scroll.contentOffset.y == 1512)
        #expect(bridge.heldRestoredAnchor(for: .home) == saved)

        // Once the reader actively touches the timeline, the restored-anchor hold releases.
        bridge.updatePhase(.tracking, for: .home)
        #expect(!bridge.isHoldingRestoredAnchor(for: .home))
    }

    @Test func timelineOpenBehaviorPolicyCoversColdLaunchAndAntiMistouchWarmResume() {
        let now = Date()
        let twoHours: TimeInterval = 2 * 60 * 60

        // 1. Keep reading position: always restores on cold launch, never auto-jumps on warm resume.
        #expect(TimelineLaunchPolicy.shouldRestoreOnColdLaunch(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.keepPosition.rawValue,
            smartWindow: twoHours, lastLeftAt: nil, now: now
        ))
        #expect(TimelineLaunchPolicy.shouldRestoreOnColdLaunch(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.keepPosition.rawValue,
            smartWindow: twoHours, lastLeftAt: now.addingTimeInterval(-10 * 3600), now: now
        ))
        #expect(!TimelineLaunchPolicy.shouldJumpToLatestOnResume(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.keepPosition.rawValue,
            smartWindow: twoHours, awayDuration: 10 * 3600
        ))

        // 2. Smart refresh: honors user-configured slider threshold on both cold launch and warm resume.
        #expect(TimelineLaunchPolicy.shouldRestoreOnColdLaunch(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.smartRefresh.rawValue,
            smartWindow: twoHours, lastLeftAt: now.addingTimeInterval(-90 * 60), now: now
        ))
        #expect(!TimelineLaunchPolicy.shouldRestoreOnColdLaunch(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.smartRefresh.rawValue,
            smartWindow: twoHours, lastLeftAt: now.addingTimeInterval(-125 * 60), now: now
        ))
        #expect(!TimelineLaunchPolicy.shouldJumpToLatestOnResume(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.smartRefresh.rawValue,
            smartWindow: twoHours, awayDuration: 119 * 60
        ))
        #expect(TimelineLaunchPolicy.shouldJumpToLatestOnResume(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.smartRefresh.rawValue,
            smartWindow: twoHours, awayDuration: 120 * 60
        ))

        // 3. Always latest: cold launch goes to top; warm resume respects 2-minute anti-mistouch guard.
        #expect(!TimelineLaunchPolicy.shouldRestoreOnColdLaunch(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.alwaysLatest.rawValue,
            smartWindow: twoHours, lastLeftAt: now.addingTimeInterval(-5), now: now
        ))
        #expect(!TimelineLaunchPolicy.shouldJumpToLatestOnResume(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.alwaysLatest.rawValue,
            smartWindow: twoHours, awayDuration: 30
        ))
        #expect(!TimelineLaunchPolicy.shouldJumpToLatestOnResume(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.alwaysLatest.rawValue,
            smartWindow: twoHours, awayDuration: 119
        ))
        #expect(TimelineLaunchPolicy.shouldJumpToLatestOnResume(
            behaviorRawValue: AppSettings.TimelineOpenBehavior.alwaysLatest.rawValue,
            smartWindow: twoHours, awayDuration: 120
        ))
    }

    @Test func readingPositionSettingsPersistAndSnapSliderSteps() throws {
        let suite = "ReadingPositionSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let settings = AppSettings(userDefaults: defaults)
        #expect(settings.timelineOpenBehavior == .keepPosition)
        #expect(settings.smartRefreshIntervalMinutes == 60)
        #expect(settings.syncReadingPositionWithServer == true)

        settings.timelineOpenBehavior = .smartRefresh
        settings.smartRefreshIntervalMinutes = 240
        settings.syncReadingPositionWithServer = false

        let reloaded = AppSettings(userDefaults: defaults)
        #expect(reloaded.timelineOpenBehavior == .smartRefresh)
        #expect(reloaded.smartRefreshIntervalMinutes == 240)
        #expect(reloaded.syncReadingPositionWithServer == false)

        #expect(AppSettings.normalizedSmartRefreshMinutes(10) == 30)
        #expect(AppSettings.normalizedSmartRefreshMinutes(95) == 120)
        #expect(AppSettings.normalizedSmartRefreshMinutes(5_000) == 1440)
    }

    @Test func remoteMarkerAdvancesReadingAnchorAndClearsAlreadyReadNewPosts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clientID = UUID().uuidString
        let cache = TimelineCache(directory: directory)
        let localAnchor = TimelineReadingAnchor(statusID: "100", viewportOffset: -64)
        let metadata = TimelineLiveMetadata(
            checkpointID: "100",
            fetchedHeadID: "100",
            readingAnchor: localAnchor
        )
        await cache.setLiveSnapshot(
            statuses: [post("100"), post("99")],
            live: metadata,
            for: clientID,
            filter: .home
        )
        await cache.flushPendingWrites()

        let api = MockMastodonAPI()
        api.fetchHomeTimelineHandler = { _, _, _ in
            [post("104"), post("103"), post("102"), post("101"), post("100")]
        }
        api.fetchMarkersHandler = { _ in
            Marker(home: MarkerContent(lastReadId: "102", updatedAt: Date(), version: 5))
        }

        let model = TimelineViewModel(
            apiClient: api,
            feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory),
            cacheClientID: clientID,
            defersLivePresentation: true,
            markerSyncEnabled: { true },
            restoresReadingPositionOverride: true
        )
        defer { model.clearStatuses() }

        await model.loadInitial()
        #expect(model.savedReadingAnchor == TimelineReadingAnchor(statusID: "102", viewportOffset: 0))
        #expect(model.pendingRemoteSyncedAnchor == TimelineReadingAnchor(statusID: "102", viewportOffset: 0))
        // 102 and 101 were already read on another device; only 104 and 103 remain unread.
        #expect(model.newPostCount == 2)
    }

    @Test func remoteMarkerNeverPullsNewerLocalAnchorBackwardAndRespectsSyncToggle() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clientID = UUID().uuidString
        let cache = TimelineCache(directory: directory)
        let localAnchor = TimelineReadingAnchor(statusID: "103", viewportOffset: -145)
        let metadata = TimelineLiveMetadata(
            checkpointID: "104",
            fetchedHeadID: "104",
            readingAnchor: localAnchor
        )
        await cache.setLiveSnapshot(
            statuses: [post("104"), post("103"), post("102"), post("101")],
            live: metadata,
            for: clientID,
            filter: .home
        )
        await cache.flushPendingWrites()

        let api = MockMastodonAPI()
        api.fetchHomeTimelineHandler = { _, _, _ in [post("104"), post("103")] }
        var markerFetchCount = 0
        var savedMarkerIDs: [String] = []
        api.fetchMarkersHandler = { _ in
            markerFetchCount += 1
            return Marker(home: MarkerContent(lastReadId: "101", updatedAt: Date(), version: 2))
        }
        api.saveMarkerHandler = { home, _ in
            if let home { savedMarkerIDs.append(home) }
            return Marker(home: home.map { MarkerContent(lastReadId: $0, updatedAt: Date(), version: 3) })
        }

        // 1. Enabled sync: older remote marker (101) keeps pixel-accurate local anchor (103, -145).
        let enabledModel = TimelineViewModel(
            apiClient: api,
            feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory),
            cacheClientID: clientID,
            defersLivePresentation: true,
            markerSyncEnabled: { true },
            restoresReadingPositionOverride: true
        )
        defer { enabledModel.clearStatuses() }
        await enabledModel.loadInitial()
        #expect(markerFetchCount == 1)
        #expect(enabledModel.savedReadingAnchor == localAnchor)

        // Forward-only push: scrolling backward to 100 never overwrites server marker 101;
        // flushing from 103 advances server marker to 103 immediately.
        await enabledModel.saveMarker(statusID: "100")
        #expect(savedMarkerIDs.isEmpty)
        await enabledModel.flushPendingMarkerSave()
        #expect(savedMarkerIDs == ["103"])

        // 2. Disabled sync: makes zero Marker API requests.
        let disabledModel = TimelineViewModel(
            apiClient: api,
            feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory),
            cacheClientID: clientID,
            defersLivePresentation: true,
            markerSyncEnabled: { false },
            restoresReadingPositionOverride: true
        )
        defer { disabledModel.clearStatuses() }
        await disabledModel.loadInitial()
        await disabledModel.saveMarker(statusID: "104")
        await disabledModel.flushPendingMarkerSave()
        #expect(markerFetchCount == 1)
        #expect(savedMarkerIDs == ["103"])
    }

    @Test func warmResumeMarkerSyncFetchesNewerPageAndAdvancesAnchor() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = MockMastodonAPI()
        api.fetchHomeTimelineHandler = { _, _, _ in [post("105"), post("104"), post("103")] }
        api.fetchMarkersHandler = { _ in
            Marker(home: MarkerContent(lastReadId: "104", updatedAt: Date(), version: 9))
        }

        let model = TimelineViewModel(
            apiClient: api,
            feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory),
            cacheClientID: UUID().uuidString,
            defersLivePresentation: true,
            markerSyncEnabled: { true },
            restoresReadingPositionOverride: true
        )
        defer { model.clearStatuses() }
        model.statuses = [post("102"), post("101"), post("100")]
        model.saveReadingAnchor(TimelineReadingAnchor(statusID: "100", viewportOffset: -40))

        let synced = await model.syncRemoteMarkerOnResume(allowAdvance: true)
        #expect(synced == TimelineReadingAnchor(statusID: "104", viewportOffset: 0))
        #expect(model.savedReadingAnchor == TimelineReadingAnchor(statusID: "104", viewportOffset: 0))
        #expect(model.newPostCount == 1) // Only 105 is newer than 104
    }

    @Test func sameDeviceReadingOlderPostDoesNotSnapBackToOwnEarlierServerMarker() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let clientID = UUID().uuidString
        let cache = TimelineCache(directory: directory)
        let metadata = TimelineLiveMetadata(
            checkpointID: "200",
            fetchedHeadID: "200",
            readingAnchor: TimelineReadingAnchor(statusID: "200", viewportOffset: 0)
        )
        await cache.setLiveSnapshot(
            statuses: [post("200"), post("180"), post("150")],
            live: metadata,
            for: clientID,
            filter: .home
        )
        await cache.flushPendingWrites()

        var remoteMarkerID = "200"
        let api = MockMastodonAPI()
        api.fetchHomeTimelineHandler = { _, _, _ in [post("205"), post("200"), post("180"), post("150")] }
        api.fetchMarkersHandler = { _ in
            Marker(home: MarkerContent(lastReadId: remoteMarkerID, updatedAt: Date(), version: 10))
        }
        api.saveMarkerHandler = { home, _ in
            if let home { remoteMarkerID = home }
            return Marker(home: MarkerContent(lastReadId: remoteMarkerID, updatedAt: Date(), version: 11))
        }

        // Session 1: device confirms server marker 200, then reader scrolls back to older post 150.
        let session1 = TimelineViewModel(
            apiClient: api,
            feedCoordinator: FeedCoordinator(),
            timelineCache: cache,
            cacheClientID: clientID,
            defersLivePresentation: true,
            markerSyncEnabled: { true },
            restoresReadingPositionOverride: true
        )
        defer { session1.clearStatuses() }
        await session1.loadInitial()
        let olderAnchor = TimelineReadingAnchor(statusID: "150", viewportOffset: -55)
        session1.saveReadingAnchor(olderAnchor)
        await session1.flushPendingMarkerSave()
        #expect(remoteMarkerID == "200")

        // Session 2 (cold relaunch): server still holds this device's own 200 -> stay on 150!
        let session2 = TimelineViewModel(
            apiClient: api,
            feedCoordinator: FeedCoordinator(),
            timelineCache: TimelineCache(directory: directory),
            cacheClientID: clientID,
            defersLivePresentation: true,
            markerSyncEnabled: { true },
            restoresReadingPositionOverride: true
        )
        defer { session2.clearStatuses() }
        await session2.loadInitial()
        #expect(session2.savedReadingAnchor == olderAnchor)
        #expect(session2.pendingRemoteSyncedAnchor == nil)

        // Now another device (Web) advances the server marker to 205 -> phone syncs forward to 205!
        remoteMarkerID = "205"
        let synced = await session2.syncRemoteMarkerOnResume(allowAdvance: true)
        #expect(synced == TimelineReadingAnchor(statusID: "205", viewportOffset: 0))
        #expect(session2.savedReadingAnchor == TimelineReadingAnchor(statusID: "205", viewportOffset: 0))
    }

}
