//
//  RichTextContentView.swift
//  moro
//
//  SwiftUI view for displaying rich text content with clickable links.
//  Supports mentions, hashtags, regular links, and custom emojis with proper styling.
//

import SwiftUI

private enum RichTextRenderBlock: Identifiable {
    case inline(id: Int, elements: [ContentElement])
    case code(id: Int, value: String)

    var id: Int {
        switch self {
        case .inline(let id, _), .code(let id, _):
            return id
        }
    }
}

/// Rich text content view with clickable links and custom emojis
struct RichTextContentView: View {
    let elements: [ContentElement]
    var onLinkTap: ((LinkAction) -> Void)? = nil
    var emojiSize: CGFloat = 20  // Default emoji size
    var isSelectable: Bool = true
    var fontOverride: Font? = nil
    var uiFontOverride: UIFont? = nil
    var textColorOverride: Color? = nil
    var linkColorOverride: Color? = nil
    var underlinesLinks: Bool = false
    var lineSpacing: CGFloat = 4
    /// Opt-in native spacing for the parser's double-break paragraph boundaries.
    var paragraphSpacing: CGFloat? = nil
    var lineLimit: Int? = nil
    var truncationMode: Text.TruncationMode = .tail
    var trailingSystemImage: String? = nil
    var trailingSystemImageColor: Color? = nil
    var trailingSystemImageSize: CGFloat = 11

