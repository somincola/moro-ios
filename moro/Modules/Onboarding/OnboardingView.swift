//
//  OnboardingView.swift
//  moro
//
//  First-launch welcome flow.
//

import SwiftUI

enum OnboardingCompletion {
    case login
    case registration
}

struct OnboardingView: View {
    let onExitStart: () -> Void
    let onFinish: (OnboardingCompletion) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.moroTheme) private var theme
    @State private var selectedPage = 0
    @State private var isExiting = false

    init(
        onExitStart: @escaping () -> Void = {},
        onFinish: @escaping (OnboardingCompletion) -> Void
    ) {
        self.onExitStart = onExitStart
        self.onFinish = onFinish
    }

    private var pages: [OnboardingPage] {
        [
            OnboardingPage(
                kind: .brand,
                title: "Moro",
                body: MoroL10n.Onboarding.tagline
            ),
            OnboardingPage(
                kind: .timeline,
                title: MoroL10n.Onboarding.previewTimelineTitle,
                body: MoroL10n.Onboarding.previewTimelineBody
            ),
            OnboardingPage(
                kind: .network,
                title: MoroL10n.Onboarding.previewSyncTitle,
                body: MoroL10n.Onboarding.previewSyncBody
            ),
        ]
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingStoryPage(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            bottomControls
        }
        .background(backgroundColor.ignoresSafeArea())
        .opacity(isExiting ? 0 : 1)
        .animation(exitAnimation, value: isExiting)
        .onChange(of: selectedPage) { _, _ in
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private var bottomControls: some View {
        VStack(spacing: 22) {
            if selectedPage == pages.count - 1 {
                Button(action: { finish(with: .login) }) {
                    Text(MoroL10n.Onboarding.getStarted)
                        .moroScaledFont(size: 16, weight: .semibold, relativeTo: .body)
                        .foregroundStyle(theme.colors.primaryForeground)
                        .frame(width: 168, height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(theme.colors.primary500)
                        )
                }
                .buttonStyle(.plain)
                .transition(.opacity.animation(.easeInOut(duration: 0.9).delay(0.12)))
            }

            OnboardingPageIndicator(pageCount: pages.count, selectedPage: selectedPage)
        }
        .padding(.bottom, 54)
        .animation(.spring(response: 0.34, dampingFraction: 0.88), value: selectedPage)
    }

    private var backgroundColor: Color {
        theme.colorScheme == .dark ? Color(hex: 0x090B12) : .white
    }

    private var exitAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: AnimationTokens.duration.sm)
            : AnimationTokens.easing.easeOutLG
    }

    private func finish(with completion: OnboardingCompletion) {
        guard !isExiting else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onExitStart()
        isExiting = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: reduceMotion ? 160_000_000 : 280_000_000)
            onFinish(completion)
        }
    }
}

private struct OnboardingPage {
    let kind: OnboardingVisualKind
    let title: String
    let body: String
}

private enum OnboardingVisualKind {
    case brand
    case timeline
    case network
}

private struct OnboardingStoryPage: View {
    let page: OnboardingPage

