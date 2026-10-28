//
//  ContentStateView.swift
//  moro
//
//  Shared loading/empty/error states for list-style pages.
//

import SwiftUI

enum ContentState {
    case loading(ContentSkeletonStyle = .list)
    case loaded
    case empty(EmptyStateSpec)
    case error(ErrorStateSpec)
}

enum ContentStateAlignment {
    case leading
    case center

    var horizontalAlignment: HorizontalAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        }
    }

    var textAlignment: TextAlignment {
        switch self {
        case .leading:
            return .leading
        case .center:
            return .center
        }
    }
}

struct EmptyStateSpec {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?
    var alignment: ContentStateAlignment = .center
}

struct ErrorStateSpec {
    let title: String
    let message: String
    var actionTitle: String = MoroL10n.ContentState.retry
    var action: (() -> Void)?
    var alignment: ContentStateAlignment = .center
}

struct ContentStateContainer<Content: View>: View {
    let state: ContentState
    let content: () -> Content

    init(
        state: ContentState,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.state = state
        self.content = content
    }

    var body: some View {
        switch state {
        case .loading(let skeletonStyle):
            // Same column as the loaded rows, so wide screens don't flash an edge-to-edge skeleton.
            ContentSkeletonView(style: skeletonStyle)
                .moroReadableColumn()
        case .loaded:
            content()
        case .empty(let spec):
            EmptyStateView(spec: spec)
        case .error(let spec):
            ErrorStateView(spec: spec)
        }
    }
}

struct EmptyStateView: View {
    @Environment(\.moroTheme) private var theme

    let spec: EmptyStateSpec

    var body: some View {
        VStack(spacing: theme.spacing.l) {
            Image(systemName: spec.icon)
                .moroScaledFont(size: 48, weight: .light)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.textSecondary)

            VStack(spacing: theme.spacing.xs) {
                Text(spec.title)
                    .font(theme.typography.subtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(spec.message)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 300)

            if let actionTitle = spec.actionTitle, let action = spec.action {
                MoroButton(title: actionTitle, kind: .secondary, action: action)
                    .frame(maxWidth: 210)
                    .padding(.top, theme.spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, theme.spacing.xl)
    }
}

struct ErrorStateView: View {
    @Environment(\.moroTheme) private var theme

    let spec: ErrorStateSpec

    var body: some View {
        VStack(alignment: spec.alignment.horizontalAlignment, spacing: theme.spacing.l) {
            Image(systemName: "exclamationmark.triangle")
                .moroScaledFont(size: 46, weight: .light)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(theme.colors.error)

            VStack(alignment: spec.alignment.horizontalAlignment, spacing: theme.spacing.xs) {
                Text(spec.title)
                    .font(theme.typography.subtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                Text(spec.message)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(spec.alignment.textAlignment)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 360, alignment: spec.alignment.frameAlignment)

            if let action = spec.action {
                MoroButton(title: spec.actionTitle, kind: .primary, action: action)
                    .frame(maxWidth: 210)
                    .padding(.top, theme.spacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, theme.spacing.xl)
    }
}
