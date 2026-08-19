//
//  AccountDisplayNameView.swift
//  moro
//
//  Dedicated display-name renderer that progressively replaces custom emoji tokens
//  without blocking the surrounding text.
//

import SwiftUI
import UIKit

struct AccountDisplayNameView: View {
    enum Typography {
        case title
        case titleStrong
        case subtitle
        case body
        case bodyStrong
        case caption
        case captionStrong

        var swiftUIFont: Font {
            switch self {
            case .title:
                return .system(.title3, weight: .semibold)
            case .titleStrong:
                return .system(.title3, weight: .bold)
            case .subtitle:
                return .system(.headline)
            case .body:
                return .system(.subheadline)
            case .bodyStrong:
                return .system(.subheadline, weight: .semibold)
            case .caption:
                return .system(.footnote)
            case .captionStrong:
                return .system(.footnote, weight: .semibold)
            }
        }

        /// Base (unscaled) UIKit font + the text style it scales against, so the
        /// UILabel (custom-emoji) path can produce a Dynamic Type–scaled font via
        /// `UIFontMetrics`. Default-size output matches the previous fixed sizes.
        var uiKitBase: (style: UIFont.TextStyle, size: CGFloat, weight: UIFont.Weight) {
            switch self {
            case .title:
                return (.title3, 20, .semibold)
            case .titleStrong:
                return (.title3, 20, .bold)
            case .subtitle:
                return (.headline, 17, .semibold)
            case .body:
                return (.subheadline, 15, .regular)
            case .bodyStrong:
                return (.subheadline, 15, .semibold)
            case .caption:
                return (.footnote, 13, .regular)
            case .captionStrong:
                return (.footnote, 13, .semibold)
            }
        }
    }

    let account: Account
    var typography: Typography = .body
    var textColor: Color
    var lineLimit: Int? = 1
    var truncationMode: Text.TruncationMode = .tail
    var minimumScaleFactor: CGFloat = 1
    var allowsTightening: Bool = false
    var emojiScale: CGFloat = 1.05
    var fontOverride: Font? = nil
    var uiFontOverride: UIFont? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let content = account.displayNameContent

        Group {
            if content.containsCustomEmoji {
                AccountDisplayNameLabelRepresentable(
                    content: content,
                    font: resolvedUIFont,
                    textColor: UIColor(textColor),
                    lineLimit: lineLimit,
                    lineBreakMode: lineBreakMode,
                    minimumScaleFactor: minimumScaleFactor,
                    allowsTightening: allowsTightening,
                    emojiScale: emojiScale
                )
                .accessibilityLabel(content.plainText)
            } else {
                Text(content.plainText)
                    .font(resolvedSwiftUIFont)
                    .foregroundStyle(textColor)
                    .lineLimit(lineLimit)
                    .truncationMode(truncationMode)
                    .minimumScaleFactor(minimumScaleFactor)
                    .allowsTightening(allowsTightening)
            }
        }
        .alignmentGuide(.firstTextBaseline) { dimensions in
            dimensions[.bottom]
        }
    }

    private var resolvedSwiftUIFont: Font {
        fontOverride ?? typography.swiftUIFont
    }

    private var resolvedUIFont: UIFont {
        if let uiFontOverride { return uiFontOverride }
        let base = typography.uiKitBase
        return UIFontMetrics(forTextStyle: base.style).scaledFont(
            for: .systemFont(ofSize: base.size, weight: base.weight),
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        )
    }

    private var lineBreakMode: NSLineBreakMode {
        guard lineLimit == 1 else { return .byWordWrapping }
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
}

struct AccountDisplayNameContent: Equatable {
    enum Segment: Equatable {
        case text(String)
        case emoji(Account.Emoji)
    }

    let plainText: String
    let segments: [Segment]
    let initials: String

    var containsCustomEmoji: Bool {
        segments.contains {
            if case .emoji = $0 { return true }
            return false
        }
    }

    var emojiURLs: [URL] {
        var seen = Set<URL>()
        var urls: [URL] = []
        for segment in segments {
            guard case .emoji(let emoji) = segment else { continue }
            if seen.insert(emoji.staticURL).inserted {
                urls.append(emoji.staticURL)
            }
        }
        return urls
    }
}

enum AccountDisplayNameParser {
    private final class CachedContentBox {
        let content: AccountDisplayNameContent

        init(_ content: AccountDisplayNameContent) {
            self.content = content
        }
    }

    private static let cache: NSCache<NSString, CachedContentBox> = {
        let cache = NSCache<NSString, CachedContentBox>()
        cache.countLimit = 1200
        return cache
    }()

    private static let emojiShortcodeRegex = try? NSRegularExpression(
        pattern: ":([a-zA-Z0-9_\\-]+):"
    )

