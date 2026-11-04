//
//  TimelineDetectionManager.swift
//  moro
//
//  Manages timeline new post detection based on user settings and system context.
//  Detection delivers complete pages; each timeline owns merging and presentation.
//
//  Policy dimensions:
//  - Following (Home)
//  - Local
//  - Federated
//
//  Frequency control:
//  - powerSaving: Low frequency polling, foreground only
//  - moreTimely: More frequent polling (experimental)
//
//  Safeguards:
//  - Background: stop ALL detection
//  - Low Power Mode: force to powerSaving
//  - Cellular: reduce frequency (future enhancement)
//

import Combine
import Foundation
import UIKit

// MARK: - Timeline Dimension

/// Timeline dimension for detection
enum TimelineDimension: String, CaseIterable, Hashable {
    case following
    case local
    case federated

    /// Map to TimelineType for API calls
    var timelineType: TimelineType {
        switch self {
        case .following: return .home
        case .local: return .local
        case .federated: return .federated
        }
    }
}

// MARK: - Detection Policy

/// Detection policy based on settings and context
struct TimelineDetectionPolicy: Equatable {
    /// Which dimensions are enabled for detection
    let enabledDimensions: Set<TimelineDimension>

    /// Polling interval per dimension (seconds)
    let intervals: [TimelineDimension: TimeInterval]

    /// Whether streaming should be used (only for Following when available)
    let useStreaming: Bool

    /// Default intervals for powerSaving mode
    static let powerSavingIntervals: [TimelineDimension: TimeInterval] = [
        .following: 60,
        .local: 90,
        .federated: 180,
    ]

    /// Default intervals for moreTimely mode
    static let moreTimelyIntervals: [TimelineDimension: TimeInterval] = [
        .following: 20,
        .local: 45,
        .federated: 90,
    ]
}

// MARK: - Detection Event

/// Event emitted when new items are detected
struct TimelineDetectionEvent {
    let dimension: TimelineDimension
    let deltaCount: Int
    let latestID: String?
}

struct TimelineDetectionSnapshot {
    let dimension: TimelineDimension
    let statusIDs: Set<String>
    let anonymousCount: Int
}

struct TimelineDetectedPage {
    let scopeID: String
    let timeline: TimelineType
    let sinceID: String?
    let page: TimelinePage
}

// MARK: - Detection Manager

/// Manager responsible for timeline new post detection
///
/// Key principles:
/// 1. Detection delivers pages; the page view model owns the timeline array
/// 2. UI updates are debounced to prevent frequent updates
/// 3. Respects app lifecycle and power state
@MainActor
final class TimelineDetectionManager: ObservableObject {

    static let shared = TimelineDetectionManager()
    let pages = PassthroughSubject<TimelineDetectedPage, Never>()

    // MARK: - Published State

    /// Detected new items count per dimension (debounced)
    @Published private(set) var newItemsCounts: [TimelineDimension: Int] = [
        .following: 0,
        .local: 0,
        .federated: 0,
    ]

    /// Latest detection event (for observers)
    @Published private(set) var latestEvent: TimelineDetectionEvent?

    // MARK: - Private State

    private var pollingTasks: [TimelineDimension: Task<Void, Never>] = [:]
    private var lastKnownTopIDs: [TimelineDimension: String] = [:]
    private var pendingCounts: [TimelineDimension: Int] = [:]
    private var detectedStatusIDs: [TimelineDimension: Set<String>] = [:]
    private var latestDetectedIDs: [TimelineDimension: String] = [:]
    private var lastCheckDates: [TimelineDimension: Date] = [:]
    private var debounceTask: Task<Void, Never>?
    private var generation = UUID()
    private var requests: [TimelineDimension: UUID] = [:]

    private var isInForeground = true
    private var isLowPowerMode = false
    private var currentPolicy: TimelineDetectionPolicy?
    private var activeDimension: TimelineDimension?
    private var configuredScopeID: String?

    private var cancellables = Set<AnyCancellable>()
    private let settings = AppSettings.shared