    @Environment(\.moroTheme) private var theme
    @Environment(\.openURL) private var openURL
    @Environment(\.appRouter) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        html: String,
        mentions: [Status.Mention]? = nil,
        tags: [Status.Tag]? = nil,
        emojis: [Status.Emoji]? = nil,
        parsingOptions: ContentParsingOptions = [],
        emojiSize: CGFloat = 20,
        isSelectable: Bool = true,
        fontOverride: Font? = nil,
        uiFontOverride: UIFont? = nil,
        textColorOverride: Color? = nil,
        linkColorOverride: Color? = nil,
        underlinesLinks: Bool = false,
        lineSpacing: CGFloat = 4,
        paragraphSpacing: CGFloat? = nil,
        lineLimit: Int? = nil,
        truncationMode: Text.TruncationMode = .tail,
        trailingSystemImage: String? = nil,
        trailingSystemImageColor: Color? = nil,
        trailingSystemImageSize: CGFloat = 11,
        onLinkTap: ((LinkAction) -> Void)? = nil
    ) {
        self.elements = ContentParser.parseToElements(
            html: html,
            mentions: mentions,
            tags: tags,
            emojis: emojis,
            options: parsingOptions
        )
        self.emojiSize = emojiSize
        self.isSelectable = isSelectable
        self.fontOverride = fontOverride
        self.uiFontOverride = uiFontOverride
        self.textColorOverride = textColorOverride
        self.linkColorOverride = linkColorOverride
        self.underlinesLinks = underlinesLinks
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.lineLimit = lineLimit
        self.truncationMode = truncationMode
        self.trailingSystemImage = trailingSystemImage
        self.trailingSystemImageColor = trailingSystemImageColor
        self.trailingSystemImageSize = trailingSystemImageSize
        self.onLinkTap = onLinkTap
    }

    init(
        elements: [ContentElement], emojiSize: CGFloat = 18,
        isSelectable: Bool = true,
        fontOverride: Font? = nil,
        uiFontOverride: UIFont? = nil,
        textColorOverride: Color? = nil,
        linkColorOverride: Color? = nil,
        underlinesLinks: Bool = false,
        lineSpacing: CGFloat = 4,
        paragraphSpacing: CGFloat? = nil,
        lineLimit: Int? = nil,
        truncationMode: Text.TruncationMode = .tail,
        trailingSystemImage: String? = nil,
        trailingSystemImageColor: Color? = nil,
        trailingSystemImageSize: CGFloat = 11,
        onLinkTap: ((LinkAction) -> Void)? = nil
    ) {
        self.elements = elements
        self.emojiSize = emojiSize
        self.isSelectable = isSelectable
        self.fontOverride = fontOverride
        self.uiFontOverride = uiFontOverride
        self.textColorOverride = textColorOverride
        self.linkColorOverride = linkColorOverride
        self.underlinesLinks = underlinesLinks
        self.lineSpacing = lineSpacing
        self.paragraphSpacing = paragraphSpacing
        self.lineLimit = lineLimit
        self.truncationMode = truncationMode
        self.trailingSystemImage = trailingSystemImage
        self.trailingSystemImageColor = trailingSystemImageColor
        self.trailingSystemImageSize = trailingSystemImageSize
        self.onLinkTap = onLinkTap
    }

    @ViewBuilder
    var body: some View {
        if !elements.isEmpty {
            if elements.contains(where: { element in
                if case .codeBlock = element { return true }
                return false
            }) {
                buildBlockView()
            } else {
                buildInterleavedView(elements: elements, showsTrailingSystemImage: true)
            }
        }
    }

    @ViewBuilder
    private func buildBlockView() -> some View {
        let blocks = renderBlocks

        VStack(alignment: .leading, spacing: theme.spacing.s) {
            ForEach(blocks) { block in
                switch block {
                case .inline(let id, let inlineElements):
                    buildInterleavedView(
                        elements: inlineElements,
                        showsTrailingSystemImage: id == blocks.last?.id
                    )
                case .code(_, let code):
                    codeBlockView(code)
                }
            }

            if case .code = blocks.last, let trailingSystemImage {
                Image(systemName: trailingSystemImage)
                    .font(.system(size: trailingSystemImageSize, weight: .semibold))
                    .foregroundStyle(resolvedTrailingSystemImageColor)
                    .fixedSize()
            }
        }
        .font(resolvedFont)
        .foregroundStyle(resolvedTextColor)
        .lineSpacing(lineSpacing)
        .lineLimit(lineLimit)
        .truncationMode(truncationMode)
        .tint(resolvedLinkColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(
            \.openURL,
            OpenURLAction { url in
                handleURL(url)
                return .handled
            }
        )
    }

    @ViewBuilder
    private func codeBlockView(_ code: String) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Group {
                if isSelectable {
                    Text(code)
                        .textSelection(.enabled)
                } else {
                    Text(code)
                }
            }
                .font(
                    .system(
                        size: max(13, resolvedUIFont.pointSize * 0.94),
                        weight: .regular,
                        design: .monospaced
                    )
                )
                .foregroundStyle(resolvedTextColor)
                .lineSpacing(2)
                .lineLimit(nil)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.colors.surfaceSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(theme.colors.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var renderBlocks: [RichTextRenderBlock] {
        var blocks: [RichTextRenderBlock] = []
        var inlineElements: [ContentElement] = []

        func flushInlineElements() {
            guard !inlineElements.isEmpty else { return }
            blocks.append(.inline(id: blocks.count, elements: inlineElements))
            inlineElements.removeAll(keepingCapacity: true)
        }

        for element in elements {
            if case .codeBlock(let code) = element {
                flushInlineElements()
                blocks.append(.code(id: blocks.count, value: code))
            } else {
                inlineElements.append(element)
            }
        }
        flushInlineElements()

        return blocks
    }

    @ViewBuilder
    private func buildInterleavedView(
        elements: [ContentElement],
        showsTrailingSystemImage: Bool
    ) -> some View {
        let trailingIcon = showsTrailingSystemImage ? trailingSystemImage : nil
        let hasEmojis = elements.contains {
            if case .emoji = $0 { return true }
            return false
        }

        Group {
            // Bios with paragraph spacing keep the TextKit view (and its text selection).
            // Everything else — post bodies included — stays plain SwiftUI `Text`, with
            // custom emoji drawn inline.
            if paragraphSpacing != nil {
                MixedTextEmojiView(
                    elements: elements,
                    emojiSize: emojiSize,
                    textColor: UIColor(resolvedTextColor),
                    linkColor: UIColor(resolvedLinkColor),
                    codeBackgroundColor: UIColor(theme.colors.surfaceSubtle),
                    underlinesLinks: underlinesLinks,
                    font: resolvedUIFont,
                    lineSpacing: lineSpacing,
                    paragraphSpacing: paragraphSpacing,
                    lineLimit: lineLimit,
                    lineBreakMode: resolvedLineBreakMode,
                    isSelectable: isSelectable,
                    trailingSystemImage: trailingIcon,
                    trailingSystemImageColor: UIColor(resolvedTrailingSystemImageColor),
                    trailingSystemImageSize: trailingSystemImageSize,
                    onOpenURL: handleURL
                )
            } else if hasEmojis {
                InlineEmojiText(
                    runs: InlineTextRunBuilder.runs(for: elements, style: inlineTextStyle),
                    emojiSize: emojiSize,
                    trailingSystemImage: trailingIcon,
                    trailingSystemImageColor: resolvedTrailingSystemImageColor,
                    trailingSystemImageSize: trailingSystemImageSize
                )
            } else if let trailingIcon {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(buildAttributedStringForTextOnly(elements: elements))
                    Image(systemName: trailingIcon)
                        .font(.system(size: trailingSystemImageSize, weight: .semibold))
                        .foregroundStyle(resolvedTrailingSystemImageColor)
                        .fixedSize()
                }
            } else {
                Text(buildAttributedStringForTextOnly(elements: elements))
            }
        }
                .font(resolvedFont)
                .foregroundStyle(resolvedTextColor)
                .lineSpacing(lineSpacing)
                .lineLimit(lineLimit)
                .truncationMode(truncationMode)
                .tint(resolvedLinkColor)
                .frame(maxWidth: .infinity, alignment: .leading)  // Ensure text doesn't exceed container width
                .environment(
                    \.openURL,
                    OpenURLAction { url in
                        handleURL(url)
                        return .handled
                    })
    }

    private var resolvedFont: Font {
        fontOverride ?? theme.typography.body
    }

    private var resolvedUIFont: UIFont {
        if let uiFontOverride { return uiFontOverride }
        return UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(
                ofSize: 15,
                weight: .regular
            ),
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        )
    }

    private var resolvedTextColor: Color {
        textColorOverride ?? theme.colors.textPrimary
    }

    private var resolvedLinkColor: Color {
        linkColorOverride ?? theme.colors.contentLink
    }

    private var resolvedTrailingSystemImageColor: Color {
        trailingSystemImageColor ?? resolvedTextColor
    }

    private var resolvedLineBreakMode: NSLineBreakMode {
        guard lineLimit != 1 else {
            switch truncationMode {
            case .head:
                return .byTruncatingHead
            case .middle:
                return .byTruncatingMiddle
            case .tail:
                return .byTruncatingTail
            @unknown default:
                return .byTruncatingTail
            }
        }
        return .byWordWrapping
    }

    private var inlineTextStyle: InlineTextStyle {
        InlineTextStyle(
            textColor: resolvedTextColor,
            linkColor: resolvedLinkColor,
            codeBackgroundColor: theme.colors.surfaceSubtle,
            codeFontSize: resolvedUIFont.pointSize,
            underlinesLinks: underlinesLinks
        )
    }

    private func buildAttributedStringForTextOnly(
        elements: [ContentElement]
    ) -> AttributedString {
        InlineTextRunBuilder.flattened(
            InlineTextRunBuilder.runs(for: elements, style: inlineTextStyle)
        )
    }

    private func handleURL(_ url: URL) {
        let action = linkAction(for: url)
        if let onLinkTap {
            onLinkTap(action)
        } else {
            URLHandler.shared.handleLinkAction(action, router: router, systemOpenURL: openURL)
        }
    }

    func linkAction(for url: URL) -> LinkAction {
        for element in elements {
            switch element {
            case .mention(let username, let target) where target == url:
                return .mention(
                    username: username.hasPrefix("@") ? String(username.dropFirst()) : username,
                    url: url
                )
            case .hashtag(let tag, let target) where target == url:
                return .hashtag(tag: tag.hasPrefix("#") ? String(tag.dropFirst()) : tag, url: url)
            case .link(_, let target) where target == url:
                return .link(url: url)
            default:
                continue
            }
        }

        return .link(url: url)
    }
}

