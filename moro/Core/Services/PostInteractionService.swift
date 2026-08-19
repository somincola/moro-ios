//
//  PostInteractionService.swift
//  moro
//
//  Unified service for handling post interactions (like, boost, bookmark).
//  Implements optimistic updates and error rollback.
//

import Foundation
import Combine
import SwiftUI

/// Service for handling post interactions
@MainActor
final class PostInteractionService: ObservableObject {
    /// Current action being performed (for preventing duplicate actions)
    @Published var isPerformingAction: (action: PostAction, statusID: String)?
    
    /// Active alert to show
    @Published var activeAlert: InteractionAlert?
    
    /// Types of post actions
    enum PostAction {
        case favourite
        case unfavourite
        case boost
        case unboost
        case bookmark
        case unbookmark
    }
    
    /// Types of alerts
    enum InteractionAlert: Identifiable {
        case confirmBoost(didConfirm: (Bool) -> Void)
        
        var id: String {
            switch self {
            case .confirmBoost:
                return "confirmBoost"
            }
        }
    }
    
    private let apiClient: MastodonAPI
    private let feedCoordinator: FeedCoordinator
    
    @MainActor
    init(apiClient: MastodonAPI, feedCoordinator: FeedCoordinator? = nil) {
        self.apiClient = apiClient
        self.feedCoordinator = feedCoordinator ?? FeedCoordinator.shared
    }
    
    // MARK: - Public API
    
    /// Handle favourite/unfavourite action
    func toggleFavourite(_ status: Status) async {
        guard isPerformingAction == nil else { return }
        
        let targetStatus = status.displayStatus
        let targetStatusID = targetStatus.id
        let isCurrentlyFavourited = targetStatus.favourited
        let expectedCount = isCurrentlyFavourited
            ? max(0, targetStatus.favouritesCount - 1)
            : targetStatus.favouritesCount + 1
        
        // Optimistic update
        let optimisticStatus = status.updating(
            favouritesCount: expectedCount,
            favourited: !isCurrentlyFavourited
        )
        
        // Set performing action
        isPerformingAction = (isCurrentlyFavourited ? .unfavourite : .favourite, targetStatusID)
        
        // Publish optimistic update
        feedCoordinator.publishUpdate(.post(optimisticStatus))
        
        // Perform API call
        do {
            let result = try await (isCurrentlyFavourited
                ? apiClient.unfavouriteStatus(id: targetStatusID)
                : apiClient.favouriteStatus(id: targetStatusID))
            
            // Publish real update
            feedCoordinator.publishUpdate(
                .post(
                    normalizedFavouriteResult(
                        result,
                        originalCount: targetStatus.favouritesCount,
                        expectedCount: expectedCount,
                        shouldBeFavourited: !isCurrentlyFavourited
                    )
                )
            )
        } catch {
            // Rollback on error
            feedCoordinator.publishUpdate(.post(status))
            AppFeedbackCenter.shared.showError(MoroL10n.StatusAction.failureToastLike)
            AppLogger.error("Failed to toggle favourite: \(error)")
        }
        
        // Clear performing action
        isPerformingAction = nil
    }
    
