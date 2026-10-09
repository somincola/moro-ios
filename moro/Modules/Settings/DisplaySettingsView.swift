import SwiftUI
import UIKit

struct DisplaySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                appearanceSection
                themeColorSection
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.surfaceBase)
        .navigationTitle(MoroL10n.Display.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: settings.themeColor)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(MoroL10n.Settings.appearance)
                .font(theme.typography.subtitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("display.section.appearance")

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 12),
                    count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
                ),
                spacing: 12
            ) {
                ForEach(AppSettings.Appearance.allCases, id: \.rawValue) { appearance in
                    appearanceCard(appearance)
                }
            }
        }
    }

    private func appearanceCard(_ appearance: AppSettings.Appearance) -> some View {
        let selected = settings.appearance == appearance
        let icon: String = switch appearance {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
        return Button {
            settings.appearance = appearance
        } label: {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text(appearance.title)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? nil : 36)
            }
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 104)
            .background(selected ? theme.colors.surfaceSubtle : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? theme.colors.textPrimary : theme.colors.borderSubtle, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("display.appearance.\(appearance.rawValue)")
    }

    private var themeColorSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text(MoroL10n.Display.themeColor)
                    .font(theme.typography.subtitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("display.section.theme-color")
                Text(MoroL10n.Display.themeColorHint)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }

            postPreview

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    colorOptions
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 16
                ) {
                    colorOptions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if settings.themeColor == .custom {
                Text(MoroL10n.Display.customColorHint)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(MoroL10n.Display.footer)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var colorOptions: some View {
        ForEach(MoroThemeColor.allCases.filter { $0 != .custom }, id: \.rawValue) { color in
            colorButton(color)
        }
        ColorPicker(MoroL10n.Display.customColor, selection: customColor, supportsOpacity: false)
            .labelsHidden()
            .scaleEffect(44.0 / 28)
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if settings.themeColor == .custom {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .background(theme.colors.surfaceBase, in: Circle())
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityAddTraits(settings.themeColor == .custom ? .isSelected : [])
            .accessibilityIdentifier("display.color.custom")
    }

    private var customColor: Binding<Color> {
        Binding {
            Color(hex: settings.customThemeColor)
        } set: { color in
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            func byte(_ component: CGFloat) -> UInt32 {
                UInt32((min(max(component, 0), 1) * 255).rounded())
            }
            settings.customThemeColor = byte(red) << 16 | byte(green) << 8 | byte(blue)
            settings.themeColor = .custom
        }
    }

    private func colorButton(_ color: MoroThemeColor) -> some View {
        let selected = settings.themeColor == color
        let palette = MoroColors(
            colorScheme: theme.colorScheme, themeColor: color,
            colorSchemeContrast: theme.colorSchemeContrast
        )
        return Button {
            settings.themeColor = color
        } label: {
            Circle()
                .fill(palette.themeTint)
                .frame(width: 36, height: 36)
                .overlay {
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(palette.themeTintForeground)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("display.color.\(color.rawValue)")
    }

    private var postPreview: some View {
        // This fixed example is rendered locally; preview links never navigate.
        let url = URL(string: "https://example.com")!
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "person.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(theme.colors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Moro")
                        .font(theme.typography.bodyStrong)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(verbatim: "@moro@example.com")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            RichTextContentView(
                elements: [
                    .text(MoroL10n.Display.previewLead),
                    .mention(username: "@moro", url: url),
                    .text(MoroL10n.Display.previewMiddle),
                    .link(text: "example.com", url: url),
                    .text(MoroL10n.Display.previewTail),
                    .hashtag(tag: "#Moro", url: url),
                ],
                isSelectable: false,
                fontOverride: theme.typography.body,
                onLinkTap: { _ in }
            )
            .allowsHitTesting(false)
        }
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.colors.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("display.preview")
    }
}

#Preview("Display · Light") {
    NavigationStack {
        DisplaySettingsView()
            .moroTheme(MoroTheme())
    }
}

#Preview("Display · Dark / Large Text") {
    NavigationStack {
        DisplaySettingsView()
            .moroTheme(MoroTheme(colorScheme: .dark, dynamicTypeSize: .accessibility3))
            .dynamicTypeSize(.accessibility3)
    }
    .preferredColorScheme(.dark)
}
