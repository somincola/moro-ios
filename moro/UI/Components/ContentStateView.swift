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
    var mascot: MoroMascotExpression? = nil
    var actionProminent: Bool = false
    var actionAccessibilityIdentifier: String? = nil

    var resolvedMascot: MoroMascotExpression {
        if let mascot { return mascot }
        let lowered = icon.lowercased()
        if lowered.contains("slash") {
            return .resting
        }
        if lowered.contains("magnifyingglass")
            || lowered.contains("questionmark")
            || lowered.contains("decrease")
            || lowered == "number"
        {
            return .curious
        }
        return .calm
    }
}

struct ErrorStateSpec {
    let title: String
    let message: String
    var actionTitle: String = MoroL10n.ContentState.retry
    var action: (() -> Void)?
    var alignment: ContentStateAlignment = .center
    var mascot: MoroMascotExpression = .offline
    var actionAccessibilityIdentifier: String? = nil
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
        VStack(alignment: spec.alignment.horizontalAlignment, spacing: 14) {
            MoroMascotView(expression: spec.resolvedMascot, size: 58)

            VStack(alignment: spec.alignment.horizontalAlignment, spacing: 6) {
                Text(spec.title)
                    .font(theme.typography.subtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(spec.alignment.textAlignment)

                if !spec.message.isEmpty {
                    Text(spec.message)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(spec.alignment.textAlignment)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 280, alignment: spec.alignment.frameAlignment)

            if let actionTitle = spec.actionTitle, let action = spec.action {
                MoroStateActionButton(
                    title: actionTitle,
                    style: spec.actionProminent ? .prominent : .subtle,
                    accessibilityIdentifier: spec.actionAccessibilityIdentifier,
                    action: action
                )
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, theme.spacing.xl)
        .padding(.vertical, theme.spacing.l)
    }
}

struct ErrorStateView: View {
    @Environment(\.moroTheme) private var theme

    let spec: ErrorStateSpec

    var body: some View {
        VStack(alignment: spec.alignment.horizontalAlignment, spacing: 14) {
            MoroMascotView(expression: spec.mascot, size: 58)

            VStack(alignment: spec.alignment.horizontalAlignment, spacing: 6) {
                Text(spec.title)
                    .font(theme.typography.subtitle)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(spec.alignment.textAlignment)

                Text(MoroErrorCopy.sanitized(spec.message))
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(spec.alignment.textAlignment)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 280, alignment: spec.alignment.frameAlignment)

            if let action = spec.action {
                MoroStateActionButton(
                    title: spec.actionTitle,
                    style: .prominent,
                    accessibilityIdentifier: spec.actionAccessibilityIdentifier,
                    action: action
                )
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, theme.spacing.xl)
        .padding(.vertical, theme.spacing.l)
    }
}

// MARK: - Capsule State Action Button

struct MoroStateActionButton: View {
    enum Style {
        case subtle
        case prominent
    }

    let title: String
    var style: Style = .subtle
    var systemImage: String? = nil
    var accessibilityIdentifier: String? = nil
    let action: () -> Void

    @Environment(\.moroTheme) private var theme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .moroScaledFont(size: 13, weight: .semibold)
                }
                Text(title)
                    .font(theme.typography.bodyStrong)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .frame(minWidth: 104, minHeight: 44)
            .background(Capsule().fill(backgroundColor))
            .overlay {
                if style == .subtle {
                    Capsule()
                        .strokeBorder(theme.colors.borderSubtle, lineWidth: 0.9)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(MoroCapsulePressStyle())
        .modifier(StateButtonAccessibilityIdentifier(id: accessibilityIdentifier))
    }

    private var foregroundColor: Color {
        switch style {
        case .subtle:
            return theme.colors.textPrimary
        case .prominent:
            return theme.colors.primaryForeground
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .subtle:
            return theme.colors.surfaceSubtle
        case .prominent:
            return theme.colors.primary500
        }
    }
}

struct MoroCapsulePressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct StateButtonAccessibilityIdentifier: ViewModifier {
    let id: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let id {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}
