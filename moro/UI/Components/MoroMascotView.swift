//
//  MoroMascotView.swift
//  moro
//
//  Minimalist monochrome line-art elephant mascot series echoing Moro's app icon.
//  Shared geometry powers both SwiftUI views and UIKit search state views.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

enum MoroMascotExpression: Equatable, Sendable, CaseIterable {
    /// Serene relaxed expression for general empty lists, profiles, announcements, and inbox.
    case calm
    /// Perked, inquisitive expression for search with no matches, empty discovery, and filters.
    case curious
    /// Gently drooped trunk with broken-signal accent for network and load failures.
    case offline
    /// Attentive silhouette with softly pulsing dots for lightweight non-skeleton loading states.
    case thinking
    /// Peaceful closed-eye rest for hidden collections, unsupported server features, or quiet ends.
    case resting
}

// MARK: - Shared Normalized Geometry (100x100 canvas)

enum MoroMascotGeometry {
    struct Layers {
        let primaryStroke: CGPath
        let secondaryStroke: CGPath
        let primaryFill: CGPath
        let thinkingDots: [CGPoint]
        let thinkingDotRadii: [CGFloat]
    }

    static func layers(for expression: MoroMascotExpression, in size: CGSize) -> Layers {
        let side = min(size.width, size.height)
        let originX = (size.width - side) * 0.5
        let originY = (size.height - side) * 0.5
        let scale = side / 100.0

        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * scale, y: originY + y * scale)
        }

        let primary = CGMutablePath()
        let secondary = CGMutablePath()
        let fill = CGMutablePath()

        // Back / right ear peeking behind forehead — echoes the secondary ear on Moro's app icon.
        secondary.move(to: pt(64.0, 35.5))
        secondary.addQuadCurve(to: pt(78.5, 32.0), control: pt(71.5, 30.5))
        secondary.addCurve(to: pt(75.0, 48.5), control1: pt(80.2, 37.5), control2: pt(78.2, 45.0))
        secondary.addQuadCurve(to: pt(70.5, 50.8), control: pt(73.0, 50.0))

        // Left wing-ear (soft rounded silhouette matching Moro's icon proportions).
        primary.move(to: pt(39.0, 35.0))
        primary.addCurve(to: pt(17.5, 37.5), control1: pt(31.5, 26.5), control2: pt(20.5, 29.0))
        primary.addCurve(to: pt(24.5, 65.5), control1: pt(13.0, 46.5), control2: pt(16.8, 59.0))
        primary.addCurve(to: pt(40.5, 61.5), control1: pt(29.8, 70.2), control2: pt(36.2, 67.8))

        // Crown + forehead + expressive trunk.
        primary.move(to: pt(39.0, 35.0))
        primary.addCurve(to: pt(69.0, 43.5), control1: pt(47.0, 23.5), control2: pt(64.5, 25.5))

        switch expression {
        case .offline:
            // Gently drooped trunk conveying a calm connection hiccup while keeping clear elephant silhouette.
            primary.addCurve(to: pt(76.5, 67.0), control1: pt(72.5, 51.5), control2: pt(76.5, 59.5))
            primary.addCurve(to: pt(74.0, 75.5), control1: pt(78.5, 71.0), control2: pt(77.5, 74.8))
            primary.addCurve(to: pt(67.5, 71.0), control1: pt(70.8, 76.2), control2: pt(68.8, 74.2))
            primary.addCurve(to: pt(56.5, 66.5), control1: pt(65.0, 67.5), control2: pt(61.5, 67.5))
            primary.addQuadCurve(to: pt(46.5, 63.0), control: pt(51.5, 65.8))

        case .curious:
            // Slightly higher inquisitive upturned trunk.
            primary.addCurve(to: pt(73.5, 59.5), control1: pt(72.0, 50.0), control2: pt(71.0, 55.5))
            primary.addCurve(to: pt(85.5, 52.0), control1: pt(77.0, 64.0), control2: pt(85.0, 59.5))
            primary.addQuadCurve(to: pt(85.8, 59.5), control: pt(89.0, 55.5))
            primary.addCurve(to: pt(58.0, 68.0), control1: pt(80.2, 69.0), control2: pt(67.5, 71.8))
            primary.addQuadCurve(to: pt(46.5, 63.0), control: pt(52.0, 66.2))

        case .calm, .thinking, .resting:
            // Signature playful short upturned trunk.
            primary.addCurve(to: pt(73.5, 61.5), control1: pt(72.0, 50.5), control2: pt(71.0, 56.5))
            primary.addCurve(to: pt(84.0, 56.5), control1: pt(77.0, 65.8), control2: pt(84.0, 62.8))
            primary.addQuadCurve(to: pt(83.8, 63.5), control: pt(87.2, 60.0))
            primary.addCurve(to: pt(58.0, 69.0), control1: pt(78.2, 71.2), control2: pt(67.2, 72.5))
            primary.addQuadCurve(to: pt(46.5, 63.0), control: pt(52.0, 66.8))
        }

        // Delicate little tusk curve hugging the lower cheek — subtle nod to Moro's app icon.
        secondary.move(to: pt(46.5, 64.5))
        secondary.addQuadCurve(to: pt(54.5, 73.0), control: pt(47.8, 71.2))

        // Facial expression + floating micro-accent.
        var thinkingDots: [CGPoint] = []
        var thinkingDotRadii: [CGFloat] = []

        switch expression {
        case .calm:
            // Warm gentle upturned smile-eye arc.
            primary.move(to: pt(53.0, 47.5))
            primary.addQuadCurve(to: pt(61.0, 47.5), control: pt(57.0, 43.0))

        case .curious:
            // Crisp attentive eye dot + soft raised brow.
            let r = 2.4 * scale
            let center = pt(57.5, 46.5)
            fill.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

            secondary.move(to: pt(53.5, 40.0))
            secondary.addQuadCurve(to: pt(60.5, 39.0), control: pt(57.0, 38.0))

            // Minimalist floating question curl cleanly above the back ear.
            secondary.move(to: pt(84.0, 15.5))
            secondary.addCurve(to: pt(90.5, 14.0), control1: pt(84.5, 11.0), control2: pt(90.0, 10.5))
            secondary.addCurve(to: pt(87.5, 21.0), control1: pt(91.0, 17.5), control2: pt(87.5, 18.2))
            secondary.addLine(to: pt(87.5, 22.8))

            let qDot = pt(87.5, 26.8)
            let qR = 1.3 * scale
            fill.addEllipse(in: CGRect(x: qDot.x - qR, y: qDot.y - qR, width: qR * 2, height: qR * 2))

        case .offline:
            // Soft rounded cross-squint eye.
            primary.move(to: pt(54.2, 44.2))
            primary.addLine(to: pt(59.8, 49.8))
            primary.move(to: pt(59.8, 44.2))
            primary.addLine(to: pt(54.2, 49.8))

            // Subtle disconnected wave/signal glyph floating cleanly above the crown.
            secondary.move(to: pt(47.0, 13.0))
            secondary.addQuadCurve(to: pt(63.0, 13.0), control: pt(55.0, 7.2))
            secondary.move(to: pt(50.5, 17.2))
            secondary.addQuadCurve(to: pt(59.5, 17.2), control: pt(55.0, 14.2))
            secondary.move(to: pt(58.8, 8.0))
            secondary.addLine(to: pt(51.2, 19.2))

        case .thinking:
            // Attentive little eye dot; 3 ascending dots are rendered as separately animatable circles.
            let r = 2.3 * scale
            let center = pt(57.5, 46.5)
            fill.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))

            thinkingDots = [pt(85.0, 42.0), pt(90.0, 33.5), pt(94.0, 24.5)]
            thinkingDotRadii = [2.1 * scale, 2.3 * scale, 2.5 * scale]

        case .resting:
            // Peaceful closed downward eye arc.
            primary.move(to: pt(53.0, 46.0))
            primary.addQuadCurve(to: pt(61.0, 46.0), control: pt(57.0, 50.2))

            // Delicate floating "z" marks cleanly above right ear.
            secondary.move(to: pt(76.0, 17.5))
            secondary.addLine(to: pt(82.5, 17.5))
            secondary.addLine(to: pt(76.0, 23.5))
            secondary.addLine(to: pt(82.5, 23.5))

            secondary.move(to: pt(85.5, 10.5))
            secondary.addLine(to: pt(90.2, 10.5))
            secondary.addLine(to: pt(85.5, 14.8))
            secondary.addLine(to: pt(90.2, 14.8))
        }

        return Layers(
            primaryStroke: primary,
            secondaryStroke: secondary,
            primaryFill: fill,
            thinkingDots: thinkingDots,
            thinkingDotRadii: thinkingDotRadii
        )
    }

    static func strokeWidth(for size: CGFloat) -> CGFloat {
        max(1.35, min(2.1, size * 0.032))
    }
}

