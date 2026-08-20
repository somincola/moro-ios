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

    static func systemImage(isNotifying: Bool) -> String {
        isNotifying ? "person.fill.xmark" : "person.fill.checkmark"
    }
    
    var body: some View {
        Button(action: onToggle) {
            ZStack {
                Image(systemName: Self.systemImage(isNotifying: isNotifying))
                    .moroScaledFont(size: 18, weight: .medium)
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
        .disabled(isLoading || isInteractionDisabled)
        .animation(.easeInOut(duration: 0.16), value: isNotifying)
        .accessibilityLabel(
            isNotifying
                ? MoroL10n.Notifications.notificationToggleDisable
                : MoroL10n.Notifications.notificationToggleEnable
        )
    }
}
