//
//  BoostOrQuoteDialog.swift
//  moro
//
//  Dialog for choosing between Boost and Quote actions.
//  Shown when instance supports quote posts.
//

import SwiftUI

struct BoostOrQuoteDialog: View {
    let status: Status
    let isBoosted: Bool
    let canQuote: Bool
    let quoteButtonTitle: String?
    let quoteButtonSubtitle: String?
    let onBoost: () -> Void
    let onUnboost: () -> Void
    let onQuote: () -> Void
    let onDismiss: () -> Void
    
    @Environment(\.moroTheme) private var theme
    
    private let rowHeight: CGFloat = 52
    private let iconSize: CGFloat = 18
    
    var body: some View {
        VStack(spacing: 0) {
            actionRow(
                title: isBoosted ? MoroL10n.BoostDialog.unboost : MoroL10n.BoostDialog.boost,
                icon: "repeat"
            ) {
                if isBoosted {
                    onUnboost()
                } else {
                    onBoost()
                }
                onDismiss()
            }

            if canQuote, let title = quoteButtonTitle {
                divider

                actionRow(
                    title: title,
                    icon: "quote.bubble"
                ) {
                    onQuote()
                    onDismiss()
                }
            } else if let subtitle = quoteButtonSubtitle {
                divider
                Text(subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .padding(.horizontal, theme.spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: rowHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.colors.background)
    }
    
    @ViewBuilder
    private func actionRow(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: theme.spacing.s) {
                Image(systemName: icon)
                    .moroScaledFont(size: iconSize, weight: .semibold)
                Text(title)
                    .font(theme.typography.bodyStrong)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, theme.spacing.l)
            .frame(height: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private var divider: some View {
        Rectangle()
            .fill(theme.colors.borderSubtle)
            .frame(height: 1)
    }
    
    static func preferredDetentHeight(
        quoteButtonTitle: String?,
        quoteButtonSubtitle: String?
    ) -> CGFloat {
        let hasSecondaryRow = quoteButtonTitle != nil || quoteButtonSubtitle != nil
        // A compact baseline with small headroom for system drag indicator / rounding.
        return hasSecondaryRow ? 112 : 64
    }
}

/// Helper to determine quote button state for a status
struct QuoteButtonInfo {
    let title: String?
    let subtitle: String?
    let isEnabled: Bool
    
    static func forStatus(_ status: Status, currentUserID: String?) -> QuoteButtonInfo {
        // Simplified version - in a full implementation, this would check:
        // 1. User's default visibility (must not be direct)
        // 2. Post's quote approval policy
        // 3. Whether user follows the author (for followers-only quotes)
        
        // For now, we'll assume quotes are enabled if the status is public/unlisted
        let isPublicOrUnlisted = status.visibility == "public" || status.visibility == "unlisted"
        
        if isPublicOrUnlisted {
            return QuoteButtonInfo(
                title: MoroL10n.BoostDialog.quote,
                subtitle: nil,
                isEnabled: true
            )
        } else {
            return QuoteButtonInfo(
                title: nil,
                subtitle: MoroL10n.BoostDialog.quoteDisabled,
                isEnabled: false
            )
        }
    }
}

#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "user",
        acct: "user@example.com",
        displayName: "Test User",
        note: "",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 0,
        followingCount: 0,
        statusesCount: 0
    )
    
    let sampleStatus = Status(
        id: "1",
        content: "Test post",
        createdAt: Date(),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 0,
        reblogsCount: 0,
        repliesCount: 0,
        bookmarked: false,
        favourited: false,
        reblogged: false
    )
    
    return BoostOrQuoteDialog(
        status: sampleStatus,
        isBoosted: false,
        canQuote: true,
        quoteButtonTitle: MoroL10n.BoostDialog.quote,
        quoteButtonSubtitle: nil,
        onBoost: {},
        onUnboost: {},
        onQuote: {},
        onDismiss: {}
    )
    .moroTheme(MoroTheme())
}
