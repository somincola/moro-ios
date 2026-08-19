//
//  InlineFeedbackCard.swift
//  moro
//
//  Inline feedback card used inside forms and multi-step flows.
//

import SwiftUI

struct InlineFeedbackCard: View {
    @Environment(\.moroTheme) private var theme

    let kind: AppFeedbackKind
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            Image(systemName: iconName)
                .foregroundStyle(tintColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.leading)

                if let actionTitle, let action {
                    Button(actionTitle, action: action)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.primary500)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(theme.spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.colors.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tintColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var iconName: String {
        switch kind {
        case .success:
            return "checkmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        case .info:
            return "info.circle.fill"
        }
    }

    private var tintColor: Color {
        switch kind {
        case .success:
            return theme.colors.success
        case .error:
            return theme.colors.error
        case .info:
            return theme.colors.primary500
        }
    }
}

