//
//  VideoPlayerObserver.swift
//  moro
//
//  Player observer class for managing AVPlayer lifecycle and resources.
//

import AVKit
import Combine
import SwiftUI

/// One configured player and the item it plays.
@MainActor
final class PooledVideoPlayer {
    let url: URL
    let isGIF: Bool
    let loops: Bool
    let player: AVPlayer
    let item: AVPlayerItem
    private var looper: AVPlayerLooper?

    init(url: URL, isGIF: Bool, loops: Bool) {
        self.url = url
        self.isGIF = isGIF
        self.loops = loops
        // Synchronous setup avoids races introduced by asynchronous asset loading.
        let item = AVPlayerItem(url: url)
        self.item = item
        if isGIF || loops {
            // AVQueuePlayer + AVPlayerLooper for looping
            let queuePlayer = AVQueuePlayer(playerItem: item)
            queuePlayer.isMuted = isGIF
            if let templateItem = queuePlayer.items().first {
                looper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)
            }
            player = queuePlayer
        } else {
            let regular = AVPlayer(playerItem: item)
            // Silent until the viewer opens it fullscreen.
            regular.isMuted = true
            regular.actionAtItemEnd = .pause
            player = regular
        }
    }

    var isReusable: Bool {
        player.currentItem != nil && item.status != .failed
    }

    func destroy() {
        looper?.disableLooping()
        looper = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// Audio for video playback. Timeline videos play silently and must never stop the
/// viewer's music, so the app stays in the ambient category; fullscreen video, which the
/// viewer opened on purpose, plays its sound like any video player.
@MainActor
enum VideoAudioSession {
    private static var audibleCount = 0

    /// A fullscreen video is playing with sound.
    static var isAudible: Bool { audibleCount > 0 }

    /// Called when fullscreen video with sound starts.
    static func beginAudiblePlayback() {
        audibleCount += 1
        guard audibleCount == 1 else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }

    /// Called when it ends; other apps' audio (music, podcasts) resumes.
    static func endAudiblePlayback() {
        guard audibleCount > 0 else { return }
        audibleCount -= 1
        guard audibleCount == 0 else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(.ambient)
    }

    /// Silent timeline playback mixes with other audio instead of interrupting it.
    static func prepareForSilentPlayback() {
        guard audibleCount == 0 else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .ambient {
            try? session.setCategory(.ambient)
        }
    }
}

/// Shares players between everything showing the same video — a timeline row and the
/// fullscreen view opened from it — and keeps the last few the user scrolled past,
/// paused, so scrolling back shows the same frame at once and resumes instead of
/// downloading from the start again.
@MainActor
final class TimelineVideoPlayerPool {
    static let shared = TimelineVideoPlayerPool()

    /// Each parked player keeps its buffered data and a decoder, so keep only a few.
    let capacity: Int
    /// Players on screen, with how many views hold each.
    private var active: [(entry: PooledVideoPlayer, holders: Int)] = []
    private var parked: [PooledVideoPlayer] = []
    private var memoryWarningObserver: NSObjectProtocol?

    init(capacity: Int = 3) {
        self.capacity = capacity
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removeAll() }
        }
    }

    var parkedCount: Int { parked.count }
    var activeCount: Int { active.count }

    /// The player for this video and setup: one already on screen, a parked one, or a new one.
    func acquire(url: URL, isGIF: Bool, loops: Bool) -> PooledVideoPlayer {
        let matches = { (entry: PooledVideoPlayer) in
            entry.url == url && entry.isGIF == isGIF && entry.loops == loops
        }
        if let existing = take(where: matches) {
            return existing
        }
        let entry = PooledVideoPlayer(url: url, isGIF: isGIF, loops: loops)
        active.append((entry: entry, holders: 1))
        return entry
    }

    /// The player already showing this video, however it was set up — so fullscreen
    /// continues the timeline video instead of starting a second download.
    func acquireExisting(url: URL) -> PooledVideoPlayer? {
        take { $0.url == url }
    }

    /// One holder is done. When nobody holds the player any more it is paused and parked.
    func release(_ entry: PooledVideoPlayer) {
        guard let index = active.firstIndex(where: { $0.entry === entry }) else { return }
        active[index].holders -= 1
        guard active[index].holders <= 0 else { return }
        active.remove(at: index)
        park(entry)
    }

    func removeAll() {
        parked.forEach { $0.destroy() }
        parked.removeAll()
    }

    private func take(where matches: (PooledVideoPlayer) -> Bool) -> PooledVideoPlayer? {
        if let index = active.firstIndex(where: { matches($0.entry) && $0.entry.isReusable }) {
            active[index].holders += 1
            return active[index].entry
        }
        while let index = parked.firstIndex(where: matches) {
            let entry = parked.remove(at: index)
            if entry.isReusable {
                active.append((entry: entry, holders: 1))
                return entry
            }
            entry.destroy()
        }
        return nil
    }

    private func park(_ entry: PooledVideoPlayer) {
        entry.player.pause()
        guard entry.isReusable else {
            entry.destroy()
            return
        }
        // Only one parked player per video.
        parked.removeAll { existing in
            guard existing.url == entry.url else { return false }
            existing.destroy()
            return true
        }
        parked.append(entry)
        while parked.count > capacity {
            parked.removeFirst().destroy()
        }
    }
}

