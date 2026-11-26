//
//  MainShellUIKit.swift
//  moro
//
//  UIKit shell container for the app navigation stacks and native bottom tab bar.
//

import SwiftUI
import Combine
import TipKit

#if os(iOS)
    import UIKit
#endif

struct MainShellContainerRepresentable: UIViewControllerRepresentable {
    @ObservedObject var coordinator: RootTabCoordinator

    let theme: MoroTheme
    let unreadInboxCount: Int
    let currentUserAvatarURL: URL?
    let contentVersion: String
    let homeView: AnyView
    let exploreView: AnyView
    let inboxView: AnyView
    let meView: AnyView
    let routeView: (Route, AppRouter) -> AnyView
    var accountSwitcher = AccountSwitcherConfiguration()
    var additionalRootView: (MainTab) -> AnyView = { _ in AnyView(EmptyView()) }

    func makeUIViewController(context: Context) -> MainShellViewController {
        MainShellViewController(
            coordinator: coordinator,
            theme: theme,
            unreadInboxCount: unreadInboxCount,
            currentUserAvatarURL: currentUserAvatarURL,
            contentVersion: contentVersion,
            homeView: homeView,
            exploreView: exploreView,
            inboxView: inboxView,
            meView: meView,
            routeView: routeView,
            accountSwitcher: accountSwitcher,
            additionalRootView: additionalRootView
        )
    }

    func updateUIViewController(_ uiViewController: MainShellViewController, context: Context) {
        uiViewController.apply(
            theme: theme,
            unreadInboxCount: unreadInboxCount,
            currentUserAvatarURL: currentUserAvatarURL,
            contentVersion: contentVersion,
            homeView: homeView,
            exploreView: exploreView,
            inboxView: inboxView,
            meView: meView,
            routeView: routeView,
            accountSwitcher: accountSwitcher,
            additionalRootView: additionalRootView
        )
    }
}