    static func parse(
        displayName: String,
        fallbackUsername: String,
        emojis: [Account.Emoji]
    ) -> AccountDisplayNameContent {
        let cacheKey = cacheKey(
            displayName: displayName,
            fallbackUsername: fallbackUsername,
            emojis: emojis
        )
        if let cached = cache.object(forKey: cacheKey) {
            return cached.content
        }

        let plainText = sanitize(displayName: displayName, fallbackUsername: fallbackUsername)
        let segments = parseSegments(in: plainText, emojis: emojis)
        let initialsSeed = segments.reduce(into: "") { partialResult, segment in
            switch segment {
            case .text(let text):
                partialResult += text
            case .emoji:
                partialResult += " "
            }
        }
        let content = AccountDisplayNameContent(
            plainText: plainText,
            segments: segments,
            initials: makeInitials(from: initialsSeed, fallbackUsername: fallbackUsername)
        )
        cache.setObject(CachedContentBox(content), forKey: cacheKey)
        return content
    }

    private static func sanitize(displayName: String, fallbackUsername: String) -> String {
        let source = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackUsername
            : displayName

        let stripped = HTMLParser.stripHTML(source)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return stripped.isEmpty ? fallbackUsername : stripped
    }

    private static func parseSegments(
        in plainText: String,
        emojis: [Account.Emoji]
    ) -> [AccountDisplayNameContent.Segment] {
        guard !plainText.isEmpty else { return [.text("")] }
        guard !emojis.isEmpty, let emojiShortcodeRegex else {
            return [.text(plainText)]
        }

        let emojiMap = Dictionary(uniqueKeysWithValues: emojis.map { ($0.shortcode, $0) })
        var segments: [AccountDisplayNameContent.Segment] = []
        var lastEnd = plainText.startIndex
        let matches = emojiShortcodeRegex.matches(
            in: plainText,
            options: [],
            range: NSRange(plainText.startIndex..., in: plainText)
        )

        for match in matches {
            guard let fullRange = Range(match.range, in: plainText),
                  let shortcodeRange = Range(match.range(at: 1), in: plainText) else {
                continue
            }

            if lastEnd < fullRange.lowerBound {
                segments.append(.text(String(plainText[lastEnd..<fullRange.lowerBound])))
            }

            let shortcode = String(plainText[shortcodeRange])
            if let emoji = emojiMap[shortcode] {
                segments.append(.emoji(emoji))
            } else {
                segments.append(.text(String(plainText[fullRange])))
            }

            lastEnd = fullRange.upperBound
        }

        if lastEnd < plainText.endIndex {
            segments.append(.text(String(plainText[lastEnd...])))
        }

        return segments.isEmpty ? [.text(plainText)] : segments
    }

    private static func makeInitials(from source: String, fallbackUsername: String) -> String {
        let normalized = source
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = fallbackUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed = normalized.isEmpty ? fallback : normalized

        guard !seed.isEmpty else { return "?" }

        let words = seed.split(whereSeparator: \.isWhitespace)
        if words.count >= 2,
           let first = words.first?.first,
           let second = words.dropFirst().first?.first {
            return String([first, second]).uppercased()
        }

        return String(seed.prefix(2)).uppercased()
    }

    private static func cacheKey(
        displayName: String,
        fallbackUsername: String,
        emojis: [Account.Emoji]
    ) -> NSString {
        var hasher = Hasher()
        hasher.combine(displayName)
        hasher.combine(fallbackUsername)
        hasher.combine(emojis.count)
        for emoji in emojis {
            hasher.combine(emoji.shortcode)
            hasher.combine(emoji.staticURL.absoluteString)
        }
        return NSString(string: String(hasher.finalize()))
    }
}

private final class AccountDisplayNameLabel: UILabel {
    override var intrinsicContentSize: CGSize {
        let width = preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : bounds.width
        guard width > 0 else { return super.intrinsicContentSize }

        let size = sizeThatFits(
            CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        return CGSize(width: UIView.noIntrinsicMetric, height: max(ceil(size.height), 1))
    }

    override var bounds: CGRect {
        didSet {
            if bounds.width > 0, abs(bounds.width - oldValue.width) > 0.5 {
                preferredMaxLayoutWidth = bounds.width
                invalidateIntrinsicContentSize()
            }
        }
    }
}

private struct AccountDisplayNameLabelRepresentable: UIViewRepresentable {
    let content: AccountDisplayNameContent
    let font: UIFont
    let textColor: UIColor
    let lineLimit: Int?
    let lineBreakMode: NSLineBreakMode
    let minimumScaleFactor: CGFloat
    let allowsTightening: Bool
    let emojiScale: CGFloat

    func makeUIView(context: Context) -> AccountDisplayNameLabel {
        let label = AccountDisplayNameLabel()
        label.backgroundColor = .clear
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        label.setContentHuggingPriority(.defaultLow, for: .vertical)
        return label
    }

