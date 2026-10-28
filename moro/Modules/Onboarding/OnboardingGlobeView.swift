//
//  OnboardingGlobeView.swift
//  moro
//
//  First-launch welcome, told almost without words:
//    · one starry net across the whole screen, swelling and sinking in slow waves;
//    · a swipe up (or a tap) gathers it into a globe whose surface rolls like a
//      gentle tide; "Moro", "FOR MASTODON" and "Get started" then fade in one
//      after another while meteors link the servers. The globe can be turned
//      freely with a finger; there is no going back to the net.
//  Getting started flies into the star nearest the centre; it opens onto the login
//  page underneath.
//

import SwiftUI

enum OnboardingCompletion {
    case login
    case registration
}

struct OnboardingGlobeView: View {
    let onExitStart: () -> Void
    let onFinish: (OnboardingCompletion) -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var story = StoryProgress()
    @State private var formed: Date?
    /// Whether the words and the button are shown; set once the globe has mostly gathered.
    @State private var revealed = false
    @State private var hintRaised = false
    @State private var turn = GlobeTurn()
    @State private var dive: DiveState?
    @State private var dragging: DragKind?
    @State private var sceneSize = CGSize.zero
    private let sceneStart = Date.now

    private enum DragKind { case gather, turn, ignored }

    init(onExitStart: @escaping () -> Void = {}, onFinish: @escaping (OnboardingCompletion) -> Void) {
        self.onExitStart = onExitStart
        self.onFinish = onFinish
    }

