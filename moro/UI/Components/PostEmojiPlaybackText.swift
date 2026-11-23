import SwiftUI

extension EnvironmentValues {
    @Entry var animatesPostEmoji = false
    @Entry var postEmojiIsScrolling = false
}

/// Each retained scroll page owns its phase; a hidden tab must not pause another page.
struct PostEmojiScrollPlayback: ViewModifier {
    var isActive = true
    var phaseChanged: (ScrollPhase, ScrollPhase) -> Void = { _, _ in }
    @Environment(\.scenePhase) private var scenePhase
    @State private var isScrolling = false

    func body(content: Content) -> some View {
        content
            .environment(\.postEmojiIsScrolling, isScrolling)
            .onScrollPhaseChange { old, new in
                isScrolling = isActive && scenePhase == .active && new != .idle
                phaseChanged(old, new)
            }
            .onChange(of: isActive && scenePhase == .active) { _, active in
                if !active { isScrolling = false }
            }
            .onDisappear { isScrolling = false }
    }
}

/// The native Text owns wrapping, links and accessibility. Only visible animated glyphs
/// get a layer; Core Animation advances their frames without updating the text or row.
struct PostEmojiPlaybackText: View {
    let emojiSize: CGFloat
    let content: (Set<InlineEmojiMarker>) -> Text

    @Environment(\.displayScale) private var displayScale
    @Environment(\.moroPlaybackScope) private var scope
    @Environment(\.postEmojiIsScrolling) private var isScrolling
    @Environment(\.moroUIKitScrollVisibility) private var uiKitVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @State private var isVisible = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var slots: [InlineEmojiSlot] = []
    @State private var playing: [InlineEmojiMarker: PostEmojiAnimation] = [:]

    private var canPlay: Bool {
        isVisible && scope.isActive && !MediaPlaybackPresentation.shared.coversInlinePlayback
            && !isScrolling && !scope.isScrolling && scope.systemAllowsAnimatedAvatars
            && playAnimatedImages && !reduceMotion && !isLowPower
    }

    var body: some View {
        let allowed = canPlay
        let visible = allowed ? slots : []
        let markers = visible.map(\.marker)
        let request = Request(markers: markers, pixelSize: Int(ceil(emojiSize * displayScale)))
        let mask = Set(markers).intersection(playing.keys)
        // The text cutouts and the actual layers must use the same measured positions,
        // including when Text temporarily publishes an empty layout after foregrounding.
        content(mask)
            .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                if allowed {
                    GeometryReader { proxy in
                        Color.clear.onChange(of: visibleSlots(layouts, in: proxy), initial: true) { _, measured in
                            if slots != measured { slots = measured }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay {
                if !mask.isEmpty {
                    PostEmojiLayers(slots: visible, playing: playing)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .task(id: request) { await load(request) }
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
            .onChange(of: allowed) { _, enabled in
                if !enabled { slots.removeAll(); playing.removeAll() }
            }
            .onDisappear {
                isVisible = false
                slots.removeAll()
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
        guard !Task.isCancelled else { return }
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
