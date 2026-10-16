//
//  AVPlayerLayerView.swift
//  moro
//
//  Custom AVPlayerLayer wrapper that doesn't affect status bar.
//  Alternative to SwiftUI VideoPlayer for timeline autoplay.
//

import SwiftUI
import AVKit

struct AVPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer?
    let videoGravity: AVLayerVideoGravity
    /// Called when the layer starts (or stops) having a video frame to show. Until then
    /// the layer is empty, so callers keep the poster image visible.
    var onReadyForDisplayChange: ((Bool) -> Void)? = nil

    init(
        player: AVPlayer?,
        videoGravity: AVLayerVideoGravity = .resizeAspectFill,
        onReadyForDisplayChange: ((Bool) -> Void)? = nil
    ) {
        self.player = player
        self.videoGravity = videoGravity
        self.onReadyForDisplayChange = onReadyForDisplayChange
    }

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = videoGravity
        view.onReadyForDisplayChange = onReadyForDisplayChange
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.onReadyForDisplayChange = onReadyForDisplayChange
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

class PlayerLayerView: UIView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    var onReadyForDisplayChange: ((Bool) -> Void)?
    private var readyObservation: NSKeyValueObservation?

    var playerLayer: AVPlayerLayer {
        return layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        playerLayer.videoGravity = .resizeAspectFill
        readyObservation = playerLayer.observe(\.isReadyForDisplay, options: [.initial, .new]) {
            [weak self] layer, _ in
            let isReady = layer.isReadyForDisplay
            DispatchQueue.main.async {
                self?.onReadyForDisplayChange?(isReady)
            }
        }
    }
}
