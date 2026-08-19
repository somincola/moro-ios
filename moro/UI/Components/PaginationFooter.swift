//
//  PaginationFooter.swift
//  moro
//
//  Shared bottom footer for paginated lists: shows a spinner while loading the
//  next page, or a tappable "tap to retry" affordance when load-more failed.
//

import SwiftUI

struct PaginationFooter: View {
    let isLoadingMore: Bool
    let didFail: Bool
    let onRetry: () -> Void

    @Environment(\.moroTheme) private var theme

    var body: some View {
        Group {
            if didFail {
                Button(action: onRetry) {
                    HStack(spacing: theme.spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .moroScaledFont(size: 13, weight: .semibold)
                        Text(MoroL10n.Common.loadMoreRetry)
                            .font(theme.typography.caption)
                    }
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.spacing.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(MoroL10n.Common.loadMoreRetry))
            } else if isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, theme.spacing.m)
            }
        }
    }
}
