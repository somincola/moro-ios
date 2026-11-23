import Testing
import UIKit
@testable import moro

@MainActor
struct ComposeEmojiLayoutTests {
    private func makeEditor() -> (ComposeUIKitTextView, CustomEmojiViewModel) {
        let url = URL(string: "https://static.invalid/\(UUID()).png")!
        let emoji = CustomEmoji(shortcode: "blobcat", url: URL(string: "https://animated.invalid/cat.gif")!,
                                staticURL: url, visibleInPicker: true, category: nil)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        }
        ImageCache.shared.setImage(image, for: url)
        let catalog = CustomEmojiViewModel(domain: "one.example", service: .shared)
        catalog.emojiDict = [emoji.shortcode: [emoji]]
        let view = ComposeUIKitTextView(emojiLayout: ComposeEmojiLayoutManager())
        view.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        view.font = .systemFont(ofSize: 18)
        return (view, catalog)
    }

    @Test func onlyLocalCompleteShortcodesFoldToOneImageWidth() {
        let (view, catalog) = makeEditor()
        let source = "👋 :blobcat: :missing: https://example.com/:blobcat: word:blobcat:"
        view.text = source
        view.emojiLayout.refresh(in: view, catalog: catalog)
        view.emojiLayout.ensureLayout(for: view.textContainer)
        let range = (source as NSString).range(of: ":blobcat:")
        #expect(view.emojiLayout.emojiEnding(at: NSMaxRange(range)) == range)
        #expect(view.emojiLayout.emojiEnding(at: source.utf16.count) == nil)
        #expect(view.emojiLayout.emojiEnding(at: "👋 :blobcat: :missing: https://example.com/:blobcat:".utf16.count) == nil)
        let glyphs = view.emojiLayout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        #expect(view.emojiLayout.delegate === view.emojiLayout)
        #expect(view.emojiLayout.propertyForGlyph(at: glyphs.location).contains(.controlCharacter))
        #expect(view.emojiLayout.propertyForGlyph(at: glyphs.location + 1).contains(.null))
        let rect = view.emojiLayout.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
        #expect(abs(rect.width - ceil(view.font!.lineHeight)) < 2)
        #expect(view.text == source)
        #expect(view.emojiLayout.atomicSelection(NSRange(location: range.location + 1, length: 2),
                                                  previous: range) == range)
        view.emojiLayout.refresh(in: view, catalog: nil)
        #expect(view.emojiLayout.emojiEnding(at: NSMaxRange(range)) == nil)
        #expect(view.text == source)
        view.selectedRange = NSRange(location: range.location + 2, length: 0)
        view.emojiLayout.refresh(in: view, catalog: catalog)
        #expect(view.emojiLayout.emojiEnding(at: NSMaxRange(range)) == nil)
        view.selectedRange = NSRange(location: NSMaxRange(range), length: 0)
        view.emojiLayout.refresh(in: view, catalog: catalog)
        #expect(view.emojiLayout.emojiEnding(at: NSMaxRange(range)) == range)
    }

    @Test func deletesOnlyRenderedEmojiAndItsOwnAutomaticSeparator() {
        let (view, catalog) = makeEditor()
        view.text = "👋 "
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        view.insertEmoji("blobcat")
        #expect(view.text == "👋 :blobcat: ")
        view.emojiLayout.refresh(in: view, catalog: catalog)
        view.deleteBackward()
        #expect(view.text == "👋 ")

        view.insertText(":blobcat: :unknown:")
        view.emojiLayout.refresh(in: view, catalog: catalog)
        view.deleteBackward()
        #expect(view.text == "👋 :blobcat: :unknown")
        view.selectedRange = NSRange(location: "👋 :blobcat:".utf16.count, length: 0)
        view.deleteBackward()
        #expect(view.text == "👋  :unknown")

        view.text = "hello world"
        view.selectedRange = NSRange(location: 5, length: 0)
        view.insertEmoji("blobcat")
        view.emojiLayout.refresh(in: view, catalog: catalog)
        view.deleteBackward()
        #expect(view.text == "hello world")
    }

    @Test func renderingPreservesMarkedTextAndOffsetsAfterAnEmoji() {
        let (view, catalog) = makeEditor()
        view.text = ":blobcat: "
        view.emojiLayout.refresh(in: view, catalog: catalog)
        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        view.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0))
        #expect(view.markedTextRange != nil)
        view.insertText("你好")
        view.unmarkText()
        view.emojiLayout.refresh(in: view, catalog: catalog)
        #expect(view.text == ":blobcat: 你好")
        #expect(view.selectedRange.location == view.text.utf16.count)

        view.selectedRange = NSRange(location: 0, length: 0)
        view.setMarkedText("ni ", selectedRange: NSRange(location: 3, length: 0))
        view.emojiLayout.refresh(in: view, catalog: catalog)
        #expect(view.markedTextRange != nil)
        #expect(view.emojiLayout.emojiEnding(at: "ni :blobcat:".utf16.count)?.location == 3)
        view.unmarkText()
    }

    @Test func nativeUndoRestoresTheDeletedEmojiAndPreservesUserSpacing() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        let (view, catalog) = makeEditor()
        controller.view.addSubview(view)
        window.makeKeyAndVisible()
        defer {
            view.resignFirstResponder()
            window.isHidden = true
            previousWindow?.makeKeyAndVisible()
        }
        view.text = "word "
        view.selectedRange = NSRange(location: 5, length: 0)
        #expect(view.becomeFirstResponder())
        view.insertEmoji("blobcat")
        view.emojiLayout.refresh(in: view, catalog: catalog)
        let history = try #require(view.undoManager)
        history.removeAllActions()
        view.deleteBackward()
        #expect(view.text == "word ")
        #expect(history.canUndo)
        history.undo()
        #expect(view.text == "word :blobcat: ")
    }
}
