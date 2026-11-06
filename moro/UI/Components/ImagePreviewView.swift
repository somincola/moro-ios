// Fullscreen image reading with optional, on-demand image descriptions.

import SwiftUI

struct ImagePreviewView: View {
    let attachments: [Status.Attachment]
    let initialIndex: Int
    var onDismiss: (() -> Void)? = nil

    @State private var currentIndex: Int
    @State private var altPresentation: AltPresentation?
    @State private var showsControls = true
    @State private var viewportHeight: CGFloat = 0
    @State private var actionTarget: Status.Attachment?
    @State private var isExporting = false
    @State private var exportNotice: String?
    @State private var noticeTask: Task<Void, Never>?
    /// iPhone Duo half open like a laptop: the fold across the screen, in screen space. The
    /// image then stays above it and the controls move below it, onto the flat half.
    @State private var tabletopFold: CGRect?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct AltPresentation: Identifiable {
        let id: String
        let text: String
    }

    init(attachments: [Status.Attachment], initialIndex: Int = 0, onDismiss: (() -> Void)? = nil) {
        self.attachments = attachments
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        _currentIndex = State(initialValue: min(max(initialIndex, 0), max(attachments.count - 1, 0)))
    }

    private var currentAttachment: Status.Attachment? {
        guard attachments.indices.contains(currentIndex) else { return nil }
        return attachments[currentIndex]
    }

    private var currentAltText: String? { Self.descriptionText(currentAttachment?.description) }

    static func descriptionText(_ raw: String?) -> String? {
        guard let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if attachments.isEmpty {
                    Text(MoroL10n.ImagePreview.emptyState)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                            ZoomableImageView(
                                url: attachment.url,
                                previewURL: attachment.previewURL,
                                altText: Self.descriptionText(attachment.description),
                                onSingleTap: toggleControls,
                                onInteractionBegan: hideControls,
                                onDismiss: closePreview,
                                onLongPress: { actionTarget = attachment }
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: tabletopFold?.minY)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                }
            }

            if showsControls {
                VStack {
                    if tabletopFold != nil { Spacer() }
                    HStack(spacing: 12) {
                        MoroFloatingNavButton(kind: .close, action: closePreview)
                            .accessibilityIdentifier("imagePreview.close")
                        Spacer()
                        if attachments.count > 1 {
                            Text("\(currentIndex + 1) / \(attachments.count)")
                                .moroScaledFont(size: 15, weight: .medium)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 44)
                                .background(.black.opacity(0.55), in: Capsule())
                                .accessibilityIdentifier("imagePreview.page")
                        }
                        if let currentAltText, let currentAttachment {
                            Button {
                                altPresentation = AltPresentation(id: currentAttachment.id, text: currentAltText)
                            } label: {
                                Text(MoroL10n.ImagePreview.altBadge)
                                    .moroScaledFont(size: 13, weight: .bold)
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(.black.opacity(0.55), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(MoroL10n.ImagePreview.altAccessibility)
                            .accessibilityIdentifier("imagePreview.alt")
                        }
                        if let currentAttachment {
                            Button {
                                run(.share, on: currentAttachment)
                            } label: {
                                ZStack {
                                    FloatingNavIconLabel(systemName: "square.and.arrow.up")
                                        .opacity(isExporting ? 0 : 1)
                                    if isExporting {
                                        ProgressView()
                                            .tint(.white)
                                            .frame(width: 34, height: 34)
                                            .background(Circle().fill(.black.opacity(0.4)))
                                    }
                                }
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(isExporting)
                            .accessibilityLabel(MoroL10n.ImagePreview.shareAccessibility)
                            .accessibilityIdentifier("imagePreview.share")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, tabletopFold == nil ? 0 : 16)
                    if tabletopFold == nil { Spacer() }
                }
            }

            // Transient result; sits above the home indicator and fades, so it
            // never parks over the image the way a fixed bottom bar would.
            if let exportNotice {
                VStack {
                    Spacer()
                    Text(exportNotice)
                        .moroScaledFont(size: 15, weight: .medium)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.7), in: Capsule())
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                        .accessibilityIdentifier("imagePreview.notice")
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: exportNotice)
        .animation(.easeInOut(duration: 0.25), value: tabletopFold)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { tabletopFold = Self.tabletopFold(in: proxy) }
                    .onChange(of: proxy.size) { _, _ in tabletopFold = Self.tabletopFold(in: proxy) }
                    .modifier(HingeChangeObserver {
                        // The fold's region updates with the layout that follows the hinge.
                        DispatchQueue.main.async { tabletopFold = Self.tabletopFold(in: proxy) }
                    })
            }
            .ignoresSafeArea()
        }
        .statusBar(hidden: true)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            if UIAccessibility.isVoiceOverRunning { showsControls = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            if UIAccessibility.isSwitchControlRunning { showsControls = true }
        }
        .accessibilityAction(.escape, closePreview)
        .onChange(of: currentIndex) { _, _ in
            showsControls = true
        }
        .confirmationDialog(
            "",
            isPresented: Binding(get: { actionTarget != nil }, set: { if !$0 { actionTarget = nil } }),
            titleVisibility: .hidden,
            presenting: actionTarget
        ) { attachment in
            ForEach(MediaExportAction.allCases, id: \.self) { action in
                Button(action.title) { run(action, on: attachment) }
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {}
        }
        .sheet(item: $altPresentation) { presentation in
            AltTextOverlay(
                altText: presentation.text,
                maximumInitialHeight: max(180, viewportHeight * 0.6)
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
    }

    /// The active fold running across the screen (tabletop), or nil when flat, closed, held
    /// the other way (the fold then runs top to bottom) or on a device without one.
    private static func tabletopFold(in proxy: GeometryProxy) -> CGRect? {
        guard #available(iOS 27.1, *) else { return nil }
        return proxy.reservedRegions(kind: .division)
            .first { $0.isActive && $0.frame.width > $0.frame.height }?.frame
    }

    private func run(_ action: MediaExportAction, on attachment: Status.Attachment) {
        guard !isExporting else { return }
        isExporting = true
        Task {
            do {
                if let message = try await action.perform(on: attachment.url) { showNotice(message) }
            } catch {
                showNotice(MediaExportService.message(for: error))
            }
            isExporting = false
        }
    }

    /// Feedback stays inside the viewer: the app-wide toast lives under this cover.
    private func showNotice(_ message: String) {
        noticeTask?.cancel()
        exportNotice = message
        UIAccessibility.post(notification: .announcement, argument: message)
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            exportNotice = nil
        }
    }

    private func toggleControls() {
        guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return }
        showsControls.toggle()
    }

    private func hideControls() {
        guard !UIAccessibility.isVoiceOverRunning, !UIAccessibility.isSwitchControlRunning else { return }
        showsControls = false
    }

    private func closePreview() {
        dismiss()
        onDismiss?()
    }
}

/// Runs `action` whenever the device's hinge changes (iPhone Duo); nothing elsewhere.
private struct HingeChangeObserver: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, _ in action() }
        } else {
            content
        }
    }
}
