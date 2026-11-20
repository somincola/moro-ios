import AVKit
import SwiftUI

struct VideoFullscreenView: View {
    @ObservedObject var session: NativeVideoSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @State private var showsControls = true
    @State private var drag: VideoPreviewDrag?
    @State private var dockArmed = false
    @State private var offeredDock = false
    @State private var holdProgress: CGFloat?
    @State private var showsSpeedConfirmation = false
    @State private var exportTask: Task<Void, Never>?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let viewport = geometry.frame(in: .global)
            let target = CGPoint(x: viewport.midX, y: viewport.maxY - VideoPreviewDrag.targetBottomInset - VideoPreviewDrag.targetRadius)
            let canvasHeight = viewport.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let canvasMidY = viewport.midY + (geometry.safeAreaInsets.bottom - geometry.safeAreaInsets.top) / 2
            ZStack {
                Color.black.opacity(1 - 0.8 * (drag?.reveal ?? 0))
                    .ignoresSafeArea()
                VideoPreviewCanvas(session: session, tap: toggleControls, zoomBegan: hideControls,
                                   drag: { distance, finger, state in
                                       updateDrag(VideoPreviewDrag(distance: distance, height: viewport.height,
                                                                   finger: finger, target: target), state: state)
                                   },
                                   speedHold: updateSpeedHold)
                    .ignoresSafeArea()
                    .scaleEffect(reduceMotion ? 1 : (drag?.scale ?? 1))
                    .offset(y: reduceMotion ? 0 : (drag?.pictureOffset(canvasHeight: canvasHeight, canvasMidY: canvasMidY,
                                                                      pictureHeight: session.layer.bounds.height) ?? 0))

                if showsControls, drag == nil {
                    VStack(spacing: 0) {
                        MediaPreviewNavigationBar(close: close, closeIdentifier: "videoPreview.close") {
                            MediaPreviewMoreMenu(post: session.post, attachment: session.attachment,
                                                 isExporting: exportTask != nil, export: export)
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                        Spacer()
                        VStack(spacing: 0) {
                            if let post = session.post {
                                MediaPreviewPostBar(post: post) { export(.share) }
                            }
                            VideoPreviewTransport(session: session, observer: session.observer, expand: hideControls)
                        }
                        .background {
                            LinearGradient(colors: [.clear, .black.opacity(0.78), .black.opacity(0.9)],
                                           startPoint: .top, endPoint: .bottom)
                                .padding(.top, -40).ignoresSafeArea()
                                .allowsHitTesting(false)
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                }

                if drag == nil && (holdProgress != nil || showsSpeedConfirmation) {
                    VideoSpeedBadge(progress: holdProgress, locked: showsSpeedConfirmation, unlock: session.unlockSpeed)
                        .padding(.top, 6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }

                if session.canDock {
                    Image(systemName: "pip.enter")
                        .font(.system(size: 22, weight: .medium))
                        .frame(width: 2 * VideoPreviewDrag.targetRadius, height: 2 * VideoPreviewDrag.targetRadius)
                        .background(.black.opacity(0.72), in: Circle())
                        .overlay {
                            Circle().trim(from: 0, to: dockArmed ? 1 : (drag?.approachProgress ?? 0))
                                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: dockArmed)
                        }
                        .foregroundStyle(.white)
                        .opacity(drag?.offersPiP == true ? 1 : 0)
                        .position(x: target.x - viewport.minX, y: target.y - viewport.minY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if let notice {
                    Text(notice).font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .padding(10).background(.black.opacity(0.83), in: Capsule())
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 110)
                        .allowsHitTesting(false).accessibilityIdentifier("videoPreview.notice")
                }
            }
        }
        .statusBarHidden()
        .modifier(MediaPreviewPostSheets(post: session.post, video: session))
        .onAppear {
            if session.host == nil { session.dismissRoute = { [dismiss] in dismiss() } }
            session.startIfNeeded()
        }
        .onDisappear {
            exportTask?.cancel()
            noticeTask?.cancel()
            session.finishSpeedHold(completedDrag: false)
            holdProgress = nil
            showsSpeedConfirmation = false
            if session.host == nil { session.leftFullscreen() }
        }
        .onChange(of: voiceOver || switchControl) { _, enabled in if enabled { showsControls = true } }
        .onChange(of: session.pipFailed) { _, failed in
            if failed {
                resetDrag()
                showNotice(MoroL10n.VideoPreview.pipUnavailable)
            }
        }
        .accessibilityAction(.escape, close)
        .onChange(of: session.isSpeedLocked) { _, locked in
            if !locked { showsSpeedConfirmation = false }
        }
        .task(id: showsSpeedConfirmation) {
            guard showsSpeedConfirmation else { return }
            try? await Task.sleep(for: .milliseconds(1600))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { showsSpeedConfirmation = false }
        }
    }

    private func toggleControls() {
        guard !voiceOver, !switchControl else { return }
        showsControls.toggle()
        if !showsControls { showsSpeedConfirmation = false }
    }

    private func hideControls() {
        guard !voiceOver, !switchControl else { return }
        showsControls = false
        showsSpeedConfirmation = false
    }

    private func close() {
        if let host = session.host { host.close() } else { dismiss() }
    }

    private func updateDrag(_ sample: VideoPreviewDrag, state: UIGestureRecognizer.State) {
        switch state {
        case .began, .changed, .ended:
            drag = sample
            dockArmed = sample.isInDockRange(wasArmed: dockArmed)
            if sample.offersPiP && session.canDock { offeredDock = true }
            guard state == .ended else { return }
            if dockArmed && offeredDock {
                // Let AVKit take over the shrunken frame on success. A failed request restores it.
                if session.startPictureInPicture() { return }
                showNotice(MoroL10n.VideoPreview.pipUnavailable)
            } else if sample.closes {
                close()
                return
            }
            resetDrag()
        case .failed, .cancelled:
            resetDrag()
        default: break
        }
    }

    private func resetDrag() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.23)) {
            drag = nil
            dockArmed = false
            offeredDock = false
        }
    }

    private func updateSpeedHold(_ distance: CGFloat?, ended: Bool) {
        let progress = min(1, (distance ?? 0) / 72)
        if ended {
            let completed = distance != nil && progress >= 1
            session.finishSpeedHold(completedDrag: completed)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                holdProgress = nil
                showsSpeedConfirmation = completed && session.isSpeedLocked
            }
        } else {
            session.beginSpeedHold()
            showsSpeedConfirmation = false
            holdProgress = progress
        }
    }

    private func export(_ action: MediaExportAction) {
        guard exportTask == nil else { return }
        exportTask = Task {
            defer { exportTask = nil }
            do {
                if let message = try await action.perform(on: session.attachment) { showNotice(message) }
            } catch is CancellationError {
            } catch { showNotice(MediaExportService.message(for: error)) }
        }
    }

    private func showNotice(_ message: String) {
        noticeTask?.cancel()
        notice = message
        UIAccessibility.post(notification: .announcement, argument: message)
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { notice = nil }
        }
    }
}

