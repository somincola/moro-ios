//
//  WelcomeIllustrationView.swift
//  moro
//
//  The welcome / login-hero illustration: a line-drawn conversation bubble hovering
//  over a top-down water surface, sending ripples outward — "a message reaching the
//  network". Viewed straight from above; the dimensional feel comes from the ripples
//  themselves (each ring = a soft swell band + a crisp crest line, dissolving as it
//  spreads), a faint disturbance glow at the origin, and a drop shadow that floats
//  the bubble off the surface. Fully monochrome — the ripple ink follows the theme
//  (pale grey on light, pale white on dark). A ring exists ONLY while it expands:
//  rings are born at the centre and emitted inside-out; none sit parked waiting.
//  Used on login + the welcome page.
//

import SwiftUI

struct WelcomeIllustrationView: View {
    /// When false, render the settled state immediately (no entrance) — previews / reduce-motion.
    var animated: Bool = true

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let rippleCount = 3
    private let rippleDuration = 6.0
    private let bobDuration = 3.0

    @State private var draw: CGFloat = 0
    @State private var dotsIn = false
    @State private var typingDim = false
    /// Per-ring "emitted" flags. A ring is invisible until its flag flips; flipping it both
    /// reveals the ring and starts its expand-and-fade loop — so the only thing ever on
    /// screen is a ripple in motion (no ring parked at the centre awaiting its delay).
    @State private var ringGo: [Bool] = [false, false, false]
    @State private var floating = false

    private var motion: Bool { animated && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // Disturbance glow at the origin — breathes gently with the bubble's bob.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                theme.colors.textPrimary.opacity(0.07),
                                theme.colors.textPrimary.opacity(0),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: s * 0.3
                        )
                    )
                    .frame(width: s * 0.6, height: s * 0.6)
                    .scaleEffect(floating ? 1.07 : 0.93)
                    .animation(
                        motion
                            ? .easeInOut(duration: bobDuration).repeatForever(autoreverses: true)
                            : nil,
                        value: floating
                    )
                    .opacity(dotsIn ? 1 : 0)
                    .animation(.easeOut(duration: 0.8), value: dotsIn)

                // Water ripples: each ring is a soft swell band with a crisp crest line on
                // top — the band blurs/softens as it spreads (blur scales with the ring),
                // so the wave reads as dissolving water, not a geometric outline. Pale
                // monochrome ink; each ring appears only once it starts expanding.
                ForEach(0..<rippleCount, id: \.self) { i in
                    ZStack {
                        Circle()
                            .stroke(theme.colors.textPrimary.opacity(0.16), lineWidth: 7)
                            .blur(radius: 5)
                        Circle()
                            .stroke(theme.colors.textPrimary.opacity(0.40), lineWidth: 1.4)
                    }
                    .frame(width: s, height: s)
                    .scaleEffect(ringGo[i] ? 1.0 : 0.3)
                    .opacity(ringGo[i] ? 0 : 0.85)
                    .animation(
                        .easeOut(duration: rippleDuration).repeatForever(autoreverses: false),
                        value: ringGo[i]
                    )
                    // Master visibility: hidden until this ring is emitted, revealed instantly
                    // (unanimated) at the same moment its expand loop starts — so a ring never
                    // sits parked at the centre waiting its turn.
                    .opacity(ringGo[i] ? 1 : 0)
                    .animation(nil, value: ringGo[i])
                }

                // The bubble hovers above the surface: drop shadow + a gentle bob.
                bubble(s: s)
                    .shadow(color: theme.colors.textPrimary.opacity(0.16), radius: 9, y: 6)
                    .offset(y: floating ? -s * 0.015 : s * 0.005)
                    .animation(
                        motion
                            ? .easeInOut(duration: bobDuration).repeatForever(autoreverses: true)
                            : nil,
                        value: floating
                    )
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityHidden(true)
        .task {
            guard motion else {
                draw = 1
                dotsIn = true
                return
            }
            withAnimation(.easeOut(duration: 0.7)) { draw = 1 }
            // First ripple sets out immediately, the rest follow from the centre at an
            // even cadence — emission starts right away, nothing waits on the entrance.
            ringGo[0] = true
            try? await Task.sleep(for: .milliseconds(640))
            withAnimation(.easeOut(duration: 0.3)) { dotsIn = true }
            typingDim = true
            floating = true
            // Emit the remaining rings every `stagger` seconds (measured from ring 0 at t=0;
            // 640ms of that interval was already spent on the entrance sleep above).
            let stagger = rippleDuration / Double(rippleCount)
            try? await Task.sleep(for: .seconds(stagger) - .milliseconds(640))
            for i in 1..<rippleCount {
                ringGo[i] = true
                if i + 1 < rippleCount {
                    try? await Task.sleep(for: .seconds(stagger))
                }
            }
        }
    }

    // MARK: - Bubble (line-drawn, strokes itself on, typing dots shimmer)

    @ViewBuilder
    private func bubble(s: CGFloat) -> some View {
        let w = s * 0.20
        let h = w * 0.64
        ZStack {
            SpeechBubbleShape()
                .trim(from: 0, to: draw)
                .stroke(
                    theme.colors.textPrimary,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

            HStack(spacing: w * 0.09) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(theme.colors.textPrimary)
                        .frame(width: w * 0.08, height: w * 0.08)
                        .opacity(typingDim ? 0.35 : 1)
                        .animation(
                            motion
                                ? .easeInOut(duration: 0.55).repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.18)
                                : nil,
                            value: typingDim
                        )
                }
            }
            .opacity(dotsIn ? 1 : 0)
            .offset(y: -h * 0.10)
        }
        .frame(width: w, height: h * 1.2)
    }
}

/// A rounded speech bubble with a lower-left tail, drawn as one continuous path so
/// `.trim(from:to:)` can stroke it on like a pen. The body occupies the upper `1/1.2`
/// of the frame; the remainder is tail headroom.
private struct SpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let bodyH = rect.height / 1.2
        let r = bodyH * 0.34
        let tailX = w * 0.22
        let tailW = w * 0.17
        let tailH = bodyH * 0.26
        let tipX = tailX + tailW * 0.28

        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: w - r, y: 0))
        p.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: bodyH - r))
        p.addQuadCurve(to: CGPoint(x: w - r, y: bodyH), control: CGPoint(x: w, y: bodyH))
        p.addLine(to: CGPoint(x: tailX + tailW, y: bodyH))
        p.addLine(to: CGPoint(x: tipX, y: bodyH + tailH))
        p.addLine(to: CGPoint(x: tailX, y: bodyH))
        p.addLine(to: CGPoint(x: r, y: bodyH))
        p.addQuadCurve(to: CGPoint(x: 0, y: bodyH - r), control: CGPoint(x: 0, y: bodyH))
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        p.closeSubpath()
        return p
    }
}

#Preview {
    HStack(spacing: 0) {
        WelcomeIllustrationView()
            .frame(width: 200, height: 200)
            .frame(maxWidth: .infinity)
            .moroTheme(MoroTheme())
        WelcomeIllustrationView()
            .frame(width: 200, height: 200)
            .frame(maxWidth: .infinity)
            .environment(\.colorScheme, .dark)
            .moroTheme(MoroTheme(colorScheme: .dark))
            .background(Color.black)
    }
}
