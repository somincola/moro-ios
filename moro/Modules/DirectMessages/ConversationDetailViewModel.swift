//
//  ConversationDetailViewModel.swift
//  moro
//
//  ViewModel for direct-message conversation detail.
//

import Foundation
import Combine

@MainActor
final class ConversationDetailViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState {
        case idle
        case loading
        case loaded
        case error(Error)
    }

    @Published private(set) var conversation: Conversation
    @Published private(set) var messages: [Status] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published var draftMessage: String = ""
    @Published private(set) var isSending: Bool = false
    @Published private(set) var sendErrorMessage: String?
    @Published private(set) var lastFailedDraft: String?

    private let apiClient: MastodonAPI

    init(conversation: Conversation, apiClient: MastodonAPI) {
        self.conversation = conversation
        self.apiClient = apiClient
    }

    func loadInitial() async {
        guard case .idle = loadingState else { return }
        loadingState = .loading
        await load()
    }

    func refresh() async {
        await load()
    }

    var canSendMessage: Bool {
        Self.hasSendableContent(draftMessage) && !isSending
    }

    var canRetryLastFailedSend: Bool {
        lastFailedDraft != nil && !isSending
    }

    var rootStatus: Status? {
        ConversationThreadPresentation.rootStatus(in: messages)
    }

    var replyMessages: [Status] {
        ConversationThreadPresentation.replyMessages(
            in: messages,
            rootStatus: rootStatus
        )
    }

    @discardableResult
    func sendMessage(currentUserID: String?) async -> Bool {
        guard canSendMessage else { return false }

        let draft = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = Self.buildOutgoingText(
            draft: draft,
            participants: conversation.accounts,
            currentUserID: currentUserID
        )

        sendErrorMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let posted = try await apiClient.postStatus(
                text: text,
                visibility: .direct,
                mediaIDs: nil,
                inReplyToID: messages.last?.id ?? conversation.lastStatus?.id,
                spoilerText: nil,
                sensitive: nil,
                quotingID: nil,
                language: nil,
                poll: nil
            )

            appendMessage(posted)
            conversation = Conversation(
                id: conversation.id,
                unread: false,
                accounts: conversation.accounts,
                lastStatus: posted,
                updatedAt: Date()
            )
            draftMessage = ""
            sendErrorMessage = nil
            lastFailedDraft = nil
            loadingState = .loaded
            return true
        } catch {
            sendErrorMessage = MoroL10n.ConversationVM.sendFailed
            lastFailedDraft = draft
            AppFeedbackCenter.shared.showError(MoroL10n.ConversationVM.sendFailedShort)
            return false
        }
    }

    @discardableResult
    func retryLastFailedSend(currentUserID: String?) async -> Bool {
        guard !isSending else { return false }
        guard let failedDraft = lastFailedDraft, !failedDraft.isEmpty else {
            return await sendMessage(currentUserID: currentUserID)
        }

        if !Self.hasSendableContent(draftMessage) {
            draftMessage = failedDraft
        }

        return await sendMessage(currentUserID: currentUserID)
    }

    func handleStreamEvent(_ event: StreamEvent) {
        switch event {
        case .conversation(let conversationID, let unread, let lastStatus):
            guard conversationID == conversation.id, let lastStatus else { return }
            appendMessage(lastStatus)
            conversation = Conversation(
                id: conversation.id,
                unread: unread,
                accounts: conversation.accounts,
                lastStatus: lastStatus,
                updatedAt: Date()
            )
            loadingState = .loaded

        case .delete(let statusID):
            removeMessage(id: statusID)

        case .update, .statusUpdate, .notification:
            break
        }
    }

    private func load() async {
        // Mark unread conversations as read when opening detail.
        _ = await markCurrentConversationReadIfNeeded()

        guard let lastStatus = conversation.lastStatus else {
            messages = []
            loadingState = .loaded
            return
        }

        do {
            let context = try await apiClient.fetchStatusContext(id: lastStatus.id)
            messages = mergeAndSortStatuses(
                ancestors: context.ancestors,
                focus: lastStatus,
                descendants: context.descendants
            )
            loadingState = .loaded
        } catch {
            // A refresh failure must not discard the conversation already read.
            // The last-status preview is only a fallback for a cold open.
            if messages.isEmpty {
                messages = [lastStatus]
            }
            loadingState = .error(error)
        }
    }

    @discardableResult
    func markCurrentConversationReadIfNeeded() async -> Bool {
        guard conversation.unread, !conversation.isDraft else { return false }

        do {
            conversation = try await apiClient.markConversationRead(id: conversation.id)
            return true
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.ConversationVM.markReadFailed)
            return false
        }
    }

    private func mergeAndSortStatuses(
        ancestors: [Status],
        focus: Status,
        descendants: [Status]
    ) -> [Status] {
        var byID: [String: Status] = [:]
        for status in ancestors + [focus] + descendants {
            byID[status.id] = status
        }

        return byID.values.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func appendMessage(_ status: Status) {
        if let index = messages.firstIndex(where: { $0.id == status.id }) {
            messages[index] = status
        } else {
            messages.append(status)
        }
        messages.sort { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.id < rhs.id
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private func removeMessage(id: String) {
        guard messages.contains(where: { $0.id == id }) else { return }
        messages.removeAll { $0.id == id }
        let newest = messages.last
        conversation = Conversation(
            id: conversation.id,
            unread: false,
            accounts: conversation.accounts,
            lastStatus: newest,
            updatedAt: Date()
        )
    }

    static func hasSendableContent(_ draft: String) -> Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func buildOutgoingText(
        draft: String,
        participants: [Account],
        currentUserID: String?
    ) -> String {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return "" }

        let existingMentionTokens = Set(
            trimmedDraft
                .split(whereSeparator: \.isWhitespace)
                .filter { $0.hasPrefix("@") }
                .map { normalizeMentionToken(String($0)) }
        )

        var missingMentions: [String] = []
        for account in participants where account.id != currentUserID {
            let acct = account.acct.hasPrefix("@") ? account.acct : "@\(account.acct)"
            let mentionToken = normalizeMentionToken(acct)
            if !mentionToken.isEmpty, !existingMentionTokens.contains(mentionToken) {
                missingMentions.append(mentionToken)
            }
        }

        if missingMentions.isEmpty {
            return trimmedDraft
        }

        return (missingMentions + [trimmedDraft]).joined(separator: " ")
    }

    private static func normalizeMentionToken(_ token: String) -> String {
        var value = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.hasPrefix("@") {
            value = "@\(value)"
        }
        value = value.trimmingCharacters(
            in: CharacterSet(charactersIn: ".,:;!?)]}\"'")
        )
        return value.lowercased()
    }
}

struct ConversationThreadPresentation {
    static func rootStatus(in messages: [Status]) -> Status? {
        // A direct root is the first message, with the same content and actions
        // as later messages. Only a non-direct origin belongs in the context card.
        messages.first { status in
            guard let visibility = status.visibility else { return false }
            return status.inReplyToID == nil && visibility != "direct"
        }
    }

    static func replyMessages(in messages: [Status], rootStatus: Status?) -> [Status] {
        guard let rootStatus else { return messages }
        return messages.filter { $0.id != rootStatus.id }
    }
}
