//
//  InboxUnreadStore.swift
//  moro
//
//  Aggregates notification and direct-message unread state for the Inbox entry.
//

import Combine
import Foundation
import WidgetKit

enum InboxUnreadPersistenceKeys {
    static let directMessageUnreadConversationIDsBySession =
        "direct_message_unread_conversation_ids_by_session_v1"
}

@MainActor
final class InboxUnreadStore: ObservableObject {
    static let shared = InboxUnreadStore()

    @Published private(set) var notificationUnreadCount: Int
    @Published private(set) var messageUnreadCount = 0

    var totalUnreadCount: Int {
        notificationUnreadCount + messageUnreadCount
    }

    private struct StreamOverride {
        let unread: Bool
        let revision: Int
    }

    private struct ConversationSnapshot {
        let conversations: [Conversation]

        var unreadIDs: Set<String> {
            Set(conversations.lazy.filter(\.unread).map(\.id))
        }
    }

    private let notificationUnreadStore: NotificationUnreadStore
    private let userDefaults: UserDefaults
    private var notificationCountCancellable: AnyCancellable?
    private var streamCancellable: AnyCancellable?
    private var unreadIDsBySession: [String: Set<String>]
    private var conversationsBySession: [String: [String: Conversation]] = [:]
    private var streamRevisionBySession: [String: Int] = [:]
    private var streamOverridesBySession: [String: [String: StreamOverride]] = [:]
    private var reconciliationTokenBySession: [String: UUID] = [:]
    private var activeSessionID: String?
    private var activeAPIClient: MastodonAPI?

    init(
        notificationUnreadStore: NotificationUnreadStore? = nil,
        userDefaults: UserDefaults = MoroSharedContainer.sharedUserDefaults(),
        streamEvents: AnyPublisher<StreamEvent, Never>? = nil
    ) {
        let notificationUnreadStore = notificationUnreadStore ?? .shared
        self.notificationUnreadStore = notificationUnreadStore
        self.userDefaults = userDefaults
        self.notificationUnreadCount = notificationUnreadStore.activeUnreadCount
        self.unreadIDsBySession = Self.loadUnreadIDs(from: userDefaults)

        notificationCountCancellable = notificationUnreadStore.$activeUnreadCount
            .sink { [weak self] count in
                Task { @MainActor [weak self] in
                    self?.notificationUnreadCount = count
                }
            }

        let publisher = streamEvents ?? StreamWatcher.shared.events.eraseToAnyPublisher()
        streamCancellable = publisher.sink { [weak self] event in
            guard case .conversation(let conversationID, let unread, let lastStatus) = event else {
                return
            }
            Task { @MainActor [weak self] in
                self?.receiveConversationEvent(
                    id: conversationID,
                    unread: unread,
                    lastStatus: lastStatus
                )
            }
        }
    }

    func activate(
        sessionID: String?,
        availableSessionIDs: [String],
        apiClient: MastodonAPI
    ) async {
        let availableSessionIDs = Set(availableSessionIDs)
        activeSessionID = sessionID
        activeAPIClient = apiClient

        if !availableSessionIDs.isEmpty {
            unreadIDsBySession = unreadIDsBySession.filter {
                availableSessionIDs.contains($0.key)
            }
            conversationsBySession = conversationsBySession.filter {
                availableSessionIDs.contains($0.key)
            }
            streamOverridesBySession = streamOverridesBySession.filter {
                availableSessionIDs.contains($0.key)
            }
            persistUnreadIDs()
        }

        publishActiveCounts()
        await reconcileActiveCount()
    }

