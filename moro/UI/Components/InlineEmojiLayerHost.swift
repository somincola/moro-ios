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
    private var glyphs: [InlineEmojiMarker: (animation: PostEmojiAnimation, layer: CALayer)] = [:]

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
                continue
            }
            glyphs[slot.marker]?.layer.removeFromSuperlayer()
            let imageLayer = CALayer()
            imageLayer.contentsScale = traitCollection.displayScale
            imageLayer.contentsGravity = .resizeAspect
            imageLayer.frame = slot.frame
            imageLayer.contents = animation.frames.last
            layer.addSublayer(imageLayer)
            let sequence = CAKeyframeAnimation(keyPath: "contents")
            sequence.calculationMode = .discrete
            sequence.values = animation.frames
            // Discrete keyframes include one extra time marking the end of the last frame.
            sequence.keyTimes = (animation.frameStarts + [1]).map(NSNumber.init(value:))
            sequence.duration = animation.duration
            sequence.repeatCount = animation.loops == 0 ? .infinity : Float(animation.loops)
            imageLayer.add(sequence, forKey: "postEmoji")
            glyphs[slot.marker] = (animation, imageLayer)
        }
        for marker in obsolete { glyphs.removeValue(forKey: marker)?.layer.removeFromSuperlayer() }
    }

    nonisolated deinit {}
}
