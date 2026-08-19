//
//  InteractionEffect.swift
//  moro
//
//  Deterministic, locally rendered effects for post actions.
//

import SwiftUI

enum PostActionRole: String, Codable, CaseIterable, Hashable {
    case reply
    case boost
    case like
    case bookmark
}

struct HeartBloomPreset {
    let duration: TimeInterval
    let ringColor: Color
    let particleColors: [Color]
    let particleCount: Int

    static let standard = HeartBloomPreset(
        duration: 0.42,
        ringColor: Color(red: 0.78, green: 0.25, blue: 0.88),
        particleColors: [
            Color(red: 0.98, green: 0.24, blue: 0.55),
            Color(red: 0.62, green: 0.37, blue: 0.92),
            Color(red: 0.20, green: 0.72, blue: 0.82),
        ],
        particleCount: 7
    )

    var effectiveDuration: TimeInterval {
        min(max(duration, 0.1), 2)
    }

    var effectiveParticleCount: Int {
        min(max(particleCount, 1), 14)
    }
}

enum PostActionEffect {
    case symbolBounce
    case bookmarkDrop
    case heartBloom(HeartBloomPreset)

    var duration: TimeInterval {
        switch self {
        case .symbolBounce, .bookmarkDrop:
            return AnimationTokens.duration.md
        case .heartBloom(let preset):
            return preset.effectiveDuration
        }
    }
}

struct PostActionAnimationPreset {
    let id: String
    let effect: PostActionEffect
}

struct PostActionAnimationCampaign {
    let id: String
    let interval: DateInterval
    let priority: Int
    let presets: [PostActionRole: PostActionAnimationPreset]
}

/// Resolves an action's animation at tap time. Future remote configuration can
/// replace this environment value after validating and caching its campaign data.
struct PostActionAnimationSchedule {
    let defaultPresets: [PostActionRole: PostActionAnimationPreset]
    let campaigns: [PostActionAnimationCampaign]

    static let standard = PostActionAnimationSchedule(
        defaultPresets: [
            .reply: .init(id: "standard-reply", effect: .symbolBounce),
            .boost: .init(id: "standard-boost", effect: .symbolBounce),
            .like: .init(id: "standard-heart-bloom", effect: .heartBloom(.standard)),
            .bookmark: .init(id: "standard-bookmark-drop", effect: .bookmarkDrop),
        ],
        campaigns: []
    )

    func preset(for role: PostActionRole, at date: Date = Date()) -> PostActionAnimationPreset {
        var selected: (priority: Int, id: String, preset: PostActionAnimationPreset)?

        for campaign in campaigns {
            guard campaign.interval.contains(date), let preset = campaign.presets[role] else { continue }
            if let current = selected {
                if campaign.priority > current.priority
                    || (campaign.priority == current.priority && campaign.id < current.id) {
                    selected = (campaign.priority, campaign.id, preset)
                }
            } else {
                selected = (campaign.priority, campaign.id, preset)
            }
        }

        return selected?.preset
            ?? defaultPresets[role]
            ?? PostActionAnimationPreset(id: "fallback", effect: .symbolBounce)
    }
}

private struct PostActionAnimationScheduleKey: EnvironmentKey {
    static let defaultValue = PostActionAnimationSchedule.standard
}

extension EnvironmentValues {
    var postActionAnimationSchedule: PostActionAnimationSchedule {
        get { self[PostActionAnimationScheduleKey.self] }
        set { self[PostActionAnimationScheduleKey.self] = newValue }
    }
}

struct PostActionEffectPlayback: Identifiable {
    let id = UUID()
    let preset: PostActionAnimationPreset
    let startedAt = Date()
}

struct HeartBloomFrame {
    let outerRadius: CGFloat
    let holeRadius: CGFloat
    let ringOpacity: Double
    let outlineScale: CGFloat
    let outlineOpacity: Double
    let heartScale: CGFloat
    let heartOpacity: Double
    let particleProgress: CGFloat
    let particleSplit: CGFloat
    let particleOpacity: Double
}

enum HeartBloomTimeline {
    static func frame(at rawProgress: Double) -> HeartBloomFrame {
        let progress = clamp(rawProgress)
        let outerExpansion = easeOutCubic(segment(progress, from: 0.03, to: 0.28))
        let outerDrift = smoothstep(segment(progress, from: 0.28, to: 0.74))
        let outerRadius = 11 * outerExpansion + 1.5 * outerDrift
        let holeProgress = smoothstep(segment(progress, from: 0.23, to: 0.76))
        let holeRadius = outerRadius * holeProgress
        let ringOpacity = segment(progress, from: 0.02, to: 0.10)
            * (1 - segment(progress, from: 0.68, to: 0.88))

        let outlineExit = easeOutCubic(segment(progress, from: 0, to: 0.16))
        let heartEntry = segment(progress, from: 0.22, to: 0.60)
        let heartScale: CGFloat
        if heartEntry < 0.72 {
            heartScale = lerp(0.15, 1.14, easeOutCubic(heartEntry / 0.72))
        } else {
            heartScale = lerp(1.14, 1, smoothstep((heartEntry - 0.72) / 0.28))
        }

        let particleProgress = easeOutCubic(segment(progress, from: 0.38, to: 0.90))
        let particleSplit = smoothstep(segment(progress, from: 0.44, to: 0.72))
        let particleOpacity = segment(progress, from: 0.34, to: 0.45)
            * (1 - segment(progress, from: 0.78, to: 0.98))

        return HeartBloomFrame(
            outerRadius: outerRadius,
            holeRadius: holeRadius,
            ringOpacity: ringOpacity,
            outlineScale: lerp(1, 0.22, outlineExit),
            outlineOpacity: 1 - segment(progress, from: 0.06, to: 0.18),
            heartScale: heartScale,
            heartOpacity: segment(progress, from: 0.22, to: 0.34),
            particleProgress: particleProgress,
            particleSplit: particleSplit,
            particleOpacity: particleOpacity
        )
    }