@MainActor
class VideoPlayerObserver: ObservableObject {
    @Published var playingState: AVPlayer.TimeControlStatus = .paused
    @Published var blurImage: UIImage?

    /// With a pool, the player is shared and parked there when no view holds it any more;
    /// without one it belongs to this observer alone and is released on tear-down.
    private let pool: TimelineVideoPlayerPool?
    /// Fullscreen: continue the player already showing this video, whatever its setup.
    private let continuesExistingPlayer: Bool
    private var entry: PooledVideoPlayer?
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var playerStatusSubscription: AnyCancellable?
    private var playerItemStatusSubscription: AnyCancellable?
    private var notificationObserver: NSObjectProtocol?

    init(pool: TimelineVideoPlayerPool? = nil, continuesExistingPlayer: Bool = false) {
        self.pool = pool
        self.continuesExistingPlayer = continuesExistingPlayer
    }

    func setPlayer(url: URL, isGIF: Bool, shouldLoop: Bool = false) {
        guard self.player == nil else { return }

        let entry: PooledVideoPlayer
        if let pool {
            entry = (continuesExistingPlayer ? pool.acquireExisting(url: url) : nil)
                ?? pool.acquire(url: url, isGIF: isGIF, loops: shouldLoop)
        } else {
            entry = PooledVideoPlayer(url: url, isGIF: isGIF, loops: shouldLoop)
        }
        let _player = entry.player
        let playerItem = entry.item
        self.entry = entry
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
        if !(entry.isGIF || entry.loops) {
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

    /// A video (not a looping GIF) that has played through to its last frame.
    var hasPlayedToEnd: Bool {
        guard let entry, !(entry.isGIF || entry.loops),
              let item = entry.player.currentItem, item.duration.isNumeric else { return false }
        return entry.player.currentTime().seconds >= item.duration.seconds - 0.1
    }

    func play() {
        guard let player else { return }
        // A reused player that already played to the end starts over.
        if let item = player.currentItem, item.duration.isNumeric,
           player.currentTime() >= item.duration {
            player.seek(to: .zero)
        }
        player.play()
    }

    /// GIFs stay silent; they have no sound.
    func setMuted(_ muted: Bool) {
        guard let entry, !entry.isGIF else { return }
        entry.player.isMuted = muted
    }

    func pause() {
        player?.pause()
    }

    /// Release playback resources when the owning view leaves the hierarchy.
    /// Timeline rows can remain cached by SwiftUI after `onDisappear`, so relying
    /// on `deinit` alone keeps decoders, KVO and player items alive unnecessarily.
    /// A shared player goes back to the pool instead, so scrolling back is instant.
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

        if let entry {
            if let pool {
                pool.release(entry)
            } else {
                entry.destroy()
            }
        }
        entry = nil
        player = nil
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

        // Never torn down. A shared player goes back to the pool; one of our own is released.
        if let pool, let entry {
            Task { @MainActor in pool.release(entry) }
        } else {
            player?.pause()
            player?.replaceCurrentItem(with: nil)
        }
    }
}
