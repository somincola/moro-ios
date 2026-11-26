//
//  MoroNavigationDrawer.swift
//  moro
//
//  Minimalist monochrome leading navigation drawer synced with NavigationAccessPolicy.
//  Houses account identity, quick account switching, TabBar overflow destinations,
//  instance utilities, and contextual Settings / Navigation customization actions.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

/// Lightweight host that mounts `MoroNavigationDrawer` strictly on demand while open,
/// animating out, or tracking an interactive edge-swipe. Keeping the drawer unmounted when
/// closed avoids offscreen hit-target / accessibility ghosting across sheet presentations.
struct MoroNavigationDrawerHost: View {
    @ObservedObject var coordinator: RootTabCoordinator
    @ObservedObject private var inboxUnreadStore = InboxUnreadStore.shared
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let currentAccount: Account?
    let accountSessions: [StoredAccountSession]
    let activeSessionID: String?
    let onSwitchAccount: (String) -> Void
    let onAddAccount: () -> Void

    @State private var isMounted = false
    @State private var animatedProgress: CGFloat = 0
    @State private var unmountTask: Task<Void, Never>?

    private var policy: NavigationAccessPolicy {
        NavigationAccessPolicy(
            tabLayout: coordinator.tabLayout,
            unreadInboxCount: inboxUnreadStore.totalUnreadCount,
            unreadAnnouncementsCount: appState.unreadAnnouncementsCount
        )
    }

    private var shouldRenderOverlay: Bool {
        isMounted || coordinator.isDrawerPresented || coordinator.drawerInteractiveProgress != nil
    }

    private var animationsEnabled: Bool {
        #if os(iOS)
        UIView.areAnimationsEnabled
        #else
        true
        #endif
    }

    private var openAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.28, extraBounce: 0)
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.14) : .snappy(duration: 0.24, extraBounce: 0)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Non-empty anchor so `.onChange` observers remain active while the drawer is unmounted.
            Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if shouldRenderOverlay {
                MoroNavigationDrawer(
                    coordinator: coordinator,
                    policy: policy,
                    animatedProgress: $animatedProgress,
                    currentAccount: currentAccount,
                    accountSessions: accountSessions,
                    activeSessionID: activeSessionID,
                    onSwitchAccount: onSwitchAccount,
                    onAddAccount: onAddAccount
                )
            }
        }
        .onAppear {
            if coordinator.isDrawerPresented {
                isMounted = true
                animatedProgress = 1
            } else if let interactive = coordinator.drawerInteractiveProgress {
                isMounted = true
                animatedProgress = min(max(interactive, 0), 1)
            }
        }
        .onChange(of: coordinator.drawerInteractiveProgress) { _, interactive in
            if let interactive {
                unmountTask?.cancel()
                unmountTask = nil
                if !isMounted {
                    isMounted = true
                }
                animatedProgress = min(max(interactive, 0), 1)
            } else if !coordinator.isDrawerPresented {
                animateClosedAndUnmount()
            }
        }
        .onChange(of: coordinator.isDrawerPresented) { _, presented in
            if presented {
                unmountTask?.cancel()
                unmountTask = nil
                if !isMounted {
                    isMounted = true
                }
                if !animationsEnabled {
                    animatedProgress = 1
                } else if animatedProgress == 0 {
                    DispatchQueue.main.async {
                        guard coordinator.isDrawerPresented,
                              coordinator.drawerInteractiveProgress == nil
                        else { return }
                        withAnimation(openAnimation) {
                            animatedProgress = 1
                        }
                    }
                } else {
                    withAnimation(openAnimation) {
                        animatedProgress = 1
                    }
                }
            } else if coordinator.drawerInteractiveProgress == nil {
                animateClosedAndUnmount()
            }
        }
        .onDisappear {
            unmountTask?.cancel()
            unmountTask = nil
        }
    }

    private func animateClosedAndUnmount() {
        unmountTask?.cancel()
        unmountTask = nil
        guard isMounted else {
            animatedProgress = 0
            return
        }
        guard animationsEnabled else {
            animatedProgress = 0
            isMounted = false
            return
        }
        withAnimation(closeAnimation) {
            animatedProgress = 0
        }
        let durationNs: UInt64 = reduceMotion ? 180_000_000 : 280_000_000
        unmountTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: durationNs)
            guard !Task.isCancelled,
                  !coordinator.isDrawerPresented,
                  coordinator.drawerInteractiveProgress == nil
            else { return }
            isMounted = false
        }
    }
}

