//
//  MoroSettingsSwitchStyle.swift
//  moro
//
//  Settings switch: system green or gray track with a white thumb.
//

import SwiftUI

struct MoroSettingsSwitchStyle: ToggleStyle {
    @Environment(\.moroTheme) private var theme
    /// Outside a List there are no row insets, so the control keeps a full 44pt frame.
    var standalone = false

    private enum Metrics {
        static let trackWidth: CGFloat = 50
        static let trackHeight: CGFloat = 30
        static let thumbSize: CGFloat = 24
        static let horizontalInset: CGFloat = 3
        static let hitSlop: CGFloat = (44 - trackHeight) / 2
    }

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.86)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                configuration.label
                    .foregroundStyle(theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 12)

                RoundedRectangle(
                    cornerRadius: Metrics.trackHeight / 2,
                    style: .continuous
                )
                .fill(Color(uiColor: configuration.isOn ? .systemGreen : .systemGray4))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: Metrics.thumbSize, height: Metrics.thumbSize)
                        .padding(.horizontal, Metrics.horizontalInset)
                        .shadow(color: .black.opacity(theme.colorScheme == .dark ? 0.28 : 0.12), radius: 6, y: 2)
                }
                .frame(width: Metrics.trackWidth, height: Metrics.trackHeight)
                .accessibilityHidden(true)
            }
            // Lay out at the track's height so switch rows share the list's
            // standard row height; the hit area still extends to a 44pt target.
            .frame(minHeight: Metrics.trackHeight)
            .padding(.vertical, Metrics.hitSlop)
            .contentShape(Rectangle())
            .padding(.vertical, standalone ? 0 : -Metrics.hitSlop)
        }
        .buttonStyle(.plain)
        // Default list insets: the label lines up with link and picker rows.
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? MoroL10n.SettingsSwitch.on : MoroL10n.SettingsSwitch.off)
    }
}

extension View {
    func moroSettingsSwitchStyle(standalone: Bool = false) -> some View {
        toggleStyle(MoroSettingsSwitchStyle(standalone: standalone))
    }
}
