import SwiftUI
import UIKit

/// Reads the owning navigation bar after layout, including compact and newer system bar sizes.
struct ProfileNavigationBarHeightReader: UIViewControllerRepresentable {
    /// Bar button tint for the current header state. The shell tints hero pages white
    /// for the banner; once the header collapses onto a light bar that would hide the
    /// back chevron (iOS 18 keeps the bar's tint even when the toolbar scheme flips).
    var tint: UIColor? = nil
    let onChange: (CGFloat) -> Void

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

        var onChange: ((CGFloat) -> Void)?
        var tint: UIColor?
        private var reportedHeight: CGFloat?

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
            let height = navigationController.navigationBar.bounds.height
            guard height > 0, reportedHeight != height else { return }
            reportedHeight = height

            // Deliver outside UIKit's layout pass; discard superseded or detached measurements.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.viewIfLoaded?.window != nil, self.reportedHeight == height else { return }
                self.onChange?(height)
            }
        }
    }
}
