//
//  LoginStarfieldView.swift
//  moro
//
//  The login page's sky. Every known server is one star, always in the same place,
//  loosely linked to its neighbours. Typing a domain lights every star that could
//  still be it; as the text narrows, the rest go out, and once only one remains it
//  rises to the top of the sky with its name. A well-formed domain nobody listed is
//  born there as a new star. Purely decorative: the text field stays the source of
//  truth for logging in.
//

import SwiftUI

struct LoginStarfieldView: View {
    /// The field's raw text.
    let query: String

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = StarfieldModel()
    private let sceneStart = Date.now

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { context in
                let date = reduceMotion ? Date.distantFuture : context.date
                ZStack {
                    Canvas { canvas, size in
                        draw(in: &canvas, size: size, date: date)
                    }
                    if let lock = model.lock {
                        let appear = smooth(lock.start, date, 0.45, delay: 0.35)
                        let slot = StarfieldModel.slot(in: proxy.size)
                        Text(lock.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .opacity(appear)
                            .offset(y: (1 - appear) * 6)
                            .position(x: slot.x, y: slot.y + 34)
                    }
                }
            }
        }
        .onAppear { model.update(query: query, now: reduceMotion ? .distantPast : .now) }
        .onChange(of: query) { _, text in model.update(query: text, now: reduceMotion ? .distantPast : .now) }
        .accessibilityHidden(true)
    }

    private var ink: Color { theme.colors.textPrimary }
    private var dark: Bool { theme.colorScheme == .dark }

    private func smooth(_ start: Date, _ now: Date, _ duration: Double, delay: Double = 0) -> Double {
        let t = min(max((now.timeIntervalSince(start) - delay) / duration, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func draw(in canvas: inout GraphicsContext, size: CGSize, date: Date) {
        let time = date.timeIntervalSince(sceneStart)
        let stars = StarfieldLayout.stars
        let positions = stars.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let levels = model.levels.map { $0.value(at: date) }

        // Dust behind the network: a few soft, out-of-focus stars, and many fine ones.
        var dust = Path()
        for (index, mote) in StarfieldLayout.dust.enumerated() {
            let twinkle = 0.5 + 0.5 * sin(time * (0.7 + mote.speed) + Double(index))
            let at = CGPoint(x: mote.x * size.width, y: mote.y * size.height)
            if index % 4 == 0 {
                let r = 3 + 4.5 * mote.speed
                canvas.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)),
                            with: .radialGradient(Gradient(colors: [ink.opacity((dark ? 0.2 : 0.12) * (0.55 + 0.45 * twinkle)),
                                                                    ink.opacity(0)]),
                                                  center: at, startRadius: 0, endRadius: r))
            } else {
                let r = 0.6 + 0.9 * twinkle
                dust.addEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
            }
        }
        canvas.fill(dust, with: .color(ink.opacity(dark ? 0.3 : 0.2)))

        // The web between neighbours, brighter where both ends are lit.
        var faint = Path(), bright = Path()
        for (a, b) in StarfieldLayout.links where !model.isMoving(a) && !model.isMoving(b) {
            let level = min(levels[a], levels[b])
            if level > 0.7 { bright.move(to: positions[a]); bright.addLine(to: positions[b]) }
            else if level > 0.2 { faint.move(to: positions[a]); faint.addLine(to: positions[b]) }
        }
        canvas.stroke(faint, with: .color(ink.opacity(dark ? 0.13 : 0.11)), lineWidth: 0.6)
        canvas.stroke(bright, with: .color(ink.opacity(0.28)), lineWidth: 0.7)

        // Stars, batched by brightness; lit ones get a soft halo and a one-off flare.
        let buckets = 6
        var dots = Array(repeating: Path(), count: buckets)
        var halos = Path()
        for index in stars.indices where !model.isMoving(index) {
            let level = levels[index]
            let twinkle = 0.85 + 0.15 * sin(time * 1.7 + stars[index].phase)
            let alpha = (0.12 + 0.83 * level) * twinkle
            let r = 1 + 1.5 * level
            let p = positions[index]
            let bucket = min(Int(alpha * Double(buckets)), buckets - 1)
            dots[bucket].addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            if level > 0.75 {
                let h = r * 3
                halos.addEllipse(in: CGRect(x: p.x - h, y: p.y - h, width: h * 2, height: h * 2))
            }
            if let lit = model.levels[index].litAt, !reduceMotion {
                let age = date.timeIntervalSince(lit)
                if age < 0.7 {
                    let ring = 3 + 14 * age / 0.7
                    canvas.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                                  with: .color(ink.opacity(0.4 * (1 - age / 0.7))), lineWidth: 0.8)
                }
            }
        }
        canvas.fill(halos, with: .color(ink.opacity(0.07)))
        for (index, path) in dots.enumerated() {
            canvas.fill(path, with: .color(ink.opacity((Double(index) + 0.5) / Double(buckets))))
        }

        // A star flying home after being released.
        if let returning = model.returning {
            let t = smooth(returning.start, date, 0.6)
            let home = positions[returning.index]
            let slot = StarfieldModel.slot(in: size)
            let p = CGPoint(x: slot.x + (home.x - slot.x) * t, y: slot.y + (home.y - slot.y) * t)
            let r = 5 - 3.5 * t
            canvas.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                        with: .color(ink.opacity(1 - 0.6 * t)))
        }

        // The chosen server: it rises to the slot, links back to its neighbours and
        // keeps a slow pulse.
        if let lock = model.lock {
            let slot = StarfieldModel.slot(in: size)
            let rise = smooth(lock.start, date, 0.7)
            let origin = lock.index.map { positions[$0] } ?? slot
            let p = CGPoint(x: origin.x + (slot.x - origin.x) * rise, y: origin.y + (slot.y - origin.y) * rise)
            let born = lock.index == nil ? smooth(lock.start, date, 0.6) : 1

            if let index = lock.index {
                var tethers = Path()
                for neighbour in StarfieldLayout.neighbours[index] {
                    tethers.move(to: p)
                    tethers.addLine(to: positions[neighbour])
                }
                canvas.stroke(tethers, with: .color(ink.opacity(0.22 * rise)), style: StrokeStyle(lineWidth: 0.7, dash: [2, 4]))
            }

            let halo = 34 * born
            canvas.fill(Path(ellipseIn: CGRect(x: p.x - halo, y: p.y - halo, width: halo * 2, height: halo * 2)),
                        with: .radialGradient(Gradient(colors: [ink.opacity(dark ? 0.22 : 0.12), ink.opacity(0)]),
                                              center: p, startRadius: 0, endRadius: halo))
            if !reduceMotion {
                for offset in [0.0, 0.5] {
                    let phase = ((time / 1.8) + offset).truncatingRemainder(dividingBy: 1)
                    let ring = (6 + 22 * phase) * born
                    canvas.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                                  with: .color(ink.opacity(0.45 * (1 - phase) * rise)), lineWidth: 1)
                }
            }
            let core = (3 + 2.5 * rise) * born
            canvas.fill(Path(ellipseIn: CGRect(x: p.x - core, y: p.y - core, width: core * 2, height: core * 2)),
                        with: .color(ink))
        }
    }
}

