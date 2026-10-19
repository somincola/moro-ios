//
//  NotificationToggleButton.swift
//  moro
//
//  Notification subscription toggle button for followed users.
//

import SwiftUI

struct NotificationToggleButton: View {
    let isNotifying: Bool
    let isLoading: Bool
    let isInteractionDisabled: Bool
    var onToggle: () -> Void
    
    @Environment(\.moroTheme) private var theme
    @State private var ringCount = 0

    /// The icon shows the current state, not the action: a quiet bell when new posts
    /// won't alert you, a ringing bell when they will. (A bell with a slash is already
    /// "mute this account", so it isn't used here.)
    static func systemImage(isNotifying: Bool) -> String {
        isNotifying ? "bell.and.waves.left.and.right.fill" : "bell"
    }

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Image(systemName: Self.systemImage(isNotifying: isNotifying))
                    .moroScaledFont(size: 17, weight: .medium)
                    .contentTransition(.symbolEffect(.replace))
                    // Turning alerts on rings the bell once.
                    .symbolEffect(.wiggle, options: .nonRepeating, value: ringCount)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(theme.colors.textPrimary)
                }
            }
            .foregroundStyle(theme.colors.textPrimary)
            .frame(width: 36, height: 36)
            .moroRelationshipControlSurface(.secondary, theme: theme)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isNotifying)
        .onChange(of: isNotifying) { _, isOn in
            if isOn { ringCount += 1 }
        }
        .disabled(isLoading || isInteractionDisabled)
        .animation(.easeInOut(duration: 0.16), value: isNotifying)
        .accessibilityLabel(
            isNotifying
                ? MoroL10n.Notifications.notificationToggleDisable
                : MoroL10n.Notifications.notificationToggleEnable
        )
        .accessibilityIdentifier("profile.notificationToggle")
    }
}
