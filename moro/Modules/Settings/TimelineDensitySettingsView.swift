//
//  TimelineDensitySettingsView.swift
//  moro
//
//  Timeline density picker retained for possible future use.
//

import SwiftUI
import UIKit

/// Standalone timeline density section retained for possible future use. Density drives the
/// timeline rows' line spacing, avatar size, and padding. Every density is a free option.
struct TimelineDensitySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme

    var body: some View {
        Section {
            ForEach(AppSettings.TimelineDensity.allCases, id: \.rawValue) { density in
                densityRow(density)
                    .listRowSeparator(.hidden)
            }
        } header: {
            Text(MoroL10n.AppSettings.densitySection)
                .moroScaledFont(size: 13, weight: .regular)
                .foregroundStyle(theme.colors.textTertiary)
                .textCase(.none)
        }
    }

    @ViewBuilder
    private func densityRow(_ density: AppSettings.TimelineDensity) -> some View {
        let isSelected = settings.timelineDensity == density

        Button {
            handleDensityTap(density)
        } label: {
            HStack(spacing: theme.spacing.m) {
                densityGlyph(density)

                VStack(alignment: .leading, spacing: 4) {
                    Text(density.title)
                        .font(theme.typography.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.colors.textPrimary)

                    Text(density.subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Spacer()

                trailingAccessory(isSelected: isSelected)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Schematic row-density glyph: three "rows" with tight or relaxed spacing.
    private func densityGlyph(_ density: AppSettings.TimelineDensity) -> some View {
        VStack(spacing: density == .compact ? 2 : 4) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(theme.colors.textTertiary)
                    .frame(width: 22, height: 3)
            }
        }
        .frame(width: 28, height: 24)
    }

    @ViewBuilder
    private func trailingAccessory(isSelected: Bool) -> some View {
        if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .moroScaledFont(size: 20, weight: .semibold)
                .foregroundStyle(theme.colors.primary500)
        }
    }

    private func handleDensityTap(_ density: AppSettings.TimelineDensity) {
        guard settings.timelineDensity != density else { return }
        settings.timelineDensity = density
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

#Preview {
    NavigationStack {
        List {
            TimelineDensitySettingsView()
        }
        .moroTheme(MoroTheme())
    }
}
