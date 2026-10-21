//
//  MediaPreviewPresenter.swift
//  moro
//
//  Opens the fullscreen image viewer from UIKit, above whatever is on screen.
//

import SwiftUI
import UIKit

/// The viewer used to be a `fullScreenCover` on the post's media grid. Posts live in lazy
/// lists (timelines, profiles, search cells), and rotating relayouts them: when the post that
/// opened the viewer left the loaded rows, SwiftUI removed its grid and closed the viewer
/// with it — so rotating closed the viewer for posts near the top or bottom of the screen.
///
/// Presented from the top view controller, the viewer no longer depends on that post staying
/// loaded. It zooms from and back to the thumbnail with the same system transition, using
/// the thumbnail's `MediaPreviewSource` anchor while it is on screen.
@MainActor
enum MediaPreviewPresenter {
    /// Returns false when there is nothing to present from; the caller then falls back to
    /// presenting the viewer itself.
    @discardableResult
    static func present(
        attachments: [Status.Attachment],
        initialIndex: Int,
        sourceID: String,
        theme: MoroTheme,
        dynamicTypeSize: DynamicTypeSize
    ) -> Bool {
        guard let presenter = topViewController(), !(presenter is MediaPreviewHostingController)
        else { return false }

        let controller = MediaPreviewHostingController(rootView: AnyView(EmptyView()))
        controller.rootView = AnyView(
            ImagePreviewView(attachments: attachments, initialIndex: initialIndex) { [weak controller] in
                controller?.close()
            }
            // A UIKit-presented host does not inherit the post's SwiftUI environment.
            .moroTheme(theme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
        )
        controller.modalPresentationStyle = .fullScreen
        controller.modalPresentationCapturesStatusBarAppearance = true
        controller.preferredTransition = .zoom { _ in
            MediaPreviewSourceRegistry.shared.view(for: sourceID)
        }
        presenter.present(controller, animated: true)
        return true
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

/// Hosts one viewer presentation.
final class MediaPreviewHostingController: UIHostingController<AnyView> {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    override init(rootView: AnyView) {
        super.init(rootView: rootView)
        view.backgroundColor = .black
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    func close() {
        guard presentingViewController != nil, !isBeingDismissed else { return }
        dismiss(animated: true)
    }
}

/// Weak lookup from attachment ID to the on-screen thumbnail the viewer zooms from.
@MainActor
final class MediaPreviewSourceRegistry {
    static let shared = MediaPreviewSourceRegistry()
    private let views = NSMapTable<NSString, UIView>.strongToWeakObjects()

    func register(_ view: UIView, for id: String) {
        views.setObject(view, forKey: id as NSString)
    }

    /// The thumbnail only while it is in a window; otherwise the system uses its default
    /// (non-zoom) animation, e.g. after rotating moved the post off screen.
    func view(for id: String) -> UIView? {
        guard let view = views.object(forKey: id as NSString), view.window != nil else { return nil }
        return view
    }
}

/// An invisible view filling a thumbnail, registered as the viewer's zoom source.
struct MediaPreviewSource: UIViewRepresentable {
    let id: String
    var cornerRadius: CGFloat = 0

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.backgroundColor = .clear
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        MediaPreviewSourceRegistry.shared.register(view, for: id)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.layer.cornerRadius = cornerRadius
        MediaPreviewSourceRegistry.shared.register(view, for: id)
    }
}
