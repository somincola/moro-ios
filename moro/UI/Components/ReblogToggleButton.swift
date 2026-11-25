//
//  ReblogToggleButton.swift
//  moro
//
//  Toggle button to show or hide a followed user's boosts on the home timeline.
//

import SwiftUI

struct ReblogToggleButton: View {
    let isShowingReblogs: Bool
    let isLoading: Bool
    let isInteractionDisabled: Bool
    var onToggle: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var slashBoxSize: CGFloat = 20
    @State private var slashProgress: CGFloat
    @State private var enableSpinCount = 0

    init(
        isShowingReblogs: Bool,
        isLoading: Bool,
        isInteractionDisabled: Bool,
        onToggle: @escaping () -> Void
    ) {
        self.isShowingReblogs = isShowingReblogs
        self.isLoading = isLoading
        self.isInteractionDisabled = isInteractionDisabled
        self.onToggle = onToggle
        _slashProgress = State(initialValue: isShowingReblogs ? 0 : 1)
    }

    private var iconTint: Color {
        isShowingReblogs ? theme.colors.textPrimary : theme.colors.textSecondary
    }

    private var slashStrokeWidth: CGFloat {
        max(1.6, slashBoxSize * 0.085)
    }

    private var cutoutStrokeWidth: CGFloat {
        slashStrokeWidth + max(2.2, slashBoxSize * 0.12)
    }

    var body: some View {
        Button(action: onToggle) {
            ZStack {
                reblogGlyph
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(iconTint)
                }
            }
            .frame(width: 36, height: 36)
            .moroRelationshipControlSurface(.secondary, theme: theme)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isShowingReblogs)
        .onChange(of: isShowingReblogs) { _, showing in
            if reduceMotion {
                slashProgress = showing ? 0 : 1
            } else if showing {
                enableSpinCount += 1
                withAnimation(.snappy(duration: 0.22)) {
                    slashProgress = 0
                }
            } else {
                withAnimation(.snappy(duration: 0.28, extraBounce: 0.08)) {
                    slashProgress = 1
                }
            }
        }
        .disabled(isLoading || isInteractionDisabled)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isShowingReblogs)
        .accessibilityLabel(
            isShowingReblogs
                ? MoroL10n.Profile.reblogToggleHide
                : MoroL10n.Profile.reblogToggleShow
        )
        .accessibilityIdentifier("profile.reblogToggle")
    }

    private var reblogGlyph: some View {
        let slashOpacity = min(Double(slashProgress) * 8, 1)

        return ZStack {
            ZStack {
                Image(systemName: "arrow.2.squarepath")
                    .moroScaledFont(size: 16, weight: .medium)
                    .foregroundStyle(iconTint)
                    .symbolEffect(.rotate, options: .nonRepeating, value: enableSpinCount)

                DiagonalSlashShape()
                    .trim(from: 0, to: slashProgress)
                    .stroke(
                        .black,
                        style: StrokeStyle(lineWidth: cutoutStrokeWidth, lineCap: .round)
                    )
                    .opacity(slashOpacity)
                    .blendMode(.destinationOut)
                    .frame(width: slashBoxSize, height: slashBoxSize)
            }
            .compositingGroup()

            DiagonalSlashShape()
                .trim(from: 0, to: slashProgress)
                .stroke(
                    iconTint,
                    style: StrokeStyle(lineWidth: slashStrokeWidth, lineCap: .round)
                )
                .opacity(slashOpacity)
                .frame(width: slashBoxSize, height: slashBoxSize)
        }
    }
}

private struct DiagonalSlashShape: Shape {
    func path(in rect: CGRect) -> Path {
        let insetX = rect.width * 0.14
        let insetY = rect.height * 0.14
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + insetX, y: rect.minY + insetY))
        path.addLine(to: CGPoint(x: rect.maxX - insetX, y: rect.maxY - insetY))
        return path
    }
}
