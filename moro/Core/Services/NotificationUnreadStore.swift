//
//  NotificationUnreadStore.swift
//  moro
//
//  Owns unread notification state across APNs, streaming, server markers, and UI badges.
//

import Combine
import Foundation
import UserNotifications
import WidgetKit

@MainActor
final class NotificationUnreadStore: ObservableObject {
    typealias BadgeSetter = @MainActor (Int) async -> Void

    static let shared = NotificationUnreadStore()

    @Published private(set) var activeUnreadCount = 0
    @Published private(set) var refreshVersion = 0
    @Published private(set) var pendingOpenRequest: PendingNotificationOpen?
    @Published private(set) var isNotificationListVisible = false

    private enum Keys {
        static let countsBySession = "notification_unread_counts_by_session_v1"
        static let recentIDsBySession = "notification_unread_recent_ids_by_session_v1"
    }

    private let userDefaults: UserDefaults
    private let badgeSetter: BadgeSetter
    private var streamCancellable: AnyCancellable?
    private var countsBySession: [String: Int]
    private(set) var activeSessionID: String?
    private var activeAPIClient: MastodonAPI?
    private var eventGenerationBySession: [String: Int] = [:]
    private var stateRevisionBySession: [String: Int] = [:]
    private var seenNotificationIDsBySession: [String: Set<String>] = [:]
    private var seenNotificationIDOrderBySession: [String: [String]] = [:]

    init(
        userDefaults: UserDefaults = MoroSharedContainer.sharedUserDefaults(),
        streamEvents: AnyPublisher<StreamEvent, Never>? = nil,
        badgeSetter: @escaping BadgeSetter = { count in
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        }
    ) {
        self.userDefaults = userDefaults
        self.badgeSetter = badgeSetter
        self.countsBySession = Self.loadCounts(from: userDefaults)
        self.seenNotificationIDOrderBySession = Self.loadRecentIDs(from: userDefaults)
        self.seenNotificationIDsBySession = self.seenNotificationIDOrderBySession.mapValues(Set.init)

        let publisher = streamEvents ?? StreamWatcher.shared.events.eraseToAnyPublisher()
        streamCancellable = publisher.sink { [weak self] event in
            guard case .notification(let notification) = event else { return }
            Task { @MainActor [weak self] in
                self?.receiveStreamNotification(notification)
            }
        }

        Task { [weak self] in
            await self?.refreshAppIconBadge()
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
            countsBySession = countsBySession.filter { availableSessionIDs.contains($0.key) }
            seenNotificationIDOrderBySession = seenNotificationIDOrderBySession.filter {
                availableSessionIDs.contains($0.key)
            }
            seenNotificationIDsBySession = seenNotificationIDsBySession.filter {
                availableSessionIDs.contains($0.key)
            }
            persistCounts()
            persistRecentIDs()
        }

        publishActiveCount()
        await refreshAppIconBadge()
        await reconcileActiveCount()
    }

    func reconcileActiveCount() async {
        guard let sessionID = activeSessionID, let apiClient = activeAPIClient else { return }
        let startingGeneration = eventGenerationBySession[sessionID, default: 0]
        let startingRevision = stateRevisionBySession[sessionID, default: 0]

        do {
            let serverCount = try await authoritativeUnreadCount(apiClient: apiClient)
            let generationChanged = eventGenerationBySession[sessionID, default: 0] != startingGeneration
            let stateChanged = stateRevisionBySession[sessionID, default: 0] != startingRevision
            if stateChanged, !generationChanged {
                return
            }
            let resolvedCount = generationChanged
                ? max(serverCount, countsBySession[sessionID, default: 0])
                : serverCount
            setCount(resolvedCount, for: sessionID)
        } catch {
            // Keep the last server value plus any optimistic push/stream increments.
            AppLogger.error("[Notifications] unread reconciliation failed: \(error)")
        }
    }

    func setNotificationListVisible(_ isVisible: Bool) {
        guard isNotificationListVisible != isVisible else { return }
        isNotificationListVisible = isVisible
        if isVisible {
            refreshVersion &+= 1
        }
    }

    func receiveRemoteNotification(userInfo: [AnyHashable: Any]) async -> Bool {
        receiveRemoteNotification(PushNotificationPayload(userInfo: userInfo))
    }

