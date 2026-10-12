import SwiftUI
import UIKit

struct DisplaySettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var fontSizeStep: Double

    init() {
        _fontSizeStep = State(initialValue: Double(
            MoroPostFontSize.allCases.firstIndex(of: AppSettings.shared.postFontSize) ?? 1
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                appearanceSection
                fontSizeSection
                themeColorSection
                appIconLink
                Text(MoroL10n.Display.footer)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 560)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .background(theme.colors.surfaceBase)
        .navigationTitle(MoroL10n.Settings.appearanceDisplay)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: settings.themeColor)
        .sensoryFeedback(.selection, trigger: previewFontSize)
        .onChange(of: settings.postFontSize) { _, size in
            fontSizeStep = Double(MoroPostFontSize.allCases.firstIndex(of: size) ?? 1)
        }
    }

    private var appIconLink: some View {
        VStack(spacing: 12) {
            Divider().overlay(theme.colors.borderSubtle)
            NavigationLink {
                List { AppIconSettingsView() }
                    .moroSettingsListChrome()
                    .navigationTitle(MoroL10n.GeneralSettings.appIconSection)
                    .navigationBarTitleDisplayMode(.inline)
            } label: {
                HStack(spacing: 12) {
                    Text(MoroL10n.GeneralSettings.appIconSection)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer(minLength: 8)
                    Image(settings.appIcon.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .accessibilityHidden(true)
                    Image(systemName: "chevron.right")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroL10n.GeneralSettings.appIconSection)
            .accessibilityValue(settings.appIcon.title)
            .accessibilityIdentifier("settings.appIcon")
        }
    }

    private var fontSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(MoroL10n.Display.fontSize)
                    .font(theme.typography.subtitle)
                    .foregroundStyle(theme.colors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(previewFontSize.title)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            postPreview

            HStack(spacing: 12) {
                Text(verbatim: "Aa").moroScaledFont(size: 12)
                    .accessibilityHidden(true)
                VStack(spacing: 0) {
                    PostFontSizeSlider(
                        value: $fontSizeStep, tint: UIColor(theme.colors.themeTint),
                        onCommit: saveFontSize
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    HStack {
                        ForEach(Array(MoroPostFontSize.allCases.enumerated()), id: \.element) { index, size in
                            if index > 0 { Spacer() }
                            Circle()
                                .fill(size == previewFontSize ? theme.colors.textPrimary : theme.colors.textTertiary)
                                .frame(width: 4, height: 4)
                        }
                    }
                    .padding(.horizontal, 14)
                    .accessibilityHidden(true)
                }
                Text(verbatim: "Aa").moroScaledFont(size: 20)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.colors.textSecondary)

            Text(MoroL10n.Display.fontSizeHint)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var previewFontSize: MoroPostFontSize {
        let index = min(max(Int(fontSizeStep.rounded()), 0), MoroPostFontSize.allCases.count - 1)
        return MoroPostFontSize.allCases[index]
    }

    private func saveFontSize() {
        let size = previewFontSize
        if settings.postFontSize != size { settings.postFontSize = size }
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
            ZStack(alignment: .topLeading) {
                // Reserve the largest layout so wrapping cannot move the slider during a drag.
                previewText(font: theme.postUIFont(for: .extraLarge))
                    .hidden()
                    .accessibilityHidden(true)
                previewText(font: theme.postUIFont(for: previewFontSize))
            }
        }
        .padding(16)
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.colors.borderSubtle, lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("display.preview")
    }

    private func previewText(font bodyFont: UIFont) -> some View {
        let url = URL(string: "https://example.com")!
        return RichTextContentView(
            elements: [
                .text(MoroL10n.Display.previewLead),
                .mention(username: "@moro", url: url),
                .text(MoroL10n.Display.previewMiddle),
                .link(text: "example.com", url: url),
                .text(MoroL10n.Display.previewTail),
                .hashtag(tag: "#Moro", url: url),
            ],
            emojiSize: bodyFont.pointSize * 1.25,
            isSelectable: false,
            fontOverride: Font(bodyFont),
            uiFontOverride: bodyFont,
            lineSpacing: 4 * bodyFont.pointSize / 16,
            onLinkTap: { _ in }
        )
        .allowsHitTesting(false)
    }
}

// Observe touch release separately because iOS 26 Slider editing callbacks can stay active.
private struct PostFontSizeSlider: UIViewRepresentable {
    @Binding var value: Double
    let tint: UIColor
    let onCommit: () -> Void

    func makeUIView(context: Context) -> FontSizeSlider {
        let slider = FontSizeSlider()
        slider.minimumValue = 0
        slider.maximumValue = Float(MoroPostFontSize.allCases.count - 1)
        slider.accessibilityIdentifier = "display.font-size"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator, action: #selector(Coordinator.commit(_:)),
            for: .editingDidEnd
        )
        let tracking = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.released(_:)))
        tracking.minimumPressDuration = 0
        tracking.allowableMovement = .greatestFiniteMagnitude
        tracking.cancelsTouchesInView = false
        tracking.delegate = context.coordinator
        slider.addGestureRecognizer(tracking)
        return slider
    }

    func updateUIView(_ slider: FontSizeSlider, context: Context) {
        context.coordinator.parent = self
        slider.tintColor = tint
        slider.accessibilityLabel = MoroL10n.Display.fontSize
        let index = min(max(Int(value.rounded()), 0), MoroPostFontSize.allCases.count - 1)
        slider.accessibilityValue = MoroPostFontSize.allCases[index].title
        if slider.value != Float(value) {
            slider.setValue(Float(value), animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PostFontSizeSlider

        init(_ parent: PostFontSizeSlider) { self.parent = parent }

        @objc func changed(_ slider: UISlider) {
            parent.value = Double(slider.value)
        }

        @objc func released(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .ended || gesture.state == .cancelled,
                let slider = gesture.view as? UISlider
            else { return }
            // The native slider applies its final value later in the same touch event.
            DispatchQueue.main.async { [weak self, weak slider] in
                guard let self, let slider else { return }
                self.commit(slider)
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func commit(_ slider: UISlider) {
            let step = slider.value.rounded()
            slider.setValue(step, animated: !UIAccessibility.isReduceMotionEnabled)
            parent.value = Double(step)
            parent.onCommit()
        }
    }

    final class FontSizeSlider: UISlider {
        override func accessibilityIncrement() {
            value = min(value.rounded() + 1, maximumValue)
            sendActions(for: [.valueChanged, .editingDidEnd])
        }

        override func accessibilityDecrement() {
            value = max(value.rounded() - 1, minimumValue)
            sendActions(for: [.valueChanged, .editingDidEnd])
        }
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
