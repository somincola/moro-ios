//
//  StatusMoreMenu.swift
//  moro
//
//  More menu for status actions (Share, Copy Link, Mute, Block, Report).
//  Designed to be extensible for future actions.
//

import SwiftUI

private enum MoroMenuMetrics {
    static let iconPointSize: CGFloat = 15
    static let iconSlotWidth: CGFloat = 18
    static let labelSpacing: CGFloat = 12
}

enum MoroMenuItemTone {
    case standard
    case destructive

    var buttonRole: ButtonRole? {
        switch self {
        case .standard:
            return nil
        case .destructive:
            return .destructive
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .standard:
            return .primary
        case .destructive:
            return Color(uiColor: .systemRed)
        }
    }

    var uiColor: UIColor {
        switch self {
        case .standard:
            return .label
        case .destructive:
            return .systemRed
        }
    }
}

private struct MoroMenuGlyph: View {
    let systemImage: String
    let tintColor: UIColor

    var body: some View {
        Image(uiImage: renderedImage)
            .renderingMode(.original)
            .frame(width: MoroMenuMetrics.iconSlotWidth, alignment: .center)
    }

    private var renderedImage: UIImage {
        let configuration = UIImage.SymbolConfiguration(
            pointSize: MoroMenuMetrics.iconPointSize,
            weight: .medium
        )
        let baseImage = UIImage(systemName: systemImage, withConfiguration: configuration)
            ?? UIImage()
        return baseImage.withTintColor(tintColor, renderingMode: .alwaysOriginal)
    }
}

private struct MoroMoreMenuTriggerLabel: View {
    var iconSize: CGFloat = 21
    @Environment(\.moroTheme) private var theme

    var body: some View {
        Image(systemName: "ellipsis")
            .moroScaledFont(size: iconSize, weight: .regular)
            .foregroundStyle(theme.colors.textSecondary)
            .frame(width: 22, height: 22)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            // Mirror the post toolbar's height so the tap target fills the row.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
    }
}

struct MoroMenuItemLabel: View {
    let title: String
    let systemImage: String
    var isDestructive: Bool = false

    private var tone: MoroMenuItemTone {
        isDestructive ? .destructive : .standard
    }

