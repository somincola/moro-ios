//
//  MoroPullRefresh.swift
//  moro
//
//  Shared pieces of Moro's own pull-to-refresh (Home and the immersive profile):
//  release detection, result feedback and the petal indicator. Explore and Inbox use the
//  system control; they share only the feedback rules.
//

import SwiftUI
import UIKit

extension ScrollPhase {
    /// The finger left the screen: a pull armed before this moment starts a refresh.
    static func releasedTouch(from oldPhase: ScrollPhase, to newPhase: ScrollPhase) -> Bool {
        let wasTouching = oldPhase == .tracking || oldPhase == .interacting
        let isTouching = newPhase == .tracking || newPhase == .interacting
        return wasTouching && !isTouching
    }
}

/// How every refresh reports its result, whatever started it (pull, tab re-tap).
@MainActor
enum MoroRefreshFeedback {
    enum Outcome: Equatable {
        case succeeded
        case failed
        case cancelled
    }

    /// Haptic when a pull crosses its threshold.
    static func armed(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// Success: a light confirmation. Failure: error haptic plus a toast, because a pull
    /// that silently fails reads exactly like "nothing new". Cancelled: nothing.
    static func deliver(
        _ outcome: Outcome,
        failureMessage: String = MoroL10n.Timeline.loadFailed,
        confirmsSuccess: Bool = true
    ) {
        switch outcome {
        case .succeeded:
            if confirmsSuccess { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            AppFeedbackCenter.shared.showError(failureMessage)
        case .cancelled:
            break
        }
    }
}

/// Moro's twelve-petal refresh indicator. Petals fill in while pulling and spin while
/// refreshing; the spin continues from where the pull left it instead of jumping.
struct MoroPetalSpinner: View {
    struct Style {
        var petalSize: CGSize
        var radius: CGFloat
        var diameter: CGFloat
        /// Seconds per turn while refreshing.
        var period: Double
        /// Turn up to half a revolution while pulling (the profile hero does this).
        var rotatesWithProgress: Bool

        static let timeline = Style(
            petalSize: CGSize(width: 2.4, height: 6.5), radius: 8.5, diameter: 28,
            period: 0.9, rotatesWithProgress: false)
        static let profile = Style(
            petalSize: CGSize(width: 3, height: 8), radius: 10, diameter: 34,
            period: 0.8, rotatesWithProgress: true)
    }

    enum Tint {
        /// Filled petals in `active`, the rest in `inactive` (timeline on the page canvas).
        case twoTone(active: Color, inactive: Color)
        /// One colour whose opacity carries progress (profile, over the hero image).
        case fading(Color)
    }

    let progress: CGFloat
    let isAnimating: Bool
    var style: Style = .timeline
    var tint: Tint

    @State private var spinStart: Date?
    private let petalCount = 12

    private var clampedProgress: CGFloat { min(max(progress, 0), 1) }
    private var restingAngle: Double {
        style.rotatesWithProgress ? Double(clampedProgress) * 180 : 0
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isAnimating)) { context in
            ZStack {
                ForEach(0..<petalCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color(for: index))
                        .frame(width: style.petalSize.width, height: style.petalSize.height)
                        .offset(y: -style.radius)
                        .rotationEffect(.degrees(Double(index) * 360 / Double(petalCount)))
                }
            }
            .frame(width: style.diameter, height: style.diameter)
            .rotationEffect(.degrees(angle(at: context.date)))
        }
        .onAppear { spinStart = isAnimating ? Date() : nil }
        .onChange(of: isAnimating) { _, animating in
            spinStart = animating ? Date() : nil
        }
        // Accessibility is the caller's: Home hides it, Profile labels it "Refreshing".
    }

    private func angle(at date: Date) -> Double {
        guard isAnimating, let spinStart else { return restingAngle }
        let turns = date.timeIntervalSince(spinStart) / style.period
        return restingAngle + turns.truncatingRemainder(dividingBy: 1) * 360
    }

    private func color(for index: Int) -> Color {
        let rank = Double(index + 1) / Double(petalCount)
        switch tint {
        case .twoTone(let active, let inactive):
            if isAnimating { return active.opacity(0.28 + rank * 0.72) }
            let visiblePetals = Int(ceil(clampedProgress * CGFloat(petalCount)))
            return index < visiblePetals ? active : inactive.opacity(0.45)
        case .fading(let base):
            if isAnimating { return base.opacity(0.2 + 0.8 * rank) }
            let filled = min(max(Double(clampedProgress) * Double(petalCount) - Double(index), 0), 1)
            return base.opacity(0.18 + 0.82 * filled)
        }
    }
}
