import UIKit

/// Folds shortcodes at glyph layout time. The text system keeps the original characters for
/// selection offsets, the keyboard, undo, copy/paste, drafts and publishing.
final class ComposeEmojiLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    nonisolated deinit {}

    private struct EmojiRun: Equatable {
        let range: NSRange
        let url: URL
        let image: UIImage
    }

    private static let expression = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}:]):([a-zA-Z0-9_]+):(?![\p{L}\p{N}:])"#
    )
    private var runs: [EmojiRun] = []
    private var side: CGFloat = 0
    private weak var catalog: CustomEmojiViewModel?
    private var requested = Set<URL>()
    private var failed = Set<URL>()

    func refresh(in view: UITextView, catalog: CustomEmojiViewModel?) {
        if self.catalog !== catalog {
            self.catalog = catalog
            failed.removeAll()
        }
        let size = ceil((view.font ?? .preferredFont(forTextStyle: .body)).lineHeight)
        let text = view.textStorage.string
        let source = text as NSString
        var updated: [EmojiRun] = []
        if let lookup = catalog?.emojiDict, !lookup.isEmpty, text.contains(":") {
            let range = NSRange(location: 0, length: source.length)
            let links = ComposeTextHighlighter.urlRanges(in: text)
            let marked = view.markedTextRange.map {
                NSRange(location: view.offset(from: view.beginningOfDocument, to: $0.start),
                        length: view.offset(from: $0.start, to: $0.end))
            }
            for match in Self.expression.matches(in: text, range: range) {
                let code = source.substring(with: match.range(at: 1))
                guard let url = lookup[code]?.first?.staticURL,
                      !links.contains(where: { NSIntersectionRange($0, match.range).length > 0 })
                else { continue }
                // During multistage input only move existing images with the surrounding text.
                if let marked {
                    guard NSIntersectionRange(marked, match.range).length == 0,
                          let previous = runs.first(where: { $0.url == url }) else { continue }
                    updated.append(EmojiRun(range: match.range, url: url, image: previous.image))
                    continue
                }
                // A late catalog or image must not fold text underneath an existing caret or selection handle.
                let selection = view.selectedRange
                let interior = (match.range.location + 1)..<NSMaxRange(match.range)
                if interior.contains(selection.location) || interior.contains(NSMaxRange(selection)) {
                    guard runs.contains(where: { $0.range == match.range && $0.url == url }) else { continue }
                }
                if let image = ImageCache.shared.image(for: url) {
                    updated.append(EmojiRun(range: match.range, url: url, image: InlineEmojiRendering.scaled(image, for: url, size: size)))
                } else {
                    load(url, for: view)
                }
            }
        }
        guard runs != updated || (!updated.isEmpty && side != size) else { return }
        runs = updated
        side = size
        let range = NSRange(location: 0, length: source.length)
        invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        invalidateDisplay(forCharacterRange: range)
        view.invalidateIntrinsicContentSize()
        view.setNeedsLayout()
    }

    private func load(_ url: URL, for view: UITextView) {
        guard !failed.contains(url), requested.insert(url).inserted else { return }
        Task { [weak self, weak view] in
            let image = await ImageCache.shared.load(from: url)
            guard let self, let view else { return }
            requested.remove(url)
            if image == nil { failed.insert(url) }
            // The next editing callback will pick up the image after a marked-text session.
            if image != nil, view.markedTextRange == nil { refresh(in: view, catalog: catalog) }
        }
    }

    func emojiEnding(at offset: Int) -> NSRange? {
        runs.first { NSMaxRange($0.range) == offset }?.range
    }

    /// Keyboard navigation, selection handles and taps cannot split a displayed image.
    func atomicSelection(_ range: NSRange, previous: NSRange) -> NSRange {
        func containing(_ offset: Int) -> NSRange? {
            runs.first { $0.range.location < offset && offset < NSMaxRange($0.range) }?.range
        }
        if range.length == 0, let emoji = containing(range.location) {
            let end = NSMaxRange(emoji)
            let moveForward = previous.location == range.location
                ? range.location - emoji.location >= end - range.location
                : previous.location < range.location
            return NSRange(location: moveForward ? end : emoji.location, length: 0)
        }
        let start = containing(range.location)?.location ?? range.location
        let end = containing(NSMaxRange(range)).map(NSMaxRange) ?? NSMaxRange(range)
        return NSRange(location: start, length: end - start)
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                       properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>,
                       font: UIFont, forGlyphRange glyphRange: NSRange) -> Int {
        guard !runs.isEmpty, glyphRange.length > 0 else { return 0 }
        let first = characterIndexes[0], last = characterIndexes[glyphRange.length - 1]
        guard var current = runs.firstIndex(where: { NSMaxRange($0.range) > first }),
              runs[current].range.location <= last else { return 0 }
        var adjusted = Array(UnsafeBufferPointer(start: properties, count: glyphRange.length))
        for i in adjusted.indices {
            let index = characterIndexes[i]
            while current < runs.count && NSMaxRange(runs[current].range) <= index { current += 1 }
            guard current < runs.count else { break }
            let start = runs[current].range.location
            if index >= start {
                adjusted[i] = index == start ? .controlCharacter : .null
            }
        }
        setGlyphs(glyphs, properties: adjusted, characterIndexes: characterIndexes, font: font, forGlyphRange: glyphRange)
        return glyphRange.length
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt index: Int) -> NSLayoutManager.ControlCharacterAction {
        runs.contains { $0.range.location == index } ? .whitespace : action
    }

    func layoutManager(_ layoutManager: NSLayoutManager, boundingBoxForControlGlyphAt glyphIndex: Int,
                       for textContainer: NSTextContainer, proposedLineFragment: CGRect, glyphPosition: CGPoint,
                       characterIndex: Int) -> CGRect {
        guard runs.contains(where: { $0.range.location == characterIndex }) else { return .zero }
        return CGRect(origin: .zero, size: CGSize(width: side, height: 0))
    }

    override func drawGlyphs(forGlyphRange glyphs: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphs, at: origin)
        guard let container = textContainers.first, let length = textStorage?.length else { return }
        for run in runs where NSMaxRange(run.range) <= length {
            let glyph = glyphIndexForCharacter(at: run.range.location)
            guard NSLocationInRange(glyph, glyphs) else { continue }
            let cell = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let line = lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            run.image.draw(in: CGRect(x: origin.x + cell.minX, y: origin.y + line.midY - side / 2,
                                      width: side, height: side))
        }
    }
}
