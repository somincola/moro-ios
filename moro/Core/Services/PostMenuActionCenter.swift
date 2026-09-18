//
//  PostMenuActionCenter.swift
//  moro
//
//  Centralized dispatcher for status "more" menu actions.
//

import Combine
import UIKit

@MainActor
final class PostMenuActionCenter: ObservableObject {
    struct Handlers {
        let onShare: () -> Void
        let onCopyLink: () -> Void
        let onCopyText: () -> Void
        let onOpenInBrowser: () -> Void
        let onMuteUser: () -> Void
        let onBlockUser: () -> Void
        let onBlockAndReport: () -> Void
        let onReport: () -> Void
        let isMutingUser: Bool?
        let isBlockingUser: Bool?
    }

    private let apiClient: MastodonAPI
    @Published private var relationshipCache: [String: Relationship] = [:]
    private let relationshipCacheLimit: Int
    private var relationshipAccessOrder: [String] = []
    private var loadingAccountIDs: Set<String> = []

    init(apiClient: MastodonAPI, relationshipCacheLimit: Int = 200) {
        self.apiClient = apiClient
        self.relationshipCacheLimit = max(1, relationshipCacheLimit)
    }

    func handlers(
        for status: Status,
        prefetchRelationship: Bool = true,
        onReport: @escaping (Status) -> Void
    ) -> Handlers {
        let targetStatus = status.displayStatus
        let accountID = targetStatus.account.id
        if prefetchRelationship {
            prefetchRelationshipIfNeeded(for: accountID)
        }
        let relationship = cachedRelationship(for: accountID)

        return Handlers(
            onShare: { self.share(targetStatus) },
            onCopyLink: { self.copyLink(targetStatus) },
            onCopyText: { self.copyText(targetStatus) },
            onOpenInBrowser: { self.openInBrowser(targetStatus) },
            onMuteUser: { self.toggleMute(for: targetStatus) },
            onBlockUser: { self.toggleBlock(for: targetStatus) },
            onBlockAndReport: { self.blockAndReport(for: targetStatus, onReport: onReport) },
            onReport: { onReport(targetStatus) },
            isMutingUser: relationship?.muting,
            isBlockingUser: relationship?.blocking
        )
    }

    func share(_ status: Status) {
        guard let url = status.url else {
            AppFeedbackCenter.shared.showError(MoroL10n.PostMenu.shareMissingLink)
            return
        }

        let activityVC = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        guard let presenter = topViewController() else {
            AppFeedbackCenter.shared.showError(MoroL10n.PostMenu.shareUnavailable)
            return
        }
        activityVC.popoverPresentationController?.sourceView = presenter.view
        presenter.present(activityVC, animated: true)
    }

    func copyLink(_ status: Status) {
        guard let url = status.url else {
            AppFeedbackCenter.shared.showError(MoroL10n.PostMenu.copyLinkMissing)
            return
        }

        UIPasteboard.general.url = url
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AppFeedbackCenter.shared.showSuccess(MoroL10n.PostMenu.linkCopied)
    }

    func copyText(_ status: Status) {
        let plainText = HTMLParser.stripHTML(status.content).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else {
            AppFeedbackCenter.shared.showError(MoroL10n.PostMenu.copyTextEmpty)
            return
        }

        UIPasteboard.general.string = plainText
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AppFeedbackCenter.shared.showSuccess(MoroL10n.PostMenu.textCopied)
    }

    func openInBrowser(_ status: Status) {
        guard let url = status.url else {
            AppFeedbackCenter.shared.showError(MoroL10n.PostMenu.openInBrowserMissing)
            return
        }

        UIApplication.shared.open(url)
    }

    private func toggleMute(for status: Status) {
        let account = status.account
        _ = Task { @MainActor [weak self] in
            guard let self else { return }
            let relationship = await self.relationship(for: account.id)
            let isMuting = relationship?.muting == true

            let performToggle: () -> Void = {
                _ = Task { @MainActor in
                    do {
                        let updatedRelationship =
                            try await
                            (isMuting
                            ? self.apiClient.unmuteAccount(id: account.id)
                            : self.apiClient.muteAccount(id: account.id))
                        self.storeRelationship(updatedRelationship)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        AppFeedbackCenter.shared.showSuccess(
                            isMuting ? MoroL10n.PostMenu.userUnmuted : MoroL10n.PostMenu.userMuted
                        )
                    } catch {
                        AppFeedbackCenter.shared.showError(MoroL10n.PostMenu.muteFailed)
                        AppLogger.error("Failed to toggle mute user: \(error)")
                    }
                }
            }

            if AppSettings.shared.askBeforeMutingAUser {
                presentConfirmation(
                    title: isMuting
                        ? MoroL10n.PostMenu.unmuteConfirmTitle(account.username)
                        : MoroL10n.PostMenu.muteConfirmTitle(account.username),
                    message: isMuting
                        ? MoroL10n.PostMenu.unmuteConfirmMessage
                        : MoroL10n.PostMenu.muteConfirmMessage,
                    confirmTitle: isMuting ? MoroL10n.PostMenu.actionUnmute : MoroL10n.PostMenu.actionMute,
                    isDestructive: false,
                    onConfirm: performToggle
                )
            } else {
                performToggle()
            }
        }
    }

