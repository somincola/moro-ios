//
//  AccountSwitcherController.swift
//  moro
//
//  Touch and hold the Me tab to raise the account switcher. Slide along the bar
//  to pick an account and release to switch, or release in place to keep the
//  panel open for a tap. The switch transition lives on the window because the
//  tab shell is rebuilt for the new account.
//

import SwiftUI
import UIKit

struct AccountSwitcherConfiguration {
    var sessions: [StoredAccountSession] = []
    var activeSessionID: String?
    var onSwitch: (String) -> Void = { _ in }
    var onAddAccount: () -> Void = {}
    /// Lets the shell step floating controls (the compose button) out of the panel's way.
    var onPresentationChange: (Bool) -> Void = { _ in }
}

@MainActor
final class AccountSwitcherController: NSObject, UIGestureRecognizerDelegate {
    // Owned by the tab shell and rebuilt with it on every account switch.
    nonisolated deinit {}

    static let meTabIdentifier = "mainTab.me"

    private weak var container: UIViewController?
    private weak var tabBarController: UITabBarController?
    private let model = AccountSwitcherModel()
    private var host: UIHostingController<AnyView>?
    private var configuration = AccountSwitcherConfiguration()
    private var theme: MoroTheme
    private let pressRecognizer = UILongPressGestureRecognizer()
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let presentFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var pressOrigin: CGPoint = .zero
    private var didTravel = false

    init(container: UIViewController, tabBarController: UITabBarController, theme: MoroTheme) {
        self.container = container
        self.tabBarController = tabBarController
        self.theme = theme
        super.init()
        model.onSelect = { [weak self] entry in self?.select(entry) }
        model.onDismiss = { [weak self] in self?.dismiss() }
    }

    func install() {
        guard let tabBar = tabBarController?.tabBar else { return }
        pressRecognizer.addTarget(self, action: #selector(handlePress(_:)))
        pressRecognizer.minimumPressDuration = 0.35
        pressRecognizer.allowableMovement = .greatestFiniteMagnitude
        // Once recognized, the hold must not also select the tab.
        pressRecognizer.cancelsTouchesInView = true
        pressRecognizer.delegate = self
        tabBar.addGestureRecognizer(pressRecognizer)
        // Build the overlay once the shell has settled, so the first hold doesn't pay
        // for the hosting controller, its first SwiftUI pass and the avatar decodes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.prewarm() }
    }

    private func prewarm() {
        guard !model.isPresented, !AccountSwitchTransition.shared.isActive,
            let hostView = makeHostIfNeeded()?.view
        else { return }
        model.entries = makeEntries()
        for url in model.entries.compactMap(\.avatarURL) {
            Task { _ = await ImageCache.shared.load(from: url) }
        }
        layoutPanel()
        // One invisible pass (scrim and panel are at zero opacity while not presented).
        hostView.isHidden = false
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.model.isPresented else { return }
            self.host?.view.isHidden = true
        }
    }

    func update(configuration: AccountSwitcherConfiguration, theme: MoroTheme) {
        self.configuration = configuration
        if Self.themeChanged(self.theme, theme) {
            self.theme = theme
            host?.rootView = rootView()
            applyInterfaceStyle()
        }
        if model.isPresented {
            model.entries = makeEntries()
        }
    }

    /// VoiceOver and Switch Control reach every account from the Me tab without the hold.
    func refreshAccessibilityActions() {
        guard let meTab = meTabView() else { return }
        let others = configuration.sessions.filter { $0.id != configuration.activeSessionID }
        var actions = others.map { session in
            UIAccessibilityCustomAction(name: MoroL10n.AccountSwitcher.switchTo("@\(session.account.acct)")) {
                [weak self] _ in
                self?.configuration.onSwitch(session.id)
                return true
            }
        }
        actions.append(UIAccessibilityCustomAction(name: MoroL10n.AccountMgmt.addAccount) { [weak self] _ in
            self?.configuration.onAddAccount()
            return true
        })
        meTab.accessibilityCustomActions = actions
    }

