//
//  RootTabCoordinator.swift
//  moro
//
//  Owns the four app-level navigation destinations and their independent route stacks.
//

import Combine
import SwiftUI

enum MainTab: String, Hashable, CaseIterable {
    case home
    case explore
    case inbox
    case me

    var defaultIcon: String {
        switch self {
        case .home: return "house"
        case .explore: return "magnifyingglass"
        case .inbox: return "tray"
        case .me: return "person"
        }
    }

    var defaultFilledIcon: String {
        switch self {
        case .home: return "house.fill"
        case .explore: return "magnifyingglass"
        case .inbox: return "tray.fill"
        case .me: return "person.fill"
        }
    }

    var modernIcon: String {
        switch self {
        case .home: return "rectangle.stack"
        case .explore: return "safari"
        case .inbox: return "tray"
        case .me: return "person.crop.circle"
        }
    }

    var modernFilledIcon: String {
        switch self {
        case .home: return "rectangle.stack.fill"
        case .explore: return "safari.fill"
        case .inbox: return "tray.fill"
        case .me: return "person.crop.circle.fill"
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
        }
    }
}

enum RootSheetDestination: String, Identifiable {
    case settings

    var id: String { rawValue }
}

@MainActor
final class RootTabCoordinator: ObservableObject {
    @Published private(set) var selectedTab: MainTab
    @Published var inboxFilter: NotificationFilter
    @Published var composeContext: ComposeContextWrapper?
    @Published var presentedSheet: RootSheetDestination?
    @Published var showAddAccountLogin = false
    @Published var selectedTabScrollToTop = -1
    @Published var timelineSelection: TimelineType = .home
    @Published var tabBarHeight: CGFloat = 78
    @Published private(set) var isExploreSearchEntryActive = false
    @Published private var rootStateByTab: [MainTab: Bool]

    let homeRouter = AppRouter()
    let exploreRouter = AppRouter()
    let inboxRouter = AppRouter()
    let meRouter = AppRouter()

    init(
        selectedTab: MainTab = .home,
        inboxFilter: NotificationFilter = .all,
        presentedSheet: RootSheetDestination? = nil
    ) {
        self.selectedTab = selectedTab
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
        presentedSheet = nil
        composeContext = ComposeContextWrapper(
            context: .newPost,
            draft: draft,
            sharedImport: sharedImport
        )
    }

    func presentSettings() {
        guard composeContext == nil, !showAddAccountLogin else { return }
        presentedSheet = .settings
    }

    func dismissPresentedSheet() {
        presentedSheet = nil
    }

    func selectTab(_ tab: MainTab) {
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

    func openInbox(_ filter: NotificationFilter) {
        inboxFilter = filter
        if selectedTab != .inbox {
            selectedTab = .inbox
        }
    }

    func openConversation(_ conversation: Conversation) {
        openInbox(.mentions)
        inboxRouter.replace(with: .conversationDetail(conversation))
    }

    func openPushNotification(_ destination: PushNotificationDestination) {
        switch destination {
        case .notifications:
            openInbox(.all)
            inboxRouter.popToRoot()
        case .messages:
            openInbox(.mentions)
            inboxRouter.popToRoot()
        case .status(let status):
            openInbox(.all)
            inboxRouter.replace(with: .statusDetail(status))
        case .profile(let account):
            openInbox(.all)
            inboxRouter.replace(with: .userProfile(account))
        case .conversation(let conversation):
            openConversation(conversation)
        }
    }

    func navigate(to route: Route, on tab: MainTab? = nil) {
        let targetTab = tab ?? selectedTab
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
        for tab in MainTab.allCases {
            router(for: tab).popToRoot()
            setIsAtRoot(true, for: tab)
        }
    }

    private func triggerScrollToTopEvent(for tab: MainTab) {
        selectedTabScrollToTop = -1

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.selectedTabScrollToTop = tab.hashValue

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                if self.selectedTabScrollToTop == tab.hashValue {
                    self.selectedTabScrollToTop = -1
                }
            }
        }
    }
}
