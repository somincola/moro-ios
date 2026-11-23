import SwiftUI

extension EnvironmentValues {
    @Entry var animatesPostEmoji = false
    @Entry var postEmojiIsScrolling = false
}

/// The native Text owns wrapping, links and accessibility. Only visible animated glyphs
/// get a layer; Core Animation advances their frames without updating the text or row.
struct PostEmojiPlaybackText: View {
    let emojiSize: CGFloat
    let content: (Set<InlineEmojiMarker>) -> Text

    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.moroPlaybackScope) private var scope
    @Environment(\.postEmojiIsScrolling) private var isScrolling
    @Environment(\.moroUIKitScrollVisibility) private var uiKitVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @State private var isVisible = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var playing: [InlineEmojiMarker: PostEmojiAnimation] = [:]

    private var canPlay: Bool {
        MediaPlaybackPolicy.canPlay(isVisible: isVisible, isActive: scope.isActive, isSceneActive: scenePhase == .active,
                                    isCovered: MediaPlaybackPresentation.shared.coversInlinePlayback)
            && !isScrolling && !scope.isScrolling && scope.systemAllowsAnimatedAvatars
            && playAnimatedImages && !reduceMotion && !isLowPower
    }

    var body: some View {
        let allowed = canPlay
        content(allowed ? Set(playing.keys) : [])
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                if allowed {
                    GeometryReader { proxy in
                        let slots = visibleSlots(layouts, in: proxy)
                        let request = Request(markers: slots.map(\.marker), pixelSize: Int(ceil(emojiSize * displayScale)))
                        Color.clear.overlay {
                            if !playing.isEmpty {
                                PostEmojiLayers(slots: slots, playing: playing)
                            }
                        }
                        .task(id: request) { await load(request) }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .background {
                if let uiKitVisibility {
                    UIKitScrollVisibilityProbe(visibility: uiKitVisibility, threshold: 0.001) { isVisible = $0 }
                }
            }
            // A long body may be taller than a viewport. Each actual glyph is clipped below.
            .onScrollVisibilityChange(threshold: 0.001) { if uiKitVisibility == nil { isVisible = $0 } }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onChange(of: allowed) { _, enabled in if !enabled { playing.removeAll() } }
            .onDisappear {
                isVisible = false
                playing.removeAll()
            }
    }

    private func visibleSlots(_ layouts: [Text.LayoutKey.AnchoredLayout], in proxy: GeometryProxy) -> [InlineEmojiSlot] {
        let viewport = proxy.bounds(of: .scrollView) ?? CGRect(origin: .zero, size: proxy.size)
        var slots: [InlineEmojiSlot] = []
        var seen = Set<InlineEmojiMarker>()
        for entry in layouts {
            let origin = proxy[entry.origin]
            for line in entry.layout {
                for run in line {
                    guard let marker = run[InlineEmojiMarker.self] else { continue }
                    let rect = run.typographicBounds.rect
                    let frame = CGRect(x: origin.x + rect.minX, y: origin.y + rect.minY,
                                       width: emojiSize, height: emojiSize)
                    if frame.intersects(viewport), seen.insert(marker).inserted {
                        slots.append(InlineEmojiSlot(marker: marker, frame: frame))
                    }
                }
            }
        }
        return slots
    }

    private struct Request: Equatable {
        let markers: [InlineEmojiMarker]
        let pixelSize: Int
    }

    private func load(_ request: Request) async {
        let visible = Set(request.markers)
        playing = playing.filter { visible.contains($0.key) }
        guard !visible.isEmpty else { return }
        do { try await Task.sleep(for: MediaPlaybackPolicy.settleDelay) } catch { return }
        let byURL = Dictionary(grouping: request.markers, by: \.url)
        await withTaskGroup(of: (URL, PostEmojiAnimation?).self) { group in
            for url in byURL.keys {
                group.addTask { (url, await PostEmojiAnimationStore.shared.animation(for: url, pixelSize: request.pixelSize)) }
            }
            for await (url, animation) in group {
                guard !Task.isCancelled else { return }
                if let animation {
                    for marker in byURL[url] ?? [] { playing[marker] = animation }
                }
            }
        }
    }
}

/// One transparent host per playing paragraph, irrespective of its number of emoji.
private struct PostEmojiLayers: UIViewRepresentable {
    let slots: [InlineEmojiSlot]
    let playing: [InlineEmojiMarker: PostEmojiAnimation]

    func makeUIView(context: Context) -> InlineEmojiLayerHost {
        let host = InlineEmojiLayerHost()
        host.isUserInteractionEnabled = false
        return host
    }

    func updateUIView(_ view: InlineEmojiLayerHost, context: Context) {
        view.update(slots: slots, playing: playing)
    }

    static func dismantleUIView(_ view: InlineEmojiLayerHost, coordinator: ()) {
        view.update(slots: [], playing: [:])
    }
}