    private func toggleBlock(for status: Status) {
        toggleBlock(for: status, afterToggle: nil)
    }

    private func blockAndReport(
        for status: Status,
        onReport: @escaping (Status) -> Void
    ) {
        let accountID = status.account.id
        if cachedRelationship(for: accountID)?.blocking == true {
            onReport(status)
            return
        }
        toggleBlock(for: status) {
            onReport(status)
        }
    }

    private func toggleBlock(
        for status: Status,
        afterToggle: (() -> Void)?
    ) {
        let account = status.account
        _ = Task { @MainActor [weak self] in
            guard let self else { return }
            let relationship = await self.relationship(for: account.id)
            let isBlocking = relationship?.blocking == true

            let performToggle: () -> Void = {
                _ = Task { @MainActor in
                    do {
                        let updatedRelationship =
                            try await
                            (isBlocking
                            ? self.apiClient.unblockAccount(id: account.id)
                            : self.apiClient.blockAccount(id: account.id))
                        self.storeRelationship(updatedRelationship)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        AppFeedbackCenter.shared.showSuccess(
                            isBlocking ? MoroL10n.PostMenu.userUnblocked : MoroL10n.PostMenu.userBlocked
                        )
                        if !isBlocking {
                            afterToggle?()
                        }
                    } catch {
                        AppFeedbackCenter.shared.showError(MoroL10n.PostMenu.blockFailed)
                        AppLogger.error("Failed to toggle block user: \(error)")
                    }
                }
            }

            if AppSettings.shared.askBeforeBlockingAUser {
                presentConfirmation(
                    title: isBlocking
                        ? MoroL10n.PostMenu.unblockConfirmTitle(account.username)
                        : MoroL10n.PostMenu.blockConfirmTitle(account.username),
                    message: isBlocking
                        ? MoroL10n.PostMenu.unblockConfirmMessage
                        : MoroL10n.PostMenu.blockConfirmMessage,
                    confirmTitle: isBlocking ? MoroL10n.PostMenu.actionUnblock : MoroL10n.PostMenu.actionBlock,
                    isDestructive: !isBlocking,
                    onConfirm: performToggle
                )
            } else {
                performToggle()
            }
        }
    }

    private func prefetchRelationshipIfNeeded(for accountID: String) {
        guard cachedRelationship(for: accountID) == nil else { return }
        guard !loadingAccountIDs.contains(accountID) else { return }

        loadingAccountIDs.insert(accountID)
        _ = Task { @MainActor in
            defer { loadingAccountIDs.remove(accountID) }
            _ = await relationship(for: accountID)
        }
    }

    private func relationship(for accountID: String) async -> Relationship? {
        if let cached = cachedRelationship(for: accountID) {
            return cached
        }

        do {
            let relationships = try await apiClient.fetchRelationships(accountIDs: [accountID])
            let relationship = relationships.first
            if let relationship {
                storeRelationship(relationship)
            }
            return relationship
        } catch {
            AppLogger.error("Failed to fetch relationship: \(error)")
            return nil
        }
    }

    private func cachedRelationship(for accountID: String) -> Relationship? {
        guard let relationship = relationshipCache[accountID] else { return nil }
        markRelationshipAsRecentlyUsed(accountID)
        return relationship
    }

    private func storeRelationship(_ relationship: Relationship) {
        var updatedCache = relationshipCache
        updatedCache[relationship.id] = relationship
        markRelationshipAsRecentlyUsed(relationship.id)

        while relationshipAccessOrder.count > relationshipCacheLimit {
            let evictedAccountID = relationshipAccessOrder.removeFirst()
            updatedCache.removeValue(forKey: evictedAccountID)
        }

        relationshipCache = updatedCache
    }

    private func markRelationshipAsRecentlyUsed(_ accountID: String) {
        relationshipAccessOrder.removeAll { $0 == accountID }
        relationshipAccessOrder.append(accountID)
    }

    private func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)

        var topController = keyWindow?.rootViewController
        while let presented = topController?.presentedViewController {
            topController = presented
        }

        return topController
    }

    private func presentConfirmation(
        title: String,
        message: String,
        confirmTitle: String,
        isDestructive: Bool,
        onConfirm: @escaping () -> Void
    ) {
        guard let presenter = topViewController() else {
            onConfirm()
            return
        }

        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: MoroL10n.Common.cancel, style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: confirmTitle,
                style: isDestructive ? .destructive : .default
            ) { _ in
                onConfirm()
            }
        )
        presenter.present(alert, animated: true)
    }
}

