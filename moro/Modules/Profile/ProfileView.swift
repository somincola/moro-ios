//
//  ProfileView.swift
//  moro
//
//  User profile view with posts, replies, and media tabs.
//

import SwiftUI

// MARK: - Profile View

private struct ProfileHeaderPlaceholder: View {
    let backgroundColor: Color
    let lineColor: Color

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(backgroundColor)
            )

            let spacing: CGFloat = 28
            var fineLines = Path()
            for originX in stride(
                from: -size.height,
                through: size.width + size.height,
                by: spacing
            ) {
                fineLines.move(to: CGPoint(x: originX, y: 0))
                fineLines.addLine(to: CGPoint(x: originX + size.height, y: size.height))
            }
            context.stroke(fineLines, with: .color(lineColor), lineWidth: 0.7)

            var broadLines = Path()
            for originX in stride(
                from: -size.height,
                through: size.width + size.height,
                by: spacing * 3
            ) {
                broadLines.move(to: CGPoint(x: originX, y: size.height))
                broadLines.addLine(to: CGPoint(x: originX + size.height, y: 0))
            }
            context.stroke(broadLines, with: .color(lineColor.opacity(0.55)), lineWidth: 0.6)
        }
        .accessibilityHidden(true)
    }
}

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
    @State private var actionPresentation = ProfileActionPresentationState()
    @StateObject private var actionSurface = PostActionSurfaceCenter()

    @StateObject private var interactionService: PostInteractionService
    private let pullRefreshVisualThreshold: CGFloat = 72
    private let refreshFeedbackMinimumDuration: TimeInterval = 0.85
    private let pullRefreshIndicatorSize: CGFloat = 34
    private let navigationBarHeight: CGFloat = 44

    private var profileChromeProgress: CGFloat {
        chromeState.headerProgress(
            bannerHeight: profileBannerBaseHeight,
            navigationBarHeight: navigationBarHeight
        )
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
        apiClient: MastodonAPI? = nil
    ) {
        self.account = account
        self.accountID = accountID
        self.onLogout = onLogout

        let resolvedAccountID = accountID ?? account?.id ?? ""
        let resolvedClient =
            apiClient
            ?? {
                let state = AppState()
                let interceptor = AuthInterceptor(tokenProvider: state)
                return MastodonClient(authInterceptor: interceptor)
            }()

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
                            .frame(minHeight: chromeLayout.pinnedContentHeight, alignment: .top)
                            .background(theme.colors.surfaceBase)
                    }
                }
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
        .navigationTitle(
            navChromeVisible
                ? (viewModel.account?.displayName
                    ?? account?.displayName
                    ?? MoroL10n.Profile.navTitle)
                : ""
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(
            profileChromeProgress >= 0.55 ? colorScheme : .dark,
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
        await viewModel.refresh()
        syncAppStateFromCurrentProfileIfNeeded()
    }

    private func updateScrollState(_ scrolled: CGFloat) {
        let didArm = chromeState.updateScroll(
            scrolled,
            pullRefreshThreshold: pullRefreshVisualThreshold
        )
        if didArm {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    private func startPullRefreshIfNeeded() {
        guard chromeState.beginRefreshIfArmed() else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task { @MainActor in
            let started = Date()
            await refreshProfileData()

            let remaining = refreshFeedbackMinimumDuration - Date().timeIntervalSince(started)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }

            chromeState.finishRefresh()
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
                onShare: shareUser,
                onEditProfile: { router.navigate(to: .editProfile) },
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

    private func navigationChromeHeight(topSafeInset: CGFloat) -> CGFloat {
        topSafeInset + navigationBarHeight
    }

    @ViewBuilder
    private func profileNavigationChromeBackground(
        topChromeHeight: CGFloat,
        progress: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            theme.colors.surfaceBase
                .frame(height: topChromeHeight)

            Rectangle()
                .fill(theme.colors.borderSubtle)
                .frame(height: 0.5)
        }
        .frame(maxWidth: .infinity)
        .opacity(progress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static var activeKeyWindow: UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return activeScene?.windows.first { $0.isKeyWindow } ?? activeScene?.windows.first
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
            ProfilePullRefreshSpinner(
                progress: chromeState.isRefreshing ? 1 : progress,
                isRefreshing: chromeState.isRefreshing,
                color: .white
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
        .background(theme.colors.surfaceBase)
    }

    @ViewBuilder
    private var profileMoreButton: some View {
        ProfileMoreButton(
            account: viewModel.account ?? account,
            relationship: viewModel.relationship,
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

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let rootViewController = windowScene.windows.first?.rootViewController
        {
            rootViewController.present(activityVC, animated: true)
        }
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
                .background(theme.colors.surfaceBase)

                VStack(alignment: .leading, spacing: 0) {
                    profileBioSection(account: acc)

                    profileInfoSection(account: acc)
                }
                .background(theme.colors.groupedBackground)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    avatarAndActionsRow
                    profileContent
                }
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
            ProfileHeaderPlaceholder(
                backgroundColor: theme.colors.surfaceSubtle,
                lineColor: theme.colors.textMuted.opacity(0.16)
            )

            if let headerURL = acc?.profileHeaderURL {
                MoroNetworkImage(url: headerURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: visibleHeight + 2)
                    .clipped()
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
        .offset(y: -max(scrollOffset, 0))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.borderSubtle)
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
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
                size: avatarSize
            )
            .overlay(
                Circle()
                    .stroke(theme.colors.surfaceBase, lineWidth: 3)
            )
            .shadow(color: .black.opacity(0.14), radius: 5, x: 0, y: 2)

            Spacer()

            if !isCurrentUser {
                actionButtons
            }
        }
        .padding(.horizontal, theme.spacing.l)
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
        .padding(.horizontal, theme.spacing.l)
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
    private var actionButtons: some View {
        HStack(spacing: theme.spacing.m) {
            FollowButton(
                relationship: viewModel.relationship,
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
        .padding(.horizontal, theme.spacing.l)
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
        let collectionsAreHidden = account.hideCollections == true

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
                fontOverride: .system(.subheadline, weight: .regular),
                uiFontOverride: .moroScaled(
                    ofSize: 15,
                    weight: .regular,
                    relativeTo: .subheadline
                ),
                textColorOverride: theme.colors.textPrimary,
                linkColorOverride: theme.colors.contentLink,
                underlinesLinks: true,
                lineSpacing: 3
            )
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            .padding(theme.spacing.m)
            .moroCardSurface(cornerRadius: 8, tone: .base, bordered: true)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.s)
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
                            .frame(height: 1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .moroCardSurface(cornerRadius: 8, tone: .base, bordered: true)
            .padding(.horizontal, theme.spacing.l)
            .padding(.top, theme.spacing.s)
            .padding(.bottom, theme.spacing.m)
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
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            RichTextContentView(
                elements: nameElements,
                emojiSize: 13,
                isSelectable: false,
                fontOverride: .system(.caption, weight: .semibold),
                uiFontOverride: .moroScaled(ofSize: 12, weight: .semibold, relativeTo: .caption1),
                textColorOverride: theme.colors.textSecondary,
                linkColorOverride: theme.colors.primary500,
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
                    linkColorOverride: theme.colors.primary500,
                    underlinesLinks: true,
                    lineSpacing: 3,
                    trailingSystemImage: field.isVerified ? "checkmark.seal.fill" : nil,
                    trailingSystemImageColor: theme.colors.success,
                    trailingSystemImageSize: 13
                )
                .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.sm)
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
        .padding(.horizontal, theme.spacing.l)
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
                name: "Website", value: "<a href=\"https://moro.somincola.com\">moro.somincola.com</a>",
                verifiedAt: Date()),
            AccountField(
                name: "GitHub", value: "<a href=\"https://github.com/moro\">github.com/moro</a>"),
            AccountField(name: "Location", value: "San Francisco, CA"),
        ]
    )

    let state = AppState()
    state.currentAccount = sampleAccount

    return ProfileView(account: sampleAccount, onLogout: {})
        .environmentObject(state)
        .moroTheme(MoroTheme())
}
