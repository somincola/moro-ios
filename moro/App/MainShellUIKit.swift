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
            routeView: routeView
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
            routeView: routeView
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
            routeView: @escaping (Route, AppRouter) -> AnyView
        ) {
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
            applyInboxBadge()
            updateAvatar(appliedAvatarURL, force: true)
            updateSelectedTab(coordinator.selectedTab)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            publishTabBarHeight()
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
            routeView: @escaping (Route, AppRouter) -> AnyView
        ) {
            self.routeView = routeView
            updateRouteViewBuilders()

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
                || appliedTheme.accent != theme.accent
                || appliedTheme.fontScale != theme.fontScale
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
            let normalConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            let selectedConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)
            controller.tabBarItem = UITabBarItem(
                title: tab.title,
                image: UIImage(systemName: tab.icon, withConfiguration: normalConfiguration),
                selectedImage: UIImage(systemName: tab.filledIcon, withConfiguration: selectedConfiguration)
            )
            controller.tabBarItem.accessibilityLabel = tab.title
            controller.tabBarItem.accessibilityIdentifier = "mainTab.\(tab.rawValue)"
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

            if loadedAvatarImage != nil {
                applyAvatarImages()
            }
        }

        private func applyInboxBadge() {
            let count = appliedUnreadInboxCount
            inboxNavigationController.tabBarItem.badgeValue = count == 0
                ? nil
                : (count > 99 ? "99+" : "\(count)")
            inboxNavigationController.tabBarItem.badgeColor = .systemRed
            inboxNavigationController.tabBarItem.accessibilityLabel = count > 0
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
        }

        private func circularAvatarImage(_ image: UIImage, selected: Bool) -> UIImage {
            let outputSize = CGSize(width: 25, height: 25)
            let format = UIGraphicsImageRendererFormat.preferred()
            format.opaque = false
            let renderer = UIGraphicsImageRenderer(size: outputSize, format: format)

            return renderer.image { context in
                let inset: CGFloat = 1.5
                let targetRect = CGRect(origin: .zero, size: outputSize).insetBy(dx: inset, dy: inset)
                context.cgContext.saveGState()
                context.cgContext.addEllipse(in: targetRect)
                context.cgContext.clip()

                let scale = max(targetRect.width / image.size.width, targetRect.height / image.size.height)
                let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let drawRect = CGRect(
                    x: targetRect.midX - drawSize.width / 2,
                    y: targetRect.midY - drawSize.height / 2,
                    width: drawSize.width,
                    height: drawSize.height
                )
                image.draw(in: drawRect)
                context.cgContext.restoreGState()

                let ringColor = selected
                    ? UIColor(appliedTheme.colors.textPrimary)
                    : UIColor(appliedTheme.colors.borderSubtle)
                ringColor.setStroke()
                let ring = UIBezierPath(ovalIn: targetRect)
                ring.lineWidth = selected ? 2 : 1
                ring.stroke()
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
                        self.mainTabController.tabBar.isHidden = !isAtRoot
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
            mainTabController.tabBar.isHidden = !coordinator.isAtRoot(tab)
            applyScenePresentation(navigationController.currentSceneDescriptor)
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
                || appliedTheme.accent != theme.accent
                || appliedTheme.fontScale != theme.fontScale
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