// MARK: - Static Inline Emoji Support

/// Custom UITextView that properly calculates intrinsic content size
private class AutoHeightTextView: UITextView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    // Named to avoid colliding with UITextView's own `layoutManager` property.
    private let textKitLayoutManager = NSLayoutManager()

    init() {
        let textStorage = NSTextStorage()
        let textContainer = NSTextContainer(
            size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textKitLayoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(textKitLayoutManager)

        super.init(frame: .zero, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        // Ensure text container width matches bounds width
        if bounds.width > 0 && abs(textContainer.size.width - bounds.width) > 1 {
            textContainer.size = CGSize(
                width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
        }

        // Calculate size based on attributed text
        let width = bounds.width > 0 ? bounds.width : textContainer.size.width

        guard width > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 0)
        }

        // Use sizeThatFits to calculate the required height
        let size = sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))

        // Return intrinsic size with no width constraint (let SwiftUI handle width)
        return CGSize(width: UIView.noIntrinsicMetric, height: max(size.height, 0))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Intrinsic height depends only on width, and `bounds.didSet` already
        // invalidates the intrinsic size when the width changes. Invalidating here on
        // every layout pass re-triggered a measure → layout cycle that kept the main
        // thread busy and never settled (a primary cause of the runaway layout loop).
    }

    override var bounds: CGRect {
        didSet {
            // Update text container width when bounds change
            if bounds.width != oldValue.width && bounds.width > 0 {
                textContainer.size = CGSize(
                    width: bounds.width, height: CGFloat.greatestFiniteMagnitude)
                invalidateIntrinsicContentSize()
            }
        }
    }
}

extension UIColor {
    /// Resolved RGBA components for value-based equality. Two `UIColor(SwiftUI.Color)`
    /// instances are not reliably `isEqual:` even when visually identical, so any Equatable
    /// gate must compare resolved components rather than the instances themselves.
    var moroRGBAComponents: [CGFloat] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard getRed(&r, green: &g, blue: &b, alpha: &a) else { return [-1, -1, -1, -1] }
        return [r, g, b, a]
    }
}

