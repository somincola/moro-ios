import SwiftUI
import UIKit

/// Reads the owning navigation bar after layout, including compact and newer system bar sizes.
struct ProfileNavigationBarHeightReader: UIViewControllerRepresentable {
    struct Metrics: Equatable {
        /// The bar's own height.
        var height: CGFloat
        /// The bar's bottom edge in window coordinates. The bar does not always start at the
        /// safe-area top (on Dynamic Island iPhones it starts a few points above it), so
        /// safe area + height can overshoot the real bar.
        var bottom: CGFloat
        /// The bar lives in iPhone Duo's vertical side bar: there is no bar across the top, so
        /// `height`/`bottom` describe the band the page draws itself instead.
        var isVertical = false
    }

    /// The top band a page draws when its bar went into the vertical side bar.
    static let verticalBarTopBandHeight: CGFloat = 44

    /// Bar button tint for the current header state. The shell tints hero pages white
    /// for the banner; once the header collapses onto a light bar that would hide the
    /// back chevron (iOS 18 keeps the bar's tint even when the toolbar scheme flips).
    var tint: UIColor? = nil
    let onChange: (Metrics) -> Void

    func makeUIViewController(context: Context) -> ReaderViewController {
        let controller = ReaderViewController()
        controller.onChange = onChange
        controller.tint = tint
        return controller
    }

    func updateUIViewController(_ controller: ReaderViewController, context: Context) {
        controller.onChange = onChange
        controller.tint = tint
        controller.reportHeight()
        controller.applyTint()
    }

    final class ReaderViewController: UIViewController {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        var onChange: ((Metrics) -> Void)?
        var tint: UIColor?
        private var reportedMetrics: Metrics?

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            view.isUserInteractionEnabled = false
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            reportHeight()
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            reportHeight()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            reportHeight()
            applyTint()
            // The shell reapplies the scene's bar appearance when navigation settles
            // (e.g. popping back to a collapsed profile); win that race.
            DispatchQueue.main.async { [weak self] in self?.applyTint() }
        }

        func applyTint() {
            guard let tint, viewIfLoaded?.window != nil,
                let bar = navigationController?.navigationBar, bar.tintColor != tint else { return }
            bar.tintColor = tint
        }

        func reportHeight() {
            guard viewIfLoaded?.window != nil, let navigationController,
                !navigationController.isNavigationBarHidden else { return }
            let bar = navigationController.navigationBar
            let height = bar.bounds.height
            guard height > 0 else { return }
            let metrics: Metrics
            if Self.isVerticalBar(bar) {
                let band = ProfileNavigationBarHeightReader.verticalBarTopBandHeight
                let top = view.window?.safeAreaInsets.top ?? 0
                metrics = Metrics(height: band, bottom: top + band, isVertical: true)
            } else {
                metrics = Metrics(height: height, bottom: bar.convert(bar.bounds, to: nil).maxY)
            }
            guard reportedMetrics != metrics else { return }
            reportedMetrics = metrics

            // Deliver outside UIKit's layout pass; discard superseded or detached measurements.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.viewIfLoaded?.window != nil, self.reportedMetrics == metrics else { return }
                self.onChange?(metrics)
            }
        }

        private static func isVerticalBar(_ bar: UINavigationBar) -> Bool {
            if #available(iOS 27.1, *), bar.traitCollection.verticalBarEdge != .unspecified {
                return true
            }
            return bar.bounds.height > bar.bounds.width
        }
    }
}
