//
//  ContentSkeletonView.swift
//  moro
//
//  Lightweight skeleton placeholders used for loading states.
//

import SwiftUI

enum ContentSkeletonStyle {
    case list
    case timeline
    case profile
}

struct ContentSkeletonView: View {
    let style: ContentSkeletonStyle
    
    private enum Metrics {
        static let topPadding: CGFloat = 8
        static let listRowCount: Int = 8
        static let timelineRowCount: Int = 7
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                switch style {
                case .list:
                    ForEach(0..<Metrics.listRowCount, id: \.self) { _ in
                        ListRowSkeleton()
                        MoroDivider()
                    }
                case .timeline:
                    ForEach(0..<Metrics.timelineRowCount, id: \.self) { _ in
                        TimelineRowSkeleton()
                        MoroDivider()
                    }
                case .profile:
                    ProfileSkeleton()
                }
            }
            .padding(.top, Metrics.topPadding)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TimelineRowSkeleton: View {
    @Environment(\.moroTheme) private var theme
    
    private enum Metrics {
        static let avatarCornerRadius: CGFloat = 18
        static let avatarSize: CGFloat = 36
        static let lineCornerRadius: CGFloat = 4
        static let titleWidth: CGFloat = 120
        static let titleLineHeight: CGFloat = 12
        static let trailingLineWidth: CGFloat = 180
    }

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            RoundedRectangle(cornerRadius: Metrics.avatarCornerRadius, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
                .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)

            VStack(alignment: .leading, spacing: theme.spacing.s) {
                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: Metrics.titleWidth, height: Metrics.titleLineHeight)
                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(height: Metrics.titleLineHeight)
                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: Metrics.trailingLineWidth, height: Metrics.titleLineHeight)
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.vertical, theme.spacing.timelineVertical)
        .redacted(reason: .placeholder)
    }
}

private struct ListRowSkeleton: View {
    @Environment(\.moroTheme) private var theme
    
    private enum Metrics {
        static let avatarCornerRadius: CGFloat = 20
        static let avatarSize: CGFloat = 40
        static let lineCornerRadius: CGFloat = 4
        static let titleWidth: CGFloat = 130
        static let titleHeight: CGFloat = 12
        static let subtitleWidth: CGFloat = 210
        static let subtitleHeight: CGFloat = 10
    }

    var body: some View {
        HStack(spacing: theme.spacing.m) {
            RoundedRectangle(cornerRadius: Metrics.avatarCornerRadius, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
                .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)

            VStack(alignment: .leading, spacing: theme.spacing.s) {
                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: Metrics.titleWidth, height: Metrics.titleHeight)
                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: Metrics.subtitleWidth, height: Metrics.subtitleHeight)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.vertical, theme.spacing.m)
        .redacted(reason: .placeholder)
    }
}

private struct ProfileSkeleton: View {
    @Environment(\.moroTheme) private var theme
    
    private enum Metrics {
        static let headerHeight: CGFloat = 140
        static let avatarCornerRadius: CGFloat = 32
        static let avatarSize: CGFloat = 72
        static let avatarTopOverlap: CGFloat = -36
        static let lineCornerRadius: CGFloat = 4
        static let displayNameWidth: CGFloat = 170
        static let displayNameHeight: CGFloat = 16
        static let lineHeight: CGFloat = 12
        static let shortLineWidth: CGFloat = 230
        static let postSkeletonCount: Int = 4
    }

    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(theme.colors.surfaceSubtle)
                .frame(height: Metrics.headerHeight)

            VStack(alignment: .leading, spacing: theme.spacing.m) {
                RoundedRectangle(cornerRadius: Metrics.avatarCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: Metrics.avatarSize, height: Metrics.avatarSize)
                    .padding(.top, Metrics.avatarTopOverlap)

                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: Metrics.displayNameWidth, height: Metrics.displayNameHeight)

                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(height: Metrics.lineHeight)
                RoundedRectangle(cornerRadius: Metrics.lineCornerRadius, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
                    .frame(width: Metrics.shortLineWidth, height: Metrics.lineHeight)
            }
            .padding(.horizontal, theme.spacing.contentHorizontalInset)

            ForEach(0..<Metrics.postSkeletonCount, id: \.self) { _ in
                ListRowSkeleton()
                MoroDivider()
            }
        }
        .redacted(reason: .placeholder)
    }
}