    var body: some View {
        HStack(spacing: MoroMenuMetrics.labelSpacing) {
            MoroMenuGlyph(systemImage: systemImage, tintColor: tone.uiColor)

            Text(title)
                .moroScaledFont(size: 15)
                .foregroundStyle(tone.swiftUIColor)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct MoroMenuActionButton: View {
    let title: String
    let systemImage: String
    var tone: MoroMenuItemTone = .standard
    let action: () -> Void

    var body: some View {
        Button(role: tone.buttonRole, action: action) {
            MoroMenuItemLabel(
                title: title,
                systemImage: systemImage,
                isDestructive: tone == .destructive
            )
        }
    }
}

/// Menu item configuration for status more menu
struct StatusMoreMenuItem {
    let title: String
    let icon: String
    let role: ButtonRole? // Use .destructive for dangerous actions
    let action: () -> Void
}

typealias StatusMoreMenuVisibility = PostMoreMenuVisibility

struct StatusMoreMenu: View {
    let status: Status
    let onShare: () -> Void
    let onCopyLink: () -> Void
    let onCopyText: () -> Void
    let onOpenInBrowser: () -> Void
    let onMuteUser: () -> Void
    let onBlockUser: () -> Void
    let onReport: () -> Void

    var body: some View {
        Menu {
            // Share
            Button(action: onShare) {
                MoroMenuItemLabel(title: "Share", systemImage: "square.and.arrow.up")
            }

            // Copy Link
            Button(action: onCopyLink) {
                MoroMenuItemLabel(title: "Copy link", systemImage: "link")
            }

            Button(action: onCopyText) {
                MoroMenuItemLabel(title: "Copy text", systemImage: "doc.on.doc")
            }

            Button(action: onOpenInBrowser) {
                MoroMenuItemLabel(title: "Open in browser", systemImage: "safari")
            }

            Divider()

            // Mute User
            Button(action: onMuteUser) {
                MoroMenuItemLabel(title: "Mute @\(status.account.username)", systemImage: "bell.slash")
            }

            // Block User
            MoroMenuActionButton(
                title: "Block @\(status.account.username)",
                systemImage: "hand.raised",
                tone: .destructive,
                action: onBlockUser
            )

            Divider()

            // Report
            MoroMenuActionButton(
                title: "Report",
                systemImage: "flag",
                tone: .destructive,
                action: onReport
            )

        } label: {
            MoroMoreMenuTriggerLabel()
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }
}

/// Simplified more button without menu labels (icon only)
struct StatusMoreButton: View {
    let status: Status
    let isOwnPost: Bool
    let isMutingUser: Bool?
    let isBlockingUser: Bool?
    
    // Common actions
    let onShare: (() -> Void)?
    let onCopyLink: (() -> Void)?
    let onCopyText: (() -> Void)?
    let onOpenInBrowser: (() -> Void)?
    let onEdit: (() -> Void)?
    
    // Other user actions
    let onMuteUser: (() -> Void)?
    let onBlockUser: (() -> Void)?
    let onBlockAndReport: (() -> Void)?
    let onReport: (() -> Void)?
    
    // Own post actions
    let onPin: (() -> Void)?
    let onDeleteAndRedraft: (() -> Void)?
    let onDelete: (() -> Void)?
    let iconSize: CGFloat

    init(
        status: Status,
        isOwnPost: Bool = false,
        isMutingUser: Bool? = nil,
        isBlockingUser: Bool? = nil,
        onShare: (() -> Void)? = nil,
        onCopyLink: (() -> Void)? = nil,
        onCopyText: (() -> Void)? = nil,
        onOpenInBrowser: (() -> Void)? = nil,
        onEdit: (() -> Void)? = nil,
        onMuteUser: (() -> Void)? = nil,
        onBlockUser: (() -> Void)? = nil,
        onBlockAndReport: (() -> Void)? = nil,
        onReport: (() -> Void)? = nil,
        onPin: (() -> Void)? = nil,
        onDeleteAndRedraft: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil,
        iconSize: CGFloat = 21
    ) {
        self.status = status
        self.isOwnPost = isOwnPost
        self.isMutingUser = isMutingUser
        self.isBlockingUser = isBlockingUser
        self.onShare = onShare
        self.onCopyLink = onCopyLink
        self.onCopyText = onCopyText
        self.onOpenInBrowser = onOpenInBrowser
        self.onEdit = onEdit
        self.onMuteUser = onMuteUser
        self.onBlockUser = onBlockUser
        self.onBlockAndReport = onBlockAndReport
        self.onReport = onReport
        self.onPin = onPin
        self.onDeleteAndRedraft = onDeleteAndRedraft
        self.onDelete = onDelete
        self.iconSize = iconSize
    }

    var body: some View {
        let visibility = menuVisibility
        Menu {
            if visibility.showShare, let onShare {
                Button(action: {
                    performAction(onShare)
                }) {
                    MoroMenuItemLabel(title: "Share", systemImage: "square.and.arrow.up")
                }
            }

            if visibility.showCopyLink, let onCopyLink {
                Button(action: {
                    performAction(onCopyLink)
                }) {
                    MoroMenuItemLabel(title: "Copy link", systemImage: "link")
                }
            }

            if visibility.showCopyText, let onCopyText {
                Button(action: {
                    performAction(onCopyText)
                }) {
                    MoroMenuItemLabel(title: "Copy text", systemImage: "doc.on.doc")
                }
            }

            if visibility.showOpenInBrowser, let onOpenInBrowser {
                Button(action: {
                    performAction(onOpenInBrowser)
                }) {
                    MoroMenuItemLabel(title: "Open in browser", systemImage: "safari")
                }
            }
            
            if isOwnPost {
                if visibility.hasCommonActions && visibility.hasOwnActions {
                    Divider()
                }

                if visibility.showEdit, let onEdit {
                    Button {
                        performAction(onEdit)
                    } label: {
                        MoroMenuItemLabel(title: "Edit post", systemImage: "square.and.pencil")
                    }
                }

                if visibility.showPin, let onPin = onPin {
                    if visibility.showEdit {
                        Divider()
                    }
                    Button {
                        performAction(onPin)
                    } label: {
                        MoroMenuItemLabel(
                            title: status.pinned == true ? "Unpin from profile" : "Pin to profile",
                            systemImage: status.pinned == true ? "pin.slash" : "pin"
                        )
                    }
                }

                if visibility.showDeleteAndRedraft || visibility.showDelete {
                    if visibility.showEdit || visibility.showPin {
                        Divider()
                    }

                    if visibility.showDeleteAndRedraft, let onDeleteAndRedraft {
                        MoroMenuActionButton(
                            title: MoroL10n.ComposeDrafts.deleteAndRedraftAction,
                            systemImage: "arrow.uturn.backward",
                            tone: .destructive,
                            action: { performAction(onDeleteAndRedraft) }
                        )
                    }

                    if visibility.showDelete, let onDelete {
                        MoroMenuActionButton(
                            title: "Delete",
                            systemImage: "trash",
                            tone: .destructive,
                            action: { performAction(onDelete) }
                        )
                    }
                }
            } else {
                if visibility.hasCommonActions && visibility.hasOtherActions {
                    Divider()
                }

                if visibility.showMuteUser, let onMuteUser {
                    Button(action: {
                        performAction(onMuteUser)
                    }) {
                        MoroMenuItemLabel(
                            title: isMutingUser == true
                                ? "Unmute @\(actionAccount.username)"
                                : "Mute @\(actionAccount.username)",
                            systemImage: isMutingUser == true ? "bell" : "bell.slash"
                        )
                    }
                }

                if visibility.showBlockUser, let onBlockUser {
                    if isBlockingUser == true {
                        Button(action: {
                            performAction(onBlockUser)
                        }) {
                            MoroMenuItemLabel(
                                title: "Unblock @\(actionAccount.username)",
                                systemImage: "hand.raised.slash"
                            )
                        }
                    } else {
                        MoroMenuActionButton(
                            title: "Block @\(actionAccount.username)",
                            systemImage: "hand.raised",
                            tone: .destructive,
                            action: { performAction(onBlockUser) }
                        )
                    }
                }

                if visibility.showBlockAndReport, let onBlockAndReport {
                    MoroMenuActionButton(
                        title: "Block and report",
                        systemImage: "hand.raised.circle",
                        tone: .destructive,
                        action: { performAction(onBlockAndReport) }
                    )
                }

                if visibility.showReport, let onReport {
                    if visibility.showMuteUser || visibility.showBlockUser || visibility.showBlockAndReport
                    {
                        Divider()
                    }
                    MoroMenuActionButton(
                        title: "Report",
                        systemImage: "flag",
                        tone: .destructive,
                        action: { performAction(onReport) }
                    )
                }
            }

        } label: {
            MoroMoreMenuTriggerLabel(iconSize: iconSize)
        }
        .buttonStyle(.plain)
        .transaction { transaction in
            transaction.disablesAnimations = true
        }
    }

    private var actionAccount: Account {
        status.displayStatus.account
    }

    private var menuVisibility: StatusMoreMenuVisibility {
        Self.visibility(
            isOwnPost: isOwnPost,
            isBlockingUser: isBlockingUser,
            hasShare: onShare != nil,
            hasCopyLink: onCopyLink != nil,
            hasCopyText: onCopyText != nil,
            hasOpenInBrowser: onOpenInBrowser != nil,
            hasEdit: onEdit != nil,
            hasMuteUser: onMuteUser != nil,
            hasBlockUser: onBlockUser != nil,
            hasBlockAndReport: onBlockAndReport != nil,
            hasReport: onReport != nil,
            hasPin: onPin != nil,
            hasDeleteAndRedraft: onDeleteAndRedraft != nil,
            hasDelete: onDelete != nil
        )
    }

    static func visibility(
        isOwnPost: Bool,
        isBlockingUser: Bool?,
        hasShare: Bool,
        hasCopyLink: Bool,
        hasCopyText: Bool,
        hasOpenInBrowser: Bool,
        hasEdit: Bool,
        hasMuteUser: Bool,
        hasBlockUser: Bool,
        hasBlockAndReport: Bool,
        hasReport: Bool,
        hasPin: Bool,
        hasDeleteAndRedraft: Bool,
        hasDelete: Bool
    ) -> StatusMoreMenuVisibility {
        PostMoreMenuPolicy.visibility(
            isOwnPost: isOwnPost,
            isBlockingUser: isBlockingUser,
            hasShare: hasShare,
            hasCopyLink: hasCopyLink,
            hasCopyText: hasCopyText,
            hasOpenInBrowser: hasOpenInBrowser,
            hasEdit: hasEdit,
            hasMuteUser: hasMuteUser,
            hasBlockUser: hasBlockUser,
            hasBlockAndReport: hasBlockAndReport,
            hasReport: hasReport,
            hasPin: hasPin,
            hasDeleteAndRedraft: hasDeleteAndRedraft,
            hasDelete: hasDelete
        )
    }

    private func performAction(_ action: @escaping () -> Void) {
        // Add haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

        action()
    }
}
