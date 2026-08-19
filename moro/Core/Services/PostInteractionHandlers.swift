//
//  PostInteractionHandlers.swift
//  moro
//
//  Shared post interaction handlers used across timeline, profile, detail, and other views.
//

import UIKit

@MainActor
struct PostInteractionHandlers {
    let interactionService: PostInteractionService
    let actionSurface: PostActionSurfaceCenter
    let postMenuActionCenter: PostMenuActionCenter
    let apiClient: MastodonAPI
    let currentUserID: String?
    let router: AppRouter
    let onRemoveStatus: ((String) -> Void)?

    func handleLike(_ status: Status) {
        Task { await interactionService.toggleFavourite(status) }
    }

    func handleBoost(_ status: Status) {
        actionSurface.presentBoostOrToggle(
            for: status,
            currentUserID: currentUserID
        ) {
            Task { await interactionService.toggleBoost(status) }
        }
    }

    func handleBookmark(_ status: Status) {
        Task { await interactionService.toggleBookmark(status) }
    }

    func handleReply(_ status: Status) {
        actionSurface.startReply(to: status)
    }

    func handleEdit(_ status: Status) {
        actionSurface.startEdit(status)
    }

    func handleDelete(_ status: Status) {
        // Honor the "ask before deleting a post" setting: when off, delete
        // immediately; when on (default), show the confirm/redraft dialog.
        if AppSettings.shared.askBeforeDeletingAPost {
            actionSurface.requestDelete(status)
        } else {
            performDelete(status)
        }
    }

    func handlePin(_ status: Status) {
        Task {
            do {
                let isPinned = status.pinned == true
                let updatedStatus = try await (
                    isPinned
                    ? apiClient.unpinStatus(id: status.id)
                    : apiClient.pinStatus(id: status.id)
                )
                FeedCoordinator.shared.publishUpdate(.post(updatedStatus))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AppFeedbackCenter.shared.showSuccess(
                    isPinned ? MoroL10n.PostInteraction.unpinned : MoroL10n.PostInteraction.pinned
                )
            } catch {
                AppFeedbackCenter.shared.showError(MoroL10n.PostInteraction.pinFailed)
                AppLogger.error("Failed to pin/unpin status: \(error)")
            }
        }
    }

    func performDelete(_ status: Status, redraft: Bool = false) {
        Task {
            do {
                try await apiClient.deleteStatus(id: status.id)
                onRemoveStatus?(status.id)
                FeedCoordinator.shared.publishUpdate(.deletedPost(status.id))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if redraft {
                    actionSurface.startRedraft(from: status, accountID: currentUserID)
                    if !status.displayStatus.mediaAttachments.isEmpty {
                        AppFeedbackCenter.shared.showInfo(MoroL10n.ComposeDrafts.redraftMediaOmitted)
                    }
                } else {
                    AppFeedbackCenter.shared.showSuccess(MoroL10n.PostInteraction.deleted)
                }
            } catch {
                AppFeedbackCenter.shared.showError(MoroL10n.PostInteraction.deleteFailed)
                AppLogger.error("Failed to delete status: \(error)")
            }
        }
    }

    func moreMenuHandlers(
        for status: Status,
        prefetchRelationship: Bool = true
    ) -> PostMenuActionCenter.Handlers {
        postMenuActionCenter.handlers(
            for: status,
            prefetchRelationship: prefetchRelationship
        ) { reportStatus in
            actionSurface.presentReport(for: reportStatus)
        }
    }

    func buildPostActions(
        for status: Status,
        onPollVote: ((String, [Int]) async -> Bool)? = nil
    ) -> PostActions {
        let menuHandlers = moreMenuHandlers(for: status)
        let navHandlers = PostNavigationActionCenter.handlers(for: status, router: router)
        return PostActions(
            navigation: navHandlers,
            menu: menuHandlers,
            onLike: { handleLike(status) },
            onBoost: { handleBoost(status) },
            onBookmark: { handleBookmark(status) },
            onReply: { handleReply(status) },
            onPollVote: onPollVote,
            onEdit: PostMoreMenuPolicy.canEditPost(
                status, currentUserID: currentUserID
            ) ? { handleEdit(status) } : nil,
            onPin: { handlePin(status) },
            onDelete: { handleDelete(status) },
            onTap: navHandlers.onTapDetail,
            isOwnPost: PostMoreMenuPolicy.isOwnPost(
                status, currentUserID: currentUserID
            )
        )
    }
}