    /// Debounce window in seconds
    private let debounceInterval: TimeInterval = 3.0

    // API client (set externally when ready)
    // Note: Cannot use weak because MastodonAPI is a protocol. The manager should be
    // stopped (stopDetection) when the API client is no longer valid.
    private var apiClient: (any MastodonAPI)?
    /// The visible shell supplies its source models so automatic and manual
    /// checks share each model's single in-flight latest-page request.
    private var refreshTimeline: ((TimelineType) async -> String?)?

    // MARK: - Initialization

    private init() {
        setupObservers()
    }

    // MARK: - Configuration

    /// Configure the manager with API client
    /// Must be called before starting detection
    func configure(apiClient: MastodonAPI, scopeID: String,
        refreshTimeline: ((TimelineType) async -> String?)? = nil) {
        if configuredScopeID != scopeID {
            stopDetection()
            clearAllCounts()
            lastKnownTopIDs.removeAll()
            detectedStatusIDs.removeAll()
            latestDetectedIDs.removeAll()
            lastCheckDates.removeAll()
            configuredScopeID = scopeID
        }
        self.apiClient = apiClient
        self.refreshTimeline = refreshTimeline
    }

    func setActiveDimension(_ dimension: TimelineDimension?) {
        guard activeDimension != dimension else { return }
        activeDimension = dimension
        if isInForeground {
            applyPolicy(computePolicy())
        }
    }

    func isConfigured(for scopeID: String) -> Bool { configuredScopeID == scopeID }

    // MARK: - Public API

    /// Start detection based on current settings
    func startDetection() {
        guard isInForeground else { return }

        let policy = computePolicy()
        applyPolicy(policy)
    }

    /// Stop all detection
    func stopDetection() {
        generation = UUID()
        requests.removeAll()
        for task in pollingTasks.values {
            task.cancel()
        }
        pollingTasks.removeAll()
        debounceTask?.cancel()
        debounceTask = nil
        currentPolicy = nil
    }

    /// Clear count for a specific dimension (call when user refreshes that timeline)
    func clearCount(for dimension: TimelineDimension) {
        newItemsCounts[dimension] = 0
        pendingCounts[dimension] = 0
        detectedStatusIDs[dimension] = []
        latestDetectedIDs[dimension] = nil
    }

    /// Clear all counts
    func clearAllCounts() {
        for dimension in TimelineDimension.allCases {
            clearCount(for: dimension)
        }
    }

    func snapshot(for dimension: TimelineDimension) -> TimelineDetectionSnapshot {
        TimelineDetectionSnapshot(
            dimension: dimension,
            statusIDs: detectedStatusIDs[dimension] ?? [],
            anonymousCount: pendingCounts[dimension] ?? 0
        )
    }

    func resolve(_ snapshot: TimelineDetectionSnapshot) {
        detectedStatusIDs[snapshot.dimension, default: []]
            .subtract(snapshot.statusIDs)
        pendingCounts[snapshot.dimension] = max(
            0,
            (pendingCounts[snapshot.dimension] ?? 0) - snapshot.anonymousCount
        )

        let remainingCount =
            (detectedStatusIDs[snapshot.dimension]?.count ?? 0)
            + (pendingCounts[snapshot.dimension] ?? 0)
        newItemsCounts[snapshot.dimension] = remainingCount
        if remainingCount == 0 {
            latestDetectedIDs[snapshot.dimension] = nil
        }
    }

    /// Update the last known top ID (call when timeline refreshes)
    func updateLastKnownTopID(_ id: String, for dimension: TimelineDimension) {
        lastKnownTopIDs[dimension] = id
    }

    /// Increment count from streaming event (called by StreamWatcher integration)
    func incrementCount(for dimension: TimelineDimension, latestID: String? = nil) {
        if let id = latestID {
            guard detectedStatusIDs[dimension, default: []].count < 200,
                detectedStatusIDs[dimension, default: []].insert(id).inserted else { return }
            latestDetectedIDs[dimension] = id
        } else {
            pendingCounts[dimension] = min(200, pendingCounts[dimension, default: 0] + 1)
        }
        scheduleDebounceFlush()
    }

