//
//  RootTabCoordinator.swift
//  moro
//
//  Owns app-level navigation destinations and their independent route stacks.
//

import Combine
import SwiftUI

enum MainTab: String, Hashable, CaseIterable {
    case home
    case explore
    case inbox
    case me
    case lists
    case bookmarks
    case favourites
    case settings

    var isRequired: Bool {
        NavigationTabLayout.requiredTabs.contains(self)
    }

    var defaultIcon: String {
        switch self {
        case .home: return "house"
        case .explore: return "magnifyingglass"
        case .inbox: return "bell"
        case .me: return "person"
        case .lists: return "list.bullet"
        case .bookmarks: return "bookmark"
        case .favourites: return "heart"
        case .settings: return "gearshape"
        }
    }

    var defaultFilledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "magnifyingglass"
        case .inbox: return "bell.fill"
        case .me: return "person.fill"
        case .lists: return defaultIcon
        case .bookmarks: return "bookmark.fill"
        case .favourites: return "heart.fill"
        case .settings: return "gearshape.fill"
        }
    }

    var modernIcon: String {
        switch self {
        case .home: return "rectangle.stack"
        case .explore: return "safari"
        case .inbox: return "bell"
        case .me: return "person.crop.circle"
        case .lists, .bookmarks, .favourites, .settings: return defaultIcon
        }
    }

    var modernFilledIcon: String {
        switch self {
        case .home: return "rectangle.stack.fill"
        case .explore: return "safari.fill"
        case .inbox: return "bell.fill"
        case .me: return "person.crop.circle.fill"
        case .lists, .bookmarks, .favourites, .settings: return defaultFilledIcon
        }
    }

    var icon: String { defaultIcon }
    var filledIcon: String { defaultFilledIcon }

    func icon(for theme: AppSettings.TabIconTheme) -> String {
        theme.icon(for: self)
    }

    func filledIcon(for theme: AppSettings.TabIconTheme) -> String {
        theme.filledIcon(for: self)
    }

    var title: String {
        switch self {
        case .home: return MoroL10n.Navigation.home
        case .explore: return MoroL10n.Navigation.explore
        case .inbox: return MoroL10n.Navigation.inbox
        case .me: return MoroL10n.Navigation.me
        case .lists: return MoroL10n.Navigation.lists
        case .bookmarks: return MoroL10n.Navigation.bookmarks
        case .favourites: return MoroL10n.Navigation.favourites
        case .settings: return MoroL10n.Navigation.settings
        }
    }
}

enum RootSheetDestination: Equatable, Identifiable {
    case settings
    case navigationCustomization
    case search(autoFocus: Bool)

    var id: String {
        switch self {
        case .settings:
            return "settings"
        case .navigationCustomization:
            return "navigationCustomization"
        case .search(let autoFocus):
            return "search.\(autoFocus)"
        }
    }
}

@MainActor
final class RootTabCoordinator: ObservableObject {
    @Published private(set) var selectedTab: MainTab {
        didSet {
            if oldValue != selectedTab { noteTabActivated(selectedTab) }
        }
    }
    @Published private(set) var tabLayout: NavigationTabLayout
    @Published var inboxFilter: NotificationFilter
    @Published var composeContext: ComposeContextWrapper?
    @Published var presentedSheet: RootSheetDestination?
    @Published var showAddAccountLogin = false
    /// The Me tab's account switcher is up; floating controls make room for it.
    @Published var isAccountSwitcherPresented = false
    /// Moro's leading navigation drawer overlay state.
    @Published var isDrawerPresented = false
    /// Live `0...1` progress while the user drags from the leading screen edge.
    @Published var drawerInteractiveProgress: CGFloat? = nil
    @Published private(set) var tabReselection: TabReselection?
    /// The latest time a root tab came on screen: switched to, or the app came back to it.
    @Published private(set) var tabActivation: TabActivation?
    @Published var timelineSelection: TimelineType = .home
    @Published var tabBarHeight: CGFloat = 78
    /// The device has a hinge (iPhone Duo): the home timeline moves its header controls into the
    /// system navigation bar, so they follow the bars into the vertical side bar and share the
    /// status row on the inner display. Other iPhones keep the custom hide-on-scroll header.
    @Published var usesSystemHomeBar = false
    @Published private(set) var isExploreSearchEntryActive = false
    @Published private(set) var homeShowsInbox = false
    @Published private var rootStateByTab: [MainTab: Bool]

    private let tabPreferences: NavigationTabPreferences?
    let homeRouter = AppRouter()
    let exploreRouter = AppRouter()
    let inboxRouter = AppRouter()
    let meRouter = AppRouter()
    private var additionalRouters: [MainTab: AppRouter] = [:]

