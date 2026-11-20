import AVKit
import SwiftUI

struct VideoFullscreenView: View {
    @ObservedObject var session: NativeVideoSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @State private var showsControls = true
    @State private var dragDistance: CGFloat = 0
    @State private var offeredDock = false
    @State private var holdProgress: CGFloat?
    @State private var exportMenu = false
    @State private var exportTask: Task<Void, Never>?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let progress = VideoPreviewDrag(distance: dragDistance, height: height)
            ZStack {
                Color.black.opacity(1 - 0.8 * progress.reveal)
                    .ignoresSafeArea()
                VideoPreviewCanvas(session: session, tap: toggleControls, zoomBegan: hideControls,
                                   drag: { updateDrag($0, ended: $1, cancelled: $2, height: height) },
                                   speedHold: updateSpeedHold, gifActions: { exportMenu = true })
                    .ignoresSafeArea()
                    .scaleEffect(reduceMotion ? 1 : 1 - 0.35 * progress.reveal)
                    .offset(y: reduceMotion ? 0 : dragDistance)

                if showsControls, dragDistance == 0 {
                    VStack(spacing: 0) {
                        HStack {
                            MoroFloatingNavButton(kind: .close, action: close)
                                .accessibilityIdentifier("videoPreview.close")
                            Spacer()
                            if let post = session.post {
                                MediaPreviewMoreMenu(post: post)
                            } else {
                                Button { export(.share) } label: {
                                    FloatingNavIconLabel(systemName: "square.and.arrow.up")
                                        .frame(width: 44, height: 44)
                                }
                                .contextMenu {
                                    ForEach(MediaExportAction.available(for: session.attachment), id: \.self) { action in
                                        Button(action.title, systemImage: action.systemImage) { export(action) }
                                    }
                                }
                                .accessibilityLabel(MoroL10n.MediaExport.share)
                                .accessibilityIdentifier("videoPreview.share")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                        Spacer()
                        VStack(spacing: 0) {
                            if let post = session.post {
                                MediaPreviewPostBar(post: post, attachment: session.attachment, export: export)
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

                if holdProgress != nil || (session.isSpeedLocked && showsControls && dragDistance == 0) {
                    VStack {
                        Button { session.unlockSpeed() } label: {
                            HStack(spacing: 5) {
                                if session.isSpeedLocked { Image(systemName: "lock.fill") }
                                Text("2×").monospacedDigit()
                            }
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .frame(minWidth: 44, minHeight: 36)
                            .contentShape(Rectangle())
                            .background(.black.opacity(0.64), in: Capsule())
                            .overlay {
                                if let holdProgress {
                                    Capsule().trim(from: 0, to: holdProgress).stroke(.white, lineWidth: 2)
                                }
                            }
                        }
                        .foregroundStyle(.white)
                        .accessibilityLabel(MoroL10n.VideoPreview.unlockSpeed)
                        .accessibilityIdentifier("videoPreview.speedLock")
                        .padding(.top, 8)
                        Spacer()
                    }
                    .allowsHitTesting(session.isSpeedLocked)
                }

                if session.canDock && progress.offersPiP {
                    VStack {
                        Spacer()
                        Image(systemName: "pip.enter")
                            .font(.system(size: 22, weight: .medium))
                            .frame(width: 60, height: 60)
                            .background(.black.opacity(0.72), in: Circle())
                            .overlay {
                                Circle().trim(from: 0, to: progress.dock)
                                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                            }
                            .foregroundStyle(.white)
                            .padding(.bottom, 16)
                    }
                    .allowsHitTesting(false)
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
        .onAppear {
            if session.host == nil { session.dismissRoute = { [dismiss] in dismiss() } }
            session.startIfNeeded()
        }
        .onDisappear {
            exportTask?.cancel()
            noticeTask?.cancel()
            session.finishSpeedHold(lock: false)
            if session.host == nil { session.leftFullscreen() }
        }
        .onChange(of: voiceOver || switchControl) { _, enabled in if enabled { showsControls = true } }
        .onChange(of: session.pipFailed) { _, failed in if failed { showNotice(MoroL10n.VideoPreview.pipUnavailable) } }
        .accessibilityAction(.escape, close)
        .confirmationDialog("", isPresented: $exportMenu, titleVisibility: .hidden) {
            ForEach(MediaExportAction.available(for: session.attachment), id: \.self) { action in
                Button(action.title) { export(action) }
            }
        }
    }

    private func toggleControls() {
        guard !voiceOver, !switchControl else { return }
        showsControls.toggle()
    }

    private func hideControls() {
        if !voiceOver && !switchControl { showsControls = false }
    }

    private func close() {
        if let host = session.host { host.close() } else { dismiss() }
    }

    private func updateDrag(_ distance: CGFloat, ended: Bool, cancelled: Bool, height: CGFloat) {
        let progress = VideoPreviewDrag(distance: distance, height: height)
        guard ended else {
            dragDistance = distance
            if progress.offersPiP, session.canDock { offeredDock = true }
            return
        }
        defer { offeredDock = false }
        if !cancelled, progress.dock >= 1, offeredDock || session.canDock {
            if session.canDock { session.startPictureInPicture() }
            else { showNotice(MoroL10n.VideoPreview.pipUnavailable) }
        } else if !cancelled, progress.closes {
            close()
            return
        }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.23)) { dragDistance = 0 }
    }

    private func updateSpeedHold(_ distance: CGFloat?, ended: Bool) {
        let progress = min(1, (distance ?? 0) / 72)
        if ended {
            session.finishSpeedHold(lock: distance != nil && progress >= 1)
            holdProgress = nil
        } else if !session.isSpeedLocked {
            session.beginSpeedHold()
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

struct VideoPreviewDrag {
    let distance: CGFloat
    let height: CGFloat
    private var extent: CGFloat { max(1, height) }
    var reveal: CGFloat { min(1, max(0, distance / (extent * 0.45))) }
    var closes: Bool { distance >= extent * 0.13 }
    var offersPiP: Bool { distance >= extent * 0.27 }
    var dock: CGFloat { min(1, max(0, (distance - extent * 0.27) / (extent * 0.16))) }
}
