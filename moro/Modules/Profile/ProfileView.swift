//
//  ProfileView.swift
//  moro
//
//  User profile view with posts, replies, and media tabs.
//

import SwiftUI

// MARK: - Profile View

private struct ProfileStatButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ProfileView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.moroSceneDescriptor) private var sceneDescriptor
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var bioLineSpacing: CGFloat = 2
    @ScaledMetric(relativeTo: .subheadline) private var bioParagraphSpacing: CGFloat = 6
    @Environment(\.cacheManager) private var cacheManager
    @Environment(\.appRouter) private var router
    @Environment(\.activeAccountKey) private var activeAccountKey
    @StateObject private var profilePreferences = ProfilePresentationPreferences.shared
    @Environment(\.settingsPresentationAction) private var presentSettings
    @EnvironmentObject private var appState: AppState

    @StateObject private var viewModel: ProfileViewModel

    let account: Account?
    let accountID: String?
    let onLogout: () -> Void
    private let apiClient: MastodonAPI
    @StateObject private var postMenuActionCenter: PostMenuActionCenter

    @State private var chromeState = ProfileChromeState()
    /// The Me tab's own profile refreshes quietly on coming back to it once older than five
    /// minutes (pushed profiles never get tab activations).
    @State private var autoRefresh = AutoRefreshSchedule(ttl: 5 * 60)
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var actionPresentation = ProfileActionPresentationState()
    @StateObject private var actionSurface = PostActionSurfaceCenter()

    @StateObject private var interactionService: PostInteractionService
    private let pullRefreshVisualThreshold: CGFloat = 72
    private let refreshFeedbackMinimumDuration: TimeInterval = 0.85
    private let pullRefreshIndicatorSize: CGFloat = 34
    // Used only before the native navigation bar has completed its first layout.
    @State private var navigationBarHeight: CGFloat = 44
    /// The native bar's bottom edge in window coordinates, once measured.
    @State private var navigationBarBottom: CGFloat?
    /// iPhone Duo with the bar in the vertical side bar: the page draws its own title band.
    @State private var navigationBarIsVertical = false

    private var profileChromeProgress: CGFloat {
        chromeState.headerProgress(
            bannerHeight: profileBannerBaseHeight,
            navigationBarHeight: navigationBarHeight
        )
    }

    /// The bar reads as solid once the collapsing chrome is mostly opaque.
    private var isNavigationChromeSolid: Bool { profileChromeProgress >= 0.55 }

    /// Bar controls: white over the banner, the theme's text color on the solid bar.
    /// Set explicitly because iOS 18 keeps the shell's white tint (invisible on a light
    /// bar) and resolves a plain menu label to the system accent in dark mode.
    private var navigationForeground: Color {
        isNavigationChromeSolid ? theme.colors.textPrimary : .white
    }

    private var navChromeVisible: Bool {
        profileChromeProgress >= 1
    }

    // Check if this is the current user's profile
    private var isCurrentUser: Bool {
        guard let currentAccountID = appState.currentAccount?.id,
            let profileAccountID = viewModel.account?.id ?? account?.id ?? accountID
        else {
            return false
        }
        return currentAccountID == profileAccountID
    }

    init(
        account: Account?,
        accountID: String? = nil,
        onLogout: @escaping () -> Void,
        apiClient: MastodonAPI
    ) {
        self.account = account
        self.accountID = accountID
        self.onLogout = onLogout

        let resolvedAccountID = accountID ?? account?.id ?? ""
        // Required: a fallback client built here had no token, so every request on the
        // page failed silently.
        let resolvedClient = apiClient

        self.apiClient = resolvedClient
        _postMenuActionCenter = StateObject(
            wrappedValue: PostMenuActionCenter(apiClient: resolvedClient))

        _viewModel = StateObject(
            wrappedValue: ProfileViewModel(apiClient: resolvedClient, accountID: resolvedAccountID))
        _interactionService = StateObject(
            wrappedValue: PostInteractionService(apiClient: resolvedClient))
    }

    var body: some View {
        GeometryReader { geometry in
            let topSafeInset = resolvedTopSafeInset(geometry.safeAreaInsets.top)
            let topChromeHeight = navigationChromeHeight(topSafeInset: topSafeInset)
            let chromeLayout = chromeState.layout(
                viewportHeight: geometry.size.height,
                topChromeHeight: topChromeHeight
            )

            ZStack(alignment: .top) {
                sceneCanvasColor
                    .ignoresSafeArea()

                profileHeaderBackground(
                    topSafeInset: topSafeInset,
                    scrollOffset: chromeState.scrollOffset,
                    pullDistance: chromeState.pullDistance
                )
                .allowsHitTesting(false)
                // The cover runs to the display edges, under a landscape notch or iPhone Duo's
                // vertical side bar, instead of stopping beside them.
                .ignoresSafeArea(.container, edges: .horizontal)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        profileHeaderRow(topSafeInset: topSafeInset)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ProfileHeaderHeightKey.self,
                                        value: proxy.size.height
                                    )
                                }
                            )

                        naturalTabBarSection(isHidden: chromeLayout.hidesNaturalTab)
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: ProfileTabBarHeightKey.self,
                                        value: proxy.size.height
                                    )
                                }
                            )

                        ProfileContentStream(
                            viewModel: viewModel,
                            apiClient: apiClient,
                            postActions: postActions
                        )
                            .equatable()
                            .moroReadableColumn()
                            .frame(minHeight: chromeLayout.pinnedContentHeight, alignment: .top)
                            .background(theme.colors.surfaceBase)
                    }
                }
                .scrollPosition($scrollPosition)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.always, axes: .vertical)
                .ignoresSafeArea(.container, edges: .top)
                .background(Color.clear)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, scrolled in
                    updateScrollState(scrolled)
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    if chromeState.didReleasePull(oldPhase: oldPhase, newPhase: newPhase) {
                        startPullRefreshIfNeeded()
                    }
                }
                .onPreferenceChange(ProfileHeaderHeightKey.self) { height in
                    chromeState.updateHeaderHeight(height)
                }
                .onPreferenceChange(ProfileTabBarHeightKey.self) { height in
                    chromeState.updateTabBarHeight(height)
                }

                profileNavigationChromeBackground(
                    topChromeHeight: topChromeHeight,
                    progress: profileChromeProgress
                )
                .ignoresSafeArea(.container, edges: .horizontal)
                .zIndex(1)

                if let tabOverlayOffset = chromeLayout.tabOverlayOffset {
                    tabBarSection(
                        hidesAccessibility: false
                    )
                        .offset(y: tabOverlayOffset)
                        .zIndex(2)
                }

                profilePullRefreshIndicator(topChromeHeight: topChromeHeight)
                    .zIndex(3)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(sceneCanvasColor)
        .background {
            ProfileNavigationBarHeightReader(tint: UIColor(navigationForeground)) { metrics in
                navigationBarHeight = metrics.height
                navigationBarBottom = metrics.bottom
                navigationBarIsVertical = metrics.isVertical
            }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // With the bar in the vertical side bar the system floats the title at the top leading
        // corner; the page's own band already shows the name, so the system title stays empty.
        .navigationTitle(navChromeVisible && !navigationBarIsVertical ? collapsedTitle : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(
            isNavigationChromeSolid ? colorScheme : .dark,
            for: .navigationBar
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                profileNavigationAction
            }
        }
        .task {
            // Update currentAccountID in viewModel
            viewModel.currentAccountID = appState.currentAccount?.id
            await viewModel.setFeaturedTagsEnabled(profilePreferences.showsFeaturedTags(accountKey: activeAccountKey))
            await viewModel.loadInitial()
            autoRefresh.recordSuccess()
            await viewModel.loadFeaturedTags()
            syncCurrentUserProfileFromAppState()
        }
        .onChange(of: viewModel.selectedTab) { _, tab in
            Task { await viewModel.loadTabIfNeeded(tab) }
        }
        .onChange(of: viewModel.mediaPreferenceRevision) { _, _ in
            if viewModel.selectedTab == .media { Task { await viewModel.loadTabIfNeeded(.media) } }
        }
        .onChange(of: profilePreferences.revision) { _, _ in
            Task {
                await viewModel.setFeaturedTagsEnabled(profilePreferences.showsFeaturedTags(accountKey: activeAccountKey))
                await viewModel.loadFeaturedTags()
            }
        }
        .onChange(of: currentAccountSyncKey) { _, _ in
            syncCurrentUserProfileFromAppState()
        }
        .onTabActivate(.me) { refreshIfStale() }
        // Only the Me tab's root profile receives re-tap events (pushed profiles don't).
        .onTabReselect(.me) {
            if chromeState.scrollOffset > 1 {
                withAnimation(.snappy) { scrollPosition.scrollTo(edge: .top) }
            } else if chromeState.beginRefresh() {
                MoroRefreshFeedback.armed()
                runRefresh()
            }
        }
        .profileActionPresentations(
            presentation: $actionPresentation,
            actionSurface: actionSurface,
            interactionService: interactionService,
            viewModel: viewModel,
            appState: appState,
            fallbackAccount: account,
            apiClient: apiClient,
            refreshProfile: refreshProfileData,
            performDelete: performDelete
        )
    }

    private var sceneCanvasColor: Color {
        (sceneDescriptor?.canvas ?? .hero).backgroundColor(in: theme)
    }

    private var currentAccountSyncKey: String {
        guard let current = appState.currentAccount else { return "none" }
        let fieldsDigest = current.fields.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
        return [
            current.id,
            current.displayName,
            current.note,
            current.avatar,
            current.avatarStatic,
            current.header,
            current.headerStatic,
            fieldsDigest,
            String(describing: current.showMedia),
            String(describing: current.showMediaReplies),
            String(describing: current.showFeatured),
            String(describing: current.credentialHideCollections),
        ].joined(separator: "|")
    }

    private func syncCurrentUserProfileFromAppState() {
        guard let current = appState.currentAccount else { return }
        let profileAccountID = viewModel.account?.id ?? account?.id ?? accountID
        guard current.id == profileAccountID else { return }

        viewModel.account = current
        cacheManager.accountCache.set(current)
    }

    private func refreshProfileData() async {
        _ = await refreshProfileDataReportingResult()
    }

    private func refreshProfileDataReportingResult() async -> Bool {
        let succeeded = await viewModel.refresh()
        syncAppStateFromCurrentProfileIfNeeded()
        return succeeded
    }

    private func updateScrollState(_ scrolled: CGFloat) {
        let didArm = chromeState.updateScroll(
            scrolled,
            pullRefreshThreshold: pullRefreshVisualThreshold
        )
        if didArm {
            MoroRefreshFeedback.armed(.light)
        }
    }

    private func startPullRefreshIfNeeded() {
        guard chromeState.beginRefreshIfArmed() else { return }
        MoroRefreshFeedback.armed()
        runRefresh()
    }

    /// Shared by pull and tab re-tap: same result feedback as Home, then the spinner stays
    /// up for at least `refreshFeedbackMinimumDuration` so a fast answer doesn't flicker.
    private func runRefresh() {
        Task { @MainActor in
            let started = Date()
            let succeeded = await refreshProfileDataReportingResult()
            MoroRefreshFeedback.deliver(succeeded ? .succeeded : .failed)
            if succeeded {
                autoRefresh.recordSuccess()
            } else {
                autoRefresh.recordFailure(automatic: false)
            }

            let remaining = refreshFeedbackMinimumDuration - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            chromeState.finishRefresh()
        }
    }

    /// Automatic and silent: no spinner, no haptics, and only at the top, so the posts
    /// being read never move.
    private func refreshIfStale() {
        guard chromeState.scrollOffset <= 1, !chromeState.isRefreshing,
            autoRefresh.shouldRefresh(isOffline: NetworkMonitor.shared.isOffline)
        else { return }
        Task { @MainActor in
            if await refreshProfileDataReportingResult() {
                autoRefresh.recordSuccess()
            } else {
                autoRefresh.recordFailure(automatic: true)
            }
        }
    }

    private func syncAppStateFromCurrentProfileIfNeeded() {
        guard let refreshed = viewModel.account else { return }
        guard refreshed.id == appState.currentAccount?.id else { return }

        appState.currentAccount = refreshed
        cacheManager.accountCache.set(refreshed)
    }

    @ViewBuilder
    private var profileNavigationAction: some View {
        if isCurrentUser {
            ProfileMoreButton(
                account: viewModel.account ?? account,
                relationship: nil,
                iconColor: navigationForeground,
                onShare: shareUser,
                onSettings: presentSettings,
                onBookmarks: { router.navigate(to: .bookmarks) },
                onFavourites: { router.navigate(to: .favourites) },
                onCopyLink: copyUserLink,
                onOpenInBrowser: openUserInBrowser
            )
        } else if !isCurrentUser {
            profileMoreButton
        }
    }

    // MARK: - Profile Tabs

    private func resolvedTopSafeInset(_ geometryTopSafeInset: CGFloat) -> CGFloat {
        max(geometryTopSafeInset, Self.activeKeyWindow?.safeAreaInsets.top ?? 0)
    }

    /// Where the solid bar background, its hairline and the pinned tabs end: the native bar's
    /// measured bottom. Safe area + bar height is only the first-layout fallback; on Dynamic
    /// Island iPhones the bar starts above the safe-area top, so that sum left a strip below
    /// the real bar (about 6 pt on iPhone 16 Pro).
    private func navigationChromeHeight(topSafeInset: CGFloat) -> CGFloat {
        navigationBarBottom ?? (topSafeInset + navigationBarHeight)
    }

    @ViewBuilder
    private func profileNavigationChromeBackground(
        topChromeHeight: CGFloat,
        progress: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            theme.colors.surfaceBase
                .frame(height: topChromeHeight)
                .overlay(alignment: .bottom) {
                    // The collapsed name goes in the band (the system title is left empty).
                    if navigationBarIsVertical {
                        Text(collapsedTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(theme.colors.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, theme.spacing.contentHorizontalInset)
                            .frame(height: navigationBarHeight)
                            .opacity(navChromeVisible ? 1 : 0)
                            .animation(.easeOut(duration: 0.15), value: navChromeVisible)
                    }
                }

            Rectangle()
                .fill(theme.colors.borderSubtle)
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity)
        .opacity(progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var collapsedTitle: String {
        viewModel.account?.displayName ?? account?.displayName ?? MoroL10n.Profile.navTitle
    }

    private static var activeKeyWindow: UIWindow? {
        UIApplication.shared.moroActiveKeyWindow
    }

    @ViewBuilder
    private func profilePullRefreshIndicator(topChromeHeight: CGFloat) -> some View {
        let progress = chromeState.pullProgress(threshold: pullRefreshVisualThreshold)
        let indicatorTop = max(
            0,
            topChromeHeight - navigationBarHeight
                + (navigationBarHeight - pullRefreshIndicatorSize) / 2
        )

        if chromeState.pullDistance > 6 || chromeState.isRefreshing {
            MoroPetalSpinner(
                progress: chromeState.isRefreshing ? 1 : progress,
                isAnimating: chromeState.isRefreshing,
                style: .profile,
                tint: .fading(.white)
            )
                .frame(width: pullRefreshIndicatorSize, height: pullRefreshIndicatorSize)
                .background(.black.opacity(0.12), in: Circle())
                .padding(.top, indicatorTop)
                .opacity(chromeState.isRefreshing ? 1 : max(0.35, progress))
                .transition(.opacity)
                .accessibilityLabel(MoroL10n.Timeline.refreshing)
                .animation(.easeOut(duration: 0.16), value: chromeState.isRefreshing)
        }
    }

    @ViewBuilder
    private func naturalTabBarSection(
        isHidden: Bool
    ) -> some View {
        if isHidden {
            tabBarSection(
                hidesAccessibility: true
            )
            .hidden()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            tabBarSection(
                hidesAccessibility: false
            )
        }
    }

    @ViewBuilder
    private func tabBarSection(
        hidesAccessibility: Bool
    ) -> some View {
        VStack(spacing: 0) {
            tabBar(hidesAccessibility: hidesAccessibility)
            if viewModel.showsFeaturedTags {
                ProfileFeaturedTagBar(tags: viewModel.featuredTags, selection: viewModel.selectedFeaturedTag) { tag in
                    Task { await viewModel.selectFeaturedTag(tag) }
                }
                .accessibilityHidden(hidesAccessibility)
            }
            MoroDivider()
        }
        .moroReadableColumn()
        .background(theme.colors.surfaceBase)
    }

    @ViewBuilder
    private var profileMoreButton: some View {
        ProfileMoreButton(
            account: viewModel.account ?? account,
            relationship: viewModel.relationship,
            iconColor: navigationForeground,
            onShare: shareUser,
            onCopyLink: copyUserLink,
            onOpenInBrowser: openUserInBrowser,
            onAddToList: addCurrentProfileToList,
            onMute: requestMuteToggle,
            onBlock: requestBlockToggle,
            onReport: reportCurrentProfile
        )
    }

    private func addCurrentProfileToList() {
        guard viewModel.relationship?.following == true else {
            AppFeedbackCenter.shared.showInfo(MoroL10n.AddToList.followRequired)
            return
        }
        guard let targetAccount = viewModel.account ?? account else { return }
        actionPresentation.addToListAccount = targetAccount
    }

    private func requestMuteToggle() {
        let isMuting = viewModel.relationship?.muting != true
        if AppSettings.shared.askBeforeMutingAUser && isMuting {
            actionPresentation.pendingAction = toggleMute
            actionPresentation.showMuteConfirmation = true
        } else {
            toggleMute()
        }
    }

    private func requestBlockToggle() {
        let isBlocking = viewModel.relationship?.blocking != true
        if AppSettings.shared.askBeforeBlockingAUser && isBlocking {
            actionPresentation.pendingAction = toggleBlock
            actionPresentation.showBlockConfirmation = true
        } else {
            toggleBlock()
        }
    }

    private func reportCurrentProfile() {
        guard let targetAccount = viewModel.account ?? account else { return }
        guard targetAccount.id != appState.currentAccount?.id else { return }
        actionPresentation.reportAccount = targetAccount
    }

    private func shareUser() {
        guard let url = profileURL else { return }

        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        // Present from the top of the window the person is using: the first connected
        // scene may be another Moro window on iPhone Duo, and the root controller may
        // already be presenting a sheet.
        UIApplication.shared.moroTopViewController()?.present(activityVC, animated: true)
    }

    private func copyUserLink() {
        guard let url = profileURL else { return }
        UIPasteboard.general.url = url
        AppFeedbackCenter.shared.showSuccess(MoroL10n.Profile.linkCopied)
    }

    private func openUserInBrowser() {
        guard let url = profileURL else { return }
        UIApplication.shared.open(url)
    }

    private var profileURL: URL? {
        guard let account = viewModel.account ?? account else { return nil }

        if let urlString = account.url, let url = URL(string: urlString) {
            return url
        }

        let domain = account.acct.split(separator: "@").last.map(String.init) ?? ""
        guard !domain.isEmpty else { return nil }
        return URL(string: "https://\(domain)/@\(account.username)")
    }

    // MARK: - Profile Header

    @ViewBuilder
    private func profileHeaderRow(topSafeInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(height: profileBannerBaseHeight + topSafeInset)

            if let acc = viewModel.account ?? account {
                VStack(alignment: .leading, spacing: 0) {
                    avatarAndActionsRow

                    profileContent

                    statsSection(account: acc)
                }
                .moroReadableColumn()
                .background(theme.colors.surfaceBase)

                VStack(alignment: .leading, spacing: 0) {
                    profileBioSection(account: acc)

                    profileInfoSection(account: acc)
                }
                .moroReadableColumn()
                .background(theme.colors.surfaceBase)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    avatarAndActionsRow
                    profileContent
                }
                .moroReadableColumn()
                .background(theme.colors.surfaceBase)
            }
        }
    }

    // MARK: - Profile Header Background

    private let profileBannerBaseHeight: CGFloat = 180

    @ViewBuilder
    private func profileHeaderBackground(
        topSafeInset: CGFloat,
        scrollOffset: CGFloat,
        pullDistance: CGFloat
    ) -> some View {
        let acc = viewModel.account ?? account
        let totalHeight = profileBannerBaseHeight + topSafeInset
        let visibleHeight = totalHeight + pullDistance

        ZStack(alignment: .bottom) {
            if let headerURL = acc?.profileHeaderURL {
                MoroNetworkImage(url: headerURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: visibleHeight + 2)
                    .clipped()
            } else if let acc {
                // No cover: the avatar blurred into a wash, or the account's own tone.
                ProfileGeneratedHeader(avatarURL: acc.profileAvatarURL, seed: acc.placeholderSeed)
                    .frame(maxWidth: .infinity)
                    .frame(height: visibleHeight + 2)
                    .clipped()
            } else {
                // Account still loading: stay neutral rather than flash a guessed tone.
                theme.colors.surfaceSubtle
            }

            LinearGradient(
                colors: [
                    .clear,
                    theme.colors.surfaceBase.opacity(0.6),
                    theme.colors.surfaceBase,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 56)
        }
        .frame(height: visibleHeight)
        .frame(maxWidth: .infinity)
        // No bottom rule: the gradient alone fades the banner into the page.
        .offset(y: -max(scrollOffset, 0))
        .overlay(alignment: .top) {
            LinearGradient(
                colors: [.black.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: navigationChromeHeight(topSafeInset: topSafeInset) + 18)
            .allowsHitTesting(false)
        }
        .clipped()
        .accessibilityIdentifier("profile.header")
    }

    // MARK: - Avatar & Actions Row (overlaps banner bottom)

    @ViewBuilder
    private var avatarAndActionsRow: some View {
        let acc = viewModel.account ?? account
        let avatarSize: CGFloat = 76

        HStack(alignment: .bottom, spacing: theme.spacing.m) {
            MoroAvatar(
                imageURL: acc?.avatarAnimatedURL,
                staticImageURL: acc?.avatarURL,
                initials: acc?.displayNameInitials ?? "?",
                seed: acc?.placeholderSeed,
                size: avatarSize
            )
            .overlay(
                Circle()
                    .stroke(theme.colors.surfaceBase, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)

            Spacer()

            if isCurrentUser {
                editProfileButton
            } else {
                actionButtons
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.top, -(avatarSize / 2))  // Overlap banner by half avatar
        .padding(.bottom, theme.spacing.xs)
    }

    // MARK: - Profile Identity

    @ViewBuilder
    private var profileContent: some View {
        let acc = viewModel.account ?? account

        VStack(alignment: .leading, spacing: theme.spacing.s) {
            // Display Name
            if let acc {
                AccountDisplayNameView(
                    account: acc,
                    typography: .title,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 2,
                    truncationMode: .tail,
                    minimumScaleFactor: 0.88,
                    allowsTightening: true
                )
            }

            if let acc {
                profileHandleRow(account: acc)
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.top, theme.spacing.xs)
    }

    @ViewBuilder
    private func profileHandleRow(account: Account) -> some View {
        HStack(spacing: theme.spacing.s) {
            Text("\u{200E}@\(account.acct.isEmpty ? account.username : account.acct)")
                .font(.subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .moroIdentityHandleLine()
                .layoutPriority(1)

            if account.bot {
                Text(MoroL10n.Profile.badgeBot)
                    .moroScaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(theme.colors.textSecondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(theme.colors.surfaceSubtle)
                    )
                    .overlay {
                        Capsule()
                            .stroke(theme.colors.textTertiary.opacity(0.35), lineWidth: 0.75)
                    }
                    .fixedSize(horizontal: true, vertical: false)
            }

            if account.locked {
                Image(systemName: "lock.fill")
                    .moroScaledFont(size: 11, weight: .semibold)
                    .foregroundStyle(theme.colors.textSecondary)
                    .accessibilityLabel(MoroL10n.Profile.badgeProtected)
                    .fixedSize()
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    /// Own-profile counterpart of the Follow button: same footprint, secondary surface,
    /// so the header keeps its geometry and "my profile" reads differently at a glance.
    private var editProfileButton: some View {
        Button {
            router.navigate(to: .editProfile)
        } label: {
            Text(MoroL10n.Profile.editProfileButton)
                .font(theme.typography.body)
                .fontWeight(.semibold)
                .lineLimit(1)
                .foregroundStyle(theme.colors.textPrimary)
                .padding(.horizontal, 20)
                .frame(height: 36)
                .moroRelationshipControlSurface(.secondary, theme: theme)
        }
        .buttonStyle(.plain)
        // Wait for the profile to load so the editor never opens on empty data.
        .disabled(viewModel.account == nil)
        .accessibilityIdentifier("profile.editButton")
    }

    private var actionButtons: some View {
        HStack(spacing: theme.spacing.m) {
            FollowButton(
                relationship: viewModel.relationship,
                isResolved: viewModel.isRelationshipResolved,
                isLoading: viewModel.isUpdatingRelationship,
                isInteractionDisabled: viewModel.isUpdatingNotification,
                onFollow: toggleFollow,
                onUnfollow: requestUnfollow,
                onCancelRequest: toggleFollow,
                onUnblock: toggleBlock
            )

            // Notification button (only show if following)
            if viewModel.relationship?.following == true {
                NotificationToggleButton(
                    isNotifying: viewModel.relationship?.notifying == true,
                    isLoading: viewModel.isUpdatingNotification,
                    isInteractionDisabled: viewModel.isUpdatingRelationship,
                    onToggle: toggleNotification
                )
            }
        }
    }

    private func requestUnfollow() {
        if AppSettings.shared.askBeforeUnfollowingAUser {
            actionPresentation.pendingAction = toggleFollow
            actionPresentation.showUnfollowConfirmation = true
        } else {
            toggleFollow()
        }
    }

    private func toggleFollow() {
        Task { await viewModel.toggleFollow() }
    }

    private func toggleMute() {
        Task { await viewModel.toggleMute() }
    }

    private func toggleBlock() {
        Task { await viewModel.toggleBlock() }
    }

    private func toggleNotification() {
        Task { await viewModel.toggleNotification() }
    }

    // MARK: - Stats Section

    @ViewBuilder
    private func statsSection(account: Account) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    profileStats(account: account)
                }
            } else {
                HStack(spacing: theme.spacing.l) {
                    profileStats(account: account)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.top, theme.spacing.m)
        .padding(.bottom, theme.spacing.s)
    }

    @ViewBuilder
    private func profileStats(account: Account) -> some View {
        profileStatItem(
            value: formatCount(account.statusesCount),
            label: MoroL10n.Profile.statPosts
        )
        profileStatButton(
            account: account,
            kind: .following,
            value: formatCount(account.followingCount),
            label: MoroL10n.Profile.statFollowing
        )
        profileStatButton(
            account: account,
            kind: .followers,
            value: formatCount(account.followersCount),
            label: MoroL10n.Profile.statFollowers
        )
    }

    private func profileStatButton(
        account: Account,
        kind: ProfileConnectionKind,
        value: String,
        label: String
    ) -> some View {
        let collectionsAreHidden = account.hideCollections == true && !isCurrentUser

        return Button {
            if collectionsAreHidden {
                AppFeedbackCenter.shared.showInfo(MoroL10n.Profile.collectionsHiddenMessage)
            } else {
                router.navigate(to: .profileConnections(accountID: account.id, kind: kind))
            }
        } label: {
            profileStatItem(
                value: value,
                label: label,
                showsPrivacyIndicator: collectionsAreHidden
            )
        }
        .buttonStyle(ProfileStatButtonStyle())
        .contentShape(Rectangle())
        .accessibilityLabel(Text(verbatim: "\(value) \(label)"))
        .accessibilityValue(
            collectionsAreHidden ? MoroL10n.Profile.collectionsHiddenAccessibilityValue : ""
        )
        .accessibilityIdentifier("profile.stat.\(kind.rawValue)")
    }

    @ViewBuilder
    private func profileStatItem(
        value: String,
        label: String,
        showsPrivacyIndicator: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(theme.typography.body)
                .fontWeight(.bold)
                .foregroundStyle(theme.colors.textPrimary)
            Text(label)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
            if showsPrivacyIndicator {
                Image(systemName: "eye.slash")
                    .moroScaledFont(size: 11, weight: .medium)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(theme.colors.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Profile Details

    @ViewBuilder
    private func profileBioSection(account: Account) -> some View {
        if !account.note.isEmpty {
            RichTextContentView(
                elements: account.noteContentElements,
                emojiSize: 16,
                isSelectable: true,
                fontOverride: theme.typography.body,
                textColorOverride: theme.colors.textPrimary,
                linkColorOverride: theme.colors.contentLink,
                underlinesLinks: true,
                lineSpacing: bioLineSpacing,
                paragraphSpacing: bioParagraphSpacing
            )
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .accessibilityIdentifier("profile.bio")
            .padding(.horizontal, theme.spacing.contentHorizontalInset)
            .padding(.top, theme.spacing.xs)
            .padding(.bottom, account.fields.isEmpty ? theme.spacing.s : 0)
        }
    }

    @ViewBuilder
    private func profileInfoSection(account: Account) -> some View {
        let hasFields = !account.fields.isEmpty

        if hasFields {
            VStack(spacing: 0) {
                ForEach(Array(account.fields.enumerated()), id: \.element.id) {
                    index,
                    field in
                    profileFieldRow(field: field, account: account)

                    if index < account.fields.count - 1 {
                        Rectangle()
                            .fill(theme.colors.borderSubtle)
                            .frame(height: 0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, theme.spacing.contentHorizontalInset)
            .padding(.top, theme.spacing.s)
        }
    }

    @ViewBuilder
    private func profileFieldRow(field: AccountField, account: Account) -> some View {
        let emojis = account.contentEmojis
        let nameElements = field.nameContentElements(
            emojis: emojis,
            contentBaseURL: account.contentBaseURL
        )

        // Vertical layout keeps the name above the value.
        // The value spans the full row width to wrap into, so a long URL can never
        // push the row past the screen edge and eat the horizontal margin — which a
        // side-by-side [fixed-name | value] layout does (the value's min width =
        // the unbreakable URL width, overflowing the row).
        VStack(alignment: .leading, spacing: 3) {
            RichTextContentView(
                elements: nameElements,
                emojiSize: 13,
                isSelectable: false,
                fontOverride: .system(.caption, weight: .medium),
                uiFontOverride: .moroScaled(ofSize: 12, weight: .medium, relativeTo: .caption1),
                textColorOverride: theme.colors.textSecondary,
                linkColorOverride: theme.colors.contentLink,
                lineSpacing: 2,
                lineLimit: 1,
                truncationMode: .tail
            )
            .accessibilityLabel(
                field.isVerified
                    ? "\(nameElements.plainTextValue), \(MoroL10n.Profile.verifiedField)"
                    : nameElements.plainTextValue
            )

            HStack(alignment: .firstTextBaseline, spacing: theme.spacing.xs) {
                RichTextContentView(
                    elements: field.valueContentElements(
                        emojis: emojis,
                        contentBaseURL: account.contentBaseURL
                    ),
                    emojiSize: 16,
                    isSelectable: true,
                    fontOverride: .system(.subheadline, weight: .medium),
                    uiFontOverride: .moroScaled(ofSize: 15, weight: .medium, relativeTo: .subheadline),
                    textColorOverride: theme.colors.textPrimary,
                    linkColorOverride: theme.colors.contentLink,
                    underlinesLinks: false,
                    lineSpacing: 3,
                    trailingSystemImage: field.isVerified ? "checkmark.seal.fill" : nil,
                    trailingSystemImageColor: theme.colors.success,
                    trailingSystemImageSize: 11
                )
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, theme.spacing.s)
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private func tabBar(
        hidesAccessibility: Bool
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(viewModel.availableTabs, id: \.rawValue) { tab in
                Button(action: {
                    selectProfileTab(tab)
                }) {
                    VStack(spacing: 0) {
                        Text(tab.localizedTitle)
                            .font(theme.typography.body)
                            .fontWeight(viewModel.selectedTab == tab ? .semibold : .regular)
                            .foregroundStyle(
                                viewModel.selectedTab == tab
                                    ? theme.colors.textPrimary : theme.colors.textSecondary
                            )
                            .padding(.vertical, theme.spacing.sm)

                        Rectangle()
                            .fill(
                                viewModel.selectedTab == tab
                                    ? theme.colors.primary500 : Color.clear
                            )
                            .frame(height: 2)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(hidesAccessibility)
                .accessibilityIdentifier("profile.tab.\(tab.rawValue.lowercased())")
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.top, theme.spacing.m)
        .background(theme.colors.surfaceBase)
    }

    private func selectProfileTab(_ tab: ProfileViewModel.Tab) {
        guard tab != viewModel.selectedTab else { return }
        viewModel.selectTab(tab)
    }

    // MARK: - Helpers

    private func postActions(for status: Status) -> PostActions {
        handlers.buildPostActions(
            for: status,
            onPollVote: { pollID, choices in
                await viewModel.votePoll(pollID: pollID, choices: choices)
            }
        )
    }

    private func performDelete(_ status: Status, redraft: Bool) {
        handlers.performDelete(status, redraft: redraft)
    }

    // MARK: - Interaction Handlers

    // MARK: - Post Interaction Handlers

    private var handlers: PostInteractionHandlers {
        PostInteractionHandlers(
            interactionService: interactionService,
            actionSurface: actionSurface,
            postMenuActionCenter: postMenuActionCenter,
            apiClient: apiClient,
            currentUserID: appState.currentAccount?.id,
            router: router,
            onRemoveStatus: { id in viewModel.removeStatus(id: id) }
        )
    }

}

#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "moro",
        acct: "moro@mastodon.social",
        displayName: "Moro User",
        note: "Building a friendly Mastodon client for iOS 🦣",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 1234,
        followingCount: 567,
        statusesCount: 890,
        createdAt: Date().addingTimeInterval(-86400 * 365),
        locked: false,
        bot: false,
        fields: [
            AccountField(
                name: "Website", value: "<a href=\"https://getmoro.app\">getmoro.app</a>",
                verifiedAt: Date()),
            AccountField(
                name: "GitHub", value: "<a href=\"https://github.com/moro\">github.com/moro</a>"),
            AccountField(name: "Location", value: "San Francisco, CA"),
        ]
    )

    let state = AppState()
    state.currentAccount = sampleAccount

    return ProfileView(
        account: sampleAccount,
        onLogout: {},
        apiClient: MastodonClient(authInterceptor: AuthInterceptor(tokenProvider: state))
    )
        .environmentObject(state)
        .moroTheme(MoroTheme())
}
