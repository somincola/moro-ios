import UIKit

/// Keeps animation layers in TextKit's content coordinates. A caret-only layout reuses
/// the current placement. Core Animation advances frames without touching the text view.
@MainActor
final class ComposeEmojiPlayback {
    private struct Layout: Equatable {
        let textRevision: Int
        let runRevision: Int
        let width: CGFloat
        let insets: UIEdgeInsets
        let viewport: CGRect
        let pixelSize: Int
    }

    private enum Asset: Sendable {
        case loading(Task<Void, Never>)
        case ready(PostEmojiAnimation)
        case deferred(bytes: Int)
        case unavailable
    }

    private var layout: Layout?
    private var slots: [InlineEmojiSlot] = []
    private var assets: [URL: Asset] = [:]
    private var host: InlineEmojiLayerHost?
    private var needsDisplay = false
    private var retainedBytes = 0
    private let byteBudget: Int

    init(byteBudget: Int = PostEmojiAnimationStore.decodedByteBudget) {
        self.byteBudget = byteBudget
    }

    func update(in editor: ComposeUIKitTextView, viewport: CGRect) {
        let manager = editor.emojiLayout
        let pixelSize = Int(ceil(manager.side * editor.traitCollection.displayScale))
        let next = Layout(textRevision: manager.textRevision, runRevision: manager.runRevision,
                          width: editor.textContainer.size.width, insets: editor.textContainerInset,
                          viewport: viewport, pixelSize: pixelSize)
        if layout != next {
            let sizeChanged = layout?.pixelSize != pixelSize
            layout = next
            slots = manager.visibleSlots(in: editor, viewport: viewport)
            let urls = Set(slots.map(\.marker.url))
            for url in Array(assets.keys) where sizeChanged || !urls.contains(url) {
                switch assets.removeValue(forKey: url) {
                case .loading(let task): task.cancel()
                case .ready(let animation): retainedBytes -= animation.byteCount
                default: break
                }
            }
            for slot in slots {
                let url = slot.marker.url
                switch assets[url] {
                case nil where retainedBytes < byteBudget: break
                case .deferred(let bytes) where bytes <= byteBudget - retainedBytes: break
                default: continue
                }
                if let cached = PostEmojiAnimationStore.shared.cachedAnimation(for: url, pixelSize: pixelSize) {
                    accept(cached, for: url)
                } else {
                    assets[url] = .loading(Task { [weak self, weak editor] in
                        let animation = await PostEmojiAnimationStore.shared.animation(for: url, pixelSize: pixelSize)
                        guard !Task.isCancelled, let self, let editor else { return }
                        accept(animation, for: url)
                        needsDisplay = true
                        editor.setNeedsLayout()
                    })
                }
            }
            needsDisplay = true
        }
        guard needsDisplay else { return }
        needsDisplay = false
        var playing: [InlineEmojiMarker: PostEmojiAnimation] = [:]
        for slot in slots {
            if case .ready(let animation) = assets[slot.marker.url] { playing[slot.marker] = animation }
        }
        manager.showAnimations(Set(playing.keys))
        guard !playing.isEmpty else {
            host?.removeFromSuperview()
            host = nil
            return
        }
        let surface: InlineEmojiLayerHost
        if let host { surface = host }
        else {
            surface = InlineEmojiLayerHost()
            surface.isUserInteractionEnabled = false
            surface.accessibilityElementsHidden = true
            editor.insertSubview(surface, at: 0)
            host = surface
        }
        surface.frame = viewport
        surface.bounds = viewport
        surface.update(slots: slots, playing: playing)
    }

    /// Live layers retain their frames even if NSCache evicts them. Count each original once.
    private func accept(_ animation: PostEmojiAnimation?, for url: URL) {
        guard let animation else { assets[url] = .unavailable; return }
        guard animation.byteCount <= byteBudget - retainedBytes else {
            assets[url] = .deferred(bytes: animation.byteCount)
            return
        }
        retainedBytes += animation.byteCount
        assets[url] = .ready(animation)
    }

    func stop(in editor: ComposeUIKitTextView) {
        for case .loading(let task) in assets.values { task.cancel() }
        assets.removeAll()
        retainedBytes = 0
        layout = nil
        slots.removeAll()
        host?.removeFromSuperview()
        host = nil
        editor.emojiLayout.showAnimations([])
    }

    nonisolated deinit {
        for case .loading(let task) in assets.values { task.cancel() }
    }
}
