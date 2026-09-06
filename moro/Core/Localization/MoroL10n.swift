//
//  MoroL10n.swift
//  moro
//
//  Centralized string accessors backed by the Moro string catalog.
//

import Foundation

public enum MoroL10n {
    private static let tableName = "Moro"
    private static let moduleBundle = Bundle.module

    /// Locale matching the localization the catalog actually resolves to, so
    /// language display names render in the app's language. Follows the
    /// system / per-app language setting like the strings themselves do.
    static var preferredLocale: Locale {
        Locale(identifier: moduleBundle.preferredLocalizations.first ?? "en")
    }

    private static func text(_ key: String) -> String {
        NSLocalizedString(
            key,
            tableName: tableName,
            bundle: moduleBundle,
            value: key,
            comment: ""
        )
    }

    private static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: text(key),
            locale: Locale.autoupdatingCurrent,
            arguments: arguments
        )
    }

    public enum ProfileEditing {
        public static var featuredTags: String { text("profileEditing.featuredTags") }
        public static var displaySettings: String { text("profileEditing.displaySettings") }
        public static var showTags: String { text("profileEditing.showTags") }
        public static var showTagsHint: String { text("profileEditing.showTagsHint") }
        public static var showMedia: String { text("profileEditing.showMedia") }
        public static var showMediaReplies: String { text("profileEditing.showMediaReplies") }
        public static var showFeaturedWeb: String { text("profileEditing.showFeaturedWeb") }
        public static var showFeaturedWebHint: String { text("profileEditing.showFeaturedWebHint") }
        public static var unsupported: String { text("profileEditing.unsupported") }
        public static var sourceUnavailable: String { text("profileEditing.sourceUnavailable") }
        public static var fieldsChangedElsewhere: String { text("profileEditing.fieldsChangedElsewhere") }
        public static var fieldOrderHint: String { text("profileEditing.fieldOrderHint") }
        public static var editField: String { text("profileEditing.editField") }
        public static var emptyFields: String { text("profileEditing.emptyFields") }
        public static var emptyTags: String { text("profileEditing.emptyTags") }
        public static var tagPlaceholder: String { text("profileEditing.tagPlaceholder") }
        public static var suggestions: String { text("profileEditing.suggestions") }
        public static var tagHint: String { text("profileEditing.tagHint") }
        public static var immediateSave: String { text("profileEditing.immediateSave") }
        public static var addTag: String { text("profileEditing.addTag") }
        public static var limitReached: String { text("profileEditing.limitReached") }
        public static var invalidTag: String { text("profileEditing.invalidTag") }
        public static var limitsExceeded: String { text("profileEditing.limitsExceeded") }
        public static var filteredEmpty: String { text("profileEditing.filteredEmpty") }
        public static var clearFilter: String { text("profileEditing.clearFilter") }
    }

    public enum Topics {
        public static var title: String { text("topics.title") }
        public static var follow: String { text("topics.follow") }
        public static var following: String { text("topics.following") }
        public static var unfollow: String { text("topics.unfollow") }
        public static var empty: String { text("topics.empty") }
        public static var homeHint: String { text("topics.homeHint") }
        public static var actionFailed: String { text("topics.actionFailed") }
        public static var loadFailed: String { text("topics.loadFailed") }
        public static var loadMore: String { text("topics.loadMore") }
    }

    public enum ComposeReading {
        public static var expand: String { text("composeReading.expand") }
        public static var collapse: String { text("composeReading.collapse") }
        public static var preview: String { text("composeReading.preview") }
        public static var mediaOrder: String { text("composeReading.mediaOrder") }
        public static var options: String { text("composeReading.options") }
        public static func attachment(_ index: Int) -> String { format("composeReading.attachment", index) }
        public static var uploadPending: String { text("composeReading.uploadPending") }
        public static var moveUp: String { text("composeReading.moveUp") }
        public static var moveDown: String { text("composeReading.moveDown") }
        public static var orderHint: String { text("composeReading.orderHint") }
    }

    public enum ThreadReading {
        public static var options: String { text("threadReading.options") }
        public static var authorOnly: String { text("threadReading.authorOnly") }
        public static var authorOnlyHint: String { text("threadReading.authorOnlyHint") }
        public static var returnToPost: String { text("threadReading.returnToPost") }
        public static var expandAll: String { text("threadReading.expandAll") }
        public static func parent(_ name: String) -> String { format("threadReading.parent", name) }
        public static func expand(_ count: Int) -> String { format("threadReading.expand", count) }
        public static func collapse(_ count: Int) -> String { format("threadReading.collapse", count) }
    }

    public enum BookmarkReading {
        public static var all: String { text("bookmarkReading.all") }
        public static var unread: String { text("bookmarkReading.unread") }
        public static var read: String { text("bookmarkReading.read") }
        public static var markRead: String { text("bookmarkReading.markRead") }
        public static var markUnread: String { text("bookmarkReading.markUnread") }
        public static var search: String { text("bookmarkReading.search") }
        public static var scope: String { text("bookmarkReading.scope") }
        public static var offline: String { text("bookmarkReading.offline") }
        public static var noMatches: String { text("bookmarkReading.noMatches") }
        public static var loadMore: String { text("bookmarkReading.loadMore") }
        public static var actions: String { text("bookmarkReading.actions") }
    }

    public enum Common {
        public static var cancel: String { text("common.cancel") }
        public static var close: String { text("common.close") }
        public static var delete: String { text("common.delete") }
        public static var done: String { text("common.done") }
        public static var ok: String { text("common.ok") }
        public static var save: String { text("common.save") }
        public static var loadMoreRetry: String { text("common.loadMoreRetry") }
    }

    public enum Navigation {
        public static var home: String { text("nav.tab.home") }
        public static var search: String { text("nav.tab.search") }
        public static var explore: String { text("nav.tab.explore") }
        public static var compose: String { text("nav.tab.compose") }
        public static var notifications: String { text("nav.tab.notifications") }
        public static var messages: String { text("nav.tab.messages") }
        public static var inbox: String { text("nav.tab.inbox") }
        public static var me: String { text("nav.tab.me") }
        public static var favourites: String { text("nav.drawer.favourites") }
        public static var bookmarks: String { text("nav.drawer.bookmarks") }
        public static var lists: String { text("nav.drawer.lists") }
        public static var scheduled: String { text("nav.drawer.scheduled") }
        public static var profileCenter: String { text("nav.drawer.profileCenter") }
        public static var instanceDetails: String { text("nav.drawer.instanceDetails") }
        public static var settings: String { text("nav.drawer.settings") }
        public static var openProfileCenter: String { text("nav.accessibility.openProfileCenter") }

        public static func notificationsUnread(_ count: Int) -> String {
            format("nav.tab.notifications.unread", Int64(count))
        }

        public static func messagesUnread(_ count: Int) -> String {
            format("nav.tab.messages.unread", Int64(count))
        }

        public static func inboxUnread(_ count: Int) -> String {
            format("nav.tab.inbox.unread", Int64(count))
        }

        public static func followingCount(_ count: Int) -> String {
            format("nav.account.following.count", Int64(count))
        }

        public static func followersCount(_ count: Int) -> String {
            format("nav.account.followers.count", Int64(count))
        }
    }

    public enum Settings {
        public static var title: String { text("settings.title") }
        public static var accountPrivacySection: String { text("settings.section.accountPrivacy") }
        public static var appSection: String { text("settings.section.app") }
        public static var aboutSection: String { text("settings.section.about") }
        public static var serverSection: String { text("settings.section.server") }
        public static var accountActionsSection: String { text("settings.section.accountActions") }
        public static var accountManagement: String { text("settings.row.accountManagement") }
        public static var switchAccount: String { text("settings.row.switchAccount") }
        public static var notificationsSubscriptions: String { text("settings.row.notificationsSubscriptions") }
        public static var privacySafety: String { text("settings.row.privacySafety") }
        public static var thisServer: String { text("settings.row.thisServer") }
        public static var appPreferences: String { text("settings.row.appPreferences") }
        public static var timeline: String { text("settings.row.timeline") }
        public static var emojiManagement: String { text("settings.row.emojiManagement") }
        public static var theme: String { text("settings.row.theme") }
        public static var appearance: String { text("settings.row.appearance") }
        public static var generalSection: String { text("settings.section.general") }
        public static var confirmBeforeAction: String { text("settings.row.confirmBeforeAction") }
        public static var feedback: String { text("settings.row.feedback") }
        public static var aboutMoro: String { text("settings.row.aboutMoro") }
        public static var logout: String { text("settings.row.logout") }
        public static var closeAccessibilityLabel: String { text("settings.accessibility.close") }
        public static var logoutAlertTitle: String { text("settings.alert.logout.title") }
        public static var logoutAlertMessage: String { text("settings.alert.logout.message") }
        public static var logoutAction: String { text("settings.action.logout") }
        public static var feedbackDialogTitle: String { text("settings.feedback.dialog.title") }
        public static var feedbackInApp: String { text("settings.feedback.option.inApp") }
        public static var feedbackMailApp: String { text("settings.feedback.option.mailApp") }

        public static var appearanceThemeSection: String { text("settings.section.appearanceTheme") }
        public static var readingBrowsingSection: String { text("settings.section.readingBrowsing") }
        public static var confirmActionsSection: String { text("settings.section.confirmActions") }

        public static var feedbackMailLinkError: String { text("settings.toast.feedbackMailLinkError") }
        public static var feedbackMailAppError: String { text("settings.toast.feedbackMailAppError") }
        public static var feedbackMailSent: String { text("settings.toast.feedbackMailSent") }
        public static var feedbackMailSaved: String { text("settings.toast.feedbackMailSaved") }
        public static var feedbackMailFailed: String { text("settings.toast.feedbackMailFailed") }

        public static func feedbackDestination(_ email: String) -> String {
            format("settings.feedback.destination", email)
        }
    }

    public enum GeneralSettings {
        public static var title: String { text("general.title") }
        public static var appearanceSection: String { text("general.section.appearance") }
        public static var appIconSection: String { text("general.section.appIcon") }
        public static var confirmBeforeActionSection: String { text("general.section.confirmBeforeAction") }
        public static var designSection: String { text("general.section.design") }
        public static var languageSection: String { text("general.section.language") }
        public static var linksSection: String { text("general.section.links") }
        public static var switchingIconFooter: String { text("general.footer.switchingIcon") }
        public static var iconAppliesFooter: String { text("general.footer.iconApplies") }
        public static var autoplayFooter: String { text("general.footer.autoplayVideo") }
        public static var askBeforePostingWithoutAltText: String { text("general.toggle.askAlt") }
        public static var askBeforeUnfollow: String { text("general.toggle.askUnfollow") }
        public static var askBeforeMute: String { text("general.toggle.askMute") }
        public static var askBeforeBlock: String { text("general.toggle.askBlock") }
        public static var askBeforeBoost: String { text("general.toggle.askBoost") }
        public static var askBeforeDelete: String { text("general.toggle.askDelete") }
        public static var playAnimations: String { text("general.toggle.playAnimations") }
        public static var autoplayGIFs: String { text("general.toggle.autoplayGifs") }
        public static var videoAutoplayMode: String { text("general.label.videoAutoplayMode") }
        public static var defaultPostLanguage: String { text("general.label.defaultPostLanguage") }
        public static var openLinksIn: String { text("general.label.openLinksIn") }
        public static var iconSwitchFailed: String { text("general.alert.iconSwitchFailed") }
        public static var retryLater: String { text("general.alert.retryLater") }
        public static var iconSwitchError: String { text("general.toast.iconSwitchError") }
        public static var languageLinksSection: String { text("general.section.languageLinks") }
        public static var newPostBanner: String { text("general.toggle.newPostBanner") }
        public static var timelineMediaSection: String { text("general.section.timelineMedia") }
        public static var timelineMediaFooter: String { text("general.footer.timelineMedia") }
    }

    public enum AppSettings {
        public static var appearanceSystem: String { text("appsettings.appearance.system") }
        public static var appearanceLight: String { text("appsettings.appearance.light") }
        public static var appearanceDark: String { text("appsettings.appearance.dark") }
        public static var appIconDefault: String { text("appsettings.icon.default") }
        public static var appIconClassic: String { text("appsettings.icon.classic") }
        public static var appIconLineElephant: String { text("appsettings.icon.lineElephant") }
        public static var appIconRainbow: String { text("appsettings.icon.rainbow") }
        public static var appIconLiquidGlass: String { text("appsettings.icon.liquidGlass") }
        public static var appIconPaintChaos: String { text("appsettings.icon.paintChaos") }
        public static var appIconRisoGlitch: String { text("appsettings.icon.risoGlitch") }
        public static var appIconTornCollage: String { text("appsettings.icon.tornCollage") }
        public static var videoAutoplayNever: String { text("appsettings.videoAutoplay.never") }
        public static var videoAutoplayWiFi: String { text("appsettings.videoAutoplay.wifi") }
        public static var videoAutoplayAlways: String { text("appsettings.videoAutoplay.always") }
        public static var openLinksInMoro: String { text("appsettings.links.moro") }
        public static var openLinksInBrowser: String { text("appsettings.links.browser") }
        public static var notificationPolicyAnyone: String { text("appsettings.notificationPolicy.anyone") }
        public static var notificationPolicyFollowers: String { text("appsettings.notificationPolicy.followers") }
        public static var notificationPolicyFollowed: String { text("appsettings.notificationPolicy.followed") }
        public static var notificationPolicyNoOne: String { text("appsettings.notificationPolicy.noone") }
        public static var postVisibilityPublic: String { text("appsettings.postVisibility.public") }
        public static var postVisibilityUnlisted: String { text("appsettings.postVisibility.unlisted") }
        public static var postVisibilityFollowersOnly: String {
            text("appsettings.postVisibility.followersOnly")
        }
        public static var postVisibilityMentionedOnly: String {
            text("appsettings.postVisibility.mentionedOnly")
        }
        public static var typographySection: String { text("appsettings.typography.section") }
        public static var typographyFooter: String { text("appsettings.typography.footer") }
        public static var typographyScaleExtraSmall: String {
            text("appsettings.typography.scale.extraSmall")
        }
        public static var typographyScaleSmall: String { text("appsettings.typography.scale.small") }
        public static var typographyScaleStandard: String {
            text("appsettings.typography.scale.standard")
        }
        public static var typographyScaleLarge: String { text("appsettings.typography.scale.large") }
        public static var typographyScaleExtraLarge: String {
            text("appsettings.typography.scale.extraLarge")
        }
        public static var densitySection: String { text("appsettings.density.section") }
        public static var densityComfortable: String { text("appsettings.density.comfortable") }
        public static var densityComfortableSubtitle: String {
            text("appsettings.density.comfortable.subtitle")
        }
        public static var densityCompact: String { text("appsettings.density.compact") }
        public static var densityCompactSubtitle: String {
            text("appsettings.density.compact.subtitle")
        }
    }

    public enum Compose {
        public static var editSourceLoading: String { text("compose.editSource.loading") }
        public static var editSourceFailed: String { text("compose.editSource.failed") }
        public static var navigationNewPost: String { text("compose.navigation.newPost") }
        public static var navigationReply: String { text("compose.navigation.reply") }
        public static var navigationQuote: String { text("compose.navigation.quote") }
        public static var navigationEdit: String { text("compose.navigation.edit") }
        public static var actionPublish: String { text("compose.action.publish") }
        public static var actionPublishing: String { text("compose.action.publishing") }
        public static var actionSchedulePublish: String { text("compose.action.schedulePublish") }
        public static var actionScheduling: String { text("compose.action.scheduling") }
        public static var continuePublish: String { text("compose.action.continuePublish") }
        public static var missingAltTitle: String { text("compose.alert.missingAlt.title") }
        public static var missingAltMessage: String { text("compose.alert.missingAlt.message") }
        public static var optionVisibility: String { text("compose.option.visibility") }
        public static var optionQuote: String { text("compose.option.quote") }
        public static var optionSchedule: String { text("compose.option.schedule") }
        public static var optionScheduleImmediate: String { text("compose.option.scheduleImmediate") }
        public static var optionScheduleDate: String { text("compose.option.scheduleDate") }
        public static var optionLanguage: String { text("compose.option.language") }
        public static var successPosted: String { text("compose.success.posted") }
        public static var validationMediaUploading: String { text("compose.validation.mediaUploading") }
        public static var validationMediaUploadFailed: String { text("compose.validation.mediaUploadFailed") }
        public static var validationPollNeedsMoreOptions: String {
            text("compose.validation.pollNeedsMoreOptions")
        }
        public static var validationPollCannotIncludeMedia: String {
            text("compose.validation.pollCannotIncludeMedia")
        }
        public static var errorEmptyContent: String { text("compose.error.emptyContent") }
        public static var errorAlreadyPublishing: String { text("compose.error.alreadyPublishing") }
        public static var errorMediaUploading: String { text("compose.error.mediaUploading") }
        public static var errorUploadFailed: String { text("compose.error.uploadFailed") }
        public static var errorCharacterLimitExceeded: String {
            text("compose.error.characterLimitExceeded")
        }
        public static var errorInvalidPoll: String { text("compose.error.invalidPoll") }
        public static var errorPollCannotIncludeMedia: String {
            text("compose.error.pollCannotIncludeMedia")
        }
        public static var errorInvalidScheduledDate: String {
            text("compose.error.invalidScheduledDate")
        }
        public static var minimumScheduleHint: String { text("compose.schedule.minimum") }
        public static var scheduleTitle: String { text("compose.schedule.title") }
        public static var schedulePublishNow: String { text("compose.schedule.publishNow") }
        public static var scheduleConfirm: String { text("compose.schedule.confirm") }
        public static var scheduleClear: String { text("compose.schedule.clear") }

        public static func scheduleHint(_ dateText: String) -> String {
            format("compose.schedule.hint", dateText)
        }

        public static func scheduleSummary(_ dateText: String) -> String {
            format("compose.schedule.summary", dateText)
        }

        public static func scheduleSuccess(_ dateText: String) -> String {
            format("compose.schedule.success", dateText)
        }

        // Placeholder
        public static var placeholderNewPost: String { text("compose.placeholder.newPost") }
        public static var placeholderReply: String { text("compose.placeholder.reply") }
        public static var placeholderQuote: String { text("compose.placeholder.quote") }
        public static var placeholderEdit: String { text("compose.placeholder.edit") }

        // Content warning
        public static var contentWarningPlaceholder: String { text("compose.contentWarning.placeholder") }

        // Reply hint
        public static var replyHint: String { text("compose.replyHint") }

        // Context card chips
        public static var chipPollMode: String { text("compose.chip.pollMode") }
        public static var chipContentWarningActive: String { text("compose.chip.contentWarningActive") }

        public static func chipMediaCount(_ count: Int) -> String {
            format("compose.chip.mediaCount", count)
        }

        public static func chipMissingAltText(_ count: Int) -> String {
            format("compose.chip.missingAltText", count)
        }

        public static func chipUploading(_ count: Int) -> String {
            format("compose.chip.uploading", count)
        }

        // Poll
        public static var pollTitle: String { text("compose.poll.title") }
        public static var pollAddOption: String { text("compose.poll.addOption") }
        public static var pollAllowMultiple: String { text("compose.poll.allowMultiple") }
        public static var pollDuration: String { text("compose.poll.duration") }
        public static var pollDurationFallback: String { text("compose.poll.durationFallback") }

        public static func pollOptionPlaceholder(_ index: Int) -> String {
            format("compose.poll.optionPlaceholder", index)
        }

        // Media toolbar
        public static var mediaPhotoLibrary: String { text("compose.media.photoLibrary") }
        public static var mediaTakePhotoOrVideo: String { text("compose.media.takePhotoOrVideo") }
        public static var mediaBrowseFiles: String { text("compose.media.browseFiles") }

        // Visibility
        public static var visibilityPublic: String { text("compose.visibility.public") }
        public static var visibilityUnlisted: String { text("compose.visibility.unlisted") }
        public static var visibilityFollowersOnly: String { text("compose.visibility.followersOnly") }
        public static var visibilityMentionedOnly: String { text("compose.visibility.mentionedOnly") }

        // Quote policy
        public static var quotePolicyAnyone: String { text("compose.quotePolicy.anyone") }
        public static var quotePolicyFollowers: String { text("compose.quotePolicy.followers") }
        public static var quotePolicySelfOnly: String { text("compose.quotePolicy.selfOnly") }
        public static var quotePolicyLabelAllow: String { text("compose.quotePolicy.label.allow") }
        public static var quotePolicyLabelFollowers: String { text("compose.quotePolicy.label.followers") }
        public static var quotePolicyLabelNone: String { text("compose.quotePolicy.label.none") }

        // Language quick menu
        public static var langCurrentDefault: String { text("compose.language.currentDefault") }
        public static var langCurrentSelection: String { text("compose.language.currentSelection") }
        public static var langRecentlyUsed: String { text("compose.language.recentlyUsed") }
        public static var langMore: String { text("compose.language.more") }
        public static var langMoreLanguages: String { text("compose.language.moreLanguages") }

        // Emoji picker
        public static var emojiLoading: String { text("compose.emoji.loading") }
        public static var emojiLoadFailed: String { text("compose.emoji.loadFailed") }

        // Retry
        public static var retry: String { text("compose.retry") }

        // Accessibility
        public static var accessibilityCharacterProgress: String { text("compose.accessibility.characterProgress") }

        // Toast / feedback messages
        public static var toastPollMediaConflict: String { text("compose.toast.pollMediaConflict") }
        public static var toastImageProcessFailed: String { text("compose.toast.imageProcessFailed") }
        public static var toastMediaCannotRetry: String { text("compose.toast.mediaCannotRetry") }
        public static var toastMediaUploadFailed: String { text("compose.toast.mediaUploadFailed") }
        public static var toastImportFailed: String { text("compose.toast.importFailed") }
        public static var toastImportComplete: String { text("compose.toast.importComplete") }
        public static var toastImportPartial: String { text("compose.toast.importPartial") }
        public static var toastAuthorMentionFailed: String { text("compose.toast.authorMentionFailed") }
        public static var toastFileAccessFailed: String { text("compose.toast.fileAccessFailed") }
        public static var toastFileReadFailed: String { text("compose.toast.fileReadFailed") }

        // Publish status messages
        public static func statusMediaUploadFailed(_ count: Int) -> String {
            format("compose.status.mediaUploadFailed", count)
        }

        public static func statusCharacterExceeded(_ count: Int) -> String {
            format("compose.status.characterExceeded", count)
        }

        public static func statusMediaUploading(_ count: Int) -> String {
            format("compose.status.mediaUploading", count)
        }

        // MARK: A11y labels for icon-only toolbar buttons
        public static var toolbarMedia: String { text("compose.toolbar.media") }
        public static var toolbarPoll: String { text("compose.toolbar.poll") }
        public static var toolbarContentWarning: String { text("compose.toolbar.contentWarning") }
        public static var toolbarEmoji: String { text("compose.toolbar.emoji") }
        public static var toolbarDrafts: String { text("compose.toolbar.drafts") }
        public static var toolbarSchedule: String { text("compose.toolbar.schedule") }
        public static var toolbarLanguage: String { text("compose.toolbar.language") }
    }

    public enum ComposeDrafts {
        public static var navigationTitle: String { text("compose.drafts.navigationTitle") }
        public static var emptyTitle: String { text("compose.drafts.empty.title") }
        public static var emptyMessage: String { text("compose.drafts.empty.message") }
        public static var badgeManual: String { text("compose.drafts.badge.manual") }
        public static var badgeAuto: String { text("compose.drafts.badge.auto") }
        public static var contextNewPost: String { text("compose.drafts.context.newPost") }
        public static var contextReply: String { text("compose.drafts.context.reply") }
        public static var contextQuote: String { text("compose.drafts.context.quote") }
        public static var untitled: String { text("compose.drafts.untitled") }
        public static var pollBadge: String { text("compose.drafts.pollBadge") }
        public static var saveFailed: String { text("compose.drafts.saveFailed") }
        public static var saved: String { text("compose.drafts.saved") }
        public static var restored: String { text("compose.drafts.restored") }
        public static var savedAfterFailure: String { text("compose.drafts.savedAfterFailure") }
        public static var redraftMediaOmitted: String { text("compose.drafts.redraft.mediaOmitted") }
        public static var discardTitle: String { text("compose.drafts.discard.title") }
        public static var discardAction: String { text("compose.drafts.discard.action") }
        public static var saveDraftAction: String { text("compose.drafts.saveDraft.action") }
        public static var deleteConfirmTitle: String { text("post.delete.confirm.title") }
        public static var deleteConfirmMessage: String { text("post.delete.confirm.message") }
        public static var deleteAction: String { text("post.delete.action.confirm") }
        public static var deleteAndRedraftAction: String { text("post.delete.action.redraft") }
    }

    public enum Language {
        public static var systemDefault: String { text("language.systemDefault") }
        public static var defaultPickerTitle: String { text("language.picker.defaultTitle") }
        public static var composePickerTitle: String { text("language.picker.composeTitle") }
        public static var searchPrompt: String { text("language.picker.search") }

        public static func followAppDefault(_ currentDefault: String) -> String {
            format("language.picker.followAppDefault", currentDefault)
        }

        public static func followAccountDefault(_ currentDefault: String) -> String {
            format("language.picker.followAccountDefault", currentDefault)
        }
    }

    public enum Notifications {
        // Page
        public static var title: String { text("notifications.title") }
        public static var notificationToggleEnable: String { text("notificationToggle.enable") }
        public static var notificationToggleDisable: String { text("notificationToggle.disable") }

        // Filters
        public static var filterAll: String { text("notifications.filter.all") }
        public static var filterInteractions: String { text("notifications.filter.interactions") }
        public static var filterMentions: String { text("notifications.filter.mentions") }
        public static var filterFollows: String { text("notifications.filter.follows") }
        public static var filterUpdates: String { text("notifications.filter.updates") }
        public static var accessibilityFilter: String { text("notifications.accessibility.filter") }

        // Date sections
        public static var sectionToday: String { text("notifications.section.today") }
        public static var sectionYesterday: String { text("notifications.section.yesterday") }
        public static var sectionEarlier: String { text("notifications.section.earlier") }

        public static var accessibilityFilterSelected: String { text("notifications.accessibility.filterSelected") }

        public static func accessibilityFilterSwitch(_ filter: String) -> String {
            format("notifications.accessibility.filterSwitch", filter)
        }

        // Action text
        public static var actionFollowed: String { text("notifications.action.followed") }
        public static var actionFollowRequest: String { text("notifications.action.followRequest") }
        public static var actionMentioned: String { text("notifications.action.mentioned") }
        public static var actionReplied: String { text("notifications.action.replied") }
        public static var actionReblogged: String { text("notifications.action.reblogged") }
        public static var actionFavourited: String { text("notifications.action.favourited") }
        public static var actionQuoted: String { text("notifications.action.quoted") }
        public static var actionQuotedUpdate: String { text("notifications.action.quotedUpdate") }
        public static var actionPollEnded: String { text("notifications.action.pollEnded") }
        public static var actionNewStatus: String { text("notifications.action.newStatus") }
        public static var actionEdited: String { text("notifications.action.edited") }
        public static var actionSignUp: String { text("notifications.action.signUp") }
        public static var actionReport: String { text("notifications.action.report") }
        public static var actionSeveredRelationships: String { text("notifications.action.severedRelationships") }
        public static var actionWarning: String { text("notifications.action.warning") }
        public static var actionAddedToCollection: String { text("notifications.action.addedToCollection") }
        public static var actionCollectionUpdated: String { text("notifications.action.collectionUpdated") }
        public static var actionUnknown: String { text("notifications.action.unknown") }

        public static func actionMultiActor(_ count: Int, _ action: String) -> String {
            format("notifications.action.multiActor", count, action)
        }

        // Badge text
        public static var badgeFollow: String { text("notifications.badge.follow") }
        public static var badgeFollowRequest: String { text("notifications.badge.followRequest") }
        public static var badgeMention: String { text("notifications.badge.mention") }
        public static var badgeReblog: String { text("notifications.badge.reblog") }
        public static var badgeFavourite: String { text("notifications.badge.favourite") }
        public static var badgeQuote: String { text("notifications.badge.quote") }
        public static var badgeQuotedUpdate: String { text("notifications.badge.quotedUpdate") }
        public static var badgePoll: String { text("notifications.badge.poll") }
        public static var badgeNewStatus: String { text("notifications.badge.newStatus") }
        public static var badgeEdit: String { text("notifications.badge.edit") }
        public static var badgeSignUp: String { text("notifications.badge.signUp") }
        public static var badgeReport: String { text("notifications.badge.report") }
        public static var badgeSeveredRelationships: String { text("notifications.badge.severedRelationships") }
        public static var badgeWarning: String { text("notifications.badge.warning") }
        public static var badgeUnknown: String { text("notifications.badge.unknown") }

        // Follow request actions
        public static var accept: String { text("notifications.followRequest.accept") }
        public static var reject: String { text("notifications.followRequest.reject") }
        public static var acceptAccessibility: String { text("notifications.followRequest.acceptAccessibility") }
        public static var rejectAccessibility: String { text("notifications.followRequest.rejectAccessibility") }

        // Status preview
        public static var unknownUser: String { text("notifications.unknownUser") }
        public static var editedPost: String { text("notifications.preview.editedPost") }
        public static var yourQuotedPost: String { text("notifications.preview.yourQuotedPost") }
        public static var yourQuotePost: String { text("notifications.preview.yourQuotePost") }
        public static var theirEditedPost: String { text("notifications.preview.theirEditedPost") }
        public static var quotedContext: String { text("notifications.preview.quotedContext") }
        public static var noTextContent: String { text("notifications.preview.noTextContent") }
        public static var containsPoll: String { text("notifications.preview.containsPoll") }
        public static var containsQuote: String { text("notifications.preview.containsQuote") }
        public static var replyContextFull: String { text("notifications.preview.replyContextFull") }

        public static func mediaAttachmentCount(_ count: Int) -> String {
            format("notifications.preview.mediaAttachmentCount", count)
        }

        public static func replyContext(_ acct: String) -> String {
            format("notifications.preview.replyContext", acct)
        }

        // Accessibility
        public static var accessibilityActorList: String { text("notifications.accessibility.actorList") }
        public static var accessibilityOpenProfile: String { text("notifications.accessibility.openProfile") }

        // Toast messages
        public static var toastAccepted: String { text("notifications.toast.accepted") }
        public static var toastAcceptFailed: String { text("notifications.toast.acceptFailed") }
        public static var toastRejected: String { text("notifications.toast.rejected") }
        public static var toastRejectFailed: String { text("notifications.toast.rejectFailed") }

        // Empty states
        public static var loadFailed: String { text("notifications.empty.loadFailed") }
        public static var retryAction: String { text("notifications.empty.retry") }
        public static var hiddenByPolicy: String { text("notifications.empty.hiddenByPolicy") }
        public static var refreshAction: String { text("notifications.empty.refresh") }
        public static var emptyTitle: String { text("notifications.empty.title") }
        public static var emptyMessage: String { text("notifications.empty.message") }
        public static var filteredEmptyTitle: String { text("notifications.empty.filteredTitle") }
        public static var filteredEmptyNoContent: String { text("notifications.empty.filteredNoContent") }
        public static var filteredEmptyMessage: String { text("notifications.empty.filteredMessage") }
        public static var viewAll: String { text("notifications.empty.viewAll") }

        // Actor list header
        public static var actorListFavouriters: String { text("notifications.actorList.favouriters") }
        public static var actorListRebloggers: String { text("notifications.actorList.rebloggers") }
        public static var actorListFollowers: String { text("notifications.actorList.followers") }
        public static var actorListFollowRequesters: String { text("notifications.actorList.followRequesters") }
        public static var actorListRelated: String { text("notifications.actorList.related") }

        // Policy insight
        public static func policyHiddenByType(_ count: Int) -> String {
            format("notifications.policy.hiddenByType", count)
        }

        public static func policyHiddenBySource(_ count: Int) -> String {
            format("notifications.policy.hiddenBySource", count)
        }

        public static var policyDefaultMessage: String { text("notifications.policy.defaultMessage") }

        public static func policySettingsHint(_ reasonText: String) -> String {
            format("notifications.policy.settingsHint", reasonText)
        }
    }

    public enum AddToList {
        public static var title: String { text("addToList.title") }
        public static var empty: String { text("addToList.empty") }
        public static var loadFailed: String { text("addToList.loadFailed") }
        public static var retry: String { text("addToList.retry") }
        public static var addFailed: String { text("addToList.addFailed") }
        public static var removeFailed: String { text("addToList.removeFailed") }
        public static var inList: String { text("addToList.inList") }
        public static var notInList: String { text("addToList.notInList") }
        public static var followRequired: String { text("addToList.followRequired") }
    }

    public enum Profile {
        // Menu actions
        public static var share: String { text("profile.action.share") }
        public static var copyLink: String { text("profile.action.copyLink") }
        public static var openInBrowser: String { text("profile.action.openInBrowser") }
        public static var addToList: String { text("profile.action.addToList") }
        public static var report: String { text("profile.action.report") }

        public static func mute(_ username: String) -> String {
            format("profile.action.mute", username)
        }

        public static var unmute: String { text("profile.action.unmute") }

        public static func block(_ username: String) -> String {
            format("profile.action.block", username)
        }

        public static var unblock: String { text("profile.action.unblock") }

        // Follow button
        public static var follow: String { text("profile.follow.follow") }
        public static var following: String { text("profile.follow.following") }
        public static var followRequested: String { text("profile.follow.requested") }
        public static var cancelFollowRequest: String { text("profile.follow.cancelRequest") }
        public static var blocked: String { text("profile.follow.blocked") }

        // Page content
        public static var navTitle: String { text("profile.navTitle") }
        public static var linkCopied: String { text("profile.linkCopied") }
        public static var badgeProtected: String { text("profile.badgeProtected") }
        public static var badgeBot: String { text("profile.badgeBot") }
        public static var statPosts: String { text("profile.statPosts") }
        public static var statFollowing: String { text("profile.statFollowing") }
        public static var statFollowers: String { text("profile.statFollowers") }
        public static var fieldsSectionTitle: String { text("profile.fieldsSectionTitle") }
        public static var verifiedField: String { text("profile.verifiedField") }
        public static var emptyPostsTitle: String { text("profile.emptyPostsTitle") }
        public static var emptyPostsMessage: String { text("profile.emptyPostsMessage") }
        public static var emptyRepliesTitle: String { text("profile.emptyRepliesTitle") }
        public static var emptyRepliesMessage: String { text("profile.emptyRepliesMessage") }
        public static var emptyMediaTitle: String { text("profile.emptyMediaTitle") }
        public static var emptyMediaMessage: String { text("profile.emptyMediaMessage") }
        public static var emptyFollowingMessage: String { text("profile.emptyFollowingMessage") }
        public static var emptyFollowersMessage: String { text("profile.emptyFollowersMessage") }
        public static var collectionsHiddenTitle: String { text("profile.collectionsHiddenTitle") }
        public static var collectionsHiddenMessage: String { text("profile.collectionsHiddenMessage") }
        public static var collectionsHiddenAccessibilityValue: String {
            text("profile.a11y.collectionsHidden")
        }

        public static func badgeFields(_ count: Int) -> String { format("profile.badgeFields", Int64(count)) }
        public static func joinedDate(_ date: String) -> String { format("profile.joinedDate", date) }

        // A11y
        public static var moreActions: String { text("profile.a11y.moreActions") }
        public static func openProfile(_ acct: String) -> String { format("profile.a11y.openProfile", acct) }
    }

    public enum Timeline {
        public static var refreshing: String { text("timeline.refreshing") }
        public static var newPostsMany: String { text("timeline.newPostsMany") }
        public static var confirmBoostTitle: String { text("timeline.confirmBoost.title") }
        public static var confirmBoostMessage: String { text("timeline.confirmBoost.message") }
        public static var confirmBoostAction: String { text("timeline.confirmBoost.action") }
        public static var noMore: String { text("timeline.noMore") }
        public static var streamConnected: String { text("timeline.streamConnected") }
        public static var canLoadMore: String { text("timeline.canLoadMore") }
        public static var loadFailed: String { text("timeline.loadFailed") }
        public static var retry: String { text("timeline.retry") }
        public static var refresh: String { text("timeline.refresh") }
        public static var emptyHomeTitle: String { text("timeline.empty.home.title") }
        public static var emptyHomeMessage: String { text("timeline.empty.home.message") }
        public static var emptyLocalTitle: String { text("timeline.empty.local.title") }
        public static var emptyLocalMessage: String { text("timeline.empty.local.message") }
        public static var emptyFederatedTitle: String { text("timeline.empty.federated.title") }
        public static var emptyFederatedMessage: String { text("timeline.empty.federated.message") }
        public static var announcementsTitle: String { text("timeline.announcementsTitle") }

        public static func newPosts(_ count: Int) -> String { format("timeline.newPosts", Int64(count)) }
        public static func announcements(_ count: Int) -> String { format("timeline.announcements", Int64(count)) }
        public static func statusCount(_ count: Int) -> String { format("timeline.statusCount", Int64(count)) }
        public static func pendingCheck(_ count: Int) -> String { format("timeline.pendingCheck", Int64(count)) }
    }

    public enum ListMembers {
        public static var title: String { text("listMembers.title") }
        public static var addMember: String { text("listMembers.addMember") }
        public static var loadFailed: String { text("listMembers.loadFailed") }
        public static var retry: String { text("listMembers.retry") }
        public static var emptyTitle: String { text("listMembers.empty.title") }
        public static var emptyMessage: String { text("listMembers.empty.message") }
        public static var remove: String { text("listMembers.remove") }
        public static var removeAccessibility: String { text("listMembers.removeAccessibility") }
        public static var searchPlaceholder: String { text("listMembers.searchPlaceholder") }
        public static var done: String { text("listMembers.done") }
        public static var searchEmptyTitle: String { text("listMembers.searchEmpty.title") }
        public static var searchEmptyMessage: String { text("listMembers.searchEmpty.message") }
        public static var searching: String { text("listMembers.searching") }
        public static var searchNoResultTitle: String { text("listMembers.searchNoResult.title") }
        public static var searchNoResultMessage: String { text("listMembers.searchNoResult.message") }
        public static var add: String { text("listMembers.add") }
        public static var toastLoadFailed: String { text("listMembers.toast.loadFailed") }
        public static var toastAdded: String { text("listMembers.toast.added") }
        public static var toastAddFailed: String { text("listMembers.toast.addFailed") }
        public static var toastAddFailedShort: String { text("listMembers.toast.addFailedShort") }
        public static var toastRemoved: String { text("listMembers.toast.removed") }
        public static var toastRemoveFailed: String { text("listMembers.toast.removeFailed") }
        public static var toastRemoveFailedShort: String { text("listMembers.toast.removeFailedShort") }
        public static var toastSearchFailed: String { text("listMembers.toast.searchFailed") }

        public static func addToList(_ listName: String) -> String { format("listMembers.addToList", listName) }
    }

    public enum MentionUser {
        public static var confirmBoostTitle: String { text("mentionUser.confirmBoost.title") }
        public static var confirmBoostMessage: String { text("mentionUser.confirmBoost.message") }
        public static var confirmBoostAction: String { text("mentionUser.confirmBoost.action") }
        public static var loadFailed: String { text("mentionUser.loadFailed") }
        public static var retry: String { text("mentionUser.retry") }
        public static var unfollowTitle: String { text("mentionUser.unfollow.title") }
        public static var unfollowAction: String { text("mentionUser.unfollow.action") }
        public static var muteTitle: String { text("mentionUser.mute.title") }
        public static var muteAction: String { text("mentionUser.mute.action") }
        public static var blockTitle: String { text("mentionUser.block.title") }
        public static var blockAction: String { text("mentionUser.block.action") }
        public static var linkCopied: String { text("mentionUser.linkCopied") }
        public static var protectedLabel: String { text("mentionUser.protected") }
        public static var emptyPostsTitle: String { text("mentionUser.empty.posts.title") }
        public static var emptyPostsMessage: String { text("mentionUser.empty.posts.message") }
        public static var emptyRepliesTitle: String { text("mentionUser.empty.replies.title") }
        public static var emptyRepliesMessage: String { text("mentionUser.empty.replies.message") }
        public static var emptyMediaTitle: String { text("mentionUser.empty.media.title") }
        public static var emptyMediaMessage: String { text("mentionUser.empty.media.message") }

        public static func unfollowMessage(_ username: String) -> String { format("mentionUser.unfollow.message", username) }
        public static func muteMessage(_ username: String) -> String { format("mentionUser.mute.message", username) }
        public static func blockMessage(_ username: String) -> String { format("mentionUser.block.message", username) }
    }

    public enum Post {
        public static var boosted: String { text("post.boosted") }
        public static var replyingTo: String { text("post.replyingTo") }
        public static var quotedPost: String { text("post.quotedPost") }
        public static var quotePendingTitle: String { text("post.quotePending.title") }
        public static var quotePendingLearnMore: String { text("post.quotePending.learnMore") }
        public static var quotePendingMessage: String { text("post.quotePending.message") }
        public static var quotePendingDismiss: String { text("post.quotePending.dismiss") }
        public static var quoteUnavailableTitle: String { text("post.quoteUnavailable.title") }
        public static var quoteUnavailableMessage: String { text("post.quoteUnavailable.message") }
        public static var noTextContent: String { text("post.noTextContent") }
        public static func openQuotedPost(_ name: String) -> String {
            format("post.openQuotedPost", name)
        }
        public static func openStatus(_ name: String) -> String {
            format("post.openStatus", name)
        }
    }

    public enum StatusAction {
        public static var reply: String { text("statusAction.reply") }
        public static var boost: String { text("statusAction.boost") }
        public static var unboost: String { text("statusAction.unboost") }
        public static var favourite: String { text("statusAction.favourite") }
        public static var unfavourite: String { text("statusAction.unfavourite") }
        public static var bookmark: String { text("statusAction.bookmark") }
        public static var unbookmark: String { text("statusAction.unbookmark") }
        public static var more: String { text("statusAction.more") }

        // Failure toasts shown when the API call to update an interaction fails.
        public static var failureToastLike: String { text("statusAction.failureToast.like") }
        public static var failureToastRepost: String { text("statusAction.failureToast.repost") }
        public static var failureToastBookmark: String { text("statusAction.failureToast.bookmark") }
    }

    /// Share / Copy / Mute / Block flow strings shown from the post "more" menu.
    public enum PostMenu {
        // Share & copy toasts
        public static var shareMissingLink: String { text("postMenu.shareMissingLink") }
        public static var shareUnavailable: String { text("postMenu.shareUnavailable") }
        public static var copyLinkMissing: String { text("postMenu.copyLinkMissing") }
        public static var linkCopied: String { text("postMenu.linkCopied") }
        public static var copyTextEmpty: String { text("postMenu.copyTextEmpty") }
        public static var textCopied: String { text("postMenu.textCopied") }
        public static var openInBrowserMissing: String { text("postMenu.openInBrowserMissing") }

        // Mute / block toasts
        public static var userMuted: String { text("postMenu.userMuted") }
        public static var userUnmuted: String { text("postMenu.userUnmuted") }
        public static var userBlocked: String { text("postMenu.userBlocked") }
        public static var userUnblocked: String { text("postMenu.userUnblocked") }
        public static var muteFailed: String { text("postMenu.muteFailed") }
        public static var blockFailed: String { text("postMenu.blockFailed") }

        // Confirmation dialog titles (parameterised by @username)
        public static func muteConfirmTitle(_ username: String) -> String {
            format("postMenu.muteConfirm.title", username)
        }
        public static func unmuteConfirmTitle(_ username: String) -> String {
            format("postMenu.unmuteConfirm.title", username)
        }
        public static func blockConfirmTitle(_ username: String) -> String {
            format("postMenu.blockConfirm.title", username)
        }
        public static func unblockConfirmTitle(_ username: String) -> String {
            format("postMenu.unblockConfirm.title", username)
        }

        // Confirmation dialog bodies
        public static var muteConfirmMessage: String { text("postMenu.muteConfirm.message") }
        public static var unmuteConfirmMessage: String { text("postMenu.unmuteConfirm.message") }
        public static var blockConfirmMessage: String { text("postMenu.blockConfirm.message") }
        public static var unblockConfirmMessage: String { text("postMenu.unblockConfirm.message") }

        // Confirm button labels
        public static var actionMute: String { text("postMenu.action.mute") }
        public static var actionUnmute: String { text("postMenu.action.unmute") }
        public static var actionBlock: String { text("postMenu.action.block") }
        public static var actionUnblock: String { text("postMenu.action.unblock") }
    }

    public enum Login {
        public static var title: String { text("login.title") }
        public static var subtitle: String { text("login.subtitle") }
        public static var instanceAddress: String { text("login.instanceAddress") }
        public static var login: String { text("login.login") }
        public static var registerNewAccount: String { text("login.registerNewAccount") }
        public static var recommendedServersTitle: String { text("login.recommendedServersTitle") }
        public static var registrationClosed: String { text("login.registrationClosed") }
        public static var retry: String { text("login.retry") }
        public static var errorInvalidFormat: String { text("login.error.invalidFormat") }
        public static var errorAuthCancelled: String { text("login.error.authCancelled") }
        public static var errorNetworkValidation: String { text("login.error.networkValidation") }
        public static var errorValidation: String { text("login.error.validation") }
        public static var errorNetworkAuth: String { text("login.error.networkAuth") }
        public static var errorAuth: String { text("login.error.auth") }

        public enum Server {
            public static var navTitle: String { text("login.server.navTitle") }
            public static var title: String { text("login.server.title") }
            public static var subtitle: String { text("login.server.subtitle") }
            public static var recommendedBadge: String { text("login.server.recommendedBadge") }
            public static var recommendedTagline: String { text("login.server.recommendedTagline") }
            public static var customLabel: String { text("login.server.customLabel") }
            public static var popularTitle: String { text("login.server.popularTitle") }
            public static var continueButton: String { text("login.server.continueButton") }
            public static var browseAll: String { text("login.server.browseAll") }
        }

        public enum Info {
            public static var loading: String { text("login.info.loading") }
            public static var aboutTitle: String { text("login.info.aboutTitle") }
            public static var rulesTitle: String { text("login.info.rulesTitle") }
            public static var adminTitle: String { text("login.info.adminTitle") }
            public static var statusOpen: String { text("login.info.statusOpen") }
            public static var statusApproval: String { text("login.info.statusApproval") }
            public static var statusClosed: String { text("login.info.statusClosed") }
            public static var registerButton: String { text("login.info.registerButton") }
            public static var errorLoad: String { text("login.info.errorLoad") }
        }
    }

    public enum Onboarding {
        public static var tagline: String { text("onboarding.tagline") }
        public static var previewTimelineTitle: String { text("onboarding.preview.timelineTitle") }
        public static var previewTimelineBody: String { text("onboarding.preview.timelineBody") }
        public static var previewComposeTitle: String { text("onboarding.preview.composeTitle") }
        public static var previewComposeBody: String { text("onboarding.preview.composeBody") }
        public static var previewSyncTitle: String { text("onboarding.preview.syncTitle") }
        public static var previewSyncBody: String { text("onboarding.preview.syncBody") }
        public static var pillarLight: String { text("onboarding.pillar.light") }
        public static var pillarSimple: String { text("onboarding.pillar.simple") }
        public static var pillarFriendly: String { text("onboarding.pillar.friendly") }
        public static var getStarted: String { text("onboarding.getStarted") }
    }

    public enum Registration {
        public static var continueButton: String { text("registration.continueButton") }
        public static var navTitleRules: String { text("registration.navTitle.rules") }
        public static var navTitleForm: String { text("registration.navTitle.form") }
        public static var navTitlePendingApproval: String { text("registration.navTitle.pendingApproval") }
        public static var navTitlePendingEmail: String { text("registration.navTitle.pendingEmail") }
        public static var close: String { text("registration.close") }
        public static var back: String { text("registration.back") }
        public static var stepTitleRules: String { text("registration.stepTitle.rules") }
        public static var stepTitleForm: String { text("registration.stepTitle.form") }
        public static var stepTitlePending: String { text("registration.stepTitle.pending") }
        public static var headlineRules: String { text("registration.headline.rules") }
        public static var headlineForm: String { text("registration.headline.form") }
        public static var headlinePendingApproval: String { text("registration.headline.pendingApproval") }
        public static var headlinePendingEmail: String { text("registration.headline.pendingEmail") }
        public static var closedDefault: String { text("registration.closedDefault") }
        public static var closedWithHint: String { text("registration.closedWithHint") }
        public static var summaryRules: String { text("registration.summary.rules") }
        public static var summaryFormApproval: String { text("registration.summary.formApproval") }
        public static var summaryFormEmail: String { text("registration.summary.formEmail") }
        public static var summaryPendingApproval: String { text("registration.summary.pendingApproval") }
        public static var summaryPendingEmail: String { text("registration.summary.pendingEmail") }
        public static var rulesSectionTitle: String { text("registration.rulesSection.title") }
        public static var rulesSectionMessage: String { text("registration.rulesSection.message") }
        public static var noRules: String { text("registration.noRules") }
        public static var openFullRules: String { text("registration.openFullRules") }
        public static var viewTerms: String { text("registration.viewTerms") }
        public static var viewPrivacy: String { text("registration.viewPrivacy") }
        public static var closedForbidden: String { text("registration.closedForbidden") }
        public static var closedForbiddenLong: String { text("registration.closedForbiddenLong") }
        public static var sectionAccountInfo: String { text("registration.section.accountInfo") }
        public static var sectionAccountInfoMessage: String { text("registration.section.accountInfoMessage") }
        public static var fieldUsername: String { text("registration.field.username") }
        public static var fieldUsernameHint: String { text("registration.field.usernameHint") }
        public static var fieldEmail: String { text("registration.field.email") }
        public static var fieldEmailHint: String { text("registration.field.emailHint") }
        public static var sectionSecurity: String { text("registration.section.security") }
        public static var sectionSecurityMessage: String { text("registration.section.securityMessage") }
        public static var fieldPassword: String { text("registration.field.password") }
        public static var fieldPasswordPlaceholder: String { text("registration.field.passwordPlaceholder") }
        public static var fieldConfirmPassword: String { text("registration.field.confirmPassword") }
        public static var fieldConfirmPasswordPlaceholder: String { text("registration.field.confirmPasswordPlaceholder") }
        public static var fieldBirthday: String { text("registration.field.birthday") }
        public static var fieldBirthdayPicker: String { text("registration.field.birthdayPicker") }
        public static var fieldReason: String { text("registration.field.reason") }
        public static var fieldReasonPlaceholder: String { text("registration.field.reasonPlaceholder") }
        public static var sectionTerms: String { text("registration.section.terms") }
        public static var sectionTermsMessage: String { text("registration.section.termsMessage") }
        public static var submitting: String { text("registration.submitting") }
        public static var submitApproval: String { text("registration.submitApproval") }
        public static var submitRegister: String { text("registration.submitRegister") }
        public static var footerApproval: String { text("registration.footer.approval") }
        public static var footerEmail: String { text("registration.footer.email") }
        public static var pendingConfirmEmail: String { text("registration.pending.confirmEmail") }
        public static var pendingBackToLogin: String { text("registration.pending.backToLogin") }
        public static var pendingOpenInstance: String { text("registration.pending.openInstance") }
        public static var pendingResendEmail: String { text("registration.pending.resendEmail") }
        public static var pendingConfirmedGoLogin: String { text("registration.pending.confirmedGoLogin") }
        public static var pendingOauthHint: String { text("registration.pending.oauthHint") }
        public static var required: String { text("registration.required") }
        public static var hintPasswordEmpty: String { text("registration.hint.passwordEmpty") }
        public static var hintPasswordValid: String { text("registration.hint.passwordValid") }
        public static var hintPasswordShort: String { text("registration.hint.passwordShort") }
        public static var hintConfirmEmpty: String { text("registration.hint.confirmEmpty") }
        public static var hintConfirmMatch: String { text("registration.hint.confirmMatch") }
        public static var hintConfirmMismatch: String { text("registration.hint.confirmMismatch") }
        public static var hintBirthdayNoReq: String { text("registration.hint.birthdayNoReq") }
        public static var hintReasonEmpty: String { text("registration.hint.reasonEmpty") }
        public static var hintReasonFilled: String { text("registration.hint.reasonFilled") }
        public static var errorValidationFailed: String { text("registration.error.validationFailed") }
        public static var successApproval: String { text("registration.success.approval") }
        public static var successEmail: String { text("registration.success.email") }
        public static var errorUsernameTaken: String { text("registration.error.usernameTaken") }
        public static var errorEmailTaken: String { text("registration.error.emailTaken") }
        public static var errorPasswordInvalid: String { text("registration.error.passwordInvalid") }
        public static var errorConfirmEmail: String { text("registration.error.confirmEmail") }
        public static var agreement: String { text("registration.agreement") }
        public static var termsOfService: String { text("registration.termsOfService") }
        public static var privacyPolicy: String { text("registration.privacyPolicy") }

        public static func stepNumber(_ number: Int) -> String { format("registration.stepNumber", Int64(number)) }
        public static func pendingAccount(_ email: String) -> String { format("registration.pending.account", email) }
        public static func hintAgeNotMet(_ minAge: Int) -> String { format("registration.hint.ageNotMet", Int64(minAge)) }
        public static func hintMinAge(_ minAge: Int) -> String { format("registration.hint.minAge", Int64(minAge)) }
        public static func errorAgeNotMet(_ minAge: Int) -> String { format("registration.error.ageNotMet", Int64(minAge)) }
        public static func validationRequired(_ field: String) -> String { format("registration.validation.required", field) }
        public static var validationUsernameInvalid: String { text("registration.validation.usernameInvalid") }
        public static var validationEmailInvalid: String { text("registration.validation.emailInvalid") }
        public static var validationAgreementRequired: String { text("registration.validation.agreementRequired") }

        /// Consent line as a markdown template; the two `%@` slots receive the terms-of-service
        /// and privacy-policy URLs, producing inline `[label](url)` links inside the sentence.
        public static func agreementConsent(termsURL: String, privacyURL: String) -> String {
            format("registration.agreement.consent", termsURL, privacyURL)
        }
    }

    public enum PrivacySafety {
        public static var title: String { text("privacy.title") }
        public static var presetOpenTitle: String { text("privacy.preset.open.title") }
        public static var presetOpenDescription: String { text("privacy.preset.open.description") }
        public static var presetPrivateTitle: String { text("privacy.preset.private.title") }
        public static var presetPrivateDescription: String { text("privacy.preset.private.description") }
        public static var sectionPresets: String { text("privacy.section.presets") }
        public static var toggleApproveFollows: String { text("privacy.toggle.approveFollows") }
        public static var toggleShowFollowCounts: String { text("privacy.toggle.showFollowCounts") }
        public static var toggleSuggestAccount: String { text("privacy.toggle.suggestAccount") }
        public static var toggleSearchEngine: String { text("privacy.toggle.searchEngine") }
        public static var sectionOptions: String { text("privacy.section.options") }
        public static var governanceMuted: String { text("privacy.governance.muted") }
        public static var governanceBlocked: String { text("privacy.governance.blocked") }
        public static var governanceFilters: String { text("privacy.governance.filters") }
        public static var sectionGovernance: String { text("privacy.section.governance") }
        public static var defaultVisibility: String { text("privacy.defaultVisibility") }
        public static var sectionDefaults: String { text("privacy.section.defaults") }
        public static var saveFailed: String { text("privacy.saveFailed") }
        public static var confirm: String { text("privacy.confirm") }
        public static var saveErrorFallback: String { text("privacy.saveError.fallback") }
        public static var toastSyncFailed: String { text("privacy.toast.syncFailed") }
    }

    public enum PrivacyProtection {
        public static var message: String { text("privacyProtection.message") }
    }

    public enum Filters {
        public static var title: String { text("filters.title") }
        public static var newFilter: String { text("filters.newFilter") }
        public static var domainBlockTitle: String { text("filters.domainBlock.title") }
        public static var domainBlockAction: String { text("filters.domainBlock.action") }
        public static var domainBlockMessage: String { text("filters.domainBlock.message") }
        public static var loadFailed: String { text("filters.loadFailed") }
        public static var retry: String { text("filters.retry") }
        public static var emptyTitle: String { text("filters.empty.title") }
        public static var emptyMessage: String { text("filters.empty.message") }
        public static var delete: String { text("filters.delete") }
        public static var sectionRules: String { text("filters.section.rules") }
        public static var sectionRulesFooter: String { text("filters.section.rulesFooter") }
        public static var domainBlockEmpty: String { text("filters.domainBlock.empty") }
        public static var domainBlockUnblock: String { text("filters.domainBlock.unblock") }
        public static var domainBlockAddLabel: String { text("filters.domainBlock.addLabel") }
        public static var sectionDomains: String { text("filters.section.domains") }
        public static var sectionDomainsFooter: String { text("filters.section.domainsFooter") }
        public static var formTitleSection: String { text("filters.form.titleSection") }
        public static var formTitlePlaceholder: String { text("filters.form.titlePlaceholder") }
        public static var formKeywordsSection: String { text("filters.form.keywordsSection") }
        public static var formKeywordPlaceholder: String { text("filters.form.keywordPlaceholder") }
        public static var formActionSection: String { text("filters.form.actionSection") }
        public static var formActionLabel: String { text("filters.form.actionLabel") }
        public static var formScopeSection: String { text("filters.form.scopeSection") }
        public static var formEditTitle: String { text("filters.form.editTitle") }
        public static var formCancel: String { text("filters.form.cancel") }
        public static var formSave: String { text("filters.form.save") }
        public static var formCreate: String { text("filters.form.create") }
        public static var formNoKeywords: String { text("filters.form.noKeywords") }
        public static var formWholeWord: String { text("filters.form.wholeWord") }
        public static var formNewKeywordPlaceholder: String { text("filters.form.newKeywordPlaceholder") }
        public static var formMatchWholeWord: String { text("filters.form.matchWholeWord") }
        public static var formAddKeyword: String { text("filters.form.addKeyword") }
        public static var formUpdateKeyword: String { text("filters.form.updateKeyword") }
        public static var formCancelEditKeyword: String { text("filters.form.cancelEditKeyword") }
        public static var formKeywordsSectionHeader: String { text("filters.form.keywordsSectionHeader") }
        public static var formKeywordsFooter: String { text("filters.form.keywordsFooter") }

        public static var toastCreated: String { text("filters.toast.created") }
        public static var toastCreateFailed: String { text("filters.toast.createFailed") }
        public static var toastCreateFailedShort: String { text("filters.toast.createFailedShort") }
        public static var toastKeywordAdded: String { text("filters.toast.keywordAdded") }
        public static var toastKeywordAddFailed: String { text("filters.toast.keywordAddFailed") }
        public static var toastKeywordAddFailedShort: String { text("filters.toast.keywordAddFailedShort") }
        public static var toastKeywordUpdated: String { text("filters.toast.keywordUpdated") }
        public static var toastKeywordUpdateFailed: String { text("filters.toast.keywordUpdateFailed") }
        public static var toastKeywordUpdateFailedShort: String { text("filters.toast.keywordUpdateFailedShort") }
        public static var toastKeywordDeleted: String { text("filters.toast.keywordDeleted") }
        public static var toastKeywordDeleteFailed: String { text("filters.toast.keywordDeleteFailed") }
        public static var toastKeywordDeleteFailedShort: String { text("filters.toast.keywordDeleteFailedShort") }
        public static var toastUpdated: String { text("filters.toast.updated") }
        public static var toastUpdateFailed: String { text("filters.toast.updateFailed") }
        public static var toastUpdateFailedShort: String { text("filters.toast.updateFailedShort") }
        public static var toastDeleted: String { text("filters.toast.deleted") }
        public static var toastDeleteFailed: String { text("filters.toast.deleteFailed") }
        public static var toastDeleteFailedShort: String { text("filters.toast.deleteFailedShort") }
        public static var toastDomainBlocked: String { text("filters.toast.domainBlocked") }
        public static var toastDomainBlockFailed: String { text("filters.toast.domainBlockFailed") }
        public static var toastDomainBlockFailedShort: String { text("filters.toast.domainBlockFailedShort") }
        public static var toastDomainUnblocked: String { text("filters.toast.domainUnblocked") }
        public static var toastDomainUnblockFailed: String { text("filters.toast.domainUnblockFailed") }
        public static var toastDomainUnblockFailedShort: String { text("filters.toast.domainUnblockFailedShort") }
        public static var toastLoadFailed: String { text("filters.toast.loadFailed") }

        public static func keywords(_ list: String) -> String {
            format("filters.keywords", list)
        }
    }

    public enum About {
        public static var title: String { text("about.title") }
        public static var tagline: String { text("about.tagline") }
        public static var sectionProductInfo: String { text("about.sectionProductInfo") }
        public static var version: String { text("about.version") }
        public static var buildNumber: String { text("about.buildNumber") }
        public static var sectionLinks: String { text("about.sectionLinks") }
        public static var githubRepo: String { text("about.githubRepo") }
        public static var mastodonOfficial: String { text("about.mastodonOfficial") }
        public static var feedbackEmail: String { text("about.feedbackEmail") }
        public static var support: String { text("about.support") }
        public static var sectionAcknowledgements: String { text("about.sectionAcknowledgements") }
        public static var viewAcknowledgements: String { text("about.viewAcknowledgements") }
        public static var footer: String { text("about.footer") }
        public static var acknowledgementsTitle: String { text("about.acknowledgementsTitle") }
        public static var ackMastodon: String { text("about.ackMastodon") }
        public static var ackSwiftUI: String { text("about.ackSwiftUI") }
        public static var ackSDWebImage: String { text("about.ackSDWebImage") }
        public static var unknown: String { text("about.unknown") }

        public static func versionBuild(_ version: String, _ build: String) -> String { format("about.versionBuild", version, build) }
        public static func copyright(_ year: Int) -> String { format("about.copyright", Int64(year)) }
    }

    public enum Lists {
        public static var cachedTimelineHint: String { text("lists.cachedTimelineHint") }
        public static var title: String { text("lists.title") }
        public static var newList: String { text("lists.newList") }
        public static var loadFailed: String { text("lists.loadFailed") }
        public static var retry: String { text("lists.retry") }
        public static var emptyTitle: String { text("lists.empty.title") }
        public static var emptyMessage: String { text("lists.empty.message") }
        public static var members: String { text("lists.members") }
        public static var rename: String { text("lists.rename") }
        public static var delete: String { text("lists.delete") }
        public static var replyPolicyFollowed: String { text("lists.replyPolicy.followed") }
        public static var replyPolicyList: String { text("lists.replyPolicy.list") }
        public static var replyPolicyNone: String { text("lists.replyPolicy.none") }
        public static var replyPolicyDefault: String { text("lists.replyPolicy.default") }
        public static var formNameSection: String { text("lists.form.nameSection") }
        public static var formNamePlaceholder: String { text("lists.form.namePlaceholder") }
        public static var formReplySection: String { text("lists.form.replySection") }
        public static var formReplyLabel: String { text("lists.form.replyLabel") }
        public static var formReplyFollowed: String { text("lists.form.replyFollowed") }
        public static var formReplyList: String { text("lists.form.replyList") }
        public static var formReplyNone: String { text("lists.form.replyNone") }
        public static var formEditTitle: String { text("lists.form.editTitle") }
        public static var formCancel: String { text("lists.form.cancel") }
        public static var formSave: String { text("lists.form.save") }
        public static var formCreate: String { text("lists.form.create") }
        public static var timelineLoadFailed: String { text("lists.timeline.loadFailed") }
        public static var timelineRetry: String { text("lists.timeline.retry") }
        public static var timelineEmptyTitle: String { text("lists.timeline.empty.title") }
        public static var timelineEmptyMessage: String { text("lists.timeline.empty.message") }
        public static var timelineRefresh: String { text("lists.timeline.refresh") }
    }

    public enum Search {
        public static var recentTitle: String { text("search.recentTitle") }
        public static var savedTitle: String { text("search.savedTitle") }
        public static var entryHint: String { text("search.entryHint") }
        public static var noRecent: String { text("search.noRecent") }
        public static var noSaved: String { text("search.noSaved") }
        public static var manageSaved: String { text("search.manageSaved") }
        public static var clearRecent: String { text("search.clearRecent") }
        public static var saveSearch: String { text("search.saveSearch") }
        public static var searchSaved: String { text("search.searchSaved") }
        public static var returnDiscovery: String { text("search.returnDiscovery") }
        public static var renameSearch: String { text("search.renameSearch") }
        public static var searchName: String { text("search.searchName") }
        public static var localSearches: String { text("search.localSearches") }
        public static func searchFor(_ query: String) -> String { format("search.searchFor", query) }

        public static var tabAll: String { text("search.tab.all") }
        public static var tabAccounts: String { text("search.tab.accounts") }
        public static var tabStatuses: String { text("search.tab.statuses") }
        public static var tabHashtags: String { text("search.tab.hashtags") }
        public static var emptyNoMatch: String { text("search.empty.noMatch") }
        public static var emptyNoMatchHint: String { text("search.empty.noMatchHint") }
        public static var emptyNoDiscover: String { text("search.empty.noDiscover") }
        public static var loading: String { text("search.loading") }
        public static var typingHint: String { text("search.typing.hint") }
        public static var keyboardFocus: String { text("search.keyboard.focus") }
        public static var keyboardDismiss: String { text("search.keyboard.dismiss") }
        public static var noTextContent: String { text("search.noTextContent") }
        public static var placeholder: String { text("search.placeholder") }
        public static var discoverDirectory: String { text("search.discover.directory") }
        public static var discoverTrendingPosts: String { text("search.discover.trendingPosts") }
        public static var discoverTrendingTags: String { text("search.discover.trendingTags") }
        public static var resultAccounts: String { text("search.result.accounts") }
        public static var resultPosts: String { text("search.result.posts") }
        public static var resultHashtags: String { text("search.result.hashtags") }
        public static var errorDiscoverFailed: String { text("search.error.discoverFailed") }
        public static var errorSearchFailed: String { text("search.error.searchFailed") }
        public static var exploreTitle: String { text("search.explore.title") }
        public static var exploreSubtitle: String { text("search.explore.subtitle") }
        public static var accessibilityOpenDetail: String { text("search.accessibility.openDetail") }
        public static var hashtagFallback: String { text("search.hashtag.fallback") }

        public static func mediaCount(_ count: Int) -> String {
            format("search.mediaCount", Int64(count))
        }

        public static func statsFav(_ count: String) -> String { format("search.stats.fav", count) }
        public static func statsReblog(_ count: String) -> String { format("search.stats.reblog", count) }
        public static func statsReply(_ count: String) -> String { format("search.stats.reply", count) }

        public static func accountStats(_ followers: String, _ following: String, _ posts: String) -> String {
            format("search.account.stats", followers, following, posts)
        }

        public static func discoverDirectoryLoaded(_ count: Int) -> String {
            format("search.discover.directoryLoaded", Int64(count))
        }

        public static func discoverDirectoryCount(_ count: Int) -> String {
            format("search.discover.directoryCount", Int64(count))
        }

        public static func discoverTrendingPostsCount(_ count: Int) -> String {
            format("search.discover.trendingPostsCount", Int64(count))
        }

        public static func discoverTrendingTagsCount(_ count: Int) -> String {
            format("search.discover.trendingTagsCount", Int64(count))
        }

        public static func resultAccountsCount(_ count: Int) -> String {
            format("search.result.accountsCount", Int64(count))
        }

        public static func resultPostsCount(_ count: Int) -> String {
            format("search.result.postsCount", Int64(count))
        }

        public static func resultHashtagsCount(_ count: Int) -> String {
            format("search.result.hashtagsCount", Int64(count))
        }

        public static func hashtagRecentUses(_ count: Int) -> String {
            format("search.hashtag.recentUses", Int64(count))
        }

        public static func tenThousands(_ value: String) -> String { format("search.tenThousands", value) }
    }

    public enum EditProfile {
        public static var title: String { text("editProfile.title") }
        public static var back: String { text("editProfile.back") }
        public static var discardTitle: String { text("editProfile.discard.title") }
        public static var discardContinue: String { text("editProfile.discard.continue") }
        public static var discardAction: String { text("editProfile.discard.action") }
        public static var discardMessage: String { text("editProfile.discard.message") }
        public static var removeAvatarTitle: String { text("editProfile.removeAvatar.title") }
        public static var removeAvatarMessage: String { text("editProfile.removeAvatar.message") }
        public static var removeHeaderTitle: String { text("editProfile.removeHeader.title") }
        public static var removeHeaderMessage: String { text("editProfile.removeHeader.message") }
        public static var remove: String { text("editProfile.remove") }
        public static var sectionMedia: String { text("editProfile.section.media") }
        public static var mediaAvatar: String { text("editProfile.media.avatar") }
        public static var mediaHeader: String { text("editProfile.media.header") }
        public static var mediaChange: String { text("editProfile.media.change") }
        public static var noDisplayName: String { text("editProfile.noDisplayName") }
        public static var sectionBasicInfo: String { text("editProfile.section.basicInfo") }
        public static var fieldDisplayName: String { text("editProfile.field.displayName") }
        public static var fieldBio: String { text("editProfile.field.bio") }
        public static var sectionExtraFields: String { text("editProfile.section.extraFields") }
        public static var fieldLabel: String { text("editProfile.field.label") }
        public static var fieldValue: String { text("editProfile.field.value") }
        public static var fieldIncomplete: String { text("editProfile.field.incomplete") }
        public static var fieldLabelPlaceholder: String { text("editProfile.field.labelPlaceholder") }
        public static var fieldValuePlaceholder: String { text("editProfile.field.valuePlaceholder") }
        public static var addField: String { text("editProfile.addField") }
        public static var saving: String { text("editProfile.saving") }
        public static var unsavedChanges: String { text("editProfile.unsavedChanges") }
        public static var reset: String { text("editProfile.reset") }
        public static var savingShort: String { text("editProfile.savingShort") }
        public static var save: String { text("editProfile.save") }
        public static var toastAvatarLoadFailed: String { text("editProfile.toast.avatarLoadFailed") }
        public static var toastAvatarProcessFailed: String { text("editProfile.toast.avatarProcessFailed") }
        public static var toastHeaderLoadFailed: String { text("editProfile.toast.headerLoadFailed") }
        public static var toastHeaderProcessFailed: String { text("editProfile.toast.headerProcessFailed") }
        public static var toastAvatarPendingRemoved: String { text("editProfile.toast.avatarPendingRemoved") }
        public static var toastAvatarRemoved: String { text("editProfile.toast.avatarRemoved") }
        public static var toastAvatarRemoveFailed: String { text("editProfile.toast.avatarRemoveFailed") }
        public static var toastHeaderPendingRemoved: String { text("editProfile.toast.headerPendingRemoved") }
        public static var toastHeaderRemoved: String { text("editProfile.toast.headerRemoved") }
        public static var toastHeaderRemoveFailed: String { text("editProfile.toast.headerRemoveFailed") }
        public static var toastFieldsIncomplete: String { text("editProfile.toast.fieldsIncomplete") }
        public static var toastNoChanges: String { text("editProfile.toast.noChanges") }
        public static var toastUpdated: String { text("editProfile.toast.updated") }
        public static var toastUpdateFailed: String { text("editProfile.toast.updateFailed") }
    }

    public enum NotificationSettings {
        public static var title: String { text("notifSettings.title") }
        public static var receiveFrom: String { text("notifSettings.inApp.receiveFrom") }
        public static var sectionDisplay: String { text("notifSettings.section.display") }
        public static var sectionType: String { text("notifSettings.section.type") }
        public static var typeMentions: String { text("notifSettings.type.mentions") }
        public static var typeBoosts: String { text("notifSettings.type.boosts") }
        public static var typeFavourites: String { text("notifSettings.type.favourites") }
        public static var typeNewFollowers: String { text("notifSettings.type.newFollowers") }
        public static var sectionPush: String { text("notifSettings.section.push") }
        public static var openSystemSettings: String { text("notifSettings.push.openSystemSettings") }
    }

    public enum Translation {
        public static var notConfigured: String { text("translation.notConfigured") }
        public static var unsupportedLanguagePair: String {
            text("translation.unsupportedLanguagePair")
        }
        public static var emptyText: String { text("translation.emptyText") }
        public static var settingsTitle: String {
            text("translation.settings.title")
        }
        public static var settingsLabel: String {
            text("translation.settings.label")
        }
        public static var providerSectionTitle: String {
            text("translation.settings.providerSection")
        }
        public static var targetLanguageLabel: String {
            text("translation.settings.targetLanguage")
        }
        public static var settingsFooter: String {
            text("translation.settings.footer")
        }
        public static var modeDisabled: String {
            text("translation.mode.disabled")
        }
        public static var modeRemote: String {
            text("translation.mode.remote")
        }
        public static var actionTranslate: String {
            text("translation.action.translate")
        }
        public static var actionShowOriginal: String {
            text("translation.action.showOriginal")
        }
        public static var sameLanguage: String {
            text("translation.sameLanguage")
        }
        public static var failed: String {
            text("translation.failed")
        }
        public static var providerRemoteName: String {
            text("translation.provider.remoteName")
        }
        public static var unavailableOnInstance: String {
            text("translation.provider.unavailableOnInstance")
        }

        public static func translatedFrom(_ language: String, _ provider: String) -> String {
            format("translation.translatedFrom", language,
                provider
            )
        }

        public static var original: String { text("translation.original") }
        public static var system: String { text("translation.system") }
    }

    public enum Report {
        public static var reasonOffensive: String { text("report.reason.offensive") }
        public static var reasonSpam: String { text("report.reason.spam") }
        public static var reasonIllegal: String { text("report.reason.illegal") }
        public static var reasonViolation: String { text("report.reason.violation") }
        public static var reasonOther: String { text("report.reason.other") }
        public static var reasonOffensiveDesc: String { text("report.reason.offensiveDesc") }
        public static var reasonSpamDesc: String { text("report.reason.spamDesc") }
        public static var reasonIllegalDesc: String { text("report.reason.illegalDesc") }
        public static var reasonViolationDesc: String { text("report.reason.violationDesc") }
        public static var reasonOtherDesc: String { text("report.reason.otherDesc") }
        public static var errorLoadPostsShort: String { text("report.error.loadPostsShort") }
        public static var errorLoadPosts: String { text("report.error.loadPosts") }
        public static var errorLoadMoreShort: String { text("report.error.loadMoreShort") }
        public static var errorLoadMore: String { text("report.error.loadMore") }
        public static var successSubmitted: String { text("report.success.submitted") }
        public static var errorSubmitShort: String { text("report.error.submitShort") }
        public static var errorSubmit: String { text("report.error.submit") }
        public static var retry: String { text("report.retry") }
        public static var retryLoadPosts: String { text("report.retryLoadPosts") }
        public static var retryLoadMore: String { text("report.retryLoadMore") }
        public static var retrySubmit: String { text("report.retrySubmit") }
        public static var cancel: String { text("report.cancel") }
        public static var nextStep: String { text("report.nextStep") }
        public static var submitButton: String { text("report.submitButton") }
        public static var selectReason: String { text("report.selectReason") }
        public static var commentHint: String { text("report.commentHint") }
        public static var commentLabel: String { text("report.commentLabel") }
        public static var commentPlaceholder: String { text("report.commentPlaceholder") }
        public static var selectPosts: String { text("report.selectPosts") }
        public static var selectPostsHint: String { text("report.selectPostsHint") }
        public static var selectPostsTitle: String { text("report.selectPostsTitle") }
        public static var reasonLabel: String { text("report.reasonLabel") }
        public static var noReasonSelected: String { text("report.noReasonSelected") }
        public static var submitting: String { text("report.submitting") }
        public static var submittingHint: String { text("report.submittingHint") }
        public static var navTitleSubmitting: String { text("report.navTitle.submitting") }
        public static var stepReason: String { text("report.stepReason") }
        public static var stepPosts: String { text("report.stepPosts") }
        public static var targetLabel: String { text("report.targetLabel") }

        public static func title(_ username: String) -> String { format("report.title", username) }
        public static func selectedCount(_ count: Int) -> String { format("report.selectedCount", Int64(count)) }
    }

    public enum DirectMessages {
        public static var title: String { text("dm.title") }
        public static var newMessage: String { text("dm.newMessage") }
        public static var close: String { text("dm.close") }
        public static var errorLoadFailed: String { text("dm.error.loadFailed") }
        public static var retry: String { text("dm.retry") }
        public static var emptyTitle: String { text("dm.empty.title") }
        public static var emptyMessage: String { text("dm.empty.message") }
        public static var emptyAction: String { text("dm.empty.action") }
        public static var conversation: String { text("dm.conversation") }
        public static var noContent: String { text("dm.noContent") }
        public static var sentMedia1: String { text("dm.sentMedia1") }
        public static var sentPoll: String { text("dm.sentPoll") }
        public static var accessibilityOpenDetail: String { text("dm.accessibilityOpenDetail") }
        public static var swipeDelete: String { text("dm.swipeDelete") }
        public static var swipeRead: String { text("dm.swipeRead") }
        public static var toastLoadMoreFailed: String { text("dm.toast.loadMoreFailed") }
        public static var toastMarkReadFailed: String { text("dm.toast.markReadFailed") }
        public static var errorMarkReadFailed: String { text("dm.error.markReadFailed") }
        public static var toastDeleted: String { text("dm.toast.deleted") }
        public static var toastDeleteFailed: String { text("dm.toast.deleteFailed") }
        public static var errorDeleteFailed: String { text("dm.error.deleteFailed") }
        public static var errorLoadFailedDetail: String { text("dm.error.loadFailed.detail") }

        public static func groupConversation(_ count: Int, _ handles: String) -> String { format("dm.groupConversation", Int64(count), handles) }
        public static func sentMediaCount(_ count: Int) -> String { format("dm.sentMediaCount", Int64(count)) }
        public static func accessibilityLabelUnread(_ title: String, _ preview: String) -> String { format("dm.accessibility.labelUnread", title, preview) }
        public static func accessibilityLabel(_ title: String, _ preview: String) -> String { format("dm.accessibility.label", title, preview) }
    }

    public enum Governance {
        public static var muteNavTitle: String { text("governance.mute.navTitle") }
        public static var blockNavTitle: String { text("governance.block.navTitle") }
        public static var muteTitle: String { text("governance.mute.title") }
        public static var blockTitle: String { text("governance.block.title") }
        public static var muteEmptyTitle: String { text("governance.mute.emptyTitle") }
        public static var blockEmptyTitle: String { text("governance.block.emptyTitle") }
        public static var muteEmptyMessage: String { text("governance.mute.emptyMessage") }
        public static var blockEmptyMessage: String { text("governance.block.emptyMessage") }
        public static var muteRelease: String { text("governance.mute.release") }
        public static var blockRelease: String { text("governance.block.release") }
        public static var muteFooter: String { text("governance.mute.footer") }
        public static var blockFooter: String { text("governance.block.footer") }
        public static var muteLoadFailed: String { text("governance.mute.loadFailed") }
        public static var blockLoadFailed: String { text("governance.block.loadFailed") }
        public static var muteReleased: String { text("governance.mute.released") }
        public static var blockReleased: String { text("governance.block.released") }
        public static var muteReleaseFailed: String { text("governance.mute.releaseFailed") }
        public static var blockReleaseFailed: String { text("governance.block.releaseFailed") }
        public static var muteReleaseFailedDetail: String { text("governance.mute.releaseFailedDetail") }
        public static var blockReleaseFailedDetail: String { text("governance.block.releaseFailedDetail") }
    }

    public enum Poll {
        public static var vote: String { text("poll.vote") }
        public static var voteFailed: String { text("poll.voteFailed") }
        public static var ended: String { text("poll.ended") }
        public static var multipleChoice: String { text("poll.multipleChoice") }
        public static var statusEnded: String { text("poll.statusEnded") }

        public static func votesCount(_ count: Int) -> String { format("poll.votesCount", Int64(count)) }
        public static func endsInDays(_ days: Int) -> String { format("poll.endsInDays", Int64(days)) }
        public static func endsInHours(_ hours: Int) -> String { format("poll.endsInHours", Int64(hours)) }
        public static func endsInMinutes(_ minutes: Int) -> String { format("poll.endsInMinutes", Int64(minutes)) }
    }

    public enum Instance {
        public static var tabAbout: String { text("instance.tab.about") }
        public static var tabRules: String { text("instance.tab.rules") }
        public static var noStatement: String { text("instance.noStatement") }
        public static var loadFailed: String { text("instance.loadFailed") }
        public static var retry: String { text("instance.retry") }
        public static var loading: String { text("instance.loading") }
        public static var navTitle: String { text("instance.navTitle") }
        public static var pickerLabel: String { text("instance.pickerLabel") }
        public static var statement: String { text("instance.statement") }
        public static var admins: String { text("instance.admins") }
        public static var noAdminInfo: String { text("instance.noAdminInfo") }
        public static var emailAdmin: String { text("instance.emailAdmin") }
        public static var adminProfile: String { text("instance.adminProfile") }
        public static var sitePage: String { text("instance.sitePage") }
        public static var noRules: String { text("instance.noRules") }
        public static var noRulesHint: String { text("instance.noRulesHint") }
        public static var openRulesPage: String { text("instance.openRulesPage") }
        public static var rulesSummary: String { text("instance.rulesSummary") }

        public static func version(_ version: String) -> String { format("instance.version", version) }
    }

    public enum Conversation {
        public static var navTitle: String { text("conversation.navTitle") }
        public static var openProfile: String { text("conversation.openProfile") }
        public static var viewMembers: String { text("conversation.viewMembers") }
        public static var fallbackTitle: String { text("conversation.fallbackTitle") }
        public static var membersTitle: String { text("conversation.membersTitle") }
        public static var emptyTitle: String { text("conversation.emptyTitle") }
        public static var emptyMessage: String { text("conversation.emptyMessage") }
        public static var loadFailed: String { text("conversation.loadFailed") }
        public static var retry: String { text("conversation.retry") }
        public static var inputPlaceholder: String { text("conversation.inputPlaceholder") }
        public static var hasQuote: String { text("conversation.hasQuote") }
        public static var mediaCount1: String { text("conversation.mediaCount1") }

        public static func messageCount(_ count: Int) -> String { format("conversation.messageCount", Int64(count)) }
        public static func membersCount(_ members: Int, _ messages: Int) -> String { format("conversation.membersCount", Int64(members), Int64(messages)) }
        public static func handleMessages(_ handle: String, _ count: Int) -> String { format("conversation.handleMessages", handle, Int64(count)) }
        public static func mediaCount(_ count: Int) -> String { format("conversation.mediaCount", Int64(count)) }
    }

    public enum Emoji {
        public static var loading: String { text("emoji.loading") }
        public static var navTitle: String { text("emoji.navTitle") }
        public static var dragHint: String { text("emoji.dragHint") }
        public static var currentSite: String { text("emoji.currentSite") }
        public static var loadFailed: String { text("emoji.loadFailed") }
        public static var noCustomEmoji: String { text("emoji.noCustomEmoji") }
        public static var sort: String { text("emoji.sort") }
        public static var groupSort: String { text("emoji.groupSort") }
        public static var groupSortHint: String { text("emoji.groupSortHint") }
        public static var resetSort: String { text("emoji.resetSort") }
        public static var noInstance: String { text("emoji.noInstance") }
        public static var noInstanceHint: String { text("emoji.noInstanceHint") }

        public static func emojiCount(_ count: Int) -> String { format("emoji.emojiCount", Int64(count)) }
    }

    public enum ComposeVisibility {
        public static var title: String { text("compose.visibility.title") }
        public static var publicOption: String { text("compose.visibility.public") }
        public static var unlisted: String { text("compose.visibility.unlisted") }
        public static var privateOption: String { text("compose.visibility.private") }
        public static var direct: String { text("compose.visibility.direct") }
        public static var publicLabel: String { text("compose.visibility.publicLabel") }
        public static var unlistedLabel: String { text("compose.visibility.unlistedLabel") }
        public static var privateLabel: String { text("compose.visibility.privateLabel") }
        public static var directLabel: String { text("compose.visibility.directLabel") }
        public static var publicDesc: String { text("compose.visibility.publicDesc") }
        public static var unlistedDesc: String { text("compose.visibility.unlistedDesc") }
        public static var privateDesc: String { text("compose.visibility.privateDesc") }
        public static var directDesc: String { text("compose.visibility.directDesc") }
    }

    public enum ListsVM {
        public static var loadFailed: String { text("lists.vm.loadFailed") }
        public static var created: String { text("lists.vm.created") }
        public static var createFailed: String { text("lists.vm.createFailed") }
        public static var createFailedShort: String { text("lists.vm.createFailedShort") }
        public static var updated: String { text("lists.vm.updated") }
        public static var updateFailed: String { text("lists.vm.updateFailed") }
        public static var updateFailedShort: String { text("lists.vm.updateFailedShort") }
        public static var deleted: String { text("lists.vm.deleted") }
        public static var deleteFailed: String { text("lists.vm.deleteFailed") }
        public static var deleteFailedShort: String { text("lists.vm.deleteFailedShort") }
        public static var loadMoreFailed: String { text("lists.vm.loadMoreFailed") }
        public static var timelineLoadFailed: String { text("lists.vm.timelineLoadFailed") }
    }

    public enum Scheduled {
        public static var title: String { text("scheduled.title") }
        public static var subtitle: String { text("scheduled.subtitle") }
        public static var loadFailed: String { text("scheduled.loadFailed") }
        public static var retry: String { text("scheduled.retry") }
        public static var emptyTitle: String { text("scheduled.emptyTitle") }
        public static var emptyMessage: String { text("scheduled.emptyMessage") }
        public static var refresh: String { text("scheduled.refresh") }
        public static var actionFailed: String { text("scheduled.actionFailed") }
        public static var cancel: String { text("scheduled.cancel") }
        public static var pending: String { text("scheduled.pending") }

        public static func mediaCount(_ count: Int) -> String { format("scheduled.mediaCount", Int64(count)) }
    }

    public enum Announcements {
        public static var title: String { text("announcements.title") }
        public static var unsupportedTitle: String { text("announcements.unsupported.title") }
        public static var unsupportedMessage: String { text("announcements.unsupported.message") }
        public static var loadFailed: String { text("announcements.loadFailed") }
        public static var retry: String { text("announcements.retry") }
        public static var emptyTitle: String { text("announcements.emptyTitle") }
        public static var emptyMessage: String { text("announcements.emptyMessage") }
        public static var refresh: String { text("announcements.refresh") }
        public static var new: String { text("announcements.new") }
        public static var markRead: String { text("announcements.markRead") }
    }

    public enum EditHistory {
        public static var navTitle: String { text("editHistory.navTitle") }
        public static var loading: String { text("editHistory.loading") }
        public static var emptyTitle: String { text("editHistory.emptyTitle") }
        public static var emptyMessage: String { text("editHistory.emptyMessage") }
        public static var retry: String { text("editHistory.retry") }
        public static var currentVersion: String { text("editHistory.currentVersion") }
        public static var noBody: String { text("editHistory.noBody") }
        public static var unknownTime: String { text("editHistory.unknownTime") }

        public static func loadFailed(_ error: String) -> String { format("editHistory.loadFailed", error) }
        public static func historyVersion(_ index: Int) -> String { format("editHistory.historyVersion", Int64(index)) }
        public static func mediaCount(_ count: Int) -> String { format("editHistory.mediaCount", Int64(count)) }
        public static func contentWarning(_ text: String) -> String { format("editHistory.contentWarning", text) }
    }

    public enum StatusDetail {
        public static var headerTitle: String { text("statusDetail.headerTitle") }
        public static var editHistory: String { text("statusDetail.editHistory") }
        public static var confirmBoostTitle: String { text("statusDetail.confirmBoostTitle") }
        public static var confirmBoostMessage: String { text("statusDetail.confirmBoostMessage") }
        public static var boost: String { text("statusDetail.boost") }
        public static var cancel: String { text("statusDetail.cancel") }
        public static var threadLoadFailed: String { text("statusDetail.threadLoadFailed") }
        public static var retry: String { text("statusDetail.retry") }
        public static var ancestorsHeader: String { text("statusDetail.ancestorsHeader") }
        public static var repliesHeader: String { text("statusDetail.repliesHeader") }
        public static var currentPost: String { text("statusDetail.currentPost") }
        public static var viewConversation: String { text("statusDetail.viewConversation") }
    }

    public enum AccountMgmt {
        public static var addAccount: String { text("accountMgmt.addAccount") }
        public static var navTitle: String { text("accountMgmt.navTitle") }
        public static var done: String { text("accountMgmt.done") }
        public static var edit: String { text("accountMgmt.edit") }
        public static var removeTitle: String { text("accountMgmt.removeTitle") }
        public static var cancel: String { text("accountMgmt.cancel") }
        public static var remove: String { text("accountMgmt.remove") }
        public static var removeHint1: String { text("accountMgmt.removeHint1") }
        public static var removeHint2: String { text("accountMgmt.removeHint2") }
        public static var removeAccessibility: String { text("accountMgmt.removeAccessibility") }
        public static var swipeToRemoveHint: String { text("accountMgmt.swipeToRemoveHint") }
        public static var editProfile: String { text("accountMgmt.editProfile") }
        public static var currentAccount: String { text("accountMgmt.currentAccount") }
        public static var deleteAccount: String { text("accountMgmt.deleteAccount") }
        public static var deleteSectionTitle: String { text("accountMgmt.deleteSectionTitle") }
        public static var deleteOpenFailedTitle: String { text("accountMgmt.deleteOpenFailedTitle") }
        public static var deleteOpenFailedMessage: String { text("accountMgmt.deleteOpenFailedMessage") }

        public static func deleteFooter(_ host: String) -> String {
            format("accountMgmt.deleteFooter", host)
        }
    }

    public enum NewConversation {
        public static var searchFailed: String { text("newConversation.searchFailed") }
        public static var navTitle: String { text("newConversation.navTitle") }
        public static var selectHint: String { text("newConversation.selectHint") }
        public static var selectDesc: String { text("newConversation.selectDesc") }
        public static var searchPlaceholder: String { text("newConversation.searchPlaceholder") }
        public static var recentContacts: String { text("newConversation.recentContacts") }
        public static var searchResults: String { text("newConversation.searchResults") }
        public static var searching: String { text("newConversation.searching") }
        public static var retry: String { text("newConversation.retry") }
        public static var emptyRecent: String { text("newConversation.emptyRecent") }
        public static var emptySearch: String { text("newConversation.emptySearch") }
        public static var emptyRecentHint: String { text("newConversation.emptyRecentHint") }
        public static var emptySearchHint: String { text("newConversation.emptySearchHint") }
    }

    public enum AccountReport {
        public static var title: String { text("accountReport.title") }
        public static var desc: String { text("accountReport.desc") }
        public static var commentLabel: String { text("accountReport.commentLabel") }
        public static var commentPlaceholder: String { text("accountReport.commentPlaceholder") }
        public static var submitting: String { text("accountReport.submitting") }
        public static var retrySubmit: String { text("accountReport.retrySubmit") }
        public static var submitButtonActive: String { text("accountReport.submitButtonActive") }
        public static var submitButtonLoading: String { text("accountReport.submitButtonLoading") }
        public static var badge: String { text("accountReport.badge") }

        public static func navTitle(_ username: String) -> String { format("accountReport.navTitle", username) }
    }

    public enum Hashtag {
        public static var loadFailed: String { text("hashtag.loadFailed") }
        public static var retry: String { text("hashtag.retry") }
        public static var emptyTitle: String { text("hashtag.emptyTitle") }
        public static var refresh: String { text("hashtag.refresh") }

        public static func emptyMessage(_ tag: String) -> String { format("hashtag.emptyMessage", tag) }
    }

    public enum PollExpiration {
        public static var fiveMinutes: String { text("pollExpiration.fiveMinutes") }
        public static var thirtyMinutes: String { text("pollExpiration.thirtyMinutes") }
        public static var oneHour: String { text("pollExpiration.oneHour") }
        public static var sixHours: String { text("pollExpiration.sixHours") }
        public static var twelveHours: String { text("pollExpiration.twelveHours") }
        public static var oneDay: String { text("pollExpiration.oneDay") }
        public static var threeDays: String { text("pollExpiration.threeDays") }
        public static var fiveDays: String { text("pollExpiration.fiveDays") }
        public static var sevenDays: String { text("pollExpiration.sevenDays") }
    }

    public enum ServerFilter {
        public static var actionWarn: String { text("serverFilter.actionWarn") }
        public static var actionHide: String { text("serverFilter.actionHide") }
        public static var actionUnknown: String { text("serverFilter.actionUnknown") }
        public static var contextHome: String { text("serverFilter.contextHome") }
        public static var contextNotifications: String { text("serverFilter.contextNotifications") }
        public static var contextPublic: String { text("serverFilter.contextPublic") }
        public static var contextThread: String { text("serverFilter.contextThread") }
        public static var contextAccount: String { text("serverFilter.contextAccount") }
        public static var contextUnknown: String { text("serverFilter.contextUnknown") }
    }

    public enum AppCoord {
        public static var switchFailed: String { text("appCoordinator.switchFailed") }
        public static var accountRemoved: String { text("appCoordinator.accountRemoved") }
        public static var switchedToNext: String { text("appCoordinator.switchedToNext") }
        public static var loggedOut: String { text("appCoordinator.loggedOut") }
        public static var currentLoggedOut: String { text("appCoordinator.currentLoggedOut") }

        public static func switchedTo(_ acct: String) -> String { format("appCoordinator.switchedTo", acct) }
    }

    public enum TimelineSwitcher {
        public static var home: String { text("timelineSwitcher.home") }
        public static var local: String { text("timelineSwitcher.local") }
        public static var federated: String { text("timelineSwitcher.federated") }
        public static var homeDesc: String { text("timelineSwitcher.homeDesc") }
        public static var localDesc: String { text("timelineSwitcher.localDesc") }
        public static var federatedDesc: String { text("timelineSwitcher.federatedDesc") }
        public static var accessibility: String { text("timelineSwitcher.accessibility") }
    }

    public enum Favourites {
        public static var navTitle: String { text("favourites.navTitle") }
        public static var loadFailed: String { text("favourites.loadFailed") }
        public static var retry: String { text("favourites.retry") }
        public static var emptyTitle: String { text("favourites.emptyTitle") }
        public static var emptyMessage: String { text("favourites.emptyMessage") }
        public static var refresh: String { text("favourites.refresh") }
        public static var unfavourite: String { text("favourites.unfavourite") }
    }

    public enum ComposeOriginal {
        public static var badgeCW: String { text("composeOriginal.badgeCW") }
        public static var badgeMediaSingular: String { text("composeOriginal.badgeMediaSingular") }
        public static var badgePoll: String { text("composeOriginal.badgePoll") }
        public static var badgeQuote: String { text("composeOriginal.badgeQuote") }
        public static var fallbackTitle: String { text("composeOriginal.fallbackTitle") }

        public static func replyTo(_ handle: String) -> String { format("composeOriginal.replyTo", handle) }
        public static func quoting(_ handle: String) -> String { format("composeOriginal.quoting", handle) }
        public static func badgeMediaPlural(_ count: Int) -> String { format("composeOriginal.badgeMediaPlural", Int64(count)) }
    }

    public enum Bookmarks {
        public static var navTitle: String { text("bookmarks.navTitle") }
        public static var loadFailed: String { text("bookmarks.loadFailed") }
        public static var retry: String { text("bookmarks.retry") }
        public static var emptyTitle: String { text("bookmarks.emptyTitle") }
        public static var emptyMessage: String { text("bookmarks.emptyMessage") }
        public static var refresh: String { text("bookmarks.refresh") }
        public static var remove: String { text("bookmarks.remove") }
        public static var swipeHint: String { text("bookmarks.swipeHint") }
        public static var gotIt: String { text("bookmarks.gotIt") }
    }

    public enum QuotePolicy {
        public static var anyone: String { text("quotePolicy.anyone") }
        public static var followers: String { text("quotePolicy.followers") }
        public static var onlySelf: String { text("quotePolicy.onlySelf") }
    }

    public enum Media {
        public static var addAlt: String { text("media.addAlt") }
        public static var altLabel: String { text("media.altLabel") }
        public static var accessibilityImage: String { text("media.accessibilityImage") }
        public static var editDescNavTitle: String { text("media.editDescNavTitle") }
        public static var cancel: String { text("media.cancel") }
        public static var save: String { text("media.save") }
    }

    public enum ScheduledVM {
        public static var loadMoreFailed: String { text("scheduledVM.loadMoreFailed") }
        public static var cancelled: String { text("scheduledVM.cancelled") }
        public static var cancelFailed: String { text("scheduledVM.cancelFailed") }
        public static var cancelFailedShort: String { text("scheduledVM.cancelFailedShort") }
        public static var loadFailed: String { text("scheduledVM.loadFailed") }
    }

    public enum FavouritesVM {
        public static var loadMoreFailed: String { text("favouritesVM.loadMoreFailed") }
        public static var unfavourited: String { text("favouritesVM.unfavourited") }
        public static var unfavouriteFailed: String { text("favouritesVM.unfavouriteFailed") }
        public static var unfavouriteFailedDetail: String { text("favouritesVM.unfavouriteFailedDetail") }
        public static var loadFailed: String { text("favouritesVM.loadFailed") }
    }

    public enum BookmarksVM {
        public static var loadMoreFailed: String { text("bookmarksVM.loadMoreFailed") }
        public static var removed: String { text("bookmarksVM.removed") }
        public static var removeFailed: String { text("bookmarksVM.removeFailed") }
        public static var removeFailedDetail: String { text("bookmarksVM.removeFailedDetail") }
        public static var loadFailed: String { text("bookmarksVM.loadFailed") }
    }

    public enum Auth {
        public static var registeredNoCredentials: String { text("auth.registeredNoCredentials") }
        public static var confirmEmail: String { text("auth.confirmEmail") }
        public static var pendingApproval: String { text("auth.pendingApproval") }
        public static var registrationSubmitted: String { text("auth.registrationSubmitted") }
    }

    public enum BoostDialog {
        public static var unboost: String { text("boostDialog.unboost") }
        public static var boost: String { text("boostDialog.boost") }
        public static var quote: String { text("boostDialog.quote") }
        public static var quoteDisabled: String { text("boostDialog.quoteDisabled") }
    }

    public enum AccountReportVM {
        public static var submitted: String { text("accountReportVM.submitted") }
        public static var submitFailed: String { text("accountReportVM.submitFailed") }
        public static var networkError: String { text("accountReportVM.networkError") }

        public static func submitFailedDetail(_ error: String) -> String { format("accountReportVM.submitFailedDetail", error) }
    }

    public enum ComposeMedia {
        public static var uploadFailed: String { text("composeMedia.uploadFailed") }
        public static var retry: String { text("composeMedia.retry") }
        public static var addAlt: String { text("composeMedia.addAlt") }
        public static var removeAttachment: String { text("composeMedia.removeAttachment") }

        public static func uploading(_ percent: Int) -> String { format("composeMedia.uploading", Int64(percent)) }
    }

    public enum Push {
        public static var permissionDenied: String { text("push.permissionDenied") }
        public static var permissionFailed: String { text("push.permissionFailed") }
        public static var registrationFailed: String { text("push.registrationFailed") }
    }

    public enum PostInteraction {
        public static var pinned: String { text("postInteraction.pinned") }
        public static var unpinned: String { text("postInteraction.unpinned") }
        public static var pinFailed: String { text("postInteraction.pinFailed") }
        public static var deleted: String { text("postInteraction.deleted") }
        public static var deleteFailed: String { text("postInteraction.deleteFailed") }
    }

    public enum AppIcon {
        public static var notSupported: String { text("appIcon.notSupported") }
        public static var resourceUnavailable: String { text("appIcon.resourceUnavailable") }
    }

    public enum MainTab {
        public static var sharedContent: String { text("mainTab.sharedContent") }
        public static var sharedContentAttachments: String { text("mainTab.sharedContentAttachments") }
        public static var addAccount: String { text("mainTab.addAccount") }
        public static var accountList: String { text("mainTab.accountList") }

        public static func quickSwitch(_ name: String) -> String { format("mainTab.quickSwitch", name) }
    }

    public enum PostFooter {
        public static var boosts: String { text("postFooter.boosts") }
        public static var replies: String { text("postFooter.replies") }
        public static var favourites: String { text("postFooter.favourites") }
    }

    public enum PinnedCard {
        public static var pinned: String { text("pinnedCard.pinned") }
        public static var mediaLabel: String { text("pinnedCard.mediaLabel") }
        public static var cwWarning: String { text("pinnedCard.cwWarning") }
    }

    public enum Feedback {
        public static var subject: String { text("feedback.subject") }
        public static var notLoggedIn: String { text("feedback.notLoggedIn") }
        public static var bodyPrompt: String { text("feedback.bodyPrompt") }
    }

    public enum ConversationVM {
        public static var sendFailed: String { text("conversationVM.sendFailed") }
        public static var sendFailedShort: String { text("conversationVM.sendFailedShort") }
        public static var markReadFailed: String { text("conversationVM.markReadFailed") }
    }

    public enum EmojiL10n {
        public static var categoryOther: String { text("emoji.categoryOther") }
        public static var categoryAll: String { text("emoji.categoryAll") }
    }

    public enum SensitiveMedia {
        public static var title: String { text("sensitiveMedia.title") }
        public static var tapToView: String { text("sensitiveMedia.tapToView") }
        public static var showAnyway: String { text("sensitiveMedia.showAnyway") }
        public static var contentWarning: String { text("sensitiveMedia.contentWarning") }
        // A11y: spoken state ("revealed"/"hidden") and the reveal hint
        public static var valueRevealed: String { text("sensitiveMedia.value.revealed") }
        public static var valueHidden: String { text("sensitiveMedia.value.hidden") }
        public static var revealHint: String { text("sensitiveMedia.revealHint") }
    }

    public enum UtilityButton {
        public static var back: String { text("utilityButton.back") }
        public static var close: String { text("utilityButton.close") }
        public static var settings: String { text("utilityButton.settings") }
    }

    /// VoiceOver-only labels and spoken states.
    public enum A11y {
        public static var play: String { text("a11y.play") }
        public static var pause: String { text("a11y.pause") }
        public static var playing: String { text("a11y.playing") }
        public static var paused: String { text("a11y.paused") }
        public static var videoPlayer: String { text("a11y.videoPlayer") }
    }

    public enum TabIconTheme {
        public static var sectionTitle: String { text("tabIconTheme.sectionTitle") }
        public static var standard: String { text("tabIconTheme.standard") }
        public static var standardSubtitle: String { text("tabIconTheme.standard.subtitle") }
        public static var modern: String { text("tabIconTheme.modern") }
        public static var modernSubtitle: String { text("tabIconTheme.modern.subtitle") }
    }

    public enum NavigationStyle {
        public static var sectionTitle: String { text("navigationStyle.sectionTitle") }
        public static var sectionFooter: String { text("navigationStyle.sectionFooter") }
        public static var current: String { text("navigationStyle.current") }
        public static var currentSubtitle: String { text("navigationStyle.current.subtitle") }
        public static var editorial: String { text("navigationStyle.editorial") }
        public static var editorialSubtitle: String { text("navigationStyle.editorial.subtitle") }
    }

    public enum LinkPreview {
        public static func byAuthor(_ name: String) -> String { format("linkPreview.byAuthor", name) }
        /// VoiceOver label for the combined card element.
        public static func cardLabel(_ title: String, _ provider: String) -> String {
            format("linkPreview.cardLabel", title, provider)
        }
    }

    public enum AnnouncementsVM {
        public static var markFailed: String { text("announcementsVM.markFailed") }
        public static var reactionFailed: String { text("announcementsVM.reactionFailed") }
    }

    public enum ScheduledStatus {
        public static var mediaOnly: String { text("scheduledStatus.mediaOnly") }
        public static var noText: String { text("scheduledStatus.noText") }
    }

    public enum PostHeader {
        public static var threadContext: String { text("postHeader.threadContext") }
    }

    public enum PinnedPosts {
        public static var title: String { text("pinnedPosts.title") }
        public static var viewAll: String { text("pinnedPosts.viewAll") }
    }

    public enum SettingsSwitch {
        public static var on: String { text("settings.switchOn") }
        public static var off: String { text("settings.switchOff") }
    }

    public enum ImagePreview {
        public static var altBadge: String { text("imagePreview.altBadge") }
        public static var altAccessibility: String { text("imagePreview.altAccessibility") }
        public static var emptyState: String { text("imagePreview.emptyState") }
        public static var noAltDescription: String { text("imagePreview.noAltDescription") }
        public static var loadFailed: String { text("imagePreview.loadFailed") }
    }

    public enum EmojiPicker {
        public static var search: String { text("emojiPicker.search") }
    }

    public enum ContentState {
        public static var retry: String { text("contentState.retry") }
    }

    public enum AltOverlay {
        public static var title: String { text("altOverlay.title") }
    }

    public enum ComposeQuote {
        public static var previewTitle: String { text("composeQuote.previewTitle") }
    }

    public enum GovernanceView {
        public static var loadFailed: String { text("governance.loadFailed") }
        public static var retry: String { text("governance.retry") }
    }

    public enum PinnedTimeline {
        public static var pin: String { text("pinnedTimeline.pin") }
        public static var unpin: String { text("pinnedTimeline.unpin") }
        public static var pinned: String { text("pinnedTimeline.pinned") }
        public static var unpinned: String { text("pinnedTimeline.unpinned") }
    }

    /// Networking / server error copy. Lives in the same `Moro` catalog as the rest of
    /// the UI so it is localized in all 9 languages (previously these were English-only
    /// in the default `Localizable` table). Used by `APIError` / `MastodonServerError`.
    public enum AppError {
        // General descriptions
        public static var invalidURL: String { text("error.invalidURL") }
        public static var decoding: String { text("error.decoding") }
        public static var authenticationRequired: String { text("error.authenticationRequired") }
        public static var cancelled: String { text("error.cancelled") }
        public static var networkUnavailable: String { text("error.networkUnavailable") }
        public static var timeout: String { text("error.timeout") }
        public static var rateLimited: String { text("error.rateLimited") }
        public static var unknown: String { text("error.unknown") }

        /// HTTP status description. Explicit per-code keys (fixes the prior interpolated
        /// `error.http.\(code)` lookup, which never matched the static keys).
        public static func http(_ statusCode: Int) -> String {
            switch statusCode {
            case 400: return text("error.http.400")
            case 401: return text("error.http.401")
            case 403: return text("error.http.403")
            case 404: return text("error.http.404")
            case 410: return text("error.http.410")
            case 422: return text("error.http.422")
            case 429: return text("error.http.429")
            case 502: return text("error.http.502")
            case 503: return text("error.http.503")
            case 500...599: return text("error.http.500")
            default: return text("error.unknown")
            }
        }

        // Failure reasons
        public static var reasonInvalidURL: String { text("error.reason.invalidURL") }
        public static var reasonAuthenticationRequired: String { text("error.reason.authenticationRequired") }
        public static var reasonNetworkUnavailable: String { text("error.reason.networkUnavailable") }
        public static var reasonTimeout: String { text("error.reason.timeout") }
        public static var reasonRateLimited: String { text("error.reason.rateLimited") }

        // Recovery suggestions
        public static var recoveryContactSupport: String { text("error.recovery.contactSupport") }
        public static var recoveryRelogin: String { text("error.recovery.relogin") }
        public static var recoveryCheckConnection: String { text("error.recovery.checkConnection") }
        public static var recoveryTryAgain: String { text("error.recovery.tryAgain") }
        public static var recoveryWaitAndRetry: String { text("error.recovery.waitAndRetry") }
        public static func recoveryWaitSeconds(_ seconds: Int) -> String {
            format("error.recovery.waitSeconds", seconds)
        }
        public static var recoveryNotFound: String { text("error.recovery.notFound") }
        public static var recoveryCheckInput: String { text("error.recovery.checkInput") }
        public static var recoveryServerError: String { text("error.recovery.serverError") }
        public static var recoveryUnauthorized: String { text("error.recovery.unauthorized") }
        public static var recoveryForbidden: String { text("error.recovery.forbidden") }
        public static var recoveryUnprocessable: String { text("error.recovery.unprocessable") }
        public static var recoveryRateLimit: String { text("error.recovery.rateLimit") }

        // Alert titles
        public static var titleNoConnection: String { text("error.title.noConnection") }
        public static var titleSessionExpired: String { text("error.title.sessionExpired") }
        public static var titleSlowDown: String { text("error.title.slowDown") }
        public static var titleServerError: String { text("error.title.serverError") }
        public static var titleSomethingWentWrong: String { text("error.title.somethingWentWrong") }
    }
}
