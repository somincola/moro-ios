import SDWebImage
import SwiftUI
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
        #expect(abs(rect.width - InlineEmojiRendering.size(for: view.font!)) < 1)
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

    @Test func aWarmAnimationFollowsTheSameGlyphThroughTypingAndCaretMoves() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        let (editor, catalog) = makeEditor()
        controller.view.addSubview(editor)
        window.isHidden = false
        defer { window.isHidden = true }
        let source = try #require(PostEmojiPlaybackFixture.post.emojis?.first)
        let emoji = CustomEmoji(shortcode: "moving", url: source.url, staticURL: source.staticURL,
                                visibleInPicker: true, category: nil)
        catalog.emojiDict = ["moving": [emoji]]
        editor.text = ":moving: "
        editor.emojiLayout.refresh(in: editor, catalog: catalog)
        let size = Int(ceil(editor.emojiLayout.side * editor.traitCollection.displayScale))
        _ = try #require(await PostEmojiAnimationStore.shared.animation(for: source.url, pixelSize: size))
        editor.setEmojiPlaybackEnabled(true)
        editor.layoutIfNeeded()
        func layer() -> CALayer? {
            editor.subviews.compactMap { $0 as? InlineEmojiLayerHost }.first?.layer.sublayers?.first
        }
        let first = try #require(layer())
        #expect(first.animation(forKey: "postEmoji") != nil)
        let originalY = first.frame.minY
        editor.selectedRange = NSRange(location: 0, length: 0)
        editor.insertText("hello\n")
        editor.emojiLayout.refresh(in: editor, catalog: catalog)
        editor.layoutIfNeeded()
        #expect(layer() === first)
        #expect(first.frame.minY > originalY)
        editor.selectedRange = NSRange(location: editor.text.utf16.count, length: 0)
        editor.setMarkedText("nihao", selectedRange: NSRange(location: 5, length: 0))
        editor.emojiLayout.refresh(in: editor, catalog: catalog)
        editor.layoutIfNeeded()
        #expect(layer() === first && editor.markedTextRange != nil)
        editor.insertText("你好")
        editor.unmarkText()
        editor.setEmojiViewport(.zero)
        editor.layoutIfNeeded()
        #expect(layer() == nil)
        editor.setEmojiViewport(editor.bounds)
        editor.layoutIfNeeded()
        #expect(layer()?.animation(forKey: "postEmoji") != nil)
        editor.setEmojiPlaybackEnabled(false)
        #expect(layer() == nil)
        #expect(editor.text == "hello\n:moving: 你好")
    }

    @Test func repeatedCopiesShareTheEditorsFrameBudgetAndScrollingFreesIt() async throws {
        let (editor, catalog) = makeEditor()
        let originals = try #require(PostEmojiPlaybackFixture.post.emojis)
        for (name, source) in zip(["a", "b"], originals) {
            catalog.emojiDict?[name] = [CustomEmoji(shortcode: name, url: source.url, staticURL: source.staticURL,
                                                    visibleInPicker: true, category: nil)]
        }
        editor.text = ":a: :a:\n:b: "
        editor.emojiLayout.refresh(in: editor, catalog: catalog)
        editor.layoutIfNeeded()
        let size = Int(ceil(editor.emojiLayout.side * editor.traitCollection.displayScale))
        let a = try #require(await PostEmojiAnimationStore.shared.animation(for: originals[0].url, pixelSize: size))
        let b = try #require(await PostEmojiAnimationStore.shared.animation(for: originals[1].url, pixelSize: size))
        let playback = ComposeEmojiPlayback(byteBudget: max(a.byteCount, b.byteCount))
        playback.update(in: editor, viewport: editor.bounds)
        func layers() -> [CALayer] {
            editor.subviews.compactMap { $0 as? InlineEmojiLayerHost }.first?.layer.sublayers ?? []
        }
        #expect(layers().count == 2)
        let bottom = try #require(editor.emojiLayout.visibleSlots(in: editor, viewport: editor.bounds).last)
        playback.update(in: editor, viewport: bottom.frame)
        #expect(layers().count == 1)
        #expect(layers().first?.frame == bottom.frame)
        playback.stop(in: editor)
        #expect(layers().isEmpty)
    }

    @Test func pickerThumbnailPaintsImmediatelyAtTheReadingBaseline() async throws {
        let (view, catalog) = makeEditor()
        let font = MoroTheme(postFontSize: .small).postUIFont()
        view.font = font
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        // A wide solid image makes it possible to check the actual painted pixels as
        // well as the square the text system reserves for it.
        let still = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
        }
        try #require(still.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let emoji = CustomEmoji(shortcode: "wide", url: URL(string: "https://animated.invalid/wide.gif")!,
                                staticURL: url, visibleInPicker: true, category: nil)
        catalog.emojiDict = ["wide": [emoji]]
        // Load through the same path the visible suggestion and picker use.
        _ = try #require(await InlineEmojiRendering.loadThumbnail(for: url))
        // Evict just this fixture from SDWebImage while the picker still displays it.
        let pixelsPerSide = InlineEmojiRendering.thumbnailPixels
        let thumbnailKey = try #require(SDWebImageManager.shared.cacheKey(for: url, context: [
            .imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: pixelsPerSide, height: pixelsPerSide))
        ]))
        SDImageCache.shared.removeImageFromMemory(forKey: thumbnailKey)
        #expect(ImageCache.shared.image(for: url) == nil)
        #expect(InlineEmojiRendering.cachedImage(for: url) != nil)
        view.insertEmoji("wide")
        view.emojiLayout.refresh(in: view, catalog: catalog)
        let manager = view.emojiLayout
        manager.ensureLayout(for: view.textContainer)
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: 0, length: 6), actualCharacterRange: nil)
        let cell = manager.boundingRect(forGlyphRange: glyphs, in: view.textContainer)
        let size = InlineEmojiRendering.size(for: font)
        #expect(abs(cell.width - size) < 1)
        let origin = CGPoint(x: 4, y: 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64), format: format).image { _ in
            manager.drawGlyphs(forGlyphRange: glyphs, at: origin)
        }
        let image = try #require(bitmap.cgImage)
        var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
        let painted = pixels.withUnsafeMutableBytes { buffer -> CGRect in
            let context = CGContext(data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8,
                                    bytesPerRow: 64 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            var bounds = CGRect.null
            for offset in stride(from: 0, to: buffer.count, by: 4)
                where buffer[offset] > 150 && buffer[offset + 1] < 20 {
                let pixel = offset / 4
                bounds = bounds.union(CGRect(x: pixel % 64, y: pixel / 64, width: 1, height: 1))
            }
            return bounds
        }
        let baseline = origin.y + manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil).minY
            + manager.location(forGlyphAt: 0).y
        #expect(abs(painted.width - size) < 2)
        #expect(abs(painted.height - size / 2) < 2)
        #expect(abs(painted.midY - (baseline + InlineEmojiRendering.descent(for: size) - size / 2)) < 1)
        #expect(view.text == ":wide: ")
    }

    @Test func accessibilitySizeKeepsTheWholeEmojiInsideItsLine() {
        let (view, catalog) = makeEditor()
        view.font = MoroTheme(dynamicTypeSize: .accessibility5).postUIFont()
        view.text = ":blobcat:\n:blobcat:"
        let manager = view.emojiLayout
        manager.refresh(in: view, catalog: catalog)
        manager.ensureLayout(for: view.textContainer)
        let size = InlineEmojiRendering.size(for: view.font!)
        var previousBottom: CGFloat = 0
        for character in [0, ":blobcat:\n".utf16.count] {
            let glyph = manager.glyphIndexForCharacter(at: character)
            let line = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = line.minY + manager.location(forGlyphAt: glyph).y
            let bottom = baseline + InlineEmojiRendering.descent(for: size)
            #expect(bottom - size >= max(line.minY, previousBottom) - 1)
            #expect(bottom <= line.maxY + 1)
            previousBottom = bottom
        }
    }

    @Test func visiblePickerPlaysTheOriginalWhileKeepingTheServerStillReady() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.gif")
        let still = directory.appendingPathComponent("static.png")
        try ProfileMediaFixture.gifData(frameDuration: 0.2).write(to: original)
        let posterBounds = CGRect(x: 0, y: 0, width: 16, height: 16)
        let poster = UIGraphicsImageRenderer(size: posterBounds.size).image { $0.fill(posterBounds) }
        try #require(poster.pngData()).write(to: still)
        let emoji = CustomEmoji(shortcode: "animated", url: original, staticURL: still, visibleInPicker: true, category: nil)
        let catalog = CustomEmojiViewModel(domain: "picker.example", service: .shared)
        catalog.emojiGroups = [EmojiGroup(name: "Test", emojis: [emoji])]
        let host = UIHostingController(rootView: EmojiPickerContentView(emojiViewModel: catalog, isSceneActive: true,
                                                                       playAnimations: true, onEmojiSelected: { _ in }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 280))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        func player(in view: UIView) -> SDAnimatedImageView? {
            if let view = view as? SDAnimatedImageView { return view }
            return view.subviews.lazy.compactMap { player(in: $0) }.first
        }
        let deadline = ContinuousClock.now + .seconds(30)
        var frames = Set<UInt>()
        while ContinuousClock.now < deadline {
            if let view = player(in: window), view.isAnimating { frames.insert(view.currentFrameIndex) }
            if frames.count > 1, InlineEmojiRendering.cachedImage(for: still) != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(frames.count == 2)
        #expect(InlineEmojiRendering.cachedImage(for: still) != nil)
    }

    @Test func coldEmojiReservesOneSlotAndShowsItsCodeIfTheStillFails() async throws {
        let (view, catalog) = makeEditor()
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        let emoji = CustomEmoji(shortcode: "missing", url: missing, staticURL: missing, visibleInPicker: true, category: nil)
        view.text = ":missing: "
        view.emojiLayout.refresh(in: view, catalog: catalog)
        #expect(view.emojiLayout.emojiEnding(at: 9) == nil)
        catalog.emojiDict = ["missing": [emoji]]
        view.emojiLayout.refresh(in: view, catalog: catalog)
        #expect(view.emojiLayout.emojiEnding(at: 9)?.location == 0)
        // The shared thumbnail loader can queue this request behind other image tests.
        let deadline = ContinuousClock.now + .seconds(60)
        while view.emojiLayout.emojiEnding(at: 9) != nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(view.emojiLayout.emojiEnding(at: 9) == nil)
        #expect(view.text == ":missing: ")
    }

    @Test func movingCaretAndSwitchingKeyboardsReusesThePickerContent() {
        let (view, catalog) = makeEditor()
        let theme = MoroTheme()
        func config(playing: Bool) -> ComposeEmojiPickerConfiguration {
            .init(catalog: ObjectIdentifier(catalog), hasHost: true, isSceneActive: true, playAnimations: playing,
                  colors: theme.colors, dynamicTypeSize: theme.dynamicTypeSize)
        }
        var builds = 0
        func update(_ mode: ComposeInputMode, height: CGFloat = 320, playing: Bool = true) {
            view.updateInputMode(mode, emojiPickerHeight: height, configuration: config(playing: playing)) {
                builds += 1
                return AnyView(EmptyView())
            }
        }
        update(.emoji)
        view.insertEmoji("blobcat")
        view.selectedRange = NSRange(location: 0, length: 0)
        update(.emoji)
        update(.emoji, height: 280)
        update(.keyboard)
        update(.emoji)
        #expect(builds == 1)
        update(.emoji, playing: false)
        #expect(builds == 2)
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