    private static func segment(_ value: Double, from start: Double, to end: Double) -> CGFloat {
        CGFloat(clamp((value - start) / (end - start)))
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        value * value * (3 - 2 * value)
    }

    private static func easeOutCubic(_ value: CGFloat) -> CGFloat {
        1 - pow(1 - value, 3)
    }

    private static func lerp(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + (to - from) * progress
    }
}

struct PostActionEffectHost: View {
    let playback: PostActionEffectPlayback
    let activeIcon: String
    let inactiveIcon: String
    let activeColor: Color

    var body: some View {
        switch playback.preset.effect {
        case .symbolBounce, .bookmarkDrop:
            EmptyView()
        case .heartBloom(let preset):
            HeartBloomEffect(
                preset: preset,
                startedAt: playback.startedAt,
                activeIcon: activeIcon,
                inactiveIcon: inactiveIcon,
                activeColor: activeColor
            )
        }
    }
}

private struct HeartBloomEffect: View {
    let preset: HeartBloomPreset
    let startedAt: Date
    let activeIcon: String
    let inactiveIcon: String
    let activeColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let progress = elapsed / preset.effectiveDuration
            let frame = HeartBloomTimeline.frame(at: progress)

            ZStack {
                Canvas { context, size in
                    drawRing(context: &context, size: size, frame: frame)
                    drawParticles(context: &context, size: size, frame: frame)
                }

                Image(systemName: inactiveIcon)
                    .moroScaledFont(size: 16, weight: .regular)
                    .foregroundStyle(activeColor)
                    .scaleEffect(frame.outlineScale)
                    .opacity(frame.outlineOpacity)

                Image(systemName: activeIcon)
                    .moroScaledFont(size: 16, weight: .regular)
                    .foregroundStyle(activeColor)
                    .scaleEffect(frame.heartScale)
                    .opacity(frame.heartOpacity)
            }
        }
        .frame(width: 40, height: 40)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawRing(
        context: inout GraphicsContext,
        size: CGSize,
        frame: HeartBloomFrame
    ) {
        guard frame.outerRadius > 0, frame.ringOpacity > 0 else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        var path = Path()
        path.addEllipse(in: CGRect(
            x: center.x - frame.outerRadius,
            y: center.y - frame.outerRadius,
            width: frame.outerRadius * 2,
            height: frame.outerRadius * 2
        ))
        if frame.holeRadius > 0 {
            path.addEllipse(in: CGRect(
                x: center.x - frame.holeRadius,
                y: center.y - frame.holeRadius,
                width: frame.holeRadius * 2,
                height: frame.holeRadius * 2
            ))
        }
        context.fill(
            path,
            with: .color(preset.ringColor.opacity(frame.ringOpacity)),
            style: FillStyle(eoFill: true)
        )
    }

    private func drawParticles(
        context: inout GraphicsContext,
        size: CGSize,
        frame: HeartBloomFrame
    ) {
        guard frame.particleOpacity > 0, !preset.particleColors.isEmpty else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = preset.effectiveParticleCount
        let rotation = Double(frame.particleProgress) * 4 * .pi / 180

        for index in 0..<count {
            let angle = -.pi / 2 + Double(index) * 2 * .pi / Double(count) + rotation
            let radial = CGVector(dx: cos(angle), dy: sin(angle))
            let tangent = CGVector(dx: -sin(angle), dy: cos(angle))
            let radius = 11 + 9 * frame.particleProgress
            let split = 2.6 * frame.particleSplit
            let first = CGPoint(
                x: center.x + radial.dx * radius + tangent.dx * split,
                y: center.y + radial.dy * radius + tangent.dy * split
            )
            let second = CGPoint(
                x: center.x + radial.dx * (radius + 1.5) - tangent.dx * split,
                y: center.y + radial.dy * (radius + 1.5) - tangent.dy * split
            )
            let firstColor = preset.particleColors[index % preset.particleColors.count]
            let secondColor = preset.particleColors[(index + 1) % preset.particleColors.count]

            context.fill(
                Path(ellipseIn: CGRect(x: first.x - 1.3, y: first.y - 1.3, width: 2.6, height: 2.6)),
                with: .color(firstColor.opacity(frame.particleOpacity))
            )

            var capsuleContext = context
            capsuleContext.translateBy(x: second.x, y: second.y)
            capsuleContext.rotate(by: .radians(angle))
            capsuleContext.fill(
                Path(roundedRect: CGRect(x: -2.2, y: -0.9, width: 4.4, height: 1.8), cornerRadius: 0.9),
                with: .color(secondColor.opacity(frame.particleOpacity))
            )
        }
    }
}
