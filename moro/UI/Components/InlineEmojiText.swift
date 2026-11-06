//
//  InlineEmojiText.swift
//  moro
//
//  Rich text with custom emoji drawn as plain SwiftUI `Text`. Post bodies and other
//  list content use this instead of a UITextView: it is cheaper to create and lay out,
//  has the same line metrics as text without emoji, and never moves when an emoji's
//  image arrives, because a same-size placeholder holds its place until then.
//

import SwiftUI
import UIKit

/// A stretch of styled text, or one custom emoji.
enum InlineTextRun: Equatable {
    case text(AttributedString)
    case emoji(shortcode: String, staticURL: URL)
}

struct InlineTextStyle {
    var textColor: Color
    var linkColor: Color
    var codeBackgroundColor: Color
    var codeFontSize: CGFloat
    var underlinesLinks: Bool = false
    /// Off for previews inside a tappable row, where a tap should open the row instead.
    var linksAreInteractive: Bool = true
}

enum InlineTextRunBuilder {
    /// Groups the parsed content into as few runs as possible: neighbouring text, links,
    /// mentions and hashtags share one `AttributedString`, broken only at an emoji.
    static func runs(for elements: [ContentElement], style: InlineTextStyle) -> [InlineTextRun] {
        var runs: [InlineTextRun] = []
        var current = AttributedString()

        func flush() {
            guard !current.characters.isEmpty else { return }
            runs.append(.text(current))
            current = AttributedString()
        }

        for (index, element) in elements.enumerated() {
            switch element {
            case .text(let text):
                current += AttributedString(text)
            case .link(let text, let url), .mention(let text, let url), .hashtag(let text, let url):
                var link = AttributedString(text)
                if style.linksAreInteractive {
                    link.link = url
                }
                link.foregroundColor = style.linkColor
                if style.underlinesLinks {
                    link.underlineStyle = .single
                }
                current += link
            case .emoji(let shortcode, _, let staticURL):
                // Keep one space between an emoji and the text right next to it.
                if elements.emojiNeedsSpace(before: index) {
                    current += AttributedString(" ")
                }
                flush()
                runs.append(.emoji(shortcode: shortcode, staticURL: staticURL))
                if elements.emojiNeedsSpace(after: index) {
                    current += AttributedString(" ")
                }
            case .inlineCode(let code):
                var codeText = AttributedString(code)
                codeText.font = .system(size: style.codeFontSize, weight: .regular, design: .monospaced)
                codeText.foregroundColor = style.textColor
                codeText.backgroundColor = style.codeBackgroundColor
                current += codeText
            case .codeBlock(let code):
                var codeText = AttributedString(code)
                codeText.font = .system(size: style.codeFontSize, weight: .regular, design: .monospaced)
                current += codeText
            case .lineBreak:
                current += AttributedString("\n")
            }
        }
        flush()
        return runs
    }

    /// The same content as one string, with each emoji written as its `:shortcode:`.
    static func flattened(_ runs: [InlineTextRun]) -> AttributedString {
        runs.reduce(into: AttributedString()) { result, run in
            switch run {
            case .text(let text):
                result += text
            case .emoji(let shortcode, _):
                result += AttributedString(":\(shortcode):")
            }
        }
    }

    static func emojiURLs(in runs: [InlineTextRun]) -> [URL] {
        var seen = Set<URL>()
        return runs.compactMap { run in
            guard case .emoji(_, let url) = run, seen.insert(url).inserted else { return nil }
            return url
        }
    }
}

/// Text with inline custom emoji. Fonts, colors, line limits and link handling come from
/// the environment like any other `Text`.
struct InlineEmojiText: View {
    let runs: [InlineTextRun]
    let emojiSize: CGFloat
    var trailingSystemImage: String? = nil
    var trailingSystemImageColor: Color = .primary
    var trailingSystemImageSize: CGFloat = 11

    /// Lowers the emoji slightly so it sits centred on the text, like the TextKit attachment.
    private static let baselineRatio: CGFloat = 0.08

    @State private var failedURLs: Set<URL> = []
    /// Bumped when downloads finish so the view picks the images up from the cache.
    @State private var loadGeneration = 0

    var body: some View {
        let _ = loadGeneration
        Self.concatenate(pieces[...])
            .task(id: InlineTextRunBuilder.emojiURLs(in: runs)) {
                await loadMissingEmoji()
            }
    }