#if os(iOS)
    @MainActor
    final class MainShellViewController: UIViewController, UITabBarControllerDelegate, UIGestureRecognizerDelegate {
        private let coordinator: RootTabCoordinator
        private let mainTabController = UITabBarController()
        private lazy var drawerEdgePanRecognizer: UIScreenEdgePanGestureRecognizer = {
            let recognizer = UIScreenEdgePanGestureRecognizer(
                target: self,
                action: #selector(handleDrawerEdgePan(_:))
            )
            recognizer.delegate = self
            return recognizer
        }()

        private var currentContentVersion: String
        private var rootViews: [MainTab: AnyView]
        private var additionalRootView: (MainTab) -> AnyView
        private var routeView: (Route, AppRouter) -> AnyView
        private var appliedTheme: MoroTheme
        private var appliedUnreadInboxCount: Int
        private var appliedAvatarURL: URL?
        private var loadedAvatarImage: UIImage?
        private var avatarTask: Task<Void, Never>?
        private let retapTip = TabRetapRefreshTip()
        private var retapTipTask: Task<Void, Never>?
        private weak var retapTipPopover: UIViewController?
        private var accountSwitcherConfiguration: AccountSwitcherConfiguration
        private lazy var accountSwitcher = AccountSwitcherController(
            container: self,
            tabBarController: mainTabController,
            theme: appliedTheme
        )

        // Keep each visited destination's controller when it moves or is hidden.
        private var navigationControllers: [MainTab: MainShellNavigationController] = [:]
        private var appliedTabs: [MainTab] = []

        init(
            coordinator: RootTabCoordinator,
            theme: MoroTheme,
            unreadInboxCount: Int,
            currentUserAvatarURL: URL?,
            contentVersion: String,
            homeView: AnyView,
            exploreView: AnyView,
            inboxView: AnyView,
            meView: AnyView,
            routeView: @escaping (Route, AppRouter) -> AnyView,
            accountSwitcher: AccountSwitcherConfiguration? = nil,
            additionalRootView: @escaping (MainTab) -> AnyView = { _ in AnyView(EmptyView()) }
        ) {
            self.accountSwitcherConfiguration = accountSwitcher ?? AccountSwitcherConfiguration()
            self.coordinator = coordinator
            self.appliedTheme = theme
            self.appliedUnreadInboxCount = unreadInboxCount
            self.appliedAvatarURL = currentUserAvatarURL
            self.currentContentVersion = contentVersion
            self.rootViews = [.home: homeView, .explore: exploreView, .inbox: inboxView, .me: meView]
            self.additionalRootView = additionalRootView
            self.routeView = routeView
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            avatarTask?.cancel()
            retapTipTask?.cancel()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            configureHierarchy()
            installHingeObserver()
            mainTabController.delegate = self
            updateTabLayout()
            apply(theme: appliedTheme)
            updateAvatar(appliedAvatarURL, force: true)
            updateSelectedTab(coordinator.selectedTab)
            accountSwitcher.install()
            accountSwitcher.update(configuration: accountSwitcherConfiguration, theme: appliedTheme)
            installDrawerEdgeGesture()
        }

        private func installDrawerEdgeGesture() {
            drawerEdgePanRecognizer.edges = view.effectiveUserInterfaceLayoutDirection == .rightToLeft ? .right : .left
            view.addGestureRecognizer(drawerEdgePanRecognizer)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === drawerEdgePanRecognizer else { return true }
            return coordinator.canOpenDrawerByEdgeSwipe
        }

        @objc private func handleDrawerEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            let isRTL = view.effectiveUserInterfaceLayoutDirection == .rightToLeft
            let leadingInset = isRTL ? view.safeAreaInsets.right : view.safeAreaInsets.left
            let drawerWidth = MoroNavigationDrawer.preferredWidth(
                containerWidth: view.bounds.width,
                leadingSafeInset: leadingInset
            )
            let rawTranslation = recognizer.translation(in: view).x
            let rawVelocity = recognizer.velocity(in: view).x
            let directedTranslation = isRTL ? -rawTranslation : rawTranslation
            let directedVelocity = isRTL ? -rawVelocity : rawVelocity

            switch recognizer.state {
            case .began, .changed:
                coordinator.updateDrawerEdgeGesture(progress: max(0, directedTranslation) / drawerWidth)
            case .ended:
                let shouldOpen = directedVelocity > 380
                    || (directedVelocity > -180 && directedTranslation > drawerWidth * 0.32)
                coordinator.finishDrawerEdgeGesture(shouldOpen: shouldOpen)
            case .cancelled, .failed:
                coordinator.finishDrawerEdgeGesture(shouldOpen: false)
            default:
                break
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // A fresh shell after an account switch: reveal it.
            AccountSwitchTransition.shared.contentDidAppear()
            observeRetapTip()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            retapTipTask?.cancel()
            retapTipTask = nil
        }

        // MARK: - Re-tap hint

        private func observeRetapTip() {
            guard retapTipTask == nil else { return }
            retapTipTask = Task { @MainActor [weak self, retapTip] in
                for await shouldDisplay in retapTip.shouldDisplayUpdates {
                    self?.updateRetapTip(shouldDisplay: shouldDisplay)
                }
            }
        }

        /// The hint points at the Home tab, so it only shows while Home is on screen with
        /// nothing presented over it; switching back to Home shows it if it is still due.
        private func updateRetapTip(shouldDisplay: Bool) {
            guard shouldDisplay else {
                retapTipPopover?.dismiss(animated: true)
                retapTipPopover = nil
                return
            }
            guard retapTipPopover == nil, presentedViewController == nil,
                coordinator.selectedTab == .home, coordinator.isAtRoot(.home)
            else { return }
            let popover = TipUIPopoverViewController(retapTip, sourceItem: navigationController(for: .home).tabBarItem)
            popover.view.accessibilityIdentifier = "tip.tabRetapRefresh"
            present(popover, animated: true)
            retapTipPopover = popover
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            publishTabBarHeight()
            accountSwitcher.refreshPresentedLayout()
            accountSwitcher.refreshAccessibilityActions()
        }

        override func viewSafeAreaInsetsDidChange() {
            super.viewSafeAreaInsetsDidChange()
            publishTabBarHeight()
        }

        func apply(
            theme: MoroTheme,
            unreadInboxCount: Int,
            currentUserAvatarURL: URL?,
            contentVersion: String,
            homeView: AnyView,
            exploreView: AnyView,
            inboxView: AnyView,
            meView: AnyView,
            routeView: @escaping (Route, AppRouter) -> AnyView,
            accountSwitcher accountSwitcherConfiguration: AccountSwitcherConfiguration? = nil,
            additionalRootView: @escaping (MainTab) -> AnyView = { _ in AnyView(EmptyView()) }
        ) {
            self.routeView = routeView
            self.additionalRootView = additionalRootView
            let switcherConfiguration = accountSwitcherConfiguration ?? AccountSwitcherConfiguration()
            let accountsChanged = self.accountSwitcherConfiguration.sessions != switcherConfiguration.sessions
            self.accountSwitcherConfiguration = switcherConfiguration
            accountSwitcher.update(configuration: switcherConfiguration, theme: theme)

            if currentContentVersion != contentVersion {
                currentContentVersion = contentVersion
                rootViews = [.home: homeView, .explore: exploreView, .inbox: inboxView, .me: meView]
                for (tab, controller) in navigationControllers {
                    controller.setRootView(rootViews[tab] ?? additionalRootView(tab))
                }
            } else if accountsChanged,
                      let settings = navigationControllers[.settings]?.viewControllers.first as? MainShellHostingController {
                settings.updateContent(additionalRootView(.settings))
            }

            if appliedTheme.colorScheme != theme.colorScheme
                || appliedTheme.colorSchemeContrast != theme.colorSchemeContrast
                || appliedTheme.accent != theme.accent
                || appliedTheme.themeColor != theme.themeColor
                || appliedTheme.customThemeColor != theme.customThemeColor
                || appliedTheme.postFontSize != theme.postFontSize
                || appliedTheme.dynamicTypeSize != theme.dynamicTypeSize
            {
                apply(theme: theme)
            }

            if appliedUnreadInboxCount != unreadInboxCount {
                appliedUnreadInboxCount = unreadInboxCount
                applyInboxBadge()
            }

            updateTabLayout()
            updateAvatar(currentUserAvatarURL)
            updateSelectedTab(coordinator.selectedTab)
        }

        /// Only devices with a hinge report one; the first update arrives right after install.
        private func installHingeObserver() {
            // UIHingeInteraction is an iOS 27.1 SDK API (Swift 6.4); older toolchains, such as
            // CI's Xcode 26, build without it.
            #if compiler(>=6.4)
            guard #available(iOS 27.1, *) else { return }
            let interaction = UIHingeInteraction { [weak self] _, update in
                self?.applyHingePresence(update.hinge != nil)
            }
            view.addInteraction(interaction)
            #endif
        }

        private func applyHingePresence(_ hasHinge: Bool) {
            // Explore and Notifications put their controls in the system bar too.
            for tab in [MainTab.home, .explore, .inbox] {
                navigationControllers[tab]?.setShowsNavigationBarAtRoot(hasHinge)
            }
            if coordinator.usesSystemHomeBar != hasHinge {
                coordinator.usesSystemHomeBar = hasHinge
            }
        }

        private func configureHierarchy() {
            view.backgroundColor = UIColor(appliedTheme.colors.surfaceBase)
            addChild(mainTabController)
            view.addSubview(mainTabController.view)
            mainTabController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                mainTabController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                mainTabController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                mainTabController.view.topAnchor.constraint(equalTo: view.topAnchor),
                mainTabController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            mainTabController.didMove(toParent: self)
        }

        private func updateTabLayout() {
            let tabs = coordinator.tabLayout.tabs
            guard tabs != appliedTabs else { return }
            appliedTabs = tabs
            mainTabController.setViewControllers(tabs.map(navigationController(for:)), animated: false)
            view.setNeedsLayout()
        }

        private func configureTabBarItem(_ controller: UIViewController, for tab: MainTab) {
            let item = UITabBarItem()
            Self.setTabIcons(
                on: item,
                image: Self.tabGlyph(tab.icon, configuration: Self.glyphConfiguration),
                selectedImage: Self.tabGlyph(tab.filledIcon, configuration: Self.selectedGlyphConfiguration),
                label: tab.title
            )
            item.accessibilityIdentifier = "mainTab.\(tab.rawValue)"
            item.largeContentSizeImage = UIImage(systemName: tab.icon)
            controller.tabBarItem = item
        }

        private static func setTabIcons(
            on item: UITabBarItem, image: UIImage?, selectedImage: UIImage?, label: String
        ) {
            item.image = image
            item.selectedImage = selectedImage
            // UIKit can derive an untitled tab's name from its installed image after insertion.
            item.image?.accessibilityLabel = label
            item.selectedImage?.accessibilityLabel = label
            item.accessibilityLabel = label
            if #unavailable(iOS 26.0) {
                item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            }
        }

        private static let glyphConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        private static let selectedGlyphConfiguration = UIImage.SymbolConfiguration(pointSize: 21, weight: .semibold)

        /// The two-tone "unread" bell: the glyph in the tab's own state color, the badge
        /// layer (the symbol's first palette slot) red. Drawn as-is, since a template
        /// image would tint the badge along with the bell.
        private static func badgedGlyph(
            _ name: String, configuration: UIImage.SymbolConfiguration, glyph: UIColor, badge: UIColor
        ) -> UIImage? {
            let palette = configuration.applying(UIImage.SymbolConfiguration(paletteColors: [badge, glyph]))
            guard let symbol = UIImage(systemName: name, withConfiguration: palette)?
                .withRenderingMode(.alwaysOriginal)
            else { return nil }
            guard #unavailable(iOS 26.0) else { return symbol }
            let side = MeTabAvatarMetrics.canvas
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            // Drawing a palette symbol straight into a context loses its palette (the glyph
            // comes out in the default tint); an image view renders it faithfully.
            let canvas = UIView(frame: CGRect(x: 0, y: 0, width: side, height: side))
            let glyphView = UIImageView(image: symbol)
            // The bell layer still follows the view's tint here; give it the state color.
            glyphView.tintColor = glyph
            glyphView.frame = CGRect(
                x: (side - symbol.size.width) / 2, y: (side - symbol.size.height) / 2,
                width: symbol.size.width, height: symbol.size.height
            )
            canvas.addSubview(glyphView)
            return UIGraphicsImageRenderer(size: canvas.bounds.size, format: format).image { context in
                canvas.layer.render(in: context.cgContext)
            }
            .withRenderingMode(.alwaysOriginal)
        }

        /// On the classic (pre-iOS 26) bar every item image shares one canvas — the Me
        /// avatar's — so glyphs and the avatar are laid out identically and line up.
        /// iOS 26 centers untitled items itself, so its glyphs stay native.
        private static func tabGlyph(_ name: String, configuration: UIImage.SymbolConfiguration) -> UIImage? {
            guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
            guard #unavailable(iOS 26.0) else { return symbol.withRenderingMode(.alwaysTemplate) }
            let side = MeTabAvatarMetrics.canvas
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let padded = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
                symbol.withTintColor(.black, renderingMode: .alwaysOriginal).draw(at: CGPoint(
                    x: (side - symbol.size.width) / 2,
                    y: (side - symbol.size.height) / 2
                ))
            }
            return padded.withRenderingMode(.alwaysTemplate)
        }

        private func apply(theme: MoroTheme) {
            appliedTheme = theme
            view.backgroundColor = UIColor(theme.colors.surfaceBase)
            mainTabController.view.backgroundColor = UIColor(theme.colors.surfaceBase)

            let selectedColor = UIColor(theme.colors.textPrimary)
            let unselectedColor = UIColor(theme.colors.textSecondary)
            mainTabController.tabBar.tintColor = selectedColor
            mainTabController.tabBar.unselectedItemTintColor = unselectedColor

            if #unavailable(iOS 26.0) {
                let appearance = UITabBarAppearance()
                appearance.configureWithDefaultBackground()
                appearance.backgroundColor = UIColor(theme.colors.surfaceBase)
                appearance.shadowColor = UIColor(theme.colors.divider)
                appearance.stackedLayoutAppearance.selected.iconColor = selectedColor
                appearance.stackedLayoutAppearance.selected.titleTextAttributes = [
                    .foregroundColor: selectedColor,
                ]
                appearance.stackedLayoutAppearance.normal.iconColor = unselectedColor
                appearance.stackedLayoutAppearance.normal.titleTextAttributes = [
                    .foregroundColor: unselectedColor,
                ]
                mainTabController.tabBar.standardAppearance = appearance
                mainTabController.tabBar.scrollEdgeAppearance = appearance
            }

            for controller in navigationControllers.values {
                controller.apply(theme: theme)
            }

            applyInboxBadge()

            if loadedAvatarImage != nil {
                applyAvatarImages()
            }
        }

        private func applyInboxBadge() {
            let count = appliedUnreadInboxCount
            let item: UITabBarItem = navigationController(for: .inbox).tabBarItem
            // Unread shows as the bell's own badge layer — a small red dot cut into the
            // glyph — instead of the system's large count bubble. The count stays in the
            // inbox and in the VoiceOver label.
            item.badgeValue = nil
            let image: UIImage?
            let selectedImage: UIImage?
            if count > 0 {
                image = Self.badgedGlyph(
                    "bell.badge", configuration: Self.glyphConfiguration,
                    glyph: UIColor(appliedTheme.colors.textSecondary), badge: .systemRed
                )
                selectedImage = Self.badgedGlyph(
                    "bell.badge.fill", configuration: Self.selectedGlyphConfiguration,
                    glyph: UIColor(appliedTheme.colors.textPrimary), badge: .systemRed
                )
            } else {
                image = Self.tabGlyph(MainTab.inbox.icon, configuration: Self.glyphConfiguration)
                selectedImage = Self.tabGlyph(
                    MainTab.inbox.filledIcon, configuration: Self.selectedGlyphConfiguration
                )
            }
            Self.setTabIcons(
                on: item, image: image, selectedImage: selectedImage,
                label: count > 0 ? MoroL10n.Navigation.inboxUnread(count) : MainTab.inbox.title
            )
        }

        private func updateAvatar(_ avatarURL: URL?, force: Bool = false) {
            guard force || appliedAvatarURL != avatarURL else { return }
            appliedAvatarURL = avatarURL
            avatarTask?.cancel()
            loadedAvatarImage = nil
            configureTabBarItem(navigationController(for: .me), for: .me)

            guard let avatarURL else { return }
            // Already decoded (e.g. prefetched by the account switcher): show it on the
            // first frame so a freshly switched shell never flashes the placeholder glyph.
            if let cached = ImageCache.shared.image(for: avatarURL) {
                loadedAvatarImage = cached
                applyAvatarImages()
                return
            }
            avatarTask = Task { [weak self] in
                guard let self else { return }
                let image = await ImageCache.shared.load(from: avatarURL)
                guard !Task.isCancelled, self.appliedAvatarURL == avatarURL else { return }
                self.loadedAvatarImage = image
                self.applyAvatarImages()
            }
        }

        private func applyAvatarImages() {
            guard let image = loadedAvatarImage else { return }
            let item: UITabBarItem = navigationController(for: .me).tabBarItem
            Self.setTabIcons(
                on: item,
                image: circularAvatarImage(image, selected: false),
                selectedImage: circularAvatarImage(image, selected: true),
                label: MainTab.me.title
            )
        }

        private func circularAvatarImage(_ image: UIImage, selected: Bool) -> UIImage {
            let canvas = MeTabAvatarMetrics.canvas
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: canvas, height: canvas), format: format)

            return renderer.image { context in
                // The avatar keeps one size in both states; selection only adds an outer ring,
                // the same ring the account switcher puts around the current account.
                let bounds = CGRect(x: 0, y: 0, width: canvas, height: canvas)
                let inset = (canvas - MeTabAvatarMetrics.avatar) / 2
                let avatarRect = bounds.insetBy(dx: inset, dy: inset)
                context.cgContext.saveGState()
                context.cgContext.addEllipse(in: avatarRect)
                context.cgContext.clip()
                let scale = max(avatarRect.width / image.size.width, avatarRect.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(
                    x: avatarRect.midX - drawSize.width / 2,
                    y: avatarRect.midY - drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                ))
                context.cgContext.restoreGState()

                if selected {
                    UIColor(appliedTheme.colors.textPrimary).setStroke()
                    let ringWidth = MeTabAvatarMetrics.ringWidth
                    let ring = UIBezierPath(ovalIn: bounds.insetBy(dx: ringWidth / 2, dy: ringWidth / 2))
                    ring.lineWidth = ringWidth
                    ring.stroke()
                } else {
                    UIColor(appliedTheme.colors.borderSubtle).setStroke()
                    let hairline = UIBezierPath(ovalIn: avatarRect.insetBy(dx: 0.25, dy: 0.25))
                    hairline.lineWidth = 0.5
                    hairline.stroke()
                }
            }
            .withRenderingMode(.alwaysOriginal)
        }

        private func publishTabBarHeight() {
            let frame = mainTabController.tabBar.frame
            guard frame.height > 0 else { return }
            // On iPhone Duo the bar runs down the side, so nothing covers the bottom of the
            // content and only the compose button's clearance remains.
            let height = frame.height > frame.width ? 0 : frame.height
            let trailingInset = Self.resolvedTabBarTrailingInset(in: mainTabController.tabBar)

            let heightChanged = abs(coordinator.tabBarHeight - height) > 0.5
            let insetChanged = abs(coordinator.tabBarTrailingInset - trailingInset) > 0.5
            guard heightChanged || insetChanged else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if abs(self.coordinator.tabBarHeight - height) > 0.5 {
                    self.coordinator.tabBarHeight = height
                }
                if abs(self.coordinator.tabBarTrailingInset - trailingInset) > 0.5 {
                    self.coordinator.tabBarTrailingInset = trailingInset
                }
            }
        }

        private static func resolvedTabBarTrailingInset(in tabBar: UITabBar) -> CGFloat {
            guard #available(iOS 26, *) else { return 16 }
            let barWidth = tabBar.bounds.width
            guard barWidth > 0, tabBar.bounds.height <= barWidth else { return 21 }
            // Match the floating Liquid Glass capsule's outer trailing margin while ignoring
            // full-width wrapper views and narrow centered capsules (e.g. 2-tab layouts).
            var matchedInset: CGFloat?
            for subview in tabBar.subviews {
                let rect = tabBar.convert(subview.bounds, from: subview)
                guard rect.width >= barWidth * 0.72,
                    rect.width < barWidth - 8,
                    rect.height >= 44
                else { continue }
                let trailingInset = max(0, barWidth - rect.maxX)
                if let current = matchedInset {
                    matchedInset = min(current, trailingInset)
                } else {
                    matchedInset = trailingInset
                }
            }
            if let inset = matchedInset {
                return min(max(inset, 16), 28)
            }
            return 21
        }

        private func updateSelectedTab(_ tab: MainTab) {
            let controller = navigationController(for: tab)
            if mainTabController.selectedViewController !== controller {
                mainTabController.selectedViewController = controller
            }
            applySelectedTabPresentation(tab)
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            didSelect viewController: UIViewController
        ) {
            guard let tab = navigationControllers.first(where: { $0.value === viewController })?.key else { return }
            coordinator.selectTab(tab)
            applySelectedTabPresentation(tab)
        }

        private func makeNavigationController(
            tab: MainTab,
            router: AppRouter,
            rootView: AnyView
        ) -> MainShellNavigationController {
            MainShellNavigationController(
                tab: tab,
                router: router,
                rootView: rootView,
                routeView: { [weak self] route, router in
                    self?.routeView(route, router) ?? AnyView(EmptyView())
                },
                theme: appliedTheme,
                showsNavigationBarAtRoot: showsNavigationBarAtRoot(for: tab),
                onRootStateChanged: { [weak self] isAtRoot in
                    guard let self else { return }
                    self.coordinator.setIsAtRoot(isAtRoot, for: tab)
                    if self.coordinator.selectedTab == tab {
                        self.updateTabBarVisibility()
                    }
                },
                onSceneChanged: { [weak self] descriptor in
                    guard let self else { return }
                    if tab == .home {
                        self.coordinator.setHomeShowsInbox(descriptor == Route.inbox.sceneDescriptor)
                    }
                    guard self.coordinator.selectedTab == tab else { return }
                    self.applyScenePresentation(descriptor)
                }
            )
        }

        private func applySelectedTabPresentation(_ tab: MainTab) {
            if tab == .home {
                updateRetapTip(shouldDisplay: retapTip.shouldDisplay)
            } else if retapTipPopover != nil {
                updateRetapTip(shouldDisplay: false)
            }
            updateTabBarVisibility()
            applyScenePresentation(navigationController(for: tab).currentSceneDescriptor)
        }

        private func updateTabBarVisibility() {
            let hidden = coordinator.isTabBarHidden
            guard mainTabController.isTabBarHidden != hidden else { return }
            // Let UIKit update the bar and its safe area together.
            mainTabController.setTabBarHidden(hidden, animated: false)
        }

        private func applyScenePresentation(_ descriptor: MoroSceneDescriptor) {
            // Paint the container behind its child. An overlay at the bottom of
            // this view covers the composer when SwiftUI resizes for a keyboard.
            let color = UIColor(descriptor.canvas.backgroundColor(in: appliedTheme))
            view.backgroundColor = color
            view.window?.backgroundColor = color
            mainTabController.view.backgroundColor = color
            mainTabController.tabBar.backgroundColor = descriptor.presentation == .root
                ? .clear
                : color
        }

        private func showsNavigationBarAtRoot(for tab: MainTab) -> Bool {
            switch tab {
            case .home, .explore, .inbox:
                return coordinator.usesSystemHomeBar
            case .me, .lists, .bookmarks, .favourites:
                return true
            case .settings:
                return false
            }
        }

        private func navigationController(for tab: MainTab) -> MainShellNavigationController {
            if let controller = navigationControllers[tab] { return controller }
            let controller = makeNavigationController(
                tab: tab,
                router: coordinator.router(for: tab),
                rootView: rootViews[tab] ?? additionalRootView(tab)
            )
            configureTabBarItem(controller, for: tab)
            navigationControllers[tab] = controller
            return controller
        }
    }

    private final class MainShellHostingController: UIHostingController<AnyView> {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        let sceneDescriptor: MoroSceneDescriptor

        private var contentRootView: AnyView
        private var appliedTheme: MoroTheme

        init(
            rootView: AnyView,
            sceneDescriptor: MoroSceneDescriptor,
            theme: MoroTheme
        ) {
            self.contentRootView = rootView
            self.sceneDescriptor = sceneDescriptor
            self.appliedTheme = theme
            super.init(
                rootView: Self.hostedRootView(
                    rootView,
                    sceneDescriptor: sceneDescriptor,
                    theme: theme
                )
            )
        }

        @available(*, unavailable)
        required dynamic init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = UIColor(sceneDescriptor.canvas.backgroundColor(in: appliedTheme))
        }

        func updateContent(_ content: AnyView) {
            contentRootView = content
            rootView = Self.hostedRootView(content, sceneDescriptor: sceneDescriptor, theme: appliedTheme)
        }

        func apply(theme: MoroTheme) {
            let shouldUpdateRootView = appliedTheme.colorScheme != theme.colorScheme
                || appliedTheme.colorSchemeContrast != theme.colorSchemeContrast
                || appliedTheme.accent != theme.accent
                || appliedTheme.themeColor != theme.themeColor
                || appliedTheme.customThemeColor != theme.customThemeColor
                || appliedTheme.postFontSize != theme.postFontSize
                || appliedTheme.dynamicTypeSize != theme.dynamicTypeSize
            appliedTheme = theme
            if shouldUpdateRootView {
                rootView = Self.hostedRootView(
                    contentRootView,
                    sceneDescriptor: sceneDescriptor,
                    theme: theme
                )
            }
            view.backgroundColor = UIColor(sceneDescriptor.canvas.backgroundColor(in: theme))
        }

        private static func hostedRootView(
            _ rootView: AnyView,
            sceneDescriptor: MoroSceneDescriptor,
            theme: MoroTheme
        ) -> AnyView {
            AnyView(
                MoroSceneHost(descriptor: sceneDescriptor) {
                    rootView
                }
                .moroTheme(theme)
            )
        }
    }

    private final class MainShellNavigationController: UINavigationController, UINavigationControllerDelegate,
        AppRouterNavigator
    {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        private let router: AppRouter
        private let routeView: (Route, AppRouter) -> AnyView
        private let onRootStateChanged: (Bool) -> Void
        private let onSceneChanged: (MoroSceneDescriptor) -> Void
        private var showsNavigationBarAtRoot: Bool
        private let rootSceneDescriptor: MoroSceneDescriptor
        private var appliedTheme: MoroTheme

        init(
            tab: MainTab,
            router: AppRouter,
            rootView: AnyView,
            routeView: @escaping (Route, AppRouter) -> AnyView,
            theme: MoroTheme,
            showsNavigationBarAtRoot: Bool,
            onRootStateChanged: @escaping (Bool) -> Void,
            onSceneChanged: @escaping (MoroSceneDescriptor) -> Void
        ) {
            self.router = router
            self.routeView = routeView
            self.appliedTheme = theme
            self.onRootStateChanged = onRootStateChanged
            self.onSceneChanged = onSceneChanged
            self.showsNavigationBarAtRoot = showsNavigationBarAtRoot
            self.rootSceneDescriptor = tab.rootSceneDescriptor
            super.init(
                rootViewController: MainShellHostingController(
                    rootView: rootView,
                    sceneDescriptor: tab.rootSceneDescriptor,
                    theme: theme
                )
            )
            self.router.navigator = self
            delegate = self
            navigationBar.prefersLargeTitles = false
            apply(theme: theme)
            setNavigationBarHidden(!showsNavigationBarAtRoot, animated: false)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        func setRootView(_ rootView: AnyView) {
            setViewControllers(
                [
                    MainShellHostingController(
                        rootView: rootView,
                        sceneDescriptor: rootSceneDescriptor,
                        theme: appliedTheme
                    )
                ],
                animated: false
            )
            setNavigationBarHidden(!showsNavigationBarAtRoot, animated: false)
            onRootStateChanged(true)
            onSceneChanged(rootSceneDescriptor)
        }

        /// Home shows the system bar at its root on iPhone Duo (see `usesSystemHomeBar`).
        func setShowsNavigationBarAtRoot(_ shows: Bool) {
            guard showsNavigationBarAtRoot != shows else { return }
            showsNavigationBarAtRoot = shows
            guard topViewController === viewControllers.first else { return }
            setNavigationBarHidden(
                shouldHideNavigationBar(isRoot: true, sceneDescriptor: rootSceneDescriptor),
                animated: false
            )
        }

        func navigate(to route: Route) {
            // A second notification can arrive while the first one's detail is still open.
            if route == .inbox, let inbox = viewControllers.last(where: { descriptor(for: $0) == route.sceneDescriptor }) {
                if topViewController !== inbox { popToViewController(inbox, animated: false) }
                return
            }
            let controller = MainShellHostingController(
                rootView: routeView(route, router),
                sceneDescriptor: route.sceneDescriptor,
                theme: appliedTheme
            )
            pushViewController(controller, animated: true)
        }

        func pop() {
            guard viewControllers.count > 1 else { return }
            popViewController(animated: true)
        }

        func popToRoot() {
            guard viewControllers.count > 1 else { return }
            popToRootViewController(animated: true)
        }

        func replaceTop(with route: Route) {
            let controller = MainShellHostingController(
                rootView: routeView(route, router),
                sceneDescriptor: route.sceneDescriptor,
                theme: appliedTheme
            )
            guard viewControllers.count > 1 else {
                pushViewController(controller, animated: false)
                return
            }
            var stack = viewControllers
            stack[stack.count - 1] = controller
            setViewControllers(stack, animated: false)
            // A non-animated swap may not round-trip through the delegate; sync the bar now.
            let descriptor = route.sceneDescriptor
            applyNavigationAppearance(for: descriptor)
            onSceneChanged(descriptor)
            setNavigationBarHidden(
                shouldHideNavigationBar(isRoot: false, sceneDescriptor: descriptor),
                animated: false
            )
        }

        func replace(with route: Route) {
            let root = viewControllers.first
                ?? MainShellHostingController(
                    rootView: AnyView(EmptyView()),
                    sceneDescriptor: rootSceneDescriptor,
                    theme: appliedTheme
                )
            let controller = MainShellHostingController(
                rootView: routeView(route, router),
                sceneDescriptor: route.sceneDescriptor,
                theme: appliedTheme
            )
            setViewControllers([root, controller], animated: true)
        }

        func apply(theme: MoroTheme) {
            appliedTheme = theme
            for controller in viewControllers {
                (controller as? MainShellHostingController)?.apply(theme: theme)
            }
            applyNavigationAppearance(for: visibleSceneDescriptor)
            onSceneChanged(visibleSceneDescriptor)
        }

        func navigationController(
            _ navigationController: UINavigationController,
            willShow viewController: UIViewController,
            animated: Bool
        ) {
            let isRoot = viewController === viewControllers.first
            let sceneDescriptor = descriptor(for: viewController)
            applyNavigationAppearance(for: sceneDescriptor)
            onSceneChanged(sceneDescriptor)
            setNavigationBarHidden(
                shouldHideNavigationBar(isRoot: isRoot, sceneDescriptor: sceneDescriptor),
                animated: animated
            )
            onRootStateChanged(isRoot)
        }

        func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            let isRoot = viewController === viewControllers.first
            let sceneDescriptor = descriptor(for: viewController)
            applyNavigationAppearance(for: sceneDescriptor)
            onSceneChanged(sceneDescriptor)
            setNavigationBarHidden(
                shouldHideNavigationBar(isRoot: isRoot, sceneDescriptor: sceneDescriptor),
                animated: false
            )
            onRootStateChanged(isRoot)
        }

        private var visibleSceneDescriptor: MoroSceneDescriptor {
            descriptor(for: topViewController)
        }

        var currentSceneDescriptor: MoroSceneDescriptor {
            visibleSceneDescriptor
        }

        private func descriptor(for viewController: UIViewController?) -> MoroSceneDescriptor {
            (viewController as? MainShellHostingController)?.sceneDescriptor ?? rootSceneDescriptor
        }

        private func shouldHideNavigationBar(
            isRoot: Bool,
            sceneDescriptor: MoroSceneDescriptor
        ) -> Bool {
            sceneDescriptor.topBar == .hidden || (isRoot && !showsNavigationBarAtRoot)
        }

        private func applyNavigationAppearance(for sceneDescriptor: MoroSceneDescriptor) {
            let role = sceneDescriptor.topBar
            let appearance = UINavigationBarAppearance()

            if role == .heroOverlay || role == .hidden {
                appearance.configureWithTransparentBackground()
                appearance.backgroundColor = .clear
                appearance.shadowColor = .clear
                navigationBar.isTranslucent = true
            } else {
                appearance.configureWithOpaqueBackground()
                appearance.backgroundColor = UIColor(role.backgroundColor(in: appliedTheme))
                appearance.shadowColor = UIColor(appliedTheme.colors.divider)
                navigationBar.isTranslucent = false
            }

            let foregroundColor = UIColor(role.foregroundColor(in: appliedTheme))
            appearance.titleTextAttributes = [
                .foregroundColor: foregroundColor,
                .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            ]
            appearance.largeTitleTextAttributes = [
                .foregroundColor: foregroundColor,
            ]

            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.tintColor = foregroundColor
            view.backgroundColor = UIColor(sceneDescriptor.canvas.backgroundColor(in: appliedTheme))
        }
    }
#endif

/// The Me tab's avatar image: a fixed-size avatar inside a canvas that leaves room for the
/// selection ring (ring, a hairline gap, then the avatar). The account switcher lands its
/// flying avatar on exactly this circle.
enum MeTabAvatarMetrics {
    static let avatar: CGFloat = 30
    static let ringWidth: CGFloat = 1.75
    static let ringGap: CGFloat = 1.75
    static var canvas: CGFloat { avatar + (ringWidth + ringGap) * 2 }
}
