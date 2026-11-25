//
//  PaginationFooter.swift
//  moro
//
//  Shared bottom footer for paginated lists: shows a lightweight breathing mascot
//  while loading the next page, or a subtle capsule retry button on failure.
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
                HStack {
                    Spacer(minLength: 0)
                    MoroStateActionButton(
                        title: MoroL10n.Common.loadMoreRetry,
                        style: .subtle,
                        systemImage: "arrow.clockwise",
                        action: onRetry
                    )
                    Spacer(minLength: 0)
                }
                .padding(.vertical, theme.spacing.m)
                .accessibilityLabel(Text(MoroL10n.Common.loadMoreRetry))
            } else if isLoadingMore {
                HStack {
                    Spacer(minLength: 0)
                    MoroMascotView(expression: .thinking, size: 32)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, theme.spacing.m)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(MoroL10n.Search.loading))
            }
        }
    }
}
