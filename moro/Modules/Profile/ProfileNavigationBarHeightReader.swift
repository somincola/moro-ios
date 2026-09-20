import SwiftUI
import UIKit

/// Reads the owning navigation bar after layout, including compact and newer system bar sizes.
struct ProfileNavigationBarHeightReader: UIViewControllerRepresentable {
    let onChange: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> ReaderViewController {
        let controller = ReaderViewController()
        controller.onChange = onChange
        return controller
    }

    func updateUIViewController(_ controller: ReaderViewController, context: Context) {
        controller.onChange = onChange
        controller.reportHeight()
    }

    final class ReaderViewController: UIViewController {
        var onChange: ((CGFloat) -> Void)?
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
