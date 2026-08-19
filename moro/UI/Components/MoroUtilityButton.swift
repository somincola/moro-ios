//
//  MoroUtilityButton.swift
//  moro
//
//  Shared utility icon button surface used by compose, detail, and inbox actions.
//

import SwiftUI

enum MoroUtilityButtonMetrics {
    static let visualSize: CGFloat = 34
    static let hitTargetSize: CGFloat = 44
    static let iconPointSize: CGFloat = 16
    static let cornerRadius: CGFloat = 17
}

struct MoroUtilityIconSurface<Accessory: View>: View {
    let systemImage: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    var activeColor: Color? = nil
    var inactiveColor: Color? = nil
    let accessory: Accessory

    @Environment(\.moroTheme) private var theme

    init(
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.accessory = accessory()
    }

    private var resolvedActiveColor: Color {
        activeColor ?? theme.colors.primary500
    }

    private var resolvedInactiveColor: Color {
        inactiveColor ?? theme.colors.textSecondary
    }

    private var foregroundColor: Color {
        if isDisabled {
            return theme.colors.textTertiary
        }
        return isActive ? resolvedActiveColor : resolvedInactiveColor
    }

    private var backgroundColor: Color {
        if isActive {
            return resolvedActiveColor.opacity(0.12)
        }
        return theme.colors.surfaceSubtle
    }

    private var borderColor: Color {
        if isActive {
            return resolvedActiveColor.opacity(0.26)
        }
        return theme.colors.borderSubtle
    }

    var body: some View {
        ZStack {
            ZStack {
                Circle()
                    .fill(backgroundColor)

                Circle()
                    .stroke(borderColor, lineWidth: 1)

                Image(systemName: systemImage)
                    .moroScaledFont(size: MoroUtilityButtonMetrics.iconPointSize, weight: .semibold)
                    .foregroundStyle(foregroundColor)

                accessory
            }
            .frame(
                width: MoroUtilityButtonMetrics.visualSize,
                height: MoroUtilityButtonMetrics.visualSize
            )
        }
        .frame(
            width: MoroUtilityButtonMetrics.hitTargetSize,
            height: MoroUtilityButtonMetrics.hitTargetSize
        )
        .opacity(isDisabled ? 0.72 : 1)
        .contentShape(Rectangle())
    }
}

extension MoroUtilityIconSurface where Accessory == EmptyView {
    init(
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil
    ) {
        self.init(
            systemImage: systemImage,
            isActive: isActive,
            isDisabled: isDisabled,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            accessory: { EmptyView() }
        )
    }
}

struct MoroUtilityIconButton<Accessory: View>: View {
    let systemImage: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    var activeColor: Color? = nil
    var inactiveColor: Color? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void
    let accessory: Accessory

    init(
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.systemImage = systemImage
        self.isActive = isActive
        self.isDisabled = isDisabled
        self.activeColor = activeColor
        self.inactiveColor = inactiveColor
        self.accessibilityLabel = accessibilityLabel
        self.action = action
        self.accessory = accessory()
    }

    var body: some View {
        Button(action: action) {
            MoroUtilityIconSurface(
                systemImage: systemImage,
                isActive: isActive,
                isDisabled: isDisabled,
                activeColor: activeColor,
                inactiveColor: inactiveColor
            ) {
                accessory
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .disabled(isDisabled)
        .accessibilityLabel(accessibilityLabel ?? systemImage)
    }
}

extension MoroUtilityIconButton where Accessory == EmptyView {
    init(
        systemImage: String,
        isActive: Bool = false,
        isDisabled: Bool = false,
        activeColor: Color? = nil,
        inactiveColor: Color? = nil,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.init(
            systemImage: systemImage,
            isActive: isActive,
            isDisabled: isDisabled,
            activeColor: activeColor,
            inactiveColor: inactiveColor,
            accessibilityLabel: accessibilityLabel,
            action: action,
            accessory: { EmptyView() }
        )
    }
}

enum MoroNavigationControlKind {
    case back
    case close
    case settings

    var systemImage: String {
        switch self {
        case .back:
            return "chevron.left"
        case .close:
            return "xmark"
        case .settings:
            return "gearshape.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .back:
            return MoroL10n.UtilityButton.back
        case .close:
            return MoroL10n.UtilityButton.close
        case .settings:
            return MoroL10n.UtilityButton.settings
        }
    }
}

struct MoroNavigationControlButton: View {
    let kind: MoroNavigationControlKind
    let action: () -> Void

    @Environment(\.moroTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: kind.systemImage)
                .moroScaledFont(size: 15, weight: .semibold)
                .foregroundStyle(theme.colors.textPrimary)
                .frame(
                    minWidth: MoroUtilityButtonMetrics.hitTargetSize,
                    minHeight: MoroUtilityButtonMetrics.hitTargetSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.accessibilityLabel)
    }
}

/// Floating chrome button for use over immersive banners or full-screen overlays.
/// Renders the kind's SF Symbol inside the same translucent scrim as
/// `FloatingNavIconLabel`, and inherits the kind's a11y label automatically.
struct MoroFloatingNavButton: View {
    let kind: MoroNavigationControlKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FloatingNavIconLabel(systemName: kind.systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(kind.accessibilityLabel)
    }
}
