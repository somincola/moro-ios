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
        MoroSettingsList {
            Section {
                appearanceTiles
                    .padding(.vertical, 6)
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Settings.appearance)
                    .accessibilityIdentifier("display.section.appearance")
            }

            Section {
                fontSizeControls
                    .padding(.vertical, 8)
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    MoroSettingsSectionHeader(title: MoroL10n.Display.fontSize)
                    Spacer(minLength: 8)
                    Text(previewFontSize.title)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .textCase(nil)
                }
            } footer: {
                Text(MoroL10n.Display.fontSizeHint)
            }

            Section {
                themeColorOptions
                    .padding(.vertical, 6)
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Display.themeColor)
                    .accessibilityIdentifier("display.section.theme-color")
            } footer: {
                Text(settings.themeColor == .custom
                    ? "\(MoroL10n.Display.themeColorHint)\n\(MoroL10n.Display.customColorHint)"
                    : MoroL10n.Display.themeColorHint)
            }

            Section {
                appIconLink
            } footer: {
                Text(MoroL10n.Display.footer)
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Settings.appearanceDisplay)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: settings.themeColor)
        .onChange(of: settings.postFontSize) { _, size in
            fontSizeStep = Double(MoroPostFontSize.allCases.firstIndex(of: size) ?? 1)
        }
    }

    private var appIconLink: some View {
        NavigationLink {
            MoroSettingsList { AppIconSettingsView() }
                .moroSettingsListChrome()
                .navigationTitle(MoroL10n.GeneralSettings.appIconSection)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 12) {
                Text(MoroL10n.GeneralSettings.appIconSection)
                    .foregroundStyle(theme.colors.textPrimary)
                Spacer(minLength: 8)
                Image(settings.appIcon.previewAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(MoroL10n.GeneralSettings.appIconSection)
        .accessibilityValue(settings.appIcon.title)
        .accessibilityIdentifier("settings.appIcon")
    }

    private var fontSizeControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            postPreview

            Rectangle()
                .fill(theme.colors.divider)
                .frame(height: 0.5)
                .accessibilityHidden(true)

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
                    .animation(.snappy(duration: 0.18), value: previewFontSize)
                    .accessibilityHidden(true)
                }
                Text(verbatim: "Aa").moroScaledFont(size: 20)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(theme.colors.textSecondary)
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

    private var appearanceTiles: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 10),
                count: dynamicTypeSize.isAccessibilitySize ? 1 : 3
            ),
            spacing: 10
        ) {
            ForEach(AppSettings.Appearance.allCases, id: \.rawValue) { appearance in
                appearanceCard(appearance)
            }
        }
    }

    private func appearanceCard(_ appearance: AppSettings.Appearance) -> some View {
        let selected = settings.appearance == appearance
        return Button {
            settings.appearance = appearance
        } label: {
            // A miniature of the app in that mode, with the name underneath, the way the
            // system's own appearance picker reads.
            VStack(spacing: 10) {
                AppearanceThumbnail(
                    appearance: appearance,
                    themeColor: settings.themeColor,
                    customThemeColor: settings.customThemeColor,
                    contrast: theme.colorSchemeContrast
                )
                .frame(maxWidth: .infinity)
                .frame(height: 76)
                .overlay {
                    RoundedRectangle(cornerRadius: AppearanceThumbnail.cornerRadius, style: .continuous)
                        .strokeBorder(theme.colors.borderSubtle, lineWidth: 0.5)
                }
                .overlay {
                    if selected {
                        // The same ring-with-a-gap the Me tab and account switcher use.
                        RoundedRectangle(cornerRadius: AppearanceThumbnail.cornerRadius + 4, style: .continuous)
                            .strokeBorder(theme.colors.textPrimary, lineWidth: 2)
                            .padding(-4)
                    }
                }
                .padding(4)

                Text(appearance.title)
                    .font(theme.typography.body)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? theme.colors.textPrimary : theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(.snappy(duration: 0.2), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(appearance.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("display.appearance.\(appearance.rawValue)")
    }

    private var themeColorOptions: some View {
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
            // Traits and identifier belong to the well alone; applied after the
            // overlay they would also expose the decorative checkmark to VoiceOver.
            .accessibilityAddTraits(settings.themeColor == .custom ? .isSelected : [])
            .accessibilityIdentifier("display.color.custom")
            .overlay(alignment: .topTrailing) {
                if settings.themeColor == .custom {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.colors.textPrimary)
                        .background(theme.colors.groupedSurface, in: Circle())
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }
            }
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
        // This fixed example is rendered locally; preview links never navigate. It sits
        // straight on the section's surface, like a post in the timeline, with no card
        // of its own, so the section doesn't read as a card inside a card.
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(settings.appIcon.previewAssetName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(theme.colors.borderSubtle, lineWidth: 0.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "Moro")
                        .font(theme.typography.bodyStrong)
                        .foregroundStyle(theme.colors.textPrimary)
                    Text(verbatim: "@moro@example.com")
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            ZStack(alignment: .topLeading) {
                // Reserve the tallest layout so wrapping cannot move the slider during a
                // drag. Every size is measured: a smaller font can wrap onto an extra line
                // and end up taller than the largest one.
                ForEach(MoroPostFontSize.allCases, id: \.self) { size in
                    previewText(font: theme.postUIFont(for: size))
                        .hidden()
                        .accessibilityHidden(true)
                }
                previewText(font: theme.postUIFont(for: previewFontSize))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Without a card behind it, the accessibility frame would shrink to the visible
        // text and change with every size. An imperceptible fill keeps the element's
        // frame equal to the reserved layout.
        .background(Color.primary.opacity(0.001))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Moro, @moro@example.com. " + [
            MoroL10n.Display.previewLead, "@moro", MoroL10n.Display.previewMiddle,
            "example.com", MoroL10n.Display.previewTail, "#Moro",
        ].joined()))
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

/// A four-detent slider: the thumb never rests between sizes. While dragging it
/// clicks from detent to detent with a light selection haptic, and release commits.
/// Touch release is observed separately because iOS 26 editing callbacks can stay active.
private struct PostFontSizeSlider: UIViewRepresentable {
    @Binding var value: Double
    let tint: UIColor
    let onCommit: () -> Void

    func makeUIView(context: Context) -> FontSizeSlider {
        let slider = FontSizeSlider()
        slider.minimumValue = 0
        slider.maximumValue = Float(MoroPostFontSize.allCases.count - 1)
        slider.value = Float(value.rounded())
        slider.accessibilityIdentifier = "display.font-size"
        slider.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .valueChanged)
        slider.addTarget(
            context.coordinator, action: #selector(Coordinator.commit(_:)),
            for: .editingDidEnd
        )
        let tracking = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tracked(_:)))
        tracking.minimumPressDuration = 0
        tracking.allowableMovement = .greatestFiniteMagnitude
        tracking.cancelsTouchesInView = false
        tracking.delegate = context.coordinator
        slider.addGestureRecognizer(tracking)
        context.coordinator.attach(to: slider)
        return slider
    }

    func updateUIView(_ slider: FontSizeSlider, context: Context) {
        context.coordinator.parent = self
        slider.tintColor = tint
        slider.accessibilityLabel = MoroL10n.Display.fontSize
        let step = Float(min(max(value.rounded(), 0), Double(MoroPostFontSize.allCases.count - 1)))
        slider.accessibilityValue = MoroPostFontSize.allCases[Int(step)].title
        context.coordinator.detent = step
        if slider.value != step {
            slider.setValue(step, animated: false)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        // UIKit bridge released with the view; keep teardown off the main-actor
        // executor (iOS 26.0–26.2 runtime crash, see docs/IOS26_DEINIT_COMPATIBILITY.md).
        nonisolated deinit {}
        var parent: PostFontSizeSlider
        /// The detent the thumb currently rests on.
        var detent: Float = 0
        private var feedback: UISelectionFeedbackGenerator?

        init(_ parent: PostFontSizeSlider) { self.parent = parent }

        func attach(to slider: UISlider) {
            detent = slider.value
            feedback = UISelectionFeedbackGenerator(view: slider)
        }

        @objc func changed(_ slider: UISlider) {
            let step = slider.value.rounded()
            guard step != detent else {
                // Hold the thumb on its detent; the finger has not reached the next one yet.
                slider.setValue(step, animated: false)
                return
            }
            detent = step
            // Glide the short distance to the new detent rather than teleporting.
            if UIAccessibility.isReduceMotionEnabled {
                slider.setValue(step, animated: false)
            } else {
                UIView.animate(
                    withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0,
                    options: [.beginFromCurrentState, .allowUserInteraction]
                ) {
                    slider.setValue(step, animated: false)
                    slider.layoutIfNeeded()
                }
            }
            if slider.isTracking || isTouching {
                feedback?.selectionChanged(at: thumbCenter(of: slider))
                feedback?.prepare()
            }
            parent.value = Double(step)
        }

        private var isTouching = false

        @objc func tracked(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                isTouching = true
                // Warm the Taptic Engine so the first detent clicks without latency.
                feedback?.prepare()
            case .ended, .cancelled, .failed:
                isTouching = false
                guard let slider = gesture.view as? UISlider else { return }
                // The native slider applies its final value later in the same touch event.
                DispatchQueue.main.async { [weak self, weak slider] in
                    guard let self, let slider else { return }
                    self.commit(slider)
                }
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func commit(_ slider: UISlider) {
            let step = slider.value.rounded()
            if slider.value != step {
                slider.setValue(step, animated: !UIAccessibility.isReduceMotionEnabled)
            }
            detent = step
            parent.value = Double(step)
            parent.onCommit()
        }

        private func thumbCenter(of slider: UISlider) -> CGPoint {
            let track = slider.trackRect(forBounds: slider.bounds)
            let thumb = slider.thumbRect(forBounds: slider.bounds, trackRect: track, value: slider.value)
            return CGPoint(x: thumb.midX, y: thumb.midY)
        }
    }

    final class FontSizeSlider: UISlider {
        nonisolated deinit {}

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

/// A miniature of a post in the given appearance. "System" shows light and dark split
/// on a diagonal.
private struct AppearanceThumbnail: View {
    static let cornerRadius: CGFloat = 12

    let appearance: AppSettings.Appearance
    let themeColor: MoroThemeColor
    let customThemeColor: UInt32
    let contrast: ColorSchemeContrast

    var body: some View {
        ZStack {
            switch appearance {
            case .light:
                mini(.light)
            case .dark:
                mini(.dark)
            case .system:
                mini(.light)
                mini(.dark).mask(DiagonalHalf())
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private func mini(_ scheme: ColorScheme) -> some View {
        let palette = MoroColors(
            colorScheme: scheme, themeColor: themeColor,
            customThemeColor: customThemeColor, colorSchemeContrast: contrast
        )
        return VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.themeTint)
                    .frame(width: 14, height: 14)
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(palette.textPrimary.opacity(0.85)).frame(width: 30, height: 4)
                    Capsule().fill(palette.textTertiary).frame(width: 20, height: 3)
                }
            }
            Capsule().fill(palette.textSecondary.opacity(0.45)).frame(height: 4)
            Capsule().fill(palette.textSecondary.opacity(0.45)).frame(width: 38, height: 4)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        // The grouped canvas, not the plain surface: a light thumbnail stays visible on
        // the white section it sits in.
        .background(palette.groupedBackground)
    }
}

/// The lower-right half of a rectangle, split on a gentle diagonal.
private struct DiagonalHalf: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