    func updateUIView(_ label: AccountDisplayNameLabel, context: Context) {
        configure(label)
        context.coordinator.render(
            on: label,
            content: content,
            font: font,
            textColor: textColor,
            lineBreakMode: lineBreakMode,
            emojiScale: emojiScale
        )
    }

    @available(iOS 16.0, *)
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: AccountDisplayNameLabel,
        context: Context
    ) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        uiView.preferredMaxLayoutWidth = width
        let size = uiView.sizeThatFits(CGSize(width: width, height: CGFloat.greatestFiniteMagnitude))
        return CGSize(width: width, height: max(ceil(size.height), 1))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configure(_ label: AccountDisplayNameLabel) {
        label.font = font
        label.textColor = textColor
        label.numberOfLines = lineLimit ?? 0
        label.lineBreakMode = lineBreakMode
        label.minimumScaleFactor = minimumScaleFactor
        label.adjustsFontSizeToFitWidth = minimumScaleFactor < 1 && (lineLimit ?? 1) == 1
        label.allowsDefaultTighteningForTruncation = allowsTightening
        if label.bounds.width > 0 {
            label.preferredMaxLayoutWidth = label.bounds.width
        }
    }

    fileprivate func attributedText(
        using images: [URL: UIImage]
    ) -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = lineBreakMode
        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle,
        ]

        let result = NSMutableAttributedString()
        let emojiSize = font.pointSize * emojiScale

        for segment in content.segments {
            switch segment {
            case .text(let text):
                result.append(NSAttributedString(string: text, attributes: baseAttributes))
            case .emoji(let emoji):
                if let image = images[emoji.staticURL] {
                    let attachment = NSTextAttachment()
                    attachment.image = image.aspectFittedCanvas(
                        size: CGSize(width: emojiSize, height: emojiSize)
                    )
                    attachment.bounds = CGRect(
                        x: 0,
                        y: -emojiSize * 0.08,
                        width: emojiSize,
                        height: emojiSize
                    )
                    let attachmentString = NSMutableAttributedString(attachment: attachment)
                    attachmentString.addAttributes(
                        [.paragraphStyle: paragraphStyle],
                        range: NSRange(location: 0, length: attachmentString.length)
                    )
                    result.append(attachmentString)
                } else {
                    result.append(
                        NSAttributedString(
                            string: ":\(emoji.shortcode):",
                            attributes: baseAttributes
                        )
                    )
                }
            }
        }

        return result
    }

    final class Coordinator {
        private var renderTask: Task<Void, Never>?
        private var generation: Int = 0

        deinit {
            renderTask?.cancel()
        }

        func render(
            on label: AccountDisplayNameLabel,
            content: AccountDisplayNameContent,
            font: UIFont,
            textColor: UIColor,
            lineBreakMode: NSLineBreakMode,
            emojiScale: CGFloat
        ) {
            generation += 1
            let currentGeneration = generation
            renderTask?.cancel()

            let renderer = AccountDisplayNameLabelRepresentable(
                content: content,
                font: font,
                textColor: textColor,
                lineLimit: label.numberOfLines == 0 ? nil : label.numberOfLines,
                lineBreakMode: lineBreakMode,
                minimumScaleFactor: label.minimumScaleFactor,
                allowsTightening: label.allowsDefaultTighteningForTruncation,
                emojiScale: emojiScale
            )

            var images: [URL: UIImage] = [:]
            for url in content.emojiURLs {
                if let image = AccountDisplayNameEmojiLoader.cachedImage(for: url) {
                    images[url] = image
                }
            }

            label.attributedText = renderer.attributedText(using: images)

            let missingURLs = content.emojiURLs.filter { images[$0] == nil }
            guard !missingURLs.isEmpty else { return }

            renderTask = Task { [weak self] in
                for url in missingURLs {
                    guard !Task.isCancelled else { return }
                    guard let image = await AccountDisplayNameEmojiLoader.loadImage(from: url) else {
                        continue
                    }
                    images[url] = image

                    // Coordinator gone (cell torn down) — drop the rest of the work
                    // so we don't keep pinning the label/images until the next URLSession
                    // timeout resolves.
                    guard let self else { return }
                    await MainActor.run {
                        guard currentGeneration == self.generation else { return }
                        label.attributedText = renderer.attributedText(using: images)
                        label.invalidateIntrinsicContentSize()
                    }
                }
            }
        }
    }
}

private enum AccountDisplayNameEmojiLoader {
    private static let imageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 240
        return cache
    }()

    static func cachedImage(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
    }

    static func loadImage(from url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) {
            return cached
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .returnCacheDataElseLoad

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled else { return nil }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard let image = UIImage(data: data) else { return nil }
            imageCache.setObject(image, forKey: url as NSURL)
            return image
        } catch {
            return nil
        }
    }
}