/// View that combines text and emoji images inline using UITextView
struct MixedTextEmojiView: UIViewRepresentable {
    let elements: [ContentElement]
    let emojiSize: CGFloat
    let textColor: UIColor
    let linkColor: UIColor
    let codeBackgroundColor: UIColor
    var underlinesLinks: Bool = false
    var font: UIFont = .systemFont(ofSize: 16)
    var lineSpacing: CGFloat = 4
    var paragraphSpacing: CGFloat? = nil
    var lineLimit: Int? = nil
    var lineBreakMode: NSLineBreakMode = .byCharWrapping
    var isSelectable: Bool = true
    var trailingSystemImage: String? = nil
    var trailingSystemImageColor: UIColor = .label
    var trailingSystemImageSize: CGFloat = 11
    var onOpenURL: ((URL) -> Void)? = nil

    private var allowsInteraction: Bool {
        // UITextView requires selection to be enabled for native link interaction.
        isSelectable || elements.contains {
            switch $0 {
            case .link, .mention, .hashtag: return true
            default: return false
            }
        }
    }

    /// TextKit applies a truncating paragraph line-break mode to every line, which squeezes
    /// a paragraph onto one line. When more than one line is allowed the paragraphs wrap,
    /// and the text container (`lineBreakMode`, `maximumNumberOfLines`) truncates the last one.
    var paragraphLineBreakMode: NSLineBreakMode {
        guard lineLimit != 1 else { return lineBreakMode }
        switch lineBreakMode {
        case .byTruncatingHead, .byTruncatingMiddle, .byTruncatingTail:
            return .byWordWrapping
        default:
            return lineBreakMode
        }
    }

