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

enum SDWebRemoteImageAnimationLoadingMode: Equatable {
    /// Preserve the shared renderer's existing behaviour for timeline media and every
    /// non-composer call site.
    case standard
    /// Decode the original APNG/GIF without thumbnailing away its frames, while bounding
    /// frame memory and pausing decorative playback during scrolling.
    case boundedPreview
}

struct SDWebRemoteImage: UIViewRepresentable {
    let url: URL?
    /// Longest-edge decode target in pixels. The decoder won't upscale, so passing the
    /// on-screen pixel size means small images are untouched and large ones shrink.
    let thumbnailPixelSize: CGFloat
    var contentMode: UIView.ContentMode = .scaleAspectFill
    var allowsAnimation: Bool = false
    /// Pause a decoded animation without replacing its image or restarting its request.
    var isAnimationPlaybackActive: Bool = true
    var animationLoadingMode: SDWebRemoteImageAnimationLoadingMode = .standard
    /// Caps decoded animation frames without forcing APNG/GIF through thumbnail decoding,
    /// which can collapse the resource to a single frame.
    var maximumAnimatedBufferSize: UInt = 8 * 1024 * 1024
    var onLoadStateChange: ((Bool) -> Void)? = nil
    var onLoadFailure: (() -> Void)? = nil

    func makeUIView(context: Context) -> SDAnimatedImageView {
        let view = SDAnimatedImageView()
        view.contentMode = contentMode
        view.clipsToBounds = true
        view.backgroundColor = .clear
        if animationLoadingMode == .boundedPreview {
            // Pause decorative animation while its scroll view is tracking without
            // changing the playback lifecycle of timeline GIF media.
            view.runLoopMode = .default
            view.maxBufferSize = maximumAnimatedBufferSize
            view.clearBufferWhenStopped = true
            view.resetFrameIndexWhenStopped = false
        }
        view.autoPlayAnimatedImage = allowsAnimation && isAnimationPlaybackActive
        return view
    }

    func updateUIView(_ view: SDAnimatedImageView, context: Context) {
        let usesBoundedPreview = animationLoadingMode == .boundedPreview
        context.coordinator.onLoadStateChange = usesBoundedPreview ? onLoadStateChange : nil
        context.coordinator.onLoadFailure = usesBoundedPreview ? onLoadFailure : nil
        view.contentMode = contentMode
        if usesBoundedPreview {
            view.maxBufferSize = maximumAnimatedBufferSize
        }
        let shouldPlay = allowsAnimation && isAnimationPlaybackActive
        view.autoPlayAnimatedImage = shouldPlay
        if shouldPlay {
            view.startAnimating()
        } else {
            view.stopAnimating()
        }
        guard context.coordinator.lastURL != url
            || context.coordinator.lastAllowsAnimation != allowsAnimation
            || context.coordinator.lastAnimationLoadingMode != animationLoadingMode
        else { return }
        let requestID = usesBoundedPreview ? UUID() : nil
        context.coordinator.loadRequestID = requestID
        context.coordinator.lastURL = url
        context.coordinator.lastAllowsAnimation = allowsAnimation
        context.coordinator.lastAnimationLoadingMode = animationLoadingMode
        view.sd_cancelCurrentImageLoad()

        guard let url else {
            view.stopAnimating()
            view.image = nil
            if let requestID {
                context.coordinator.reportLoadState(false, requestID: requestID)
            }
            return
        }
        if let requestID {
            context.coordinator.reportLoadState(false, requestID: requestID)
        }
        if !allowsAnimation {
            view.stopAnimating()
        }
        let thumbnail = NSValue(
            cgSize: CGSize(width: thumbnailPixelSize, height: thumbnailPixelSize))
        var options: SDWebImageOptions = [.retryFailed]
        let imageContext: [SDWebImageContextOption: Any]
        if allowsAnimation, usesBoundedPreview {
            options.insert(.matchAnimatedImageClass)
            imageContext = [
                .imageScaleDownLimitBytes: NSNumber(value: maximumAnimatedBufferSize)
            ]
        } else if !allowsAnimation {
            options.insert(.decodeFirstFrameOnly)
            imageContext = [.imageThumbnailPixelSize: thumbnail]
        } else {
            // This is the pre-existing path used by timeline GIF attachments. Keeping it as
            // the default ensures the composer feature cannot alter feed playback behaviour.
            imageContext = [.imageThumbnailPixelSize: thumbnail]
        }

        guard usesBoundedPreview, let requestID else {
            // Preserve the exact pre-feature loading path for timeline media and all other
            // shared-image consumers: no completion callback or extra main-queue work.
            view.sd_setImage(
                with: url,
                placeholderImage: nil,
                options: options,
                context: imageContext
            )
            return
        }

        view.sd_setImage(
            with: url,
            placeholderImage: nil,
            options: options,
            context: imageContext,
            progress: nil
        ) { [weak coordinator = context.coordinator] image, error, _, _ in
            guard let coordinator,
                  coordinator.loadRequestID == requestID else { return }
            let succeeded = image != nil && error == nil
            coordinator.reportLoadState(succeeded, requestID: requestID)
            if !succeeded {
                coordinator.reportLoadFailure(requestID: requestID)
            }
        }
    }

    static func dismantleUIView(_ view: SDAnimatedImageView, coordinator: Coordinator) {
        coordinator.loadRequestID = nil
        view.sd_cancelCurrentImageLoad()
        // Stop the animation + release frames so an off-screen media or picker preview does
        // not retain a CADisplayLink after SwiftUI dismantles the representable.
        view.stopAnimating()
        view.image = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        var lastURL: URL?
        var lastAllowsAnimation = false
        var lastAnimationLoadingMode: SDWebRemoteImageAnimationLoadingMode = .standard
        var loadRequestID: UUID?
        var onLoadStateChange: ((Bool) -> Void)?
        var onLoadFailure: (() -> Void)?

        func reportLoadState(_ isLoaded: Bool, requestID: UUID) {
            // Updating SwiftUI state synchronously from updateUIView causes runtime warnings
            // and can re-enter representable updates.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadRequestID == requestID else { return }
                self.onLoadStateChange?(isLoaded)
            }
        }

        func reportLoadFailure(requestID: UUID) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.loadRequestID == requestID else { return }
                self.onLoadFailure?()
            }
        }
    }

    /// Fill the proposed frame exactly (instead of reporting the image's intrinsic size),
    /// so callers that pin a height — e.g. the profile banner — don't get a gap.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: SDAnimatedImageView, context: Context
    ) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