    var body: some View {
        GeometryReader { proxy in
            let fullSize = CGSize(width: proxy.size.width,
                                  height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom)
            ZStack {
                // The scene paints its own background so the dive can cut a hole
                // through it onto whatever sits underneath.
                TimelineView(.animation(paused: reduceMotion && dive == nil)) { context in
                    Canvas { canvas, size in
                        StarScene(ink: theme.colors.textPrimary, background: theme.starfieldBackground,
                                  dark: theme.colorScheme == .dark)
                            .draw(in: &canvas, size: size, frame: frame(at: context.date))
                    }
                }
                .ignoresSafeArea()
                .accessibilityHidden(true)

                overlay
                    // The scene fills the whole display, so center the words and controls on
                    // it too. On iPhone Duo the status bar sits down one side, which makes the
                    // safe area lopsided: even out the smaller side to match.
                    .padding(.leading, max(0, proxy.safeAreaInsets.trailing - proxy.safeAreaInsets.leading))
                    .padding(.trailing, max(0, proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing))
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(height: proxy.size.height))
            .onTapGesture { gather() }
            // A tappable container would otherwise be read as one big button that
            // swallows the controls inside it.
            .accessibilityElement(children: .contain)
            .onAppear { sceneSize = fullSize }
            .onChange(of: fullSize) { _, size in sceneSize = size }
        }
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: formed)
        .accessibilityAction(named: MoroL10n.Registration.continueButton) { gather() }
    }

    // MARK: Timing

    private func progress(at date: Date) -> Double {
        if reduceMotion { return formed == nil ? 0 : 1 }
        return story.value(at: date)
    }

    /// Seconds since the globe began to form, offset so 0 is when it has mostly gathered.
    private func reveal(at date: Date) -> Double {
        guard let formed else { return -.infinity }
        return reduceMotion ? .infinity : date.timeIntervalSince(formed) - 0.55
    }

    private func frame(at date: Date) -> StarScene.Frame {
        let time = date.timeIntervalSince(sceneStart)
        let rotation = dive?.rotation ?? turn.matrix(at: date) * .rotationY(-0.6 + 0.08 * time)
        return StarScene.Frame(progress: progress(at: date), time: time, rotation: rotation,
                               meteors: smoothstep(0.2, 1.4, reveal(at: date)),
                               dive: dive.map { ($0.target, $0.amount(at: date)) })
    }

    // MARK: Overlay

    /// The words and controls over the scene. Driven by state and SwiftUI animations,
    /// not the scene's clock, so VoiceOver and UI automation see exactly what is shown.
    private var overlay: some View {
        let exiting = dive != nil
        let showWords = revealed && !exiting
        return ZStack {

            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 10) {
                    if showWords {
                        Text(verbatim: "Moro")
                            .font(.system(size: 60, weight: .bold))
                            .tracking(-1.8)
                            .foregroundStyle(theme.colors.textPrimary)
                            .transition(reveal(after: 0))
                        Text(verbatim: "FOR MASTODON")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(3)
                            .foregroundStyle(theme.colors.textTertiary)
                            .transition(reveal(after: 0.45))
                    }
                }
                .frame(height: 96)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHidden(!showWords)

                Spacer().frame(height: 40)

                ZStack {
                    if showWords {
                        Button { finish(.login) } label: {
                            Text(MoroL10n.Onboarding.getStarted)
                                .moroScaledFont(size: 17, weight: .semibold, relativeTo: .body)
                                .foregroundStyle(theme.colors.primaryForeground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(theme.colors.primary500, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(GlobePressStyle())
                        .transition(reveal(after: 0.9))
                        .accessibilityIdentifier("onboarding.start")
                    }

                    if formed == nil {
                        // Swipe hint for the wordless first moment.
                        Image(systemName: "chevron.compact.up")
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(theme.colors.textSecondary)
                            .offset(y: hintRaised && !reduceMotion ? -6 : 0)
                            .opacity(hintRaised ? 0.9 : 0.55)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(), value: hintRaised)
                            .onAppear { hintRaised = true }
                            .transition(.opacity.animation(.easeOut(duration: 0.3)))
                            .accessibilityHidden(true)
                    }
                }
                .frame(height: 54)
                // A full-width button reads as a banner on a wide display.
                .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    /// Fades a piece of the title area in, a beat after the globe has gathered.
    private func reveal(after delay: Double) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return AnyTransition.opacity.combined(with: .offset(y: 12))
            .animation(.easeOut(duration: 0.8).delay(delay))
    }

    // MARK: Interaction

    private func dragGesture(height: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard dive == nil, !reduceMotion else { return }
                if dragging == nil {
                    if formed != nil {
                        dragging = .turn
                        turn.begin(at: .now)
                    } else if value.translation.height < 0,
                              abs(value.translation.height) >= abs(value.translation.width) {
                        dragging = .gather
                        _ = story.begin(at: .now)
                    } else {
                        dragging = .ignored
                    }
                }
                switch dragging {
                case .gather:
                    // Follow the finger up, with a little resistance past the globe.
                    var p = -value.translation.height / (height * 0.45)
                    if p < 0 { p *= 0.3 } else if p > 1 { p = 1 + (p - 1) * 0.25 }
                    story.live = p
                case .turn:
                    turn.live = value.translation
                default:
                    break
                }
            }
            .onEnded { value in
                defer { dragging = nil }
                guard dive == nil, !reduceMotion else { return }
                switch dragging {
                case .gather:
                    let projected = -value.predictedEndTranslation.height / (height * 0.45)
                    if projected > 0.3 { gather() } else { story.settle(to: 0, now: .now) }
                case .turn:
                    turn.release(translation: value.translation, velocity: value.velocity, now: .now)
                default:
                    break
                }
            }
    }

    /// Gathers the net into the globe, once and for good.
    private func gather() {
        guard formed == nil, dive == nil else { return }
        let now = Date.now
        story.settle(to: 1, now: now)
        formed = now
        Task { @MainActor in
            // Let the globe mostly gather before the words arrive.
            if !reduceMotion { try? await Task.sleep(for: .milliseconds(550)) }
            revealed = true
        }
    }

    private func finish(_ completion: OnboardingCompletion) {
        guard dive == nil else { return }
        onExitStart()
        guard !reduceMotion else {
            onFinish(completion)
            return
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        let now = Date.now
        if formed == nil { formed = now }
        let current = frame(at: now)
        story.settle(to: 1, now: now)
        let target = StarScene.nearestServer(to: CGPoint(x: sceneSize.width / 2, y: sceneSize.height * 0.42),
                                             size: sceneSize, frame: current)
        dive = DiveState(start: now, target: target, rotation: current.rotation)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(DiveState.duration * 1000) + 50))
            onFinish(completion)
        }
    }
}

extension MoroTheme {
    /// The night (or paper) behind the onboarding globe and the login starfield,
    /// shared so the dive from one opens seamlessly onto the other.
    var starfieldBackground: Color {
        colorScheme == .dark ? Color(hex: 0x050608) : .white
    }
}

private func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private struct GlobePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - State

/// How far the net has gathered (0…1), either following a finger or easing.
/// Eased by wall-clock time so the Canvas can read it every frame.
private struct StoryProgress {
    var from = 0.0
    var to = 0.0
    var start = Date.distantPast
    var live: Double?
    static let settleDuration = 1.2

    func value(at date: Date) -> Double {
        if let live { return live }
        let t = min(max(date.timeIntervalSince(start) / Self.settleDuration, 0), 1)
        return from + (to - from) * (1 - pow(1 - t, 3))
    }

    mutating func begin(at now: Date) -> Double {
        let current = value(at: now)
        live = current
        return current
    }

    mutating func settle(to target: Double, now: Date) {
        from = live ?? value(at: now)
        to = target
        start = now
        live = nil
    }
}

/// A 3×3 rotation, row-major.
private struct Rotation3 {
    var m: (Double, Double, Double, Double, Double, Double, Double, Double, Double)

    static let identity = Rotation3(m: (1, 0, 0, 0, 1, 0, 0, 0, 1))