    private var resolvedLinkTextAttributes: [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: linkColor
        ]
        if underlinesLinks {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    static func makeStaticEmojiAttachment(
        image: UIImage,
        emojiSize: CGFloat
    ) -> NSTextAttachment {
        makeEmojiAttachment(
            displayImage: image.aspectFittedCanvas(size: CGSize(width: emojiSize, height: emojiSize)),
            emojiSize: emojiSize
        )
    }

    /// `displayImage` is already drawn at `emojiSize` (a scaled emoji or a placeholder).
    /// Both use the same bounds, so swapping one for the other never moves the text.
    static func makeEmojiAttachment(displayImage: UIImage, emojiSize: CGFloat) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = displayImage
        attachment.bounds = CGRect(
            x: 0,
            y: -emojiSize * 0.08,
            width: emojiSize,
            height: emojiSize
        )
        return attachment
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = AutoHeightTextView()
        textView.isEditable = false
        textView.isSelectable = allowsInteraction
        textView.isUserInteractionEnabled = allowsInteraction
        textView.isScrollEnabled = false  // Disable scrolling to enable dynamic height
        textView.backgroundColor = .clear
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = .zero
        textView.textContainer.widthTracksTextView = true  // Track textView width
        textView.textContainer.maximumNumberOfLines = max(0, lineLimit ?? 0)
        textView.textContainer.lineBreakMode = lineBreakMode
        textView.textColor = textColor
        textView.font = font
        textView.linkTextAttributes = resolvedLinkTextAttributes
        textView.delegate = context.coordinator

        // Set priorities for proper layout
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.setContentHuggingPriority(.defaultLow, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.onOpenURL = onOpenURL
        textView.isSelectable = allowsInteraction
        textView.isUserInteractionEnabled = allowsInteraction
        textView.textColor = textColor
        textView.font = font
        textView.linkTextAttributes = resolvedLinkTextAttributes
        textView.textContainer.maximumNumberOfLines = max(0, lineLimit ?? 0)
        textView.textContainer.lineBreakMode = lineBreakMode

        let width = textView.bounds.width
        // Use a fallback width when bounds aren't laid out yet so emoji loading isn't skipped;
        // re-layouts below once the real width is known. Derive it from the view's own window
        // scene — UIScreen.main is deprecated and reports the wrong screen under Split View.
        let fallbackWidth = textView.window?.windowScene?.screen.bounds.width ?? 320
        let effectiveWidth = width > 0 ? width : min(280, fallbackWidth - 32)

        // Only rebuild the attributed string when something that affects it actually
        // changed. The previous unconditional rebuild + invalidate on every SwiftUI
        // update was a primary driver of the runaway layout loop.
        let inputs = buildInputs(width: effectiveWidth)
        if context.coordinator.lastBuildInputs != inputs {
            context.coordinator.lastBuildInputs = inputs
            updateTextContainerAndContent(textView: textView, width: effectiveWidth, context: context)
        }

        if width <= 0 {
            DispatchQueue.main.async {
                let finalWidth = textView.bounds.width
                if finalWidth > 0 && abs(finalWidth - effectiveWidth) > 1 {
                    context.coordinator.lastBuildInputs = self.buildInputs(width: finalWidth)
                    self.updateTextContainerAndContent(
                        textView: textView, width: finalWidth, context: context)
                }
            }
        }
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }

        if abs(uiView.textContainer.size.width - width) > 0.5 {
            uiView.textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }

        let fittingSize = uiView.sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: width, height: max(ceil(fittingSize.height), 1))
    }

    private func updateTextContainerAndContent(
        textView: UITextView, width: CGFloat, context: Context
    ) {
        // Update text container size to match available width (height is unlimited)
        textView.textContainer.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)

        let render: ([URL: UIImage]) -> Void = { [
            weak textView,
            weak coordinator = context.coordinator,
            textColor = self.textColor,
            linkColor = self.linkColor,
            codeBackgroundColor = self.codeBackgroundColor,
            underlinesLinks = self.underlinesLinks
        ] emojiAssets in
            guard let textView else { return }
            let attributedString = self.buildAttributedString(
                emojiAssets: emojiAssets,
                textColor: textColor,
                linkColor: linkColor,
                codeBackgroundColor: codeBackgroundColor,
                underlinesLinks: underlinesLinks,
                pendingEmojiURLs: coordinator?.pendingEmojiURLs ?? []
            )
            textView.attributedText = attributedString

            // Force layout to calculate the correct height
            textView.layoutIfNeeded()

            // Ask SwiftUI to measure again. A finished emoji download replaces a same-size
            // placeholder, so when the height is unchanged that relayout is skipped.
            let measuringWidth = textView.bounds.width > 0 ? textView.bounds.width : width
            let height = ceil(textView.sizeThatFits(
                CGSize(width: measuringWidth, height: CGFloat.greatestFiniteMagnitude)
            ).height)
            let heightUnchanged = coordinator?.lastReportedHeight.map { abs($0 - height) < 0.5 } ?? false
            coordinator?.lastReportedHeight = height
            if !(coordinator?.isDeliveringLoadedEmoji == true && heightUnchanged) {
                textView.invalidateIntrinsicContentSize()
            }

            // Ensure the text container width matches the textView width
            DispatchQueue.main.async {
                let currentWidth = textView.bounds.width > 0 ? textView.bounds.width : width
                if abs(textView.textContainer.size.width - currentWidth) > 1 {
                    textView.textContainer.size = CGSize(
                        width: currentWidth, height: CGFloat.greatestFiniteMagnitude)
                    textView.layoutIfNeeded()
                    textView.invalidateIntrinsicContentSize()
                }
            }
        }
        // Text is available now. A slow or unavailable emoji host must never
        // leave the entire post body blank until its image requests finish.
        context.coordinator.loadEmojiAssets(
            elements: elements, emojiSize: emojiSize,
            initial: render, completion: render
        )
    }

    /// Everything that affects the rendered attributed string. updateUIView skips the
    /// expensive rebuild when this is unchanged.
    struct BuildInputs: Equatable {
        let elements: [ContentElement]
        let width: CGFloat
        let emojiSize: CGFloat
        // Compared by resolved RGBA, NOT by UIColor instance: every SwiftUI render builds a
        // fresh `UIColor(SwiftUI.Color)`, and two such instances are not reliably `isEqual:`
        // (especially dynamic colors). Keying the gate on the instance made it always differ
        // → the text view rebuilt + invalidated on every update, defeating the gate entirely.
        let textColorRGBA: [CGFloat]
        let linkColorRGBA: [CGFloat]
        let codeBackgroundColorRGBA: [CGFloat]
        let underlinesLinks: Bool
        let lineLimit: Int
        let lineSpacing: CGFloat
        let paragraphSpacing: CGFloat?
        let font: UIFont
        let trailingSystemImage: String?
        let trailingSystemImageColorRGBA: [CGFloat]
        let trailingSystemImageSize: CGFloat
    }

    private func buildInputs(width: CGFloat) -> BuildInputs {
        BuildInputs(
            elements: elements, width: width, emojiSize: emojiSize,
            textColorRGBA: textColor.moroRGBAComponents,
            linkColorRGBA: linkColor.moroRGBAComponents,
            codeBackgroundColorRGBA: codeBackgroundColor.moroRGBAComponents,
            underlinesLinks: underlinesLinks,
            lineLimit: max(0, lineLimit ?? 0), lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing, font: font,
            trailingSystemImage: trailingSystemImage,
            trailingSystemImageColorRGBA: trailingSystemImageColor.moroRGBAComponents,
            trailingSystemImageSize: trailingSystemImageSize)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenURL: onOpenURL)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        typealias EmojiDataLoader = @Sendable (URL) async -> Data?

        var onOpenURL: ((URL) -> Void)?
        private let emojiDataLoader: EmojiDataLoader?
        private var emojiLoadTasks: [URL: Task<Data?, Never>] = [:]
        private var emojiLoadGeneration: Int = 0
        /// Inputs of the last attributed-string build, so updateUIView can skip the
        /// (expensive) rebuild + invalidate when nothing relevant changed.
        var lastBuildInputs: MixedTextEmojiView.BuildInputs?
        /// Emoji still downloading. The renderer reserves their space with a placeholder.
        private(set) var pendingEmojiURLs: Set<URL> = []
        /// True only while a finished download is being applied — the one update that
        /// happens outside SwiftUI's own layout pass.
        private(set) var isDeliveringLoadedEmoji = false
        /// Height last handed to SwiftUI, so a finished download that doesn't change the
        /// height doesn't ask SwiftUI to lay the row out again.
        var lastReportedHeight: CGFloat?

        override init() {
            self.onOpenURL = nil
            self.emojiDataLoader = nil
            super.init()
        }

        init(emojiDataLoader: @escaping EmojiDataLoader) {
            self.onOpenURL = nil
            self.emojiDataLoader = emojiDataLoader
            super.init()
        }

        init(onOpenURL: ((URL) -> Void)?) {
            self.onOpenURL = onOpenURL
            self.emojiDataLoader = nil
            super.init()
        }

        init(emojiDataLoader: @escaping EmojiDataLoader, onOpenURL: ((URL) -> Void)?) {
            self.onOpenURL = onOpenURL
            self.emojiDataLoader = emojiDataLoader
            super.init()
        }

        deinit {
            emojiLoadTasks.values.forEach { $0.cancel() }
        }

        func loadEmojiAssets(
            elements: [ContentElement], emojiSize: CGFloat,
            initial: (([URL: UIImage]) -> Void)? = nil,
            completion: @escaping ([URL: UIImage]) -> Void
        ) {
            _ = emojiSize
            emojiLoadGeneration += 1
            let generation = emojiLoadGeneration
            emojiLoadTasks.values.forEach { $0.cancel() }
            emojiLoadTasks.removeAll()
            pendingEmojiURLs = []

            var seenURLs = Set<URL>()
            var emojiURLs: [URL] = []
            for element in elements {
                if case .emoji(_, _, let staticURL) = element {
                    // Always the static URL — in-text emoji render as static images.
                    if seenURLs.insert(staticURL).inserted {
                        emojiURLs.append(staticURL)
                    }
                }
            }

            guard !emojiURLs.isEmpty else {
                completion([:])
                return
            }

            // Download the emoji as static UIImages for NSTextAttachment rendering. (There is
            // no animated path: a per-emoji SDAnimatedImageView per cell, unbounded by cell
            // reuse in a SwiftUI list, kept main-thread CADisplayLinks running and froze the UI.)
            var assets: [URL: UIImage] = [:]
            var missingURLs: [URL] = []
            for emojiURL in emojiURLs {
                if let cachedImage = InlineEmojiRendering.cachedImage(for: emojiURL) {
                    assets[emojiURL] = cachedImage
                } else {
                    missingURLs.append(emojiURL)
                }
            }

            guard !missingURLs.isEmpty else {
                completion(assets)
                return
            }

            // Populate the UITextView synchronously: cached images now, and a same-size
            // placeholder for each emoji still loading. Completion swaps in the images.
            pendingEmojiURLs = Set(missingURLs)
            initial?(assets)

            let emojiDataLoader = self.emojiDataLoader
            for emojiURL in missingURLs {
                if let emojiDataLoader {
                    emojiLoadTasks[emojiURL] = Task(priority: .utility) {
                        await emojiDataLoader(emojiURL)
                    }
                } else {
                    emojiLoadTasks[emojiURL] = Task(priority: .utility) {
                        await Self.defaultEmojiDataLoader(emojiURL)
                    }
                }
            }

            let taskSnapshot = emojiLoadTasks
            Task { [weak self] in
                guard let self else { return }

                for (emojiURL, task) in taskSnapshot {
                    guard !Task.isCancelled else { return }
                    guard generation == self.emojiLoadGeneration else { return }
                    guard let data = await task.value,
                          let image = UIImage(data: data) else {
                        continue
                    }
                    InlineEmojiRendering.store(image, for: emojiURL)
                    assets[emojiURL] = image
                }

                // The completion mutates the UITextView (attributedText/layout/invalidate),
                // which is main-thread-only — this Task is not main-isolated, so hop first.
                await MainActor.run {
                    guard generation == self.emojiLoadGeneration else { return }
                    self.emojiLoadTasks.removeAll()
                    self.pendingEmojiURLs = []
                    self.isDeliveringLoadedEmoji = true
                    defer { self.isDeliveringLoadedEmoji = false }
                    completion(assets)
                }
            }
        }

        nonisolated private static func defaultEmojiDataLoader(_ url: URL) async -> Data? {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .returnCacheDataElseLoad
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard !Task.isCancelled else { return nil }
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }

        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange
        ) -> Bool {
            if let onOpenURL {
                onOpenURL(url)
                return false
            }
            return true
        }
    }

    func buildAttributedString(
        emojiAssets: [URL: UIImage],
        textColor: UIColor,
        linkColor: UIColor,
        codeBackgroundColor: UIColor,
        underlinesLinks: Bool,
        pendingEmojiURLs: Set<URL> = []
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.lineBreakMode = paragraphLineBreakMode
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]
        var linkAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: linkColor,
            .paragraphStyle: paragraphStyle,
        ]
        if underlinesLinks {
            linkAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        var codeAttributes = baseAttributes
        codeAttributes[.font] = UIFont.monospacedSystemFont(
            ofSize: font.pointSize,
            weight: .regular
        )
        codeAttributes[.backgroundColor] = codeBackgroundColor

        var paragraphStart = 0
        for (index, element) in elements.enumerated() {
            switch element {
            case .text(let text):
                result.append(
                    NSAttributedString(
                        string: text,
                        attributes: baseAttributes
                    )
                )

            case .link(let text, let url):
                let linkAttr = NSMutableAttributedString(
                    string: text,
                    attributes: linkAttributes
                )
                linkAttr.addAttribute(
                    .link, value: url, range: NSRange(location: 0, length: linkAttr.length))
                result.append(linkAttr)

            case .mention(let username, let url):
                let mentionAttr = NSMutableAttributedString(
                    string: username,
                    attributes: linkAttributes
                )
                mentionAttr.addAttribute(
                    .link, value: url, range: NSRange(location: 0, length: mentionAttr.length))
                result.append(mentionAttr)

            case .hashtag(let tag, let url):
                let tagAttr = NSMutableAttributedString(
                    string: tag,
                    attributes: linkAttributes
                )
                tagAttr.addAttribute(
                    .link, value: url, range: NSRange(location: 0, length: tagAttr.length))
                result.append(tagAttr)

            case .emoji(let shortcode, _, let staticURL):
                // Keep one space between the emoji and the text in front of it.
                if elements.emojiNeedsSpace(before: index) {
                    result.append(
                        NSAttributedString(
                            string: " ",
                            attributes: baseAttributes
                        )
                    )
                }

                // Custom emoji render as static inline images (plain NSTextAttachment) — no
                // per-emoji SDAnimatedImageView / CADisplayLink, which (unbounded by cell reuse
                // in a SwiftUI list) saturated the main thread. Keyed on the static URL.
                // A loaded emoji and a still-loading one take the same space; only an emoji
                // that failed to load falls back to its readable shortcode.
                let displayImage: UIImage?
                if let image = emojiAssets[staticURL] {
                    displayImage = InlineEmojiRendering.scaled(image, for: staticURL, size: emojiSize)
                } else if pendingEmojiURLs.contains(staticURL) {
                    displayImage = InlineEmojiRendering.placeholder(size: emojiSize)
                } else {
                    displayImage = nil
                }
                if let displayImage {
                    let plain = Self.makeEmojiAttachment(
                        displayImage: displayImage,
                        emojiSize: emojiSize
                    )
                    let attachmentString = NSMutableAttributedString(attachment: plain)
                    attachmentString.addAttributes(
                        [.paragraphStyle: paragraphStyle],
                        range: NSRange(location: 0, length: attachmentString.length)
                    )
                    result.append(attachmentString)
                } else {
                    result.append(
                        NSAttributedString(
                            string: ":\(shortcode):",
                            attributes: baseAttributes
                        )
                    )
                }

                // And after it.
                if elements.emojiNeedsSpace(after: index) {
                    result.append(
                        NSAttributedString(
                            string: " ",
                            attributes: baseAttributes
                        )
                    )
                }

            case .inlineCode(let code):
                result.append(
                    NSAttributedString(
                        string: code,
                        attributes: codeAttributes
                    )
                )

            case .codeBlock(let code):
                result.append(
                    NSAttributedString(
                        string: code,
                        attributes: codeAttributes
                    )
                )

            case .lineBreak:
                if paragraphSpacing != nil, index > 0, elements[index - 1] == .lineBreak {
                    continue
                }
                result.append(
                    NSAttributedString(
                        string: "\n",
                        attributes: baseAttributes
                    )
                )
                if let paragraphSpacing, index + 1 < elements.count, elements[index + 1] == .lineBreak {
                    let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                    style.paragraphSpacing = paragraphSpacing
                    result.addAttribute(.paragraphStyle, value: style,
                        range: NSRange(location: paragraphStart, length: result.length - paragraphStart))
                }
                paragraphStart = result.length
            }
        }

        if let trailingSystemImage,
           let image = UIImage(
               systemName: trailingSystemImage,
               withConfiguration: UIImage.SymbolConfiguration(
                   pointSize: trailingSystemImageSize,
                   weight: .semibold
               )
           )?.withTintColor(trailingSystemImageColor, renderingMode: .alwaysOriginal)
        {
            result.append(NSAttributedString(string: " ", attributes: baseAttributes))

            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(
                x: 0,
                y: font.descender * 0.35,
                width: image.size.width,
                height: image.size.height
            )
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            attachmentString.addAttributes(
                [.paragraphStyle: paragraphStyle],
                range: NSRange(location: 0, length: attachmentString.length)
            )
            result.append(attachmentString)
        }

        return result
    }

}

