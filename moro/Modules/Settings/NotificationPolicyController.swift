//
//  NotificationPolicyController.swift
//  moro
//
//  Stale-while-revalidate state for server notification intake settings.
//

import Combine
import Foundation

@MainActor
final class NotificationPolicyController: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case unsupported
        case failed(String)
    }

    @Published private(set) var loadState: LoadState
    @Published private(set) var policy: ServerNotificationPolicy?
    @Published private(set) var isRefreshing = false
    @Published private(set) var isSaving = false
    @Published private(set) var refreshError: String?
    @Published private(set) var saveError: String?

    private let snapshotStore: NotificationPolicySnapshotStore
    private let snapshotSession: NotificationPolicySnapshotStore.Session
    private var mutationRevision = 0
    private var activeRefreshID: UUID?

    init(
        accountKey: String,
        snapshotStore: NotificationPolicySnapshotStore? = nil
    ) {
        let snapshotStore = snapshotStore ?? .shared
        self.snapshotStore = snapshotStore
        snapshotSession = snapshotStore.session(for: accountKey)
        if let snapshot = snapshotStore.load(for: snapshotSession) {
            policy = snapshot.policy
            loadState = .loaded
        } else {
            policy = nil
            loadState = .idle
        }
    }

    func refresh(using apiClient: MastodonAPI) async {
        guard activeRefreshID == nil else { return }
        let refreshID = UUID()
        let startingMutationRevision = mutationRevision
        activeRefreshID = refreshID
        refreshError = nil
        if policy == nil {
            loadState = .loading
        } else {
            loadState = .loaded
            isRefreshing = true
        }

        defer {
            if activeRefreshID == refreshID {
                activeRefreshID = nil
                isRefreshing = false
            }
        }

        do {
            let fetched = try await apiClient.fetchNotificationPolicy()
            try Task.checkCancellation()
            guard activeRefreshID == refreshID else { return }

            // A user edit that started after this request owns the visible
            // state. Its update response, not this older GET, is authoritative.
            guard mutationRevision == startingMutationRevision else {
                if policy != nil { loadState = .loaded }
                return
            }

            policy = fetched
            loadState = .loaded
            snapshotStore.save(fetched, for: snapshotSession)
        } catch is CancellationError {
            return
        } catch {
            guard activeRefreshID == refreshID else { return }
            guard mutationRevision == startingMutationRevision else {
                if policy != nil { loadState = .loaded }
                return
            }
            if Self.isUnsupported(error) {
                policy = nil
                refreshError = nil
                loadState = .unsupported
                snapshotStore.clear(for: snapshotSession)
            } else if policy != nil {
                // Keep the last-known configuration usable when offline.
                loadState = .loaded
                refreshError = error.localizedDescription
            } else {
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    func markUnsupported() {
        activeRefreshID = nil
        isRefreshing = false
        refreshError = nil
        policy = nil
        loadState = .unsupported
    }

    func save(
        _ value: ServerNotificationPolicy.Disposition,
        at keyPath: WritableKeyPath<ServerNotificationPolicy, ServerNotificationPolicy.Disposition>,
        using apiClient: MastodonAPI
    ) async {
        guard let previous = policy, !isSaving else { return }
        var updated = previous
        updated[keyPath: keyPath] = value
        await persist(updated, previous: previous, using: apiClient)
    }

    func saveBots(
        _ value: ServerNotificationPolicy.Disposition,
        using apiClient: MastodonAPI
    ) async {
        guard let previous = policy, !isSaving else { return }
        var updated = previous
        updated.forBots = value
        await persist(updated, previous: previous, using: apiClient)
    }

    func resolvePendingRequest(_ request: ServerNotificationRequest) {
        guard var policy else { return }
        mutationRevision += 1
        policy.summary = .init(
            pendingRequestsCount: max(0, policy.summary.pendingRequestsCount - 1),
            pendingNotificationsCount: max(
                0, policy.summary.pendingNotificationsCount - request.notificationsCount)
        )
        self.policy = policy
        snapshotStore.save(policy, for: snapshotSession)
    }

    private func persist(
        _ updated: ServerNotificationPolicy,
        previous: ServerNotificationPolicy,
        using apiClient: MastodonAPI
    ) async {
        mutationRevision += 1
        let revision = mutationRevision
        policy = updated
        saveError = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let saved = try await apiClient.updateNotificationPolicy(updated)
            try Task.checkCancellation()
            guard mutationRevision == revision else { return }
            policy = saved
            loadState = .loaded
            snapshotStore.save(saved, for: snapshotSession)
        } catch is CancellationError {
            if mutationRevision == revision { policy = previous }
        } catch {
            guard mutationRevision == revision else { return }
            policy = previous
            saveError = error.localizedDescription
        }
    }

    private static func isUnsupported(_ error: Error) -> Bool {
        guard let status = (error as? APIError)?.httpStatusCode else { return false }
        return [404, 405, 501].contains(status)
    }
}
