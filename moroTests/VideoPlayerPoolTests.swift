import AVKit
import Foundation
import SwiftUI
import Testing
@testable import moro

@MainActor
struct VideoPlayerPoolTests {
    /// An address that never answers within a test, so the item stays loading. (A missing
    /// local file fails within milliseconds, and a failed player is rightly never reused.)
    private func url(_ name: String) -> URL {
        URL(string: "https://10.255.255.1/moro-pool-\(name)-\(UUID().uuidString).mp4")!
    }

    @Test func scrollingBackToAVideoReusesItsPlayer() {
        let pool = TimelineVideoPlayerPool(capacity: 3)
        let video = url("a")
        let first = VideoPlayerObserver(pool: pool)
        first.setPlayer(url: video, isGIF: false)
        let player = first.getPlayer()

        // The row scrolls away: the player is parked, paused, not destroyed.
        first.tearDown()
        #expect(first.getPlayer() == nil)
        #expect(pool.parkedCount == 1)
        #expect(player?.currentItem != nil)

        // The row comes back: same player, so its frame and position are still there.
        let second = VideoPlayerObserver(pool: pool)
        second.setPlayer(url: video, isGIF: false)
        #expect(second.getPlayer() === player)
        #expect(pool.parkedCount == 0)
        second.tearDown()
    }

    @Test func fullscreenContinuesTheTimelinePlayer() {
        let pool = TimelineVideoPlayerPool(capacity: 3)
        let video = url("shared")
        let row = VideoPlayerObserver(pool: pool)
        row.setPlayer(url: video, isGIF: true)
        let player = row.getPlayer()

        // Fullscreen opens the same address as a plain video, and still gets the row's player.
        let fullscreen = VideoPlayerObserver(pool: pool, continuesExistingPlayer: true)
        fullscreen.setPlayer(url: video, isGIF: false)
        #expect(fullscreen.getPlayer() === player)

        // The row scrolling away behind fullscreen doesn't stop it.
        row.tearDown()
        #expect(pool.activeCount == 1)
        #expect(pool.parkedCount == 0)

        // Closing fullscreen parks it for the row to pick up again.
        fullscreen.tearDown()
        #expect(pool.parkedCount == 1)
        let rowAgain = VideoPlayerObserver(pool: pool)
        rowAgain.setPlayer(url: video, isGIF: true)
        #expect(rowAgain.getPlayer() === player)
        rowAgain.tearDown()
    }

    @Test func fullscreenWithoutATimelinePlayerMakesItsOwn() {
        let pool = TimelineVideoPlayerPool(capacity: 3)
        let fullscreen = VideoPlayerObserver(pool: pool, continuesExistingPlayer: true)
        fullscreen.setPlayer(url: url("alone"), isGIF: false)
        #expect(fullscreen.getPlayer() != nil)
        #expect(pool.activeCount == 1)
        fullscreen.tearDown()
        #expect(pool.activeCount == 0)
    }

    @Test func onlyTheMostRecentVideosAreKept() {
        let pool = TimelineVideoPlayerPool(capacity: 2)
        let urls = [url("1"), url("2"), url("3")]
        var players: [AVPlayer] = []
        for video in urls {
            let entry = pool.acquire(url: video, isGIF: false, loops: false)
            players.append(entry.player)
            pool.release(entry)
        }
        #expect(pool.parkedCount == 2)
        // The oldest was released; the newer two come back as they were.
        #expect(players[0].currentItem == nil)
        #expect(pool.acquire(url: urls[0], isGIF: false, loops: false).player !== players[0])
        #expect(pool.acquire(url: urls[2], isGIF: false, loops: false).player === players[2])
    }

    @Test func aGIFAndAVideoAtTheSameAddressAreNotMixedUpInTheTimeline() {
        let pool = TimelineVideoPlayerPool(capacity: 3)
        let video = url("same")
        let gif = pool.acquire(url: video, isGIF: true, loops: false)
        pool.release(gif)
        let regular = pool.acquire(url: video, isGIF: false, loops: false)
        #expect(regular.player !== gif.player)
    }

    @Test func playersWithoutAPoolAreReleased() {
        let observer = VideoPlayerObserver()
        observer.setPlayer(url: url("own"), isGIF: false)
        let player = observer.getPlayer()
        observer.tearDown()
        #expect(player?.currentItem == nil)
    }

    @Test func aMemoryWarningEmptiesThePool() {
        let pool = TimelineVideoPlayerPool(capacity: 3)
        let entry = pool.acquire(url: url("memory"), isGIF: false, loops: false)
        pool.release(entry)
        NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        #expect(pool.parkedCount == 0)
        #expect(entry.player.currentItem == nil)
    }

    @Test func aVideoThatHasNotPlayedIsNotFinished() {
        // Autoplay skips a video only once it has really reached its end.
        let pool = TimelineVideoPlayerPool(capacity: 3)
        let video = VideoPlayerObserver(pool: pool)
        #expect(!video.hasPlayedToEnd)
        video.setPlayer(url: url("fresh"), isGIF: false)
        #expect(!video.hasPlayedToEnd)
        video.tearDown()

        let gif = VideoPlayerObserver(pool: pool)
        gif.setPlayer(url: url("gif"), isGIF: true)
        #expect(!gif.hasPlayedToEnd)
        gif.tearDown()
    }

    @Test func timelineVideosAreSilentAndFullscreenHasSound() {
        let pool = TimelineVideoPlayerPool(capacity: 3)
        let video = url("sound")
        let row = VideoPlayerObserver(pool: pool)
        row.setPlayer(url: video, isGIF: false)
        #expect(row.getPlayer()?.isMuted == true)

        let fullscreen = VideoPlayerObserver(pool: pool, continuesExistingPlayer: true)
        fullscreen.setPlayer(url: video, isGIF: false)
        fullscreen.setMuted(false)
        VideoAudioSession.beginAudiblePlayback()
        #expect(row.getPlayer()?.isMuted == false)
        #expect(VideoAudioSession.isAudible)
        #expect(AVAudioSession.sharedInstance().category == .playback)

        fullscreen.setMuted(true)
        VideoAudioSession.endAudiblePlayback()
        #expect(!VideoAudioSession.isAudible)
        // Back to mixing with other apps' audio.
        #expect(AVAudioSession.sharedInstance().category == .ambient)
        #expect(row.getPlayer()?.isMuted == true)
        fullscreen.tearDown()
        row.tearDown()
    }

    @Test func timelineVideosUseTheirOwnShape() {
        // A portrait video (590×1282) gets a tall box instead of a fixed 280pt crop.
        let attachment = try? JSONDecoder().decode(Status.Attachment.self, from: Data("""
            {"id":"v","type":"gifv","url":"https://example.com/v.mp4","preview_url":"https://example.com/v.png",
             "meta":{"small":{"width":590,"height":1282,"aspect":0.46}}}
            """.utf8))
        let ratio = attachment.map { MediaGridLayoutMetrics.singleImageAspectRatio(for: $0) }
        #expect(ratio.map { abs($0 - 0.46) < 0.001 } == true)
    }
}
