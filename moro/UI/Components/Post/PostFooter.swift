//
//  PostFooter.swift
//  moro
//
//  Post footer component (timestamp, engagement stats)
//

import SwiftUI

/// Post footer component for detail view
struct PostFooter: View {
    let status: Status
    var showFullTimestamp: Bool = false
    var showEngagementStats: Bool = false

    @Environment(\.moroTheme) private var theme
    
    private enum Metrics {
        static let sectionSpacing: CGFloat = 12
        static let inlineSpacing: CGFloat = 4
        static let statsSpacing: CGFloat = 16
        static let iconSize: CGFloat = 13
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            // Full timestamp (for detail view)
            if showFullTimestamp {
                HStack(spacing: Metrics.inlineSpacing) {
                    Image(systemName: "calendar")
                        .moroScaledFont(size: Metrics.iconSize)
                        .accessibilityHidden(true)
                    Text(fullDateString(from: status.createdAt))
                        .font(theme.typography.body)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }

            // Engagement stats bar (if any)
            if showEngagementStats
                && (status.reblogsCount > 0 || status.favouritesCount > 0
                    || status.repliesCount > 0)
            {
                engagementStatsBar
            }
        }
    }

    // MARK: - Engagement Stats Bar

    @ViewBuilder
    private var engagementStatsBar: some View {
        HStack(spacing: Metrics.statsSpacing) {
            if status.reblogsCount > 0 {
                HStack(spacing: Metrics.inlineSpacing) {
                    Text("\(status.reblogsCount)")
                        .fontWeight(.semibold)
                    Text(MoroL10n.PostFooter.boosts)
                }
            }

            if status.repliesCount > 0 {
                HStack(spacing: Metrics.inlineSpacing) {
                    Text("\(status.repliesCount)")
                        .fontWeight(.semibold)
                    Text(MoroL10n.PostFooter.replies)
                }
            }

            if status.favouritesCount > 0 {
                HStack(spacing: Metrics.inlineSpacing) {
                    Image(systemName: "star")
                        .moroScaledFont(size: Metrics.iconSize)
                        .accessibilityHidden(true)
                    Text("\(status.favouritesCount)")
                        .fontWeight(.semibold)
                    Text(MoroL10n.PostFooter.favourites)
                }
            }

            Spacer()
        }
        .font(theme.typography.body)
        .foregroundStyle(theme.colors.textSecondary)
    }

    // MARK: - Helpers

    private func fullDateString(from date: Date) -> String {
        DateFormatting.dateTimeString(from: date)
    }
}
