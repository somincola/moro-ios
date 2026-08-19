//
//  MoroNoticePill.swift
//  moro
//
//  Monochrome transient notice shared by global and timeline feedback.
//

import SwiftUI

struct MoroNoticePill: View {
    let icon: String
    let text: String

    @Environment(\.moroTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: icon)
                .moroScaledFont(size: 13, weight: .semibold)

            Text(text)
                .font(theme.typography.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .foregroundStyle(Color.white)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 10, y: 3)
        .accessibilityElement(children: .combine)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? theme.colors.surfaceElevated : theme.colors.textPrimary
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06)
    }
}

#Preview {
    VStack(spacing: 16) {
        MoroNoticePill(icon: "checkmark", text: "Saved")
        MoroNoticePill(icon: "exclamationmark", text: "Could not complete the request")
    }
    .padding()
    .moroTheme(MoroTheme())
}
