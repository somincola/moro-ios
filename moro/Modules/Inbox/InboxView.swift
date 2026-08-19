//
//  InboxView.swift
//  moro
//
//  Relationship hub combining notifications and direct messages under one root scene.
//

import SwiftUI

struct InboxView: View {
    @ObservedObject var coordinator: RootTabCoordinator
    @ObservedObject private var inboxUnreadStore = InboxUnreadStore.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroSceneDescriptor) private var sceneDescriptor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .body) private var preferredChromeHeight: CGFloat = 54
    @State private var notificationFilter: NotificationFilter = .all
    @State private var newMessageRequestVersion = 0

    let apiClient: MastodonAPI

    var body: some View {
        ZStack {
            NotificationsView(
                apiClient: apiClient,
                presentation: .inbox,
                isActive: coordinator.inboxSection == .notifications,
                selectedFilter: $notificationFilter
            )
            .opacity(coordinator.inboxSection == .notifications ? 1 : 0)
            .allowsHitTesting(coordinator.inboxSection == .notifications)
            .accessibilityHidden(coordinator.inboxSection != .notifications)

            DirectMessagesView(
                apiClient: apiClient,
                showsDismissButton: false,
                presentation: .inbox,
                isActive: coordinator.inboxSection == .messages,
                newConversationRequest: newMessageRequestVersion
            )
            .opacity(coordinator.inboxSection == .messages ? 1 : 0)
            .allowsHitTesting(coordinator.inboxSection == .messages)
            .accessibilityHidden(coordinator.inboxSection != .messages)
        }
        .background(sceneCanvasColor)
        .safeAreaInset(edge: .top, spacing: 0) {
            inboxChrome
        }
        .environment(\.selectedTabScrollToTop, coordinator.selectedTabScrollToTop)
    }

    private var inboxChrome: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(InboxSection.allCases) { section in
                    sectionButton(section)
                }
            }

            contextAction
                .frame(width: contextActionWidth, height: chromeHeight)
                .animation(.easeOut(duration: 0.18), value: contextActionWidth)
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

    private var contextActionWidth: CGFloat {
        guard coordinator.inboxSection == .notifications else { return 56 }
        return notificationFilter == .all ? 56 : 128
    }

    private func sectionButton(_ section: InboxSection) -> some View {
        let isSelected = coordinator.inboxSection == section
        let unreadCount = unreadCount(for: section)

        return Button {
            coordinator.openInbox(section)
        } label: {
            HStack(spacing: 6) {
                Text(section.title)
                    .font(theme.typography.body)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.72 : 1)
                    .allowsTightening(true)

                if unreadCount > 0 {
                    if dynamicTypeSize.isAccessibilitySize {
                        Circle()
                            .fill(unreadColor(for: section))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                    } else {
                        Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                            .moroScaledFont(size: 11, weight: .bold, relativeTo: .caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(unreadColor(for: section))
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
        .accessibilityLabel(accessibilityLabel(for: section))
    }

    @ViewBuilder
    private var contextAction: some View {
        switch coordinator.inboxSection {
        case .notifications:
            NotificationFilterMenu(
                selectedFilter: $notificationFilter,
                style: notificationFilter == .all ? .icon : .labeled
            )

        case .messages:
            Button {
                newMessageRequestVersion += 1
            } label: {
                Image(systemName: "plus.message")
                    .moroScaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroL10n.DirectMessages.newMessage)
        }
    }

    private func unreadColor(for section: InboxSection) -> Color {
        section == .notifications ? theme.colors.error : theme.colors.contentLink
    }

    private func accessibilityLabel(for section: InboxSection) -> String {
        let unreadCount = unreadCount(for: section)
        guard unreadCount > 0 else {
            return section.title
        }
        switch section {
        case .notifications:
            return MoroL10n.Navigation.notificationsUnread(unreadCount)
        case .messages:
            return MoroL10n.Navigation.messagesUnread(unreadCount)
        }
    }

    private func unreadCount(for section: InboxSection) -> Int {
        switch section {
        case .notifications:
            return inboxUnreadStore.notificationUnreadCount
        case .messages:
            return inboxUnreadStore.messageUnreadCount
        }
    }
}