    func checkForNewItems(
        dimension: TimelineDimension,
        force: Bool = false,
        staleAfter: TimeInterval = 60
    ) async {
        if !force,
            let lastCheck = lastCheckDates[dimension],
            Date().timeIntervalSince(lastCheck) < staleAfter
        {
            return
        }
        await pollForNewItems(
            dimension: dimension,
            allowWhileStreaming: force
        )
    }

    // MARK: - Policy Computation

    /// Compute effective policy from settings + context
    private func computePolicy() -> TimelineDetectionPolicy {
        var dimensions: Set<TimelineDimension> = [.following]
        if let activeDimension {
            dimensions.insert(activeDimension)
        }
        // Low Power Mode turns polling off; opening a page and foregrounding still check
        // once (TimelineHomeView), and the stream keeps delivering.
        return TimelineDetectionPolicy(
            enabledDimensions: dimensions,
            intervals: isLowPowerMode ? [:] : TimelineDetectionPolicy.powerSavingIntervals,
            useStreaming: true
        )
    }

    // MARK: - Policy Application

    /// Apply a new policy, diffing against current
    private func applyPolicy(_ newPolicy: TimelineDetectionPolicy) {
        guard newPolicy != currentPolicy else { return }

        let oldEnabledDimensions = currentPolicy?.enabledDimensions ?? []
        let oldPollingDimensions =
            currentPolicy.map { pollingDimensions(for: $0) } ?? []
        let newPollingDimensions = pollingDimensions(for: newPolicy)

        // Stop removed dimensions
        for dimension in oldPollingDimensions.subtracting(newPollingDimensions) {
            pollingTasks[dimension]?.cancel()
            pollingTasks[dimension] = nil
        }

        // Start or restart changed dimensions
        for dimension in newPollingDimensions {
            let oldInterval = currentPolicy?.intervals[dimension]
            let newInterval = newPolicy.intervals[dimension]

            if oldInterval != newInterval || !oldPollingDimensions.contains(dimension) {
                // Restart polling for this dimension
                pollingTasks[dimension]?.cancel()
                if let interval = newInterval {
                    pollingTasks[dimension] = createPollingTask(for: dimension, interval: interval)
                }
            }
        }

        let removedEnabledDimensions = oldEnabledDimensions.subtracting(newPolicy.enabledDimensions)
        for dimension in removedEnabledDimensions {
            // Preserve each source's baseline and notice when another page is selected.
            pollingTasks[dimension]?.cancel()
        }

        currentPolicy = newPolicy
    }

    private func pollingDimensions(for policy: TimelineDetectionPolicy) -> Set<TimelineDimension> {
        policy.enabledDimensions
    }

    // MARK: - Polling

