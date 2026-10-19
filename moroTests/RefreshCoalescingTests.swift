//
//  RefreshCoalescingTests.swift
//  moroTests
//
//  Overlapping refreshes share one request, and a load-more page that overlapped a refresh
//  is dropped instead of leaving a gap and a stale cursor.
//

import Foundation
import Testing
@testable import moro

/// Suspends callers until opened; `entered` reports that the first caller is waiting.
@MainActor
private final class Gate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isOpen = false
    private(set) var entered = false

    func wait() async {
        entered = true
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func untilEntered() async {
        while !entered { await Task.yield() }
    }
}

@MainActor
private final class Counter {
    var value = 0
}

@MainActor
struct RefreshCoalescingTests {
    private func conversation(_ id: String) -> Conversation {
        Conversation(id: id, unread: false, accounts: [], lastStatus: nil, updatedAt: Date())
    }

    @Test func overlappingRequestsShareOneRunPlusOneFollowUpPass() async {
        let runner = CoalescedRefresh()
        let gate = Gate()
        let counter = Counter()

        async let first: Void = runner.run {
            counter.value += 1
            if counter.value == 1 { await gate.wait() }
        }
        await gate.untilEntered()
        // Two more requests while the first is in flight collapse into one more pass.
        // Main-actor tasks run in order, each up to its first suspension, before the yield
        // returns, so both have joined when the gate opens.
        let second = Task { @MainActor in await runner.run { counter.value += 1 } }
        let third = Task { @MainActor in await runner.run { counter.value += 1 } }
        await Task.yield()
        gate.open()
        await first
        await second.value
        await third.value

        #expect(counter.value == 2)
        #expect(runner.isRunning == false)

        // Once idle, a new request runs again.
        await runner.run { counter.value += 1 }
        #expect(counter.value == 3)
    }

    @Test func directMessagesDropLoadMorePageThatOverlappedARefresh() async {
        let api = MockMastodonAPI()
        let gate = Gate()
        var firstPageLoads = 0
        var requestedCursors: [String?] = []
        api.fetchConversationsPageHandler = { maxID, _ in
            requestedCursors.append(maxID)
            if let maxID {
                if maxID == "cursor:old" {
                    await gate.wait()
                    return ConversationsPage(conversations: [self.conversation("stale-older")], nextMaxID: "cursor:stale")
                }
                return ConversationsPage(conversations: [self.conversation("fresh-older")], nextMaxID: nil)
            }
            firstPageLoads += 1
            if firstPageLoads == 1 {
                return ConversationsPage(conversations: [self.conversation("old-1")], nextMaxID: "cursor:old")
            }
            return ConversationsPage(
                conversations: [self.conversation("new-1"), self.conversation("old-1")],
                nextMaxID: "cursor:fresh"
            )
        }
        let viewModel = DirectMessagesViewModel(apiClient: api)
        await viewModel.loadInitial()

        async let loadMore: Void = viewModel.loadMore()
        await gate.untilEntered()
        await viewModel.refresh()
        gate.open()
        await loadMore

        #expect(viewModel.conversations.map(\.id) == ["new-1", "old-1"])

        // The next page continues the refreshed list, not the old one.
        await viewModel.loadMore()
        #expect(requestedCursors.last == "cursor:fresh")
        #expect(viewModel.conversations.map(\.id) == ["new-1", "old-1", "fresh-older"])
    }

    @Test func directMessagesConcurrentRefreshesShareOneRequest() async {
        let api = MockMastodonAPI()
        let gate = Gate()
        var firstPageLoads = 0
        api.fetchConversationsPageHandler = { _, _ in
            firstPageLoads += 1
            if firstPageLoads == 2 { await gate.wait() }
            return ConversationsPage(conversations: [self.conversation("c\(firstPageLoads)")], nextMaxID: nil)
        }
        let viewModel = DirectMessagesViewModel(apiClient: api)
        await viewModel.loadInitial()
        #expect(firstPageLoads == 1)

        async let pull: Void = viewModel.refresh()
        await gate.untilEntered()
        let foreground = Task { @MainActor in await viewModel.refresh() }
        let appear = Task { @MainActor in await viewModel.refresh() }
        await Task.yield()
        gate.open()
        await pull
        await foreground.value
        await appear.value

        // One refresh plus one follow-up pass, not three overlapping resets.
        #expect(firstPageLoads == 3)
        #expect(viewModel.conversations.map(\.id) == ["c3"])
    }
}
