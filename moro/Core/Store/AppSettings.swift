//
//  AppSettings.swift
//  moro
//
//  Centralized app settings management using UserDefaults.
//

import Combine
import Foundation
import MoroLocalization
import SwiftUI

/// Centralized app settings manager
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let userDefaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        // Appearance
        static let appearance = "appearance"
        static let appIcon = "appIcon"
        static let tabIconTheme = "tabIconTheme"
        static let navigationStyle = "navigationStyle"

        // Ask Before
        static let askBeforePostingWithoutAltText = "askBeforePostingWithoutAltText"
        static let askBeforeUnfollowingSomeone = "askBeforeUnfollowingSomeone"
        static let askBeforeMutingAUser = "askBeforeMutingAUser"
        static let askBeforeBlockingAUser = "askBeforeBlockingAUser"
        static let askBeforeBoostingAPost = "askBeforeBoostingAPost"
        static let askBeforeDeletingAPost = "askBeforeDeletingAPost"

        // Design
        static let playAnimations = "playAnimations"
        static let autoplayGIFs = "autoplayGIFs"

        // Language
        static let defaultPostLanguage = "defaultPostLanguage"
        static let recentPostLanguages = "recentPostLanguages"
        static let contentTranslationMode = "contentTranslationMode"

        // Links
        static let openLinksIn = "openLinksIn"

        // Media
        static let autoplayVideoMode = "autoplayVideoMode"

        // Notification Settings
        static let receiveMentionsAndReplies = "receiveMentionsAndReplies"
        static let receiveBoosts = "receiveBoosts"
        static let receiveFavourites = "receiveFavourites"
        static let receiveNewFollowers = "receiveNewFollowers"
        static let notificationPolicy = "notificationPolicy"

        // Privacy & Safety Settings
        static let manuallyApproveFollowRequests = "manuallyApproveFollowRequests"
        static let showFollowersAndFollowing = "showFollowersAndFollowing"
        static let suggestMyAccountToOthers = "suggestMyAccountToOthers"
        static let appearInSearchEngines = "appearInSearchEngines"
        static let defaultPostVisibility = "defaultPostVisibility"

        // Timeline Detection Settings
        static let timelineInAppNewPostBannerEnabled = "timelineInAppNewPostBannerEnabled"

        // Emoji Management
        static let customEmojiGroupOrderByDomain = "customEmojiGroupOrderByDomain"

        // Pinned Timelines
        static let pinnedTimelineListsByAccount = "pinnedTimelineListsByAccount"

        // Typography & Density
        static let typographyFontScale = "typographyFontScale"
        static let timelineDensity = "timelineDensity"
    }

    // MARK: - Appearance

    enum Appearance: Int, CaseIterable {
        case system = 0
        case light = 1
        case dark = 2

        var title: String {
            switch self {
            case .system: return MoroL10n.AppSettings.appearanceSystem
            case .light: return MoroL10n.AppSettings.appearanceLight
            case .dark: return MoroL10n.AppSettings.appearanceDark
            }
        }
    }

    @Published var appearance: Appearance {
        didSet {
            userDefaults.set(appearance.rawValue, forKey: Keys.appearance)
        }
    }

    enum AppIconChoice: String, CaseIterable {
        case `default`            // geometric elephant head — the default + App Store icon
        case rainbow
        case liquidGlass
        case paintChaos
        case risoGlitch
        case tornCollage
        case appleGummy
        case zebraPrint
        case notAwake

        var title: String {
            switch self {
            case .default: return MoroL10n.AppSettings.appIconDefault
            case .rainbow: return MoroL10n.AppSettings.appIconRainbow
            case .liquidGlass: return MoroL10n.AppSettings.appIconLiquidGlass
            case .paintChaos: return MoroL10n.AppSettings.appIconPaintChaos
            case .risoGlitch: return MoroL10n.AppSettings.appIconRisoGlitch
            case .tornCollage: return MoroL10n.AppSettings.appIconTornCollage
            case .appleGummy: return MoroL10n.AppSettings.appIconAppleGummy
            case .zebraPrint: return MoroL10n.AppSettings.appIconZebraPrint
            case .notAwake: return MoroL10n.AppSettings.appIconNotAwake
            }
        }

        var alternateIconName: String? {
            switch self {
            case .default: return nil
            case .rainbow: return "AppIconRainbow"
            case .liquidGlass: return "AppIconLiquidGlass"
            case .paintChaos: return "AppIconPaintChaos"
            case .risoGlitch: return "AppIconRisoGlitch"
            case .tornCollage: return "AppIconTornCollage"
            case .appleGummy: return "AppIconAppleGummy"
            case .zebraPrint: return "AppIconZebraPrint"
            case .notAwake: return "AppIconNotAwake"
            }
        }

        var previewAssetName: String {
            switch self {
            case .default: return "AppIconPreviewDefault"
            case .rainbow: return "AppIconPreviewRainbow"
            case .liquidGlass: return "AppIconPreviewLiquidGlass"
            case .paintChaos: return "AppIconPreviewPaintChaos"
            case .risoGlitch: return "AppIconPreviewRisoGlitch"
            case .tornCollage: return "AppIconPreviewTornCollage"
            case .appleGummy: return "AppIconPreviewAppleGummy"
            case .zebraPrint: return "AppIconPreviewZebraPrint"
            case .notAwake: return "AppIconPreviewNotAwake"
            }
        }

        init?(alternateIconName: String?) {
            guard let choice = Self.allCases.first(where: { $0.alternateIconName == alternateIconName }) else {
                return nil
            }
            self = choice
        }
    }

    @Published var appIcon: AppIconChoice {
        didSet {
            userDefaults.set(appIcon.rawValue, forKey: Keys.appIcon)
        }
    }

    // MARK: - Tab Icon Theme

    enum TabIconTheme: String, CaseIterable {
        case modern
        case standard

        var title: String {
            switch self {
            case .standard: return MoroL10n.TabIconTheme.standard
            case .modern: return MoroL10n.TabIconTheme.modern
            }
        }

        var subtitle: String {
            switch self {
            case .standard: return MoroL10n.TabIconTheme.standardSubtitle
            case .modern: return MoroL10n.TabIconTheme.modernSubtitle
            }
        }

        func icon(for tab: MainTab) -> String {
            switch self {
            case .standard:
                return tab.defaultIcon
            case .modern:
                return tab.modernIcon
            }
        }

        func filledIcon(for tab: MainTab) -> String {
            switch self {
            case .standard:
                return tab.defaultFilledIcon
            case .modern:
                return tab.modernFilledIcon
            }
        }
    }

    @Published var tabIconTheme: TabIconTheme {
        didSet {
            userDefaults.set(tabIconTheme.rawValue, forKey: Keys.tabIconTheme)
        }
    }

    // MARK: - Navigation Style

    enum NavigationStyle: String, CaseIterable {
        case current
        case editorial

        var title: String {
            switch self {
            case .current: return MoroL10n.NavigationStyle.current
            case .editorial: return MoroL10n.NavigationStyle.editorial
            }
        }

        var subtitle: String {
            switch self {
            case .current: return MoroL10n.NavigationStyle.currentSubtitle
            case .editorial: return MoroL10n.NavigationStyle.editorialSubtitle
            }
        }

    }

    @Published var navigationStyle: NavigationStyle {
        didSet {
            userDefaults.set(navigationStyle.rawValue, forKey: Keys.navigationStyle)
        }
    }

    enum NavigationAppearance: String, CaseIterable {
        case modern
        case standard
        case typeBar

        var title: String {
            switch self {
            case .modern: return MoroL10n.TabIconTheme.modern
            case .standard: return MoroL10n.TabIconTheme.standard
            case .typeBar: return MoroL10n.NavigationStyle.editorial
            }
        }

        var subtitle: String {
            switch self {
            case .modern: return MoroL10n.TabIconTheme.modernSubtitle
            case .standard: return MoroL10n.TabIconTheme.standardSubtitle
            case .typeBar: return MoroL10n.NavigationStyle.editorialSubtitle
            }
        }

        var tabIconTheme: TabIconTheme {
            switch self {
            case .modern, .typeBar: return .modern
            case .standard: return .standard
            }
        }

        var navigationStyle: NavigationStyle {
            switch self {
            case .modern, .standard: return .current
            case .typeBar: return .editorial
            }
        }
    }

    static let defaultNavigationAppearance: NavigationAppearance = .standard

    var navigationAppearance: NavigationAppearance {
        if navigationStyle == .editorial {
            return .typeBar
        }
        switch tabIconTheme {
        case .standard:
            return .standard
        case .modern:
            return .modern
        }
    }

    func applyNavigationAppearance(_ appearance: NavigationAppearance) {
        tabIconTheme = appearance.tabIconTheme
        navigationStyle = appearance.navigationStyle
    }

    // MARK: - Brand Colour

    /// Moro uses one fixed monochrome product palette. Historical accent
    /// preferences are intentionally ignored after colour switching was retired.
    @Published private(set) var accentStyle: MoroAccentStyle

    // MARK: - Ask Before

    @Published var askBeforePostingWithoutAltText: Bool {
        didSet {
            userDefaults.set(
                askBeforePostingWithoutAltText, forKey: Keys.askBeforePostingWithoutAltText)
        }
    }

    @Published var askBeforeBoostingAPost: Bool {
        didSet {
            userDefaults.set(askBeforeBoostingAPost, forKey: Keys.askBeforeBoostingAPost)
        }
    }

    @Published var askBeforeUnfollowingAUser: Bool {
        didSet {
            userDefaults.set(askBeforeUnfollowingAUser, forKey: Keys.askBeforeUnfollowingSomeone)
        }
    }

    @Published var askBeforeMutingAUser: Bool {
        didSet {
            userDefaults.set(askBeforeMutingAUser, forKey: Keys.askBeforeMutingAUser)
        }
    }

    @Published var askBeforeBlockingAUser: Bool {
        didSet {
            userDefaults.set(askBeforeBlockingAUser, forKey: Keys.askBeforeBlockingAUser)
        }
    }

    @Published var askBeforeDeletingAPost: Bool {
        didSet {
            userDefaults.set(askBeforeDeletingAPost, forKey: Keys.askBeforeDeletingAPost)
        }
    }

    // MARK: - Design

    @Published var playAnimations: Bool {
        didSet {
            userDefaults.set(playAnimations, forKey: Keys.playAnimations)
        }
    }

    @Published var autoplayGIFs: Bool {
        didSet {
            userDefaults.set(autoplayGIFs, forKey: Keys.autoplayGIFs)
        }
    }

    // MARK: - Video Autoplay Mode

    enum VideoAutoplayMode: String, CaseIterable {
        case never = "never"
        case wifi = "wifi"
        case always = "always"

        var title: String {
            switch self {
            case .never: return MoroL10n.AppSettings.videoAutoplayNever
            case .wifi: return MoroL10n.AppSettings.videoAutoplayWiFi
            case .always: return MoroL10n.AppSettings.videoAutoplayAlways
            }
        }
    }

    @Published var videoAutoplayMode: VideoAutoplayMode {
        didSet {
            userDefaults.set(videoAutoplayMode.rawValue, forKey: Keys.autoplayVideoMode)
        }
    }

    // MARK: - Language

    @Published var defaultPostLanguage: String {
        didSet {
            userDefaults.set(defaultPostLanguage, forKey: Keys.defaultPostLanguage)
        }
    }

    /// The signed-in account's server-side default posting language
    /// (`source.language` from verify_credentials). Updated when the current
    /// account changes; not persisted, since it belongs to the account and is
    /// re-fetched on launch / account switch.
    @Published var serverDefaultPostLanguage: String = ""

    /// The concrete default posting language for a new post, in priority order:
    /// an explicit in-app override, then the server account default
    /// (`source.language`), then — when the server is set to "Automatic" — the
    /// app UI language, so each localized UI gets a matching default.
    var effectiveDefaultPostLanguageCode: String {
        let explicit = defaultPostLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        if !serverDefaultPostLanguage.isEmpty { return serverDefaultPostLanguage }
        return MoroAppLanguage.current
    }

    @Published var recentPostLanguageCodes: [String] {
        didSet {
            userDefaults.set(recentPostLanguageCodes, forKey: Keys.recentPostLanguages)
        }
    }

    enum ContentTranslationMode: String, CaseIterable {
        case disabled = "disabled"
        case remote = "remote"

        var localizedName: String {
            switch self {
            case .disabled:
                return MoroL10n.Translation.modeDisabled
            case .remote:
                return MoroL10n.Translation.modeRemote
            }
        }
    }

    @Published var contentTranslationMode: ContentTranslationMode {
        didSet {
            userDefaults.set(contentTranslationMode.rawValue, forKey: Keys.contentTranslationMode)
        }
    }

    func recordRecentPostLanguage(_ code: String?) {
        guard let code else { return }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let canonical = PostLanguageCatalog.canonicalLanguageCode(for: trimmed)
        guard !canonical.isEmpty else { return }

        var updated = recentPostLanguageCodes.filter {
            $0.caseInsensitiveCompare(canonical) != .orderedSame
        }
        updated.insert(canonical, at: 0)
        recentPostLanguageCodes = Array(updated.prefix(3))
    }

    // MARK: - Links

    enum OpenLinksIn: String, CaseIterable {
        // ponytail: preserve the old raw value so existing preferences keep working.
        case moro = "mastodon"
        case browser = "browser"

        var title: String {
            switch self {
            case .moro: return MoroL10n.AppSettings.openLinksInMoro
            case .browser: return MoroL10n.AppSettings.openLinksInBrowser
            }
        }
    }

    @Published var openLinksIn: OpenLinksIn {
        didSet {
            userDefaults.set(openLinksIn.rawValue, forKey: Keys.openLinksIn)
        }
    }

    // MARK: - Notification Settings

    @Published var receiveMentionsAndReplies: Bool {
        didSet {
            userDefaults.set(receiveMentionsAndReplies, forKey: Keys.receiveMentionsAndReplies)
        }
    }

    @Published var receiveBoosts: Bool {
        didSet {
            userDefaults.set(receiveBoosts, forKey: Keys.receiveBoosts)
        }
    }

    @Published var receiveFavourites: Bool {
        didSet {
            userDefaults.set(receiveFavourites, forKey: Keys.receiveFavourites)
        }
    }

    @Published var receiveNewFollowers: Bool {
        didSet {
            userDefaults.set(receiveNewFollowers, forKey: Keys.receiveNewFollowers)
        }
    }

    enum NotificationPolicy: String, CaseIterable {
        case anyone = "anyone"
        case followers = "followers"
        case followed = "followed"
        case noone = "noone"

        var localizedName: String {
            switch self {
            case .anyone: return MoroL10n.AppSettings.notificationPolicyAnyone
            case .followers: return MoroL10n.AppSettings.notificationPolicyFollowers
            case .followed: return MoroL10n.AppSettings.notificationPolicyFollowed
            case .noone: return MoroL10n.AppSettings.notificationPolicyNoOne
            }
        }
    }

    @Published var notificationPolicy: NotificationPolicy {
        didSet {
            userDefaults.set(notificationPolicy.rawValue, forKey: Keys.notificationPolicy)
        }
    }

    // MARK: - Privacy & Safety Settings

    @Published var manuallyApproveFollowRequests: Bool {
        didSet {
            userDefaults.set(
                manuallyApproveFollowRequests, forKey: Keys.manuallyApproveFollowRequests)
        }
    }

    @Published var showFollowersAndFollowing: Bool {
        didSet {
            userDefaults.set(showFollowersAndFollowing, forKey: Keys.showFollowersAndFollowing)
        }
    }

    @Published var suggestMyAccountToOthers: Bool {
        didSet {
            userDefaults.set(suggestMyAccountToOthers, forKey: Keys.suggestMyAccountToOthers)
        }
    }

    @Published var appearInSearchEngines: Bool {
        didSet {
            userDefaults.set(appearInSearchEngines, forKey: Keys.appearInSearchEngines)
        }
    }

    enum PostVisibility: String, CaseIterable {
        case `public` = "public"
        case unlisted = "unlisted"
        case followersOnly = "followers_only"
        case mentionedOnly = "direct"

        var localizedName: String {
            switch self {
            case .public: return MoroL10n.AppSettings.postVisibilityPublic
            case .unlisted: return MoroL10n.AppSettings.postVisibilityUnlisted
            case .followersOnly: return MoroL10n.AppSettings.postVisibilityFollowersOnly
            case .mentionedOnly: return MoroL10n.AppSettings.postVisibilityMentionedOnly
            }
        }

        /// Convert to MastodonVisibility for API calls.
        var mastodonVisibility: MastodonVisibility? {
            switch self {
            case .public: return .public
            case .unlisted: return .unlisted
            case .followersOnly: return .followers
            case .mentionedOnly: return .direct
            }
        }

        /// Value for `source[privacy]` on update_credentials. Mastodon uses
        /// "private" (not "followers") for the followers-only default.
        var sourcePrivacyValue: String {
            switch self {
            case .public: return "public"
            case .unlisted: return "unlisted"
            case .followersOnly: return "private"
            case .mentionedOnly: return "direct"
            }
        }
    }

    @Published var defaultPostVisibility: PostVisibility {
        didSet {
            userDefaults.set(defaultPostVisibility.rawValue, forKey: Keys.defaultPostVisibility)
        }
    }

    // MARK: - Timeline Detection Settings

    /// Whether to show in-app banner for new posts
    @Published var timelineInAppNewPostBannerEnabled: Bool {
        didSet {
            userDefaults.set(
                timelineInAppNewPostBannerEnabled, forKey: Keys.timelineInAppNewPostBannerEnabled)
        }
    }

    // MARK: - Emoji Management

    func emojiGroupOrder(for domain: String) -> [String] {
        guard !domain.isEmpty else { return [] }
        return customEmojiGroupOrderByDomain[domain] ?? []
    }

    func setEmojiGroupOrder(_ order: [String], for domain: String) {
        guard !domain.isEmpty else { return }
        var updated = customEmojiGroupOrderByDomain
        if order.isEmpty {
            updated.removeValue(forKey: domain)
        } else {
            updated[domain] = order
        }
        userDefaults.set(updated, forKey: Keys.customEmojiGroupOrderByDomain)
    }

    func resetEmojiGroupOrder(for domain: String) {
        guard !domain.isEmpty else { return }
        var updated = customEmojiGroupOrderByDomain
        updated.removeValue(forKey: domain)
        userDefaults.set(updated, forKey: Keys.customEmojiGroupOrderByDomain)
    }

    private var customEmojiGroupOrderByDomain: [String: [String]] {
        userDefaults.dictionary(forKey: Keys.customEmojiGroupOrderByDomain) as? [String: [String]] ?? [:]
    }

    // MARK: - Pinned Timelines

    /// A user list pinned into the home timeline switcher.
    struct PinnedTimelineList: Codable, Equatable, Identifiable {
        /// Mastodon list ID.
        let id: String
        var title: String
    }

    /// Pinned lists keyed by account session ID, so multi-account setups never
    /// leak one account's pinned timelines into another.
    @Published private(set) var pinnedTimelineListsByAccount: [String: [PinnedTimelineList]] {
        didSet {
            if pinnedTimelineListsByAccount.isEmpty {
                userDefaults.removeObject(forKey: Keys.pinnedTimelineListsByAccount)
            } else if let data = try? JSONEncoder().encode(pinnedTimelineListsByAccount) {
                userDefaults.set(data, forKey: Keys.pinnedTimelineListsByAccount)
            }
        }
    }

    func pinnedTimelineLists(for accountKey: String) -> [PinnedTimelineList] {
        pinnedTimelineListsByAccount[accountKey] ?? []
    }

    func isTimelineListPinned(_ listID: String, accountKey: String) -> Bool {
        pinnedTimelineLists(for: accountKey).contains { $0.id == listID }
    }

    func pinTimelineList(id: String, title: String, accountKey: String) {
        var items = pinnedTimelineLists(for: accountKey)
        guard !items.contains(where: { $0.id == id }) else { return }
        items.append(PinnedTimelineList(id: id, title: title))
        pinnedTimelineListsByAccount[accountKey] = items
    }

    func unpinTimelineList(id: String, accountKey: String) {
        var items = pinnedTimelineLists(for: accountKey)
        items.removeAll { $0.id == id }
        if items.isEmpty {
            pinnedTimelineListsByAccount.removeValue(forKey: accountKey)
        } else {
            pinnedTimelineListsByAccount[accountKey] = items
        }
    }

    /// Keep a pinned tab's title in sync when the underlying list is renamed.
    func renamePinnedTimelineList(id: String, title: String, accountKey: String) {
        guard var items = pinnedTimelineListsByAccount[accountKey],
            let index = items.firstIndex(where: { $0.id == id })
        else { return }
        items[index].title = title
        pinnedTimelineListsByAccount[accountKey] = items
    }

    // MARK: - Typography (Font Scale)

    /// In-app font scale stacked on top of the system Dynamic Type setting.
    /// A free in-app preference; `standard` is 1.0×.
    enum TypographyFontScale: String, CaseIterable {
        case extraSmall
        case small
        case standard
        case large
        case extraLarge

        /// Multiplier applied to base font sizes before Dynamic Type scaling.
        var factor: CGFloat {
            switch self {
            case .extraSmall: return 0.85
            case .small: return 0.92
            case .standard: return 1.0
            case .large: return 1.15
            case .extraLarge: return 1.30
            }
        }

        var title: String {
            switch self {
            case .extraSmall: return MoroL10n.AppSettings.typographyScaleExtraSmall
            case .small: return MoroL10n.AppSettings.typographyScaleSmall
            case .standard: return MoroL10n.AppSettings.typographyScaleStandard
            case .large: return MoroL10n.AppSettings.typographyScaleLarge
            case .extraLarge: return MoroL10n.AppSettings.typographyScaleExtraLarge
            }
        }
    }

    static let defaultTypographyFontScale: TypographyFontScale = .standard

    @Published var typographyFontScale: TypographyFontScale {
        didSet {
            userDefaults.set(typographyFontScale.rawValue, forKey: Keys.typographyFontScale)
        }
    }

    // MARK: - Timeline Density

    /// Timeline row density: line spacing, avatar size, and row padding.
    /// `comfortable` matches the pre-density defaults; `compact` tightens the rows.
    enum TimelineDensity: String, CaseIterable {
        case comfortable
        case compact

        var title: String {
            switch self {
            case .comfortable: return MoroL10n.AppSettings.densityComfortable
            case .compact: return MoroL10n.AppSettings.densityCompact
            }
        }

        var subtitle: String {
            switch self {
            case .comfortable: return MoroL10n.AppSettings.densityComfortableSubtitle
            case .compact: return MoroL10n.AppSettings.densityCompactSubtitle
            }
        }

        // Timeline row metrics.

        /// Top padding of a timeline row.
        var rowTopPadding: CGFloat {
            switch self {
            case .comfortable: return 12
            case .compact: return 10
            }
        }

        /// Bottom padding of a timeline row.
        var rowBottomPadding: CGFloat {
            switch self {
            case .comfortable: return 10
            case .compact: return 8
            }
        }

        /// Line spacing of the post body text (was the RichTextContentView default of 4).
        var contentLineSpacing: CGFloat {
            switch self {
            case .comfortable: return 3
            case .compact: return 3
            }
        }
    }

    static let defaultTimelineDensity: TimelineDensity = .comfortable

    @Published var timelineDensity: TimelineDensity {
        didSet {
            userDefaults.set(timelineDensity.rawValue, forKey: Keys.timelineDensity)
        }
    }

    // MARK: - Initialization

    private init() {
        // Appearance
        let appearanceRaw = userDefaults.integer(forKey: Keys.appearance)
        self.appearance = Appearance(rawValue: appearanceRaw) ?? .system
        let appIconRaw = userDefaults.string(forKey: Keys.appIcon) ?? AppIconChoice.default.rawValue
        self.appIcon = AppIconChoice(rawValue: appIconRaw) ?? .default
        self.tabIconTheme = Self.defaultNavigationAppearance.tabIconTheme
        self.navigationStyle = Self.defaultNavigationAppearance.navigationStyle
        self.accentStyle = .monochrome

        // Ask Before (default: true for safety)
        self.askBeforePostingWithoutAltText =
            userDefaults.object(forKey: Keys.askBeforePostingWithoutAltText) as? Bool ?? true
        self.askBeforeUnfollowingAUser =
            userDefaults.object(forKey: Keys.askBeforeUnfollowingSomeone) as? Bool ?? true
        self.askBeforeMutingAUser =
            userDefaults.object(forKey: Keys.askBeforeMutingAUser) as? Bool ?? true
        self.askBeforeBlockingAUser =
            userDefaults.object(forKey: Keys.askBeforeBlockingAUser) as? Bool ?? true
        self.askBeforeBoostingAPost =
            userDefaults.object(forKey: Keys.askBeforeBoostingAPost) as? Bool ?? false
        self.askBeforeDeletingAPost =
            userDefaults.object(forKey: Keys.askBeforeDeletingAPost) as? Bool ?? true

        // Design (default: true for better UX)
        self.playAnimations = userDefaults.object(forKey: Keys.playAnimations) as? Bool ?? true
        self.autoplayGIFs = userDefaults.object(forKey: Keys.autoplayGIFs) as? Bool ?? true

        // Video Autoplay Mode (default: wifi)
        if let modeRaw = userDefaults.string(forKey: Keys.autoplayVideoMode),
            let mode = VideoAutoplayMode(rawValue: modeRaw)
        {
            self.videoAutoplayMode = mode
        } else {
            self.videoAutoplayMode = .wifi
        }

        // Language (default: empty, use system)
        self.defaultPostLanguage = userDefaults.string(forKey: Keys.defaultPostLanguage) ?? ""
        self.recentPostLanguageCodes =
            userDefaults.stringArray(forKey: Keys.recentPostLanguages)?
            .compactMap { rawCode in
                let normalized = PostLanguageCatalog.canonicalLanguageCode(for: rawCode)
                return normalized.isEmpty ? nil : normalized
            } ?? []
        if let translationModeRaw = userDefaults.string(forKey: Keys.contentTranslationMode),
            let translationMode = ContentTranslationMode(rawValue: translationModeRaw)
        {
            self.contentTranslationMode = translationMode
        } else {
            self.contentTranslationMode = .remote
        }

        // Links (default: Moro)
        if let linksRaw = userDefaults.string(forKey: Keys.openLinksIn),
            let links = OpenLinksIn(rawValue: linksRaw)
        {
            self.openLinksIn = links
        } else {
            self.openLinksIn = .moro
        }

        // Notification Settings (default: all enabled, policy: anyone)
        self.receiveMentionsAndReplies =
            userDefaults.object(forKey: Keys.receiveMentionsAndReplies) as? Bool ?? true
        self.receiveBoosts = userDefaults.object(forKey: Keys.receiveBoosts) as? Bool ?? true
        self.receiveFavourites =
            userDefaults.object(forKey: Keys.receiveFavourites) as? Bool ?? true
        self.receiveNewFollowers =
            userDefaults.object(forKey: Keys.receiveNewFollowers) as? Bool ?? true

        if let policyRaw = userDefaults.string(forKey: Keys.notificationPolicy),
            let policy = NotificationPolicy(rawValue: policyRaw)
        {
            self.notificationPolicy = policy
        } else {
            self.notificationPolicy = .anyone
        }

        // Privacy & Safety Settings (default: open/public settings)
        self.manuallyApproveFollowRequests =
            userDefaults.object(forKey: Keys.manuallyApproveFollowRequests) as? Bool ?? false
        self.showFollowersAndFollowing =
            userDefaults.object(forKey: Keys.showFollowersAndFollowing) as? Bool ?? true
        self.suggestMyAccountToOthers =
            userDefaults.object(forKey: Keys.suggestMyAccountToOthers) as? Bool ?? true
        self.appearInSearchEngines =
            userDefaults.object(forKey: Keys.appearInSearchEngines) as? Bool ?? true

        if let visibilityRaw = userDefaults.string(forKey: Keys.defaultPostVisibility),
            let visibility = PostVisibility(rawValue: visibilityRaw)
        {
            self.defaultPostVisibility = visibility
        } else {
            self.defaultPostVisibility = .public
        }

        // Timeline Detection Settings (default: banner on)
        self.timelineInAppNewPostBannerEnabled =
            userDefaults.object(forKey: Keys.timelineInAppNewPostBannerEnabled) as? Bool ?? true

        // Pinned Timelines (default: none)
        if let pinnedData = userDefaults.data(forKey: Keys.pinnedTimelineListsByAccount),
            let pinned = try? JSONDecoder().decode(
                [String: [PinnedTimelineList]].self, from: pinnedData)
        {
            self.pinnedTimelineListsByAccount = pinned
        } else {
            self.pinnedTimelineListsByAccount = [:]
        }

        // Hidden appearance controls use stable defaults until product tuning returns.
        self.typographyFontScale = Self.defaultTypographyFontScale
        self.timelineDensity = Self.defaultTimelineDensity

        // Replace legacy values so removed controls cannot continue affecting the UI.
        userDefaults.set(tabIconTheme.rawValue, forKey: Keys.tabIconTheme)
        userDefaults.set(navigationStyle.rawValue, forKey: Keys.navigationStyle)
        userDefaults.set(typographyFontScale.rawValue, forKey: Keys.typographyFontScale)
        userDefaults.set(timelineDensity.rawValue, forKey: Keys.timelineDensity)
    }
}
