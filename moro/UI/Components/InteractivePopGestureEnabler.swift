//
//  InteractivePopGestureEnabler.swift
//  moro
//
//  Keeps the system edge-swipe back gesture available on screens that draw
//  their own navigation chrome and hide SwiftUI's navigation bar.
//

import SwiftUI
import UIKit

private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableInteractivePopIfNeeded()
    }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enableInteractivePopIfNeeded()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableInteractivePopIfNeeded()
        }

        func enableInteractivePopIfNeeded() {
            guard let navigationController else { return }
            let shouldEnable = navigationController.viewControllers.count > 1
            navigationController.interactivePopGestureRecognizer?.isEnabled = shouldEnable
            if shouldEnable {
                navigationController.interactivePopGestureRecognizer?.delegate = nil
            }
        }
    }
}

extension View {
    func moroInteractivePopGestureEnabled() -> some View {
        background(
            InteractivePopGestureEnabler()
                .frame(width: 0, height: 0)
        )
    }
}
