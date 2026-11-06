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
        ScrollPhase.releasedTouch(from: oldPhase, to: newPhase)
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

    /// A refresh not started by pulling (tab re-tap). False while one is already running.
    mutating func beginRefresh() -> Bool {
        guard !isRefreshing else { return false }
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
