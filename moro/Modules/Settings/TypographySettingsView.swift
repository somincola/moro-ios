//
//  TypographySettingsView.swift
//  moro
//
//  In-app font-scale picker retained for possible future use.
//

import SwiftUI
import UIKit

/// Standalone font-scale section retained for possible future use. The scale stacks on top of
/// the system Dynamic Type setting. Every step is a free in-app font-scale option.
struct TypographySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme

    var body: some View {
        Section {
            ForEach(AppSettings.TypographyFontScale.allCases, id: \.rawValue) { scale in
                scaleRow(scale)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text(MoroL10n.AppSettings.typographySection)
                .moroScaledFont(size: 13, weight: .regular)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.none)
        } footer: {
            Text(MoroL10n.AppSettings.typographyFooter)
                .padding(.top, theme.spacing.xs)
        }
    }

    @ViewBuilder
    private func scaleRow(_ scale: AppSettings.TypographyFontScale) -> some View {
        let isSelected = settings.typographyFontScale == scale

        Button {
            handleScaleTap(scale)
        } label: {
            HStack(spacing: theme.spacing.m) {
                // Fixed-size "Aa" preview of the step (intentionally not re-scaled).
                Text(verbatim: "Aa")
                    .font(.system(size: 17 * scale.factor, weight: .semibold))
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(width: 36)

                Text(scale.title)
                    .font(theme.typography.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(theme.colors.textPrimary)

                Spacer()

                Text(verbatim: String(format: "%.2fx", scale.factor))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)

                trailingAccessory(isSelected: isSelected)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailingAccessory(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .moroScaledFont(size: 20, weight: .semibold)
                .foregroundStyle(theme.colors.primary500)
        }
    }

    private func handleScaleTap(_ scale: AppSettings.TypographyFontScale) {
        guard settings.typographyFontScale != scale else { return }
        settings.typographyFontScale = scale
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview {
    NavigationStack {
        List {
            TypographySettingsView()
        }
        .moroTheme(MoroTheme())
    }
}