// MARK: - Layout

enum StarfieldLayout {
    struct Star { let x: Double, y: Double, phase: Double }

    static func noise(_ index: Int, _ salt: UInt64) -> Double {
        var h = UInt64(truncatingIfNeeded: index) &* 0x9E37_79B9_7F4A_7C15 ^ salt
        h ^= h >> 31; h = h &* 0xBF58_476D_1CE4_E5B9; h ^= h >> 27
        return Double(h % 10_000) / 10_000
    }

    /// One star per known server; the same domain always lands in the same place.
    static let stars: [Star] = KnownServers.domains.map { domain in
        let seed = Int(truncatingIfNeeded: ProfilePlaceholderPalette.stableHash(domain))
        return Star(x: 0.06 + 0.88 * noise(seed, 0x51), y: 0.06 + 0.52 * noise(seed, 0x62), phase: noise(seed, 0x73) * 6.28)
    }

    static let dust: [(x: Double, y: Double, speed: Double)] = (0..<140).map { i in
        (noise(i, 0x81), noise(i, 0x92), noise(i, 0xA3))
    }

    /// Each star's two nearest neighbours (the sky is about twice as tall as wide).
    static let neighbours: [[Int]] = stars.indices.map { i in
        stars.indices.filter { $0 != i }
            .sorted { hypot(stars[$0].x - stars[i].x, (stars[$0].y - stars[i].y) * 2) <
                      hypot(stars[$1].x - stars[i].x, (stars[$1].y - stars[i].y) * 2) }
            .prefix(2).map { $0 }
    }

