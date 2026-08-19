//
//  SDWebRemoteImage.swift
//  moro
//
//  SwiftUI wrapper over SDWebImage's SDAnimatedImageView. It downsamples to the
//  view's pixel size at decode time (so high-volume surfaces like avatars never hold
//  full-resolution bitmaps — the optimisation AlamofireImage's filters used to do),
//  caches, and only plays animated images when explicitly allowed.
//

import SDWebImage
import SwiftUI

struct SDWebRemoteImage: UIViewRepresentable {
    let url: URL?
    /// Longest-edge decode target in pixels. The decoder won't upscale, so passing the
    /// on-screen pixel size means small images are untouched and large ones shrink.
    let thumbnailPixelSize: CGFloat
    var contentMode: UIView.ContentMode = .scaleAspectFill
    var allowsAnimation: Bool = false

    func makeUIView(context: Context) -> SDAnimatedImageView {
        let view = SDAnimatedImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.autoPlayAnimatedImage = allowsAnimation
        return view
    }

    func updateUIView(_ view: SDAnimatedImageView, context: Context) {
        view.contentMode = contentMode
        view.autoPlayAnimatedImage = allowsAnimation
        guard context.coordinator.lastURL != url
            || context.coordinator.lastAllowsAnimation != allowsAnimation
        else { return }
        context.coordinator.lastURL = url
        context.coordinator.lastAllowsAnimation = allowsAnimation
        view.sd_cancelCurrentImageLoad()

        guard let url else {
            view.stopAnimating()
            view.image = nil
            return
        }
        if !allowsAnimation {
            view.stopAnimating()
        }
        let thumbnail = NSValue(
            cgSize: CGSize(width: thumbnailPixelSize, height: thumbnailPixelSize))
        var options: SDWebImageOptions = [.retryFailed]
        if !allowsAnimation {
            options.insert(.decodeFirstFrameOnly)
        }
        view.sd_setImage(
            with: url,
            placeholderImage: nil,
            options: options,
            context: [.imageThumbnailPixelSize: thumbnail]
        )
    }

    static func dismantleUIView(_ view: SDAnimatedImageView, coordinator: Coordinator) {
        view.sd_cancelCurrentImageLoad()
        // Stop the animation + release the frames so a recycled / off-screen cell doesn't keep
        // a main-thread CADisplayLink running for an image that's no longer shown. With many
        // animated avatars / custom emoji in a feed, those orphaned display links pile up and
        // saturate the main thread.
        view.stopAnimating()
        view.image = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastURL: URL?
        var lastAllowsAnimation = false
    }

    /// Fill the proposed frame exactly (instead of reporting the image's intrinsic size),
    /// so callers that pin a height — e.g. the profile banner — don't get a gap.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: SDAnimatedImageView, context: Context
    ) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
