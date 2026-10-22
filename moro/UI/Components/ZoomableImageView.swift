import SDWebImage
import SwiftUI

/// UIKit owns every frame of zooming and panning; SwiftUI only receives discrete
/// chrome events. Updating a toolbar or opening ALT must not reset the viewport.
struct ZoomableImageView: UIViewRepresentable {
    let url: URL
    /// The smaller rendition the timeline shows; displayed at once while `url` loads.
    var previewURL: URL? = nil
    let altText: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onSingleTap: () -> Void
    var onInteractionBegan: () -> Void
    var onDismiss: () -> Void
    var onLongPress: () -> Void = {}

    func makeUIView(context: Context) -> ImagePreviewPageView { ImagePreviewPageView() }

    func updateUIView(_ view: ImagePreviewPageView, context: Context) {
        view.reduceMotion = reduceMotion
        view.scrollView.onSingleTap = onSingleTap
        view.scrollView.onInteractionBegan = onInteractionBegan
        view.scrollView.onDismiss = onDismiss
        view.scrollView.onLongPress = onLongPress
        view.scrollView.configure(url: url, previewURL: previewURL, altText: altText)
    }

    static func dismantleUIView(_ view: ImagePreviewPageView, coordinator: ()) {
        view.resetDismissDrag()
        view.scrollView.cancelLoading()
    }
}

/// Keep the pager and its safe area stationary. Transforming the SwiftUI TabView
/// during dismissal changes its page bounds and repeatedly refits the image.
final class ImagePreviewPageView: UIView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    let scrollView = ImagePreviewScrollView()
    var reduceMotion = false
    private var dragStartOffset: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(scrollView)
        scrollView.onDismissDrag = { [weak self] distance, ended in
            self?.updateDismissDrag(distance, ended: ended)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Do not set frame while transformed: it is the transformed bounding box.
        scrollView.bounds.size = bounds.size
        scrollView.center = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func updateDismissDrag(_ distance: CGFloat, ended: Bool) {
        if ended {
            dragStartOffset = nil
            if reduceMotion {
                resetDismissDrag()
            } else {
                UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.86,
                    initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                    self.scrollView.transform = .identity
                }
            }
            return
        }
        if dragStartOffset == nil {
            // A new drag can interrupt the return animation. Start at the visible
            // position instead of snapping to the animation's model-layer target.
            let visible = scrollView.layer.presentation()?.affineTransform() ?? scrollView.transform
            dragStartOffset = max(visible.ty, 0)
            scrollView.layer.removeAllAnimations()
        }
        let offset = max(distance + (dragStartOffset ?? 0), 0)
        let scale = reduceMotion ? 1 : 1 - min(offset / 220, 1) * 0.06
        scrollView.transform = CGAffineTransform(translationX: 0, y: offset).scaledBy(x: scale, y: scale)
    }

    func resetDismissDrag() {
        dragStartOffset = nil
        scrollView.layer.removeAllAnimations()
        scrollView.transform = .identity
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { resetDismissDrag() }
    }
}

struct ImageZoomGeometry {
    let imageSize: CGSize
    let viewport: CGSize

    var minimumScale: CGFloat {
        min(viewport.width / max(imageSize.width, 1), viewport.height / max(imageSize.height, 1))
    }

    var readingScale: CGFloat {
        let widthScale = viewport.width / max(imageSize.width, 1)
        // Long text images fill the width instead of using an insufficient fixed 2x zoom.
        return widthScale > minimumScale * 1.4 ? widthScale : minimumScale * 2
    }

    var maximumScale: CGFloat { max(minimumScale * 4, readingScale * 2) }
}

