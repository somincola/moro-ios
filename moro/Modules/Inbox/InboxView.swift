//
//  InboxView.swift
//  moro
//
//  Notifications hub with primary reading tabs and a settings entry point.
//

import SwiftUI

struct InboxView: View {
    @ObservedObject var coordinator: RootTabCoordinator
    @ObservedObject private var notificationUnreadStore = NotificationUnreadStore.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroSceneDescriptor) private var sceneDescriptor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.appRouter) private var router
    @Environment(\.threadSplitPanelOwnsBar) private var panelOwnsBar
    @State private var toolbarIsVertical = false

    @ScaledMetric(relativeTo: .body) private var preferredChromeHeight: CGFloat = 54

    let apiClient: MastodonAPI
    var sessionID: String? = nil

    var body: some View {
        NotificationsView(
            apiClient: apiClient,
            sessionID: sessionID,
            presentation: .inbox,
            isActive: coordinator.selectedTab == .inbox && coordinator.isAtRoot(.inbox),
            selectedFilter: $coordinator.inboxFilter
        )
        .background(sceneCanvasColor)
        .safeAreaInset(edge: .top, spacing: 0) {
            // iPhone Duo: the filters and settings go in the system bar instead, like Home.
            if !coordinator.usesSystemHomeBar {
                inboxChrome
            }
        }
        .toolbar {
            if coordinator.usesSystemHomeBar && !panelOwnsBar {
                systemBarItems
            }
        }
        .background {
            ToolbarAxisReader { isVertical in
                Color.clear.onChange(of: isVertical, initial: true) { _, vertical in
                    toolbarIsVertical = vertical
                }
            }
        }
        .environment(\.tabReselection, coordinator.tabReselection)
    }

    /// Held upright the filters sit in the status row with the settings button; held
    /// landscape they go down the side bar as icons.
    @ToolbarContentBuilder
    private var systemBarItems: some ToolbarContent {
        if toolbarIsVertical {
            VerticalPreferredToolbarItem(placement: .topBarLeading) { filterIconButton(.all) }
            VerticalPreferredToolbarItem(placement: .topBarLeading) { filterIconButton(.mentions) }
        } else {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    filterButton(.all)
                        .frame(minWidth: 96)
                    filterButton(.mentions)
                        .frame(minWidth: 96)
                }
                .frame(height: 44)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                router.navigate(to: .notificationSettings)
            } label: {
                Label(MoroL10n.NotificationSettings.title, systemImage: "gearshape")
            }
            .accessibilityIdentifier("inbox.notificationSettings")
        }
    }

    private func filterIconButton(_ filter: NotificationFilter) -> some View {
        let isSelected = coordinator.inboxFilter == filter
        let unreadCount = filter == .all ? notificationUnreadStore.activeUnreadCount : 0
        return Button {
            coordinator.openInbox(filter)
        } label: {
            Image(systemName: filter.barIcon(filled: isSelected))
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textTertiary)
                .frame(minWidth: 36, minHeight: 36)
                .overlay(alignment: .topTrailing) {
                    if unreadCount > 0 {
                        Circle()
                            .fill(theme.colors.error)
                            .frame(width: 8, height: 8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(unreadCount > 0
            ? "\(filter.title), \(MoroL10n.Navigation.notificationsUnread(unreadCount))" : filter.title)
        .accessibilityIdentifier("inbox.filter.\(filter.rawValue)")
    }

    private var inboxChrome: some View {
        HStack(spacing: 0) {
            ForEach([NotificationFilter.all, .mentions]) { filter in
                filterButton(filter)
            }

            Button {
                router.navigate(to: .notificationSettings)
            } label: {
                Image(systemName: "gearshape")
                    .moroScaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(width: 56, height: chromeHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroL10n.NotificationSettings.title)
            .accessibilityIdentifier("inbox.notificationSettings")
        }
        .frame(height: chromeHeight)
        .background(sceneCanvasColor)
        .dynamicTypeSize(.xSmall ... .xxxLarge)
        .overlay(alignment: .bottom) {
            MoroDivider()
        }
    }

    private var chromeHeight: CGFloat {
        min(max(preferredChromeHeight, 54), 76)
    }

    private var sceneCanvasColor: Color {
        (sceneDescriptor?.canvas ?? .content).backgroundColor(in: theme)
    }

    private func filterButton(_ filter: NotificationFilter) -> some View {
        let isSelected = coordinator.inboxFilter == filter
        let unreadCount = filter == .all ? notificationUnreadStore.activeUnreadCount : 0

        return Button {
            coordinator.openInbox(filter)
        } label: {
            HStack(spacing: 6) {
                Text(filter.title)
                    .font(theme.typography.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.72 : 1)
                    .allowsTightening(true)

                if unreadCount > 0 {
                    if dynamicTypeSize.isAccessibilitySize {
                        Circle()
                            .fill(theme.colors.error)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    } else {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .moroScaledFont(size: 11, weight: .bold, relativeTo: .caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(theme.colors.error)
                            .clipShape(Capsule())
                            .accessibilityHidden(true)
                    }
                }
            }
            .foregroundStyle(isSelected ? theme.colors.textPrimary : theme.colors.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? theme.colors.textPrimary : .clear)
                    .frame(width: 32, height: 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityLabel(unreadCount > 0
            ? "\(filter.title), \(MoroL10n.Navigation.notificationsUnread(unreadCount))" : filter.title)
        .accessibilityIdentifier("inbox.filter.\(filter.rawValue)")
    }
}

private extension NotificationFilter {
    func barIcon(filled: Bool) -> String {
        switch self {
        case .mentions: return "at"
        default: return filled ? "tray.full.fill" : "tray.full"
        }
    }
}