    static func rotationX(_ a: Double) -> Rotation3 {
        Rotation3(m: (1, 0, 0, 0, cos(a), -sin(a), 0, sin(a), cos(a)))
    }

    static func rotationY(_ a: Double) -> Rotation3 {
        Rotation3(m: (cos(a), 0, sin(a), 0, 1, 0, -sin(a), 0, cos(a)))
    }

    /// Rotation by `angle` about the unit axis (x, y, z).
    static func axisAngle(_ x: Double, _ y: Double, _ z: Double, _ angle: Double) -> Rotation3 {
        let c = cos(angle), s = sin(angle), t = 1 - c
        return Rotation3(m: (t * x * x + c, t * x * y - s * z, t * x * z + s * y,
                             t * x * y + s * z, t * y * y + c, t * y * z - s * x,
                             t * x * z - s * y, t * y * z + s * x, t * z * z + c))
    }

    func apply(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        (m.0 * x + m.1 * y + m.2 * z, m.3 * x + m.4 * y + m.5 * z, m.6 * x + m.7 * y + m.8 * z)
    }

    static func * (a: Rotation3, b: Rotation3) -> Rotation3 {
        let (a0, a1, a2, a3, a4, a5, a6, a7, a8) = a.m
        let (b0, b1, b2, b3, b4, b5, b6, b7, b8) = b.m
        return Rotation3(m: (a0 * b0 + a1 * b3 + a2 * b6, a0 * b1 + a1 * b4 + a2 * b7, a0 * b2 + a1 * b5 + a2 * b8,
                             a3 * b0 + a4 * b3 + a5 * b6, a3 * b1 + a4 * b4 + a5 * b7, a3 * b2 + a4 * b5 + a5 * b8,
                             a6 * b0 + a7 * b3 + a8 * b6, a6 * b1 + a7 * b4 + a8 * b7, a6 * b2 + a7 * b5 + a8 * b8))
    }
}

/// The finger's turn of the globe: any direction, with a little momentum on release.
private struct GlobeTurn {
    var base = Rotation3.rotationX(0.38)
    var live: CGSize?
    var velocity = CGSize.zero
    var released = Date.distantPast

    /// Points of drag per radian.
    static let reach = 150.0
    /// Momentum decay, in seconds.
    static let decay = 0.45

    /// Dragging right turns the front to the right, dragging down turns it down.
    static func turn(by drag: CGSize) -> Rotation3 {
        let length = hypot(drag.width, drag.height)
        guard length > 0.001 else { return .identity }
        return .axisAngle(drag.height / length, drag.width / length, 0, length / reach)
    }

    func matrix(at date: Date) -> Rotation3 {
        if let live { return Self.turn(by: live) * base }
        let elapsed = max(date.timeIntervalSince(released), 0)
        let carry = Self.decay * (1 - exp(-elapsed / Self.decay))
        return Self.turn(by: CGSize(width: velocity.width * carry, height: velocity.height * carry)) * base
    }

    mutating func begin(at now: Date) {
        base = matrix(at: now)
        velocity = .zero
        live = .zero
    }

    mutating func release(translation: CGSize, velocity v: CGSize, now: Date) {
        base = Self.turn(by: translation) * base
        live = nil
        let speed = hypot(v.width, v.height)
        let cap = 2400.0
        velocity = speed > cap ? CGSize(width: v.width * cap / speed, height: v.height * cap / speed) : v
        released = now
    }
}

private struct DiveState {
    let start: Date
    let target: Int
    let rotation: Rotation3
    static let duration = 1.6

