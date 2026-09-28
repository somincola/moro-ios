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
    
    init(player: AVPlayer?, videoGravity: AVLayerVideoGravity = .resizeAspectFill) {
        self.player = player
        self.videoGravity = videoGravity
    }
    
    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = videoGravity
        return view
    }
    
    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

class PlayerLayerView: UIView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

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
    }
}