    // MARK: - Gesture

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Wake the Taptic Engine on touch down so the "raise" tap lands on time.
        if gestureRecognizer === pressRecognizer {
            presentFeedback.prepare()
        }
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pressRecognizer, !model.isPresented,
            !AccountSwitchTransition.shared.isActive,
            let tabBar = tabBarController?.tabBar, let meFrame = meTabFrame(in: tabBar)
        else { return false }
        return meFrame.insetBy(dx: -6, dy: -6).contains(gestureRecognizer.location(in: tabBar))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // The iOS 26 tab bar tracks touches with its own recognizer (the selection lens),
        // which would otherwise exclude the hold. Run alongside it, then cancel it on begin.
        guard gestureRecognizer === pressRecognizer,
            let tabBar = tabBarController?.tabBar, let view = otherGestureRecognizer.view
        else { return false }
        return view === tabBar || view.isDescendant(of: tabBar)
    }

    /// Stops the tab bar's own tracking so releasing the hold doesn't also select a tab.
    private func cancelTabBarTracking() {
        guard let tabBar = tabBarController?.tabBar else { return }
        var queue: [UIView] = [tabBar]
        while let view = queue.popLast() {
            for recognizer in view.gestureRecognizers ?? []
            where recognizer !== pressRecognizer && recognizer.isEnabled {
                recognizer.isEnabled = false
                recognizer.isEnabled = true
            }
            queue.append(contentsOf: view.subviews)
        }
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        guard let hostView = makeHostIfNeeded()?.view else { return }
        let location = recognizer.location(in: hostView)
        switch recognizer.state {
        case .began:
            pressOrigin = location
            didTravel = false
            cancelTabBarTracking()
            present()
            // Item frames arrive after the first layout pass.
            DispatchQueue.main.async { [weak self] in self?.updateHover(at: location, haptic: false) }
        case .changed:
            if hypot(location.x - pressOrigin.x, location.y - pressOrigin.y) > 10 { didTravel = true }
            updateHover(at: location, haptic: true)
        case .ended:
            let target = entry(at: location)
            if !didTravel {
                enterSticky()
            } else if let target {
                select(target)
            } else {
                dismiss()
            }
        case .cancelled, .failed:
            dismiss()
        default:
            break
        }
    }

    private func updateHover(at location: CGPoint, haptic: Bool) {
        let id = entry(at: location)?.id
        guard id != model.hoveredID else { return }
        model.hoveredID = id
        if haptic, id != nil {
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
        }
    }

    /// Hit test by column: anywhere between the panel and the screen edge picks the
    /// item above or below the finger, so sliding along the tab bar is enough.
    private func entry(at point: CGPoint) -> AccountSwitcherEntry? {
        guard let bounds = host?.view.bounds else { return nil }
        let frames = model.entries.compactMap { entry in model.itemFrames[entry.id].map { (entry, $0) } }
        guard let union = frames.map(\.1).reduce(nil, { $0?.union($1) ?? $1 }) else { return nil }
        let reach: CGFloat = 70
        let inBand = model.placement == .aboveTabBar
            ? point.y >= union.minY - reach && point.y <= bounds.maxY
            : point.y >= bounds.minY && point.y <= union.maxY + reach
        let slack = AccountSwitcherMetrics.spacing / 2 + AccountSwitcherMetrics.padding
        guard inBand, point.x >= union.minX - slack else { return nil }
        return frames.min { abs($0.1.midX - point.x) < abs($1.1.midX - point.x) }?.0
    }

    // MARK: - Presentation

    private func makeEntries() -> [AccountSwitcherEntry] {
        AccountSwitcherEntry.entries(
            sessions: configuration.sessions,
            activeSessionID: configuration.activeSessionID,
            addTitle: MoroL10n.AccountMgmt.addAccount
        )
    }

    private func present() {
        guard let hostView = host?.view else { return }
        model.entries = makeEntries()
        model.hoveredID = nil
        model.flyingID = nil
        model.isSticky = false
        for url in model.entries.compactMap(\.avatarURL) {
            Task { _ = await ImageCache.shared.load(from: url) }
        }
        layoutPanel()
        hostView.isUserInteractionEnabled = false
        hostView.isHidden = false
        container?.view.bringSubviewToFront(hostView)
        model.isPresented = true
        configuration.onPresentationChange(true)
        presentFeedback.impactOccurred(intensity: 0.75)
        selectionFeedback.prepare()
    }

    private func enterSticky() {
        model.hoveredID = nil
        model.isSticky = true
        host?.view.isUserInteractionEnabled = true
    }

    private func dismiss() {
        model.isPresented = false
        configuration.onPresentationChange(false)
        model.isSticky = false
        model.hoveredID = nil
        host?.view.isUserInteractionEnabled = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, !self.model.isPresented else { return }
            self.host?.view.isHidden = true
        }
    }

    private func select(_ entry: AccountSwitcherEntry) {
        switch entry.kind {
        case .addAccount:
            dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.configuration.onAddAccount()
            }
        case .account(let sessionID):
            if entry.isCurrent {
                dismiss()
            } else {
                beginSwitch(to: sessionID, entry: entry)
            }
        }
    }

    private func beginSwitch(to sessionID: String, entry: AccountSwitcherEntry) {
        guard let hostView = host?.view, let window = hostView.window else {
            dismiss()
            configuration.onSwitch(sessionID)
            return
        }
        // The avatar as drawn right now, including the hover lift.
        var avatar: UIView?
        var avatarFrame = CGRect.zero
        if let frame = model.itemFrames[entry.id] {
            let hovered = model.hoveredID.flatMap { id in model.entries.first { $0.id == id } }
            let size = AccountSwitcherMetrics.visualSize(of: entry, hovered: hovered)
            let offsetY = (model.placement == .aboveTabBar ? -1 : 1)
                * AccountSwitcherMetrics.lift(of: entry, hovered: hovered)
            let visual = CGRect(
                x: frame.midX - size / 2, y: frame.midY - size / 2 + offsetY,
                width: size, height: size
            )
            // The avatar's own image when it is cached, else the host as drawn
            // (snapshot views of a hosting controller can render empty or dark).
            let image = entry.avatarURL.flatMap { ImageCache.shared.image(for: $0) }
                ?? Self.render(hostView, rect: visual)
            let imageView = UIImageView(image: image)
            imageView.frame = CGRect(origin: .zero, size: visual.size)
            imageView.contentMode = .scaleAspectFill
            imageView.backgroundColor = .secondarySystemFill
            imageView.layer.cornerRadius = size / 2
            imageView.layer.cornerCurve = .circular
            imageView.clipsToBounds = true
            avatar = imageView
            avatarFrame = hostView.convert(visual, to: window)
        }

        // The rest of the panel leaves with the old screen.
        model.flyingID = entry.id
        hostView.setNeedsLayout()
        hostView.layoutIfNeeded()
        let panel = hostView.snapshotView(afterScreenUpdates: true)
        let panelFrame = hostView.convert(hostView.bounds, to: window)
        hostView.isHidden = true
        hostView.isUserInteractionEnabled = false

        // Land on where the Me avatar rests, not where it is drawn right now: on iOS 26
        // the glass tab bar is still swollen from the hold and settles back after release.
        AccountSwitchTransition.shared.begin(
            window: window,
            panel: panel, panelFrame: panelFrame,
            avatar: avatar, from: avatarFrame,
            to: meIconFrame(in: window)
        )
        model.isPresented = false
        model.isSticky = false
        model.hoveredID = nil
        model.flyingID = nil

        // Freeze the old screen only once the tab bar has settled, so the avatar lands on
        // the old Me avatar exactly; then rebuild underneath the still.
        let settle: TimeInterval
        if #available(iOS 26.0, *) { settle = 0.24 } else { settle = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + settle) { [configuration, weak window] in
            if let window {
                AccountSwitchTransition.shared.freezeContent(of: window)
            }
            configuration.onPresentationChange(false)
            // Let the still commit before the heavy rebuild starts.
            DispatchQueue.main.async {
                configuration.onSwitch(sessionID)
            }
        }
    }

    private static func render(_ view: UIView, rect: CGRect) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = view.window?.screen.scale ?? 3
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            view.drawHierarchy(
                in: CGRect(origin: CGPoint(x: -rect.minX, y: -rect.minY), size: view.bounds.size),
                afterScreenUpdates: false
            )
        }
    }

    private func layoutPanel() {
        guard let hostView = host?.view, let tabBar = tabBarController?.tabBar else { return }
        let bar = tabBar.convert(tabBar.bounds, to: hostView)
        let me = meTabFrame(in: tabBar).map { tabBar.convert($0, to: hostView) }
            ?? CGRect(x: bar.maxX - bar.width / 4, y: bar.minY, width: bar.width / 4, height: bar.height)
        let above = bar.midY > hostView.bounds.midY
        model.placement = above ? .aboveTabBar : .belowTabBar
        // Center the current account (rightmost) over the Me tab when it fits.
        let half = AccountSwitcherMetrics.avatarSize / 2 + AccountSwitcherMetrics.padding
        model.trailingInset = max(AccountSwitcherMetrics.edgeMargin, hostView.bounds.width - me.midX - half)
        model.edgeInset = above
            ? hostView.bounds.height - bar.minY + AccountSwitcherMetrics.gapToTabBar
            : bar.maxY + AccountSwitcherMetrics.gapToTabBar
    }

    private func makeHostIfNeeded() -> UIHostingController<AnyView>? {
        if let host { return host }
        guard let container else { return nil }
        let host = UIHostingController(rootView: rootView())
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        container.addChild(host)
        host.view.frame = container.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.isHidden = true
        host.view.isUserInteractionEnabled = false
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        self.host = host
        applyInterfaceStyle()
        return host
    }

    /// Glass and materials follow UIKit traits, not the SwiftUI theme, so pin them to the
    /// app's own appearance (which can differ from the system's).
    private func applyInterfaceStyle() {
        host?.overrideUserInterfaceStyle = theme.colorScheme == .dark ? .dark : .light
    }

    private static func themeChanged(_ old: MoroTheme, _ new: MoroTheme) -> Bool {
        old.colorScheme != new.colorScheme
            || old.colorSchemeContrast != new.colorSchemeContrast
            || old.themeColor != new.themeColor
            || old.customThemeColor != new.customThemeColor
            || old.dynamicTypeSize != new.dynamicTypeSize
    }

    private func rootView() -> AnyView {
        AnyView(AccountSwitcherOverlay(model: model).moroTheme(theme).environment(\.colorScheme, theme.colorScheme))
    }

    // MARK: - Me tab geometry

    private func meTabView() -> UIView? {
        guard let tabBar = tabBarController?.tabBar else { return nil }
        return Self.firstView(in: tabBar) { $0.accessibilityIdentifier == Self.meTabIdentifier }
    }

    private func meTabFrame(in tabBar: UITabBar) -> CGRect? {
        if let view = meTabView(), view.bounds.width > 0 {
            return view.convert(view.bounds, to: tabBar)
        }
        // Fallback: the trailing of four equal tab slots.
        let width = tabBar.bounds.width / CGFloat(MainTab.allCases.count)
        guard width > 0 else { return nil }
        let x = tabBar.effectiveUserInterfaceLayoutDirection == .rightToLeft
            ? tabBar.bounds.minX : tabBar.bounds.maxX - width
        return CGRect(x: x, y: 0, width: width, height: tabBar.bounds.height)
    }

    /// Where the Me tab's glyph is drawn. The iOS 26 tab bar doesn't expose the item's
    /// view by identifier, so pick the icon-sized image view nearest the Me slot.
    private func meIconFrame(in window: UIWindow) -> CGRect {
        let size = MeTabAvatarMetrics.avatar
        guard let tabBar = tabBarController?.tabBar, let slot = meTabFrame(in: tabBar) else {
            return CGRect(x: window.bounds.maxX - 60, y: window.bounds.maxY - 70, width: size, height: size)
        }
        var icons: [UIImageView] = []
        var queue: [UIView] = [tabBar]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if let image = view as? UIImageView, image.image != nil, !image.isHidden, image.alpha > 0.01,
                (16...40).contains(image.bounds.width), (16...40).contains(image.bounds.height)
            {
                icons.append(image)
            }
            queue.append(contentsOf: view.subviews)
        }
        let nearest = icons.min { lhs, rhs in
            let l = lhs.convert(lhs.bounds, to: tabBar), r = rhs.convert(rhs.bounds, to: tabBar)
            return abs(l.midX - slot.midX) < abs(r.midX - slot.midX)
        }
        if let nearest {
            let frame = nearest.convert(nearest.bounds, to: window)
            if abs(frame.midX - tabBar.convert(slot, to: window).midX) < slot.width / 2 {
                // On the avatar image, land on the avatar circle inside the ring canvas,
                // scaled the way the tab bar actually drew it.
                let isAvatar = abs((nearest.image?.size.width ?? 0) - MeTabAvatarMetrics.canvas) < 0.5
                let side = isAvatar
                    ? min(frame.width, frame.height) * MeTabAvatarMetrics.avatar / MeTabAvatarMetrics.canvas
                    : size
                return CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side)
            }
        }
        let inWindow = tabBar.convert(slot, to: window)
        return CGRect(x: inWindow.midX - size / 2, y: inWindow.minY + 6, width: size, height: size)
    }

    private static func firstView(in root: UIView, where predicate: (UIView) -> Bool) -> UIView? {
        var queue = [root]
        while !queue.isEmpty {
            let view = queue.removeFirst()
            if view !== root, predicate(view) { return view }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }
}