    func amount(at date: Date) -> Double {
        let t = min(max(date.timeIntervalSince(start) / Self.duration, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

// MARK: - Points

private struct StarPoint {
    /// On the unit sphere.
    let x: Double, y: Double, z: Double
    /// On the net: across (-1…1) and down the screen (0…1).
    let netX: Double, netY: Double
    let isServer: Bool
    let delay: Double
    let phase: Double
}

private enum StarField {
    static let columns = 22
    static let rows = 44

    /// Deterministic noise in 0..<1, so the scene is the same on every launch.
    static func noise(_ index: Int, _ salt: UInt64) -> Double {
        var h = UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15 ^ salt
        h ^= h >> 31; h = h &* 0xBF58_476D_1CE4_E5B9; h ^= h >> 27
        return Double(h % 10_000) / 10_000
    }

    /// Row r of the net (top to bottom) folds into the r-th latitude band of the globe.
    static let all: [StarPoint] = {
        let count = columns * rows
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0..<count).map { index in
            let y = 1 - (Double(index) + 0.5) / Double(count) * 2
            let radius = (1 - y * y).squareRoot()
            let theta = golden * Double(index)
            let column = index % columns
            let row = index / columns
            return StarPoint(
                x: cos(theta) * radius, y: y, z: sin(theta) * radius,
                netX: Double(column) / Double(columns - 1) * 2.1 - 1.05 + (noise(index, 0x11) - 0.5) * 0.06,
                netY: Double(row) / Double(rows - 1) + (noise(index, 0x22) - 0.5) * 0.012,
                isServer: index % 23 == 7,
                delay: noise(index, 0x33),
                phase: noise(index, 0x44) * 2 * .pi)
        }
    }()

    static let servers: [Int] = all.indices.filter { all[$0].isServer }

    /// Distant stars that show once the net has gathered into the globe.
    static let stars: [(x: Double, y: Double, phase: Double, size: Double)] = (0..<110).map { i in
        (noise(i, 0xD4), noise(i, 0xE5), noise(i, 0xF6) * 2 * .pi, noise(i, 0xA7))
    }
}

// MARK: - Scene

private struct StarScene {
    let ink: Color
    let background: Color
    let dark: Bool

    struct Frame {
        let progress: Double
        let time: Double
        let rotation: Rotation3
        let meteors: Double
        let dive: (target: Int, amount: Double)?
    }

    // MARK: The net

    /// Swells and hollows drifting across the net. Each one slowly wanders, rises
    /// into a crest that bulges the net toward you like a lens, sinks into a hollow
    /// that pinches it, and rises again, out of step with the rest.
    private struct Swells {
        struct Swell { let x: Double, y: Double, amount: Double, reach: Double }
        let items: [Swell]
        let time: Double

        /// The net is about four times as tall as half its width; swells are round on screen.
        static let aspect = 4.0

        init(time t: Double) {
            time = t
            items = (0..<6).map { k in
                let f = Double(k)
                return Swell(x: 0.95 * sin(t * (0.033 + 0.011 * f) + f * 1.7),
                             y: 2 + 1.9 * sin(t * (0.026 + 0.009 * f) + f * 2.3),
                             amount: sin(t * (0.26 + 0.05 * f) + f * 0.9),
                             reach: 0.62 + 0.14 * Double(k % 3))
            }
        }

        /// Where a point of the net is pushed to, and how high it stands (roughly -1…1).
        func sample(x: Double, y: Double) -> (x: Double, y: Double, height: Double) {
            let v = y * Self.aspect
            var h = 0.25 * sin(x * 1.7 + v * 1.1 - time * 0.38) * sin(v * 0.8 + time * 0.22)
            var dx = 0.0, dv = 0.0
            for s in items {
                let ox = x - s.x, ov = v - s.y
                let g = exp(-(ox * ox + ov * ov) / (2 * s.reach * s.reach))
                h += s.amount * g
                dx += ox * s.amount * g * 0.32
                dv += ov * s.amount * g * 0.32
            }
            return (x + dx, (v + dv) / Self.aspect, min(max(h / 1.1, -1), 1))
        }
    }

    /// The net fills the screen, tipped back just enough to feel like a surface;
    /// crests rise toward the viewer, hollows sink away.
    private static func netPoint(x: Double, y: Double, height h: Double, size: CGSize) -> CGPoint {
        let near = 0.9 + 0.18 * y
        let top = size.height * (-0.04 + 1.08 * pow(max(y, 0), 1.12))
        return CGPoint(x: size.width / 2 + x * size.width * 0.55 * near * (1 + 0.06 * h),
                       y: top - h * size.height * 0.045 * (0.6 + 0.4 * y))
    }

    // MARK: The globe

    private struct Globe {
        let center: CGPoint
        let radius: Double
        let presence: Double
        let time: Double
        let bumps: [(x: Double, y: Double, z: Double, amount: Double)]
    }

    private static func globe(size: CGSize, frame: Frame) -> Globe {
        let t = frame.time
        let bumps = (0..<5).map { k -> (x: Double, y: Double, z: Double, amount: Double) in
            let f = Double(k)
            let lon = t * 0.11 * (1 + 0.3 * f) + f * 1.6
            let lat = 0.9 * sin(t * 0.07 * (1 + 0.2 * f) + f)
            return (cos(lat) * cos(lon), sin(lat), cos(lat) * sin(lon), sin(t * (0.4 + 0.07 * f) + f * 1.3))
        }
        return Globe(center: CGPoint(x: size.width / 2, y: size.height * 0.4),
                     radius: size.width * 0.44,
                     presence: smoothstep(0.6, 1.1, frame.progress), time: t, bumps: bumps)
    }

    /// The globe's surface, roughly -1…1: a few swells rising and sinking as they
    /// drift around it, over long slow waves.
    private static func tide(_ p: StarPoint, globe g: Globe) -> Double {
        let t = g.time
        var h = 0.2 * sin(2.2 * p.x + 1.4 * p.y - t * 0.6)
            + 0.15 * sin(2.6 * p.z - 1.8 * p.y + t * 0.45 + 1.3)
        for b in g.bumps {
            let d = p.x * b.x + p.y * b.y + p.z * b.z
            h += b.amount * exp(-(1 - d) / 0.09)
        }
        return min(max(h, -1), 1)
    }

    /// A point on the globe, raised or lowered by the tide; returns its depth and tide.
    private static func spherePoint(_ p: StarPoint, globe g: Globe, rotation: Rotation3) -> (CGPoint, Double, Double) {
        let wave = tide(p, globe: g) * g.presence
        let r = rotation.apply(p.x, p.y, p.z)
        let radius = g.radius * (1 + 0.065 * wave)
        return (CGPoint(x: g.center.x + r.x * radius, y: g.center.y - r.y * radius), r.z, wave)
    }

    static func nearestServer(to point: CGPoint, size: CGSize, frame: Frame) -> Int {
        let g = globe(size: size, frame: frame)
        return StarField.servers.min { a, b in
            func score(_ i: Int) -> Double {
                let (s, z, _) = spherePoint(StarField.all[i], globe: g, rotation: frame.rotation)
                return z < 0.2 ? .infinity : hypot(s.x - point.x, s.y - point.y)
            }
            return score(a) < score(b)
        } ?? StarField.servers[0]
    }

    // MARK: Drawing

    func draw(in canvas: inout GraphicsContext, size: CGSize, frame: Frame) {
        canvas.fill(Path(CGRect(origin: .zero, size: size)), with: .color(background))

        let time = frame.time
        let morph = min(max(frame.progress, 0), 1)
        let g = Self.globe(size: size, frame: frame)
        let swells = morph < 1 ? Swells(time: time) : nil

        // Flying in: everything scales about the chosen star, which drifts to where
        // the login page raises its own chosen star.
        let dive = frame.dive?.amount ?? 0
        var anchor = CGPoint.zero
        var anchorZ = 1.0
        if let target = frame.dive?.target {
            (anchor, anchorZ, _) = Self.spherePoint(StarField.all[target], globe: g, rotation: frame.rotation)
        }
        let zoom = 1 + pow(dive, 2) * 11
        let destination = CGPoint(x: size.width / 2, y: size.height * 0.2)
        let pull = min(dive * 1.4, 1)
        func place(_ point: CGPoint) -> CGPoint {
            guard dive > 0 else { return point }
            return CGPoint(x: anchor.x + (point.x - anchor.x) * zoom + (destination.x - anchor.x) * pull,
                           y: anchor.y + (point.y - anchor.y) * zoom + (destination.y - anchor.y) * pull)
        }
        let fade = 1 - min(dive * 1.3, 1)

        // Distant stars come out once the net has gathered into the globe.
        if morph > 0.3 {
            let strength = smoothstep(0.3, 1, morph) * fade
            for pass in 0..<2 {
                var sky = Path()
                for (index, star) in StarField.stars.enumerated() where index % 2 == pass {
                    let twinkle = 0.5 + 0.5 * sin(time * (0.6 + star.size * 0.8) + star.phase)
                    let r = (0.4 + 0.8 * star.size) * (0.6 + 0.5 * twinkle)
                    let at = place(CGPoint(x: star.x * size.width, y: star.y * size.height))
                    sky.addEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
                }
                let base = (dark ? 0.22 : 0.12) * (pass == 0 ? 1 : 0.65)
                canvas.fill(sky, with: .color(ink.opacity(base * strength)))
            }
        }

        // A soft halo once the globe exists.
        if morph > 0.5 {
            let halo = g.radius * 1.4
            canvas.fill(Path(ellipseIn: CGRect(x: g.center.x - halo, y: g.center.y - halo, width: halo * 2, height: halo * 2)),
                        with: .radialGradient(Gradient(colors: [ink.opacity((dark ? 0.08 : 0.045) * (morph - 0.5) * 2 * fade),
                                                                ink.opacity(0)]),
                                              center: g.center, startRadius: g.radius * 0.5, endRadius: halo))
        }

        // Points: where each one is between net and globe, batched by brightness.
        let points = StarField.all
        var screen = [CGPoint](repeating: .zero, count: points.count)
        var heights = [Double](repeating: 0, count: points.count)
        let buckets = 8
        var dots = Array(repeating: Path(), count: buckets)
        var servers = Path()
        var glows: [(CGPoint, Double, Double)] = []
        for (index, point) in points.enumerated() {
            let local = morph <= 0 ? 0 : morph >= 1 ? 1
                : min(max((morph - point.delay * 0.3) / 0.7, 0), 1)
            let eased = local * local * (3 - 2 * local)

            let s = swells?.sample(x: point.netX, y: point.netY) ?? (x: point.netX, y: point.netY, height: 0)
            heights[index] = s.height
            let net = Self.netPoint(x: s.x, y: s.y, height: s.height, size: size)
            let (sphere, z, wave) = Self.spherePoint(point, globe: g, rotation: frame.rotation)
            let position = place(CGPoint(x: net.x + (sphere.x - net.x) * eased, y: net.y + (sphere.y - net.y) * eased))
            screen[index] = position

            // Each star twinkles at its own pace, and now and then one flares.
            let twinkle = 0.7 + 0.3 * sin(time * (1.2 + point.delay * 1.4) + point.phase)
            let flare = pow(max(sin(time * (0.3 + 0.45 * point.delay) + point.phase * 3), 0), 14)
            let crest = (s.height + 1) / 2
            let netAlpha = (0.06 + 0.7 * pow(crest, 1.6)) * twinkle + 0.45 * flare
            let depth = min(max((z + 0.35) / 1.35, 0), 1)
            let globeAlpha = z > -0.35 ? (0.08 + 0.5 * depth) * (1 + 0.45 * wave) * twinkle + 0.3 * flare * depth : 0
            let alpha = min(max(netAlpha + (globeAlpha - netAlpha) * eased, 0), 1) * fade
            guard alpha > 0.01 else { continue }
            let netRadius = (0.5 + 1.5 * crest) + 0.9 * flare
            let globeRadius = (0.7 + 1.0 * depth) * (1 + 0.3 * wave) + 0.6 * flare * depth
            let radius = netRadius + (globeRadius - netRadius) * eased
            if point.isServer, eased > 0.9, z > 0 {
                let r = 2.2 + 1.3 * depth
                servers.addEllipse(in: CGRect(x: position.x - r, y: position.y - r, width: r * 2, height: r * 2))
                glows.append((position, r, depth))
            } else {
                let bucket = min(Int(alpha / 0.8 * Double(buckets)), buckets - 1)
                dots[bucket].addEllipse(in: CGRect(x: position.x - radius, y: position.y - radius,
                                                   width: radius * 2, height: radius * 2))
            }
        }

        // The net's threads: bright along the crests, all but gone in the hollows,
        // letting go as the net gathers.
        if morph < 1 {
            var threads = [Path](repeating: Path(), count: 4)
            func band(_ a: Int, _ b: Int) -> Int {
                min(max(Int(((heights[a] + heights[b]) / 2 + 1) / 2 * 4), 0), 3)
            }
            for index in points.indices {
                let column = index % StarField.columns
                let row = index / StarField.columns
                if column + 1 < StarField.columns {
                    let k = band(index, index + 1)
                    threads[k].move(to: screen[index]); threads[k].addLine(to: screen[index + 1])
                }
                if row + 1 < StarField.rows {
                    let k = band(index, index + StarField.columns)
                    threads[k].move(to: screen[index]); threads[k].addLine(to: screen[index + StarField.columns])
                }
            }
            let letGo = pow(1 - morph, 1.5) * fade
            for (k, path) in threads.enumerated() {
                let alpha = [0.015, 0.045, 0.1, 0.19][k] * letGo * (dark ? 1 : 0.85)
                canvas.stroke(path, with: .color(ink.opacity(alpha)), lineWidth: k == 3 ? 0.8 : 0.6)
            }
        }

        for (index, path) in dots.enumerated() {
            canvas.fill(path, with: .color(ink.opacity((Double(index) + 0.5) / Double(buckets) * 0.8)))
        }
        for (at, r, depth) in glows {
            let halo = r * 3.2
            canvas.fill(Path(ellipseIn: CGRect(x: at.x - halo, y: at.y - halo, width: halo * 2, height: halo * 2)),
                        with: .radialGradient(Gradient(colors: [ink.opacity((dark ? 0.22 : 0.14) * depth * fade), ink.opacity(0)]),
                                              center: at, startRadius: r * 0.6, endRadius: halo))
        }
        canvas.fill(servers, with: .color(ink.opacity(0.9 * fade)))

        // Lightning: now and then a spark races along the net's own threads between
        // two distant stars, its tail fading behind it.
        if morph < 0.6 {
            let strength = (1 - morph / 0.6) * fade
            for slot in 0..<3 {
                drawLightning(slot: slot, in: &canvas, screen: screen, time: time, strength: strength)
            }
        }

        // Keep the top and bottom edges of the net quiet, so the status bar and
        // the swipe hint sit on clean ground.
        if morph < 1 {
            let quiet = 1 - morph
            canvas.fill(Path(CGRect(x: 0, y: size.height * 0.76, width: size.width, height: size.height * 0.24)),
                        with: .linearGradient(Gradient(colors: [background.opacity(0), background.opacity(0.94 * quiet)]),
                                              startPoint: CGPoint(x: 0, y: size.height * 0.76),
                                              endPoint: CGPoint(x: 0, y: size.height * 0.95)))
            canvas.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.12)),
                        with: .linearGradient(Gradient(colors: [background.opacity(0.8 * quiet), background.opacity(0)]),
                                              startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.12)))
        }