    func reconcileActiveCount() async {
        guard let sessionID = activeSessionID, let apiClient = activeAPIClient else { return }

        let token = UUID()
        reconciliationTokenBySession[sessionID] = token
        let startingRevision = streamRevisionBySession[sessionID, default: 0]

        do {
            let snapshot = try await fetchConversationSnapshot(apiClient: apiClient)
            guard reconciliationTokenBySession[sessionID] == token else { return }

            var resolvedUnreadIDs = snapshot.unreadIDs
            for (conversationID, override) in streamOverridesBySession[sessionID, default: [:]]
            where override.revision > startingRevision {
                if override.unread {
                    resolvedUnreadIDs.insert(conversationID)
                } else {
                    resolvedUnreadIDs.remove(conversationID)
                }
            }

            conversationsBySession[sessionID] = Dictionary(
                uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0) }
            )
            setUnreadIDs(resolvedUnreadIDs, for: sessionID)
            streamOverridesBySession[sessionID] = streamOverridesBySession[sessionID]?.filter {
                $0.value.revision > startingRevision
            }
        } catch {
            AppLogger.error("[Inbox] direct-message unread reconciliation failed: \(error)")
        }
    }

    func isActive(sessionID: String?) -> Bool {
        activeSessionID == sessionID && activeAPIClient != nil
    }

    func markConversationRead(id: String) {
        guard let sessionID = activeSessionID else { return }
        updateUnreadState(false, conversationID: id, sessionID: sessionID, recordsOverride: true)
    }

    func removeConversation(id: String) {
        guard let sessionID = activeSessionID else { return }
        conversationsBySession[sessionID]?[id] = nil
        updateUnreadState(false, conversationID: id, sessionID: sessionID, recordsOverride: true)
    }

    private func receiveConversationEvent(
        id: String,
        unread: Bool,
        lastStatus: Status?
    ) {
        guard let sessionID = activeSessionID else { return }

        let revision = streamRevisionBySession[sessionID, default: 0] + 1
        streamRevisionBySession[sessionID] = revision
        streamOverridesBySession[sessionID, default: [:]][id] = StreamOverride(
            unread: unread,
            revision: revision
        )

        if let current = conversationsBySession[sessionID]?[id] {
            conversationsBySession[sessionID]?[id] = Conversation(
                id: current.id,
                unread: unread,
                accounts: current.accounts,
                lastStatus: lastStatus ?? current.lastStatus,
                updatedAt: lastStatus?.createdAt ?? Date()
            )
        }

        updateUnreadState(
            unread,
            conversationID: id,
            sessionID: sessionID,
            recordsOverride: false
        )
    }

    private func updateUnreadState(
        _ unread: Bool,
        conversationID: String,
        sessionID: String,
        recordsOverride: Bool
    ) {
        var unreadIDs = unreadIDsBySession[sessionID, default: []]
        let changed: Bool
        if unread {
            changed = unreadIDs.insert(conversationID).inserted
        } else {
            changed = unreadIDs.remove(conversationID) != nil
        }

        if recordsOverride {
            let revision = streamRevisionBySession[sessionID, default: 0] + 1
            streamRevisionBySession[sessionID] = revision
            streamOverridesBySession[sessionID, default: [:]][conversationID] = StreamOverride(
                unread: unread,
                revision: revision
            )
        }

        guard changed else { return }
        setUnreadIDs(unreadIDs, for: sessionID)
    }

    private func setUnreadIDs(_ ids: Set<String>, for sessionID: String) {
        unreadIDsBySession[sessionID] = ids
        persistUnreadIDs()
        publishActiveCounts()
    }

    private func publishActiveCounts() {
        messageUnreadCount = activeSessionID.map {
            unreadIDsBySession[$0, default: []].count
        } ?? 0
    }

    private func persistUnreadIDs() {
        let value = unreadIDsBySession.mapValues { Array($0).sorted() }
        userDefaults.set(value, forKey: InboxUnreadPersistenceKeys.directMessageUnreadConversationIDsBySession)
        WidgetCenter.shared.reloadTimelines(ofKind: MoroWidgetKind.overview)
        WidgetCenter.shared.reloadTimelines(ofKind: MoroWidgetKind.quickActions)
        Task { [weak notificationUnreadStore = notificationUnreadStore] in
            await notificationUnreadStore?.refreshAppIconBadge()
        }
    }

    private func fetchConversationSnapshot(apiClient: MastodonAPI) async throws
        -> ConversationSnapshot
    {
        let pageSize = 40
        let maximumCount = 1_000
        let maximumPageCount = 100
        var maxID: String?
        var conversationsByID: [String: Conversation] = [:]
        var visitedCursors: Set<String> = []
        var fetchedPageCount = 0

        while conversationsByID.count < maximumCount, fetchedPageCount < maximumPageCount {
            let page = try await apiClient.fetchConversationsPage(
                maxID: maxID,
                limit: pageSize
            )
            fetchedPageCount += 1
            page.conversations.forEach { conversationsByID[$0.id] = $0 }

            guard let nextMaxID = page.nextMaxID,
                nextMaxID != maxID,
                visitedCursors.insert(nextMaxID).inserted
            else {
                break
            }
            maxID = nextMaxID
        }

        return ConversationSnapshot(conversations: Array(conversationsByID.values))
    }

    private static func loadUnreadIDs(from userDefaults: UserDefaults) -> [String: Set<String>] {
        guard let stored = userDefaults.dictionary(
            forKey: InboxUnreadPersistenceKeys.directMessageUnreadConversationIDsBySession
        ) else {
            return [:]
        }

        return stored.reduce(into: [:]) { result, entry in
            if let ids = entry.value as? [String] {
                result[entry.key] = Set(ids)
            }
        }
    }

    private static func activityDate(for conversation: Conversation) -> Date {
        conversation.lastStatus?.createdAt ?? conversation.updatedAt ?? .distantPast
    }
}