    func receiveRemoteNotification(_ payload: PushNotificationPayload) -> Bool {
        let sessionID = payload.sessionID ?? activeSessionID
        if let sessionID {
            recordIncomingNotification(
                sessionID: sessionID,
                notificationID: payload.notificationID
            )
            if isNotificationListVisible, sessionID == activeSessionID {
                refreshVersion &+= 1
            }
        }

        return !(isNotificationListVisible && sessionID == activeSessionID)
    }

    func handleNotificationResponse(userInfo: [AnyHashable: Any]) async {
        handleNotificationResponse(PushNotificationPayload(userInfo: userInfo))
    }

    func handleNotificationResponse(_ payload: PushNotificationPayload) {
        let sessionID = payload.sessionID ?? activeSessionID
        if let sessionID {
            recordIncomingNotification(
                sessionID: sessionID,
                notificationID: payload.notificationID
            )
        }
        pendingOpenRequest = PendingNotificationOpen(sessionID: sessionID, payload: payload)
    }

    func consumePendingNotificationOpen(id: UUID) {
        guard pendingOpenRequest?.id == id else { return }
        pendingOpenRequest = nil
    }

    func markActiveNotificationsRead(through notificationID: String) async {
        guard let sessionID = activeSessionID, let apiClient = activeAPIClient else { return }
        let startingGeneration = eventGenerationBySession[sessionID, default: 0]

        do {
            try await saveNotificationMarkerWithConflictRetry(
                notificationID: notificationID,
                apiClient: apiClient
            )
            let newEvents = max(
                0,
                eventGenerationBySession[sessionID, default: 0] - startingGeneration
            )
            setCount(newEvents, for: sessionID)
            await removeDeliveredNotifications(for: sessionID)
        } catch {
            // Do not clear the badge until the server accepts the read marker.
            AppLogger.error("[Notifications] failed to save read marker: \(error)")
        }
    }

    func unreadCount(for sessionID: String) -> Int {
        countsBySession[sessionID, default: 0]
    }

    func recordIncomingNotification(sessionID: String, notificationID: String?) {
        synchronizeSessionStateFromDefaults(sessionID: sessionID)
        if let notificationID, hasSeen(notificationID: notificationID, sessionID: sessionID) {
            publishActiveCount()
            Task { [weak self] in
                await self?.refreshAppIconBadge()
            }
            return
        }

        if let notificationID {
            remember(notificationID: notificationID, sessionID: sessionID)
        }
        eventGenerationBySession[sessionID, default: 0] &+= 1
        setCount(countsBySession[sessionID, default: 0] + 1, for: sessionID)
    }

    private func receiveStreamNotification(_ notification: NotificationItem) {
        guard let activeSessionID else { return }
        recordIncomingNotification(sessionID: activeSessionID, notificationID: notification.id)
        if isNotificationListVisible {
            refreshVersion &+= 1
        }
    }

    private func authoritativeUnreadCount(apiClient: MastodonAPI) async throws -> Int {
        do {
            return max(0, try await apiClient.fetchUnreadNotificationCount())
        } catch {
            if let apiError = error as? APIError,
                let statusCode = apiError.httpStatusCode,
                [404, 405, 422, 501].contains(statusCode)
            {
                return try await markerBasedUnreadCount(apiClient: apiClient)
            }
            throw error
        }
    }

    private func markerBasedUnreadCount(apiClient: MastodonAPI) async throws -> Int {
        let marker = try await apiClient.fetchMarkers(timelines: [.notifications])
        guard let lastReadID = marker.notifications?.lastReadId else { return 0 }

        let pageSize = 80
        let maximumCount = 1_000
        var maxID: String?
        var seenIDs = Set<String>()

        while seenIDs.count < maximumCount {
            let page = try await apiClient.fetchNotifications(
                maxID: maxID,
                sinceID: lastReadID,
                limit: pageSize
            )
            let previousCount = seenIDs.count
            page.forEach { seenIDs.insert($0.id) }

            guard page.count == pageSize,
                seenIDs.count > previousCount,
                let nextMaxID = page.last?.id,
                nextMaxID != maxID
            else {
                break
            }
            maxID = nextMaxID
        }

        return min(seenIDs.count, maximumCount)
    }