final class ImagePreviewScrollView: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    let imageView = UIImageView()
    var onSingleTap: (() -> Void)?
    var onInteractionBegan: (() -> Void)?
    var onDismissDrag: ((CGFloat, Bool) -> Void)?
    var onDismiss: (() -> Void)?
    var onLongPress: (() -> Void)?

    private let spinner = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private var imageLoad: SDWebImageOperation?
    private var requestID = UUID()
    private var imageURL: URL?
    private var previewURL: URL?
    /// True once the full-size image is on screen (not just the timeline's preview).
    private var showsFullImage = false
    /// A full-size image that arrived mid-gesture; swapped in when the gesture ends.
    private var pendingFullImage: UIImage?
    private var viewportSize: CGSize = .zero
    private var needsImageLayout = false
    private var isUpdatingLayout = false
    private weak var lockedPager: UIScrollView?
    private lazy var dismissPan = UIPanGestureRecognizer(target: self, action: #selector(dragToDismiss(_:)))
    private lazy var longPress: UILongPressGestureRecognizer = {
        let recognizer = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        recognizer.minimumPressDuration = 0.45
        recognizer.delegate = self
        return recognizer
    }()

    var isAtMinimumZoom: Bool { zoomScale <= minimumZoomScale * 1.01 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .clear
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        accessibilityIdentifier = "imagePreview.scroll"

        imageView.contentMode = .scaleToFill
        imageView.isAccessibilityElement = true
        imageView.accessibilityTraits = .image
        imageView.accessibilityIdentifier = "imagePreview.image"
        imageView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: MoroL10n.ImagePreview.zoomAction, target: self,
                selector: #selector(accessibilityToggleZoom))
        ]
        addSubview(imageView)

        spinner.color = .white
        addSubview(spinner)
        retryButton.setTitle(MoroL10n.ImagePreview.loadFailed + " · " + MoroL10n.ContentState.retry, for: .normal)
        retryButton.setTitleColor(.white, for: .normal)
        retryButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        retryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        retryButton.titleLabel?.numberOfLines = 0
        retryButton.addTarget(self, action: #selector(retryLoading), for: .touchUpInside)
        retryButton.accessibilityIdentifier = "imagePreview.retry"
        retryButton.isHidden = true
        addSubview(retryButton)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.delegate = self
        singleTap.require(toFail: doubleTap)
        addGestureRecognizer(singleTap)

        dismissPan.maximumNumberOfTouches = 1
        dismissPan.delegate = self
        addGestureRecognizer(dismissPan)
        // Long press opens save/share/copy. It only fires on a still finger, so it
        // never competes with pinch, pan, paging or drag-to-dismiss.
        addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(url: URL, previewURL: URL? = nil, altText: String?) {
        imageView.accessibilityLabel = altText ?? MoroL10n.ImagePreview.noAltDescription
        guard imageURL != url else { return }
        imageURL = url
        // The timeline shows `preview_url` when there is one, otherwise the image itself.
        self.previewURL = previewURL ?? url
        imageView.image = nil
        imageView.isHidden = true
        showsFullImage = false
        pendingFullImage = nil
        loadImage()
    }

    func cancelLoading() {
        unlockPager()
        requestID = UUID()
        imageLoad?.cancel()
        imageLoad = nil
    }

    private func loadImage() {
        cancelLoading()
        guard let imageURL else { return }
        let request = requestID
        if !showsFullImage, imageView.image == nil { spinner.startAnimating() }
        retryButton.isHidden = true
        showCachedPreview(for: request)
        // Preserve long-image width with a 32 MiB decoded-pixel budget. The former
        // 2000px longest-edge limit could reduce a 600x6000 page to 200x2000.
        // Thumbnail context separates this rendition from timeline memory-cache
        // entries. The per-request coder calculates the size from the file header,
        // including when the server omits attachment dimensions.
        imageLoad = SDWebImageManager.shared.loadImage(
            with: imageURL,
            options: [.retryFailed],
            context: [
                .imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: 8192, height: 8192)),
                .imageCoder: ImagePreviewImageCoder.shared,
            ],
            progress: nil
        ) { [weak self] image, _, _, _, finished, _ in
            guard finished else { return }
            DispatchQueue.main.async {
                guard let self, self.requestID == request else { return }
                self.spinner.stopAnimating()
                self.retryButton.isHidden = image != nil
                if let image { self.showFullImage(image) }
            }
        }
    }

    /// Shows the image the timeline already loaded, straight from the cache, while the full
    /// size downloads. The timeline shows `preview_url` (a smaller file), so the viewer still
    /// needs the original; it just no longer opens on an empty spinner. Never downloads.
    private func showCachedPreview(for request: UUID) {
        guard let previewURL, !showsFullImage, imageView.image == nil else { return }
        let side = MoroNetworkImage.thumbnailPixelSize
        SDWebImageManager.shared.loadImage(
            with: previewURL,
            options: [.fromCacheOnly, .decodeFirstFrameOnly],
            // Same context as the timeline's MoroNetworkImage, so this is the same cache entry.
            context: [.imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: side, height: side))],
            progress: nil
        ) { [weak self] image, _, _, _, finished, _ in
            guard finished, let image else { return }
            DispatchQueue.main.async {
                guard let self, self.requestID == request, !self.showsFullImage,
                    self.imageView.image == nil else { return }
                self.spinner.stopAnimating()
                self.display(image)
            }
        }
    }

    private func showFullImage(_ image: UIImage) {
        showsFullImage = true
        guard imageView.image != nil, viewportSize != .zero else {
            display(image)
            return
        }
        // Replacing the preview mid-gesture would fight the user's fingers.
        if isZooming || isTracking || isDragging || isDecelerating || isZoomBouncing {
            pendingFullImage = image
            return
        }
        replaceDisplayedImage(with: image)
    }

    private func applyPendingFullImage() {
        guard let image = pendingFullImage, !isZooming, !isTracking, !isDecelerating else { return }
        pendingFullImage = nil
        replaceDisplayedImage(with: image)
    }

    /// Swaps the preview for the full-size image without moving anything on screen: same
    /// relative zoom, same visible point. A different aspect ratio starts over instead.
    func replaceDisplayedImage(with image: UIImage) {
        guard let current = imageView.image, current.size.width > 0, current.size.height > 0,
            image.size.width > 0, image.size.height > 0, viewportSize != .zero
        else {
            display(image)
            return
        }
        let currentAspect = current.size.width / current.size.height
        let newAspect = image.size.width / image.size.height
        guard abs(currentAspect - newAspect) / newAspect < 0.02 else {
            display(image)
            return
        }

        let wasAtMinimum = isAtMinimumZoom
        let relativeScale = zoomScale / max(minimumZoomScale, 0.0001)
        let visibleCenter = CGPoint(
            x: (contentOffset.x + bounds.width / 2) / max(contentSize.width, 1),
            y: (contentOffset.y + bounds.height / 2) / max(contentSize.height, 1))

        isUpdatingLayout = true
        defer { isUpdatingLayout = false }
        imageView.image = image
        minimumZoomScale = 0.0001
        maximumZoomScale = 100
        setZoomScale(1, animated: false)
        imageView.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        let geometry = ImageZoomGeometry(imageSize: image.size, viewport: bounds.size)
        minimumZoomScale = geometry.minimumScale
        maximumZoomScale = geometry.maximumScale
        setZoomScale(wasAtMinimum ? minimumZoomScale
            : min(maximumZoomScale, minimumZoomScale * relativeScale), animated: false)
        centerImage()
        if wasAtMinimum {
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        } else {
            contentOffset = boundedOffset(CGPoint(
                x: visibleCenter.x * contentSize.width - bounds.width / 2,
                y: visibleCenter.y * contentSize.height - bounds.height / 2))
        }
        viewportSize = bounds.size
        updateAccessibilityValue()
    }

    func display(_ image: UIImage) {
        imageView.image = image
        imageView.isHidden = false
        needsImageLayout = true
        setNeedsLayout()
    }

    @objc private func retryLoading() { loadImage() }

    override func layoutSubviews() {
        super.layoutSubviews()
        spinner.center = CGPoint(x: bounds.midX, y: bounds.midY)
        retryButton.frame = CGRect(x: bounds.minX + 24, y: bounds.midY - 36,
            width: max(bounds.width - 48, 0), height: 72)
        guard !isUpdatingLayout, bounds.width > 0, bounds.height > 0,
            let image = imageView.image,
            needsImageLayout || viewportSize != bounds.size else { return }

        isUpdatingLayout = true
        defer { isUpdatingLayout = false }
        let reset = needsImageLayout || viewportSize == .zero
        let wasAtMinimum = isAtMinimumZoom
        let relativeScale = zoomScale / max(minimumZoomScale, 0.0001)
        let center = CGPoint(
            x: (contentOffset.x + viewportSize.width / 2) / zoomScale,
            y: (contentOffset.y + viewportSize.height / 2) / zoomScale)

        viewportSize = bounds.size
        needsImageLayout = false
        if reset {
            minimumZoomScale = 0.0001
            maximumZoomScale = 100
            setZoomScale(1, animated: false)
            imageView.frame = CGRect(origin: .zero, size: image.size)
            contentSize = image.size
        }
        let geometry = ImageZoomGeometry(imageSize: image.size, viewport: bounds.size)
        minimumZoomScale = geometry.minimumScale
        maximumZoomScale = geometry.maximumScale
        setZoomScale(reset || wasAtMinimum ? minimumZoomScale
            : min(maximumZoomScale, minimumZoomScale * relativeScale), animated: false)
        centerImage()
        if reset || wasAtMinimum {
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        } else {
            contentOffset = boundedOffset(CGPoint(x: center.x * zoomScale - bounds.width / 2,
                y: center.y * zoomScale - bounds.height / 2))
        }
        updateAccessibilityValue()
    }

    private func centerImage() {
        let horizontal = max((bounds.width - imageView.frame.width) / 2, 0)
        let vertical = max((bounds.height - imageView.frame.height) / 2, 0)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if contentInset != inset { contentInset = inset }
    }

    func boundedOffset(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, -contentInset.left), max(-contentInset.left, contentSize.width - bounds.width + contentInset.right)),
            y: min(max(point.y, -contentInset.top), max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)))
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        lockPager()
        onInteractionBegan?()
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { onInteractionBegan?() }
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        if isAtMinimumZoom { unlockPager() }
        updateAccessibilityValue()
        applyPendingFullImage()
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { applyPendingFullImage() }
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { applyPendingFullImage() }

    private func updateAccessibilityValue() {
        imageView.accessibilityValue = "\(Int((zoomScale / max(minimumZoomScale, 0.0001) * 100).rounded()))%"
    }

    @objc private func singleTapped() { onSingleTap?() }
    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onLongPress?()
    }
    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        toggleZoom(at: gesture.location(in: imageView), animated: !UIAccessibility.isReduceMotionEnabled)
    }
    @objc private func accessibilityToggleZoom() -> Bool {
        toggleZoom(at: CGPoint(x: imageView.bounds.midX, y: imageView.bounds.midY), animated: false)
        return true
    }

    func toggleZoom(at point: CGPoint, animated: Bool) {
        guard let image = imageView.image else { return }
        onInteractionBegan?()
        if !isAtMinimumZoom {
            setZoomScale(minimumZoomScale, animated: animated)
        } else {
            lockPager()
            let target = ImageZoomGeometry(imageSize: image.size, viewport: bounds.size).readingScale
            let size = CGSize(width: bounds.width / target, height: bounds.height / target)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                width: size.width, height: size.height), animated: animated)
        }
        if !animated {
            if isAtMinimumZoom { unlockPager() }
            updateAccessibilityValue()
        }
    }

    private func lockPager() {
        guard lockedPager == nil else { return }
        var ancestor = superview
        while let view = ancestor {
            if let pager = view as? UIScrollView, pager.isScrollEnabled {
                lockedPager = pager
                pager.isScrollEnabled = false
                return
            }
            ancestor = view.superview
        }
    }

    private func unlockPager() {
        lockedPager?.isScrollEnabled = true
        lockedPager = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { unlockPager() }
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === dismissPan {
            let velocity = dismissPan.velocity(in: self)
            return isAtMinimumZoom && !isZooming && dismissPan.numberOfTouches == 1
                && velocity.y > abs(velocity.x)
        }
        if gestureRecognizer === longPress {
            return imageView.image != nil && !isZooming && !isDragging && !isDecelerating
        }
        if gestureRecognizer === panGestureRecognizer {
            // At overview scale horizontal drags belong to the surrounding pager;
            // at reading scale the image keeps both axes, including at its edges.
            return imageView.image != nil && !isAtMinimumZoom
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard !(touch.view is UIControl) else { return false }
        if gestureRecognizer === dismissPan {
            // Reject at touch-down while reading, rather than making native image
            // scrolling wait for a second pan recognizer to resolve its direction.
            return imageView.image != nil && isAtMinimumZoom && !isZooming
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === dismissPan,
            let pager = otherGestureRecognizer.view as? UIScrollView,
            pager !== self, isDescendant(of: pager),
            otherGestureRecognizer === pager.panGestureRecognizer else { return false }
        // At overview scale decide down-to-dismiss vs horizontal paging once.
        return true
    }

    @objc private func dragToDismiss(_ gesture: UIPanGestureRecognizer) {
        let distance = max(gesture.translation(in: window).y, 0)
        switch gesture.state {
        case .began:
            onInteractionBegan?()
            onDismissDrag?(distance, false)
        case .changed:
            onDismissDrag?(distance, false)
        case .ended:
            if distance > 120 || distance + gesture.velocity(in: window).y * 0.2 > 170 {
                onDismiss?()
            } else {
                onDismissDrag?(0, true)
            }
        case .cancelled, .failed:
            onDismissDrag?(0, true)
        default: break
        }
    }
}