struct MoroNavigationDrawer: View {
    @ObservedObject var coordinator: RootTabCoordinator
    let policy: NavigationAccessPolicy
    @Binding var animatedProgress: CGFloat
    let currentAccount: Account?
    let accountSessions: [StoredAccountSession]
    let activeSessionID: String?
    let onSwitchAccount: (String) -> Void
    let onAddAccount: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    static func preferredWidth(containerWidth: CGFloat, leadingSafeInset: CGFloat = 0) -> CGFloat {
        let baseWidth = min(max(containerWidth * 0.72, 256), 288)
        return min(baseWidth + leadingSafeInset, containerWidth * 0.80)
    }

    @State private var dismissDragTranslation: CGFloat = 0
    @State private var isDraggingToClose = false
    @State private var suppressRowTapsUntil: Date = .distantPast

    private var animationsEnabled: Bool {
        #if os(iOS)
        UIView.areAnimationsEnabled
        #else
        true
        #endif
    }

    private var activeSession: StoredAccountSession? {
        accountSessions.first { $0.id == activeSessionID }
    }

    private var otherSessions: [StoredAccountSession] {
        accountSessions.filter { $0.id != activeSessionID }
    }

    private var currentInstanceHost: String? {
        if let host = activeSession?.instanceHost, !host.isEmpty {
            return host
        }
        if let urlString = currentAccount?.url, let host = URL(string: urlString)?.host {
            return host
        }
        return nil
    }