/// One centered shape expands around the same text when the user releases a completed hold.
private struct VideoSpeedBadge: View {
    let progress: CGFloat?
    let locked: Bool
    let unlock: () -> Void
    @ScaledMetric(relativeTo: .subheadline) private var diameter: CGFloat = 40
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: unlock) {
            HStack(spacing: 5) {
                if locked {
                    Image(systemName: "lock.fill")
                        .transition(.opacity)
                }
                Text(verbatim: "2×").monospacedDigit()
            }
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .fixedSize()
            .frame(width: locked ? diameter * 1.85 : diameter, height: diameter)
            .background(Color(white: contrast == .increased ? 0.12 : 0.22).opacity(contrast == .increased ? 1 : 0.80), in: Capsule())
            .overlay {
                if let progress {
                    Circle().inset(by: 1).trim(from: 0, to: progress)
                        .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(locked)
        .accessibilityHidden(!locked)
        .accessibilityLabel(MoroL10n.VideoPreview.unlockSpeed)
        .accessibilityIdentifier("videoPreview.speedLock")
    }
}

struct VideoPreviewDrag {
    static let targetRadius: CGFloat = 30
    static let targetBottomInset: CGFloat = 16
    let distance: CGFloat
    let height: CGFloat
    let finger: CGPoint
    let target: CGPoint

    private var startGap: CGFloat { max(0, target.y - finger.y + distance) }
    private var offerDistance: CGFloat { min(height * 0.24, max(50, startGap * 0.47)) }
    private var captureRadius: CGFloat { min(92, max(52, height * 0.115)) }
    private var remainingGap: CGFloat {
        let horizontal = max(0, abs(finger.x - target.x) - Self.targetRadius)
        return hypot(horizontal, max(0, target.y - finger.y))
    }

    var closes: Bool { distance >= min(height * 0.13, max(32, startGap * 0.30)) }
    var offersPiP: Bool { distance >= offerDistance }
    var reveal: CGFloat {
        let travel = min(height * 0.45, max(offerDistance, startGap - captureRadius))
        return min(1, distance / max(1, travel))
    }
    private var dockScale: CGFloat { min(0.65, max(0.50, 1 - 128 / max(1, height))) }
    var scale: CGFloat { 1 - (1 - dockScale) * reveal }

    /// Show a small lead-in. Crossing the capture radius fills the remaining arc even with a stationary finger.
    var approachProgress: CGFloat {
        guard offersPiP else { return 0 }
        let gapAtReveal = startGap - offerDistance
        let approach = min(1, max(0, (gapAtReveal - remainingGap) / max(1, gapAtReveal - captureRadius)))
        return 0.55 * approach * approach
    }

    func isInDockRange(wasArmed: Bool) -> Bool {
        offersPiP && remainingGap <= captureRadius + (wasArmed ? 18 : 0)
    }

    func pictureOffset(canvasHeight: CGFloat, canvasMidY: CGFloat, pictureHeight: CGFloat) -> CGFloat {
        let fittedHeight = pictureHeight > 0 ? min(pictureHeight, canvasHeight) : canvasHeight
        let lift = VideoViewport.pictureLift(viewportHeight: canvasHeight, pictureHeight: fittedHeight)
        let bottomAtDockScale = canvasMidY + (fittedHeight / 2 - lift) * dockScale
        // Follow the finger initially, then ease out so the bottom of the video leaves the target visible.
        let room = target.y - Self.targetRadius - 12 - bottomAtDockScale
        // In a short landscape viewport the fitted picture can already reach the target.
        if room <= 0 { return room * reveal }
        let freeTravel = room / 2
        let extra = max(0, distance - freeTravel)
        return min(distance, freeTravel) + freeTravel * extra / max(1, freeTravel + extra)
    }
}