        // Meteors: a bright head racing between two servers, a fading tail, and a
        // brief link left behind.
        if frame.meteors > 0, fade > 0 {
            for slot in 0..<5 {
                drawMeteor(slot: slot, in: &canvas, globe: g, frame: frame, place: place, strength: frame.meteors * fade)
            }
        }

        // The door: the chosen star lights up, then opens onto the page beneath.
        if dive > 0 {
            let target = place(anchor)
            let core = 3 + 5 * min(dive * 4, 1)
            canvas.fill(Path(ellipseIn: CGRect(x: target.x - core, y: target.y - core, width: core * 2, height: core * 2)),
                        with: .color(ink.opacity(anchorZ > 0 ? 1 : 0.6)))
            let opening = max(dive - 0.4, 0) / 0.6
            let door = 4 + pow(opening, 1.6) * hypot(size.width, size.height) * 1.15
            var cut = canvas
            cut.blendMode = .destinationOut
            cut.fill(Path(ellipseIn: CGRect(x: target.x - door, y: target.y - door, width: door * 2, height: door * 2)),
                     with: .radialGradient(Gradient(stops: [
                         .init(color: .black, location: 0),
                         .init(color: .black, location: 0.72),
                         .init(color: .black.opacity(0), location: 1),
                     ]), center: target, startRadius: 0, endRadius: door))
        }
    }

    /// A crooked walk along the net's threads from one star to another a fair way
    /// off: mostly toward the goal, with a sideways jag now and then.
    private static func lightningPath(round: Int, slot: Int) -> [Int] {
        let columns = StarField.columns, rows = StarField.rows
        let seed = round * 13 + slot * 101
        func n(_ k: Int, _ salt: UInt64) -> Double { StarField.noise(seed * 64 + k, salt) }
        var column = 2 + Int(n(0, 0x71) * Double(columns - 4))
        var row = 8 + Int(n(0, 0x72) * Double(rows - 22))
        let goalColumn = min(max(column + Int((n(1, 0x73) - 0.5) * 16), 0), columns - 1)
        let goalRow = min(max(row + (n(1, 0x74) < 0.5 ? -1 : 1) * (7 + Int(n(1, 0x75) * 10)), 5), rows - 9)
        var path = [row * columns + column]
        var step = 0
        while (column != goalColumn || row != goalRow) && step < 48 {
            step += 1
            let across = goalColumn - column, down = goalRow - row
            let jag = n(step + 2, 0x76) < 0.22
            let preferAcross = n(step + 2, 0x77) * Double(abs(across) + abs(down)) < Double(abs(across))
            if jag {
                // A sideways kick, away from the main direction.
                if preferAcross, row > 1, row < rows - 2 { row += n(step + 2, 0x78) < 0.5 ? -1 : 1 }
                else if column > 0, column < columns - 1 { column += n(step + 2, 0x78) < 0.5 ? -1 : 1 }
            } else if preferAcross, across != 0 {
                column += across > 0 ? 1 : -1
            } else if down != 0 {
                row += down > 0 ? 1 : -1
            } else {
                column += across > 0 ? 1 : -1
            }
            path.append(row * columns + column)
        }
        return path
    }

    private func drawLightning(slot: Int, in canvas: inout GraphicsContext, screen: [CGPoint],
                               time: Double, strength: Double) {
        let period = 5.6 + 1.7 * Double(slot)
        let cycle = (time + 1.2 + Double(slot) * 1.37) / period
        let round = Int(cycle.rounded(.down))
        let u = cycle - Double(round)
        guard u < 0.78 else { return }
        let path = Self.lightningPath(round: round, slot: slot)
        guard path.count > 3 else { return }
        let last = Double(path.count - 1)

        // The head runs the path quickly; the tail follows, then catches up.
        let run = 0.42
        let head = last * (0.5 - 0.5 * cos(.pi * min(u / run, 1)))
        let tailLength = last * 0.5
        let tail = u < run ? max(head - tailLength, 0)
            : max(head - tailLength, 0) + (last - max(head - tailLength, 0)) * min((u - run) / 0.24, 1)

        func at(_ s: Double) -> CGPoint {
            let i = min(Int(s), path.count - 2)
            let f = s - Double(i)
            let a = screen[path[i]], b = screen[path[i + 1]]
            return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        }

        if head > tail {
            var s = tail
            var previous = at(s)
            while s < head {
                let next = min(floor(s) + 1, head)
                let point = at(next)
                let k = (next - tail) / max(head - tail, 0.001)
                let flicker = 0.8 + 0.2 * sin(time * 47 + next * 2.3)
                var segment = Path()
                segment.move(to: previous)
                segment.addLine(to: point)
                canvas.stroke(segment, with: .color(ink.opacity(0.9 * k * k * flicker * strength)),
                              style: StrokeStyle(lineWidth: 0.5 + 1.3 * k, lineCap: .round, lineJoin: .round))
                previous = point
                s = next
            }
        }

        // A bright head while it runs, and a flash where it starts and lands.
        func spark(_ point: CGPoint, _ amount: Double, _ radius: Double) {
            guard amount > 0.01 else { return }
            canvas.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                        with: .radialGradient(Gradient(colors: [ink.opacity(0.45 * amount * strength), ink.opacity(0)]),
                                              center: point, startRadius: 0, endRadius: radius))
            let core = 1.4 + 1.2 * amount
            canvas.fill(Path(ellipseIn: CGRect(x: point.x - core, y: point.y - core, width: core * 2, height: core * 2)),
                        with: .color(ink.opacity(min(amount, 1) * strength)))
        }
        if u < run { spark(at(head), 1, 9) }
        spark(screen[path[0]], max(1 - u / 0.16, 0), 10)
        spark(screen[path[path.count - 1]], u < run ? 0 : max(1 - (u - run) / 0.34, 0), 14)
    }

    private func drawMeteor(slot: Int, in canvas: inout GraphicsContext, globe g: Globe, frame: Frame,
                            place: (CGPoint) -> CGPoint, strength: Double) {
        let period = 2.4 + 0.47 * Double(slot)
        let cycle = (frame.time + Double(slot) * 0.71) / period
        let round = Int(cycle.rounded(.down))
        let u = cycle - Double(round)
        let servers = StarField.servers
        let a = StarField.all[servers[Int(StarField.noise(round * 7 + slot, 0x51) * Double(servers.count))]]
        let b = StarField.all[servers[Int(StarField.noise(round * 7 + slot, 0x62) * Double(servers.count))]]
        let dot = a.x * b.x + a.y * b.y + a.z * b.z
        let omega = acos(min(max(dot, -1), 1))
        guard omega > 0.15 else { return }

        func point(_ s: Double) -> (CGPoint, Double) {
            let wa = sin((1 - s) * omega) / sin(omega)
            let wb = sin(s * omega) / sin(omega)
            let lift = 1 + 0.16 * sin(s * .pi) * min(omega, 1.6)
            let r = frame.rotation.apply((a.x * wa + b.x * wb) * lift, (a.y * wa + b.y * wb) * lift,
                                         (a.z * wa + b.z * wb) * lift)
            return (place(CGPoint(x: g.center.x + r.x * g.radius, y: g.center.y - r.y * g.radius)), r.z)
        }

        // Travel over the first 55%, then the tail catches up and the link fades.
        let head = 1 - pow(1 - min(u / 0.55, 1), 2)
        let tailStart = u < 0.55 ? max(head - 0.38, 0) : min((u - 0.55) / 0.35, 1)
        let linger = u < 0.55 ? 1 : max(1 - (u - 0.55) / 0.45, 0)

        // The link they leave.
        var link = Path()
        var drawing = false
        for step in 0...24 {
            let s = Double(step) / 24 * head
            let (pt, z) = point(s)
            if z > -0.05 { drawing ? link.addLine(to: pt) : link.move(to: pt); drawing = true } else { drawing = false }
        }
        canvas.stroke(link, with: .color(ink.opacity(0.14 * linger * strength)), lineWidth: 0.7)

        // The tail, brightening toward the head.
        guard tailStart < head else { return }
        let segments = 12
        var previous = point(tailStart)
        for step in 1...segments {
            let s = tailStart + (head - tailStart) * Double(step) / Double(segments)
            let current = point(s)
            if previous.1 > 0, current.1 > 0 {
                var seg = Path()
                seg.move(to: previous.0)
                seg.addLine(to: current.0)
                let k = Double(step) / Double(segments)
                canvas.stroke(seg, with: .color(ink.opacity(0.75 * k * k * strength)),
                              style: StrokeStyle(lineWidth: 0.6 + 1.4 * k, lineCap: .round))
            }
            previous = current
        }
        if u < 0.6 {
            let (tip, z) = point(head)
            guard z > 0 else { return }
            let r = 2.4
            canvas.fill(Path(ellipseIn: CGRect(x: tip.x - r * 3, y: tip.y - r * 3, width: r * 6, height: r * 6)),
                        with: .radialGradient(Gradient(colors: [ink.opacity(0.5 * strength), ink.opacity(0)]),
                                              center: tip, startRadius: r * 0.5, endRadius: r * 3))
            canvas.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r, width: r * 2, height: r * 2)),
                        with: .color(ink.opacity(strength)))
        }
    }
}

#Preview("Globe") {
    OnboardingGlobeView(onFinish: { _ in })
        .moroTheme(MoroTheme(colorScheme: .dark))
        .environment(\.colorScheme, .dark)
}
