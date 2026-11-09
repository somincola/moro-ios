import SwiftUI
import UIKit

/// UIHostingConfiguration has no SwiftUI ScrollView to deliver visibility callbacks.
/// Its UIKit owner refreshes these weak probes from the existing scroll delegate.
@MainActor
final class UIKitScrollVisibility {
    // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
    nonisolated deinit {}

    private struct WeakProbe { weak var view: UIKitScrollVisibilityProbeView? }
    private var probes: [ObjectIdentifier: WeakProbe] = [:]

    func register(_ view: UIKitScrollVisibilityProbeView) {
        probes[ObjectIdentifier(view)] = WeakProbe(view: view)
        view.refreshVisibility()
    }

    func unregister(_ view: UIKitScrollVisibilityProbeView) {
        probes[ObjectIdentifier(view)] = nil
    }

    func refresh() {
        probes = probes.filter { $0.value.view != nil }
        for probe in probes.values { probe.view?.refreshVisibility() }
    }
}

private struct UIKitScrollVisibilityKey: EnvironmentKey {
    static let defaultValue: UIKitScrollVisibility? = nil
}

extension EnvironmentValues {
    var moroUIKitScrollVisibility: UIKitScrollVisibility? {
        get { self[UIKitScrollVisibilityKey.self] }
        set { self[UIKitScrollVisibilityKey.self] = newValue }
    }
}

struct UIKitScrollVisibilityProbe: UIViewRepresentable {
    let visibility: UIKitScrollVisibility
    let onChange: (Bool) -> Void

    func makeUIView(context: Context) -> UIKitScrollVisibilityProbeView {
        UIKitScrollVisibilityProbeView(visibility: visibility)
    }

    func updateUIView(_ view: UIKitScrollVisibilityProbeView, context: Context) {
        view.onChange = onChange
        view.refreshVisibility()
    }

    static func dismantleUIView(_ view: UIKitScrollVisibilityProbeView, coordinator: ()) {
        view.detach()
    }
}

final class UIKitScrollVisibilityProbeView: UIView {
    private let visibility: UIKitScrollVisibility
    var onChange: ((Bool) -> Void)?
    private var lastVisible: Bool?
    private var notificationTask: Task<Void, Never>?

    init(visibility: UIKitScrollVisibility) {
        self.visibility = visibility
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { visibility.unregister(self); report(false) }
        else { visibility.register(self) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refreshVisibility()
    }

    func refreshVisibility() {
        guard let window, bounds.width > 0, bounds.height > 0 else { report(false); return }
        let frame = convert(bounds, to: window)
        var visible = frame.intersection(window.bounds)
        var ancestor: UIView? = self
        while let view = ancestor {
            guard !view.isHidden, view.alpha > 0.01 else { report(false); return }
            if view.clipsToBounds || view is UIScrollView {
                visible = visible.intersection(view.convert(view.bounds, to: window))
            }
            ancestor = view.superview
        }
        let fraction = visible.isNull ? 0 : visible.width * visible.height / (frame.width * frame.height)
        report(Double(fraction) >= MediaPlaybackPolicy.visibleFraction)
    }

    private func report(_ visible: Bool) {
        guard visible != lastVisible else { return }
        lastVisible = visible
        notificationTask?.cancel()
        // Layout can run inside a SwiftUI update. Publish only threshold crossings,
        // on the next actor turn, rather than publishing every scroll offset.
        notificationTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            self?.onChange?(visible)
        }
    }

    func detach() {
        visibility.unregister(self)
        notificationTask?.cancel()
        onChange = nil
    }

    nonisolated deinit { notificationTask?.cancel() }
}