    static let links: [(Int, Int)] = {
        var seen = Set<Int>()
        var pairs: [(Int, Int)] = []
        for (i, near) in neighbours.enumerated() {
            for j in near {
                let key = min(i, j) * 10_000 + max(i, j)
                if seen.insert(key).inserted { pairs.append((i, j)) }
            }
        }
        return pairs
    }()
}

// MARK: - State

struct StarfieldModel {
    struct Level {
        var from = 0.0
        var to = 0.0
        var start = Date.distantPast
        var litAt: Date?
        func value(at date: Date) -> Double {
            let t = min(max(date.timeIntervalSince(start) / 0.45, 0), 1)
            return from + (to - from) * t * t * (3 - 2 * t)
        }
    }

    struct Lock: Equatable {
        let index: Int?
        let label: String
        let start: Date
    }

    var levels = Array(repeating: Level(), count: KnownServers.domains.count)
    var lock: Lock?
    var returning: (index: Int, start: Date)?

    /// Where the chosen server settles: centred, in the upper part of the sky.
    static func slot(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * 0.2)
    }

    func isMoving(_ index: Int) -> Bool {
        lock?.index == index || returning?.index == index
    }

    /// The text as a domain: no scheme, no path, and only the server part of a handle.
    static func normalize(_ text: String) -> String {
        var value = AuthDomainUtility.sanitize(text)
        if let at = value.lastIndex(of: "@") { value = String(value[value.index(after: at)...]) }
        return value
    }

    mutating func update(query: String, now: Date) {
        let q = Self.normalize(query)
        let domains = KnownServers.domains
        let matches: Set<Int> = q.isEmpty ? [] : Set(domains.indices.filter { domains[$0].contains(q) })

        var newLock: (index: Int?, label: String)?
        if let exact = domains.firstIndex(of: q) {
            newLock = (exact, q)
        } else if matches.count == 1, let only = matches.first {
            newLock = (only, domains[only])
        } else if matches.isEmpty, AuthDomainUtility.isLikelyDomain(q) {
            newLock = (nil, q)
        }

        if newLock?.index != lock?.index || newLock?.label != lock?.label {
            if let old = lock?.index, old != newLock?.index { returning = (old, now) }
            lock = newLock.map { Lock(index: $0.index, label: $0.label, start: now) }
        }

        let neighbours = lock?.index.map { Set(StarfieldLayout.neighbours[$0]) } ?? []
        for index in levels.indices {
            let target: Double
            if q.isEmpty { target = 0.5 }
            else if lock != nil { target = neighbours.contains(index) ? 0.65 : 0.3 }
            else { target = matches.contains(index) ? 1 : 0.22 }
            guard abs(levels[index].to - target) > 0.001 else { continue }
            let current = levels[index].value(at: now)
            let lit = target == 1 && levels[index].to < 1
            levels[index] = Level(from: current, to: target, start: now, litAt: lit ? now : levels[index].litAt)
        }
    }
}
