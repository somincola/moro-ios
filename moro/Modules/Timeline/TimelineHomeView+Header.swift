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

        homeViewModel.receiveLiveStatus(status, authoredByCurrentUser: true)
    }

    func handleStreamEvent(_ event: StreamEvent) {
        guard detectionManager.isConfigured(for: cacheClientID),
            streamWatcher.matchesCredentials(baseURL: AppEnvironment.apiBaseURL, accessToken: appState.authToken)
        else { return }
        switch event {
        case .update(let status):
            homeViewModel.receiveLiveStatus(status,
                authoredByCurrentUser: status.account.id == appState.currentAccount?.id)

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
                SettingsAvatarButton(
                    account: account,
                    showsUnreadDot: navigationPolicy.showsDrawerAvatarBadge,
                    action: onAvatarTap
                )
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }

            Spacer()

            // Center: Timeline switcher
            timelineSwitcher(style: .header)

            Spacer()

            // Right: Smart contextual slot (unread announcements > hidden Explore search > clean whitespace)
            homeTrailingHeaderSlot
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .frame(height: headerHeight)
        .background(sceneCanvasColor)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
    }

    @ViewBuilder
    private var homeTrailingHeaderSlot: some View {
        switch navigationPolicy.homeTrailingAction {
        case .announcements:
            announcementsButton
        case .search:
            homeSearchButton
        case .none:
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    /// The same contextual controls as toolbar items, used when the system bar replaces the header.
    @ToolbarContentBuilder
    var systemBarToolbar: some ToolbarContent {
        // iPhone Duo with the panel open: the bar shows the panel's controls instead.
        if usesSystemNavigationBar && !panelOwnsSystemBar {
            // In the side bar the Me tab's avatar sits in the same column, so the drawer trigger
            // shows as a menu glyph there instead of a second avatar.
            if let onAvatarTap, toolbarIsVertical {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onAvatarTap) {
                        Label(MoroL10n.Navigation.openMenu, systemImage: "line.3.horizontal")
                    }
                    .accessibilityIdentifier("home.drawerButton")
                }
            } else if let onAvatarTap, let account = appState.currentAccount {
                VerticalPreferredToolbarItem(placement: .topBarLeading) {
                    SettingsAvatarButton(
                        account: account,
                        isToolbarItem: true,
                        showsUnreadDot: navigationPolicy.showsDrawerAvatarBadge,
                        action: onAvatarTap
                    )
                }
            }
            // A title-slot item stays in a bar across the top, so with vertical bars the menu
            // joins the avatar as an ordinary item and moves to the side with the others.
            if toolbarIsVertical {
                ToolbarItem(placement: .topBarLeading) {
                    timelineSwitcher(style: .toolbar)
                }
            } else {
                ToolbarItem(placement: .principal) {
                    timelineSwitcher(style: .toolbar)
                }
            }
            if case .announcements = navigationPolicy.homeTrailingAction {
                VerticalPreferredToolbarItem(placement: .topBarTrailing) {
                    announcementsButton
                }
            } else if case .search = navigationPolicy.homeTrailingAction {
                VerticalPreferredToolbarItem(placement: .topBarTrailing) {
                    homeSearchButton
                }
            }
        }
    }

    func timelineSwitcher(style: TimelineSwitcher.Style) -> some View {
        TimelineSwitcher(
            selectedTimeline: $selectedTimeline,
            pinnedTimelines: pinnedTimelineTypes,
            style: style,
            onManageLists: navigationPolicy.showsTimelineSwitcherListsShortcut
                ? { router.navigate(to: .lists) }
                : nil,
            onManageTopics: { router.navigate(to: .followedTopics) }
        )
    }

    var homeSearchButton: some View {
        Button {
            if let onOpenSearch {
                onOpenSearch()
            } else {
                router.navigate(to: .search(query: nil))
            }
        } label: {
            Image(systemName: "magnifyingglass")
                .moroScaledFont(size: 17, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MoroL10n.Navigation.search)
        .accessibilityIdentifier("home.searchButton")
    }

    var announcementsButton: some View {
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
        .accessibilityIdentifier("home.announcementsButton")
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
            streamWatcher.ensureUserSession(accessToken: appState.authToken)

            // Stage 2: Sync marker as fallback if initial load did not yet resolve one.
            try? await Task.sleep(nanoseconds: startupMarkerDelayAfterStreamNanoseconds)
            guard !Task.isCancelled, scenePhase == .active else { return }
            if settings.syncReadingPositionWithServer, homeViewModel.lastReadStatusID == nil {
                if scrollBridge.hasScrolledHome {
                    try? await Task.sleep(nanoseconds: startupMarkerBackoffOnInteractionNanoseconds)
                    guard !Task.isCancelled, scenePhase == .active else { return }
                }
                await homeViewModel.fetchMarker()
            }

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

/// A toolbar item with a custom view that may still go into iPhone Duo's vertical side bar
/// (custom views stay horizontal unless they opt in).
struct VerticalPreferredToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        // axisBehavior is an iOS 27.1 SDK API (Swift 6.4); older toolchains, such as CI's
        // Xcode 26, build the plain item.
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            ToolbarItem(placement: placement, content: content)
                .axisBehavior(.verticalPreferred)
        } else {
            ToolbarItem(placement: placement, content: content)
        }
        #else
        ToolbarItem(placement: placement, content: content)
        #endif
    }
}
