//
//  TimelineHomeView+Header.swift
//  moro
//
//  Timeline header content shared by the root stream scene.
//

import SwiftUI
import UIKit

extension TimelineHomeView {
    func handleFeedCoordinatorUpdate(_ update: UpdatedElement) {
        guard case .createdPost(let status) = update else { return }

        let pendingCount = detectionManager.newItemsCounts[.following] ?? 0
        if selectedTimeline == .home,
            scrollBridge.isAtTop(.home),
            pendingCount == 0
        {
            homeViewModel.insertCreatedStatus(status)
            syncDetectionTopID(for: .home)
        } else {
            homeViewModel.stageCreatedStatus(status)
            detectionManager.incrementCount(for: .following, latestID: status.id)
        }
    }

    func handleStreamEvent(_ event: StreamEvent) {
        switch event {
        case .update(let status):
            homeViewModel.trackPendingStatusID(status.id)
            if status.account.id != appState.currentAccount?.id {
                detectionManager.incrementCount(for: .following, latestID: status.id)
            }

        case .statusUpdate, .delete:
            let viewModels = [homeViewModel, localViewModel, federatedViewModel]
                + pinnedTimelineStore.allViewModels
            for viewModel in viewModels {
                viewModel.handleStreamEvent(event)
            }

        case .notification, .conversation:
            break
        }
    }

    // MARK: - Floating Header

    @ViewBuilder
    var floatingHeader: some View {
        HStack(spacing: theme.spacing.m) {
            if let onAvatarTap, let account = appState.currentAccount {
                Button(
                    action: onAvatarTap
                ) {
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(theme.colors.surfaceSubtle)
                            .frame(width: 38, height: 38)
                        MoroAvatar(
                            imageURL: account.avatarAnimatedURL,
                            staticImageURL: account.avatarURL,
                            initials: account.displayNameInitials,
                            size: 32
                        )
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel(MoroL10n.Navigation.settings)
            } else {
                Color.clear
                    .frame(width: 38, height: 38)
            }

            Spacer()

            // Center: Timeline switcher
            TimelineSwitcher(
                selectedTimeline: $selectedTimeline,
                pinnedTimelines: pinnedTimelineTypes,
                onManageLists: { router.navigate(to: .lists) },
                onManageTopics: { router.navigate(to: .followedTopics) }
            )

            Spacer()

            // Right: Announcements
            Button(action: { router.navigate(to: .announcements) }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: appState.unreadAnnouncementsCount > 0 ? "megaphone.fill" : "megaphone")
                        .moroScaledFont(size: 16, weight: .semibold)
                        .foregroundStyle(
                            appState.unreadAnnouncementsCount > 0
                                ? theme.colors.primary500
                                : theme.colors.textSecondary
                        )
                        .frame(width: 30, height: 30)

                    if appState.unreadAnnouncementsCount > 0 {
                        Text(appState.unreadAnnouncementsCount > 99 ? "99+" : "\(appState.unreadAnnouncementsCount)")
                            .moroScaledFont(size: 9, weight: .bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, appState.unreadAnnouncementsCount > 9 ? 4 : 3)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(theme.colors.error)
                            )
                            .offset(x: 5, y: -2)
                    }
                }
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(
                appState.unreadAnnouncementsCount > 0
                    ? MoroL10n.Timeline.announcements(appState.unreadAnnouncementsCount)
                    : MoroL10n.Timeline.announcementsTitle)
        }
        .padding(.horizontal, theme.spacing.l)
        .frame(height: headerHeight)
        .background(sceneCanvasColor)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    func refreshAnnouncementBadge(initialDelay: Bool) {
        if !initialDelay,
            Date().timeIntervalSince(lastAnnouncementRefreshAt) < announcementRefreshCooldown
        {
            return
        }

        announcementBadgeTask?.cancel()
        lastAnnouncementRefreshAt = Date()
        announcementBadgeTask = Task {
            if initialDelay {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }

            do {
                let announcements = try await apiClient.fetchAnnouncements()
                guard !Task.isCancelled else { return }
                let unreadCount = announcements.reduce(into: 0) { count, item in
                    if !item.read {
                        count += 1
                    }
                }
                await MainActor.run {
                    appState.unreadAnnouncementsCount = unreadCount
                }
            } catch {
                // Ignore fetch failure for badge updates to avoid noisy UI feedback.
            }
        }
    }

    func scheduleDeferredStartupTasks() {
        startupDeferredTask?.cancel()
        startupDeferredTask = Task(priority: .utility) { @MainActor in
            // Stage 1: Bootstrap stream after first paint cooldown.
            try? await Task.sleep(nanoseconds: startupStreamDelayNanoseconds)
            guard !Task.isCancelled, scenePhase == .active else { return }
            if let token = appState.authToken {
                streamWatcher.configure(baseURL: AppEnvironment.apiBaseURL, accessToken: token)
                streamWatcher.addStream(.user)
            }

            // Stage 2: Sync marker later; if user is actively scrolling, back off once more.
            try? await Task.sleep(nanoseconds: startupMarkerDelayAfterStreamNanoseconds)
            guard !Task.isCancelled, scenePhase == .active else { return }
            if scrollBridge.hasScrolledHome {
                try? await Task.sleep(nanoseconds: startupMarkerBackoffOnInteractionNanoseconds)
                guard !Task.isCancelled, scenePhase == .active else { return }
            }
            await homeViewModel.fetchMarker()

            // Stage 3: Announcements stay lowest priority and remain delayed inside helper.
            refreshAnnouncementBadge(initialDelay: true)
        }
    }

    func clearDetectionStateForAllTimelines() {
        homeViewModel.clearPendingStatuses()
        detectionManager.clearAllCounts()
    }

    func handleScrollOffset(_ offset: CGFloat, for timelineType: TimelineType) {
        guard isActive else { return }
        scrollBridge.offsets[timelineType] = offset
        if timelineType == .home, !scrollBridge.hasScrolledHome, abs(offset) > 24 {
            scrollBridge.hasScrolledHome = true
        }
        // Drive the root chrome elevation. The per-frame fraction is broadcast over a Combine
        // subject (not @Published), so only the small header reacts and the pager stays stable.
        let isSelected = scrollBridge.isPresented(timelineType)
        let fraction = scrollBridge.updateChrome(
            offset: offset,
            headerHeight: headerHeight,
            timeline: timelineType,
            isSelected: isSelected
        )
        if isSelected { onChromeFraction?(fraction) }
    }

}
