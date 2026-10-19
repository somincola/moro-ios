//
//  BoostOrQuoteDialog.swift
//  moro
//
//  Dialog for choosing between Boost and Quote actions.
//  Shown when instance supports quote posts.
//

import SwiftUI
import UIKit

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
    
    private let rowHeight: CGFloat = 60
    private let iconSize: CGFloat = 24
    
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 4) {
                actionRow(
                    title: isBoosted ? MoroL10n.BoostDialog.unboost : MoroL10n.BoostDialog.boost,
                    icon: "arrow.2.squarepath"
                ) {
                    if isBoosted {
                        onUnboost()
                    } else {
                        onBoost()
                    }
                    onDismiss()
                }
                .accessibilityIdentifier("boostDialog.boost")

                if canQuote, let title = quoteButtonTitle {
                    actionRow(
                        title: title,
                        icon: "pencil.line"
                    ) {
                        onQuote()
                        onDismiss()
                    }
                    .accessibilityIdentifier("boostDialog.quote")
                } else if let subtitle = quoteButtonSubtitle {
                    Text(subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: rowHeight)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(theme.colors.surfaceElevated.ignoresSafeArea())
        .dynamicTypeSize(theme.dynamicTypeSize)
        .moroSheetSurface(
            detents: [
                theme.dynamicTypeSize.isAccessibilitySize ? .medium : .height(
                    Self.preferredDetentHeight(
                        quoteButtonTitle: quoteButtonTitle,
                        quoteButtonSubtitle: quoteButtonSubtitle
                    )
                )
            ],
            cornerRadius: 28
        )
    }
    
    @ViewBuilder
    private func actionRow(
        title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 20) {
                Image(systemName: icon)
                    .moroScaledFont(size: iconSize)
                    .frame(width: UIFontMetrics(forTextStyle: .body).scaledValue(
                        for: 28,
                        compatibleWith: UITraitCollection(
                            preferredContentSizeCategory: theme.dynamicTypeSize.uiContentSizeCategory
                        )
                    ))
                Text(title)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.vertical, 16)
            .frame(minHeight: rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    static func preferredDetentHeight(
        quoteButtonTitle: String?,
        quoteButtonSubtitle: String?
    ) -> CGFloat {
        let hasSecondaryRow = quoteButtonTitle != nil || quoteButtonSubtitle != nil
        return hasSecondaryRow ? 144 : 80
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
        let visibility = status.displayStatus.visibility
        let isPublicOrUnlisted = visibility == "public" || visibility == "unlisted"
        
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