    private func saveNotificationMarkerWithConflictRetry(
        notificationID: String,
        apiClient: MastodonAPI
    ) async throws {
        do {
            _ = try await apiClient.saveMarker(home: nil, notifications: notificationID)
        } catch {
            if let apiError = error as? APIError, apiError.httpStatusCode == 409 {
                _ = try await apiClient.saveMarker(home: nil, notifications: notificationID)
            } else {
                throw error
            }
        }
    }

    private func setCount(_ count: Int, for sessionID: String) {
        countsBySession[sessionID] = max(0, count)
        stateRevisionBySession[sessionID, default: 0] &+= 1
        persistCounts()
        publishActiveCount()
        Task { [weak self] in
            await self?.refreshAppIconBadge()
        }
    }

    private func publishActiveCount() {
        activeUnreadCount = activeSessionID.map { countsBySession[$0, default: 0] } ?? 0
    }

    func refreshAppIconBadge() async {
        let notificationTotal = countsBySession.values.reduce(0, +)
        await badgeSetter(notificationTotal)
    }

    private func persistCounts() {
        userDefaults.set(countsBySession, forKey: Keys.countsBySession)
        WidgetCenter.shared.reloadTimelines(ofKind: MoroWidgetKind.overview)
        WidgetCenter.shared.reloadTimelines(ofKind: MoroWidgetKind.quickActions)
    }

    private func persistRecentIDs() {
        userDefaults.set(seenNotificationIDOrderBySession, forKey: Keys.recentIDsBySession)
    }

    private static func loadCounts(from userDefaults: UserDefaults) -> [String: Int] {
        guard let stored = userDefaults.dictionary(forKey: Keys.countsBySession) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            if let number = entry.value as? NSNumber {
                result[entry.key] = max(0, number.intValue)
            }
        }
    }

    private static func loadRecentIDs(from userDefaults: UserDefaults) -> [String: [String]] {
        guard let stored = userDefaults.dictionary(forKey: Keys.recentIDsBySession) else { return [:] }
        return stored.reduce(into: [:]) { result, entry in
            if let ids = entry.value as? [String] {
                result[entry.key] = Array(ids.suffix(200))
            }
        }
    }

    private func synchronizeSessionStateFromDefaults(sessionID: String) {
        if let number = userDefaults.dictionary(forKey: Keys.countsBySession)?[sessionID] as? NSNumber {
            let persistedCount = max(0, number.intValue)
            if countsBySession[sessionID] != persistedCount {
                countsBySession[sessionID] = persistedCount
                stateRevisionBySession[sessionID, default: 0] &+= 1
            }
        }
        if let ids = userDefaults.dictionary(forKey: Keys.recentIDsBySession)?[sessionID] as? [String] {
            let recentIDs = Array(ids.suffix(200))
            seenNotificationIDOrderBySession[sessionID] = recentIDs
            seenNotificationIDsBySession[sessionID] = Set(recentIDs)
        }
    }

    private func hasSeen(notificationID: String, sessionID: String) -> Bool {
        seenNotificationIDsBySession[sessionID, default: []].contains(notificationID)
    }

    private func remember(notificationID: String, sessionID: String) {
        seenNotificationIDsBySession[sessionID, default: []].insert(notificationID)
        seenNotificationIDOrderBySession[sessionID, default: []].append(notificationID)

        let maximumRememberedIDs = 200
        if seenNotificationIDOrderBySession[sessionID, default: []].count > maximumRememberedIDs {
            let removedID = seenNotificationIDOrderBySession[sessionID]!.removeFirst()
            seenNotificationIDsBySession[sessionID]?.remove(removedID)
        }
        persistRecentIDs()
    }

    private func payloadSessionID(in userInfo: [AnyHashable: Any]) -> String? {
        guard let rawValue = userInfo["x"] as? String, !rawValue.isEmpty else { return nil }
        return rawValue.removingPercentEncoding ?? rawValue
    }

    private func removeDeliveredNotifications(for sessionID: String) async {
        let center = UNUserNotificationCenter.current()
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered.compactMap { notification -> String? in
            payloadSessionID(in: notification.request.content.userInfo) == sessionID
                ? notification.request.identifier
                : nil
        }
        guard !identifiers.isEmpty else { return }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