extension UIImage {
    func aspectFittedCanvas(size: CGSize) -> UIImage {
        guard size.width > 0, size.height > 0 else { return self }
        guard self.size.width > 0, self.size.height > 0 else { return self }

        let widthScale = size.width / self.size.width
        let heightScale = size.height / self.size.height
        let scale = min(widthScale, heightScale)
        let drawSize = CGSize(width: self.size.width * scale, height: self.size.height * scale)
        let drawOrigin = CGPoint(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            self.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}

/// View for displaying a custom emoji image
struct EmojiImageView: View {
    let url: URL
    let shortcode: String
    let size: CGFloat

    var body: some View {
        MoroNetworkImage(url: url)
            .frame(width: size, height: size)
            .alignmentGuide(.firstTextBaseline) { _ in
                size * 0.75  // Adjust baseline to align with text
            }
    }
}

/// Convenience view that also handles opening URLs in Safari
struct LinkedTextView: View {
    let html: String
    let mentions: [Status.Mention]?
    let tags: [Status.Tag]?
    let emojis: [Status.Emoji]?
    var parsingOptions: ContentParsingOptions = []
    var emojiSize: CGFloat = 18
    var isSelectable: Bool = true
    var lineSpacing: CGFloat = 4
    var lineLimit: Int? = nil
    var fontOverride: Font? = nil
    var uiFontOverride: UIFont? = nil
    var textColorOverride: Color? = nil
    var linkColorOverride: Color? = nil
    var onMentionTap: ((String, URL) -> Bool)? = nil
    var onHashtagTap: ((String, URL) -> Void)? = nil
    var onLinkTap: ((URL) -> Void)? = nil

    @Environment(\.openURL) private var systemOpenURL
    @Environment(\.appRouter) private var router

    var body: some View {
        RichTextContentView(
            html: html,
            mentions: mentions,
            tags: tags,
            emojis: emojis,
            parsingOptions: parsingOptions,
            emojiSize: emojiSize,
            isSelectable: isSelectable,
            fontOverride: fontOverride,
            uiFontOverride: uiFontOverride,
            textColorOverride: textColorOverride,
            linkColorOverride: linkColorOverride,
            lineSpacing: lineSpacing,
            lineLimit: lineLimit
        ) { action in
            if !handleCustomLinkAction(action) {
                URLHandler.shared.handleLinkAction(action, router: router, systemOpenURL: systemOpenURL)
            }
        }
    }

    /// An unmatched mention must fall through to the user's URL opening preference.
    func handleCustomLinkAction(_ action: LinkAction) -> Bool {
        switch action {
        case .mention(let username, let url):
            return onMentionTap?(username, url) ?? false
        case .hashtag(let tag, let url):
            guard let onHashtagTap else { return false }
            onHashtagTap(tag, url)
        case .link(let url):
            guard let onLinkTap else { return false }
            onLinkTap(url)
        }
        return true
    }
}

#Preview {
    let sampleHTML = """
        <p>Hello <span class="h-card"><a href="https://mastodon.social/@user" class="u-url mention">@<span>user</span></a></span>! Check out <a href="https://mastodon.social/tags/SwiftUI" class="hashtag" rel="tag">#<span>SwiftUI</span></a> and visit <a href="https://apple.com" rel="nofollow">apple.com</a></p>
        """

    VStack(alignment: .leading, spacing: 20) {
        RichTextContentView(html: sampleHTML) { _ in }

        Divider()

        LinkedTextView(
            html: sampleHTML,
            mentions: nil,
            tags: nil,
            emojis: nil,
            onMentionTap: { _, _ in false },
            onHashtagTap: { _, _ in },
            onLinkTap: { _ in }
        )
    }
    .padding()
    .moroTheme(MoroTheme())
}