/// Covers the window while the shell is rebuilt for the new account: the old screen
/// recedes and dims, the chosen avatar arcs into the Me tab, and the new screen is
/// revealed once it has appeared.
@MainActor
final class AccountSwitchTransition {
    nonisolated deinit {}
    static let shared = AccountSwitchTransition()
    private init() {}

    /// Holds a still of the old account above the window while the new shell builds.
    private var cover: UIView?
    private var oldContent: UIView?
    private var avatarView: UIView?
    private var origin: CGPoint = .zero
    private var avatarLanded = false
    private var contentReady = false
    private var isRevealing = false
    private var timeout: DispatchWorkItem?

    private static let flightDuration: TimeInterval = 0.36
    private static let rippleDuration: TimeInterval = 0.46

    var isActive: Bool { cover != nil }

    /// - Parameter to: the Me tab avatar, where the flying avatar lands and the new
    ///   account ripples out from.
    func begin(
        window: UIWindow,
        panel: UIView?, panelFrame: CGRect,
        avatar: UIView?, from: CGRect, to: CGRect
    ) {
        removeCover()
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let cover = UIView(frame: window.bounds)
        cover.backgroundColor = .clear
        cover.isUserInteractionEnabled = true // swallow touches until the new shell shows
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(cover)
        self.cover = cover
        origin = CGPoint(x: to.midX, y: to.midY)
        avatarLanded = false
        contentReady = false
        isRevealing = false

        if let panel {
            panel.frame = panelFrame
            cover.addSubview(panel)
            UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseIn) {
                panel.alpha = 0
            } completion: { _ in
                panel.removeFromSuperview()
            }
        }