    private var pieces: [Text] {
        var pieces = runs.map { run -> Text in
            switch run {
            case .text(let text):
                return Text(text)
            case .emoji(let shortcode, let url):
                if let image = InlineEmojiRendering.cachedImage(for: url) {
                    return emojiText(InlineEmojiRendering.scaled(image, for: url, size: emojiSize), shortcode: shortcode)
                }
                if failedURLs.contains(url) {
                    return Text(verbatim: ":\(shortcode):")
                }
                return emojiText(InlineEmojiRendering.placeholder(size: emojiSize), shortcode: shortcode)
            }
        }
        if let trailingSystemImage {
            pieces.append(Text(verbatim: " "))
            pieces.append(
                Text(Image(systemName: trailingSystemImage))
                    .font(.system(size: trailingSystemImageSize, weight: .semibold))
                    .foregroundStyle(trailingSystemImageColor)
            )
        }
        return pieces
    }

    private func emojiText(_ image: UIImage, shortcode: String) -> Text {
        let label = Text(verbatim: ":\(shortcode):")
        let swiftUIImage = image.cgImage.map { Image($0, scale: image.scale, label: label) }
            ?? Image(uiImage: image)
        // Same baseline shift as the TextKit attachment, so both renderers agree.
        return Text(swiftUIImage).baselineOffset(-emojiSize * Self.baselineRatio)
    }

    /// Joins the pieces as a balanced tree. A long left-leaning chain of nested `Text`
    /// interpolations measured far slower, with occasional very long layouts.
    static func concatenate(_ pieces: ArraySlice<Text>) -> Text {
        switch pieces.count {
        case 0:
            return Text(verbatim: "")
        case 1:
            return pieces[pieces.startIndex]
        default:
            let middle = pieces.startIndex + pieces.count / 2
            return Text("\(concatenate(pieces[..<middle]))\(concatenate(pieces[middle...]))")
        }
    }

    private func loadMissingEmoji() async {
        let missing = InlineTextRunBuilder.emojiURLs(in: runs).filter {
            InlineEmojiRendering.cachedImage(for: $0) == nil && !failedURLs.contains($0)
        }
        guard !missing.isEmpty else { return }

        var failures: Set<URL> = []
        await withTaskGroup(of: (URL, Bool).self) { group in
            for url in missing {
                group.addTask { (url, await InlineEmojiRendering.loadImage(for: url) != nil) }
            }
            for await (url, loaded) in group where !loaded {
                failures.insert(url)
            }
        }
        guard !Task.isCancelled else { return }
        if !failures.isEmpty {
            failedURLs.formUnion(failures)
        }
        loadGeneration &+= 1
    }
}

/// Shared pieces for drawing custom emoji inline (SwiftUI text, TextKit bios, names).
@MainActor
enum InlineEmojiRendering {
    // NSCache is thread-safe; it just isn't annotated Sendable.
    nonisolated(unsafe) private static let imageCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 240
        return cache
    }()
    private static var placeholders: [CGFloat: UIImage] = [:]
    private static let scaledImages: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()
    private static var inFlight: [URL: Task<UIImage?, Never>] = [:]

    nonisolated static func cachedImage(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
    }

    nonisolated static func store(_ image: UIImage, for url: URL) {
        imageCache.setObject(image, forKey: url as NSURL)
    }

    /// Downloads a static emoji image once, however many views ask for it at the same time.
    static func loadImage(for url: URL) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let running = inFlight[url] { return await running.value }
        let task = Task<UIImage?, Never> {
            defer { inFlight[url] = nil }
            guard let data = await fetchData(from: url), let image = UIImage(data: data) else {
                return nil
            }
            store(image, for: url)
            return image
        }
        inFlight[url] = task
        return await task.value
    }

    nonisolated static func fetchData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .returnCacheDataElseLoad
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    /// A transparent image the size of the final emoji. While an emoji is still loading it
    /// holds the emoji's exact place, so the line breaks and the view's height don't change
    /// when the real image arrives. (A `:shortcode:` stand-in is much wider and reflows.)
    static func placeholder(size: CGFloat) -> UIImage {
        let key = (size * 2).rounded() / 2
        if let cached = placeholders[key] { return cached }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: key, height: key), format: format)
            .image { _ in }
        placeholders[key] = image
        return image
    }

    /// The emoji drawn at its display size, cached so a rebuild doesn't redraw it.
    static func scaled(_ image: UIImage, for url: URL, size: CGFloat) -> UIImage {
        let key = "\(size)|\(url.absoluteString)" as NSString
        if let cached = scaledImages.object(forKey: key) { return cached }
        let scaled = image.aspectFittedCanvas(size: CGSize(width: size, height: size))
        scaledImages.setObject(scaled, forKey: key)
        return scaled
    }
}