    /// Handle boost/unboost action
    func toggleBoost(_ status: Status, askFirst: Bool? = nil) async {
        guard isPerformingAction == nil else { return }
        
        let targetStatus = status.displayStatus
        let targetStatusID = targetStatus.id
        let isCurrentlyBoosted = targetStatus.reblogged
        let expectedCount = isCurrentlyBoosted
            ? max(0, targetStatus.reblogsCount - 1)
            : targetStatus.reblogsCount + 1
        
        // Determine if we should ask first:
        // 1. If askFirst is explicitly provided, use it
        // 2. Otherwise, check AppSettings
        let shouldAskFirst = askFirst ?? AppSettings.shared.askBeforeBoostingAPost
        
        // If asking first and not currently boosted, show confirmation
        if shouldAskFirst && !isCurrentlyBoosted {
            activeAlert = .confirmBoost { [weak self] confirmed in
                guard confirmed else { return }
                Task { @MainActor in
                    await self?.toggleBoost(status, askFirst: false)
                }
            }
            return
        }
        
        // Optimistic update
        let optimisticStatus = status.updating(
            reblogsCount: expectedCount,
            reblogged: !isCurrentlyBoosted
        )
        
        // Set performing action
        isPerformingAction = (isCurrentlyBoosted ? .unboost : .boost, targetStatusID)
        
        // Publish optimistic update
        feedCoordinator.publishUpdate(.post(optimisticStatus))
        
        // Perform API call
        do {
            let result = try await (isCurrentlyBoosted
                ? apiClient.unreblogStatus(id: targetStatusID)
                : apiClient.reblogStatus(id: targetStatusID))
            
            let canonicalResult = result.displayStatus
            feedCoordinator.publishUpdate(
                .post(
                    normalizedBoostResult(
                        canonicalResult,
                        originalCount: targetStatus.reblogsCount,
                        expectedCount: expectedCount,
                        shouldBeReblogged: !isCurrentlyBoosted
                    )
                )
            )
        } catch {
            // Rollback on error
            feedCoordinator.publishUpdate(.post(status))
            AppFeedbackCenter.shared.showError(MoroL10n.StatusAction.failureToastRepost)
            AppLogger.error("Failed to toggle boost: \(error)")
        }
        
        // Clear performing action
        isPerformingAction = nil
    }
    
    /// Handle bookmark/unbookmark action
    func toggleBookmark(_ status: Status) async {
        guard isPerformingAction == nil else { return }
        
        let targetStatus = status.displayStatus
        let targetStatusID = targetStatus.id
        let isCurrentlyBookmarked = targetStatus.bookmarked
        
        // Optimistic update
        let optimisticStatus = status.updating(bookmarked: !isCurrentlyBookmarked)
        
        // Set performing action
        isPerformingAction = (isCurrentlyBookmarked ? .unbookmark : .bookmark, targetStatusID)
        
        // Publish optimistic update
        feedCoordinator.publishUpdate(.post(optimisticStatus))
        
        // Perform API call
        do {
            let result = try await (isCurrentlyBookmarked
                ? apiClient.unbookmarkStatus(id: targetStatusID)
                : apiClient.bookmarkStatus(id: targetStatusID))
            
            // Publish real update
            feedCoordinator.publishUpdate(.post(result))
        } catch {
            // Rollback on error
            feedCoordinator.publishUpdate(.post(status))
            AppFeedbackCenter.shared.showError(MoroL10n.StatusAction.failureToastBookmark)
            AppLogger.error("Failed to toggle bookmark: \(error)")
        }
        
        // Clear performing action
        isPerformingAction = nil
    }
    
    /// Clear any pending actions (e.g., on view appear)
    func clearPendingActions() {
        isPerformingAction = nil
        activeAlert = nil
    }

    private func normalizedFavouriteResult(
        _ result: Status,
        originalCount: Int,
        expectedCount: Int,
        shouldBeFavourited: Bool
    ) -> Status {
        let needsCountFallback =
            result.favourited == shouldBeFavourited && result.favouritesCount == originalCount

        return result.updating(
            favouritesCount: needsCountFallback ? expectedCount : result.favouritesCount,
            favourited: shouldBeFavourited
        )
    }

    private func normalizedBoostResult(
        _ result: Status,
        originalCount: Int,
        expectedCount: Int,
        shouldBeReblogged: Bool
    ) -> Status {
        let needsCountFallback =
            result.reblogged == shouldBeReblogged && result.reblogsCount == originalCount

        return result.updating(
            reblogsCount: needsCountFallback ? expectedCount : result.reblogsCount,
            reblogged: shouldBeReblogged
        )
    }
}