    @Environment(\.moroTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.clear.frame(height: 54)

                OnboardingVisualStage(kind: page.kind)
                    .frame(maxWidth: .infinity)
                    .frame(height: min(proxy.size.height * 0.47, 376))
                    .accessibilityHidden(true)

                Color.clear.frame(height: 44)

                VStack(spacing: 10) {
                    Text(page.title)
                        .moroScaledFont(size: page.kind == .brand ? 38 : 28, weight: .bold, relativeTo: .title)
                        .foregroundStyle(theme.colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                        .multilineTextAlignment(.center)

                    Text(page.body)
                        .moroScaledFont(size: 16, weight: .regular, relativeTo: .body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 34)

                Spacer(minLength: 24)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct OnboardingVisualStage: View {
    let kind: OnboardingVisualKind

    @Environment(\.moroTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                OnboardingPathCanvas(kind: kind)

                switch kind {
                case .brand:
                    BrandGlyph()
                case .timeline:
                    TimelineGlyph()
                case .network:
                    NetworkGlyph()
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct OnboardingPathCanvas: View {
    let kind: OnboardingVisualKind

    @Environment(\.moroTheme) private var theme

    var body: some View {
        Canvas { context, size in
            let inset = size.width * 0.15
            var mainPath = Path()
            mainPath.move(to: CGPoint(x: inset, y: size.height * 0.64))
            mainPath.addCurve(
                to: CGPoint(x: size.width - inset, y: size.height * 0.32),
                control1: CGPoint(x: size.width * 0.28, y: size.height * 0.20),
                control2: CGPoint(x: size.width * 0.68, y: size.height * 0.80)
            )

            context.stroke(
                mainPath,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 8])
            )

            if kind == .network {
                var secondaryPath = Path()
                secondaryPath.move(to: CGPoint(x: size.width * 0.26, y: size.height * 0.30))
                secondaryPath.addQuadCurve(
                    to: CGPoint(x: size.width * 0.74, y: size.height * 0.66),
                    control: CGPoint(x: size.width * 0.52, y: size.height * 0.48)
                )
                context.stroke(
                    secondaryPath,
                    with: .color(lineColor.opacity(0.72)),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round)
                )
            }
        }
        .overlay {
            GeometryReader { proxy in
                ForEach(nodeSpecs) { node in
                    Circle()
                        .fill(accentColor.opacity(node.opacity))
                        .frame(width: node.size, height: node.size)
                        .position(
                            x: proxy.size.width * node.x,
                            y: proxy.size.height * node.y
                        )
                }
            }
        }
    }

    private var nodeSpecs: [PathNode] {
        [
            PathNode(id: "topLeft", x: 0.20, y: 0.25, size: 6, opacity: 0.26),
            PathNode(id: "topRight", x: 0.81, y: 0.22, size: 5, opacity: 0.22),
            PathNode(id: "lowerLeft", x: 0.14, y: 0.64, size: 5, opacity: 0.20),
            PathNode(id: "lowerRight", x: 0.88, y: 0.60, size: 6, opacity: 0.24),
        ]
    }

    private var lineColor: Color {
        theme.colorScheme == .dark ? Color.white.opacity(0.18) : Color(hex: 0xBFC2CF).opacity(0.55)
    }

    private var accentColor: Color {
        theme.colorScheme == .dark ? Color(hex: 0xB7AAFF) : Color(hex: 0x8D7AF2)
    }
}

private struct PathNode: Identifiable {
    let id: String
    let x: CGFloat
    let y: CGFloat
    let size: CGFloat
    let opacity: Double
}

private struct BrandGlyph: View {
    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(spacing: 22) {
            AppIconMark(size: 104)

            HStack(spacing: 9) {
                MiniPill(systemName: "leaf", text: MoroL10n.Onboarding.pillarLight)
                MiniPill(systemName: "sparkle", text: MoroL10n.Onboarding.pillarSimple)
                MiniPill(systemName: "heart", text: MoroL10n.Onboarding.pillarFriendly)
            }
        }
        .padding(.top, 12)
    }
}

private struct TimelineGlyph: View {
    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 12) {
                    Circle()
                        .fill(avatarColor(index))
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 8) {
                        Capsule(style: .continuous)
                            .fill(primaryLineColor)
                            .frame(width: index == 1 ? 156 : 128, height: 8)

                        Capsule(style: .continuous)
                            .fill(secondaryLineColor)
                            .frame(width: index == 2 ? 118 : 172, height: 7)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 13)
                .background(rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.horizontal, 42)
                .offset(x: index == 1 ? 18 : index == 2 ? -12 : 0)
            }
        }
    }

    private var rowBackground: Color {
        theme.colorScheme == .dark ? Color.white.opacity(0.055) : Color(hex: 0xF7F7FA)
    }

    private var primaryLineColor: Color {
        theme.colorScheme == .dark ? Color.white.opacity(0.68) : Color(hex: 0x2E3138).opacity(0.72)
    }

    private var secondaryLineColor: Color {
        theme.colorScheme == .dark ? Color.white.opacity(0.24) : Color(hex: 0xA2A6B2).opacity(0.46)
    }

    private func avatarColor(_ index: Int) -> Color {
        [Color(hex: 0x1E1B4B), Color(hex: 0x8D7AF2), Color(hex: 0xA7D8D0)][index]
    }
}

private struct NetworkGlyph: View {
    var body: some View {
        ZStack {
            OrbitNode(systemName: "house.fill", size: 78)

            OrbitNode(systemName: "globe", size: 46)
                .offset(x: -100, y: -52)

            OrbitNode(systemName: "person.2", size: 50)
                .offset(x: 98, y: -42)

            OrbitNode(systemName: "at", size: 42)
                .offset(x: -74, y: 88)

            OrbitNode(systemName: "paperplane", size: 44)
                .offset(x: 88, y: 92)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct AppIconMark: View {
    let size: CGFloat

    var body: some View {
        Image("AppIconPreviewDefault")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .shadow(color: .black.opacity(0.10), radius: 24, x: 0, y: 14)
    }
}

private struct MiniPill: View {
    let systemName: String
    let text: String

    @Environment(\.moroTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemName)
                .moroScaledFont(size: 11, weight: .semibold)

            Text(text)
                .moroScaledFont(size: 12, weight: .medium, relativeTo: .caption)
                .lineLimit(1)
        }
        .foregroundStyle(theme.colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(surfaceColor)
        .clipShape(Capsule(style: .continuous))
    }

    private var surfaceColor: Color {
        theme.colorScheme == .dark ? Color.white.opacity(0.07) : Color(hex: 0xF3F3F7)
    }
}

private struct OrbitNode: View {
    let systemName: String
    let size: CGFloat

    @Environment(\.moroTheme) private var theme

    var body: some View {
        Circle()
            .fill(surfaceColor)
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: systemName)
                    .moroScaledFont(size: size * 0.36, weight: .semibold)
                    .foregroundStyle(theme.colorScheme == .dark ? Color.white.opacity(0.76) : Color(hex: 0x363942))
            }
            .shadow(color: .black.opacity(theme.colorScheme == .dark ? 0.20 : 0.07), radius: 16, x: 0, y: 8)
    }

    private var surfaceColor: Color {
        theme.colorScheme == .dark ? Color.white.opacity(0.075) : .white
    }
}

private struct OnboardingPageIndicator: View {
    let pageCount: Int
    let selectedPage: Int

    @Environment(\.moroTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<pageCount, id: \.self) { page in
                Capsule(style: .continuous)
                    .fill(page == selectedPage ? activeColor : inactiveColor)
                    .frame(width: page == selectedPage ? 32 : 24, height: 4)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: selectedPage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(selectedPage + 1) / \(pageCount)"))
    }

    private var activeColor: Color {
        theme.colorScheme == .dark ? Color(hex: 0xB7AAFF) : Color(hex: 0x8175ED)
    }

    private var inactiveColor: Color {
        theme.colors.textTertiary.opacity(0.24)
    }
}

#Preview("Onboarding Light") {
    OnboardingView(onFinish: { _ in })
        .moroTheme(MoroTheme())
}

#Preview("Onboarding Dark") {
    OnboardingView(onFinish: { _ in })
        .moroTheme(MoroTheme(colorScheme: .dark))
        .environment(\.colorScheme, .dark)
}
