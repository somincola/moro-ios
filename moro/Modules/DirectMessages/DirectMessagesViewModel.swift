//
//  DirectMessagesViewModel.swift
//  moro
//
//  ViewModel for direct-message conversations list.
//

import Foundation
import Combine

@MainActor
final class DirectMessagesViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}


    enum LoadingState {
        case idle
        case loading
        case loadingMore
        case loaded
        case error(Error)
    }

    @Published var conversations: [Conversation] = []
    @Published var loadingState: LoadingState = .idle
    @Published var transientErrorMessage: String?
    /// True when the most recent load-more page failed; drives the inline retry footer.
    @Published var loadMoreFailed: Bool = false

    private let apiClient: MastodonAPI
    private let pageSize: Int = 20
    private var currentMaxID: String?
    private var hasMore: Bool = true
    private var inFlightConversationRefreshIDs: Set<String> = []
    private let refreshRunner = CoalescedRefresh()
    /// Bumped when a first-page load starts and when it lands; a load-more page that
    /// overlapped either is stale.
    private var listGeneration = 0

    init(apiClient: MastodonAPI) {
        self.apiClient = apiClient
    }

    func loadInitial() async {
        guard case .idle = loadingState else { return }

        loadingState = .loading
        await refresh()
    }

    /// Pull, foreground and appear can all ask at once; they share one request.
    func refresh() async {
        await refreshRunner.run { [weak self] in await self?.load(reset: true) }
    }

    func loadMore() async {
        guard hasMore, case .loaded = loadingState else { return }

        loadingState = .loadingMore
        loadMoreFailed = false

        let generation = listGeneration
        do {
            let requestedMaxID = currentMaxID
            let page = try await apiClient.fetchConversationsPage(
                maxID: currentMaxID,
                limit: pageSize
            )
            // A refresh replaced the list meanwhile: this page continues the old one and
            // would leave a gap and a stale cursor. The refresh owns loadingState now.
            guard generation == listGeneration else { return }
            let existingIDs = Set(conversations.map(\.id))
            let newItems = page.conversations.filter { !existingIDs.contains($0.id) }
            conversations.append(contentsOf: newItems)
            updatePagination(
                nextMaxID: page.nextMaxID,
                requestedMaxID: requestedMaxID,
                receivedNewItems: !newItems.isEmpty
            )
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            guard generation == listGeneration else { return }
            // Keep already loaded data visible.
            loadingState = .loaded
            loadMoreFailed = true
        }
    }

    @discardableResult
    func markAsReadIfNeeded(_ conversation: Conversation) async -> Bool {
        guard conversation.unread else { return false }

        do {
            let updatedConversation = try await apiClient.markConversationRead(id: conversation.id)
            replaceConversation(updatedConversation)
            transientErrorMessage = nil
            return true
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.DirectMessages.toastMarkReadFailed)
            transientErrorMessage = MoroL10n.DirectMessages.errorMarkReadFailed
            return false
        }
    }

    @discardableResult
    func delete(_ conversation: Conversation) async -> Bool {
        do {
            try await apiClient.deleteConversation(id: conversation.id)
            conversations.removeAll { $0.id == conversation.id }
            AppFeedbackCenter.shared.showSuccess(MoroL10n.DirectMessages.toastDeleted)
            transientErrorMessage = nil
            return true
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.DirectMessages.toastDeleteFailed)
            transientErrorMessage = MoroL10n.DirectMessages.errorDeleteFailed
            return false
        }
    }

    func conversation(withParticipantID accountID: String) -> Conversation? {
        conversations.first { conversation in
            conversation.accounts.contains(where: { $0.id == accountID })
        }
    }

    func handleStreamEvent(_ event: StreamEvent) {
        switch event {
        case .conversation(let conversationID, let unread, let lastStatus):
            let requiresRefresh = upsertConversationFromStream(
                conversationID: conversationID,
                unread: unread,
                lastStatus: lastStatus
            )
            if requiresRefresh {
                Task { await refreshConversationByID(conversationID) }
            }

        case .delete(let statusID):
            handleDeleteEvent(statusID: statusID)

        case .update, .statusUpdate, .notification:
            break
        }
    }

    private func load(reset: Bool) async {
        if reset { listGeneration += 1 }
        do {
            let page = try await apiClient.fetchConversationsPage(
                maxID: nil,
                limit: pageSize
            )
            let items = uniqueConversations(page.conversations)
            if reset {
                // Also bumped here: a load-more that started while this request was in
                // flight read the old cursor.
                listGeneration += 1
                conversations = items
            } else {
                let existingIDs = Set(conversations.map(\.id))
                conversations.append(contentsOf: items.filter { !existingIDs.contains($0.id) })
            }
            updatePagination(
                nextMaxID: page.nextMaxID,
                requestedMaxID: nil,
                receivedNewItems: !items.isEmpty
            )
            loadingState = .loaded
            transientErrorMessage = nil
        } catch {
            loadingState = .error(error)
            transientErrorMessage = MoroL10n.DirectMessages.errorLoadFailedDetail
        }
    }

    private func replaceConversation(_ conversation: Conversation) {
        guard let index = conversations.firstIndex(where: { $0.id == conversation.id }) else { return }
        conversations[index] = conversation
    }

    private func uniqueConversations(_ items: [Conversation]) -> [Conversation] {
        var seen: Set<String> = []
        return items.filter { seen.insert($0.id).inserted }
    }

    private func updatePagination(
        nextMaxID: String?,
        requestedMaxID: String?,
        receivedNewItems: Bool
    ) {
        guard receivedNewItems,
            let nextMaxID,
            nextMaxID != requestedMaxID
        else {
            currentMaxID = nil
            hasMore = false
            return
        }
        currentMaxID = nextMaxID
        hasMore = true
    }

    private func upsertConversationFromStream(
        conversationID: String,
        unread: Bool,
        lastStatus: Status?
    ) -> Bool {
        if let index = conversations.firstIndex(where: { $0.id == conversationID }) {
            let current = conversations.remove(at: index)
            let updated = Conversation(
                id: current.id,
                unread: unread,
                accounts: current.accounts,
                lastStatus: lastStatus ?? current.lastStatus,
                updatedAt: lastStatus?.createdAt ?? Date()
            )
            conversations.insert(updated, at: 0)
            return lastStatus == nil
        }

        let fallbackConversation = Conversation(
            id: conversationID,
            unread: unread,
            accounts: lastStatus.map { [$0.account] } ?? [],
            lastStatus: lastStatus,
            updatedAt: lastStatus?.createdAt ?? Date()
        )
        conversations.insert(fallbackConversation, at: 0)
        return true
    }

    private func handleDeleteEvent(statusID: String) {
        guard let index = conversations.firstIndex(where: { $0.lastStatus?.id == statusID }) else {
            return
        }

        let current = conversations[index]
        conversations[index] = Conversation(
            id: current.id,
            unread: current.unread,
            accounts: current.accounts,
            lastStatus: nil,
            updatedAt: current.updatedAt
        )

        Task { await refreshConversationByID(current.id) }
    }

    private func refreshConversationByID(_ conversationID: String) async {
        guard !inFlightConversationRefreshIDs.contains(conversationID) else { return }
        inFlightConversationRefreshIDs.insert(conversationID)
        defer { inFlightConversationRefreshIDs.remove(conversationID) }

        do {
            let items = try await apiClient.fetchConversations(
                maxID: nil,
                sinceID: nil,
                limit: pageSize
            )
            guard let latest = items.first(where: { $0.id == conversationID }) else { return }
            replaceOrInsertAtTop(latest)
        } catch {
            // Silent fallback: keep currently visible local state.
        }
    }

    private func replaceOrInsertAtTop(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations.remove(at: index)
        }
        conversations.insert(conversation, at: 0)
    }
}
