//
//  PostAuthorInfo.swift
//  moro
//
//  Author information component with two layout modes: timeline and detail
//

import SwiftUI

/// Author information component with two layout modes
struct PostAuthorInfo: View {
    enum LayoutMode {
        /// Timeline mode: horizontal layout with name + handle + time (time right-aligned)
        case timeline
        /// Detail mode: vertical layout with name and handle, time shown separately below
        case detail
    }

    let account: Account
    let createdAt: Date
    let layoutMode: LayoutMode
    var onAvatarTap: (() -> Void)? = nil
    var onUsernameTap: (() -> Void)? = nil
    var onStatusTap: (() -> Void)? = nil
    var avatarSize: CGFloat = 36
    var hideAvatar: Bool = false
    var isQuoted: Bool = false  // Whether this is a quoted/referenced post (for gray styling)

    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    private var displayHandle: String {
        account.acct.isEmpty ? account.username : account.acct
    }

    private var formattedHandle: String {
        "\u{200E}@\(displayHandle)"
    }

    var body: some View {
        switch layoutMode {
        case .timeline:
            timelineLayout
        case .detail:
            detailLayout
        }
    }

    // MARK: - Timeline Layout (Two-line identity block + fixed top-right time)

    private var timelineLayout: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.spacing.xs) {
                    timelineIdentity
                    timelineTimestamp
                }
            } else {
                HStack(alignment: .top, spacing: theme.spacing.s) {
                    timelineIdentity
                        .layoutPriority(1)

                    timelineTimestamp
                        .layoutPriority(3)
                }
            }
        }
    }

    private var timelineIdentity: some View {
        Button(action: { onUsernameTap?() }) {
            VStack(alignment: .leading, spacing: 2) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: isQuoted ? theme.colors.textSecondary : theme.colors.textPrimary,
                    lineLimit: dynamicTypeSize.isAccessibilitySize ? 2 : 1,
                    truncationMode: .tail,
                    minimumScaleFactor: dynamicTypeSize.isAccessibilitySize ? 1 : 0.86,
                    allowsTightening: !dynamicTypeSize.isAccessibilitySize
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(formattedHandle)
                    .moroIdentityHandleLine()
                    .moroScaledFont(size: 14)
                    .foregroundStyle(
                        isQuoted ? theme.colors.textTertiary : theme.colors.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(MoroL10n.Profile.openProfile(displayHandle))
    }

    @ViewBuilder
    private var timelineTimestamp: some View {
        if let onStatusTap {
            Button(action: onStatusTap) {
                timestampLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroL10n.Post.openStatus(account.displayNameFormatted))
        } else {
            timestampLabel
                .accessibilityLabel(createdAt.formatted(date: .omitted, time: .shortened))
        }
    }

    private var timestampLabel: some View {
        Text(timeAgoString(from: createdAt))
            .moroScaledFont(size: 14)
            .foregroundStyle(isQuoted ? theme.colors.textTertiary : theme.colors.textSecondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: - Detail Layout (Vertical: name, handle)

    @ViewBuilder
    private var detailLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { onUsernameTap?() }) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: isQuoted ? theme.colors.textSecondary : theme.colors.textPrimary,
                    lineLimit: 1,
                    truncationMode: .tail,
                    minimumScaleFactor: 0.86,
                    allowsTightening: true
                )
            }
            .buttonStyle(.plain)

            Button(action: { onUsernameTap?() }) {
                Text(formattedHandle)
                    .font(theme.typography.body)
                    .foregroundStyle(
                        isQuoted ? theme.colors.textTertiary : theme.colors.textSecondary)
                    .moroIdentityHandleLine()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func timeAgoString(from date: Date) -> String {
        DateFormatting.relativeString(for: date)
    }
}
