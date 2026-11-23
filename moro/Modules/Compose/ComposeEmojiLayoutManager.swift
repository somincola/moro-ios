import UIKit

enum ComposeEmojiShortcodes {
    private static let expression = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}:]):([a-zA-Z0-9_]+):(?![\p{L}\p{N}:])"#
    )

    static func matches(in text: String, using lookup: [String: [CustomEmoji]]?) -> [(range: NSRange, emoji: CustomEmoji)] {
        guard let lookup, !lookup.isEmpty, text.contains(":") else { return [] }
        let source = text as NSString
        let links = ComposeTextHighlighter.urlRanges(in: text)
        return expression.matches(in: text, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let code = source.substring(with: match.range(at: 1))
            guard let emoji = lookup[code]?.first,
                  !links.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return nil }
            return (match.range, emoji)
        }
    }
}

/// Folds shortcodes at glyph layout time. The text system keeps the original characters for
/// selection offsets, the keyboard, undo, copy/paste, drafts and publishing.
final class ComposeEmojiLayoutManager: NSLayoutManager, NSLayoutManagerDelegate {
    nonisolated deinit {}

    private struct EmojiRun: Equatable {
        let range: NSRange
        let url: URL
        var image: UIImage?
    }

    private var runs: [EmojiRun] = []
    private var side: CGFloat = 0
    private weak var catalog: CustomEmojiViewModel?
    private var requested = Set<URL>()
    private var failed = Set<URL>()

    private struct LayoutInputs: Equatable {
        let textRevision: Int
        let catalogRevision: Int?
        let size: CGFloat
        let markedRange: NSRange?
    }

    private(set) var textRevision = 0
    private var lastInputs: LayoutInputs?
    private var needsAssetRefresh = false
    private var deferredSelection: NSRange?
    private static let loadingImage = UIImage(systemName: "face.smiling")?
        .withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)

    override func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorage.EditActions,
                                 range newCharRange: NSRange, changeInLength delta: Int,
                                 invalidatedRange invalidatedCharRange: NSRange) {
        if editMask.contains(.editedCharacters) { textRevision &+= 1 }
        super.processEditing(for: textStorage, edited: editMask, range: newCharRange,
                             changeInLength: delta, invalidatedRange: invalidatedCharRange)
    }

    func refresh(in view: UITextView, catalog: CustomEmojiViewModel?) {
        if self.catalog !== catalog || lastInputs?.catalogRevision != catalog?.emojiCatalogRevision {
            self.catalog = catalog
            lastInputs = nil
            failed.removeAll()
        }
        let size = InlineEmojiRendering.size(for: view.font ?? .preferredFont(forTextStyle: .body))
        let marked = view.markedTextRange.map {
            NSRange(location: view.offset(from: view.beginningOfDocument, to: $0.start),
                    length: view.offset(from: $0.start, to: $0.end))
        }
        let inputs = LayoutInputs(textRevision: textRevision, catalogRevision: catalog?.emojiCatalogRevision,
                                  size: size, markedRange: marked)
        let selection = view.selectedRange
        // Ordinary caret moves reuse the glyphs. Only a shortcode left open under the
        // selection needs another pass when the user moves away from it.
        guard needsAssetRefresh || lastInputs != inputs || (deferredSelection != nil && selection != deferredSelection) else { return }
        needsAssetRefresh = false
        lastInputs = inputs
        deferredSelection = nil

        var updated: [EmojiRun] = []
        let text = view.textStorage.string
        let range = NSRange(location: 0, length: view.textStorage.length)
        let matches = ComposeEmojiShortcodes.matches(in: text, using: catalog?.emojiDict)
        if !matches.isEmpty {
            let previous = Dictionary(runs.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
            for match in matches {
                let url = match.emoji.staticURL
                if let marked {
                    guard NSIntersectionRange(marked, match.range).length == 0,
                          let existing = previous[url] else { continue }
                    updated.append(EmojiRun(range: match.range, url: url, image: existing.image))
                    continue
                }
                let interior = (match.range.location + 1)..<NSMaxRange(match.range)
                if interior.contains(selection.location) || interior.contains(NSMaxRange(selection)) {
                    guard runs.contains(where: { $0.range == match.range && $0.url == url }) else {
                        deferredSelection = selection
                        continue
                    }
                }

                let image = previous[url]?.image ?? InlineEmojiRendering.cachedImage(for: url)
                if image == nil {
                    guard !failed.contains(url) else { continue }
                    load(url, for: view)
                }
                updated.append(EmojiRun(range: match.range, url: url, image: image))
            }
        }
        guard runs != updated || (!updated.isEmpty && side != size) else { return }
        runs = updated
        side = size
        invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
        invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
        invalidateDisplay(forCharacterRange: range)
        view.invalidateIntrinsicContentSize()
        view.setNeedsLayout()
    }

    private func load(_ url: URL, for view: UITextView) {
        guard requested.insert(url).inserted else { return }
        Task { [weak self, weak view] in
            let image = await InlineEmojiRendering.loadThumbnail(for: url)
            guard let self, let view else { return }
            requested.remove(url)
            if let image {
                // The slot already has its final metrics. A download only repaints this URL.
                for index in runs.indices where runs[index].url == url {
                    runs[index].image = image
                    let range = runs[index].range
                    if NSMaxRange(range) <= view.textStorage.length { invalidateDisplay(forCharacterRange: range) }
                }
            } else {
                failed.insert(url)
                needsAssetRefresh = true
                if view.markedTextRange == nil { refresh(in: view, catalog: catalog) }
            }
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

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard !runs.isEmpty, glyphRange.length > 0 else { return false }
        let characters = characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard runs.contains(where: { NSLocationInRange($0.range.location, characters) }) else { return false }
        // A control glyph reserves width only. Leave room for the actual image above
        // and below the baseline, including on the first line at accessibility sizes.
        let descent = InlineEmojiRendering.descent(for: side)
        let above = max(0, side - descent - baselineOffset.pointee)
        let below = max(0, descent - (lineFragmentRect.pointee.height - baselineOffset.pointee))
        guard above + below > 0 else { return false }
        baselineOffset.pointee += above
        lineFragmentRect.pointee.size.height += above + below
        lineFragmentUsedRect.pointee.size.height += above + below
        return true
    }

    override func drawGlyphs(forGlyphRange glyphs: NSRange, at origin: CGPoint) {
        super.drawGlyphs(forGlyphRange: glyphs, at: origin)
        guard !runs.isEmpty, let container = textContainers.first, let length = textStorage?.length else { return }
        let visible = characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        for run in runs where NSLocationInRange(run.range.location, visible) && NSMaxRange(run.range) <= length {
            let glyph = glyphIndexForCharacter(at: run.range.location)
            let cell = boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let line = lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = origin.y + line.minY + location(forGlyphAt: glyph).y
            let slot = CGRect(x: origin.x + cell.minX, y: baseline + InlineEmojiRendering.descent(for: side) - side,
                              width: side, height: side)
            if let image = run.image {
                InlineEmojiRendering.scaled(image, for: run.url, size: side).draw(in: slot)
            } else {
                Self.loadingImage?.draw(in: slot)
            }
        }
    }
}
