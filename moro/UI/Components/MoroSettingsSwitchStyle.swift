//
//  MoroSettingsSwitchStyle.swift
//  moro
//
//  Settings-specific switch style aligned with the monochrome design system.
//

import SwiftUI

struct MoroSettingsSwitchStyle: ToggleStyle {
    @Environment(\.moroTheme) private var theme

    private enum Metrics {
        static let trackWidth: CGFloat = 50
        static let trackHeight: CGFloat = 30
        static let thumbSize: CGFloat = 24
        static let horizontalInset: CGFloat = 3
        static let minimumTapHeight: CGFloat = 44
        static let rowInsets = EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                RoundedRectangle(
                    cornerRadius: Metrics.trackHeight / 2,
                    style: .continuous
                )
                .fill(trackFillColor(isOn: configuration.isOn))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: Metrics.trackHeight / 2,
                        style: .continuous
                    )
                    .stroke(trackBorderColor(isOn: configuration.isOn), lineWidth: 1)
                }
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(thumbColor(isOn: configuration.isOn))
                        .frame(width: Metrics.thumbSize, height: Metrics.thumbSize)
                        .padding(.horizontal, Metrics.horizontalInset)
                        .shadow(color: .black.opacity(theme.colorScheme == .dark ? 0.28 : 0.12), radius: 6, y: 2)
                }
                .frame(width: Metrics.trackWidth, height: Metrics.trackHeight)
                .accessibilityHidden(true)
            }
            .frame(minHeight: Metrics.minimumTapHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Keep the full tap target without adding the list's default vertical padding again.
        .listRowInsets(Metrics.rowInsets)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? MoroL10n.SettingsSwitch.on : MoroL10n.SettingsSwitch.off)
        .opacity(configuration.isOn ? 1 : 0.96)
    }

    private func trackFillColor(isOn: Bool) -> Color {
        if isOn {
            return theme.colors.primary500
        }
        return theme.colorScheme == .dark ? Color(hex: 0x2A2D31) : Color(hex: 0xE7E8EB)
    }

    private func trackBorderColor(isOn: Bool) -> Color {
        if isOn {
            return theme.colors.primary500.opacity(theme.colorScheme == .dark ? 0.88 : 0.92)
        }
        return theme.colors.borderSubtle
    }

    private func thumbColor(isOn: Bool) -> Color {
        if isOn {
            return theme.colors.primaryForeground
        }
        return theme.colorScheme == .dark ? Color(hex: 0xF5F5F7) : .white
    }
}

extension View {
    func moroSettingsSwitchStyle() -> some View {
        toggleStyle(MoroSettingsSwitchStyle())
    }
}