    init(
        selectedTab: MainTab = .home,
        inboxFilter: NotificationFilter = .all,
        presentedSheet: RootSheetDestination? = nil,
        tabPreferences: NavigationTabPreferences? = nil
    ) {
        let layout = tabPreferences?.load() ?? NavigationTabLayout()
        self.tabPreferences = tabPreferences
        self.tabLayout = layout
        self.selectedTab = layout.tabs.contains(selectedTab) ? selectedTab : .home
        self.inboxFilter = inboxFilter
        self.presentedSheet = presentedSheet
        self.rootStateByTab = Dictionary(
            uniqueKeysWithValues: MainTab.allCases.map { ($0, true) }
        )
    }

    // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
    nonisolated deinit {}

    func openCompose(
        draft: ComposeDraft? = nil,
        sharedImport: SharedComposeAttachmentImportPayload? = nil
    ) {
        isDrawerPresented = false
        drawerInteractiveProgress = nil
        presentedSheet = nil
        composeContext = ComposeContextWrapper(
            context: .newPost,
            draft: draft,
            sharedImport: sharedImport
        )
    }

    var canOpenDrawerByEdgeSwipe: Bool {
        selectedTab == .home
            && isAtRoot(.home)
            && !isDrawerPresented
            && presentedSheet == nil
            && composeContext == nil
            && !showAddAccountLogin
            && !isAccountSwitcherPresented
            && !usesSystemHomeBar
    }

    func openDrawer() {
        guard composeContext == nil, !showAddAccountLogin, presentedSheet == nil else { return }
        drawerInteractiveProgress = nil
        isDrawerPresented = true
    }

    func closeDrawer() {
        drawerInteractiveProgress = nil
        isDrawerPresented = false
    }

    func updateDrawerEdgeGesture(progress: CGFloat) {
        drawerInteractiveProgress = min(max(progress, 0), 1)
    }

    func finishDrawerEdgeGesture(shouldOpen: Bool) {
        drawerInteractiveProgress = nil
        isDrawerPresented = shouldOpen
    }

    func openTabOrRoute(_ tab: MainTab, account: Account?) {
        closeDrawer()
        switch tab {
        case .home:
            selectTab(.home)
        case .explore:
            openExplore()
        case .inbox:
            openInbox(.all)
        case .me:
            openProfile(account)
        case .lists:
            if tabLayout.tabs.contains(.lists) {
                selectTab(.lists)
            } else {
                navigate(to: .lists, on: .home)
            }
        case .bookmarks:
            if tabLayout.tabs.contains(.bookmarks) {
                selectTab(.bookmarks)
            } else {
                navigate(to: .bookmarks, on: .home)
            }
        case .favourites:
            if tabLayout.tabs.contains(.favourites) {
                selectTab(.favourites)
            } else {
                navigate(to: .favourites, on: .home)
            }
        case .settings:
            if tabLayout.tabs.contains(.settings) {
                selectTab(.settings)
            } else {
                presentSettings()
            }
        }
    }

    func openRouteFromDrawer(_ route: Route) {
        closeDrawer()
        navigate(to: route, on: .home)
    }

    @discardableResult
    func presentPendingSharedImport(
        using importer: SharedComposeImportCoordinator, accountID: String?
    ) -> SharedComposeImportResolution? {
        guard composeContext == nil, presentedSheet == nil, !showAddAccountLogin,
              !SharedComposeHandoff.shared.hasPresentedEditor,
              let resolution = importer.consumeNextImportableDraft(activeAccountID: accountID) else { return nil }
        composeContext = ComposeContextWrapper(context: resolution.draft.target.composeContext,
            draft: resolution.draft, sharedImport: resolution.sharedImport)
        return resolution
    }

    func presentSettings() {
        guard composeContext == nil, !showAddAccountLogin else { return }
        closeDrawer()
        if tabLayout.tabs.contains(.settings) {
            selectTab(.settings)
        } else {
            presentedSheet = .settings
        }
    }

    func presentNavigationCustomization() {
        guard composeContext == nil, !showAddAccountLogin else { return }
        closeDrawer()
        guard presentedSheet == nil else { return }
        presentedSheet = .navigationCustomization
    }

    func toggleTab(_ tab: MainTab) {
        var layout = tabLayout
        layout.toggle(tab)
        applyTabLayout(layout)
    }

    func moveTab(_ tab: MainTab, to index: Int) {
        applyTabLayout(tabLayout.moving(tab, to: index))
    }

    func restoreDefaultTabLayout() {
        applyTabLayout(NavigationTabLayout())
    }

    private func applyTabLayout(_ layout: NavigationTabLayout) {
        guard layout != tabLayout else { return }
        if !layout.tabs.contains(selectedTab) { selectedTab = .home }
        tabLayout = layout
        tabPreferences?.save(layout)
    }

    /// Work that must wait until the root sheet has finished dismissing (switching
    /// accounts, pushing onto the now-visible stack). Run from the sheet's `onDismiss`
    /// instead of guessing the animation length with a timer.
    private var actionsAfterSheetDismiss: [() -> Void] = []

