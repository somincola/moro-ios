//
//  ScrollViewRefreshBridge.swift
//  moro
//
//  Lets a tab re-tap start a SwiftUI list's own pull-to-refresh, so the refresh shows exactly
//  as if the reader had pulled.
//

import SwiftUI
import UIKit

/// Holds the UIScrollView behind a SwiftUI `ScrollView`. SwiftUI has no way to start a
/// `.refreshable` from code, but it backs one with the scroll view's UIRefreshControl, which
/// UIKit can start (Explore's table view does the same).
@MainActor
final class ScrollViewRefreshBridge {
    weak var scrollView: UIScrollView?

    var isRefreshing: Bool { scrollView?.refreshControl?.isRefreshing == true }

    /// Shows the spinner, pushes the rows down and runs the list's `.refreshable` action.
    /// False when there is no control to drive (the caller then refreshes without it) or a
    /// refresh is already showing.
    func beginRefreshing() -> Bool {
        guard let scrollView, let control = scrollView.refreshControl, !control.isRefreshing else {
            return false
        }
        let topOffset = -scrollView.adjustedContentInset.top
        control.beginRefreshing()
        scrollView.setContentOffset(
            CGPoint(x: scrollView.contentOffset.x, y: topOffset - control.frame.height), animated: true)
        control.sendActions(for: .valueChanged)
        return true
    }
}

/// Place inside a `ScrollView`'s content to hand its UIScrollView to a bridge.
struct ScrollViewRefreshBridgeAnchor: UIViewRepresentable {
    let bridge: ScrollViewRefreshBridge

    func makeUIView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.bridge = bridge
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: AnchorView, context: Context) {
        view.bridge = bridge
        view.resolve()
    }

    final class AnchorView: UIView {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        weak var bridge: ScrollViewRefreshBridge?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            resolve()
        }

        func resolve() {
            var candidate = superview
            while let view = candidate, !(view is UIScrollView) { candidate = view.superview }
            if let scrollView = candidate as? UIScrollView { bridge?.scrollView = scrollView }
        }
    }
}
