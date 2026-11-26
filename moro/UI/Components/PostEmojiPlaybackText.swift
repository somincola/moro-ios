import SwiftUI

extension EnvironmentValues {
    @Entry var animatesPostEmoji = false
    @Entry var postEmojiIsScrolling = false
}

nonisolated enum PostEmojiPlaybackPolicy {
    /// Normal posts fit within one screen height, so measuring all emoji slots once
    /// avoids reading `proxy.bounds(of: .scrollView)` at 120Hz while scrolling.
    static let viewportClipHeightThreshold: CGFloat = 900

    static func shouldClipToScrollView(contentHeight: CGFloat, isScrolling: Bool) -> Bool {
        contentHeight > viewportClipHeightThreshold && !isScrolling
    }

    static func shouldDecodeUncached(hasUncached: Bool, isScrolling: Bool) -> Bool {
        hasUncached && !isScrolling
    }
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
/// get a layer; Core Animation advances their frames on the render server without updating
/// the text or row while scrolling.
struct PostEmojiPlaybackText<Content: View>: View {
    let emojiSize: CGFloat
    var textKitSlots: [InlineEmojiSlot]? = nil
    let content: (Set<InlineEmojiMarker>) -> Content

    @Environment(\.displayScale) private var displayScale
    @Environment(\.moroPlaybackScope) private var scope
    @Environment(\.moroUIKitScrollVisibility) private var uiKitVisibility
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityPlayAnimatedImages) private var playAnimatedImages
    @State private var isVisible = false
    @State private var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var slots: [InlineEmojiSlot] = []
    @State private var playing: [InlineEmojiMarker: PostEmojiAnimation] = [:]
    @State private var resolvedStills: Set<URL> = []

    /// Active playback stays alive during scrolling so Core Animation keeps advancing frames
    /// without tearing down layers or re-rendering Text. Only uncached decoding is deferred
    /// until scrolling settles.
    private var canPlay: Bool {
        isVisible && scope.isActive && !MediaPlaybackPresentation.shared.coversInlinePlayback
            && scope.systemAllowsAnimatedAvatars
            && playAnimatedImages && !reduceMotion && !isLowPower
    }

    var body: some View {
        let allowed = canPlay
        let visible = allowed ? slots : []
        let pixelSize = Int(ceil(emojiSize * displayScale))
        let effectivePlaying = resolvedPlaying(for: visible, pixelSize: pixelSize)
        let markers = visible.map(\.marker)
        let mask = Set(markers).intersection(effectivePlaying.keys)
        let uncached = markers.filter { marker in
            effectivePlaying[marker] == nil
                && !resolvedStills.contains(marker.url)
                && !PostEmojiAnimationStore.shared.isKnownStill(for: marker.url)
        }
        // The text cutouts and the actual layers must use the same measured positions,
        // including when Text temporarily publishes an empty layout after foregrounding.
        content(mask)
            .backgroundPreferenceValue(Text.LayoutKey.self) { layouts in
                if allowed, textKitSlots == nil {
                    GeometryReader { proxy in
                        if proxy.size.height > PostEmojiPlaybackPolicy.viewportClipHeightThreshold {
                            TallPostEmojiSlotMeasurer(
                                layouts: layouts,
                                proxy: proxy,
                                emojiSize: emojiSize
                            ) { measured in
                                applyMeasuredSlots(measured, pixelSize: pixelSize)
                            }
                        } else {
                            Color.clear.onChange(
                                of: Self.measureSlots(
                                    layouts, in: proxy, emojiSize: emojiSize, viewport: nil
                                ),
                                initial: true
                            ) { _, measured in
                                applyMeasuredSlots(measured, pixelSize: pixelSize)
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onChange(of: allowed ? textKitSlots : nil, initial: true) { _, measured in
                if let measured { applyMeasuredSlots(measured, pixelSize: pixelSize) }
            }
            .overlay {
                if !mask.isEmpty {
                    PostEmojiLayers(slots: visible, playing: effectivePlaying)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .background {
                if allowed, !uncached.isEmpty {
                    PostEmojiUncachedLoader(markers: uncached, pixelSize: pixelSize) { decoded, stills in
                        guard canPlay else { return }
                        let currentVisible = Set(slots.map(\.marker))
                        for (marker, animation) in decoded where currentVisible.contains(marker) {
                            playing[marker] = animation
                        }
                        if !stills.isEmpty { resolvedStills.formUnion(stills) }
                    }
                }
            }
            .background {
                if let uiKitVisibility {
                    UIKitScrollVisibilityProbe(visibility: uiKitVisibility, threshold: 0.001) { isVisible = $0 }
                }
            }
            // A long body may be taller than a viewport. Tall bodies clip glyphs when settled.
            .onScrollVisibilityChange(threshold: 0.001) { if uiKitVisibility == nil { isVisible = $0 } }
            .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
                isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
            .onChange(of: allowed) { _, enabled in
                if !enabled {
                    slots.removeAll()
                    playing.removeAll()
                }
            }
            .onDisappear {
                isVisible = false
                slots.removeAll()
                playing.removeAll()
                resolvedStills.removeAll()
            }
    }

    private func resolvedPlaying(
        for visible: [InlineEmojiSlot],
        pixelSize: Int
    ) -> [InlineEmojiMarker: PostEmojiAnimation] {
        guard !visible.isEmpty else { return [:] }
        var resolved = playing
        for slot in visible where resolved[slot.marker] == nil {
            if let cached = PostEmojiAnimationStore.shared.cachedAnimation(
                for: slot.marker.url, pixelSize: pixelSize
            ) {
                resolved[slot.marker] = cached
            }
        }
        return resolved
    }

    private func applyMeasuredSlots(_ measured: [InlineEmojiSlot], pixelSize: Int) {
        if slots != measured { slots = measured }
        let visible = Set(measured.map(\.marker))
        playing = playing.filter { visible.contains($0.key) }
        for slot in measured where playing[slot.marker] == nil {
            if let cached = PostEmojiAnimationStore.shared.cachedAnimation(
                for: slot.marker.url, pixelSize: pixelSize
            ) {
                playing[slot.marker] = cached
            }
        }
    }

    static func measureSlots(
        _ layouts: [Text.LayoutKey.AnchoredLayout],
        in proxy: GeometryProxy,
        emojiSize: CGFloat,
        viewport: CGRect?
    ) -> [InlineEmojiSlot] {
        var slots: [InlineEmojiSlot] = []
        var seen = Set<InlineEmojiMarker>()
        for entry in layouts {
            let origin = proxy[entry.origin]
            for line in entry.layout {
                for run in line {
                    guard let marker = run[InlineEmojiMarker.self] else { continue }
                    let rect = run.typographicBounds.rect
                    let frame = CGRect(
                        x: origin.x + rect.minX,
                        y: origin.y + rect.minY,
                        width: emojiSize,
                        height: emojiSize
                    )
                    let isIncluded = viewport.map { frame.intersects($0) } ?? true
                    if isIncluded, seen.insert(marker).inserted {
                        slots.append(InlineEmojiSlot(marker: marker, frame: frame))
                    }
                }
            }
        }
        return slots
    }
}

/// Only tall paragraphs observe scroll state to clip off-screen glyphs when settled,
/// avoiding per-frame `proxy.bounds(of: .scrollView)` reads during active scrolling.
private struct TallPostEmojiSlotMeasurer: View {
    let layouts: [Text.LayoutKey.AnchoredLayout]
    let proxy: GeometryProxy
    let emojiSize: CGFloat
    let onMeasured: ([InlineEmojiSlot]) -> Void

    @Environment(\.moroPlaybackScope) private var scope
    @Environment(\.postEmojiIsScrolling) private var isScrolling

    var body: some View {
        let scrolling = isScrolling || scope.isScrolling
        if PostEmojiPlaybackPolicy.shouldClipToScrollView(
            contentHeight: proxy.size.height, isScrolling: scrolling
        ) {
            let viewport = proxy.bounds(of: .scrollView) ?? CGRect(origin: .zero, size: proxy.size)
            Color.clear.onChange(
                of: PostEmojiPlaybackText<Text>.measureSlots(
                    layouts, in: proxy, emojiSize: emojiSize, viewport: viewport
                ),
                initial: true
            ) { _, measured in
                onMeasured(measured)
            }
        } else {
            Color.clear
        }
    }
}

/// Isolated loader for emojis that missed the memory cache. Observes scrolling only while
/// uncached work exists, so already-playing posts perform zero SwiftUI updates on scroll.
private struct PostEmojiUncachedLoader: View {
    let markers: [InlineEmojiMarker]
    let pixelSize: Int
    let onResolved: ([InlineEmojiMarker: PostEmojiAnimation], Set<URL>) -> Void

    @Environment(\.moroPlaybackScope) private var scope
    @Environment(\.postEmojiIsScrolling) private var isScrolling

    private struct Request: Equatable {
        let markers: [InlineEmojiMarker]
        let pixelSize: Int
        let canDecode: Bool
    }

    var body: some View {
        let request = Request(
            markers: markers,
            pixelSize: pixelSize,
            canDecode: PostEmojiPlaybackPolicy.shouldDecodeUncached(
                hasUncached: !markers.isEmpty,
                isScrolling: isScrolling || scope.isScrolling
            )
        )
        Color.clear
            .task(id: request) { await load(request) }
    }

    private func load(_ request: Request) async {
        guard request.canDecode, !Task.isCancelled else { return }
        do { try await Task.sleep(for: MediaPlaybackPolicy.settleDelay) } catch { return }
        let byURL = Dictionary(grouping: request.markers, by: \.url)
        var decoded: [InlineEmojiMarker: PostEmojiAnimation] = [:]
        var stills: Set<URL> = []
        await withTaskGroup(of: (URL, PostEmojiAnimation?).self) { group in
            for url in byURL.keys {
                group.addTask {
                    (url, await PostEmojiAnimationStore.shared.animation(for: url, pixelSize: request.pixelSize))
                }
            }
            for await (url, animation) in group {
                guard !Task.isCancelled else { return }
                if let animation {
                    for marker in byURL[url] ?? [] { decoded[marker] = animation }
                } else if PostEmojiAnimationStore.shared.isKnownStill(for: url) {
                    stills.insert(url)
                }
            }
        }
        guard !Task.isCancelled, (!decoded.isEmpty || !stills.isEmpty) else { return }
        onResolved(decoded, stills)
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
