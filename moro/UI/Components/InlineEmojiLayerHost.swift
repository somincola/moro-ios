import SwiftUI

/// An occurrence, including its position so repeated copies of one emoji wrap independently.
nonisolated struct InlineEmojiMarker: TextAttribute, Hashable {
    let index: Int
    let url: URL
}

struct InlineEmojiSlot: Equatable {
    let marker: InlineEmojiMarker
    let frame: CGRect
}

final class InlineEmojiLayerHost: UIView {
    private struct Glyph {
        let animation: PostEmojiAnimation
        let layer: CALayer
        let start: CFTimeInterval

        func restore(in parent: CALayer, onActivation: Bool = false) {
            if layer.superlayer !== parent { parent.addSublayer(layer) }
            if layer.contents == nil { layer.contents = animation.frames.last }
            // A finite sequence naturally removes itself and rests on its last frame.
            // An interrupted loop, by contrast, must reacquire its contents animation.
            if animation.loops > 0,
               layer.convertTime(CACurrentMediaTime(), from: nil) - start >= animation.duration * Double(animation.loops) {
                return
            }
            guard onActivation || layer.animation(forKey: "postEmoji") == nil else { return }
            let sequence = CAKeyframeAnimation(keyPath: "contents")
            sequence.calculationMode = .discrete
            sequence.values = animation.frames
            sequence.keyTimes = (animation.frameStarts + [1]).map(NSNumber.init(value:))
            sequence.duration = animation.duration
            sequence.repeatCount = animation.loops == 0 ? .infinity : Float(animation.loops)
            sequence.beginTime = start
            layer.add(sequence, forKey: "postEmoji")
        }
    }

    private var glyphs: [InlineEmojiMarker: Glyph] = [:]

    override func didMoveToWindow() {
        super.didMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: UIScene.didActivateNotification, object: nil)
        if let scene = window?.windowScene {
            NotificationCenter.default.addObserver(self, selector: #selector(restoreAnimations(_:)),
                                                  name: UIScene.didActivateNotification, object: scene)
            restoreAnimations()
        }
    }

    @objc private func restoreAnimations(_ notification: Notification? = nil) {
        for glyph in glyphs.values { glyph.restore(in: layer, onActivation: true) }
    }

    func update(slots: [InlineEmojiSlot], playing: [InlineEmojiMarker: PostEmojiAnimation]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        var obsolete = Set(glyphs.keys)
        for slot in slots {
            guard let animation = playing[slot.marker] else { continue }
            obsolete.remove(slot.marker)
            if let glyph = glyphs[slot.marker], glyph.animation === animation {
                glyph.layer.frame = slot.frame
                glyph.restore(in: layer)
                continue
            }
            glyphs[slot.marker]?.layer.removeFromSuperlayer()
            let imageLayer = CALayer()
            imageLayer.contentsScale = traitCollection.displayScale
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.frame = slot.frame
            layer.addSublayer(imageLayer)
            let glyph = Glyph(animation: animation, layer: imageLayer,
                              start: imageLayer.convertTime(CACurrentMediaTime(), from: nil))
            glyph.restore(in: layer)
            glyphs[slot.marker] = glyph
        }
        for marker in obsolete { glyphs.removeValue(forKey: marker)?.layer.removeFromSuperlayer() }
    }

    nonisolated deinit {}
}
