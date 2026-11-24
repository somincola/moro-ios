//
//  MoroInlineNoticeBanner.swift
//  moro
//
//  Calm monochrome inline notice banner for refresh errors, offline cache hints,
//  and transient section-level messages with an optional capsule retry button.
//

import SwiftUI

struct MoroInlineNoticeBanner: View {
    enum Tone {
        case neutral
        case error
    }

    let message: String
    var tone: Tone = .neutral
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var isActionDisabled: Bool = false
    var messageAccessibilityIdentifier: String? = nil
    var actionAccessibilityIdentifier: String? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    messageRow
                    if let actionTitle, let action {
                        actionButton(title: actionTitle, action: action)
                    }
                }
            } else {
                HStack(spacing: theme.spacing.s) {
                    messageRow
                    Spacer(minLength: theme.spacing.xs)
                    if let actionTitle, let action {
                        actionButton(title: actionTitle, action: action)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, (actionTitle != nil && action != nil && !dynamicTypeSize.isAccessibilitySize) ? 4 : 11)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.colors.borderSubtle, lineWidth: 0.5)
        }
    }

    private var messageRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(tone == .error ? theme.colors.error.opacity(0.85) : theme.colors.textTertiary)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)

            Text(MoroErrorCopy.sanitized(message))
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(OptionalAccessibilityIdentifier(id: messageAccessibilityIdentifier))
        }
    }

    private func actionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(theme.colors.surfaceBase)
                )
                .overlay {
                    Capsule()
                        .strokeBorder(theme.colors.borderSubtle, lineWidth: 0.8)
                }
                .frame(minHeight: 45)
                .contentShape(Rectangle())
        }
        .buttonStyle(MoroCapsulePressStyle())
        .disabled(isActionDisabled)
        .opacity(isActionDisabled ? 0.5 : 1)
        .modifier(OptionalAccessibilityIdentifier(id: actionAccessibilityIdentifier))
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
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

#Preview {
    VStack(spacing: 12) {
        MoroInlineNoticeBanner(
            message: "Showing cached posts while offline.",
            tone: .neutral,
            actionTitle: "Retry",
            action: {}
        )
        MoroInlineNoticeBanner(
            message: "Could not refresh announcements right now.",
            tone: .error
        )
    }
    .padding()
    .moroTheme(MoroTheme())
}