// MARK: - SwiftUI View

struct MoroMascotView: View {
    let expression: MoroMascotExpression
    var size: CGFloat = 56
    var animated: Bool = true

    @Environment(\.moroTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isBreathing = false
    @State private var dotPulse = false

    private var shouldAnimate: Bool {
        animated && !reduceMotion && expression == .thinking
    }

    var body: some View {
        let canvasSize = CGSize(width: size, height: size)
        let layers = MoroMascotGeometry.layers(for: expression, in: canvasSize)
        let lineWidth = MoroMascotGeometry.strokeWidth(for: size)
        let primaryStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let secondaryStyle = StrokeStyle(
            lineWidth: max(1.15, lineWidth * 0.85),
            lineCap: .round,
            lineJoin: .round
        )

        ZStack {
            ZStack {
                Path(layers.secondaryStroke)
                    .stroke(secondaryInk, style: secondaryStyle)

                Path(layers.primaryStroke)
                    .stroke(primaryInk, style: primaryStyle)

                Path(layers.primaryFill)
                    .fill(primaryInk)
            }
            .offset(y: shouldAnimate && isBreathing ? -1.4 : 0.6)
            .animation(
                shouldAnimate
                    ? .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                    : nil,
                value: isBreathing
            )

            if expression == .thinking {
                ForEach(Array(layers.thinkingDots.enumerated()), id: \.offset) { index, point in
                    let radius = layers.thinkingDotRadii[index]
                    Circle()
                        .fill(primaryInk)
                        .frame(width: radius * 2, height: radius * 2)
                        .position(point)
                        .opacity(thinkingDotOpacity(index: index))
                        .scaleEffect(shouldAnimate && dotPulse ? 1.08 : 0.88)
                        .animation(
                            shouldAnimate
                                ? .easeInOut(duration: 0.72)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.22)
                                : nil,
                            value: dotPulse
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .onAppear {
            startMotionIfNeeded()
        }
        .onChange(of: shouldAnimate) { _, active in
            if active {
                startMotionIfNeeded()
            } else {
                isBreathing = false
                dotPulse = false
            }
        }
    }

    private func thinkingDotOpacity(index: Int) -> Double {
        guard shouldAnimate else {
            return [0.45, 0.65, 0.85][index]
        }
        return dotPulse ? 0.88 : 0.22
    }

    private func startMotionIfNeeded() {
        guard shouldAnimate else { return }
        isBreathing = true
        dotPulse = true
    }

    private var primaryInk: Color {
        theme.colors.textPrimary.opacity(colorScheme == .dark ? 0.84 : 0.78)
    }

    private var secondaryInk: Color {
        theme.colors.textSecondary.opacity(colorScheme == .dark ? 0.56 : 0.52)
    }
}

// MARK: - Lightweight Loading State

struct MoroLoadingStateView: View {
    var message: String? = nil
    var mascotSize: CGFloat = 44

    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.s) {
            MoroMascotView(expression: .thinking, size: mascotSize)

            if let message, !message.isEmpty {
                Text(message)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, theme.spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message ?? MoroL10n.Search.loading))
    }
}

// MARK: - UIKit Bridge (Shared Paths for SearchCoreViewController)

#if os(iOS)
final class MoroMascotUIView: UIView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let expression: MoroMascotExpression
    private let bodyContainer = CALayer()
    private let secondaryLayer = CAShapeLayer()
    private let primaryLayer = CAShapeLayer()
    private let fillLayer = CAShapeLayer()
    private var dotLayers: [CAShapeLayer] = []
    private var isAnimationActive = false

    private let breatheAnimationKey = "moro.mascot.breathe"
    private let dotOpacityAnimationKey = "moro.mascot.dot.opacity"
    private let dotScaleAnimationKey = "moro.mascot.dot.scale"

    init(expression: MoroMascotExpression) {
        self.expression = expression
        super.init(frame: .zero)
        isAccessibilityElement = false
        backgroundColor = .clear

        layer.addSublayer(bodyContainer)
        for strokeLayer in [secondaryLayer, primaryLayer] {
            strokeLayer.fillColor = UIColor.clear.cgColor
            strokeLayer.lineCap = .round
            strokeLayer.lineJoin = .round
            bodyContainer.addSublayer(strokeLayer)
        }
        bodyContainer.addSublayer(fillLayer)

        if expression == .thinking {
            for _ in 0..<3 {
                let dot = CAShapeLayer()
                layer.addSublayer(dot)
                dotLayers.append(dot)
            }
        }
        apply(theme: MoroTheme())
    }

    required init?(coder: NSCoder) {
        self.expression = .calm
        super.init(coder: coder)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        bodyContainer.frame = bounds
        secondaryLayer.frame = bounds
        primaryLayer.frame = bounds
        fillLayer.frame = bounds

        let side = min(bounds.width, bounds.height)
        guard side > 0 else { return }
        let layers = MoroMascotGeometry.layers(for: expression, in: bounds.size)
        let lineWidth = MoroMascotGeometry.strokeWidth(for: side)

        secondaryLayer.lineWidth = max(1.15, lineWidth * 0.85)
        secondaryLayer.path = layers.secondaryStroke
        primaryLayer.lineWidth = lineWidth
        primaryLayer.path = layers.primaryStroke
        fillLayer.path = layers.primaryFill

        if expression == .thinking, dotLayers.count == layers.thinkingDots.count {
            for (index, dot) in dotLayers.enumerated() {
                let r = layers.thinkingDotRadii[index]
                let center = layers.thinkingDots[index]
                dot.bounds = CGRect(x: 0, y: 0, width: r * 2, height: r * 2)
                dot.position = center
                dot.path = CGPath(ellipseIn: dot.bounds, transform: nil)
                if !isAnimationActive || UIAccessibility.isReduceMotionEnabled {
                    dot.opacity = [0.45, 0.65, 0.85][index]
                }
            }
        }
    }

    func apply(theme: MoroTheme) {
        let palette = theme.uiKitPalette
        let primaryAlpha: CGFloat = theme.colorScheme == .dark ? 0.84 : 0.78
        let secondaryAlpha: CGFloat = theme.colorScheme == .dark ? 0.56 : 0.52
        let primary = palette.textPrimary.withAlphaComponent(primaryAlpha).cgColor
        let secondary = palette.textSecondary.withAlphaComponent(secondaryAlpha).cgColor

        primaryLayer.strokeColor = primary
        secondaryLayer.strokeColor = secondary
        fillLayer.fillColor = primary
        for dot in dotLayers {
            dot.fillColor = primary
        }
    }

    func setAnimationActive(_ active: Bool) {
        guard expression == .thinking else { return }
        guard active != isAnimationActive else { return }
        isAnimationActive = active

        if !active || UIAccessibility.isReduceMotionEnabled {
            bodyContainer.removeAnimation(forKey: breatheAnimationKey)
            for (index, dot) in dotLayers.enumerated() {
                dot.removeAnimation(forKey: dotOpacityAnimationKey)
                dot.removeAnimation(forKey: dotScaleAnimationKey)
                dot.opacity = [0.45, 0.65, 0.85][index]
            }
            return
        }

        let breathe = CABasicAnimation(keyPath: "transform.translation.y")
        breathe.fromValue = 0.6
        breathe.toValue = -1.4
        breathe.duration = 1.4
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bodyContainer.add(breathe, forKey: breatheAnimationKey)

        let now = CACurrentMediaTime()
        for (index, dot) in dotLayers.enumerated() {
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.22
            opacity.toValue = 0.88
            opacity.duration = 0.72
            opacity.beginTime = now + Double(index) * 0.22
            opacity.autoreverses = true
            opacity.repeatCount = .infinity
            opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(opacity, forKey: dotOpacityAnimationKey)

            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.88
            scale.toValue = 1.08
            scale.duration = 0.72
            scale.beginTime = now + Double(index) * 0.22
            scale.autoreverses = true
            scale.repeatCount = .infinity
            scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(scale, forKey: dotScaleAnimationKey)
        }
    }
}
#endif

#Preview {
    VStack(spacing: 28) {
        HStack(spacing: 24) {
            ForEach(MoroMascotExpression.allCases, id: \.self) { expression in
                VStack(spacing: 8) {
                    MoroMascotView(expression: expression, size: 56)
                    Text(String(describing: expression))
                        .font(.caption2)
                }
            }
        }
        .padding()
        .background(Color.white)
        .moroTheme(MoroTheme(colorScheme: .light))

        HStack(spacing: 24) {
            ForEach(MoroMascotExpression.allCases, id: \.self) { expression in
                VStack(spacing: 8) {
                    MoroMascotView(expression: expression, size: 56)
                    Text(String(describing: expression))
                        .font(.caption2)
                        .foregroundStyle(.white)
                }
            }
        }
        .padding()
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .moroTheme(MoroTheme(colorScheme: .dark))
    }
}
