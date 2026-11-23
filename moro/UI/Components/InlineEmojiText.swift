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
    case emoji(shortcode: String, url: URL, staticURL: URL)
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
            case .emoji(let shortcode, let url, let staticURL):
                // Keep one space between an emoji and the text right next to it.
                if elements.emojiNeedsSpace(before: index) {
                    current += AttributedString(" ")
                }
                flush()
                runs.append(.emoji(shortcode: shortcode, url: url, staticURL: staticURL))
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
            case .emoji(let shortcode, _, _):
                result += AttributedString(":\(shortcode):")
            }
        }
    }

    static func emojiURLs(in runs: [InlineTextRun]) -> [URL] {
        var seen = Set<URL>()
        return runs.compactMap { run in
            guard case .emoji(_, _, let url) = run, seen.insert(url).inserted else { return nil }
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

    @Environment(\.animatesPostEmoji) private var animatesPostEmoji
    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Environment(\.scenePhase) private var scenePhase
    private struct PosterRequest: Equatable {
        let urls: [URL]
        let size: CGFloat
        let isActive: Bool
    }
    private struct Posters: Equatable {
        var size: CGFloat = 0
        var images: [URL: UIImage] = [:]
        var failed: Set<URL> = []
    }
    // The paragraph keeps its display-sized posters while mounted. Memory-cache
    // eviction in the background must not erase the still or the playback fallback.
    @State private var posters = Posters()

    var body: some View {
        let request = PosterRequest(urls: InlineTextRunBuilder.emojiURLs(in: runs), size: emojiSize,
                                    isActive: !animatesPostEmoji || scenePhase == .active)
        return Group {
            if animatesPostEmoji && mediaPrefs.playAnimations && request.isActive {
                PostEmojiPlaybackText(emojiSize: emojiSize) { playing in
                    inlineText(markForPlayback: true, playing: playing)
                }
            } else {
                inlineText(markForPlayback: false, playing: [])
            }
        }
        .task(id: request) { if request.isActive { await loadPosters(request) } }
    }

    private func inlineText(markForPlayback: Bool, playing: Set<InlineEmojiMarker>) -> Text {
        var pieces = runs.enumerated().map { index, run -> Text in
            switch run {
            case .text(let text):
                return Text(text)
            case .emoji(let shortcode, let original, let poster):
                let marker = InlineEmojiMarker(index: index, url: original)
                let piece: Text
                if playing.contains(marker) {
                    piece = emojiText(InlineEmojiRendering.placeholder(size: emojiSize), shortcode: shortcode)
                } else if posters.size == emojiSize, let image = posters.images[poster] {
                    piece = emojiText(image, shortcode: shortcode)
                } else if let image = InlineEmojiRendering.cachedImage(for: poster) {
                    piece = emojiText(InlineEmojiRendering.scaled(image, for: poster, size: emojiSize), shortcode: shortcode)
                } else if posters.failed.contains(poster) {
                    piece = Text(verbatim: ":\(shortcode):")
                } else {
                    piece = emojiText(InlineEmojiRendering.placeholder(size: emojiSize), shortcode: shortcode)
                }
                return markForPlayback ? piece.customAttribute(marker) : piece
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
        return Self.concatenate(pieces[...])
    }

    private func emojiText(_ image: UIImage, shortcode: String) -> Text {
        let label = Text(verbatim: ":\(shortcode):")
        let swiftUIImage = image.cgImage.map { Image($0, scale: image.scale, label: label) }
            ?? Image(uiImage: image)
        // Same baseline shift as the TextKit attachment, so both renderers agree.
        return Text(swiftUIImage).baselineOffset(-InlineEmojiRendering.descent(for: emojiSize))
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

    private func loadPosters(_ request: PosterRequest) async {
        guard !Task.isCancelled else { return }
        let urls = Set(request.urls)
        var next = Posters(size: request.size)
        if posters.size == request.size { next.images = posters.images.filter { urls.contains($0.key) } }
        next.failed = posters.failed.intersection(urls)
        var missing: [URL] = []
        for url in request.urls where next.images[url] == nil {
            if let image = InlineEmojiRendering.cachedImage(for: url) {
                next.images[url] = InlineEmojiRendering.scaled(image, for: url, size: request.size)
                next.failed.remove(url)
            } else {
                missing.append(url)
            }
        }
        if posters != next { posters = next }
        guard !missing.isEmpty else { return }

        let sharedOriginals = Set(runs.compactMap { run -> URL? in
            guard animatesPostEmoji && mediaPrefs.playAnimations,
                  case .emoji(_, let original, let poster) = run, original == poster else { return nil }
            return original
        })
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in missing {
                group.addTask {
                    let image = await InlineEmojiRendering.loadImage(for: url, sharesOriginal: sharedOriginals.contains(url))
                    return (url, image)
                }
            }
            for await (url, image) in group {
                guard !Task.isCancelled else { return }
                if let image {
                    posters.images[url] = InlineEmojiRendering.scaled(image, for: url, size: request.size)
                    posters.failed.remove(url)
                } else {
                    posters.failed.insert(url)
                }
            }
        }
    }
}

/// Shared pieces for drawing custom emoji inline (SwiftUI text, TextKit bios, names).
@MainActor
enum InlineEmojiRendering {
    static func size(for font: UIFont) -> CGFloat { font.pointSize * 1.25 }

    /// Portion of the square below the text baseline in both SwiftUI and TextKit.
    static func descent(for size: CGFloat) -> CGFloat { size * 0.08 }

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

    // The picker, suggestions and text use one SDWebImage thumbnail key. A static
    // preview that is already visible can be painted synchronously in either renderer.
    private nonisolated static let thumbnailPixels: CGFloat = 128

    nonisolated static func cachedImage(for url: URL) -> UIImage? {
        imageCache.object(forKey: url as NSURL)
            ?? ImageCache.shared.thumbnail(for: url, maxPixelSize: thumbnailPixels)
            ?? ImageCache.shared.image(for: url)
    }

    static func loadThumbnail(for url: URL) async -> UIImage? {
        if let image = cachedImage(for: url) { return image }
        return await ImageCache.shared.loadThumbnail(from: url, maxPixelSize: thumbnailPixels)
    }

    nonisolated static func store(_ image: UIImage, for url: URL) {
        imageCache.setObject(image, forKey: url as NSURL)
    }

    /// Downloads a static emoji image once, however many views ask for it at the same time.
    static func loadImage(for url: URL, sharesOriginal: Bool = false) async -> UIImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let running = inFlight[url] { return await running.value }
        let task = Task<UIImage?, Never> {
            defer { inFlight[url] = nil }
            if sharesOriginal, let original = try? await AvatarAnimationDataStore.shared.data(for: url),
               let image = UIImage(data: original) {
                store(image, for: url)
                return image
            }
            return await loadThumbnail(for: url)
        }
        inFlight[url] = task
        return await task.value
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
