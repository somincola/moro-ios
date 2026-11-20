import AVFoundation
import SwiftUI
import UIKit

/// The player layer only draws video. All playback controls live outside this surface.
struct VideoPreviewCanvas: UIViewRepresentable {
    let session: NativeVideoSession
    let tap: () -> Void
    let zoomBegan: () -> Void
    let drag: (CGFloat, Bool, Bool) -> Void
    let speedHold: (CGFloat?, Bool) -> Void

    func makeUIView(context: Context) -> VideoViewport {
        VideoViewport(session: session)
    }

    func updateUIView(_ view: VideoViewport, context: Context) {
        view.tap = tap
        view.zoomBegan = zoomBegan
        view.drag = drag
        view.speedHold = speedHold
    }
}

final class VideoViewport: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var tap: (() -> Void)?
    var zoomBegan: (() -> Void)?
    var drag: ((CGFloat, Bool, Bool) -> Void)?
    var speedHold: ((CGFloat?, Bool) -> Void)?

    private let session: NativeVideoSession
    private let picture = UIView()
    private let dismissPan = UIPanGestureRecognizer()
    private let hold = UILongPressGestureRecognizer()
    private var holdOrigin: CGFloat = 0
    private var layoutSize: CGSize = .zero
    private var videoAspect: CGFloat = 0
    private var sizeObservation: NSKeyValueObservation?

    init(session: NativeVideoSession) {
        self.session = session
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .clear
        minimumZoomScale = 1
        maximumZoomScale = 5
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        panGestureRecognizer.minimumNumberOfTouches = 2
        picture.layer.addSublayer(session.layer)
        addSubview(picture)
        accessibilityLabel = session.attachment.description ?? MoroL10n.A11y.videoPlayer
        accessibilityTraits = .image
        accessibilityIdentifier = "videoPreview.canvas"
        accessibilityValue = "100%"
        isAccessibilityElement = true

        let single = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(single)
        dismissPan.addTarget(self, action: #selector(dragged))
        dismissPan.maximumNumberOfTouches = 1
        dismissPan.delegate = self
        addGestureRecognizer(dismissPan)
        hold.addTarget(self, action: #selector(held))
        hold.minimumPressDuration = 0.34
        hold.allowableMovement = 9
        hold.delegate = self
        addGestureRecognizer(hold)
        // Early movement fails the stationary hold; a recognized hold owns the touch until release.
        dismissPan.require(toFail: hold)
        single.require(toFail: hold)
        sizeObservation = session.layer.observe(\.videoRect, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in self?.setNeedsLayout() }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    nonisolated deinit {}

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let size = session.player?.currentItem?.presentationSize ?? .zero
        let aspect = size.width > 0 && size.height > 0 ? size.width / size.height :
            CGFloat(session.attachment.previewAspectRatio ?? 16.0 / 9.0)
        guard bounds.size != layoutSize || aspect != videoAspect else { return }
        layoutSize = bounds.size
        videoAspect = aspect
        setZoomScale(1, animated: false)
        let rect = AVMakeRect(aspectRatio: CGSize(width: aspect, height: 1), insideRect: CGRect(origin: .zero, size: layoutSize))
        picture.frame = CGRect(origin: .zero, size: rect.size)
        contentSize = rect.size
        if session.layer.superlayer === picture.layer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            session.layer.frame = picture.bounds
            CATransaction.commit()
        }
        centerPicture()
    }

    private func centerPicture() {
        let horizontal = max(0, (bounds.width - contentSize.width) / 2)
        let vertical = max(0, (bounds.height - contentSize.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { picture }
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) { zoomBegan?() }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        panGestureRecognizer.minimumNumberOfTouches = zoomScale > 1.01 ? 1 : 2
        accessibilityValue = "\(Int((zoomScale * 100).rounded()))%"
        centerPicture()
    }

    override func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        if recognizer === dismissPan {
            let velocity = dismissPan.velocity(in: window)
            return zoomScale <= 1.01 && velocity.y > abs(velocity.x)
        }
        if recognizer === hold { return zoomScale <= 1.01 || session.isSpeedLocked }
        return super.gestureRecognizerShouldBegin(recognizer)
    }

    @objc private func tapped() { tap?() }
    @objc private func dragged() {
        let distance = max(0, dismissPan.translation(in: window).y)
        switch dismissPan.state {
        case .began, .changed: drag?(distance, false, false)
        case .ended: drag?(distance, true, false)
        case .cancelled, .failed: drag?(0, true, true)
        default: break
        }
    }

    @objc private func held() {
        let y = hold.location(in: window).y
        switch hold.state {
        case .began:
            holdOrigin = y
            speedHold?(0, false)
        case .changed: speedHold?(max(0, y - holdOrigin), false)
        case .ended: speedHold?(max(0, y - holdOrigin), true)
        case .cancelled, .failed: speedHold?(nil, true)
        default: break
        }
    }
}
