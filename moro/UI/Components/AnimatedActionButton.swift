//
//  AnimatedActionButton.swift
//  moro
//
//  Shared interaction and transition handling for post actions.
//

import SwiftUI

struct AnimatedActionButton: View {
    let role: PostActionRole
    let activeIcon: String
    let inactiveIcon: String
    let isActive: Bool
    let activeColor: Color
    let inactiveColor: Color
    let count: Int
    let isDisabled: Bool
    let action: () -> Void
    var accessibilityLabel: String = ""
    var iconSize: CGFloat = 21
    /// Minimum hit-target height. The toolbar passes its bar height so the tappable
    /// area fills the row without enlarging the visible icon or changing layout.
    var minHitHeight: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.postActionAnimationSchedule) private var animationSchedule

    @State private var playback: PostActionEffectPlayback?
    @State private var symbolTrigger = 0

    private var compactCountText: String? {
        guard count > 0 else { return nil }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    var body: some View {
        Button(action: handleTap) {
            HStack(spacing: 5) {
                ZStack {
                    actionIcon
                        .opacity(playback == nil ? 1 : 0)

                    if let playback {
                        PostActionEffectHost(
                            playback: playback,
                            activeIcon: activeIcon,
                            inactiveIcon: inactiveIcon,
                            activeColor: activeColor
                        )
                    }
                }
                .frame(width: 22, height: 22)

                if let compactCountText {
                    Text(compactCountText)
                        .moroScaledFont(size: 13)
                        .foregroundStyle(isActive ? activeColor : inactiveColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .allowsTightening(true)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: !isActive))
                        .animation(reduceMotion ? nil : .default, value: count)
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .frame(minHeight: minHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(PostActionPressStyle(reduceMotion: reduceMotion))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.72 : 1)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(count > 0 ? Text("\(count)") : Text(""))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .task(id: playback?.id) {
            guard let currentPlayback = playback else { return }
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(currentPlayback.preset.effect.duration * 1_000_000_000)
                )
            } catch {
                return
            }
            guard playback?.id == currentPlayback.id else { return }
            playback = nil
        }
        .onChange(of: isActive) { previousValue, newValue in
            if previousValue && !newValue {
                playback = nil
            }
        }
    }

    @ViewBuilder
    private var actionIcon: some View {
        let icon = Image(systemName: isActive ? activeIcon : inactiveIcon)
            .moroScaledFont(size: iconSize, weight: .regular)
            .foregroundStyle(isActive ? activeColor : inactiveColor)
            .contentTransition(.symbolEffect(.replace))

        switch animationSchedule.preset(for: role).effect {
        case .bookmarkDrop:
            icon.symbolEffect(.bounce.down, value: symbolTrigger)
        case .symbolBounce, .heartBloom:
            icon.symbolEffect(.bounce, value: symbolTrigger)
        }
    }

    private func handleTap() {
        guard !isDisabled else { return }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preset = animationSchedule.preset(for: role)

        if !reduceMotion {
            switch preset.effect {
            case .heartBloom where !isActive:
                playback = PostActionEffectPlayback(preset: preset)
            case .bookmarkDrop where isActive:
                break
            case .symbolBounce, .bookmarkDrop, .heartBloom:
                symbolTrigger += 1
            }
        }

        action()
    }
}

private struct PostActionPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(
                reduceMotion ? nil : AnimationTokens.easing.springSoft,
                value: configuration.isPressed
            )
    }
}

#Preview {
    HStack(spacing: 20) {
        AnimatedActionButton(
            role: .like,
            activeIcon: "heart.fill",
            inactiveIcon: "heart",
            isActive: false,
            activeColor: .red,
            inactiveColor: .gray,
            count: 10,
            isDisabled: false,
            action: {}
        )

        AnimatedActionButton(
            role: .like,
            activeIcon: "heart.fill",
            inactiveIcon: "heart",
            isActive: true,
            activeColor: .red,
            inactiveColor: .gray,
            count: 11,
            isDisabled: false,
            action: {}
        )
    }
    .padding()
}