        if let avatar, !reduceMotion, from != .zero {
            fly(avatar, from: from, to: to, in: cover)
        } else {
            avatarLanded = true
        }

        let work = DispatchWorkItem { [weak self] in
            self?.avatarLanded = true
            self?.contentReady = true
            self?.revealIfReady()
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    /// Puts a still of the old screen (without the cover's own avatar) under the flight,
    /// hiding the rebuild that follows.
    func freezeContent(of window: UIWindow) {
        guard let cover, oldContent == nil else { return }
        // The root view holds the app but not the cover, so nothing needs hiding.
        let source: UIView = window.rootViewController?.view ?? window
        guard let still = source.snapshotView(afterScreenUpdates: true) else { return }
        still.frame = cover.bounds
        cover.insertSubview(still, at: 0)
        oldContent = still
    }

    /// The new account's shell is on screen underneath the cover.
    func contentDidAppear() {
        guard isActive else { return }
        contentReady = true
        // One more frame so the new shell has actually drawn before it is uncovered.
        DispatchQueue.main.async { [weak self] in self?.revealIfReady() }
    }

    /// The switch failed; the old shell is still underneath, so just lift the cover.
    func cancel() {
        guard let cover, !isRevealing else { return }
        isRevealing = true
        UIView.animate(withDuration: 0.2) {
            cover.alpha = 0
        } completion: { [weak self] _ in
            self?.removeCover()
        }
    }

    private func fly(_ avatar: UIView, from: CGRect, to: CGRect, in cover: UIView) {
        avatar.frame = from
        cover.addSubview(avatar)
        avatarView = avatar

        let start = CGPoint(x: from.midX, y: from.midY)
        let end = CGPoint(x: to.midX, y: to.midY)
        // A short hop: up and over, then down into the tab.
        let control = CGPoint(x: (start.x + end.x) / 2 + 12, y: min(start.y, end.y) - 40)
        let path = UIBezierPath()
        path.move(to: start)
        path.addQuadCurve(to: end, controlPoint: control)

        let position = CAKeyframeAnimation(keyPath: "position")
        position.path = path.cgPath
        position.duration = Self.flightDuration
        position.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        avatar.layer.position = end
        avatar.layer.add(position, forKey: "accountSwitch.fly")

        let scale = to.width / max(from.width, 1)
        UIView.animate(withDuration: Self.flightDuration, delay: 0, options: .curveEaseInOut) {
            avatar.transform = CGAffineTransform(scaleX: scale, y: scale)
        } completion: { [weak self] _ in
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8)
            self?.avatarLanded = true
            self?.revealIfReady()
        }
    }