    func dismissPresentedSheet(then action: (() -> Void)? = nil) {
        if let action { actionsAfterSheetDismiss.append(action) }
        if presentedSheet == nil {
            runActionsAfterSheetDismiss()
        } else {
            presentedSheet = nil
        }
    }

    func runActionsAfterSheetDismiss() {
        let actions = actionsAfterSheetDismiss
        actionsAfterSheetDismiss = []
        actions.forEach { $0() }
    }

    func selectTab(_ tab: MainTab) {
        closeDrawer()
        guard tabLayout.tabs.contains(tab) else { return }
        guard tab == selectedTab else {
            selectedTab = tab
            return
        }

        if !isAtRoot(tab) {
            router(for: tab).popToRoot()
            return
        }

        triggerScrollToTopEvent(for: tab)
    }

    func openExplore(autoFocus: Bool = false) {
        closeDrawer()
        if tabLayout.tabs.contains(.explore) {
            selectTab(.explore)
        } else {
            guard composeContext == nil, !showAddAccountLogin else { return }
            presentedSheet = .search(autoFocus: autoFocus)
        }
    }

    func openProfile(_ account: Account?) {
        closeDrawer()
        if tabLayout.tabs.contains(.me) {
            selectTab(.me)
        } else if let account {
            navigate(to: .userProfile(account), on: .home)
        }
    }

    var isInboxVisible: Bool {
        (selectedTab == .inbox && isAtRoot(.inbox)) || (selectedTab == .home && homeShowsInbox)
    }

    func setHomeShowsInbox(_ visible: Bool) {
        if homeShowsInbox != visible { homeShowsInbox = visible }
    }

    func openInbox(_ filter: NotificationFilter) {
        closeDrawer()
        inboxFilter = filter
        let target: MainTab = tabLayout.tabs.contains(.inbox) ? .inbox : .home
        if selectedTab != target { selectedTab = target }
        if target == .home && !homeShowsInbox {
            homeRouter.navigate(to: .inbox)
            setHomeShowsInbox(true)
        }
    }

    func openConversation(_ conversation: Conversation) {
        openPushNotification(.conversation(conversation))
    }

    func openPushNotification(_ destination: PushNotificationDestination) {
        let (filter, detail): (NotificationFilter, Route?) = switch destination {
        case .notifications: (.all, nil)
        case .messages: (.mentions, nil)
        case .status(let status): (.all, .statusDetail(status))
        case .profile(let account): (.all, .userProfile(account))
        case .conversation(let conversation): (.mentions, .conversationDetail(conversation))
        }
        openInbox(filter)
        if selectedTab == .inbox {
            if let detail { inboxRouter.replace(with: detail) } else { inboxRouter.popToRoot() }
        } else if let detail {
            homeRouter.navigate(to: detail)
            setHomeShowsInbox(false)
        }
    }

    func navigate(to route: Route, on tab: MainTab? = nil) {
        let targetTab = tab.flatMap { tabLayout.tabs.contains($0) ? $0 : nil } ?? selectedTab
        let router = router(for: targetTab)
        if selectedTab != targetTab {
            selectedTab = targetTab
        }
        router.navigate(to: route)
    }

    func router(for tab: MainTab) -> AppRouter {
        switch tab {
        case .home:
            return homeRouter
        case .explore:
            return exploreRouter
        case .inbox:
            return inboxRouter
        case .me:
            return meRouter
        case .lists, .bookmarks, .favourites, .settings:
            if let router = additionalRouters[tab] { return router }
            let router = AppRouter()
            additionalRouters[tab] = router
            return router
        }
    }

    func setIsAtRoot(_ isAtRoot: Bool, for tab: MainTab) {
        guard rootStateByTab[tab] != isAtRoot else { return }
        rootStateByTab[tab] = isAtRoot
    }

    func isAtRoot(_ tab: MainTab) -> Bool {
        return rootStateByTab[tab] ?? true
    }

    var isCurrentTabAtRoot: Bool {
        isAtRoot(selectedTab)
    }

    var isTabBarHidden: Bool {
        !isCurrentTabAtRoot || (selectedTab == .explore && isExploreSearchEntryActive)
    }

    func setExploreSearchEntryActive(_ active: Bool) {
        guard isExploreSearchEntryActive != active else { return }
        isExploreSearchEntryActive = active
    }

    func popAllToRoot() {
        for tab in NavigationTabLayout.defaultTabs + Array(additionalRouters.keys) {
            router(for: tab).popToRoot()
            setIsAtRoot(true, for: tab)
        }
    }

    /// The app came back to the foreground showing the selected tab.
    func noteAppBecameActive() {
        noteTabActivated(selectedTab)
    }

    private func noteTabActivated(_ tab: MainTab) {
        tabActivation = TabActivation(tab: tab, sequence: (tabActivation?.sequence ?? 0) + 1)
    }

    private func triggerScrollToTopEvent(for tab: MainTab) {
        tabReselection = TabReselection(tab: tab, sequence: (tabReselection?.sequence ?? 0) + 1)
    }
}