    /// Create a polling task for a dimension
    private func createPollingTask(for dimension: TimelineDimension, interval: TimeInterval)
        -> Task<Void, Never>
    {
        Task { [weak self] in
            let intervalNanoseconds = UInt64(interval * 1_000_000_000)

            // Avoid immediate startup burst: first poll happens after one interval.
            try? await Task.sleep(nanoseconds: intervalNanoseconds)

            while !Task.isCancelled {
                await self?.pollForNewItems(
                    dimension: dimension,
                    allowWhileStreaming: false
                )
                try? await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }
    }

    /// Poll for new items in a dimension
    private func pollForNewItems(
        dimension: TimelineDimension,
        allowWhileStreaming: Bool
    ) async {
        guard let apiClient = apiClient else { return }
        // Offline, a poll can only fail; the reconnect check below catches up.
        guard !NetworkMonitor.shared.isOffline else { return }

        // The user stream covers the following dimension in real time, so polling is
        // only a fallback for when the stream isn't actively connected (dropped or
        // mid-reconnect). While the stream is delivering events, skip the request
        // instead of duplicating its work every interval.
        if dimension == .following,
            StreamWatcher.shared.isWatching,
            !allowWhileStreaming,
            Date().timeIntervalSince(lastCheckDates[dimension] ?? .distantPast) < 300
        {
            return
        }

        // An initial 206 response has no verified head yet; retry the newest page.
        let sinceID = lastKnownTopIDs[dimension]

        guard requests[dimension] == nil, let scopeID = configuredScopeID else { return }
        let requestID = UUID()
        let requestGeneration = generation
        requests[dimension] = requestID
        defer { if requests[dimension] == requestID { requests[dimension] = nil } }

        lastCheckDates[dimension] = Date()

        if let refreshTimeline {
            let headID = await refreshTimeline(dimension.timelineType)
            guard !Task.isCancelled, configuredScopeID == scopeID,
                generation == requestGeneration, requests[dimension] == requestID else { return }
            if let headID { lastKnownTopIDs[dimension] = headID }
            return
        }

        do {
            // Fetch timeline with since_id to get only newer items
            // We only need the count and possibly the latest ID
            let page = try await apiClient.fetchTimelinePage(timeline: dimension.timelineType,
                maxID: nil, sinceID: sinceID, limit: 20)
            guard !Task.isCancelled, configuredScopeID == scopeID,
                generation == requestGeneration, requests[dimension] == requestID else { return }
            pages.send(TimelineDetectedPage(scopeID: scopeID, timeline: dimension.timelineType,
                sinceID: sinceID, page: page))

        } catch {
            // Silently ignore errors during polling
            // (network issues, etc. - we'll retry on next interval)
        }
    }

    // MARK: - Debouncing

    /// Schedule a debounced flush of pending counts to published counts
    private func scheduleDebounceFlush() {
        guard debounceTask == nil else { return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: UInt64((self?.debounceInterval ?? 3.0) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.debounceTask = nil
            self?.flushPendingCounts()
        }
    }

    /// Flush pending counts to published counts
    func flushPendingCounts() {
        for dimension in TimelineDimension.allCases {
            let anonymousPending = pendingCounts[dimension] ?? 0
            let detectedCount = detectedStatusIDs[dimension]?.count ?? 0
            let totalCount = detectedCount + anonymousPending
            if totalCount > 0 {
                newItemsCounts[dimension] = totalCount

                // Emit event
                latestEvent = TimelineDetectionEvent(
                    dimension: dimension,
                    deltaCount: totalCount,
                    latestID: latestDetectedIDs[dimension]
                )

                // Haptic feedback is handled at the UI layer (TimelineHomeView)
                // to avoid duplicate vibrations from both ViewModel and DetectionManager.
            }
        }
    }

    // MARK: - Observers

    /// Setup observers for app lifecycle and settings changes
    private func setupObservers() {
        NotificationCenter.default.publisher(for: .timelineContentWillClear)
            .sink { [weak self] notification in
                guard notification.object as? TimelineCache === CacheManager.shared.timelineCache,
                    let self else { return }
                self.stopDetection()
                self.clearAllCounts()
                self.lastKnownTopIDs.removeAll()
                self.lastCheckDates.removeAll()
            }
            .store(in: &cancellables)

        // App lifecycle
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isInForeground = true
                self?.startDetection()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isInForeground = false
                self?.stopDetection()
            }
            .store(in: &cancellables)

        // Low Power Mode
        NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
                // Re-apply policy with new power state
                if self?.isInForeground == true {
                    self?.startDetection()
                }
            }
            .store(in: &cancellables)

        // Initialize low power mode state
        isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

        // Back online: check the page on screen once instead of waiting for the next poll.
        NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                guard let self, self.isInForeground, let dimension = self.activeDimension else { return }
                Task { await self.checkForNewItems(dimension: dimension, force: true) }
            }
            .store(in: &cancellables)

        // Settings changes
        settings.objectWillChange
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                // Re-apply policy when settings change
                if self?.isInForeground == true {
                    self?.startDetection()
                }
            }
            .store(in: &cancellables)
    }
}