    private func revealIfReady() {
        guard avatarLanded, contentReady, !isRevealing, let cover else { return }
        isRevealing = true
        timeout?.cancel()
        timeout = nil

        guard let content = oldContent, !UIAccessibility.isReduceMotionEnabled else {
            UIView.animate(withDuration: 0.25) {
                cover.alpha = 0
            } completion: { [weak self] _ in
                self?.removeCover()
            }
            return
        }

        // The new account spreads out from the Me tab: a widening hole in the old still.
        let bounds = content.bounds
        let corners = [
            CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.minX, y: bounds.maxY), CGPoint(x: bounds.maxX, y: bounds.maxY),
        ]
        let center = cover.convert(origin, to: content)
        let radius = corners.map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? bounds.height
        func holePath(_ r: CGFloat) -> CGPath {
            let path = UIBezierPath(rect: bounds)
            path.append(UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)))
            return path.cgPath
        }
        let mask = CAShapeLayer()
        mask.frame = bounds
        mask.fillRule = .evenOdd
        mask.path = holePath(radius)
        content.layer.mask = mask

        // A faint ring rides the wavefront and fades as it spreads.
        let ring = CAShapeLayer()
        ring.frame = bounds
        ring.fillColor = UIColor.clear.cgColor
        ring.strokeColor = UIColor.label.withAlphaComponent(0.14).resolvedColor(with: content.traitCollection).cgColor
        ring.lineWidth = 1.5
        func ringPath(_ r: CGFloat) -> CGPath {
            UIBezierPath(ovalIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).cgPath
        }
        ring.path = ringPath(radius)
        ring.opacity = 0
        content.layer.addSublayer(ring)

        let timing = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.25, 1)
        let start: CGFloat = 12
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.removeCover() }

        let grow = CABasicAnimation(keyPath: "path")
        grow.fromValue = holePath(start)
        grow.toValue = holePath(radius)
        grow.duration = Self.rippleDuration
        grow.timingFunction = timing
        mask.add(grow, forKey: "accountSwitch.ripple")

        let ringGrow = CABasicAnimation(keyPath: "path")
        ringGrow.fromValue = ringPath(start)
        ringGrow.toValue = ringPath(radius)
        let ringFade = CAKeyframeAnimation(keyPath: "opacity")
        ringFade.values = [1, 0.8, 0]
        ringFade.keyTimes = [0, 0.35, 1]
        let ringGroup = CAAnimationGroup()
        ringGroup.animations = [ringGrow, ringFade]
        ringGroup.duration = Self.rippleDuration
        ringGroup.timingFunction = timing
        ring.add(ringGroup, forKey: "accountSwitch.ring")
        CATransaction.commit()

        // The landed avatar hands over to the new shell's own Me tab as the wave leaves it.
        if let avatar = avatarView {
            UIView.animate(withDuration: 0.22, delay: 0.04, options: .curveEaseOut) {
                avatar.alpha = 0
            }
        }
    }

    private func removeCover() {
        timeout?.cancel()
        timeout = nil
        cover?.removeFromSuperview()
        cover = nil
        oldContent = nil
        avatarView = nil
        isRevealing = false
    }
}
