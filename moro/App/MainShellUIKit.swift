//
//  MainShellUIKit.swift
//  moro
//
//  UIKit shell container for the app navigation stacks and native bottom tab bar.
//

import SwiftUI
import Combine

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
            accountSwitcher: accountSwitcher
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
            accountSwitcher: accountSwitcher
        )
    }
}

#if os(iOS)
    @MainActor
    final class MainShellViewController: UIViewController, UITabBarControllerDelegate {
        private let coordinator: RootTabCoordinator
        private let mainTabController = UITabBarController()

        private var currentContentVersion: String
        private var homeRootView: AnyView
        private var exploreRootView: AnyView
        private var inboxRootView: AnyView
        private var meRootView: AnyView
        private var routeView: (Route, AppRouter) -> AnyView
        private var appliedTheme: MoroTheme
        private var appliedUnreadInboxCount: Int
        private var appliedAvatarURL: URL?
        private var loadedAvatarImage: UIImage?
        private var avatarTask: Task<Void, Never>?
        private var accountSwitcherConfiguration: AccountSwitcherConfiguration
        private lazy var accountSwitcher = AccountSwitcherController(
            container: self,
            tabBarController: mainTabController,
            theme: appliedTheme
        )

        private lazy var homeNavigationController = makeNavigationController(
            tab: .home,
            router: coordinator.homeRouter,
            rootView: homeRootView
        )
        private lazy var exploreNavigationController = makeNavigationController(
            tab: .explore,
            router: coordinator.exploreRouter,
            rootView: exploreRootView
        )
        private lazy var inboxNavigationController = makeNavigationController(
            tab: .inbox,
            router: coordinator.inboxRouter,
            rootView: inboxRootView
        )
        private lazy var meNavigationController = makeNavigationController(
            tab: .me,
            router: coordinator.meRouter,
            rootView: meRootView
        )

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
            accountSwitcher: AccountSwitcherConfiguration? = nil
        ) {
            self.accountSwitcherConfiguration = accountSwitcher ?? AccountSwitcherConfiguration()
            self.coordinator = coordinator
            self.appliedTheme = theme
            self.appliedUnreadInboxCount = unreadInboxCount
            self.appliedAvatarURL = currentUserAvatarURL
            self.currentContentVersion = contentVersion
            self.homeRootView = homeView
            self.exploreRootView = exploreView
            self.inboxRootView = inboxView
            self.meRootView = meView
            self.routeView = routeView
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            avatarTask?.cancel()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            configureHierarchy()
            configureTabs()
            apply(theme: appliedTheme)
            updateAvatar(appliedAvatarURL, force: true)
            updateSelectedTab(coordinator.selectedTab)
            accountSwitcher.install()
            accountSwitcher.update(configuration: accountSwitcherConfiguration, theme: appliedTheme)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            // A fresh shell after an account switch: reveal it.
            AccountSwitchTransition.shared.contentDidAppear()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            publishTabBarHeight()
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
            accountSwitcher accountSwitcherConfiguration: AccountSwitcherConfiguration? = nil
        ) {
            self.routeView = routeView
            updateRouteViewBuilders()
            self.accountSwitcherConfiguration = accountSwitcherConfiguration ?? AccountSwitcherConfiguration()
            accountSwitcher.update(configuration: self.accountSwitcherConfiguration, theme: theme)

            if currentContentVersion != contentVersion {
                currentContentVersion = contentVersion
                homeRootView = homeView
                exploreRootView = exploreView
                inboxRootView = inboxView
                meRootView = meView
                homeNavigationController.setRootView(homeView)
                exploreNavigationController.setRootView(exploreView)
                inboxNavigationController.setRootView(inboxView)
                meNavigationController.setRootView(meView)
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

            updateAvatar(currentUserAvatarURL)
            updateSelectedTab(coordinator.selectedTab)
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

        private func configureTabs() {
            configureTabBarItem(homeNavigationController, for: .home)
            configureTabBarItem(exploreNavigationController, for: .explore)
            configureTabBarItem(inboxNavigationController, for: .inbox)
            configureTabBarItem(meNavigationController, for: .me)

            mainTabController.viewControllers = [
                homeNavigationController,
                exploreNavigationController,
                inboxNavigationController,
                meNavigationController,
            ]
            mainTabController.delegate = self
        }

        private func configureTabBarItem(_ controller: UIViewController, for tab: MainTab) {
            // Icon-only: the four destinations are familiar enough that labels are noise.
            // The names stay for VoiceOver and the large content viewer.
            let item = UITabBarItem(
                title: nil,
                image: Self.tabGlyph(tab.icon, configuration: Self.glyphConfiguration),
                selectedImage: Self.tabGlyph(tab.filledIcon, configuration: Self.selectedGlyphConfiguration)
            )
            item.accessibilityLabel = tab.title
            item.accessibilityIdentifier = "mainTab.\(tab.rawValue)"
            item.largeContentSizeImage = UIImage(systemName: tab.icon)
            Self.centerImageWithoutTitle(item)
            controller.tabBarItem = item
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
            guard #unavailable(iOS 26.0) else { return symbol }
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

        /// The classic bar keeps room for a title under the image; with no title, nudge the
        /// (shared-size) images down onto the bar's center line.
        private static func centerImageWithoutTitle(_ item: UITabBarItem) {
            guard #unavailable(iOS 26.0) else { return }
            item.imageInsets = UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
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

            homeNavigationController.apply(theme: theme)
            exploreNavigationController.apply(theme: theme)
            inboxNavigationController.apply(theme: theme)
            meNavigationController.apply(theme: theme)

            applyInboxBadge()

            if loadedAvatarImage != nil {
                applyAvatarImages()
            }
        }

        private func applyInboxBadge() {
            let count = appliedUnreadInboxCount
            let item: UITabBarItem = inboxNavigationController.tabBarItem
            // Unread shows as the bell's own badge layer — a small red dot cut into the
            // glyph — instead of the system's large count bubble. The count stays in the
            // inbox and in the VoiceOver label.
            item.badgeValue = nil
            if count > 0 {
                item.image = Self.badgedGlyph(
                    "bell.badge", configuration: Self.glyphConfiguration,
                    glyph: UIColor(appliedTheme.colors.textSecondary), badge: .systemRed
                )
                item.selectedImage = Self.badgedGlyph(
                    "bell.badge.fill", configuration: Self.selectedGlyphConfiguration,
                    glyph: UIColor(appliedTheme.colors.textPrimary), badge: .systemRed
                )
            } else {
                item.image = Self.tabGlyph(MainTab.inbox.icon, configuration: Self.glyphConfiguration)
                item.selectedImage = Self.tabGlyph(
                    MainTab.inbox.filledIcon, configuration: Self.selectedGlyphConfiguration
                )
            }
            Self.centerImageWithoutTitle(item)
            item.accessibilityLabel = count > 0
                ? MoroL10n.Navigation.inboxUnread(count)
                : MainTab.inbox.title
        }

        private func updateAvatar(_ avatarURL: URL?, force: Bool = false) {
            guard force || appliedAvatarURL != avatarURL else { return }
            appliedAvatarURL = avatarURL
            avatarTask?.cancel()
            loadedAvatarImage = nil
            configureTabBarItem(meNavigationController, for: .me)

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
            meNavigationController.tabBarItem.image = circularAvatarImage(
                image,
                selected: false
            )
            meNavigationController.tabBarItem.selectedImage = circularAvatarImage(
                image,
                selected: true
            )
            Self.centerImageWithoutTitle(meNavigationController.tabBarItem)
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
            let height = mainTabController.tabBar.frame.height
            guard height > 0 else { return }

            let heightChanged = abs(coordinator.tabBarHeight - height) > 0.5
            guard heightChanged else { return }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.coordinator.tabBarHeight = height
            }
        }

        private func updateSelectedTab(_ tab: MainTab) {
            guard let index = tabIndex(for: tab) else { return }
            if mainTabController.selectedIndex != index {
                mainTabController.selectedIndex = index
            }
            applySelectedTabPresentation(tab)
        }

        func tabBarController(
            _ tabBarController: UITabBarController,
            didSelect viewController: UIViewController
        ) {
            guard let tab = tab(for: viewController) else { return }
            coordinator.selectTab(tab)
            applySelectedTabPresentation(tab)
        }

        private func tab(for viewController: UIViewController) -> MainTab? {
            if viewController === homeNavigationController { return .home }
            if viewController === exploreNavigationController { return .explore }
            if viewController === inboxNavigationController { return .inbox }
            if viewController === meNavigationController { return .me }
            return nil
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
                onRootStateChanged: { [weak self] isAtRoot in
                    guard let self else { return }
                    self.coordinator.setIsAtRoot(isAtRoot, for: tab)
                    if self.coordinator.selectedTab == tab {
                        self.updateTabBarVisibility()
                    }
                },
                onSceneChanged: { [weak self] descriptor in
                    guard let self, self.coordinator.selectedTab == tab else { return }
                    self.applyScenePresentation(descriptor)
                }
            )
        }

        private func applySelectedTabPresentation(_ tab: MainTab) {
            guard let navigationController = navigationController(for: tab) else { return }
            updateTabBarVisibility()
            applyScenePresentation(navigationController.currentSceneDescriptor)
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

        private func navigationController(for tab: MainTab) -> MainShellNavigationController? {
            switch tab {
            case .home:
                return homeNavigationController
            case .explore:
                return exploreNavigationController
            case .inbox:
                return inboxNavigationController
            case .me:
                return meNavigationController
            }
        }

        private func updateRouteViewBuilders() {
            let builder: (Route, AppRouter) -> AnyView = { [weak self] route, router in
                self?.routeView(route, router) ?? AnyView(EmptyView())
            }
            homeNavigationController.setRouteView(builder)
            exploreNavigationController.setRouteView(builder)
            inboxNavigationController.setRouteView(builder)
            meNavigationController.setRouteView(builder)
        }

        private func tabIndex(for tab: MainTab) -> Int? {
            MainTab.allCases.firstIndex(of: tab)
        }
    }

    private final class MainShellHostingController: UIHostingController<AnyView> {
        // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
        nonisolated deinit {}

        let sceneDescriptor: MoroSceneDescriptor

        private let contentRootView: AnyView
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
        private var routeView: (Route, AppRouter) -> AnyView
        private let onRootStateChanged: (Bool) -> Void
        private let onSceneChanged: (MoroSceneDescriptor) -> Void
        private let showsNavigationBarAtRoot: Bool
        private let rootSceneDescriptor: MoroSceneDescriptor
        private var appliedTheme: MoroTheme

        init(
            tab: MainTab,
            router: AppRouter,
            rootView: AnyView,
            routeView: @escaping (Route, AppRouter) -> AnyView,
            theme: MoroTheme,
            onRootStateChanged: @escaping (Bool) -> Void,
            onSceneChanged: @escaping (MoroSceneDescriptor) -> Void
        ) {
            self.router = router
            self.routeView = routeView
            self.appliedTheme = theme
            self.onRootStateChanged = onRootStateChanged
            self.onSceneChanged = onSceneChanged
            self.showsNavigationBarAtRoot = tab == .me
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

        func setRouteView(_ routeView: @escaping (Route, AppRouter) -> AnyView) {
            self.routeView = routeView
        }

        func navigate(to route: Route) {
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
