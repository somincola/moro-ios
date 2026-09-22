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
                                altText: Self.descriptionText(attachment.description),
                                onSingleTap: toggleControls,
                                onInteractionBegan: hideControls,
                                onDismiss: closePreview
                            )
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
            }

            if showsControls {
                VStack {
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    Spacer()
                }
            }
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
        .sheet(item: $altPresentation) { presentation in
            AltTextOverlay(
                altText: presentation.text,
                maximumInitialHeight: max(180, viewportHeight * 0.6)
            )
            .environment(\.dynamicTypeSize, dynamicTypeSize)
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
