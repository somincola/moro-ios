import AVKit
import SwiftUI

struct VideoPreviewTransport: View {
    @ObservedObject var session: NativeVideoSession
    @ObservedObject var observer: VideoPlayerObserver
    let expand: () -> Void
    @State private var playbackTime: Double = 0
    @State private var scrubFraction: Double?
    @State private var resumeAfterScrub = false

    var body: some View {
        let player = session.player
        let seconds = player?.currentItem?.duration.seconds ?? 0
        let duration = seconds.isFinite && seconds > 0 ? seconds : 0
        let current = playbackTime
        let fraction = scrubFraction ?? (duration > 0 && current.isFinite ? max(0, min(1, current / duration)) : 0)
        VStack(spacing: 0) {
            if observer.didFail {
                Button(MoroL10n.ContentState.retry, systemImage: "arrow.clockwise", action: session.retry)
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.35))
                    Capsule().fill(.white).frame(width: proxy.size.width * fraction)
                }
                .frame(height: scrubFraction == nil ? 2 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    guard duration > 0 else { return }
                    if scrubFraction == nil {
                        resumeAfterScrub = observer.isPlaybackActive
                        observer.pause()
                    }
                    let next = max(0, min(1, value.location.x / max(1, proxy.size.width)))
                    scrubFraction = next
                    seek(next * duration, precise: false)
                }.onEnded { value in
                    guard scrubFraction != nil else { return }
                    let next = max(0, min(1, value.location.x / max(1, proxy.size.width)))
                    seek(next * duration, precise: true)
                    finishScrubbing()
                })
            }
            .frame(height: 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(MoroL10n.VideoPreview.position)
            .accessibilityValue(time(fraction * duration))
            .accessibilityAdjustableAction { direction in
                guard duration > 0 else { return }
                seek(min(duration, max(0, current + (direction == .increment ? 10 : -10))), precise: true)
            }
            .accessibilityIdentifier("videoPreview.scrubber")

            HStack(spacing: 0) {
                icon(observer.isPlaybackActive ? "pause.fill" : "play.fill",
                     observer.isPlaybackActive ? MoroL10n.A11y.pause : MoroL10n.A11y.play,
                     id: "play", action: session.togglePlayback)
                Text(duration > 0 ? "−" + time(duration * (1 - fraction)) : "–:––")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.72))
                    .accessibilityHidden(true)
                Spacer(minLength: 2)
                Button(action: session.cycleRate) {
                    Text(session.selectedRate.formatted(.number.precision(.fractionLength(0...2))) + "×")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(MoroL10n.VideoPreview.speed)
                .accessibilityValue(session.selectedRate.formatted() + "×")
                .accessibilityActions {
                    if session.isSpeedLocked {
                        Button(MoroL10n.VideoPreview.unlockSpeed, action: session.unlockSpeed)
                    }
                }
                .accessibilityIdentifier("videoPreview.rate")
                if !session.isGIF {
                    icon(session.isMuted ? "speaker.slash" : "speaker.wave.2",
                         session.isMuted ? MoroL10n.VideoPreview.soundOn : MoroL10n.VideoPreview.soundOff,
                         id: "sound", action: session.toggleMute)
                    MediaRoutePicker().frame(width: 44, height: 44)
                }
                icon("arrow.up.left.and.arrow.down.right", MoroL10n.VideoPreview.immersive,
                     id: "expand", action: expand)
                if !session.isGIF && AVPictureInPictureController.isPictureInPictureSupported() {
                    icon("pip.enter", MoroL10n.VideoPreview.pip, id: "pip", action: session.startPictureInPicture)
                        .disabled(!session.canDock)
                        .opacity(session.canDock ? 1 : 0.4)
                }
            }
        }
        .padding(.horizontal, 12)
        .foregroundStyle(.white)
        .task(id: player.map(ObjectIdentifier.init)) {
            guard let player else { return }
            let (ticks, continuation) = AsyncStream<Double>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let token = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { time in
                if time.isNumeric { continuation.yield(time.seconds) }
            }
            defer {
                player.removeTimeObserver(token)
                continuation.finish()
            }
            for await seconds in ticks { playbackTime = seconds }
        }
        .onDisappear { if scrubFraction != nil { finishScrubbing() } }
    }

    private func finishScrubbing() {
        scrubFraction = nil
        if resumeAfterScrub { observer.play() }
        resumeAfterScrub = false
    }

    private func seek(_ seconds: Double, precise: Bool) {
        observer.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), precise: precise)
    }

    private func time(_ seconds: Double) -> String {
        let value = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }

    private func icon(_ symbol: String, _ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("videoPreview." + id)
    }
}

private struct MediaRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = .white
        picker.activeTintColor = .systemBlue
        picker.prioritizesVideoDevices = true
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
