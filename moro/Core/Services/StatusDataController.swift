//
//  StatusDataController.swift
//  moro
//
//  Controller that manages interaction state for a single status.
//  Implements optimistic updates with automatic rollback on failure.
//

import Combine
import Foundation
import SwiftUI

/// Controller that manages the mutable state of a single status
@MainActor
@Observable
final class StatusDataController: Identifiable {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}


    // MARK: - Identity

    let id: String
    private let originalStatus: Status
    @ObservationIgnored private var client: (any MastodonAPI)?

    // MARK: - Mutable State (for optimistic updates)

    private(set) var isFavorited: Bool
    private(set) var favoritesCount: Int

    private(set) var isReblogged: Bool
    private(set) var reblogsCount: Int

    private(set) var isBookmarked: Bool

    private(set) var repliesCount: Int

    // MARK: - Loading States

    private(set) var isFavoriting: Bool = false
    private(set) var isReblogging: Bool = false
    private(set) var isBookmarking: Bool = false

    // MARK: - Initialization

    public init(status: Status, client: MastodonAPI?) {
        let targetStatus = status.displayStatus

        self.id = targetStatus.id
        self.originalStatus = status
        self.client = client

        self.isFavorited = targetStatus.favourited
        self.favoritesCount = targetStatus.favouritesCount
        self.isReblogged = targetStatus.reblogged
        self.reblogsCount = targetStatus.reblogsCount
        self.isBookmarked = targetStatus.bookmarked
        self.repliesCount = targetStatus.repliesCount
    }

    // MARK: - Update from External Source

    /// Update controller state from a new status (e.g., from server response or stream event)
    func updateFrom(status: Status) {
        let targetStatus = status.displayStatus

        guard targetStatus.id == id else { return }

        self.isFavorited = targetStatus.favourited
        self.favoritesCount = targetStatus.favouritesCount
        self.isReblogged = targetStatus.reblogged
        self.reblogsCount = targetStatus.reblogsCount
        self.isBookmarked = targetStatus.bookmarked
        self.repliesCount = targetStatus.repliesCount
    }

    // MARK: - Actions with Optimistic Updates

    /// Toggle favorite with optimistic update and automatic rollback
    func toggleFavorite() async {
        guard let client = client, !isFavoriting else { return }

        isFavoriting = true

        // Save original state for rollback
        let wasLiked = isFavorited
        let originalCount = favoritesCount

        // Optimistic update
        withAnimation(.default) {
            isFavorited.toggle()
            favoritesCount += isFavorited ? 1 : -1
        }

        do {
            let updatedStatus =
                try await
                (wasLiked
                ? client.unfavouriteStatus(id: id)
                : client.favouriteStatus(id: id))

            updateFrom(status: updatedStatus)
        } catch {
            // Rollback on error
            withAnimation(.default) {
                isFavorited = wasLiked
                favoritesCount = originalCount
            }

            AppFeedbackCenter.shared.showError(MoroL10n.StatusAction.failureToastLike)
            #if DEBUG
                AppLogger.error("Failed to toggle favorite: \(error)")
            #endif
        }

        isFavoriting = false
    }

    /// Toggle reblog/boost with optimistic update and automatic rollback
    func toggleReblog() async {
        guard let client = client, !isReblogging else { return }

        isReblogging = true

        // Save original state for rollback
        let wasReblogged = isReblogged
        let originalCount = reblogsCount

        // Optimistic update
        withAnimation(.default) {
            isReblogged.toggle()
            reblogsCount += isReblogged ? 1 : -1
        }

        do {
            let updatedStatus =
                try await
                (wasReblogged
                ? client.unreblogStatus(id: id)
                : client.reblogStatus(id: id))

            // For reblog, API returns the boost status, update from reblog if present
            updateFrom(status: updatedStatus.reblog?.value ?? updatedStatus)
        } catch {
            // Rollback on error
            withAnimation(.default) {
                isReblogged = wasReblogged
                reblogsCount = originalCount
            }

            AppFeedbackCenter.shared.showError(MoroL10n.StatusAction.failureToastRepost)
            #if DEBUG
                AppLogger.error("Failed to toggle reblog: \(error)")
            #endif
        }

        isReblogging = false
    }

    /// Toggle bookmark with optimistic update and automatic rollback
    func toggleBookmark() async {
        guard let client = client, !isBookmarking else { return }

        isBookmarking = true

        // Save original state for rollback
        let wasBookmarked = isBookmarked

        // Optimistic update
        withAnimation(.default) {
            isBookmarked.toggle()
        }

        do {
            let updatedStatus =
                try await
                (wasBookmarked
                ? client.unbookmarkStatus(id: id)
                : client.bookmarkStatus(id: id))

            updateFrom(status: updatedStatus)
        } catch {
            // Rollback on error
            withAnimation(.default) {
                isBookmarked = wasBookmarked
            }

            AppFeedbackCenter.shared.showError(MoroL10n.StatusAction.failureToastBookmark)
            #if DEBUG
                AppLogger.error("Failed to toggle bookmark: \(error)")
            #endif
        }

        isBookmarking = false
    }
}

// MARK: - StatusDataControllerProvider

/// Provider that caches StatusDataController instances for efficient reuse
@MainActor
final class StatusDataControllerProvider {
    static let shared = StatusDataControllerProvider()

    /// Cache of controllers by status ID and client
    private var cache: [CacheKey: StatusDataController] = [:]

    private struct CacheKey: Hashable {
        let statusId: String
        let clientId: String
    }

    private init() {}

    /// Get or create a data controller for a status
    func dataController(for status: Status, client: MastodonAPI?, clientId: String)
        -> StatusDataController
    {
        let displayStatus = status.displayStatus
        let key = CacheKey(statusId: displayStatus.id, clientId: clientId)

        if let controller = cache[key] {
            // Update existing controller with latest data
            controller.updateFrom(status: status)
            return controller
        }

        let controller = StatusDataController(status: status, client: client)
        cache[key] = controller
        return controller
    }

    /// Update data controllers for a batch of statuses
    func updateDataControllers(
        for statuses: [Status], client: MastodonAPI?, clientId: String
    ) {
        for status in statuses {
            let displayStatus = status.displayStatus
            let key = CacheKey(statusId: displayStatus.id, clientId: clientId)

            if let controller = cache[key] {
                controller.updateFrom(status: status)
            }
        }
    }

    /// Get existing controller if cached
    func existingController(for statusId: String, clientId: String) -> StatusDataController? {
        let key = CacheKey(statusId: statusId, clientId: clientId)
        return cache[key]
    }

    /// Remove controller from cache
    func removeController(for statusId: String, clientId: String) {
        let key = CacheKey(statusId: statusId, clientId: clientId)
        cache[key] = nil
    }

    /// Clear all cached controllers
    func clearAll() {
        cache.removeAll()
    }

    /// Clear controllers for a specific client
    func clear(for clientId: String) {
        cache = cache.filter { $0.key.clientId != clientId }
    }

    /// Current cache size
    var cacheSize: Int {
        cache.count
    }
}

// MARK: - Status Extension for Controller

extension Status {
    /// Get or create a data controller for this status
    @MainActor
    func dataController(client: MastodonAPI?, clientId: String) -> StatusDataController {
        StatusDataControllerProvider.shared.dataController(
            for: self, client: client, clientId: clientId)
    }
}
