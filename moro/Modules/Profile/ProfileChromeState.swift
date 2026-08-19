//
//  ProfileChromeState.swift
//  moro
//
//  Stable measurement and interaction state for the immersive profile chrome.
//

import SwiftUI

struct ProfileHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ProfileTabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

enum ProfileTabPlacement: Equatable {
    case natural
    case bottomDocked
    case topPinned
}

enum ProfileHeaderChromeLogic {
    static let transitionDistance: CGFloat = 32

    static func collapseOffset(
        bannerHeight: CGFloat,
        navigationBarHeight: CGFloat
    ) -> CGFloat {
        max(0, bannerHeight - navigationBarHeight)
    }

    static func progress(
        scrollOffset: CGFloat,
        bannerHeight: CGFloat,
        navigationBarHeight: CGFloat
    ) -> CGFloat {
        let end = collapseOffset(
            bannerHeight: bannerHeight,
            navigationBarHeight: navigationBarHeight
        )
        let start = max(0, end - transitionDistance)
        guard end > start else { return scrollOffset >= end ? 1 : 0 }
        return min(max((scrollOffset - start) / (end - start), 0), 1)
    }
}

enum ProfileStickyTabLogic {
    static let pinTolerance: CGFloat = 0.5

    static func pinThreshold(
        headerHeight: CGFloat,
        topChromeHeight: CGFloat
    ) -> CGFloat {
        max(0, headerHeight - topChromeHeight)
    }

    static func placement(
        headerHeight: CGFloat,
        topChromeHeight: CGFloat,
        scrollOffset: CGFloat,
        viewportHeight: CGFloat,
        tabBarHeight: CGFloat
    ) -> ProfileTabPlacement {
        guard headerHeight > 1, tabBarHeight > 1 else { return .natural }

        let naturalTop = headerHeight - scrollOffset
        if naturalTop <= topChromeHeight + pinTolerance {
            return .topPinned
        }

        let bottomDockTop = max(topChromeHeight, viewportHeight - tabBarHeight)
        if naturalTop >= bottomDockTop - pinTolerance {
            return .bottomDocked
        }

        return .natural
    }

    static func overlayOffset(
        for placement: ProfileTabPlacement,
        topChromeHeight: CGFloat,
        viewportHeight: CGFloat,
        tabBarHeight: CGFloat
    ) -> CGFloat? {
        switch placement {
        case .natural:
            return nil
        case .bottomDocked:
            return max(topChromeHeight, viewportHeight - tabBarHeight)
        case .topPinned:
            return topChromeHeight
        }
    }
}

struct ProfileChromeLayout: Equatable {
    let pinnedContentHeight: CGFloat
    let tabPlacement: ProfileTabPlacement
    let tabOverlayOffset: CGFloat?

    var hidesNaturalTab: Bool {
        tabPlacement != .natural
    }
}

struct ProfileChromeState: Equatable {
    var scrollOffset: CGFloat = 0
    var pullDistance: CGFloat = 0
    var isRefreshing = false
    var isPullRefreshArmed = false
    var headerHeight: CGFloat = 0
    var tabBarHeight: CGFloat = 0

    mutating func updateHeaderHeight(_ height: CGFloat) {
        guard height > 1, abs(headerHeight - height) > 0.5 else { return }
        headerHeight = height
    }

    mutating func updateTabBarHeight(_ height: CGFloat) {
        guard height > 1, abs(tabBarHeight - height) > 0.5 else { return }
        tabBarHeight = height
    }

    @discardableResult
    mutating func updateScroll(
        _ scrolled: CGFloat,
        pullRefreshThreshold: CGFloat
    ) -> Bool {
        if abs(scrollOffset - scrolled) > 0.5 {
            scrollOffset = scrolled
        }

        let nextPull = max(0, -scrolled)
        if abs(pullDistance - nextPull) > 0.5 {
            pullDistance = nextPull
        }

        let wasArmed = isPullRefreshArmed
        isPullRefreshArmed = !isRefreshing && nextPull >= pullRefreshThreshold
        return !wasArmed && isPullRefreshArmed
    }

    func didReleasePull(oldPhase: ScrollPhase, newPhase: ScrollPhase) -> Bool {
        let wasTouching = oldPhase == .tracking || oldPhase == .interacting
        let isTouching = newPhase == .tracking || newPhase == .interacting
        return wasTouching && !isTouching
    }

    mutating func beginRefreshIfArmed() -> Bool {
        guard isPullRefreshArmed, !isRefreshing else {
            isPullRefreshArmed = false
            return false
        }

        isPullRefreshArmed = false
        isRefreshing = true
        return true
    }

    mutating func finishRefresh() {
        isRefreshing = false
        pullDistance = 0
    }

    func headerProgress(
        bannerHeight: CGFloat,
        navigationBarHeight: CGFloat
    ) -> CGFloat {
        ProfileHeaderChromeLogic.progress(
            scrollOffset: scrollOffset,
            bannerHeight: bannerHeight,
            navigationBarHeight: navigationBarHeight
        )
    }

    func pullProgress(threshold: CGFloat) -> CGFloat {
        min(max(pullDistance / threshold, 0), 1)
    }

    func layout(
        viewportHeight: CGFloat,
        topChromeHeight: CGFloat
    ) -> ProfileChromeLayout {
        let placement = ProfileStickyTabLogic.placement(
            headerHeight: headerHeight,
            topChromeHeight: topChromeHeight,
            scrollOffset: scrollOffset,
            viewportHeight: viewportHeight,
            tabBarHeight: tabBarHeight
        )

        return ProfileChromeLayout(
            pinnedContentHeight: max(
                1,
                viewportHeight - topChromeHeight - tabBarHeight
            ),
            tabPlacement: placement,
            tabOverlayOffset: ProfileStickyTabLogic.overlayOffset(
                for: placement,
                topChromeHeight: topChromeHeight,
                viewportHeight: viewportHeight,
                tabBarHeight: tabBarHeight
            )
        )
    }
}

struct ProfilePullRefreshSpinner: View {
    let progress: CGFloat
    let isRefreshing: Bool
    let color: Color

    @State private var rotation: Double = 0

    private let petalCount = 12

    var body: some View {
        ZStack {
            ForEach(0..<petalCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color.opacity(petalOpacity(at: index)))
                    .frame(width: 3, height: 8)
                    .offset(y: -10)
                    .rotationEffect(.degrees(Double(index) * 360 / Double(petalCount)))
            }
        }
        .frame(width: 34, height: 34)
        .rotationEffect(.degrees(isRefreshing ? rotation : Double(progress) * 180))
        .onAppear { updateRotation() }
        .onChange(of: isRefreshing) { _, _ in
            updateRotation()
        }
    }

    private func petalOpacity(at index: Int) -> Double {
        if isRefreshing {
            return 0.2 + 0.8 * Double(index + 1) / Double(petalCount)
        }

        let visibleAmount = min(max(progress * Double(petalCount) - Double(index), 0), 1)
        return 0.18 + 0.82 * visibleAmount
    }

    private func updateRotation() {
        if isRefreshing {
            rotation = 0
            withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        } else {
            rotation = 0
        }
    }
}
