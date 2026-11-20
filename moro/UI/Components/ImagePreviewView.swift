// Fullscreen image reading with optional, on-demand image descriptions.

import SwiftUI

struct ImagePreviewView: View {
    let attachments: [Status.Attachment]
    let initialIndex: Int
    let post: MediaPreviewPost?
    var onDismiss: (() -> Void)? = nil

    @State private var currentIndex: Int
    @State private var altPresentation: AltPresentation?
    @State private var showsControls = true
    @State private var viewportHeight: CGFloat = 0
    @State private var isExporting = false
    @State private var exportNotice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var playbackToken: UUID?
    /// iPhone Duo half open like a laptop: the fold across the screen, in screen space. The
    /// image then stays above it and the controls move below it, onto the flat half.
    @State private var tabletopFold: CGRect?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct AltPresentation: Identifiable {
        let id: String
        let text: String
    }

    init(attachments: [Status.Attachment], initialIndex: Int = 0, post: MediaPreviewPost? = nil,
         onDismiss: (() -> Void)? = nil) {
        self.attachments = attachments
        self.initialIndex = initialIndex
        self.post = post
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
                                onDismiss: closePreview
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(height: tabletopFold?.minY)
                    .overlay(alignment: .bottom) {
                        if tabletopFold != nil && showsControls { pageIndicator }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                }
            }

            if showsControls {
                VStack {
                    if tabletopFold != nil { Spacer() }
                    MediaPreviewNavigationBar(close: closePreview, closeIdentifier: "imagePreview.close") {
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
                            MediaPreviewMoreMenu(post: post, attachment: currentAttachment, isExporting: isExporting) {
                                run($0, on: currentAttachment)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, tabletopFold == nil ? 0 : 16)
                    if tabletopFold == nil {
                        Spacer()
                        pageIndicator
                    }
                    if let post, let currentAttachment {
                        MediaPreviewPostBar(post: post) { run(.share, on: currentAttachment) }
                            .background {
                                LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                                    .padding(.top, -24).ignoresSafeArea()
                            }
                    }
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
        .modifier(MediaPreviewPostSheets(post: post))
        .onAppear {
            if playbackToken == nil { playbackToken = MediaPlaybackPresentation.shared.begin() }
        }
        .onDisappear {
            if let playbackToken { MediaPlaybackPresentation.shared.end(playbackToken) }
            playbackToken = nil
            noticeTask?.cancel()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            if UIAccessibility.isVoiceOverRunning { showsControls = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.switchControlStatusDidChangeNotification)) { _ in
            if UIAccessibility.isSwitchControlRunning { showsControls = true }
        }
        .accessibilityAction(.escape, closePreview)
        .sheet(item: $altPresentation) { presentation in
            AltTextOverlay(
                altText: presentation.text,
                maximumInitialHeight: max(180, viewportHeight * 0.6)
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        }
    }

    @ViewBuilder private var pageIndicator: some View {
        if attachments.count > 1 {
            ImagePreviewPageControl(selection: $currentIndex, count: attachments.count)
                .frame(height: 44)
                .shadow(color: .black.opacity(0.65), radius: 2)
        }
    }

    /// The active fold running across the screen (tabletop), or nil when flat, closed, held
    /// the other way (the fold then runs top to bottom) or on a device without one.
    private static func tabletopFold(in proxy: GeometryProxy) -> CGRect? {
        // Reserved regions are an iOS 27.1 SDK API (Swift 6.4); older toolchains, such as
        // CI's Xcode 26, build without them.
        #if compiler(>=6.4)
        guard #available(iOS 27.1, *) else { return nil }
        return proxy.reservedRegions(kind: .division)
            .first { $0.isActive && $0.frame.width > $0.frame.height }?.frame
        #else
        return nil
        #endif
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

private struct ImagePreviewPageControl: UIViewRepresentable {
    @Binding var selection: Int
    let count: Int

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.backgroundStyle = .minimal
        control.pageIndicatorTintColor = .white.withAlphaComponent(0.44)
        control.currentPageIndicatorTintColor = .white
        control.accessibilityIdentifier = "imagePreview.pages"
        control.addAction(UIAction { [weak control] _ in
            if let control { selection = control.currentPage }
        }, for: .valueChanged)
        return control
    }

    func updateUIView(_ control: UIPageControl, context: Context) {
        control.numberOfPages = count
        control.currentPage = selection
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIPageControl, context: Context) -> CGSize? {
        let size = uiView.size(forNumberOfPages: count)
        return CGSize(width: min(size.width, proposal.width ?? size.width), height: proposal.height ?? size.height)
    }
}

/// Runs `action` whenever the device's hinge changes (iPhone Duo); nothing elsewhere.
private struct HingeChangeObserver: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        // onHingeChange is an iOS 27.1 SDK API (Swift 6.4); older toolchains, such as CI's
        // Xcode 26, build without it.
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, _ in action() }
        } else {
            content
        }
        #else
        content
        #endif
    }
}
