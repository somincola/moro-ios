//
//  VideoPlayerObserver.swift
//  moro
//
//  Player observer class for managing AVPlayer lifecycle and resources.
//

import AVKit
import Combine
import SwiftUI

@MainActor
class VideoPlayerObserver: ObservableObject {
    @Published var playingState: AVPlayer.TimeControlStatus = .paused
    @Published var blurImage: UIImage?
    
    private var player: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var playerLooper: AVPlayerLooper?
    private var timeObserverToken: Any?
    private var playerStatusSubscription: AnyCancellable?
    private var playerItemStatusSubscription: AnyCancellable?
    private var notificationObserver: NSObjectProtocol?
    
    func setPlayer(url: URL, isGIF: Bool, shouldLoop: Bool = false) {
        guard self.player == nil else { return }
        
        // Synchronous setup avoids races introduced by asynchronous asset loading.
        let playerItem = AVPlayerItem(url: url)
        self.playerItem = playerItem
        
        let _player: AVPlayer
        let needsLooping = isGIF || shouldLoop
        
        if needsLooping {
            // Use AVQueuePlayer + AVPlayerLooper for looping
            let queuePlayer = AVQueuePlayer(playerItem: playerItem)
            queuePlayer.isMuted = isGIF
            _player = queuePlayer
            
            // Setup looper
            if let templateItem = queuePlayer.items().first {
                let looper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)
                self.playerLooper = looper
            }
        } else {
            // Regular video player
            _player = AVPlayer(playerItem: playerItem)
            _player.isMuted = false
            _player.actionAtItemEnd = .pause
        }
        
        self.player = _player
        // Force UI update
        self.objectWillChange.send()
        
        // Observe player time control status
        playerStatusSubscription = _player.publisher(for: \.timeControlStatus, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.playingState = status
            }
        
        // Observe player item status for error handling
        playerItemStatusSubscription = playerItem.publisher(for: \.status, options: [.initial, .new])
            .receive(on: DispatchQueue.main)
            .sink { status in
                switch status {
                case .failed:
                    if let error = playerItem.error {
                        AppLogger.warning(
                            "[VideoPlayerObserver] Player item failed: \(error.localizedDescription)"
                        )
                    }
                case .readyToPlay:
                    break
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        
        // Observe playback end only for non-looping videos
        if !needsLooping {
            notificationObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: playerItem,
                queue: .main
            ) { [weak self] _ in
                let observer = self
                Task { @MainActor [observer] in
                    observer?.playingState = .paused
                }
            }
        }
    }
    
    func getPlayer() -> AVPlayer? {
        return player
    }
    
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }

    /// Release playback resources when the owning view leaves the hierarchy.
    /// Timeline rows can remain cached by SwiftUI after `onDisappear`, so relying
    /// on `deinit` alone keeps decoders, KVO and player items alive unnecessarily.
    func tearDown() {
        playerStatusSubscription?.cancel()
        playerStatusSubscription = nil
        playerItemStatusSubscription?.cancel()
        playerItemStatusSubscription = nil

        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }

        playerLooper?.disableLooping()
        playerLooper = nil

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        playerItem = nil
        blurImage = nil
        playingState = .paused
    }

    deinit {
        playerStatusSubscription?.cancel()
        playerItemStatusSubscription?.cancel()

        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
        }

        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }

        playerLooper?.disableLooping()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }
}