    private var windowSafeAreaInsets: EdgeInsets {
        #if os(iOS)
        let insets = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
        return EdgeInsets(
            top: insets.top,
            leading: insets.left,
            bottom: insets.bottom,
            trailing: insets.right
        )
        #else
        return EdgeInsets()
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let containerWidth = proxy.size.width
            let resolvedSafeInsets = EdgeInsets(
                top: max(proxy.safeAreaInsets.top, windowSafeAreaInsets.top),
                leading: max(proxy.safeAreaInsets.leading, windowSafeAreaInsets.leading),
                bottom: max(proxy.safeAreaInsets.bottom, windowSafeAreaInsets.bottom),
                trailing: max(proxy.safeAreaInsets.trailing, windowSafeAreaInsets.trailing)
            )
            let drawerWidth = Self.preferredWidth(
                containerWidth: containerWidth,
                leadingSafeInset: resolvedSafeInsets.leading
            )
            let progress = resolvedProgress(drawerWidth: drawerWidth)
            let isRTL = layoutDirection == .rightToLeft
            let direction: CGFloat = isRTL ? -1 : 1
            let hiddenOffset = -drawerWidth * direction
            let currentOffset = reduceMotion ? 0 : hiddenOffset * (1 - progress)

            ZStack(alignment: .leading) {
                Color.black
                    .opacity((colorScheme == .dark ? 0.56 : 0.28) * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                HStack(spacing: 0) {
                    drawerPanel(width: drawerWidth, safeAreaInsets: resolvedSafeInsets)
                        .frame(width: drawerWidth, height: proxy.size.height)
                        .accessibilityAddTraits(.isModal)

                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            dismissDrawer()
                        }
                        .accessibilityElement()
                        .accessibilityLabel(Text(MoroL10n.Common.close))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("drawer.scrim")
                }
                .offset(x: currentOffset)
                .opacity(reduceMotion ? progress : 1)
            }
            #if os(iOS)
            .gesture(
                DrawerClosePanGesture(
                    isRTL: isRTL,
                    isEnabled: coordinator.isDrawerPresented && coordinator.drawerInteractiveProgress == nil,
                    onChanged: { directedTranslation in
                        handleClosePanChanged(directedTranslation)
                    },
                    onEnded: { directedTranslation, directedVelocity in
                        handleClosePanEnded(
                            directedTranslation: directedTranslation,
                            directedVelocity: directedVelocity,
                            drawerWidth: drawerWidth
                        )
                    },
                    onCancelled: {
                        handleClosePanCancelled()
                    }
                )
            )
            #endif
            .accessibilityHidden(!coordinator.isDrawerPresented)
        }
        .ignoresSafeArea()
    }

    private func resolvedProgress(drawerWidth: CGFloat) -> CGFloat {
        if let interactive = coordinator.drawerInteractiveProgress {
            return min(max(interactive, 0), 1)
        }
        let baseProgress: CGFloat
        if !animationsEnabled {
            baseProgress = coordinator.isDrawerPresented ? 1 : 0
        } else {
            baseProgress = animatedProgress
        }
        guard baseProgress > 0 else { return 0 }
        let dragDelta = min(0, dismissDragTranslation) / max(drawerWidth, 1)
        return min(max(baseProgress + dragDelta, 0), 1)
    }

    private func handleClosePanChanged(_ directedTranslation: CGFloat) {
        guard coordinator.isDrawerPresented else { return }
        if !isDraggingToClose {
            isDraggingToClose = true
        }
        suppressRowTapsUntil = Date().addingTimeInterval(0.45)
        dismissDragTranslation = min(0, directedTranslation)
    }

    private func handleClosePanEnded(
        directedTranslation: CGFloat,
        directedVelocity: CGFloat,
        drawerWidth: CGFloat
    ) {
        let currentProgress = resolvedProgress(drawerWidth: drawerWidth)
        isDraggingToClose = false
        suppressRowTapsUntil = Date().addingTimeInterval(0.35)
        guard coordinator.isDrawerPresented else {
            dismissDragTranslation = 0
            return
        }
        let shouldClose = directedTranslation < -drawerWidth * 0.25 || directedVelocity < -420
        if shouldClose {
            animatedProgress = currentProgress
            dismissDragTranslation = 0
            coordinator.closeDrawer()
        } else if animationsEnabled && !reduceMotion {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                dismissDragTranslation = 0
            }
        } else {
            dismissDragTranslation = 0
        }
    }

    private func handleClosePanCancelled() {
        isDraggingToClose = false
        suppressRowTapsUntil = Date().addingTimeInterval(0.35)
        if animationsEnabled && !reduceMotion {
            withAnimation(.snappy(duration: 0.24, extraBounce: 0)) {
                dismissDragTranslation = 0
            }
        } else {
            dismissDragTranslation = 0
        }
    }

    private func dismissDrawer() {
        isDraggingToClose = false
        dismissDragTranslation = 0
        suppressRowTapsUntil = Date().addingTimeInterval(0.35)
        coordinator.closeDrawer()
    }

    private func performDrawerAction(_ action: () -> Void) {
        guard coordinator.isDrawerPresented,
              !isDraggingToClose,
              dismissDragTranslation == 0,
              Date() >= suppressRowTapsUntil
        else { return }
        action()
    }

    // MARK: - Panel Layout

    private func drawerPanel(width: CGFloat, safeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            accountHeader(topInset: safeAreaInsets.top)

            MoroDivider()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(policy.drawerOverflowTabs, id: \.self) { tab in
                        overflowTabRow(tab)
                    }

                    secondarySection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }

            MoroDivider()

            drawerFooter(bottomInset: safeAreaInsets.bottom)
        }
        .allowsHitTesting(!isDraggingToClose)
        .padding(.leading, safeAreaInsets.leading)
        .background(theme.colors.surfaceBase)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.colors.borderSubtle)
                .frame(width: 0.5)
        }
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.46 : 0.14),
            radius: 22,
            x: layoutDirection == .rightToLeft ? -6 : 6,
            y: 0
        )
    }

    // MARK: - Account Identity Header

    private func accountHeader(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if let account = currentAccount {
                    Button {
                        performDrawerAction {
                            coordinator.openTabOrRoute(.me, account: account)
                        }
                    } label: {
                        MoroAvatar(
                            imageURL: account.avatarAnimatedURL,
                            staticImageURL: account.avatarURL,
                            initials: account.displayNameInitials,
                            seed: account.placeholderSeed,
                            size: 46
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(MoroL10n.Navigation.profileCenter))
                    .accessibilityIdentifier("drawer.profileAvatar")
                }

                Spacer(minLength: 8)

                accountSwitcherCluster
            }

            if let account = currentAccount {
                Button {
                    performDrawerAction {
                        coordinator.openTabOrRoute(.me, account: account)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        AccountDisplayNameView(
                            account: account,
                            typography: .subtitle,
                            textColor: theme.colors.textPrimary
                        )
                        Text(formattedHandle(for: account))
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("drawer.profileHeader")

                connectionStatsRow(for: account)
            }
        }
        .padding(.top, max(topInset, 20) + 14)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var accountSwitcherCluster: some View {
        HStack(spacing: 2) {
            ForEach(Array(otherSessions.prefix(2))) { session in
                Button {
                    performDrawerAction {
                        dismissDrawer()
                        onSwitchAccount(session.id)
                    }
                } label: {
                    MoroAvatar(
                        imageURL: session.account.avatarAnimatedURL,
                        staticImageURL: session.account.avatarURL,
                        initials: session.account.displayNameInitials,
                        seed: session.account.placeholderSeed,
                        size: 28
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(
                                theme.colors.textPrimary.opacity(colorScheme == .dark ? 0.18 : 0.12),
                                lineWidth: 0.75
                            )
                    }
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(session.account.displayName.isEmpty ? session.account.acct : session.account.displayName))
                .accessibilityIdentifier("drawer.switchAccount.\(session.id)")
            }

            Menu {
                let overflowSessions = Array(otherSessions.dropFirst(2))
                if !overflowSessions.isEmpty {
                    ForEach(overflowSessions) { session in
                        Button {
                            dismissDrawer()
                            onSwitchAccount(session.id)
                        } label: {
                            Label(
                                "@\(session.account.acct)",
                                systemImage: "person.crop.circle"
                            )
                        }
                    }
                    Divider()
                }

                Button {
                    dismissDrawer()
                    onAddAccount()
                } label: {
                    Label(MoroL10n.AccountMgmt.addAccount, systemImage: "plus")
                }

                if policy.showsDrawerSettingsFooter {
                    Button {
                        coordinator.presentSettings()
                    } label: {
                        Label(MoroL10n.Settings.account, systemImage: "person.2")
                    }
                }
            } label: {
                accountsMenuButtonLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(MoroL10n.Settings.account))
            .accessibilityIdentifier("drawer.accountsMenu")
        }
        .padding(.trailing, -6)
    }

    @ViewBuilder
    private var accountsMenuButtonLabel: some View {
        let isHighContrast = colorSchemeContrast == .increased
        let borderOpacity: Double = {
            if isHighContrast { return 0.50 }
            return colorScheme == .dark ? 0.28 : 0.22
        }()
        let borderWidth: CGFloat = isHighContrast ? 1.25 : 1.0
        let shadowOpacity: Double = colorScheme == .dark ? 0.36 : 0.10
        let fillColor: Color = colorScheme == .dark
            ? theme.colors.surfaceElevated
            : theme.colors.surfaceBase

        Image(systemName: "ellipsis")
            .moroScaledFont(size: 14, weight: .semibold)
            .foregroundStyle(theme.colors.textPrimary)
            .frame(width: 32, height: 32)
            .background(Circle().fill(fillColor))
            .overlay {
                Circle()
                    .strokeBorder(theme.colors.textPrimary.opacity(borderOpacity), lineWidth: borderWidth)
            }
            .shadow(
                color: Color.black.opacity(shadowOpacity),
                radius: 3.5,
                x: 0,
                y: 1
            )
            .frame(width: 44, height: 44)
            .contentShape(Circle())
    }

    private func connectionStatsRow(for account: Account) -> some View {
        let followingText = MoroL10n.Navigation.followingCount(account.followingCount)
        let followersText = account.followersCount < 1_000
            ? MoroL10n.Navigation.followersCount(account.followersCount)
            : MoroL10n.Profile.compactFollowers(
                ProfileConnectionKind.compactCount(account.followersCount, locale: locale)
            )

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                statButton(text: followingText) {
                    coordinator.openRouteFromDrawer(
                        .profileConnections(accountID: account.id, kind: .following, totalCount: account.followingCount)
                    )
                }
                statButton(text: followersText) {
                    coordinator.openRouteFromDrawer(
                        .profileConnections(accountID: account.id, kind: .followers, totalCount: account.followersCount)
                    )
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                statButton(text: followingText) {
                    coordinator.openRouteFromDrawer(
                        .profileConnections(accountID: account.id, kind: .following, totalCount: account.followingCount)
                    )
                }
                statButton(text: followersText) {
                    coordinator.openRouteFromDrawer(
                        .profileConnections(accountID: account.id, kind: .followers, totalCount: account.followersCount)
                    )
                }
            }
        }
    }

    private func statButton(text: String, action: @escaping () -> Void) -> some View {
        Button {
            performDrawerAction(action)
        } label: {
            Text(styledStatText(text))
                .lineLimit(1)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func styledStatText(_ raw: String) -> AttributedString {
        var attributed = AttributedString(raw)
        attributed.font = theme.typography.caption
        attributed.foregroundColor = theme.colors.textSecondary
        let nsRange = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        if let regex = try? NSRegularExpression(pattern: #"\d[\d.,\u00A0]*[KkMmWw万亿]?"#) {
            for match in regex.matches(in: raw, range: nsRange) {
                if let range = Range(match.range, in: raw),
                   let attrRange = Range(range, in: attributed)
                {
                    attributed[attrRange].font = theme.typography.caption.weight(.semibold)
                    attributed[attrRange].foregroundColor = theme.colors.textPrimary
                }
            }
        }
        return attributed
    }

    // MARK: - Navigation Rows

    private func overflowTabRow(_ tab: MainTab) -> some View {
        let title: String = tab == .me ? MoroL10n.Navigation.profileCenter : tab.title
        let badge: Int = tab == .inbox ? policy.unreadInboxCount : 0
        return drawerRow(
            title: title,
            systemImage: tab.icon,
            badgeCount: badge,
            accessibilityIdentifier: "drawer.tab.\(tab.rawValue)"
        ) {
            coordinator.openTabOrRoute(tab, account: currentAccount)
        }
    }

    @ViewBuilder
    private var secondarySection: some View {
        drawerRow(
            title: MoroL10n.Topics.title,
            systemImage: "number",
            accessibilityIdentifier: "drawer.followedTopics"
        ) {
            coordinator.openRouteFromDrawer(.followedTopics)
        }

        drawerRow(
            title: MoroL10n.Announcements.title,
            systemImage: "megaphone",
            badgeCount: policy.unreadAnnouncementsCount,
            accessibilityIdentifier: "drawer.announcements"
        ) {
            coordinator.openRouteFromDrawer(.announcements)
        }

        drawerRow(
            title: MoroL10n.Navigation.instanceDetails,
            systemImage: "building.2",
            accessibilityIdentifier: "drawer.instanceDetails"
        ) {
            coordinator.openRouteFromDrawer(.instanceDetails)
        }
    }

    private func drawerRow(
        title: String,
        systemImage: String,
        detail: String? = nil,
        badgeCount: Int = 0,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            performDrawerAction(action)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .moroScaledFont(size: 18, weight: .regular)
                    .foregroundStyle(theme.colors.textPrimary)
                    .frame(width: 24, alignment: .center)
                    .accessibilityHidden(true)

                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                if badgeCount > 0 {
                    Text(badgeCount > 99 ? "99+" : "\(badgeCount)")
                        .moroScaledFont(size: 11, weight: .bold, relativeTo: .caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(minWidth: 20, minHeight: 20)
                        .background(Capsule().fill(theme.colors.error))
                        .accessibilityHidden(true)
                } else if let detail, !detail.isEmpty, !dynamicTypeSize.isAccessibilitySize {
                    Text(detail)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 96, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(minHeight: 46)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(DrawerRowButtonStyle(highlightColor: theme.colors.surfaceSubtle, isSuppressed: isDraggingToClose))
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    // MARK: - Footer

    private func drawerFooter(bottomInset: CGFloat) -> some View {
        HStack(spacing: 8) {
            if policy.showsDrawerSettingsFooter {
                Button {
                    performDrawerAction {
                        coordinator.presentSettings()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "gearshape")
                            .moroScaledFont(size: 18, weight: .regular)
                            .frame(width: 24, alignment: .center)
                        Text(MoroL10n.Settings.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(DrawerRowButtonStyle(highlightColor: theme.colors.surfaceSubtle, isSuppressed: isDraggingToClose))
                .accessibilityIdentifier("drawer.settings")

                Spacer(minLength: 4)

                Button {
                    performDrawerAction {
                        coordinator.presentNavigationCustomization()
                    }
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .moroScaledFont(size: 17, weight: .regular)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(DrawerRowButtonStyle(highlightColor: theme.colors.surfaceSubtle, isSuppressed: isDraggingToClose))
                .accessibilityLabel(Text(MoroL10n.NavigationCustomization.title))
                .accessibilityIdentifier("drawer.customizeNavigation")
            } else {
                Button {
                    performDrawerAction {
                        coordinator.presentNavigationCustomization()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .moroScaledFont(size: 18, weight: .regular)
                            .frame(width: 24, alignment: .center)
                        Text(MoroL10n.NavigationCustomization.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(theme.colors.textPrimary)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(DrawerRowButtonStyle(highlightColor: theme.colors.surfaceSubtle, isSuppressed: isDraggingToClose))
                .accessibilityIdentifier("drawer.customizeNavigation")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, max(bottomInset, 12) + 4)
    }

    private func formattedHandle(for account: Account) -> String {
        if account.acct.contains("@") {
            return "@\(account.acct)"
        }
        if let host = currentInstanceHost {
            return "@\(account.acct)@\(host)"
        }
        return "@\(account.acct)"
    }
}

private struct DrawerRowButtonStyle: ButtonStyle {
    let highlightColor: Color
    var isSuppressed = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(configuration.isPressed && !isSuppressed ? highlightColor : .clear)
            )
    }
}

#if os(iOS)
/// Native UIKit horizontal close pan gesture for the drawer.
/// Using `UIPanGestureRecognizer` (`cancelsTouchesInView = true`, non-simultaneous)
/// cancels in-flight row `Button` tracking the instant a close swipe begins, so
/// lifting the finger after swiping left across a menu row never activates that row.
private struct DrawerClosePanGesture: UIGestureRecognizerRepresentable {
    let isRTL: Bool
    let isEnabled: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void
    let onCancelled: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(isRTL: isRTL, isEnabled: isEnabled)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.cancelsTouchesInView = true
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isRTL = isRTL
        context.coordinator.isEnabled = isEnabled
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        guard let view = recognizer.view else { return }
        let rawTranslation = recognizer.translation(in: view).x
        let rawVelocity = recognizer.velocity(in: view).x
        let directedTranslation = isRTL ? -rawTranslation : rawTranslation
        let directedVelocity = isRTL ? -rawVelocity : rawVelocity

        switch recognizer.state {
        case .began, .changed:
            onChanged(min(0, directedTranslation))
        case .ended:
            onEnded(directedTranslation, directedVelocity)
        case .cancelled, .failed:
            onCancelled()
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isRTL: Bool
        var isEnabled: Bool

        init(isRTL: Bool, isEnabled: Bool) {
            self.isRTL = isRTL
            self.isEnabled = isEnabled
            super.init()
        }

        // Avoid the isolated-deinit back-deployment crash on iOS 26.2 and earlier.
        nonisolated deinit {}

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard isEnabled,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view
            else { return false }
            let velocity = pan.velocity(in: view)
            let translation = pan.translation(in: view)
            let directedVelocity = isRTL ? -velocity.x : velocity.x
            let directedTranslation = isRTL ? -translation.x : translation.x
            let movingTowardClose = directedVelocity < -10 || directedTranslation < -4
            let primarilyHorizontal = abs(velocity.x) > abs(velocity.y) * 1.1
                || abs(translation.x) > abs(translation.y) * 1.1
            return movingTowardClose && primarilyHorizontal
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}
#endif
