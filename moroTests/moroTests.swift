//
//  moroTests.swift
//  moroTests
//
//  Created by Noah on 11/24/25.
//

import Testing
@testable import moro
import Foundation
import SwiftUI
import UIKit
import Combine

struct moroTests {
    @Test @MainActor func notificationRefreshFinishesWhenItsViewTaskIsCancelled() async {
        let api = MockMastodonAPI()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        var requestCount = 0
        api.fetchNotificationsHandler = { _, sinceID, _, _ in
            requestCount += 1
            guard sinceID != nil else { return [self.makeNotification(id: "1", type: "update")] }
            signal.yield(())
            for await _ in release { break }
            try Task.checkCancellation()
            return [self.makeNotification(id: "2", type: "update")]
        }
        let model = NotificationsViewModel(apiClient: api)
        await model.loadInitial()
        let firstRefresh = Task { await model.refresh() }
        for await _ in started { break }
        firstRefresh.cancel()
        let (joined, joinSignal) = AsyncStream<Void>.makeStream()
        let secondRefresh = Task {
            joinSignal.yield(())
            return await model.refresh()
        }
        for await _ in joined { break }
        resume.yield(())
        resume.finish()
        #expect(await firstRefresh.value == "2")
        #expect(await secondRefresh.value == "2")
        #expect(requestCount == 2)
        #expect(model.notifications.map(\.id) == ["2", "1"])
        if case .loaded = model.loadingState {} else { Issue.record("Refresh must leave the feed usable") }
    }

    @Test @MainActor func resolvedFollowRequestsDisappearFromEveryCachedNotificationFilter() async throws {
        let settings = AppSettings.shared
        let oldPolicy = settings.notificationPolicy
        let oldFollowers = settings.receiveNewFollowers
        settings.notificationPolicy = .anyone
        settings.receiveNewFollowers = true
        defer {
            settings.notificationPolicy = oldPolicy
            settings.receiveNewFollowers = oldFollowers
        }
        for shouldAccept in [true, false] {
            let api = MockMastodonAPI()
            api.authorizeFollowRequestHandler = { self.makeRelationship(id: $0, followedBy: true) }
            api.rejectFollowRequestHandler = { self.makeRelationship(id: $0) }
            api.fetchNotificationsHandler = { _, sinceID, _, _ in
                sinceID == nil ? [self.makeNotification(id: "100", type: "follow_request")] : []
            }
            let feeds = NotificationFeedStore(apiClient: api)
            let all = feeds.model(for: .everything)
            let mentions = feeds.model(for: .mentions)
            await all.activate()
            await mentions.activate()
            let request = try #require(mentions.notifications.first)
            if shouldAccept {
                await mentions.acceptFollowRequest(request)
            } else {
                await mentions.rejectFollowRequest(request)
            }
            #expect(mentions.notifications.isEmpty)
            #expect(all.notifications.isEmpty)
            await all.refresh()
            #expect(all.notifications.isEmpty)
        }
    }

    @Test @MainActor func notificationFiltersRequestMatchingTypesAndKeepAllOpenToFallbacks() {
        for filter in NotificationFilter.allCases {
            let scope = filter.serverScope
            if filter == .all {
                #expect(scope.types.isEmpty)
                continue
            }
            for rawType in NotificationKind.supportedRawValues {
                let item = NotificationDisplayItem.consolidate([
                    makeNotification(id: "1", type: rawType)
                ])[0]
                #expect(filter.matches(item) == scope.types.contains(rawType))
            }
        }
        #expect(MastodonNotificationScope.mentions.types == ["mention"])
        let all = MastodonEndpoint.notifications(maxID: nil, sinceID: nil, limit: 30,
            types: MastodonNotificationScope.everything.types,
            supportedTypes: NotificationKind.supportedRawValues)
        #expect(all.queryItems?.contains { $0.name == "types[]" } == false)
        #expect(all.queryItems?.contains { $0.name == "supported_types[]" } == true)
    }

    @Test @MainActor func notificationFeedSwitchingKeepsIndependentHistoryAndRefreshCursors() async {
        let settings = AppSettings.shared
        let oldPolicy = settings.notificationPolicy
        let oldFavourites = settings.receiveFavourites
        settings.notificationPolicy = .anyone
        settings.receiveFavourites = true
        defer {
            settings.notificationPolicy = oldPolicy
            settings.receiveFavourites = oldFavourites
        }
        let api = MockMastodonAPI()
        var calls: [(String?, String?, MastodonNotificationScope)] = []
        api.fetchNotificationsHandler = { maxID, sinceID, _, scope in
            calls.append((maxID, sinceID, scope))
            if scope == .everything { return [self.makeNotification(id: "300", type: "update")] }
            if sinceID != nil { return [self.makeNotification(id: "61", type: "mention")] }
            let range = maxID == nil ? 31...60 : 1...30
            return range.reversed().map { self.makeNotification(id: String($0), type: "mention") }
        }
        let feeds = NotificationFeedStore(apiClient: api, minimumRefreshInterval: 0)
        let all = feeds.model(for: .everything)
        let mentions = feeds.model(for: .mentions)
        await all.activate()
        await mentions.activate()
        await mentions.loadMore()
        #expect(feeds.model(for: .everything) === all)
        #expect(feeds.model(for: .mentions) === mentions)
        await feeds.model(for: .mentions).activate()
        #expect(calls.last?.1 == "60" && calls.last?.2 == .mentions)
        await mentions.loadMore()
        #expect(calls.last?.0 == "1" && calls.last?.1 == nil)
        #expect(all.notifications.map(\.id) == ["300"])
    }

    @Test @MainActor func notificationActivationSurvivesRapidSwitchAwayAndBack() async {
        let api = MockMastodonAPI()
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        var requestCount = 0
        api.fetchNotificationsHandler = { _, _, _, _ in
            requestCount += 1
            signal.yield(())
            for await _ in release { break }
            try Task.checkCancellation()
            return [self.makeNotification(id: "1", type: "update")]
        }
        let model = NotificationsViewModel(apiClient: api)
        let firstVisit = Task { await model.activate() }
        for await _ in started { break }
        firstVisit.cancel()
        let (joined, joinSignal) = AsyncStream<Void>.makeStream()
        let secondVisit = Task {
            joinSignal.yield(())
            return await model.activate()
        }
        for await _ in joined { break }
        resume.yield(())
        resume.finish()
        #expect(await secondVisit.value == "1")
        _ = await firstVisit.value
        #expect(requestCount == 1)
        #expect(model.notifications.map(\.id) == ["1"])
        if case .loaded = model.loadingState {} else { Issue.record("Returned feed must be usable") }
    }

    @Test @MainActor func notificationMentionsUseTheirOwnServerScopeAndPagination() async {
        let settings = AppSettings.shared
        let oldPolicy = settings.notificationPolicy
        let oldMentions = settings.receiveMentionsAndReplies
        settings.notificationPolicy = .anyone
        settings.receiveMentionsAndReplies = true
        defer {
            settings.notificationPolicy = oldPolicy
            settings.receiveMentionsAndReplies = oldMentions
        }

        let api = MockMastodonAPI()
        var calls: [(maxID: String?, scope: MastodonNotificationScope)] = []
        api.fetchNotificationsHandler = { maxID, _, _, scope in
            calls.append((maxID, scope))
            if maxID == nil {
                return (31...60).reversed().map {
                    self.makeNotification(id: String($0), type: "mention")
                }
            }
            return [self.makeNotification(id: "30", type: "mention")]
        }

        let model = NotificationsViewModel(apiClient: api, scope: .mentions)
        await model.loadInitial()
        await model.loadMore()

        #expect(calls.count == 2)
        #expect(calls[0].maxID == nil && calls[0].scope == .mentions)
        #expect(calls[1].maxID == "31" && calls[1].scope == .mentions)
        #expect(model.notifications.count == 31)
        #expect(NotificationFilter.mentions.serverScope == .mentions)
        #expect(NotificationFilter.all.serverScope == .everything)
    }

    @Test @MainActor func notificationEmptyFilterCanLoadOlderMatchesAndRetryTheSameCursor() async {
        let settings = AppSettings.shared
        let oldPolicy = settings.notificationPolicy
        let oldMentions = settings.receiveMentionsAndReplies
        settings.notificationPolicy = .anyone
        settings.receiveMentionsAndReplies = true
        defer {
            settings.notificationPolicy = oldPolicy
            settings.receiveMentionsAndReplies = oldMentions
        }
        let api = MockMastodonAPI()
        var failPagination = true
        var cursors: [String?] = []
        api.fetchNotificationsHandler = { maxID, _, _, _ in
            cursors.append(maxID)
            if maxID == nil {
                return (31...60).reversed().map {
                    self.makeNotification(id: String($0), type: "update")
                }
            }
            if failPagination { throw URLError(.notConnectedToInternet) }
            return [self.makeNotification(id: "30", type: "mention")]
        }
        let model = NotificationsViewModel(apiClient: api)
        await model.loadInitial()
        #expect(model.notifications.filter(NotificationFilter.mentions.matches).isEmpty)
        #expect(model.hasMore)
        await model.loadMore()
        #expect(model.loadMoreFailed && model.hasMore)
        failPagination = false
        await model.loadMore()
        #expect(model.notifications.filter(NotificationFilter.mentions.matches).map(\.id) == ["30"])
        #expect(!model.hasMore && !model.loadMoreFailed)
        #expect(cursors == [nil, "31", "31"])
    }

    @Test @MainActor func notificationRefreshMergesEveryNewPageAndPreservesTheHistoryCursor() async {
        let settings = AppSettings.shared
        let oldPolicy = settings.notificationPolicy
        settings.notificationPolicy = .anyone
        defer { settings.notificationPolicy = oldPolicy }
        let api = MockMastodonAPI()
        var calls: [(String?, String?)] = []
        func page(_ range: ClosedRange<Int>) -> [NotificationItem] {
            range.reversed().map {
                self.makeNotification(id: String($0), type: "update", createdAt: Date(timeIntervalSince1970: Double($0)))
            }
        }
        api.fetchNotificationsHandler = { maxID, sinceID, _, _ in
            calls.append((maxID, sinceID))
            if sinceID == "300" {
                if maxID == nil { return page(331...360) }
                if maxID == "331" { return page(301...330) }
                return []
            }
            if maxID == nil { return page(271...300) }
            if maxID == "271" { return page(241...270) }
            return page(240...240)
        }
        let model = NotificationsViewModel(apiClient: api)
        await model.loadInitial()
        await model.loadMore()
        let originalIDs = Set(model.notifications.map(\.id))
        let newest = await model.refresh()
        #expect(newest == "360")
        #expect(model.notifications.count == 120)
        #expect(originalIDs.isSubset(of: Set(model.notifications.map(\.id))))
        #expect(model.notifications.first?.id == "360")
        #expect(model.notifications.last?.id == "241")
        #expect(calls[3].0 == "331" && calls[3].1 == "300")
        #expect(calls[4].0 == "301" && calls[4].1 == "300")
        await model.loadMore()
        #expect(calls.last?.0 == "241" && calls.last?.1 == nil)
        #expect(model.notifications.last?.id == "240")
    }

    @Test @MainActor func notificationRefreshFailureAndRepeatedPagesKeepExistingContentUsable() async {
        let settings = AppSettings.shared
        let oldPolicy = settings.notificationPolicy
        settings.notificationPolicy = .anyone
        defer { settings.notificationPolicy = oldPolicy }
        let api = MockMastodonAPI()
        let page = (1...30).reversed().map {
            makeNotification(id: String($0), type: "update", createdAt: Date(timeIntervalSince1970: Double($0)))
        }
        api.fetchNotificationsHandler = { _, _, _, _ in page }
        let model = NotificationsViewModel(apiClient: api)
        await model.loadInitial()
        api.fetchNotificationsHandler = { _, _, _, _ in throw URLError(.notConnectedToInternet) }
        #expect(await model.refresh() == nil)
        #expect(model.notifications.count == 30 && model.hasMore)
        if case .loaded = model.loadingState {} else { Issue.record("Keep loaded content after refresh failure") }

        api.fetchNotificationsHandler = { _, _, _, _ in page }
        await model.loadMore()
        #expect(model.notifications.count == 30 && !model.hasMore)
        await model.refresh()
        #expect(model.notifications.count == 30 && !model.hasMore)
    }

    @Test @MainActor func localPushPreferencesDoNotHideServerNotifications() async {
        let settings = AppSettings.shared
        let oldPolicy = settings.notificationPolicy
        let oldMentions = settings.receiveMentionsAndReplies
        settings.notificationPolicy = .anyone
        settings.receiveMentionsAndReplies = true
        defer {
            settings.notificationPolicy = oldPolicy
            settings.receiveMentionsAndReplies = oldMentions
        }
        let api = MockMastodonAPI()
        let mention = makeNotification(id: "100", type: "mention")
        api.fetchNotificationsHandler = { _, sinceID, _, _ in sinceID == nil ? [mention] : [] }
        let model = NotificationsViewModel(apiClient: api)
        await model.loadInitial()
        #expect(model.notifications.map(\.id) == ["100"])
        settings.receiveMentionsAndReplies = false
        await model.refresh()
        #expect(model.notifications.map(\.id) == ["100"])
        #expect(!model.filterInsight.hidesAnything)
        settings.receiveMentionsAndReplies = true
        await model.refresh()
        #expect(model.notifications.map(\.id) == ["100"])
        #expect(!model.filterInsight.hidesAnything)
    }

    @Test @MainActor func conversationRefreshFailurePreservesHistoryLiveMessagesAndDraft() async {
        let api = MockMastodonAPI()
        let ancestor = makeStatus(id: "99", createdAt: Date(timeIntervalSince1970: 99))
        let last = makeStatus(id: "100", createdAt: Date(timeIntervalSince1970: 100))
        let incoming = makeStatus(id: "101", createdAt: Date(timeIntervalSince1970: 101))
        let model = ConversationDetailViewModel(
            conversation: makeConversation(id: "conversation", unread: false, lastStatus: last),
            apiClient: api
        )
        api.fetchStatusContextHandler = { _ in StatusContext(ancestors: [ancestor], descendants: []) }
        await model.loadInitial()
        model.handleStreamEvent(.conversation(conversationId: "conversation", unread: false, lastStatus: incoming))
        model.draftMessage = "Keep this unfinished message"
        api.fetchStatusContextHandler = { _ in throw URLError(.notConnectedToInternet) }
        await model.refresh()
        #expect(model.messages.map(\.id) == ["99", "100", "101"])
        #expect(model.draftMessage == "Keep this unfinished message")
        if case .error = model.loadingState {} else { Issue.record("Expose a recoverable refresh error") }

        api.fetchStatusContextHandler = { _ in StatusContext(ancestors: [ancestor, last], descendants: []) }
        await model.refresh()
        #expect(model.messages.map(\.id) == ["99", "100", "101"])
        #expect(model.draftMessage == "Keep this unfinished message")
        if case .loaded = model.loadingState {} else { Issue.record("Clear the error after retry") }
    }

    @Test @MainActor func profileStopsAutomaticallyScanningAfterThreeEmptyReplyPages() async {
        let api = MockMastodonAPI()
        var page = 0
        api.fetchAccountStatusesHandler = { _, _, _, _, _, _, _, _ in
            page += 1
            return (0..<20).map { makeStatus(id: "\(page)-\($0)") }
        }
        let model = ProfileViewModel(apiClient: api, accountID: "account")
        model.selectTab(.replies)
        await model.loadTabIfNeeded(.replies)
        #expect(model.shouldAutomaticallyContinueEmptyPage)
        await model.loadMore()
        #expect(model.shouldAutomaticallyContinueEmptyPage)
        await model.loadMore()
        #expect(!model.shouldAutomaticallyContinueEmptyPage)
        #expect(model.hasMore && model.currentStatuses.isEmpty)
        #expect(model.paginationCursor == "3-19")
    }

    @Test @MainActor func profileTagFilterAlsoAppliesToLivePostAndPinEvents() async {
        let api = MockMastodonAPI()
        let account = makeAccount(id: "live-tag-owner")
        api.accountFeaturedTagsHandler = { _ in [FeaturedTag(id: "app-tag", name: "app")] }
        api.taggedStatusesHandler = { _, _, _, _ in [] }
        let model = ProfileViewModel(apiClient: api, accountID: account.id)
        await model.loadFeaturedTags()
        await model.selectFeaturedTag("app")
        let matching = makeStatus(id: "matching", account: account,
            tags: [.init(name: "APP", url: URL(string: "https://example.org/tags/app")!)], pinned: true)
        let unrelated = makeStatus(id: "unrelated", account: account, pinned: true)
        FeedCoordinator.shared.publishUpdate(.createdPost(unrelated))
        FeedCoordinator.shared.publishUpdate(.post(unrelated))
        #expect(model.posts.isEmpty && model.pinnedStatuses.isEmpty)
        FeedCoordinator.shared.publishUpdate(.createdPost(matching))
        FeedCoordinator.shared.publishUpdate(.post(matching))
        #expect(model.posts.map(\.id) == ["matching"])
        #expect(model.pinnedStatuses.map(\.id) == ["matching"])
        FeedCoordinator.shared.publishUpdate(.post(makeStatus(id: "matching", account: account, pinned: true)))
        #expect(model.posts.isEmpty && model.pinnedStatuses.isEmpty)
    }

    @Test @MainActor func profilePreservesPreviouslyAcceptedTextWhenLimitsAreLowered() async throws {
        let api = MockMastodonAPI()
        let raw = String(repeating: "x", count: 540) + " https://example.org/keep"
        let value = "https://example.org/" + String(repeating: "x", count: 300)
        let source = EditableProfile(id: "account", displayName: "Name", note: raw,
            fields: [.init(name: "Website", value: value), .init(name: "Other", value: "Value")])
        api.fetchEditableProfileHandler = { source }
        api.verifyCredentialsHandler = { makeAccount() }
        api.updateAccountProfileHandler = { _, _, _, _, _, _, _ in makeAccount() }
        let basic = EditProfileViewModel(apiClient: api, initialAccount: makeAccount(), scope: .basic)
        await basic.load()
        basic.displayName = "Changed"
        #expect(await basic.save(to: AppState()))
        #expect(api.updateAccountProfileCalls.last?.note == nil)
        basic.updateNote(String(raw.dropLast()))
        #expect(basic.note.count == raw.count - 1)
        let fields = EditProfileViewModel(apiClient: api, initialAccount: makeAccount(), scope: .fields)
        await fields.load()
        fields.moveFields(from: IndexSet(integer: 0), to: 2)
        #expect(await fields.save(to: AppState()))
        #expect(api.updateAccountProfileCalls.last?.fields?.last?.value == value)
    }

    @Test @MainActor func failedMediaRefreshCannotReplaceANewerPreferenceResult() async {
        let api = MockMastodonAPI()
        let started = AsyncStream<Void>.makeStream()
        var pending: CheckedContinuation<[Status], Error>?
        let oldAccount = makeAccount(showMedia: true, showMediaReplies: false)
        api.verifyCredentialsHandler = { oldAccount }
        api.fetchAccountStatusesHandler = { _, _, _, _, excludeReplies, _, onlyMedia, _ in
            if onlyMedia && excludeReplies {
                return try await withCheckedThrowingContinuation { continuation in
                    pending = continuation
                    started.continuation.yield(())
                }
            }
            return onlyMedia ? [makeStatus(id: "current-media")] : []
        }
        let model = ProfileViewModel(apiClient: api, accountID: "account", currentAccountID: "account")
        model.account = oldAccount
        model.selectTab(.media)
        let refresh = Task { await model.refresh() }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        model.account = makeAccount(showMedia: true, showMediaReplies: true)
        await model.loadTabIfNeeded(.media)
        pending?.resume(throwing: MockMastodonAPI.MockError.forcedFailure)
        await refresh.value
        #expect(model.tabLoadState(for: .media) == .loaded)
        #expect(model.media.map(\.id) == ["current-media"])
    }

    @Test @MainActor func profileDisplaySaveKeepsLocalDraftWhenTheServerFails() async throws {
        let suite = "profile-display-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ProfilePresentationPreferences(defaults: defaults)
        let api = MockMastodonAPI()
        let source = EditableProfile(id: "account", displayName: "Name", note: "", fields: [],
            showMedia: true, showMediaReplies: true, showFeatured: true, hideCollections: false)
        api.fetchEditableProfileHandler = { source }
        var fails = true
        var savedUpdate: ProfileDisplayUpdate?
        api.profileDisplayUpdateHandler = { update in
            savedUpdate = update
            if fails { throw MockMastodonAPI.MockError.forcedFailure }
            return source
        }
        api.verifyCredentialsHandler = { makeAccount(showMedia: false) }
        let model = ProfileDisplayViewModel(apiClient: api, accountKey: "A", preferences: preferences)
        await model.load()
        model.showTags = false
        model.showMedia = false
        #expect(await model.save(to: AppState()) == false)
        #expect(model.hasChanges)
        #expect(preferences.showsFeaturedTags(accountKey: "A"))
        #expect(savedUpdate?.showMedia == false)
        #expect(savedUpdate?.showMediaReplies == nil)
        fails = false
        #expect(await model.save(to: AppState()))
        #expect(!preferences.showsFeaturedTags(accountKey: "A"))
        #expect(preferences.showsFeaturedTags(accountKey: "B"))
        #expect(!model.hasChanges)
    }

    @Test @MainActor func legacyProfileDisplayOnlyUpdatesSupportedCredentials() async {
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = { EditableProfile(id: "account", displayName: "", note: "", fields: []) }
        var hidden: Bool?
        api.credentialsUpdateHandler = { value in hidden = value; return makeAccount() }
        let model = ProfileDisplayViewModel(apiClient: api, accountKey: "legacy-test")
        await model.load()
        #expect(!model.supportsMedia && !model.supportsFeatured)
        model.showConnections = false
        #expect(await model.save(to: AppState()))
        #expect(hidden == true)
    }

    @Test @MainActor func mediaPreferenceChangesDiscardAnOldRequestAndHideTheTab() async {
        let api = MockMastodonAPI()
        let started = AsyncStream<Void>.makeStream()
        var oldRequest: CheckedContinuation<[Status], Error>?
        api.fetchAccountStatusesHandler = { _, _, _, _, excludeReplies, _, _, _ in
            if excludeReplies {
                return try await withCheckedThrowingContinuation { continuation in
                    oldRequest = continuation
                    started.continuation.yield(())
                }
            }
            return [makeStatus(id: "media-with-replies")]
        }
        let model = ProfileViewModel(apiClient: api, accountID: "account")
        model.account = makeAccount(showMedia: true, showMediaReplies: false)
        model.selectTab(.media)
        let oldLoad = Task { await model.loadTabIfNeeded(.media) }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        model.account = makeAccount(showMedia: true, showMediaReplies: true)
        await model.loadTabIfNeeded(.media)
        oldRequest?.resume(returning: [makeStatus(id: "outdated-media")])
        await oldLoad.value
        #expect(model.media.map(\.id) == ["media-with-replies"])
        model.account = makeAccount(showMedia: false, showMediaReplies: true)
        #expect(model.availableTabs == [.posts, .replies])
        #expect(model.selectedTab == .posts)
    }

    @Test @MainActor func profileTagChangesDiscardLateResponsesAndResetPagination() async throws {
        let api = MockMastodonAPI()
        let account = makeAccount()
        api.accountFeaturedTagsHandler = { _ in [FeaturedTag(id: "a", name: "old"), FeaturedTag(id: "b", name: "new")] }
        let started = AsyncStream<Void>.makeStream()
        var oldRequest: CheckedContinuation<[Status], Error>?
        api.taggedStatusesHandler = { _, tag, maxID, pinned in
            if tag == "old", !pinned {
                return try await withCheckedThrowingContinuation { continuation in
                    oldRequest = continuation
                    started.continuation.yield(())
                }
            }
            if tag == "new" {
                if pinned { return [makeStatus(id: "new-0")] }
                if maxID != nil { return [] }
                return (0..<20).map { makeStatus(id: "new-\($0)") }
            }
            return []
        }
        let model = ProfileViewModel(apiClient: api, accountID: account.id)
        await model.loadFeaturedTags()
        let oldLoad = Task { await model.selectFeaturedTag("old") }
        var iterator = started.stream.makeAsyncIterator()
        await iterator.next()
        await model.selectFeaturedTag("new")
        oldRequest?.resume(returning: [makeStatus(id: "stale-old")])
        await oldLoad.value
        #expect(model.selectedFeaturedTag == "new")
        #expect(model.currentStatuses.count == 19)
        #expect(model.pinnedStatuses.map(\.id) == ["new-0"])
        let displayedIDs = Set(model.currentStatuses.map(\.id))
        #expect(!displayedIDs.contains("stale-old"))
        #expect(!displayedIDs.contains("new-0"))
        await model.loadMore()
        #expect(api.taggedStatusesCalls.last?.maxID == "new-19")
        await model.setFeaturedTagsEnabled(false)
        #expect(model.selectedFeaturedTag == nil)
        #expect(!model.showsFeaturedTags)
        #expect(api.taggedStatusesCalls.suffix(2).allSatisfy { $0.maxID == nil && $0.tag == nil })
    }

    @Test @MainActor func featuredTagRemovalWaitsForTheServerAndKeepsFailedRows() async {
        let api = MockMastodonAPI()
        let tag = FeaturedTag(id: "featured-entity-id", name: "moro")
        api.ownFeaturedTagsHandler = { [tag] }
        var fails = true
        var deletedID: String?
        api.unfeatureTagHandler = { id in
            deletedID = id
            if fails { throw MockMastodonAPI.MockError.forcedFailure }
        }
        let model = FeaturedTagsViewModel(apiClient: api)
        await model.load()
        await model.remove(tag)
        #expect(model.tags == [tag])
        #expect(model.error != nil)
        #expect(deletedID == tag.id)
        fails = false
        await model.remove(tag)
        #expect(model.tags.isEmpty)
    }


    @Test @MainActor func profileBasicEditPreservesRawLinksAndOmitsUnchangedFields() async throws {
        let api = MockMastodonAPI()
        let raw = "Hello\nhttps://example.org/full/path?query=value\n:custom_emoji:"
        let source = EditableProfile(id: "account", displayName: "Original", note: raw,
            fields: [AccountField(name: "Website", value: "https://example.org/full/path")])
        api.fetchEditableProfileHandler = { source }
        let account = makeAccount()
        api.verifyCredentialsHandler = { account }
        api.updateAccountProfileHandler = { _, _, _, _, _, _, _ in account }
        let model = EditProfileViewModel(apiClient: api, initialAccount: account, scope: .basic)
        await model.load()
        #expect(model.note == raw)
        #expect(!model.hasUnsavedChanges)
        model.displayName = "New name"
        #expect(await model.save(to: AppState()))
        let request = try #require(api.updateAccountProfileCalls.first)
        #expect(request.displayName == "New name")
        #expect(request.note == nil)
        #expect(request.fields == nil)
        #expect(model.note == raw)
    }

    @Test @MainActor func profileFieldReorderingPreservesValuesAndDetectsConcurrentEdits() async throws {
        let api = MockMastodonAPI()
        let original = EditableProfile(id: "account", displayName: "Name", note: "Bio",
            fields: [AccountField(name: "First", value: "https://example.org/a?x=1&y=2"),
                     AccountField(name: "Second", value: "  retained spacing  ")])
        var source = original
        api.fetchEditableProfileHandler = { source }
        let account = makeAccount()
        api.verifyCredentialsHandler = { account }
        api.updateAccountProfileHandler = { _, _, _, _, _, _, _ in account }
        let model = EditProfileViewModel(apiClient: api, initialAccount: account, scope: .fields)
        await model.load()
        let fieldIDs = model.fields.map(\.id)
        model.moveFields(from: IndexSet(integer: 0), to: 2)
        #expect(model.fields.map(\.id) == Array(fieldIDs.reversed()))
        #expect(await model.save(to: AppState()))
        let request = try #require(api.updateAccountProfileCalls.first)
        #expect(request.fields?.map(\.value) == original.fields.reversed().map(\.value))
        #expect(request.note == nil && request.displayName == nil)

        let other = EditProfileViewModel(apiClient: api, initialAccount: account, scope: .fields)
        await other.load()
        other.fields[0].name = "Edited"
        source = EditableProfile(id: "account", displayName: "Name", note: "Bio", fields: [])
        #expect(await other.save(to: AppState()) == false)
        #expect(api.updateAccountProfileCalls.count == 1)
        #expect(other.fields[0].name == "Edited")
    }

    @Test @MainActor func profileCannotSaveWithoutEditableSource() async {
        let api = MockMastodonAPI()
        let model = EditProfileViewModel(apiClient: api, initialAccount: makeAccount(), scope: .basic)
        await model.load()
        model.displayName = "Changed"
        #expect(model.loadError != nil)
        #expect(!model.canSave)
        #expect(await model.save(to: AppState()) == false)
        #expect(api.updateAccountProfileCalls.isEmpty)
    }

    @Test @MainActor func profileSourceAndDisplayPreferencesSurviveAccountCacheUpdates() throws {
        let data = Data(#"{"id":"1","username":"tester","show_media":false,"show_media_replies":true,"show_featured":false,"hide_collections":true,"source":{"note":"raw https://example.org/full","fields":[{"name":"Web","value":"https://example.org/full"}]}}"#.utf8)
        let account = try JSONDecoder().decode(Account.self, from: data)
        for copy in [account.updating(followersCount: 3), account.withCacheBustedMedia()] {
            #expect(copy.showMedia == false)
            #expect(copy.showMediaReplies == true)
            #expect(copy.showFeatured == false)
            #expect(copy.hideCollections == true)
            #expect(copy.source?.fields?.first?.value == "https://example.org/full")
            let decoded = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(copy))
            #expect(decoded.source?.note == "raw https://example.org/full")
            #expect(decoded.showMedia == false)
        }
    }


    @Test func notificationContentEventsUseTheDisplayedPostAuthor() {
        let actor = makeAccount(id: "notification-actor")
        let author = makeAccount(id: "post-author")
        let status = makeStatus(id: "edited", account: author)
        for type in ["poll", "update"] {
            let item = NotificationDisplayItem(from: makeNotification(
                id: type, type: type, account: actor, status: status
            ))
            #expect(item.presentationAccount?.id == author.id)
        }
        let like = NotificationDisplayItem(from: makeNotification(
            id: "like", type: "favourite", account: actor, status: status
        ))
        #expect(like.presentationAccount?.id == actor.id)
        let missing = NotificationDisplayItem(from: makeNotification(
            id: "missing", type: "poll", account: actor
        ))
        #expect(missing.presentationAccount?.id == actor.id)
    }

    @Test @MainActor func composerPublishesReorderedMediaWithoutChangingAltText() async throws {
        let api = MockMastodonAPI()
        var postedIDs: [String] = []
        api.postStatusHandler = { _, _, ids, _, _, _, _, _, _ in
            postedIDs = ids ?? []
            return makeStatus(id: "published")
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api)
        model.content = "Body"
        model.mediaAttachments = (1...3).map { index in
            MediaAttachment(id: "media-\(index)", url: URL(string: "https://example.com/\(index).png")!,
                previewURL: nil, type: "image", description: "ALT \(index)", focus: nil,
                originalDescription: "ALT \(index)", uploadState: .uploaded)
        }
        model.moveMedia(from: IndexSet(integer: 0), to: 3)
        _ = try await model.publish()
        #expect(postedIDs == ["media-2", "media-3", "media-1"])
        #expect(model.mediaAttachments.map(\.description) == ["ALT 2", "ALT 3", "ALT 1"])
    }


    @Test func accountDeletionURLPointsDirectlyToMastodonDeletionPage() throws {
        let instanceURL = try #require(URL(string: "https://social.example/path?source=moro#account"))

        let deletionURL = MastodonAccountDeletionURL.make(from: instanceURL)

        #expect(deletionURL?.absoluteString == "https://social.example/settings/delete")
    }

    @Test func accountDeletionURLPreservesInstancePort() throws {
        let instanceURL = try #require(URL(string: "https://social.example:8443"))

        let deletionURL = MastodonAccountDeletionURL.make(from: instanceURL)

        #expect(deletionURL?.absoluteString == "https://social.example:8443/settings/delete")
    }

    @Test func accountDeletionURLRejectsNonHTTPSAddress() throws {
        let instanceURL = try #require(URL(string: "http://social.example"))

        #expect(MastodonAccountDeletionURL.make(from: instanceURL) == nil)
    }

    @Test @MainActor func monochromeDarkThemeUsesPureBlackBackground() async throws {
        let colors = MoroColors(colorScheme: .dark, accent: .monochrome)
        let background = UIColor(colors.background)
        var white: CGFloat = 1
        var alpha: CGFloat = 1
        background.getWhite(&white, alpha: &alpha)

        #expect(white == 0)
        #expect(alpha == 1)
    }

    @Test @MainActor func monochromeDarkThemeUsesDarkForegroundOnPrimaryFill() async throws {
        let colors = MoroColors(colorScheme: .dark, accent: .monochrome)
        let foreground = UIColor(colors.primaryForeground)
        var white: CGFloat = 1
        var alpha: CGFloat = 1
        foreground.getWhite(&white, alpha: &alpha)

        #expect(white < 0.1)
        #expect(alpha == 1)
    }

    @Test @MainActor func statusAllowsReblogActionOnlyForPublicOrUnlisted() async throws {
        let publicStatus = makeStatus(id: "public", visibility: "public")
        let unlistedStatus = makeStatus(id: "unlisted", visibility: "unlisted")
        let privateStatus = makeStatus(id: "private", visibility: "private")
        let directStatus = makeStatus(id: "direct", visibility: "direct")

        #expect(publicStatus.allowsReblogAction)
        #expect(unlistedStatus.allowsReblogAction)
        #expect(privateStatus.allowsReblogAction == false)
        #expect(directStatus.allowsReblogAction == false)
    }

    @Test @MainActor func statusIncorporatingDisplayStatusUpdateKeepsReblogWrapperID() async throws {
        let original = makeStatus(id: "original")
        let wrapper = makeStatus(id: "wrapper", reblog: Indirect(original))
        let updatedOriginal = Status(
            id: "original",
            content: "updated",
            createdAt: original.createdAt,
            account: original.account,
            mediaAttachments: [],
            favouritesCount: 7,
            reblogsCount: 3,
            repliesCount: 1,
            bookmarked: true,
            favourited: true,
            reblogged: true
        )

        let merged = wrapper.incorporatingDisplayStatusUpdate(updatedOriginal)

        #expect(merged.id == "wrapper")
        #expect(merged.displayStatus.id == "original")
        #expect(merged.displayStatus.content == "updated")
        #expect(merged.displayStatus.favouritesCount == 7)
        #expect(merged.favourited)
        #expect(merged.bookmarked)
        #expect(merged.reblogged)
    }

    @Test @MainActor func hashtagTimelineIncorporatesPostInteractionUpdates() async throws {
        let original = makeStatus(id: "hashtag-original")
        let viewModel = HashtagViewModel(
            apiClient: MockMastodonAPI(),
            hashtag: "swift"
        )
        viewModel.statuses = [original]

        let interacted = Status(
            id: original.id,
            content: original.content,
            createdAt: original.createdAt,
            account: original.account,
            mediaAttachments: original.mediaAttachments,
            favouritesCount: 1,
            reblogsCount: 1,
            repliesCount: original.repliesCount,
            bookmarked: true,
            favourited: true,
            reblogged: true
        )

        FeedCoordinator.shared.publishUpdate(.post(interacted))

        let updated = try #require(viewModel.statuses.first)
        #expect(updated.id == original.id)
        #expect(updated.favourited)
        #expect(updated.favouritesCount == 1)
        #expect(updated.reblogged)
        #expect(updated.reblogsCount == 1)
        #expect(updated.bookmarked)

        FeedCoordinator.shared.publishUpdate(.post(original))

        let rolledBack = try #require(viewModel.statuses.first)
        #expect(rolledBack.favourited == false)
        #expect(rolledBack.reblogged == false)
        #expect(rolledBack.bookmarked == false)
    }

    @Test @MainActor func hashtagTimelineUpdatesEveryReblogWrapperForCanonicalPost() async throws {
        let original = makeStatus(id: "canonical-status")
        let firstWrapper = makeStatus(id: "wrapper-1", reblog: Indirect(original))
        let secondWrapper = makeStatus(id: "wrapper-2", reblog: Indirect(original))
        let viewModel = HashtagViewModel(
            apiClient: MockMastodonAPI(),
            hashtag: "swift"
        )
        viewModel.statuses = [firstWrapper, secondWrapper]

        let canonicalUpdate = Status(
            id: original.id,
            content: original.content,
            createdAt: original.createdAt,
            account: original.account,
            mediaAttachments: original.mediaAttachments,
            favouritesCount: 4,
            reblogsCount: 2,
            repliesCount: original.repliesCount,
            bookmarked: false,
            favourited: true,
            reblogged: true
        )

        FeedCoordinator.shared.publishUpdate(.post(canonicalUpdate))

        #expect(viewModel.statuses.map(\.id) == ["wrapper-1", "wrapper-2"])
        #expect(viewModel.statuses.allSatisfy { $0.displayStatus.favourited })
        #expect(viewModel.statuses.allSatisfy { $0.displayStatus.favouritesCount == 4 })
        #expect(viewModel.statuses.allSatisfy { $0.displayStatus.reblogged })
        #expect(viewModel.statuses.allSatisfy { $0.displayStatus.reblogsCount == 2 })
    }

    @Test func threadedConversationPreservesAPISiblingOrderAndDepth() {
        let baseDate = Date(timeIntervalSince1970: 1_000)
        let focusedAccount = makeAccount(id: "focused-author")
        let focused = makeStatus(
            id: "focused",
            createdAt: baseDate,
            account: focusedAccount
        )
        let firstReply = makeStatus(
            id: "first",
            createdAt: baseDate.addingTimeInterval(10),
            inReplyToID: focused.id
        )
        let secondReply = makeStatus(
            id: "second",
            createdAt: baseDate.addingTimeInterval(20),
            inReplyToID: focused.id
        )
        let nestedReply = makeStatus(
            id: "nested",
            createdAt: baseDate.addingTimeInterval(30),
            account: focusedAccount,
            inReplyToID: firstReply.id
        )
        let hiddenReply = makeStatus(
            id: "hidden",
            createdAt: baseDate.addingTimeInterval(40),
            inReplyToID: firstReply.id
        )
        let model = ThreadedConversationModel(
            focusedStatus: focused,
            context: StatusContext(
                ancestors: [],
                descendants: [hiddenReply, nestedReply, secondReply, firstReply]
            )
        )

        // Keep sibling order from the API even when children arrive before their parent.
        #expect(
            model.threadItems.map(\.status.id)
                == ["focused", "second", "first", "hidden", "nested"]
        )
        #expect(model.threadItems.map(\.replyDepth) == [0, 0, 0, 1, 1])
    }

    @Test @MainActor func statusDetailUsesCountsFromFreshCachedThread() async throws {
        let statusID = "detail-fresh-\(UUID().uuidString)"
        let replyID = "reply-fresh-\(UUID().uuidString)"
        let initialStatus = makeStatus(id: statusID)
        let cachedStatus = makeStatus(
            id: statusID,
            favouritesCount: 44,
            reblogsCount: 14,
            repliesCount: 2
        )
        let cachedReply = makeStatus(
            id: replyID,
            favouritesCount: 2,
            repliesCount: 1,
            inReplyToID: statusID
        )
        let cachedThread = ThreadedConversationModel(
            focusedStatus: cachedStatus,
            context: StatusContext(ancestors: [], descendants: [cachedReply])
        )
        let threadCache = ThreadCache()
        threadCache.set(cachedThread, for: statusID)
        let api = MockMastodonAPI()
        let viewModel = StatusDetailViewModel(
            status: initialStatus,
            apiClient: api,
            threadCache: threadCache,
            accountCache: AccountCache(),
            // This case verifies a fresh cache hit, independent of CI scheduling delays.
            // Stale-cache revalidation is exercised separately below.
            cacheFreshnessInterval: .infinity
        )

        await viewModel.loadThread()

        #expect(viewModel.focusedStatus.favouritesCount == 44)
        #expect(viewModel.focusedStatus.reblogsCount == 14)
        #expect(viewModel.focusedStatus.repliesCount == 2)
        let reply = try #require(
            viewModel.threadModel?.threadItems.first(where: { $0.status.id == replyID })?.status
        )
        #expect(reply.favouritesCount == 2)
        #expect(reply.repliesCount == 1)
        #expect(api.fetchStatusDetailCallIDs.isEmpty)
        #expect(api.fetchStatusContextCallIDs.isEmpty)
    }

    @Test @MainActor func statusDetailRevalidatesStaleCachedInteractionCounts() async throws {
        let statusID = "detail-stale-\(UUID().uuidString)"
        let replyID = "reply-stale-\(UUID().uuidString)"
        let initialStatus = makeStatus(id: statusID)
        let staleReply = makeStatus(id: replyID, inReplyToID: statusID)
        let staleThread = ThreadedConversationModel(
            focusedStatus: initialStatus,
            context: StatusContext(ancestors: [], descendants: [staleReply])
        )
        let threadCache = ThreadCache()
        threadCache.set(
            staleThread,
            for: statusID,
            timestamp: Date().addingTimeInterval(-30)
        )

        let refreshedStatus = makeStatus(
            id: statusID,
            favouritesCount: 44,
            reblogsCount: 14,
            repliesCount: 2
        )
        let refreshedReply = makeStatus(
            id: replyID,
            favouritesCount: 2,
            repliesCount: 1,
            inReplyToID: statusID
        )
        let api = MockMastodonAPI()
        api.fetchStatusDetailHandler = { id in
            #expect(id == statusID)
            return refreshedStatus
        }
        api.fetchStatusContextHandler = { id in
            #expect(id == statusID)
            return StatusContext(ancestors: [], descendants: [refreshedReply])
        }
        let viewModel = StatusDetailViewModel(
            status: initialStatus,
            apiClient: api,
            threadCache: threadCache,
            accountCache: AccountCache()
        )

        await viewModel.loadThread()

        #expect(viewModel.focusedStatus.favouritesCount == 44)
        #expect(viewModel.focusedStatus.reblogsCount == 14)
        #expect(viewModel.focusedStatus.repliesCount == 2)
        let reply = try #require(
            viewModel.threadModel?.threadItems.first(where: { $0.status.id == replyID })?.status
        )
        #expect(reply.favouritesCount == 2)
        #expect(reply.repliesCount == 1)
        #expect(api.fetchStatusDetailCallIDs == [statusID])
        #expect(api.fetchStatusContextCallIDs == [statusID])
    }

    @Test @MainActor func statusDetailRevalidationKeepsNewerInteractionUpdate() async throws {
        let statusID = "detail-race-\(UUID().uuidString)"
        let cachedStatus = makeStatus(id: statusID, favouritesCount: 1)
        let staleThread = ThreadedConversationModel(
            focusedStatus: cachedStatus,
            context: StatusContext(ancestors: [], descendants: [])
        )
        let threadCache = ThreadCache()
        threadCache.set(
            staleThread,
            for: statusID,
            timestamp: Date().addingTimeInterval(-30)
        )

        let detailRequests = AsyncStream<CheckedContinuation<Status, Never>>.makeStream()
        let contextRequests = AsyncStream<CheckedContinuation<StatusContext, Never>>.makeStream()
        defer {
            detailRequests.continuation.finish()
            contextRequests.continuation.finish()
        }
        let api = MockMastodonAPI()
        api.fetchStatusDetailHandler = { _ in
            await withCheckedContinuation { detailRequests.continuation.yield($0) }
        }
        api.fetchStatusContextHandler = { _ in
            await withCheckedContinuation { contextRequests.continuation.yield($0) }
        }
        let viewModel = StatusDetailViewModel(
            status: cachedStatus,
            apiClient: api,
            threadCache: threadCache,
            accountCache: AccountCache()
        )

        let loadTask = Task { await viewModel.loadThread() }
        // Hold both GET responses until the interaction has happened, regardless
        // of how long the runner takes to start or schedule the requests.
        var detailIterator = detailRequests.stream.makeAsyncIterator()
        var contextIterator = contextRequests.stream.makeAsyncIterator()
        let detailResponse = try #require(await detailIterator.next())
        let contextResponse = try #require(await contextIterator.next())
        let interactedStatus = makeStatus(
            id: statusID,
            favouritesCount: 2,
            favourited: true
        )
        viewModel.updateStatus(interactedStatus)
        detailResponse.resume(returning: cachedStatus)
        contextResponse.resume(returning: StatusContext(ancestors: [], descendants: []))
        await loadTask.value

        #expect(viewModel.focusedStatus.favouritesCount == 2)
        #expect(viewModel.focusedStatus.favourited)
    }

    @Test func postActionAnimationScheduleUsesHighestPriorityActiveCampaign() {
        let date = Date(timeIntervalSince1970: 10_000)
        let defaultPreset = PostActionAnimationPreset(id: "default", effect: .symbolBounce)
        let schedule = PostActionAnimationSchedule(
            defaultPresets: [.like: defaultPreset],
            campaigns: [
                PostActionAnimationCampaign(
                    id: "low-priority",
                    interval: DateInterval(
                        start: date.addingTimeInterval(-100),
                        end: date.addingTimeInterval(100)
                    ),
                    priority: 1,
                    presets: [.like: .init(id: "low", effect: .heartBloom(.standard))]
                ),
                PostActionAnimationCampaign(
                    id: "high-priority",
                    interval: DateInterval(
                        start: date.addingTimeInterval(-50),
                        end: date.addingTimeInterval(50)
                    ),
                    priority: 2,
                    presets: [.like: .init(id: "high", effect: .heartBloom(.standard))]
                ),
            ]
        )

        #expect(schedule.preset(for: .like, at: date).id == "high")
        #expect(schedule.preset(for: .like, at: date.addingTimeInterval(200)).id == "default")
        #expect(schedule.preset(for: .bookmark, at: date).id == "fallback")
    }

    @Test func standardBookmarkAnimationUsesDropFeedback() {
        let usesDropFeedback: Bool
        switch PostActionAnimationSchedule.standard.preset(for: .bookmark).effect {
        case .bookmarkDrop:
            usesDropFeedback = true
        case .symbolBounce, .heartBloom:
            usesDropFeedback = false
        }

        #expect(usesDropFeedback)
    }

    @Test func heartBloomTimelineFinishesWithStableHeartAndNoDecoration() {
        let early = HeartBloomTimeline.frame(at: 0.15)
        let middle = HeartBloomTimeline.frame(at: 0.5)
        let completed = HeartBloomTimeline.frame(at: 1)

        #expect(HeartBloomPreset.standard.particleCount == 7)
        #expect(early.outerRadius > 0)
        #expect(middle.holeRadius > 0)
        #expect(middle.holeRadius < middle.outerRadius)
        #expect(middle.heartOpacity > 0)
        #expect(completed.ringOpacity == 0)
        #expect(completed.particleOpacity == 0)
        #expect(abs(completed.heartScale - 1) < 0.001)
        #expect(completed.heartOpacity == 1)
    }

    @Test func heartBloomPresetBoundsUnsafeConfiguration() {
        let preset = HeartBloomPreset(
            duration: -1,
            ringColor: .red,
            particleColors: [.red],
            particleCount: 200
        )

        #expect(preset.effectiveDuration == 0.1)
        #expect(preset.effectiveParticleCount == 14)
        #expect(PostActionEffect.heartBloom(preset).duration == 0.1)
    }

    @Test func contentParserPreservesHTMLLineBreakVariants() async throws {
        let elements = ContentParser.parseToElements(
            html: #"<p>第一行<br/>第二行<br class="soft-break" />第三行<BR>第四行</p>"#
        )

        #expect(
            elements == [
                .text("第一行"),
                .lineBreak,
                .text("第二行"),
                .lineBreak,
                .text("第三行"),
                .lineBreak,
                .text("第四行"),
            ]
        )
        #expect(elements.plainTextValue == "第一行\n第二行\n第三行\n第四行")
    }

    @Test @MainActor func statusContentAndEmojiMetadataResolveEveryEmojiOccurrence() throws {
        let emojiSpecs = [
            ("ablobangel", "000/002/817"),
            ("ablobblewobble", "000/002/819"),
            ("ablobcall", "000/002/820"),
            ("ablobcaramelldansen", "000/002/821"),
            ("Parrot04", "000/003/284"),
            ("Parrot08", "000/003/285"),
            ("Parrot09", "000/003/286"),
            ("usamaru004", "000/003/202"),
            ("usamaru049", "000/003/210"),
        ]
        let emojis = try emojiSpecs.map { shortcode, path in
            Status.Emoji(
                shortcode: shortcode,
                url: try #require(
                    URL(
                        string:
                            "https://media.somincola.org/custom_emojis/images/\(path)/original/\(shortcode).png"
                    )
                ),
                staticURL: try #require(
                    URL(
                        string:
                            "https://media.somincola.org/custom_emojis/images/\(path)/static/\(shortcode).png"
                    )
                )
            )
        }
        let content = "<p>:ablobangel: :ablobblewobble: :ablobcall: :ablobcaramelldansen: :Parrot04: :Parrot08: :Parrot09: :usamaru004: :usamaru004: :usamaru049: :usamaru049: </p><p>测试表情</p>"

        let elements = ContentParser.parseToElements(
            html: content,
            emojis: emojis,
            options: .statusBody
        )
        let parsedEmojis = elements.compactMap { element -> (String, URL, URL)? in
            guard case .emoji(let shortcode, let url, let staticURL) = element else {
                return nil
            }
            return (shortcode, url, staticURL)
        }
        let expectedShortcodes = [
            "ablobangel", "ablobblewobble", "ablobcall", "ablobcaramelldansen",
            "Parrot04", "Parrot08", "Parrot09", "usamaru004", "usamaru004",
            "usamaru049", "usamaru049",
        ]
        let metadataByShortcode = Dictionary(
            uniqueKeysWithValues: emojis.map { ($0.shortcode, $0) }
        )

        #expect(parsedEmojis.map { $0.0 } == expectedShortcodes)
        for (shortcode, originalURL, staticURL) in parsedEmojis {
            let metadata = try #require(metadataByShortcode[shortcode])
            #expect(originalURL == metadata.url)
            #expect(staticURL == metadata.staticURL)
        }
        #expect(elements.plainTextValue.contains("测试表情"))
    }

    @Test func contentParserPreservesParagraphSpacingAndOmitsKnownStatusTags() throws {
        let firstTagURL = try #require(URL(
            string: "https://m.somincola.org/tags/%E5%BC%80%E5%8F%91%E6%97%A5%E5%B8%B8"
        ))
        let secondTagURL = try #require(URL(
            string: "https://m.somincola.org/tags/app%E6%B5%8B%E8%AF%95"
        ))
        let tags = [
            Status.Tag(name: "开发日常", url: firstTagURL),
            Status.Tag(name: "app测试", url: secondTagURL),
        ]
        let html = #"<p>测试发帖格式<br />回车一行输入</p><p>回车两行，造成空格</p><p><a href="https://m.somincola.org/tags/%E5%BC%80%E5%8F%91%E6%97%A5%E5%B8%B8" class="mention hashtag" rel="tag">#<span>开发日常</span></a> <a href="https://m.somincola.org/tags/app%E6%B5%8B%E8%AF%95" class="mention hashtag" rel="tag">#<span>app测试</span></a></p>"#

        let bodyElements = ContentParser.parseToElements(
            html: html,
            tags: tags,
            options: .statusBody
        )
        let tagOnlyElements = ContentParser.parseToElements(
            html: #"<p><a href="https://m.somincola.org/tags/%E5%BC%80%E5%8F%91%E6%97%A5%E5%B8%B8" class="mention hashtag" rel="tag">#<span>开发日常</span></a></p>"#,
            tags: tags,
            options: .statusBody
        )
        let defaultElements = ContentParser.parseToElements(html: html, tags: tags)
        let inlineHashtagCount = defaultElements.reduce(into: 0) { count, element in
            if case .hashtag = element {
                count += 1
            }
        }

        #expect(
            bodyElements == [
                .text("测试发帖格式"),
                .lineBreak,
                .text("回车一行输入"),
                .lineBreak,
                .lineBreak,
                .text("回车两行，造成空格"),
            ]
        )
        #expect(bodyElements.plainTextValue == "测试发帖格式\n回车一行输入\n\n回车两行，造成空格")
        #expect(tagOnlyElements.isEmpty)
        #expect(inlineHashtagCount == 2)
    }

    @Test func contentParserSeparatesStatusMentionFromFollowingText() throws {
        let mentionURL = try #require(URL(string: "https://example.social/@tang"))
        let mention = Status.Mention(
            id: "tang",
            username: "tang",
            url: mentionURL,
            acct: "tang@example.social"
        )
        let attachedHTML = #"<p><a href="https://example.social/@tang" class="u-url mention">@<span>tang</span></a>quote (') 寫數據很方便</p>"#
        let punctuationHTML = #"<p><a href="https://example.social/@tang" class="u-url mention">@<span>tang</span></a>，歡迎</p>"#

        let statusElements = ContentParser.parseToElements(
            html: attachedHTML,
            mentions: [mention],
            options: .statusBody
        )
        let punctuationElements = ContentParser.parseToElements(
            html: punctuationHTML,
            mentions: [mention],
            options: .statusBody
        )
        let accountElements = ContentParser.parseToElements(
            html: attachedHTML,
            mentions: [mention],
            options: .accountRichText
        )

        #expect(statusElements == [
            .mention(username: "@tang", url: mentionURL),
            .text(" quote (') 寫數據很方便"),
        ])
        #expect(punctuationElements == [
            .mention(username: "@tang", url: mentionURL),
            .text("，歡迎"),
        ])
        #expect(accountElements.plainTextValue == "@tangquote (') 寫數據很方便")
    }

    @Test @MainActor func contentParserSeparatesAdjacentStatusMentions() throws {
        let jabsonikURL = try #require(URL(string: "https://ihan.outo.la/@jabsonik"))
        let mookieURL = try #require(URL(string: "https://bunnymotorsports.com/@mookie"))
        let html = #"<p><span class="h-card" translate="no"><a href="https://ihan.outo.la/@jabsonik" class="u-url mention">@<span>jabsonik</span></a></span> <span class="h-card" translate="no"><a href="https://bunnymotorsports.com/@mookie" class="u-url mention">@<span>mookie</span></a></span> </p><p>This is the first time I’ve received feedback.</p>"#
        let mentions = [
            Status.Mention(
                id: "jabsonik",
                username: "jabsonik",
                url: jabsonikURL,
                acct: "jabsonik@ihan.outo.la"
            ),
            Status.Mention(
                id: "mookie",
                username: "mookie",
                url: mookieURL,
                acct: "mookie@bunnymotorsports.com"
            ),
        ]

        let elements = ContentParser.parseToElements(
            html: html,
            mentions: mentions,
            options: .statusBody
        )

        #expect(Array(elements.prefix(3)) == [
            .mention(username: "@jabsonik", url: jabsonikURL),
            .text(" "),
            .mention(username: "@mookie", url: mookieURL),
        ])
        #expect(elements.plainTextValue.hasPrefix("@jabsonik @mookie\n\nThis is"))
    }

    @Test func contentParserPreservesStatusCodeBlocksInOrder() throws {
        let mentionURL = try #require(URL(string: "https://social.lomia.uk/@tan"))
        let mention = Status.Mention(
            id: "tan",
            username: "tan",
            url: mentionURL,
            acct: "tan@social.lomia.uk"
        )
        let html = #"""
        <a href="https://social.lomia.uk/@tan" class="u-url mention" rel="nofollow noopener" target="_blank">@tan@social.lomia.uk</a> quote (') 寫數據很方便。比如下面這個結果是 '(+ 1 2)<pre><code>(let ((empty '()))
          `(+ 1 2 ,@empty))</code></pre><br>數據也可以變成代碼，下面的結果是 3<pre><code>(eval '(+ 1 2) (interaction-environment))</code></pre><br>結果就會變成 -1<pre><code>(define my-env (make-module))
        (module-define! my-env '+ -)

        (eval '(+ 1 2) my-env)</code></pre>（例子裏用的是 Guile Scheme）
        """#

        let elements = ContentParser.parseToElements(
            html: html,
            mentions: [mention],
            options: .statusBody
        )
        let codeBlocks = elements.compactMap { element -> String? in
            guard case .codeBlock(let code) = element else { return nil }
            return code
        }

        #expect(codeBlocks == [
            "(let ((empty '()))\n  `(+ 1 2 ,@empty))",
            "(eval '(+ 1 2) (interaction-environment))",
            "(define my-env (make-module))\n(module-define! my-env '+ -)\n\n(eval '(+ 1 2) my-env)",
        ])
        #expect(elements.first == .mention(username: "@tan", url: mentionURL))
        #expect(elements.plainTextValue.contains("@tan quote (') 寫數據很方便"))
        #expect(elements.plainTextValue.contains("\n(let ((empty '()))\n  `(+ 1 2 ,@empty))\n數據也可以"))
        #expect(elements.plainTextValue.hasSuffix("（例子裏用的是 Guile Scheme）"))
    }

    @Test func contentParserPreservesInlineCodeAndDecodesEntities() {
        let elements = ContentParser.parseToElements(
            html: #"<p>Use <code>value &lt; limit</code> now</p>"#,
            options: .statusBody
        )

        #expect(elements == [
            .text("Use "),
            .inlineCode("value < limit"),
            .text(" now"),
        ])
        #expect(elements.plainTextValue == "Use value < limit now")
    }

    @Test func contentParserKeepsCodeParsingScopedToStatusBodies() {
        let elements = ContentParser.parseToElements(
            html: #"<p>Use <code>value</code> now</p>"#
        )

        #expect(elements == [.text("Use value now")])
    }

    @Test func attachmentDecodesPortraitMediaAspectRatio() throws {
        let data = Data(#"""
        {
            "id":"117029262068063929",
            "type":"image",
            "url":"https://media.example/original.jpeg",
            "preview_url":"https://media.example/small.jpeg",
            "description":null,
            "blurhash":"UGKd#m;c-o%L?b~q4.xuk?.9EMD%IA9E-p%0",
            "meta":{
                "original":{"width":1440,"height":1920,"aspect":0.75},
                "small":{"width":416,"height":554,"aspect":0.7509025270758123}
            }
        }
        """#.utf8)

        let attachment = try JSONDecoder().decode(Status.Attachment.self, from: data)

        #expect(attachment.aspectRatio == 0.75)
        #expect(attachment.previewAspectRatio == 0.7509025270758123)
    }

    @Test func singleImageLayoutPreservesWidePreviewAspectRatio() throws {
        let data = Data(#"""
        {
            "id":"wide-image",
            "type":"image",
            "url":"https://media.example/original.png",
            "preview_url":"https://media.example/small.png",
            "meta":{
                "original":{"width":2650,"height":1000,"aspect":2.65},
                "small":{"width":750,"height":283,"aspect":2.65018}
            }
        }
        """#.utf8)

        let attachment = try JSONDecoder().decode(Status.Attachment.self, from: data)

        #expect(MediaGridLayoutMetrics.singleImageAspectRatio(for: attachment) == 2.65018)
    }

    @Test func singleImageLayoutFallsBackToThreeByTwoWithoutMediaMetadata() throws {
        let data = Data(#"""
        {
            "id":"missing-media-metadata",
            "type":"image",
            "url":"https://media.example/original.png",
            "preview_url":"https://media.example/small.png"
        }
        """#.utf8)

        let attachment = try JSONDecoder().decode(Status.Attachment.self, from: data)

        #expect(
            MediaGridLayoutMetrics.singleImageAspectRatio(for: attachment)
                == MediaGridLayoutMetrics.fallbackSingleImageAspectRatio
        )
    }

    @Test func postTagStripUsesUniqueNonemptyStatusTags() throws {
        let firstURL = try #require(URL(string: "https://example.social/tags/swift"))
        let duplicateURL = try #require(URL(string: "https://example.social/tags/Swift/"))
        let secondURL = try #require(URL(string: "https://example.social/tags/ios"))
        let emptyURL = try #require(URL(string: "https://example.social/tags/empty"))

        let tags = PostTagStrip.displayTags(from: [
            Status.Tag(name: "Swift", url: firstURL),
            Status.Tag(name: "swift", url: duplicateURL),
            Status.Tag(name: " iOS ", url: secondURL),
            Status.Tag(name: "   ", url: emptyURL),
        ])

        #expect(tags.map(\.name) == ["Swift", "iOS"])
        #expect(tags.map(\.url) == [firstURL, secondURL])
    }

    @Test func contentParserHidesQuoteCompatibilityLink() {
        let elements = ContentParser.parseToElements(
            html: #"<p class="quote-inline">RE: <a href="https://o3o.ca/@nabiki1003/116957909500612061"><span class="invisible">https://</span><span class="ellipsis">o3o.ca/@nabiki1003/11695790950</span><span class="invisible">0612061</span></a></p><p>完了 想吃咖喱牛肉了</p>"#
        )

        #expect(elements.normalizedInlinePlainText == "完了 想吃咖喱牛肉了")
        #expect(!elements.plainTextValue.contains("o3o.ca"))
    }

    @Test func statusQuotePreservesPendingConsentState() throws {
        let pendingJSON = Data(#"{"state":"pending","quoted_status":null}"#.utf8)
        let quote = try JSONDecoder().decode(Status.Quote.self, from: pendingJSON)

        #expect(quote.state == .pending)
        #expect(quote.quotedStatus == nil)
        #expect(quote.displayableStatus == nil)
    }

    @Test func statusQuoteOnlyDisplaysAcceptedStatuses() {
        let quoted = makeStatus(id: "quoted-consent")
        let accepted = Status.Quote(state: .accepted, quotedStatus: quoted)
        let blocked = Status.Quote(state: .blockedAccount, quotedStatus: quoted)

        #expect(accepted.displayableStatus?.id == quoted.id)
        #expect(blocked.quotedStatus?.id == quoted.id)
        #expect(blocked.displayableStatus == nil)
    }

    @Test func statusQuoteTreatsUnknownStateAsUnauthorized() throws {
        let unknownJSON = Data(#"{"state":"future_state","quoted_status":null}"#.utf8)
        let quote = try JSONDecoder().decode(Status.Quote.self, from: unknownJSON)

        #expect(quote.state == .unauthorized)
        #expect(quote.displayableStatus == nil)
    }

    @Test func statusQuoteDecodesLegacyDirectStatus() throws {
        let quoted = makeStatus(id: "legacy-quoted")
        let data = try JSONEncoder().encode(quoted)
        let quote = try JSONDecoder().decode(Status.Quote.self, from: data)

        #expect(quote.state == .accepted)
        #expect(quote.displayableStatus?.id == quoted.id)
    }

    @Test func htmlParserPreservesHTMLLineBreakVariants() async throws {
        let text = HTMLParser.stripHTML(
            #"<p>第一行<br/>第二行<br class="soft-break" />第三行<BR>第四行</p>"#
        )

        #expect(text == "第一行\n第二行\n第三行\n第四行")
    }

    @Test func htmlParserSeparatesParagraphsWithAnEmptyLine() {
        let text = HTMLParser.stripHTML(
            "<p>第一段<br>段内换行</p><p class=\"body\">第二段</p>"
        )

        #expect(text == "第一段\n段内换行\n\n第二段")
    }

    @Test @MainActor func timelineViewModelUpdatesReblogWrapperWhenDisplayStatusChanges() async throws {
        let api = MockMastodonAPI()
        let viewModel = TimelineViewModel(apiClient: api)
        let original = makeStatus(id: "original")
        let wrapper = makeStatus(id: "wrapper", reblog: Indirect(original))
        viewModel.statuses = [wrapper]

        let updatedOriginal = Status(
            id: "original",
            content: "updated-original",
            createdAt: original.createdAt,
            account: original.account,
            mediaAttachments: [],
            favouritesCount: 4,
            reblogsCount: 2,
            repliesCount: 1,
            bookmarked: false,
            favourited: true,
            reblogged: false
        )

        viewModel.updateStatus(updatedOriginal)

        #expect(viewModel.statuses.count == 1)
        #expect(viewModel.statuses[0].id == "wrapper")
        #expect(viewModel.statuses[0].displayStatus.content == "updated-original")
        #expect(viewModel.statuses[0].displayStatus.favouritesCount == 4)
        #expect(viewModel.statuses[0].favourited)
    }

    @Test @MainActor func postInteractionServiceNormalizesFavouriteCountWhenServerReturnsStaleCount() async throws {
        let api = MockMastodonAPI()
        let feedCoordinator = FeedCoordinator.shared
        feedCoordinator.mostRecentUpdate = nil

        let favouritedStatus = Status(
            id: "status-1",
            content: "hello",
            createdAt: Date(),
            account: makeAccount(id: "acct-1"),
            mediaAttachments: [],
            favouritesCount: 3,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: true,
            reblogged: false
        )

        api.unfavouriteStatusHandler = { _ in
            Status(
                id: "status-1",
                content: "hello",
                createdAt: favouritedStatus.createdAt,
                account: favouritedStatus.account,
                mediaAttachments: [],
                favouritesCount: 3,
                reblogsCount: 0,
                repliesCount: 0,
                bookmarked: false,
                favourited: false,
                reblogged: false
            )
        }

        let service = PostInteractionService(apiClient: api, feedCoordinator: feedCoordinator)
        await service.toggleFavourite(favouritedStatus)

        guard case .post(let updatedStatus)? = feedCoordinator.mostRecentUpdate else {
            Issue.record("Expected a post update after unfavourite")
            return
        }

        #expect(updatedStatus.favourited == false)
        #expect(updatedStatus.favouritesCount == 2)
    }

    @Test @MainActor func postNavigationRoutesDetailToDisplayStatusByDefault() async throws {
        var capturedRoutes: [Route] = []
        let original = makeStatus(id: "original")
        let wrapper = makeStatus(id: "wrapper", reblog: Indirect(original))

        let handlers = PostNavigationActionCenter.handlers(
            for: wrapper,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onTapDetail()

        #expect(capturedRoutes.count == 1)
        #expect(capturedRoutes.first == .statusDetail(original))
    }

    @Test @MainActor func postNavigationRoutesDetailToExplicitStatusWhenProvided() async throws {
        var capturedRoutes: [Route] = []
        let status = makeStatus(id: "status")
        let explicit = makeStatus(id: "explicit")

        let handlers = PostNavigationActionCenter.handlers(
            for: status,
            detailStatus: explicit,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onTapDetail()

        #expect(capturedRoutes.count == 1)
        #expect(capturedRoutes.first == .statusDetail(explicit))
    }

    @Test @MainActor func postNavigationMentionTapPrefersURLThenUsername() async throws {
        var capturedRoutes: [Route] = []
        let byURL = Status.Mention(
            id: "m1",
            username: "alice",
            url: URL(string: "https://example.com/@alice")!,
            acct: "alice@example.com"
        )
        let byUsername = Status.Mention(
            id: "m2",
            username: "bob",
            url: URL(string: "https://example.com/@bob")!,
            acct: "bob@example.com"
        )
        let status = makeStatus(id: "status", mentions: [byURL, byUsername])

        let handlers = PostNavigationActionCenter.handlers(
            for: status,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onMentionTap("bob", URL(string: "https://example.com/@alice")!)
        handlers.onMentionTap("bob", URL(string: "https://not-matched.com")!)

        #expect(capturedRoutes.count == 2)
        #expect(capturedRoutes[0] == .mentionUser(byURL))
        #expect(capturedRoutes[1] == .mentionUser(byUsername))
    }

    @Test @MainActor func postNavigationMentionTapNoMatchDoesNotNavigate() async throws {
        var capturedRoutes: [Route] = []
        let onlyMention = Status.Mention(
            id: "m1",
            username: "alice",
            url: URL(string: "https://example.com/@alice")!,
            acct: "alice@example.com"
        )
        let status = makeStatus(id: "status", mentions: [onlyMention])

        let handlers = PostNavigationActionCenter.handlers(
            for: status,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onMentionTap("charlie", URL(string: "https://example.com/@charlie")!)

        #expect(capturedRoutes.isEmpty)
    }

    @Test @MainActor func postNavigationRoutesMediaAndProfileActions() async throws {
        var capturedRoutes: [Route] = []
        let status = makeStatus(id: "status")
        let replyMention = Status.Mention(
            id: "m-reply",
            username: "replyUser",
            url: URL(string: "https://example.com/@reply")!,
            acct: "reply@example.com"
        )
        let mediaURL = URL(string: "https://example.com/media.png")!

        let handlers = PostNavigationActionCenter.handlers(
            for: status,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onAvatarTap()
        handlers.onUsernameTap()
        handlers.onImageTap(mediaURL)
        handlers.onHashtagTap("swift", URL(string: "https://example.com/tags/swift")!)
        handlers.onBoostUserTap()
        handlers.onReplyToUserTap(replyMention)

        #expect(capturedRoutes.count == 6)
        #expect(capturedRoutes[0] == .userProfile(status.account))
        #expect(capturedRoutes[1] == .userProfile(status.account))
        #expect(capturedRoutes[2] == .mediaPreview(url: mediaURL))
        #expect(capturedRoutes[3] == .hashtag("swift"))
        #expect(capturedRoutes[4] == .userProfile(status.account))
        #expect(capturedRoutes[5] == .mentionUser(replyMention))
    }

    @Test @MainActor func postNavigationRoutesImageTapToMediaGalleryWhenImageContextExists() async throws {
        var capturedRoutes: [Route] = []
        let firstImage = Status.Attachment(
            id: "img-1",
            type: "image",
            url: URL(string: "https://example.com/image-1.png")!,
            description: "first image alt"
        )
        let secondImage = Status.Attachment(
            id: "img-2",
            type: "image",
            url: URL(string: "https://example.com/image-2.png")!,
            description: "second image alt"
        )
        let video = Status.Attachment(
            id: "vid-1",
            type: "video",
            url: URL(string: "https://example.com/video-1.mp4")!
        )
        let status = makeStatus(
            id: "status-gallery",
            mediaAttachments: [firstImage, secondImage, video]
        )

        let handlers = PostNavigationActionCenter.handlers(
            for: status,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onImageTap(secondImage.url)

        #expect(capturedRoutes.count == 1)
        #expect(
            capturedRoutes[0] == .mediaGallery(
                items: [
                    RouteMediaGalleryItem(
                        id: firstImage.id,
                        url: firstImage.url,
                        altText: firstImage.description
                    ),
                    RouteMediaGalleryItem(
                        id: secondImage.id,
                        url: secondImage.url,
                        altText: secondImage.description
                    ),
                ],
                initialIndex: 1
            )
        )
    }

    @Test @MainActor func postNavigationRoutesVideoTapToMediaPreviewFallback() async throws {
        var capturedRoutes: [Route] = []
        let image = Status.Attachment(
            id: "img-1",
            type: "image",
            url: URL(string: "https://example.com/image-1.png")!
        )
        let video = Status.Attachment(
            id: "vid-1",
            type: "video",
            url: URL(string: "https://example.com/video-1.mp4")!
        )
        let status = makeStatus(
            id: "status-media-fallback",
            mediaAttachments: [image, video]
        )

        let handlers = PostNavigationActionCenter.handlers(
            for: status,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onImageTap(video.url)

        #expect(capturedRoutes.count == 1)
        #expect(capturedRoutes[0] == .mediaPreview(url: video.url))
    }

    @Test @MainActor func postNavigationRoutesQuotedStatusTapToQuotedDetail() async throws {
        var capturedRoutes: [Route] = []
        let wrapper = makeStatus(id: "wrapper")
        let quotedOriginal = makeStatus(id: "quoted-original")
        let quotedWrapper = makeStatus(id: "quoted-wrapper", reblog: Indirect(quotedOriginal))

        let handlers = PostNavigationActionCenter.handlers(
            for: wrapper,
            navigate: { capturedRoutes.append($0) }
        )

        handlers.onQuotedStatusTap(quotedWrapper)

        #expect(capturedRoutes.count == 1)
        #expect(capturedRoutes.first == .statusDetail(quotedOriginal))
    }

    @Test @MainActor func routeStaticContentCasesCompareEqual() async throws {
        #expect(Route.bookmarks == .bookmarks)
        #expect(Route.favourites == .favourites)
        #expect(Route.lists == .lists)
        #expect(Route.scheduledStatuses == .scheduledStatuses)
        #expect(Route.announcements == .announcements)
        #expect(Route.notificationSettings == .notificationSettings)
    }

    @Test @MainActor func routeStaticContentCasesRemainDistinctInSet() async throws {
        let routes: Set<Route> = [
            .bookmarks, .favourites, .lists, .scheduledStatuses, .announcements,
            .notificationSettings,
        ]
        #expect(routes.count == 6)
    }

    @Test @MainActor func urlHandlerParsesHashtagRoute() async throws {
        let url = URL(string: "https://mastodon.social/tags/swift")!
        #expect(URLHandler.shared.parseMastodonURL(url) == .hashtag("swift"))
    }

    @Test @MainActor func urlHandlerParsesStatusRouteFromWebStatusesPath() async throws {
        let url = URL(string: "https://mastodon.social/web/statuses/1234567890")!
        #expect(URLHandler.shared.parseMastodonURL(url) == .statusLink(url))
    }

    @Test @MainActor func urlHandlerParsesStatusRouteFromMentionPath() async throws {
        let url = URL(string: "https://mastodon.social/@alice/9988776655")!
        #expect(URLHandler.shared.parseMastodonURL(url) == .statusLink(url))
    }

    @Test @MainActor func statusLinksKeepTheOriginAndResolveToTheActiveServersID() async throws {
        let url = try #require(URL(string: "https://remote.example/@alice/100"))
        let api = MockMastodonAPI()
        let resolved = makeStatus(id: "200", content: "Resolved remote post")
        api.searchHandler = { query, type, resolve, limit, offset in
            #expect(query == url.absoluteString)
            #expect(type == .statuses && resolve && limit == 1 && offset == nil)
            return SearchResults(accounts: [], statuses: [resolved], hashtags: [])
        }

        let route = await URLHandler.shared.resolveStatusLink(url, apiClient: api)
        guard case .statusDetail(let status)? = route else {
            Issue.record("Expected the resolved status")
            return
        }
        #expect(status.id == "200")
        #expect(status.content == "Resolved remote post")
        #expect(api.fetchStatusDetailCallIDs.isEmpty)
        #expect(api.fetchStatusContextCallIDs.isEmpty)

        let otherURL = try #require(URL(string: "https://another.example/@alice/100"))
        #expect(Set<Route>([.statusLink(url), .statusLink(otherURL)]).count == 2)
    }

    @Test @MainActor func unresolvedStatusLinksOpenTheOriginalWebpage() async throws {
        let url = try #require(URL(string: "https://remote.example/@alice/100"))
        let api = MockMastodonAPI()
        api.searchHandler = { _, _, _, _, _ in
            SearchResults(accounts: [], statuses: [], hashtags: [])
        }
        #expect(await URLHandler.shared.resolveStatusLink(url, apiClient: api) == .webPreview(url))

        api.searchHandler = { _, _, _, _, _ in throw URLError(.notConnectedToInternet) }
        #expect(await URLHandler.shared.resolveStatusLink(url, apiClient: api) == .webPreview(url))
        #expect(api.fetchStatusDetailCallIDs.isEmpty && api.fetchStatusContextCallIDs.isEmpty)
    }

    @Test @MainActor func cancelledStatusResolutionDoesNotOpenAnotherDestination() async throws {
        let url = try #require(URL(string: "https://remote.example/@alice/100"))
        let api = MockMastodonAPI()
        api.searchHandler = { _, _, _, _, _ in throw CancellationError() }
        #expect(await URLHandler.shared.resolveStatusLink(url, apiClient: api) == nil)
        api.searchHandler = { _, _, _, _, _ in throw URLError(.cancelled) }
        #expect(await URLHandler.shared.resolveStatusLink(url, apiClient: api) == nil)
        let httpURL = try #require(URL(string: "http://remote.example/@alice/100"))
        #expect(await URLHandler.shared.resolveStatusLink(httpURL, apiClient: api) == .webPreview(httpURL))
        #expect(URLHandler.shared.parseMastodonURL(URL(string: "custom://remote.example/@alice/100")!) == nil)
    }

    @Test @MainActor func urlHandlerParsesMentionPathToAccountLookupRoute() async throws {
        let url = URL(string: "https://mastodon.social/@alice")!
        #expect(URLHandler.shared.parseMastodonURL(url) == .accountLookup("alice@mastodon.social"))
    }

    @Test @MainActor func urlHandlerParsesUsersPathToUserProfileRoute() async throws {
        let url = URL(string: "https://mastodon.social/users/4242")!
        let route = URLHandler.shared.parseMastodonURL(url)

        guard case .userProfile(let account)? = route else {
            #expect(Bool(false))
            return
        }
        #expect(account.id == "4242")
    }

    @Test @MainActor func hiddenAppearanceControlsUseStandardDefaults() async throws {
        #expect(AppSettings.defaultTypographyFontScale == .standard)
        #expect(AppSettings.defaultTimelineDensity == .comfortable)
        #expect(AppSettings.defaultNavigationAppearance == .standard)
        #expect(AppSettings.defaultNavigationAppearance.tabIconTheme == .standard)
        #expect(AppSettings.defaultNavigationAppearance.navigationStyle == .current)
    }

    @Test @MainActor func urlHandlerUsesInAppPreviewForExternalURLsWhenConfigured() async throws {
        let settings = AppSettings.shared
        let previous = settings.openLinksIn
        settings.openLinksIn = .moro
        defer { settings.openLinksIn = previous }

        let url = try #require(URL(string: "https://example.com/articles/hello"))
        #expect(URLHandler.shared.preferredInAppRoute(for: url) == .webPreview(url))
    }

    @Test @MainActor func urlHandlerLeavesExternalURLsToBrowserWhenConfigured() async throws {
        let settings = AppSettings.shared
        let previous = settings.openLinksIn
        settings.openLinksIn = .browser
        defer { settings.openLinksIn = previous }

        let url = try #require(URL(string: "https://example.com/articles/hello"))
        #expect(URLHandler.shared.preferredInAppRoute(for: url) == nil)
    }

    @Test @MainActor func urlHandlerLeavesMastodonURLsToBrowserWhenConfigured() async throws {
        let settings = AppSettings.shared
        let previous = settings.openLinksIn
        settings.openLinksIn = .browser
        defer { settings.openLinksIn = previous }

        let url = try #require(URL(string: "https://mastodon.social/@alice/123456"))
        #expect(URLHandler.shared.preferredInAppRoute(for: url) == nil)
    }

    @Test @MainActor func urlHandlerDoesNotForceMailtoIntoInAppPreview() async throws {
        let settings = AppSettings.shared
        let previous = settings.openLinksIn
        settings.openLinksIn = .moro
        defer { settings.openLinksIn = previous }

        let url = try #require(URL(string: "mailto:test@example.com"))
        #expect(URLHandler.shared.preferredInAppRoute(for: url) == nil)
    }

    @Test @MainActor func richTextEmojiLoaderDedupesRequestsWithinSingleLoad() async throws {
        let url = URL(string: "https://example.com/\(UUID().uuidString).png")!
        let counter = AsyncCounter()
        let fakeData = tinyPNGData()
        let coordinator = MixedTextEmojiView.Coordinator { _ in
            await counter.increment()
            return fakeData
        }

        let assets = await withCheckedContinuation { continuation in
            coordinator.loadEmojiAssets(
                elements: [
                    .emoji(shortcode: "a", url: url, staticURL: url),
                    .text(" "),
                    .emoji(shortcode: "b", url: url, staticURL: url)
                ],
                emojiSize: 18
            ) { resolved in
                continuation.resume(returning: resolved)
            }
        }

        #expect(await counter.value() == 1)
        #expect(assets.count == 1)
    }

    @Test @MainActor func richTextEmojiLoaderReusesSharedCacheAcrossCoordinatorInstances()
        async throws
    {
        let url = URL(string: "https://example.com/\(UUID().uuidString).png")!
        let counter = AsyncCounter()
        let fakeData = tinyPNGData()

        let firstCoordinator = MixedTextEmojiView.Coordinator { _ in
            await counter.increment()
            return fakeData
        }
        _ = await withCheckedContinuation { continuation in
            firstCoordinator.loadEmojiAssets(
                elements: [.emoji(shortcode: "a", url: url, staticURL: url)],
                emojiSize: 18
            ) { resolved in
                continuation.resume(returning: resolved)
            }
        }

        let secondCoordinator = MixedTextEmojiView.Coordinator { _ in
            await counter.increment()
            return fakeData
        }
        _ = await withCheckedContinuation { continuation in
            secondCoordinator.loadEmojiAssets(
                elements: [.emoji(shortcode: "a", url: url, staticURL: url)],
                emojiSize: 18
            ) { resolved in
                continuation.resume(returning: resolved)
            }
        }

        #expect(await counter.value() == 1)
    }

    @Test @MainActor func richTextEmojiLoaderAlwaysFetchesStaticImage()
        async throws
    {
        let url = URL(string: "https://example.com/\(UUID().uuidString).gif")!
        let staticURL = URL(string: "https://example.com/\(UUID().uuidString).png")!
        let counter = AsyncCounter()
        let requestedURLs = AsyncURLRecorder()
        let coordinator = MixedTextEmojiView.Coordinator { requestedURL in
            await counter.increment()
            await requestedURLs.append(requestedURL)
            return tinyPNGData()
        }

        let assets = await withCheckedContinuation { continuation in
            coordinator.loadEmojiAssets(
                elements: [.emoji(shortcode: "wave", url: url, staticURL: staticURL)],
                emojiSize: 18
            ) { resolved in
                continuation.resume(returning: resolved)
            }
        }

        // Post text always renders the server-provided static resource and never requests
        // the original APNG/GIF URL.
        #expect(await counter.value() == 1)
        #expect(await requestedURLs.values() == [staticURL])
        #expect(assets.count == 1)
        #expect(assets[staticURL] != nil)
    }

    @Test @MainActor func richTextEmojiRendererBuildsPlainStaticAttachment() throws {
        let image = try #require(UIImage(data: tinyPNGData()))
        let attachment = MixedTextEmojiView.makeStaticEmojiAttachment(
            image: image,
            emojiSize: 20
        )
        let attributedString = NSAttributedString(attachment: attachment)
        let storedAttachment = try #require(
            attributedString.attribute(.attachment, at: 0, effectiveRange: nil)
                as? NSTextAttachment
        )

        #expect(storedAttachment === attachment)
        #expect(attachment.image != nil)
        #expect(attachment.bounds.size == CGSize(width: 20, height: 20))
        #expect(abs(attachment.bounds.minY + 1.6) < 0.001)
    }

    @Test @MainActor func richTextEmojiRendererKeepsReadableShortcodeWhenStaticAssetFails() {
        let animatedURL = URL(string: "https://example.test/original/wave.apng")!
        let staticURL = URL(string: "https://example.test/static/wave.png")!
        let elements: [ContentElement] = [
            .emoji(shortcode: "wave", url: animatedURL, staticURL: staticURL)
        ]

        let rendered = MixedTextEmojiView(
            elements: elements,
            emojiSize: 20,
            textColor: .label,
            linkColor: .systemBlue,
            codeBackgroundColor: .secondarySystemBackground
        ).buildAttributedString(
            emojiAssets: [:],
            textColor: .label,
            linkColor: .systemBlue,
            codeBackgroundColor: .secondarySystemBackground,
            underlinesLinks: false
        )
        var attachmentCount = 0
        rendered.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: rendered.length)
        ) { value, _, _ in
            if value is NSTextAttachment {
                attachmentCount += 1
            }
        }

        #expect(rendered.string == ":wave:")
        #expect(attachmentCount == 0)
    }

    @Test @MainActor func statusEmojiPipelineParsesStaticURLsAndBuildsEveryAttachment()
        async throws
    {
        let originalWaveURL = try #require(
            URL(string: "https://example.com/\(UUID().uuidString)/original/wave.apng")
        )
        let staticWaveURL = try #require(
            URL(string: "https://example.com/\(UUID().uuidString)/static/wave.png")
        )
        let originalCatURL = try #require(
            URL(string: "https://example.com/\(UUID().uuidString)/original/cat.gif")
        )
        let staticCatURL = try #require(
            URL(string: "https://example.com/\(UUID().uuidString)/static/cat.png")
        )
        let emojis = [
            Status.Emoji(shortcode: "wave", url: originalWaveURL, staticURL: staticWaveURL),
            Status.Emoji(shortcode: "cat", url: originalCatURL, staticURL: staticCatURL),
        ]
        let elements = ContentParser.parseToElements(
            html: "<p>:wave: :cat: :wave:</p><p>测试表情</p>",
            emojis: emojis,
            options: .statusBody
        )
        let requestedURLs = AsyncURLRecorder()
        let coordinator = MixedTextEmojiView.Coordinator { requestedURL in
            await requestedURLs.append(requestedURL)
            return tinyPNGData()
        }
        let assets = await withCheckedContinuation { continuation in
            coordinator.loadEmojiAssets(elements: elements, emojiSize: 20) { resolved in
                continuation.resume(returning: resolved)
            }
        }

        let rendered = MixedTextEmojiView(
            elements: elements,
            emojiSize: 20,
            textColor: .label,
            linkColor: .systemBlue,
            codeBackgroundColor: .secondarySystemBackground
        ).buildAttributedString(
            emojiAssets: assets,
            textColor: .label,
            linkColor: .systemBlue,
            codeBackgroundColor: .secondarySystemBackground,
            underlinesLinks: false
        )
        var attachments: [NSTextAttachment] = []
        rendered.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: rendered.length)
        ) { value, _, _ in
            if let attachment = value as? NSTextAttachment {
                attachments.append(attachment)
            }
        }
        let loadedURLs = await requestedURLs.values()

        #expect(Set(loadedURLs) == Set([staticWaveURL, staticCatURL]))
        #expect(assets.count == 2)
        #expect(assets[originalWaveURL] == nil)
        #expect(assets[originalCatURL] == nil)
        #expect(attachments.count == 3)
        #expect(attachments.allSatisfy { type(of: $0) == NSTextAttachment.self })
        #expect(rendered.string.contains(":wave:") == false)
        #expect(rendered.string.contains(":cat:") == false)
        #expect(rendered.string.contains("测试表情"))
    }

    @Test @MainActor func profilePinnedInsertIgnoresOtherAccountsPinnedPost() async throws {
        // Counterexample to the earlier "every .post write is already holding-guarded" claim:
        // the feed coordinator is global, so a freshly-pinned post from ANY account must not
        // leak into a *different* profile's pinned carousel (and especially not a hidden one).
        let api = MockMastodonAPI()
        let vmA = ProfileViewModel(apiClient: api, accountID: "account-A")
        let vmB = ProfileViewModel(apiClient: api, accountID: "account-B")

        let pinnedByB = makeStatus(
            id: "pinned-by-B",
            account: makeAccount(id: "account-B"),
            pinned: true
        )

        // @Published delivers synchronously on the main actor, so both view models have
        // processed the event by the time publishUpdate returns.
        FeedCoordinator.shared.publishUpdate(.post(pinnedByB))

        #expect(vmA.pinnedStatuses.isEmpty)
        #expect(vmB.pinnedStatuses.contains { $0.id == "pinned-by-B" })

        withExtendedLifetime((vmA, vmB)) {}
    }

    @Test @MainActor func profilePinnedPostSurvivesInteractionResponseWithoutPinnedField() async {
        let api = MockMastodonAPI()
        let coordinator = FeedCoordinator()
        let account = makeAccount(id: "profile-owner")
        let viewModel = ProfileViewModel(
            apiClient: api,
            accountID: account.id,
            feedCoordinator: coordinator
        )
        viewModel.pinnedStatuses = [
            makeStatus(id: "pinned-status", account: account, pinned: true)
        ]

        coordinator.publishUpdate(
            .post(
                makeStatus(
                    id: "pinned-status",
                    account: account,
                    favouritesCount: 1,
                    favourited: true,
                    pinned: nil
                )
            )
        )

        #expect(viewModel.pinnedStatuses.count == 1)
        #expect(viewModel.pinnedStatuses.first?.favourited == true)
        #expect(viewModel.pinnedStatuses.first?.pinned == true)

        coordinator.publishUpdate(
            .post(makeStatus(id: "pinned-status", account: account, pinned: false))
        )
        #expect(viewModel.pinnedStatuses.isEmpty)
    }

    @Test @MainActor func accountDisplayNameParserKeepsPlainTextVisibleWhileResolvingEmoji()
        async throws
    {
        let animatedURL = URL(string: "https://example.com/wave.gif")!
        let staticURL = URL(string: "https://example.com/wave.png")!
        let emoji = Account.Emoji(shortcode: "wave", url: animatedURL, staticURL: staticURL)

        let content = AccountDisplayNameParser.parse(
            displayName: "<span>Hi</span> :wave: &amp; :missing:",
            fallbackUsername: "alice",
            emojis: [emoji]
        )

        #expect(content.plainText == "Hi :wave: & :missing:")
        #expect(content.containsCustomEmoji)
        #expect(content.emojiURLs == [staticURL])

        guard content.segments.count >= 3 else {
            #expect(Bool(false))
            return
        }

        #expect(content.segments[0] == .text("Hi "))
        if case .emoji(let resolvedEmoji) = content.segments[1] {
            #expect(resolvedEmoji.shortcode == "wave")
            #expect(resolvedEmoji.staticURL == staticURL)
            #expect(resolvedEmoji.url == animatedURL)
        } else {
            #expect(Bool(false))
        }
    }

    @Test @MainActor func accountDisplayNameParserKeepsFirstDuplicateEmojiShortcode()
        async throws
    {
        let firstAnimatedURL = URL(string: "https://example.com/duplicate-first.gif")!
        let firstStaticURL = URL(string: "https://example.com/duplicate-first.png")!
        let secondAnimatedURL = URL(string: "https://example.com/duplicate-second.gif")!
        let secondStaticURL = URL(string: "https://example.com/duplicate-second.png")!
        let firstEmoji = Account.Emoji(
            shortcode: "duplicate_wave",
            url: firstAnimatedURL,
            staticURL: firstStaticURL
        )
        let secondEmoji = Account.Emoji(
            shortcode: "duplicate_wave",
            url: secondAnimatedURL,
            staticURL: secondStaticURL
        )

        let content = AccountDisplayNameParser.parse(
            displayName: "Duplicate :duplicate_wave: account",
            fallbackUsername: "duplicate-emoji-user",
            emojis: [firstEmoji, secondEmoji]
        )

        #expect(content.plainText == "Duplicate :duplicate_wave: account")
        #expect(content.containsCustomEmoji)
        #expect(content.emojiURLs == [firstStaticURL])

        guard content.segments.count == 3 else {
            #expect(Bool(false))
            return
        }

        if case .emoji(let resolvedEmoji) = content.segments[1] {
            #expect(resolvedEmoji.url == firstAnimatedURL)
            #expect(resolvedEmoji.staticURL == firstStaticURL)
        } else {
            #expect(Bool(false))
        }
    }

    @Test @MainActor func accountDisplayNameFallsBackToUsernameWhenNameIsEffectivelyEmpty()
        async throws
    {
        let account = makeAccount(
            username: "alice",
            displayName: "<span> </span>"
        )

        #expect(account.displayNameFormatted == "alice")
        #expect(account.displayNameInitials == "AL")
    }

    @Test @MainActor func accountDisplayNameInitialsIgnoreLeadingCustomEmoji() async throws {
        let account = makeAccount(
            username: "fallback",
            displayName: ":wave: Alice Bob",
            emojis: [
                Account.Emoji(
                    shortcode: "wave",
                    url: URL(string: "https://example.com/wave.gif")!,
                    staticURL: URL(string: "https://example.com/wave.png")!
                )
            ]
        )

        #expect(account.displayNameFormatted == ":wave: Alice Bob")
        #expect(account.displayNameInitials == "AB")
    }

    @Test @MainActor func accountNoteContentElementsPreserveEmojiAndLinkText() async throws {
        let account = makeAccount(
            note: """
                <p>Hello :wave: <a href="https://example.com">example</a></p><p>Next line</p>
                """,
            emojis: [
                Account.Emoji(
                    shortcode: "wave",
                    url: URL(string: "https://example.com/wave.gif")!,
                    staticURL: URL(string: "https://example.com/wave.png")!
                )
            ]
        )

        let elements = account.noteContentElements

        #expect(elements.containsCustomEmoji)
        #expect(elements.plainTextValue.contains("Hello"))
        #expect(elements.plainTextValue.contains(":wave:"))
        #expect(elements.plainTextValue.contains("example"))
        #expect(elements.plainTextValue.contains("Next line"))
    }

    @Test @MainActor func accountNoteContentElementsPreserveEmojiImageAltText() async throws {
        let account = makeAccount(
            note: """
                <p>Hello <img class="emojione" alt=":wave:" src="https://example.com/wave.png"> world</p>
                """,
            emojis: [
                Account.Emoji(
                    shortcode: "wave",
                    url: URL(string: "https://example.com/wave.gif")!,
                    staticURL: URL(string: "https://example.com/wave.png")!
                )
            ]
        )

        let elements = account.noteContentElements

        #expect(elements.containsCustomEmoji)
        #expect(elements.plainTextValue == "Hello :wave: world")
    }

    @Test @MainActor func accountNoteContentElementsSeparateAdjacentHashtagLinks() async throws {
        let account = makeAccount(
            note: """
                <p><a href="https://ihan.outo.la/tags/music" class="mention hashtag">#<span>music</span></a> <a href="https://ihan.outo.la/tags/afrobeat" class="mention hashtag">#<span>afrobeat</span></a> <a href="https://ihan.outo.la/tags/afrofunk" class="mention hashtag">#<span>afrofunk</span></a></p>
                """,
            url: "https://ihan.outo.la/@jabsonik"
        )

        #expect(account.noteContentElements.plainTextValue == "#music #afrobeat #afrofunk")
    }

    @Test @MainActor func accountFieldContentElementsSupportEmojiMentionsURLsAndHashtags() async throws {
        let account = makeAccount(
            note: "",
            fields: [
                AccountField(
                    name: ":verified: 爱买游戏",
                    value: """
                        Visit https://example.com and ping @alice@example.com about #SwiftUI <img alt=":verified:" src="https://example.com/verified.png">
                        """
                )
            ],
            emojis: [
                Account.Emoji(
                    shortcode: "verified",
                    url: URL(string: "https://example.com/verified.gif")!,
                    staticURL: URL(string: "https://example.com/verified.png")!
                )
            ]
        )

        let field = try #require(account.fields.first)
        let nameElements = field.nameContentElements(
            emojis: account.contentEmojis,
            contentBaseURL: account.contentBaseURL
        )
        let valueElements = field.valueContentElements(
            emojis: account.contentEmojis,
            contentBaseURL: account.contentBaseURL
        )

        #expect(nameElements.containsCustomEmoji)
        #expect(nameElements.plainTextValue.contains(":verified:"))
        #expect(valueElements.containsCustomEmoji)
        #expect(valueElements.contains {
            if case .link(let text, let url) = $0 {
                return text == "https://example.com" && url.absoluteString == "https://example.com"
            }
            return false
        })
        #expect(valueElements.contains {
            if case .mention(let username, let url) = $0 {
                return username == "@alice@example.com"
                    && url.absoluteString == "https://example.com/@alice"
            }
            return false
        })
        #expect(valueElements.contains {
            if case .hashtag(let tag, let url) = $0 {
                return tag == "#SwiftUI"
                    && url.absoluteString == "https://example.com/tags/SwiftUI"
            }
            return false
        })
    }

    @Test @MainActor func accountNoteContentElementsAutoDetectPlainHashtagsWithAccountHost()
        async throws
    {
        let account = makeAccount(
            username: "tester",
            note: "<p>Discussing #女同 and #SwiftUI today</p>",
            url: "https://social.example/@tester"
        )

        let elements = account.noteContentElements

        #expect(elements.contains {
            if case .hashtag(let tag, let url) = $0 {
                return tag == "#女同" && url.absoluteString == "https://social.example/tags/%E5%A5%B3%E5%90%8C"
            }
            return false
        })
        #expect(elements.contains {
            if case .hashtag(let tag, let url) = $0 {
                return tag == "#SwiftUI" && url.absoluteString == "https://social.example/tags/SwiftUI"
            }
            return false
        })
    }

    @Test @MainActor func accountNotePreviewTextCollapsesWhitespaceForCompactSurfaces() async throws {
        let account = makeAccount(
            note: """
                <p>First line</p>
                <p>Second&nbsp;line :wave:</p>
                """,
            emojis: [
                Account.Emoji(
                    shortcode: "wave",
                    url: URL(string: "https://example.com/wave.gif")!,
                    staticURL: URL(string: "https://example.com/wave.png")!
                )
            ]
        )

        #expect(account.notePreviewText == "First line Second line :wave:")
    }

    @Test @MainActor func appSettingsEmojiGroupOrderStoresPerDomain() async throws {
        let settings = AppSettings.shared
        let domainA = "a.example"
        let domainB = "b.example"
        let orderA = ["动物", "食物"]
        let orderB = ["默认", "活动"]

        settings.resetEmojiGroupOrder(for: domainA)
        settings.resetEmojiGroupOrder(for: domainB)
        defer {
            settings.resetEmojiGroupOrder(for: domainA)
            settings.resetEmojiGroupOrder(for: domainB)
        }

        settings.setEmojiGroupOrder(orderA, for: domainA)
        settings.setEmojiGroupOrder(orderB, for: domainB)

        #expect(settings.emojiGroupOrder(for: domainA) == orderA)
        #expect(settings.emojiGroupOrder(for: domainB) == orderB)
    }

    @Test @MainActor func appSettingsEmojiGroupOrderResetClearsDomainOnly() async throws {
        let settings = AppSettings.shared
        let domainA = "reset-a.example"
        let domainB = "reset-b.example"
        let orderA = ["测试组A"]
        let orderB = ["测试组B"]

        settings.setEmojiGroupOrder(orderA, for: domainA)
        settings.setEmojiGroupOrder(orderB, for: domainB)
        defer {
            settings.resetEmojiGroupOrder(for: domainA)
            settings.resetEmojiGroupOrder(for: domainB)
        }

        settings.resetEmojiGroupOrder(for: domainA)

        #expect(settings.emojiGroupOrder(for: domainA).isEmpty)
        #expect(settings.emojiGroupOrder(for: domainB) == orderB)
    }

    @Test @MainActor func postMoreMenuPolicyOwnPostHidesOtherUserActions() async throws {
        let visibility = PostMoreMenuPolicy.visibility(
            isOwnPost: true,
            isBlockingUser: false,
            hasShare: true,
            hasCopyLink: true,
            hasCopyText: true,
            hasOpenInBrowser: true,
            hasEdit: true,
            hasMuteUser: true,
            hasBlockUser: true,
            hasBlockAndReport: true,
            hasReport: true,
            hasPin: true,
            hasDeleteAndRedraft: true,
            hasDelete: true
        )

        #expect(visibility.showShare)
        #expect(visibility.showCopyLink)
        #expect(visibility.showCopyText)
        #expect(visibility.showOpenInBrowser)
        #expect(visibility.showEdit)
        #expect(visibility.showPin)
        #expect(visibility.showDeleteAndRedraft)
        #expect(visibility.showDelete)
        #expect(visibility.showMuteUser == false)
        #expect(visibility.showBlockUser == false)
        #expect(visibility.showBlockAndReport == false)
        #expect(visibility.showReport == false)
    }

    @Test @MainActor func postMoreMenuPolicyOtherPostShowsRelationshipActions() async throws {
        let visibility = PostMoreMenuPolicy.visibility(
            isOwnPost: false,
            isBlockingUser: false,
            hasShare: true,
            hasCopyLink: true,
            hasCopyText: true,
            hasOpenInBrowser: true,
            hasEdit: true,
            hasMuteUser: true,
            hasBlockUser: true,
            hasBlockAndReport: true,
            hasReport: true,
            hasPin: true,
            hasDeleteAndRedraft: true,
            hasDelete: true
        )

        #expect(visibility.showShare)
        #expect(visibility.showCopyLink)
        #expect(visibility.showCopyText)
        #expect(visibility.showOpenInBrowser)
        #expect(visibility.showMuteUser)
        #expect(visibility.showBlockUser)
        #expect(visibility.showBlockAndReport)
        #expect(visibility.showReport)
        #expect(visibility.showEdit == false)
        #expect(visibility.showPin == false)
        #expect(visibility.showDeleteAndRedraft == false)
        #expect(visibility.showDelete == false)
    }

    @Test @MainActor func postMoreMenuPolicyBlockedUserHidesBlockAndReport() async throws {
        let visibility = PostMoreMenuPolicy.visibility(
            isOwnPost: false,
            isBlockingUser: true,
            hasShare: true,
            hasCopyLink: true,
            hasCopyText: true,
            hasOpenInBrowser: true,
            hasEdit: false,
            hasMuteUser: true,
            hasBlockUser: true,
            hasBlockAndReport: true,
            hasReport: true,
            hasPin: false,
            hasDeleteAndRedraft: false,
            hasDelete: false
        )

        #expect(visibility.showBlockUser)
        #expect(visibility.showBlockAndReport == false)
        #expect(visibility.showReport)
    }

    @Test @MainActor func postMoreMenuPolicyRespectsMissingHandlers() async throws {
        let visibility = PostMoreMenuPolicy.visibility(
            isOwnPost: false,
            isBlockingUser: false,
            hasShare: false,
            hasCopyLink: true,
            hasCopyText: false,
            hasOpenInBrowser: false,
            hasEdit: true,
            hasMuteUser: false,
            hasBlockUser: true,
            hasBlockAndReport: false,
            hasReport: false,
            hasPin: true,
            hasDeleteAndRedraft: true,
            hasDelete: true
        )

        #expect(visibility.showShare == false)
        #expect(visibility.showCopyLink)
        #expect(visibility.showCopyText == false)
        #expect(visibility.showOpenInBrowser == false)
        #expect(visibility.showMuteUser == false)
        #expect(visibility.showBlockUser)
        #expect(visibility.showBlockAndReport == false)
        #expect(visibility.showReport == false)
        #expect(visibility.showEdit == false)
        #expect(visibility.showPin == false)
        #expect(visibility.showDeleteAndRedraft == false)
        #expect(visibility.showDelete == false)
    }

    @Test @MainActor func postMoreMenuPolicyIsOwnPostUsesDisplayStatusAuthor() async throws {
        let me = makeAccount(id: "me")
        let other = makeAccount(id: "other")
        let original = makeStatus(id: "original", account: other)
        let reblogWrapper = makeStatus(id: "wrapper", account: me, reblog: Indirect(original))

        #expect(PostMoreMenuPolicy.isOwnPost(original, currentUserID: me.id) == false)
        #expect(PostMoreMenuPolicy.isOwnPost(reblogWrapper, currentUserID: me.id) == false)
        #expect(PostMoreMenuPolicy.isOwnPost(makeStatus(id: "mine", account: me), currentUserID: me.id))
        #expect(PostMoreMenuPolicy.isOwnPost(makeStatus(id: "mine", account: me), currentUserID: nil) == false)
    }

    @Test @MainActor func postMoreMenuPolicyCanEditOwnPostUnlessItHasPoll() async throws {
        let me = makeAccount(id: "me")
        let poll = Status.Poll(
            id: "poll-1",
            expiresAt: nil,
            expired: false,
            multiple: false,
            votesCount: 0,
            votersCount: nil,
            options: [.init(title: "One", votesCount: nil)],
            voted: nil,
            ownVotes: nil
        )

        #expect(
            PostMoreMenuPolicy.canEditPost(
                makeStatus(id: "editable", account: me),
                currentUserID: me.id
            )
        )
        #expect(
            PostMoreMenuPolicy.canEditPost(
                makeStatus(id: "poll-post", account: me, poll: poll),
                currentUserID: me.id
            ) == false
        )
    }

    @Test @MainActor func deleteAndRedraftMenuActionRequestsConfirmationBeforeDeleting() throws {
        let api = MockMastodonAPI()
        let actionSurface = PostActionSurfaceCenter()
        let status = makeStatus(id: "delete-and-redraft", account: makeAccount(id: "me"))
        let handlers = PostInteractionHandlers(
            interactionService: PostInteractionService(apiClient: api),
            actionSurface: actionSurface,
            postMenuActionCenter: PostMenuActionCenter(apiClient: api),
            apiClient: api,
            currentUserID: "me",
            router: AppRouter(),
            onRemoveStatus: nil
        )

        let action = try #require(handlers.buildPostActions(for: status).onDeleteAndRedraft)
        action()

        let request = try #require(actionSurface.deleteRequest)
        #expect(request.status.id == status.id)
        #expect(request.mode == .redraft)
        #expect(request.shouldRedraft)

        actionSurface.clearDeleteRequest()
        #expect(actionSurface.deleteRequest == nil)
    }

    @Test @MainActor func statusFilterWarningUsesFilteredResults() async throws {
        let filtered = [
            Status.FilterResult(
                filter: .init(title: "Sensitive phrase")
            )
        ]
        let status = makeStatus(id: "filtered", filtered: filtered)

        #expect(status.hasFilterWarning)
        #expect(status.primaryFilterWarningTitle == "Sensitive phrase")
    }

    @Test @MainActor func statusFilterWarningUsesDisplayStatusForReblogWrapper() async throws {
        let filtered = [
            Status.FilterResult(
                filter: .init(title: "Blocked topic")
            )
        ]
        let original = makeStatus(id: "original-filtered", filtered: filtered)
        let wrapper = makeStatus(id: "wrapper-filtered", reblog: Indirect(original))

        #expect(wrapper.hasFilterWarning)
        #expect(wrapper.primaryFilterWarningTitle == "Blocked topic")
    }

    @Test @MainActor func statusFilterWarningBannerTextAggregatesMultipleRules() async throws {
        let filtered = [
            Status.FilterResult(filter: .init(title: "Politics")),
            Status.FilterResult(filter: .init(title: "Politics")),
            Status.FilterResult(filter: .init(title: "Spoilers"))
        ]
        let status = makeStatus(id: "multi-filter", filtered: filtered)

        #expect(status.hasFilterWarning)
        #expect(status.primaryFilterWarningTitle == "Politics")
        #expect(status.filterWarningBannerText == "Filtered by 2 rules")
    }

    @Test @MainActor func timelineLoadInitialMergesNetworkWithCachedStatuses() async throws {
        let api = MockMastodonAPI()
        let timelineCache = TimelineCache(maxCachedStatuses: 800)
        let clientID = "timeline-merge-\(UUID().uuidString)"
        let cached = [
            makeStatus(id: "c3"),
            makeStatus(id: "c2"),
            makeStatus(id: "c1"),
        ]

        await timelineCache.set(statuses: cached, for: clientID, filter: .home)

        api.fetchHomeTimelineHandler = { _, _, _ in
            [
                self.makeStatus(id: "n1"),
                self.makeStatus(id: "c3"),
                self.makeStatus(id: "c2"),
            ]
        }

        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: timelineCache,
            cacheClientID: clientID
        )

        await viewModel.loadInitial()

        #expect(viewModel.statuses.map(\.id) == ["n1", "c3", "c2", "c1"])
    }

    @Test @MainActor func timelineLoadInitialKeepsCachedStatusesWhenNetworkFails() async throws {
        let api = MockMastodonAPI()
        let timelineCache = TimelineCache(maxCachedStatuses: 800)
        let clientID = "timeline-fallback-\(UUID().uuidString)"
        let cached = [
            makeStatus(id: "c2"),
            makeStatus(id: "c1"),
        ]

        await timelineCache.set(statuses: cached, for: clientID, filter: .home)

        api.fetchHomeTimelineHandler = { _, _, _ in
            throw MockMastodonAPI.MockError.forcedFailure
        }

        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: timelineCache,
            cacheClientID: clientID
        )

        await viewModel.loadInitial()

        #expect(viewModel.statuses.map(\.id) == ["c2", "c1"])
        let isErrorState: Bool
        if case .error = viewModel.loadingState {
            isErrorState = true
        } else {
            isErrorState = false
        }
        #expect(isErrorState == false)
    }

    @Test @MainActor func refreshOnEmptyTimelineRecoversAndDoesNotStick() async throws {
        // Regression: a refresh whose API returns nothing, on an already-empty timeline,
        // used to call loadInitial() while loadingState == .refreshing. loadInitial() bails
        // on any non-idle state, so loadingState stayed .refreshing forever and every later
        // load was gated off — the frozen timeline reported on local↔federated switches.
        let api = MockMastodonAPI()
        api.fetchHomeTimelineHandler = { _, _, _ in [] }

        let viewModel = TimelineViewModel(apiClient: api, timelineType: .home,
            timelineCache: TimelineCache(), cacheClientID: "empty-refresh-\(UUID().uuidString)")
        await viewModel.loadInitial()   // loads empty → .idle, statuses == []
        await viewModel.refresh()       // empty refresh on an empty list

        // Must have recovered to a non-.refreshing state, not be stuck.
        let stuck: Bool
        if case .refreshing = viewModel.loadingState { stuck = true } else { stuck = false }
        #expect(stuck == false)

        // And it must still accept loads — a stuck VM rejects refresh()/loadMore()/loadInitial().
        api.fetchHomeTimelineHandler = { _, _, _ in [self.makeStatus(id: "n1")] }
        await viewModel.refresh()
        #expect(viewModel.statuses.map(\.id) == ["n1"])
    }

    @Test @MainActor func notificationConsolidationGroupsFavouritesByStatus() async throws {
        let status = makeStatus(id: "s1")
        let first = makeNotification(
            id: "n1",
            type: "favourite",
            createdAt: Date(timeIntervalSince1970: 200),
            account: makeAccount(id: "u1"),
            status: status
        )
        let second = makeNotification(
            id: "n2",
            type: "favourite",
            createdAt: Date(timeIntervalSince1970: 100),
            account: makeAccount(id: "u2"),
            status: status
        )

        let consolidated = NotificationDisplayItem.consolidate([first, second])

        #expect(consolidated.count == 1)
        #expect(consolidated.first?.id.hasPrefix("favourite-s1-") == true)
        #expect(consolidated.first?.actorCount == 2)
        #expect(consolidated.first?.sourceNotificationIDs.count == 2)
        #expect(consolidated.first?.primaryAccount?.id == "u1")
    }

    @Test @MainActor func notificationConsolidationDoesNotGroupDifferentStatuses() async throws {
        let first = makeNotification(
            id: "n1",
            type: "reblog",
            createdAt: Date(timeIntervalSince1970: 200),
            account: makeAccount(id: "u1"),
            status: makeStatus(id: "s1")
        )
        let second = makeNotification(
            id: "n2",
            type: "reblog",
            createdAt: Date(timeIntervalSince1970: 100),
            account: makeAccount(id: "u2"),
            status: makeStatus(id: "s2")
        )

        let consolidated = NotificationDisplayItem.consolidate([first, second])

        #expect(consolidated.count == 2)
    }

    @Test @MainActor func notificationConsolidationKeepsNewestActorAsPrimary() async throws {
        let status = makeStatus(id: "s1")
        let older = makeNotification(
            id: "n-old",
            type: "favourite",
            createdAt: Date(timeIntervalSince1970: 100),
            account: makeAccount(id: "u1"),
            status: status
        )
        let newer = makeNotification(
            id: "n-new",
            type: "favourite",
            createdAt: Date(timeIntervalSince1970: 200),
            account: makeAccount(id: "u2"),
            status: status
        )

        // Intentionally pass unsorted notifications to ensure merge keeps newest actor first.
        let consolidated = NotificationDisplayItem.consolidate([older, newer])

        #expect(consolidated.count == 1)
        #expect(consolidated.first?.primaryAccount?.id == "u2")
        #expect(consolidated.first?.actorCount == 2)
        #expect(consolidated.first?.createdAt == Date(timeIntervalSince1970: 200))
    }

    @Test @MainActor func notificationConsolidationGroupsReblogsByStatus() async throws {
        let status = makeStatus(id: "shared-reblog")
        let first = makeNotification(
            id: "n1",
            type: "reblog",
            createdAt: Date(timeIntervalSince1970: 220),
            account: makeAccount(id: "u1"),
            status: status
        )
        let second = makeNotification(
            id: "n2",
            type: "reblog",
            createdAt: Date(timeIntervalSince1970: 210),
            account: makeAccount(id: "u2"),
            status: status
        )

        let consolidated = NotificationDisplayItem.consolidate([first, second])

        #expect(consolidated.count == 1)
        #expect(consolidated.first?.id.hasPrefix("reblog-shared-reblog-") == true)
        #expect(consolidated.first?.actorCount == 2)
    }

    @Test @MainActor func notificationConsolidationDoesNotGroupUpdateTypes() async throws {
        let status = makeStatus(id: "s-update")
        let update = makeNotification(
            id: "n-update",
            type: "update",
            createdAt: Date(timeIntervalSince1970: 200),
            account: makeAccount(id: "u1"),
            status: status
        )
        let quotedUpdate = makeNotification(
            id: "n-quoted-update",
            type: "quoted_update",
            createdAt: Date(timeIntervalSince1970: 190),
            account: makeAccount(id: "u2"),
            status: status
        )

        let consolidated = NotificationDisplayItem.consolidate([update, quotedUpdate])

        #expect(consolidated.count == 2)
    }

    @Test @MainActor func notificationConsolidationKeepsFollowsSeparate() async throws {
        let first = makeNotification(
            id: "n1",
            type: "follow",
            createdAt: Date(timeIntervalSince1970: 200),
            account: makeAccount(id: "u1"),
            status: nil
        )
        let second = makeNotification(
            id: "n2",
            type: "follow",
            createdAt: Date(timeIntervalSince1970: 100),
            account: makeAccount(id: "u2"),
            status: nil
        )

        let consolidated = NotificationDisplayItem.consolidate([first, second])

        #expect(consolidated.count == 2)
        #expect(consolidated.allSatisfy { $0.actorCount == 1 })
    }

    @Test @MainActor func notificationConsolidationDoesNotCrossCalendarDays() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let firstDate = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 2, hour: 23, minute: 55
        )))
        let secondDate = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 3, hour: 0, minute: 5
        )))
        let status = makeStatus(id: "same-status-across-days")
        let first = makeNotification(
            id: "n-day-one",
            type: "favourite",
            createdAt: firstDate,
            account: makeAccount(id: "u1"),
            status: status
        )
        let second = makeNotification(
            id: "n-day-two",
            type: "favourite",
            createdAt: secondDate,
            account: makeAccount(id: "u2"),
            status: status
        )

        let consolidated = NotificationDisplayItem.consolidate([first, second])

        #expect(consolidated.count == 2)
    }

    @Test @MainActor func notificationConsolidationUsesServerGroupKey() async throws {
        let status = makeStatus(id: "server-group-status")
        let first = makeNotification(
            id: "server-group-1",
            type: "reblog",
            groupKey: "reblog:server-group-status",
            createdAt: Date(timeIntervalSince1970: 200),
            account: makeAccount(id: "u1"),
            status: status
        )
        let second = makeNotification(
            id: "server-group-2",
            type: "reblog",
            groupKey: "reblog:server-group-status",
            createdAt: Date(timeIntervalSince1970: 100),
            account: makeAccount(id: "u2"),
            status: status
        )

        let consolidated = NotificationDisplayItem.consolidate([first, second])

        #expect(consolidated.count == 1)
        #expect(consolidated.first?.id.contains("reblog:server-group-status") == true)
    }

    @Test func notificationKindsCoverSupportedServerTypesAndValidIcons() {
        #expect(NotificationKind.supportedRawValues.count == 16)
        #expect(Set(NotificationKind.supportedRawValues).count == 16)

        for rawValue in NotificationKind.supportedRawValues {
            let kind = NotificationKind(rawValue: rawValue)
            #expect(kind.rawValue == rawValue)
            #expect(!kind.actionText().isEmpty)
            #expect(UIImage(systemName: kind.descriptor.iconName) != nil)
        }
    }

    @Test func notificationKindPreservesUnknownRawValue() {
        let kind = NotificationKind(rawValue: "future.event")

        #expect(kind == .unknown("future.event"))
        #expect(kind.rawValue == "future.event")
        #expect(kind.descriptor.layoutFamily == .systemEvent)
        #expect(UIImage(systemName: kind.descriptor.iconName) != nil)
    }

    @Test @MainActor func notificationEffectiveStatusTargetsRespectEditSemantics() async throws {
        let quotedTarget = makeStatus(id: "quoted-target")
        let quoteWrapper = makeStatus(
            id: "my-quote",
            quote: Status.Quote(state: .accepted, quotedStatus: quotedTarget)
        )
        let update = NotificationDisplayItem(from: makeNotification(
            id: "update-notification",
            type: "update",
            status: makeStatus(id: "boosted-target")
        ))
        let quotedUpdate = NotificationDisplayItem(from: makeNotification(
            id: "quoted-update-notification",
            type: "quoted_update",
            status: quoteWrapper
        ))
        let unavailableQuotedUpdate = NotificationDisplayItem(from: makeNotification(
            id: "unavailable-quoted-update",
            type: "quoted_update",
            status: makeStatus(id: "quote-without-target")
        ))

        #expect(update.effectiveStatusTarget?.id == "boosted-target")
        #expect(quotedUpdate.effectiveStatusTarget?.id == "quoted-target")
        #expect(unavailableQuotedUpdate.effectiveStatusTarget == nil)
    }

    @Test @MainActor func notificationConsolidationDoesNotDuplicateSameActor() async throws {
        let status = makeStatus(id: "same-status")
        let account = makeAccount(id: "same-actor")
        let first = makeNotification(
            id: "n1",
            type: "favourite",
            createdAt: Date(timeIntervalSince1970: 300),
            account: account,
            status: status
        )
        let second = makeNotification(
            id: "n2",
            type: "favourite",
            createdAt: Date(timeIntervalSince1970: 100),
            account: account,
            status: status
        )

        let consolidated = NotificationDisplayItem.consolidate([first, second])

        #expect(consolidated.count == 1)
        #expect(consolidated.first?.actorCount == 1)
        #expect(consolidated.first?.sourceNotificationIDs.count == 2)
    }

    @Test @MainActor func rootTabCoordinatorHomeRetapKeepsSubTimelineAndScrollsToTop() async throws {
        let state = RootTabCoordinator(selectedTab: .home)
        state.timelineSelection = .federated

        // triggerScrollToTopEvent sets selectedTabScrollToTop to the tab's
        // hashValue, then auto-resets it to -1 after ~50ms, so the token is only
        // briefly observable. Record every assignment via a Combine sink so a
        // poll that overshoots the window on a slow CI machine cannot miss the
        // transient (which made this test flaky on CI while passing locally).
        var observed: [Int] = []
        let cancellable = state.$selectedTabScrollToTop.sink { observed.append($0) }
        defer { cancellable.cancel() }

        state.selectTab(.home)
        // Re-tap must keep the current sub-timeline (not force back to Following)…
        #expect(state.timelineSelection == .federated)

        // …and still fire the scroll-to-top token for the timeline tab.
        for _ in 0..<200 where !observed.contains(MainTab.home.hashValue) {
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(observed.contains(MainTab.home.hashValue))
    }

    @Test @MainActor func profileTabTransitionsBetweenBottomNaturalAndTopAnchors() async throws {
        #expect(
            ProfileStickyTabLogic.pinThreshold(
                headerHeight: 500,
                topChromeHeight: 100
            ) == 400
        )
        #expect(
            ProfileStickyTabLogic.placement(
                headerHeight: 0,
                topChromeHeight: 100,
                scrollOffset: 500,
                viewportHeight: 800,
                tabBarHeight: 50
            ) == .natural
        )
        #expect(
            ProfileStickyTabLogic.placement(
                headerHeight: 900,
                topChromeHeight: 100,
                scrollOffset: 0,
                viewportHeight: 800,
                tabBarHeight: 50
            ) == .bottomDocked
        )
        #expect(
            ProfileStickyTabLogic.placement(
                headerHeight: 700,
                topChromeHeight: 100,
                scrollOffset: 0,
                viewportHeight: 800,
                tabBarHeight: 50
            ) == .natural
        )
        #expect(
            ProfileStickyTabLogic.placement(
                headerHeight: 500,
                topChromeHeight: 100,
                scrollOffset: 399.4,
                viewportHeight: 800,
                tabBarHeight: 50
            ) == .natural
        )
        #expect(
            ProfileStickyTabLogic.placement(
                headerHeight: 500,
                topChromeHeight: 100,
                scrollOffset: 399.5,
                viewportHeight: 800,
                tabBarHeight: 50
            ) == .topPinned
        )
        #expect(
            ProfileStickyTabLogic.overlayOffset(
                for: .bottomDocked,
                topChromeHeight: 100,
                viewportHeight: 800,
                tabBarHeight: 50
            ) == 750
        )
    }

    @Test @MainActor func profileHeaderChromeProgressClampsAcrossTransition() async throws {
        #expect(
            ProfileHeaderChromeLogic.collapseOffset(
                bannerHeight: 180,
                navigationBarHeight: 44
            ) == 136
        )
        #expect(
            ProfileHeaderChromeLogic.progress(
                scrollOffset: 100,
                bannerHeight: 180,
                navigationBarHeight: 44
            ) == 0
        )
        #expect(
            ProfileHeaderChromeLogic.progress(
                scrollOffset: 120,
                bannerHeight: 180,
                navigationBarHeight: 44
            ) == 0.5
        )
        #expect(
            ProfileHeaderChromeLogic.progress(
                scrollOffset: 136,
                bannerHeight: 180,
                navigationBarHeight: 44
            ) == 1
        )
        #expect(
            ProfileHeaderChromeLogic.progress(
                scrollOffset: 220,
                bannerHeight: 180,
                navigationBarHeight: 44
            ) == 1
        )
    }

    @Test @MainActor func profileChromeStateOwnsMeasurementsLayoutAndRefreshLifecycle() async throws {
        var state = ProfileChromeState()

        state.updateHeaderHeight(900)
        state.updateTabBarHeight(50)
        state.updateHeaderHeight(900.4)

        #expect(state.headerHeight == 900)
        #expect(state.tabBarHeight == 50)
        #expect(
            state.layout(viewportHeight: 800, topChromeHeight: 100)
                == ProfileChromeLayout(
                    pinnedContentHeight: 650,
                    tabPlacement: .bottomDocked,
                    tabOverlayOffset: 750
                )
        )

        let didArm = state.updateScroll(-72, pullRefreshThreshold: 72)
        #expect(didArm)
        #expect(state.pullDistance == 72)
        #expect(state.isPullRefreshArmed)
        let didBeginRefresh = state.beginRefreshIfArmed()
        #expect(didBeginRefresh)
        #expect(state.isRefreshing)
        #expect(!state.isPullRefreshArmed)

        state.finishRefresh()
        #expect(!state.isRefreshing)
        #expect(state.pullDistance == 0)
    }

    @Test @MainActor func profileLoadedEmptyTabDoesNotRequestAgain() async throws {
        let api = MockMastodonAPI()
        api.fetchAccountStatusesHandler = { _, _, _, _, _, _, _, _ in [] }
        let viewModel = ProfileViewModel(apiClient: api, accountID: "target")

        await viewModel.loadTabIfNeeded(.replies)
        await viewModel.loadTabIfNeeded(.replies)

        #expect(viewModel.tabLoadState(for: .replies) == .loaded)
        #expect(viewModel.replies.isEmpty)
        #expect(api.fetchAccountStatusesCalls.count == 1)
        #expect(api.fetchAccountStatusesCalls.first?.excludeReplies == false)
        #expect(api.fetchAccountStatusesCalls.first?.excludeReblogs == true)
    }

    @Test @MainActor func profileTabLoadAppliesToRequestedTabAfterSelectionChanges() async throws {
        let api = MockMastodonAPI()
        let reply = makeStatus(id: "reply", inReplyToID: "parent")
        api.fetchAccountStatusesHandler = { _, _, _, _, excludeReplies, _, _, _ in
            excludeReplies ? [] : [reply]
        }
        let viewModel = ProfileViewModel(apiClient: api, accountID: "target")
        viewModel.selectTab(.media)

        await viewModel.loadTabIfNeeded(.replies)

        #expect(viewModel.selectedTab == .media)
        #expect(viewModel.replies.map(\.id) == ["reply"])
        #expect(viewModel.media.isEmpty)
        #expect(viewModel.tabLoadState(for: .replies) == .loaded)
        #expect(viewModel.tabLoadState(for: .media) == .notLoaded)
    }

    @Test @MainActor func profileFollowingListLoadsTheRequestedAccount() async throws {
        let api = MockMastodonAPI()
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")
        api.fetchAccountFollowingHandler = { _, _, _ in [alice, bob] }
        let viewModel = ProfileConnectionsViewModel(
            accountID: "target",
            kind: .following,
            apiClient: api,
            pageSize: 20
        )

        await viewModel.loadInitial()

        #expect(viewModel.loadingState == .loaded)
        #expect(viewModel.accounts.map(\.id) == ["alice", "bob"])
        #expect(viewModel.hasMore == false)
        #expect(api.fetchAccountFollowingCalls.count == 1)
        #expect(api.fetchAccountFollowingCalls.first?.id == "target")
        #expect(api.fetchAccountFollowingCalls.first?.maxID == nil)
        #expect(api.fetchAccountFollowersCalls.isEmpty)
    }

    @Test @MainActor func profileFollowersListPaginatesAndRemovesDuplicateAccounts() async throws {
        let api = MockMastodonAPI()
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")
        let charlie = makeAccount(id: "charlie")
        api.fetchAccountFollowersHandler = { _, maxID, _ in
            maxID == nil ? [alice, bob] : [bob, charlie]
        }
        let viewModel = ProfileConnectionsViewModel(
            accountID: "target",
            kind: .followers,
            apiClient: api,
            pageSize: 2
        )

        await viewModel.loadInitial()
        await viewModel.loadMore()

        #expect(viewModel.accounts.map(\.id) == ["alice", "bob", "charlie"])
        #expect(viewModel.didFailLoadMore == false)
        #expect(api.fetchAccountFollowersCalls.count == 2)
        #expect(api.fetchAccountFollowersCalls.last?.maxID == "bob")
        #expect(api.fetchAccountFollowingCalls.isEmpty)
    }

    @Test @MainActor func profileConnectionsReplaceLoadedAccountsWhenCollectionsBecomeHidden() async {
        let api = MockMastodonAPI()
        let alice = makeAccount(id: "alice")
        var requestCount = 0
        api.fetchAccountFollowersHandler = { _, _, _ in
            requestCount += 1
            if requestCount == 1 {
                return [alice]
            }
            throw APIError.http(statusCode: 403, data: nil)
        }
        let viewModel = ProfileConnectionsViewModel(
            accountID: "target",
            kind: .followers,
            apiClient: api,
            pageSize: 20
        )

        await viewModel.loadInitial()
        await viewModel.refresh()

        #expect(viewModel.loadingState == .collectionsHidden)
        #expect(viewModel.accounts.isEmpty)
        #expect(viewModel.hasMore == false)
        #expect(viewModel.transientErrorMessage == nil)
    }

    @Test func profileHeaderURLRejectsMissingAndInvalidMedia() {
        #expect(makeAccount(header: "", headerStatic: "").profileHeaderURL == nil)
        #expect(
            makeAccount(
                header: "https://example.com/headers/missing.png",
                headerStatic: "https://example.com/headers/missing.png"
            ).profileHeaderURL == nil
        )
        #expect(makeAccount(header: "relative/header.png").profileHeaderURL == nil)
    }

    @Test func profileHeaderURLPrefersValidAnimatedMedia() {
        let account = makeAccount(
            header: "https://cdn.example.com/headers/animated.webp",
            headerStatic: "https://cdn.example.com/headers/static.png"
        )
        let staticFallback = makeAccount(
            header: "https://example.com/headers/missing.png",
            headerStatic: "https://cdn.example.com/headers/static.png"
        )

        #expect(
            account.profileHeaderURL
                == URL(string: "https://cdn.example.com/headers/animated.webp")
        )
        #expect(
            staticFallback.profileHeaderURL
                == URL(string: "https://cdn.example.com/headers/static.png")
        )
    }

    @Test func profileAvatarURLRejectsMissingAndInvalidMedia() {
        #expect(makeAccount(avatar: "", avatarStatic: "").profileAvatarURL == nil)
        #expect(
            makeAccount(
                avatar: "https://example.com/avatars/missing.png",
                avatarStatic: "https://example.com/avatars/missing.png"
            ).profileAvatarURL == nil
        )
        #expect(makeAccount(avatar: "relative/avatar.png").profileAvatarURL == nil)
    }

    @Test func profileAvatarURLPrefersValidAnimatedMedia() {
        let account = makeAccount(
            avatar: "https://cdn.example.com/avatars/animated.webp",
            avatarStatic: "https://cdn.example.com/avatars/static.png"
        )
        let staticFallback = makeAccount(
            avatar: "https://example.com/avatars/missing.png",
            avatarStatic: "https://cdn.example.com/avatars/static.png"
        )

        #expect(
            account.profileAvatarURL
                == URL(string: "https://cdn.example.com/avatars/animated.webp")
        )
        #expect(
            staticFallback.profileAvatarURL
                == URL(string: "https://cdn.example.com/avatars/static.png")
        )
    }

    @Test @MainActor func editProfileStartsWithoutSyntheticFieldAndLimitsFields() {
        let viewModel = EditProfileViewModel(
            apiClient: MockMastodonAPI(),
            initialAccount: makeAccount()
        )

        #expect(viewModel.fields.isEmpty)
        #expect(viewModel.addField() != nil)
        #expect(viewModel.addField() != nil)
        #expect(viewModel.addField() != nil)
        #expect(viewModel.addField() != nil)
        #expect(viewModel.addField() == nil)
        #expect(viewModel.fields.count == EditProfileViewModel.maxFieldCount)
    }

    @Test @MainActor func editProfileRejectsIncompleteFieldAndLimitsBio() async {
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = { EditableProfile(id: "account", displayName: "", note: "", fields: []) }
        let viewModel = EditProfileViewModel(apiClient: api, initialAccount: makeAccount())
        await viewModel.load()
        let appState = AppState()
        defer { AppFeedbackCenter.shared.dismiss() }

        let fieldID = viewModel.addField()
        #expect(fieldID != nil)
        viewModel.fields[0].name = "Website"
        viewModel.updateNote(String(repeating: "a", count: 520))

        #expect(viewModel.note.count == EditProfileViewModel.bioCharacterLimit)
        #expect(fieldID.map(viewModel.invalidFieldIDs.contains) == true)
        #expect(await viewModel.save(to: appState) == false)
        #expect(api.updateAccountProfileCalls.isEmpty)
    }

    @Test @MainActor func editProfileStagesMediaRemovalUntilSave() async throws {
        let initialAccount = makeAccount(
            avatar: "https://cdn.example.com/avatar.png",
            avatarStatic: "https://cdn.example.com/avatar.png",
            header: "https://cdn.example.com/header.png",
            headerStatic: "https://cdn.example.com/header.png"
        )
        let updatedAccount = makeAccount()
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = { EditableProfile(id: "account", displayName: "", note: "", fields: []) }
        api.updateAccountProfileHandler = { _, _, _, _, _, _, _ in updatedAccount }
        api.verifyCredentialsHandler = { updatedAccount }
        let appState = AppState()
        appState.currentAccount = initialAccount
        let viewModel = EditProfileViewModel(apiClient: api, initialAccount: initialAccount)
        await viewModel.load()
        defer { AppFeedbackCenter.shared.dismiss() }

        viewModel.markAvatarRemoved()
        viewModel.markHeaderRemoved()

        #expect(viewModel.isAvatarRemoved)
        #expect(viewModel.isHeaderRemoved)
        #expect(viewModel.hasUnsavedChanges)
        #expect(api.updateAccountProfileCalls.isEmpty)
        #expect(appState.currentAccount?.profileAvatarURL != nil)
        #expect(appState.currentAccount?.profileHeaderURL != nil)

        #expect(await viewModel.save(to: appState))
        let call = try #require(api.updateAccountProfileCalls.first)
        #expect(call.removeAvatar)
        #expect(call.removeHeader)
        #expect(call.avatar == nil)
        #expect(call.header == nil)
        #expect(appState.currentAccount?.profileAvatarURL == nil)
        #expect(appState.currentAccount?.profileHeaderURL == nil)
    }

    @Test @MainActor func editProfileSubmitsOnlyCompleteTrimmedFields() async throws {
        let initialAccount = makeAccount()
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = { EditableProfile(id: "account", displayName: "", note: "", fields: []) }
        api.updateAccountProfileHandler = { _, _, _, _, _, _, fields in
            self.makeAccount(fields: fields ?? [])
        }
        api.verifyCredentialsHandler = {
            self.makeAccount(
                fields: [AccountField(name: "Website", value: "https://moro.example")]
            )
        }
        let viewModel = EditProfileViewModel(apiClient: api, initialAccount: initialAccount)
        await viewModel.load()
        let appState = AppState()
        defer { AppFeedbackCenter.shared.dismiss() }

        _ = viewModel.addField()
        viewModel.fields[0].name = "  Website  "
        viewModel.fields[0].value = "  https://moro.example  "

        #expect(await viewModel.save(to: appState))
        let fields = try #require(api.updateAccountProfileCalls.first?.fields)
        #expect(fields.count == 1)
        #expect(fields[0].name == "Website")
        #expect(fields[0].value == "https://moro.example")
    }

    @Test @MainActor func accountPrefersVerifiedFormattedProfileFields() throws {
        let payload = """
            {
              "id": "verified-account",
              "username": "verified",
              "fields": [
                {
                  "name": "Website",
                  "value": "https://example.com/",
                  "verified_at": "2026-07-10T08:50:41.033+00:00"
                }
              ],
              "formatted_fields": [
                {
                  "name": "Website",
                  "value": "<a href=\\\"https://example.com/\\\">example.com</a>",
                  "verified_at": "2026-07-10T08:50:41.033+00:00"
                }
              ]
            }
            """

        let account = try JSONDecoder().decode(Account.self, from: Data(payload.utf8))
        let field = try #require(account.fields.first)

        #expect(field.value.contains("<a href="))
        #expect(field.isVerified)
        #expect(field.verifiedAt != nil)
    }

    @Test @MainActor func accountDecodesVerifiedProfileFieldFromFieldsPayload() throws {
        let payload = """
            {
              "id": "113817148213605504",
              "username": "jabsonik",
              "fields": [
                {
                  "name": "Outola radio show (FI)",
                  "value": "<a href=\\\"https://outo.la\\\">outo.la</a>",
                  "verified_at": "2026-09-01T18:29:49.661+00:00"
                },
                {
                  "name": "Hire me! (FI)",
                  "value": "<a href=\\\"https://mediakali.fi\\\">mediakali.fi</a>",
                  "verified_at": null
                }
              ]
            }
            """

        let account = try JSONDecoder().decode(Account.self, from: Data(payload.utf8))

        #expect(account.fields.count == 2)
        #expect(account.fields[0].isVerified)
        #expect(account.fields[0].verifiedAt != nil)
        #expect(!account.fields[1].isVerified)
        #expect(account.fields[1].verifiedAt == nil)
    }

    @Test @MainActor func followButtonResolvesActionableRelationshipStates() async throws {
        #expect(FollowButton.ButtonState.resolve(relationship: nil) == .notFollowing)
        #expect(
            FollowButton.ButtonState.resolve(
                relationship: makeRelationship(id: "target", following: true)
            ) == .following
        )
        #expect(
            FollowButton.ButtonState.resolve(
                relationship: makeRelationship(id: "target", requested: true)
            ) == .requested
        )
        #expect(
            FollowButton.ButtonState.resolve(
                relationship: makeRelationship(id: "target", blocking: true)
            ) == .blocked
        )
        #expect(
            FollowButton.ButtonState.resolve(
                relationship: makeRelationship(id: "target", domainBlocking: true)
            ) == .domainBlocked
        )
    }

    @Test @MainActor func profileFollowRequestCanBeCancelledWithoutChangingFollowerCount() async throws {
        let api = MockMastodonAPI()
        let cancelledRelationship = makeRelationship(id: "target")
        api.unfollowAccountHandler = { _ in cancelledRelationship }

        let viewModel = ProfileViewModel(
            apiClient: api,
            accountID: "target",
            currentAccountID: "me"
        )
        viewModel.account = makeAccount(id: "target").updating(followersCount: 10)
        viewModel.relationship = makeRelationship(id: "target", requested: true)

        await viewModel.toggleFollow()

        #expect(api.unfollowAccountCallIDs == ["target"])
        #expect(viewModel.relationship?.requested == false)
        #expect(viewModel.account?.followersCount == 10)
    }

    @Test @MainActor func profileFollowRequestDoesNotIncrementFollowerCountBeforeApproval() async throws {
        let api = MockMastodonAPI()
        let requestedRelationship = makeRelationship(id: "target", requested: true)
        api.followAccountHandler = { _, _, _ in requestedRelationship }

        let viewModel = ProfileViewModel(
            apiClient: api,
            accountID: "target",
            currentAccountID: "me"
        )
        viewModel.account = makeAccount(id: "target").updating(followersCount: 10)
        viewModel.relationship = makeRelationship(id: "target")

        await viewModel.toggleFollow()

        #expect(api.followAccountCallIDs == ["target"])
        #expect(viewModel.relationship?.requested == true)
        #expect(viewModel.account?.followersCount == 10)
    }

    @Test @MainActor func profileNotificationUsesIndependentLoadingState() async throws {
        let api = MockMastodonAPI()
        let viewModel = ProfileViewModel(
            apiClient: api,
            accountID: "target",
            currentAccountID: "me"
        )
        viewModel.relationship = makeRelationship(id: "target", following: true)

        var observedFollowLoading = true
        var observedNotificationLoading = false
        api.followAccountHandler = { _, reblogs, notify in
            observedFollowLoading = viewModel.isUpdatingRelationship
            observedNotificationLoading = viewModel.isUpdatingNotification
            #expect(reblogs == nil)
            #expect(notify == true)
            return self.makeRelationship(id: "target", following: true, notifying: true)
        }

        await viewModel.toggleNotification()

        #expect(!observedFollowLoading)
        #expect(observedNotificationLoading)
        #expect(!viewModel.isUpdatingRelationship)
        #expect(!viewModel.isUpdatingNotification)
        #expect(viewModel.relationship?.notifying == true)
    }

    @Test @MainActor func timelinePageOrderMatchesHomeLocalFederated() async throws {
        #expect(TimelineType.builtin == [.home, .local, .federated])
    }

    @Test @MainActor func conversationKeyboardMetricsFallbackDurationAndPadding() async throws {
        let fallback = ConversationKeyboardMetrics.animationDuration(from: nil)
        #expect(fallback == 0.25)

        let custom = ConversationKeyboardMetrics.animationDuration(
            from: [UIResponder.keyboardAnimationDurationUserInfoKey: 0.42]
        )
        #expect(custom == 0.42)

        #expect(ConversationKeyboardMetrics.inputBottomPadding(isKeyboardVisible: true) == 3)
        #expect(ConversationKeyboardMetrics.inputBottomPadding(isKeyboardVisible: false) == 6)
    }

    @Test @MainActor func conversationMessageLayoutClustersSameSenderMessages() async throws {
        let sender = makeAccount(id: "alice", username: "alice")
        let first = makeStatus(
            id: "m1",
            createdAt: Date(timeIntervalSince1970: 100),
            account: sender
        )
        let second = makeStatus(
            id: "m2",
            createdAt: Date(timeIntervalSince1970: 220),
            account: sender
        )

        let firstLayout = ConversationMessageLayout.resolve(
            current: first,
            previous: nil,
            next: second,
            isOutgoing: false,
            isGroupConversation: true
        )
        let secondLayout = ConversationMessageLayout.resolve(
            current: second,
            previous: first,
            next: nil,
            isOutgoing: false,
            isGroupConversation: true
        )

        #expect(firstLayout.showsSenderName == true)
        #expect(firstLayout.showsAvatar == true)
        #expect(firstLayout.showsTimestamp == true)
        #expect(secondLayout.showsSenderName == false)
        #expect(secondLayout.showsAvatar == false)
        #expect(secondLayout.showsTimestamp == true)
    }

    @Test @MainActor func conversationMessageLayoutBreaksClusterAcrossSendersOrLargeGaps() async throws {
        let alice = makeAccount(id: "alice", username: "alice")
        let bob = makeAccount(id: "bob", username: "bob")
        let current = makeStatus(
            id: "m-current",
            createdAt: Date(timeIntervalSince1970: 600),
            account: alice
        )
        let previous = makeStatus(
            id: "m-previous",
            createdAt: Date(timeIntervalSince1970: 0),
            account: alice
        )
        let next = makeStatus(
            id: "m-next",
            createdAt: Date(timeIntervalSince1970: 620),
            account: bob
        )

        let layout = ConversationMessageLayout.resolve(
            current: current,
            previous: previous,
            next: next,
            isOutgoing: false,
            isGroupConversation: true
        )

        #expect(layout.showsSenderName == true)
        #expect(layout.showsAvatar == true)
        #expect(layout.showsTimestamp == true)
        #expect(layout.topPadding == 12)
        #expect(layout.bottomPadding == 8)
    }

    @Test @MainActor func conversationThreadPresentationSeparatesRootStatusFromReplies() async throws {
        let sender = makeAccount(id: "alice", username: "alice")
        let root = makeStatus(id: "root", account: sender, visibility: "public")
        let firstReply = makeStatus(id: "reply-1", account: sender, inReplyToID: root.id)
        let secondReply = makeStatus(id: "reply-2", account: sender, inReplyToID: firstReply.id)
        let messages = [root, firstReply, secondReply]

        let resolvedRoot = ConversationThreadPresentation.rootStatus(in: messages)
        let replies = ConversationThreadPresentation.replyMessages(
            in: messages,
            rootStatus: resolvedRoot
        )

        #expect(resolvedRoot?.id == root.id)
        #expect(replies.map(\.id) == [firstReply.id, secondReply.id])
    }

    @Test @MainActor func conversationDirectRootKeepsItsFullMessageBody() {
        for visibility in ["direct", nil] {
            let root = makeStatus(id: "direct-root", visibility: visibility)
            let reply = makeStatus(id: "reply", inReplyToID: root.id, visibility: "direct")
            let messages = [root, reply]
            let context = ConversationThreadPresentation.rootStatus(in: messages)

            #expect(context == nil)
            #expect(ConversationThreadPresentation.replyMessages(in: messages, rootStatus: context).map(\.id)
                    == [root.id, reply.id])
        }
    }

    @Test @MainActor func conversationContentRetainsEllipsisAnchorAndParagraphs() {
        let url = URL(string: "https://remote.example/@reader/123456789")!
        let status = makeStatus(id: "direct-link", content: """
            <p><a href="https://local.example/@reader" class="mention">@reader</a></p>
            <p><a href="\(url.absoluteString)"><span class="invisible">https://</span><span class="ellipsis">remote.example/@reader/123</span><span class="invisible">456789</span></a></p>
            <p>Second paragraph<br>Another line</p>
            """, visibility: "direct")
        let elements = ConversationMessageContent.elements(for: status)
        #expect(elements.contains { element in
            if case .link(let label, let target) = element {
                return label.contains("remote.example/@reader/123") && target == url
            }
            return false
        })
        #expect(elements.plainTextValue.contains("\n"))
        #expect(elements.plainTextValue.contains("Second paragraph\nAnother line"))
        #expect(ConversationMessageContent.summary(for: status).contains("remote.example/@reader/123"))
        #expect(!ConversationMessageContent.summary(for: status).contains("\n"))
    }

    @Test @MainActor func conversationContentDetectsPlainLinksWithoutPreviewMetadata() {
        let status = makeStatus(id: "plain-link", content: "<p>Read https://example.com/article?first=1&amp;second=2</p>", visibility: "direct")
        #expect(ConversationMessageContent.elements(for: status).contains { element in
            if case .link(_, let url) = element {
                return url.absoluteString == "https://example.com/article?first=1&second=2"
            }
            return false
        })
    }

    @Test @MainActor func conversationSummaryFallsBackToExistingLinkCard() throws {
        for title in ["An article", ""] {
            let card = try JSONDecoder().decode(Status.PreviewCard.self, from: Data("""
                {"url":"https://example.com/article","title":"\(title)","description":"","type":"link"}
                """.utf8))
            let status = makeStatus(id: "card-only", content: "<p></p>", visibility: "direct", card: card)
            #expect(ConversationMessageContent.summary(for: status)
                    == (title.isEmpty ? "https://example.com/article" : title))
        }
    }

    @Test @MainActor func conversationThreadPresentationKeepsAllMessagesWhenRootIsUnavailable() async throws {
        let firstReply = makeStatus(id: "reply-1", inReplyToID: "missing-root")
        let secondReply = makeStatus(id: "reply-2", inReplyToID: firstReply.id)
        let messages = [firstReply, secondReply]

        let resolvedRoot = ConversationThreadPresentation.rootStatus(in: messages)
        let replies = ConversationThreadPresentation.replyMessages(
            in: messages,
            rootStatus: resolvedRoot
        )

        #expect(resolvedRoot == nil)
        #expect(replies.map(\.id) == messages.map(\.id))
    }

    @Test @MainActor func notificationsPrefetchStatusAndQuotePrefetchesBothStatuses() async throws {
        let api = MockMastodonAPI()
        let viewModel = NotificationsViewModel(apiClient: api)
        let quoted = makeStatus(id: "quoted-\(UUID().uuidString)")
        let status = makeStatus(
            id: "main-\(UUID().uuidString)",
            quote: Status.Quote(state: .accepted, quotedStatus: quoted)
        )

        api.fetchStatusDetailHandler = { id in
            Status(
                id: id,
                content: "prefetched-\(id)",
                createdAt: Date(),
                account: Account(
                    id: "acct-\(id)",
                    username: "user_\(id)",
                    acct: "user_\(id)@example.com",
                    displayName: "User \(id)",
                    note: "",
                    avatar: "",
                    avatarStatic: "",
                    header: "",
                    headerStatic: "",
                    followersCount: 0,
                    followingCount: 0,
                    statusesCount: 0
                ),
                mediaAttachments: [],
                favouritesCount: 0,
                reblogsCount: 0,
                repliesCount: 0,
                bookmarked: false,
                favourited: false,
                reblogged: false
            )
        }

        await viewModel.prefetchStatusAndQuoteIfNeeded(for: status)

        #expect(Set(api.fetchStatusDetailCallIDs) == Set([status.id, quoted.id]))
        #expect(Set(api.fetchStatusContextCallIDs) == Set([status.id, quoted.id]))
    }

    @Test @MainActor func notificationsPrefetchStatusAndQuoteAvoidsDuplicateRequests() async throws {
        let api = MockMastodonAPI()
        let viewModel = NotificationsViewModel(apiClient: api)
        let quoted = makeStatus(id: "quoted-\(UUID().uuidString)")
        let status = makeStatus(
            id: "main-\(UUID().uuidString)",
            quote: Status.Quote(state: .accepted, quotedStatus: quoted)
        )

        api.fetchStatusDetailHandler = { id in
            Status(
                id: id,
                content: "prefetched-\(id)",
                createdAt: Date(),
                account: Account(
                    id: "acct-\(id)",
                    username: "user_\(id)",
                    acct: "user_\(id)@example.com",
                    displayName: "User \(id)",
                    note: "",
                    avatar: "",
                    avatarStatic: "",
                    header: "",
                    headerStatic: "",
                    followersCount: 0,
                    followingCount: 0,
                    statusesCount: 0
                ),
                mediaAttachments: [],
                favouritesCount: 0,
                reblogsCount: 0,
                repliesCount: 0,
                bookmarked: false,
                favourited: false,
                reblogged: false
            )
        }

        await viewModel.prefetchStatusAndQuoteIfNeeded(for: status)
        await viewModel.prefetchStatusAndQuoteIfNeeded(for: status)

        #expect(api.fetchStatusDetailCallIDs.count == 2)
        #expect(api.fetchStatusContextCallIDs.count == 2)
        #expect(Set(api.fetchStatusDetailCallIDs) == Set([status.id, quoted.id]))
    }

    @Test @MainActor func trendsTagsEndpointBuildsExpectedPathAndLimitQuery() async throws {
        let endpoint = MastodonEndpoint.trendsTags(limit: 10)
        let limitItem = endpoint.queryItems?.first(where: { $0.name == "limit" })

        #expect(endpoint.method == "GET")
        #expect(endpoint.path == "/api/v1/trends/tags")
        #expect(limitItem?.value == "10")
    }

    @Test @MainActor func notificationUnreadCountEndpointUsesMastodon43Path() async throws {
        let endpoint = MastodonEndpoint.notificationUnreadCount

        #expect(endpoint.method == "GET")
        #expect(endpoint.path == "/api/v1/notifications/unread_count")
        #expect(endpoint.queryItems == nil)
    }

    @Test @MainActor func notificationPolicyAndRequestEndpointsUseMastodon43Paths() async throws {
        let policy = MastodonEndpoint.notificationPolicy
        let updatePolicy = MastodonEndpoint.updateNotificationPolicy
        let requests = MastodonEndpoint.notificationRequests(maxID: "42", limit: 40)
        let accept = MastodonEndpoint.acceptNotificationRequest(id: "request-7")
        let dismiss = MastodonEndpoint.dismissNotificationRequest(id: "request-7")

        #expect(policy.method == "GET")
        #expect(policy.path == "/api/v2/notifications/policy")
        #expect(updatePolicy.method == "PATCH")
        #expect(updatePolicy.path == "/api/v2/notifications/policy")
        #expect(requests.method == "GET")
        #expect(requests.path == "/api/v1/notifications/requests")
        #expect(requests.queryItems?.contains(URLQueryItem(name: "max_id", value: "42")) == true)
        #expect(requests.queryItems?.contains(URLQueryItem(name: "limit", value: "40")) == true)
        #expect(accept.method == "POST")
        #expect(accept.path == "/api/v1/notifications/requests/request-7/accept")
        #expect(dismiss.method == "POST")
        #expect(dismiss.path == "/api/v1/notifications/requests/request-7/dismiss")
    }

    @Test func notificationPolicyDecodesCurrentAndOlderServerResponses() throws {
        let currentJSON = Data(
            """
            {
              "for_not_following": "filter",
              "for_not_followers": "accept",
              "for_new_accounts": "drop",
              "for_private_mentions": "filter",
              "for_limited_accounts": "drop",
              "for_bots": "accept",
              "summary": {
                "pending_requests_count": 3,
                "pending_notifications_count": 8
              }
            }
            """.utf8)
        let olderJSON = Data(
            """
            {
              "for_not_following": "accept",
              "for_not_followers": "accept",
              "for_new_accounts": "accept",
              "for_private_mentions": "filter",
              "for_limited_accounts": "drop",
              "summary": {
                "pending_requests_count": 0,
                "pending_notifications_count": 0
              }
            }
            """.utf8)

        let decoder = JSONDecoder()
        let current = try decoder.decode(ServerNotificationPolicy.self, from: currentJSON)
        let older = try decoder.decode(ServerNotificationPolicy.self, from: olderJSON)

        #expect(current.forNotFollowing == .filter)
        #expect(current.forNewAccounts == .drop)
        #expect(current.forBots == .accept)
        #expect(current.summary.pendingRequestsCount == 3)
        #expect(current.summary.pendingNotificationsCount == 8)
        #expect(older.forBots == nil)
        #expect(older.forPrivateMentions == .filter)
    }

    @Test @MainActor func notificationsEndpointSendsSupportedTypesForFallbackPayloads() async throws {
        let endpoint = MastodonEndpoint.notifications(
            maxID: "40",
            sinceID: nil,
            limit: 30,
            types: ["mention"],
            supportedTypes: ["mention", "quote"]
        )

        #expect(endpoint.path == "/api/v1/notifications")
        #expect(endpoint.queryItems?.contains(URLQueryItem(name: "max_id", value: "40")) == true)
        #expect(
            endpoint.queryItems?
                .filter { $0.name == "types[]" }
                .compactMap(\.value) == ["mention"]
        )
        #expect(
            endpoint.queryItems?
                .filter { $0.name == "supported_types[]" }
                .compactMap(\.value) == ["mention", "quote"]
        )
    }

    @Test @MainActor func trendsTagsEndpointWithoutLimitHasNoQueryItems() async throws {
        let endpoint = MastodonEndpoint.trendsTags(limit: nil)

        #expect(endpoint.path == "/api/v1/trends/tags")
        #expect(endpoint.queryItems?.isEmpty ?? true)
    }

    @Test @MainActor func trendsStatusesEndpointBuildsExpectedPathAndLimitQuery() async throws {
        let endpoint = MastodonEndpoint.trendsStatuses(limit: 10)
        let limitItem = endpoint.queryItems?.first(where: { $0.name == "limit" })

        #expect(endpoint.method == "GET")
        #expect(endpoint.path == "/api/v1/trends/statuses")
        #expect(limitItem?.value == "10")
    }

    @Test @MainActor func trendsStatusesEndpointWithoutLimitHasNoQueryItems() async throws {
        let endpoint = MastodonEndpoint.trendsStatuses(limit: nil)

        #expect(endpoint.path == "/api/v1/trends/statuses")
        #expect(endpoint.queryItems?.isEmpty ?? true)
    }

    @Test @MainActor func directoryEndpointBuildsExpectedQuery() async throws {
        let endpoint = MastodonEndpoint.directory(
            limit: 10,
            offset: 20,
            order: "active",
            local: true
        )
        let items = endpoint.queryItems ?? []

        #expect(endpoint.method == "GET")
        #expect(endpoint.path == "/api/v1/directory")
        #expect(items.first(where: { $0.name == "limit" })?.value == "10")
        #expect(items.first(where: { $0.name == "offset" })?.value == "20")
        #expect(items.first(where: { $0.name == "order" })?.value == "active")
        #expect(items.first(where: { $0.name == "local" })?.value == "true")
    }

    @Test @MainActor func directoryEndpointWithoutOptionalParamsHasNoQueryItems() async throws {
        let endpoint = MastodonEndpoint.directory(
            limit: nil,
            offset: nil,
            order: nil,
            local: nil
        )

        #expect(endpoint.path == "/api/v1/directory")
        #expect(endpoint.queryItems?.isEmpty ?? true)
    }

    @Test @MainActor func conversationsEndpointBuildsExpectedQuery() async throws {
        let endpoint = MastodonEndpoint.conversations(
            maxID: "100",
            sinceID: "50",
            limit: 20
        )
        let items = endpoint.queryItems ?? []

        #expect(endpoint.method == "GET")
        #expect(endpoint.path == "/api/v1/conversations")
        #expect(items.first(where: { $0.name == "max_id" })?.value == "100")
        #expect(items.first(where: { $0.name == "since_id" })?.value == "50")
        #expect(items.first(where: { $0.name == "limit" })?.value == "20")
    }

    @Test @MainActor func conversationsEndpointWithOnlyLimitBuildsRequiredQuery() async throws {
        let endpoint = MastodonEndpoint.conversations(
            maxID: nil,
            sinceID: nil,
            limit: 20
        )
        let items = endpoint.queryItems ?? []

        #expect(endpoint.path == "/api/v1/conversations")
        #expect(items.first(where: { $0.name == "max_id" }) == nil)
        #expect(items.first(where: { $0.name == "since_id" }) == nil)
        #expect(items.first(where: { $0.name == "limit" })?.value == "20")
    }

    @Test @MainActor func readConversationEndpointBuildsExpectedPathAndMethod() async throws {
        let endpoint = MastodonEndpoint.readConversation(id: "42")

        #expect(endpoint.method == "POST")
        #expect(endpoint.path == "/api/v1/conversations/42/read")
        #expect(endpoint.queryItems == nil)
    }

    @Test @MainActor func deleteConversationEndpointBuildsExpectedPathAndMethod() async throws {
        let endpoint = MastodonEndpoint.deleteConversation(id: "42")

        #expect(endpoint.method == "DELETE")
        #expect(endpoint.path == "/api/v1/conversations/42")
        #expect(endpoint.queryItems == nil)
    }

    @Test @MainActor func deleteProfileAvatarEndpointBuildsExpectedPathAndMethod() async throws {
        let endpoint = MastodonEndpoint.deleteProfileAvatar

        #expect(endpoint.method == "DELETE")
        #expect(endpoint.path == "/api/v1/profile/avatar")
        #expect(endpoint.queryItems == nil)
    }

    @Test @MainActor func deleteProfileHeaderEndpointBuildsExpectedPathAndMethod() async throws {
        let endpoint = MastodonEndpoint.deleteProfileHeader

        #expect(endpoint.method == "DELETE")
        #expect(endpoint.path == "/api/v1/profile/header")
        #expect(endpoint.queryItems == nil)
    }

    @Test @MainActor func scheduledStatusesEndpointBuildsExpectedPathAndQuery() async throws {
        let endpoint = MastodonEndpoint.scheduledStatuses(
            maxID: "100",
            sinceID: "80",
            limit: 15
        )
        let items = endpoint.queryItems ?? []

        #expect(endpoint.method == "GET")
        #expect(endpoint.path == "/api/v1/scheduled_statuses")
        #expect(items.first(where: { $0.name == "max_id" })?.value == "100")
        #expect(items.first(where: { $0.name == "since_id" })?.value == "80")
        #expect(items.first(where: { $0.name == "limit" })?.value == "15")
    }

    @Test @MainActor func cancelScheduledStatusEndpointBuildsExpectedPathAndMethod() async throws {
        let endpoint = MastodonEndpoint.cancelScheduledStatus(id: "42")

        #expect(endpoint.method == "DELETE")
        #expect(endpoint.path == "/api/v1/scheduled_statuses/42")
        #expect(endpoint.queryItems == nil)
    }

    @Test @MainActor func statusHistoryEndpointBuildsExpectedPathAndMethod() async throws {
        let endpoint = MastodonEndpoint.statusHistory(id: "42")

        #expect(endpoint.method == "GET")
        #expect(endpoint.path == "/api/v1/statuses/42/history")
        #expect(endpoint.queryItems == nil)
    }

    @Test @MainActor func followRequestActionEndpointsBuildExpectedPathsAndMethods() async throws {
        let authorizeEndpoint = MastodonEndpoint.authorizeFollowRequest(id: "acct-1")
        let rejectEndpoint = MastodonEndpoint.rejectFollowRequest(id: "acct-1")

        #expect(authorizeEndpoint.method == "POST")
        #expect(authorizeEndpoint.path == "/api/v1/follow_requests/acct-1/authorize")
        #expect(rejectEndpoint.method == "POST")
        #expect(rejectEndpoint.path == "/api/v1/follow_requests/acct-1/reject")
    }

    @Test @MainActor func announcementEndpointsBuildExpectedPathsAndMethods() async throws {
        let listEndpoint = MastodonEndpoint.announcements
        let dismissEndpoint = MastodonEndpoint.dismissAnnouncement(id: "anno-1")
        let addReactionEndpoint = MastodonEndpoint.addAnnouncementReaction(id: "anno-1", name: "👍")
        let removeReactionEndpoint = MastodonEndpoint.removeAnnouncementReaction(
            id: "anno-1",
            name: "👍"
        )

        #expect(listEndpoint.method == "GET")
        #expect(listEndpoint.path == "/api/v1/announcements")
        #expect(dismissEndpoint.method == "POST")
        #expect(dismissEndpoint.path == "/api/v1/announcements/anno-1/dismiss")
        #expect(addReactionEndpoint.method == "PUT")
        #expect(addReactionEndpoint.path.contains("/api/v1/announcements/anno-1/reactions/"))
        #expect(removeReactionEndpoint.method == "DELETE")
        #expect(removeReactionEndpoint.path.contains("/api/v1/announcements/anno-1/reactions/"))
    }

    @Test @MainActor func listAccountsEndpointsBuildExpectedPathsMethodsAndQuery() async throws {
        let fetchEndpoint = MastodonEndpoint.listAccounts(
            id: "list-1",
            maxID: "55",
            sinceID: "44",
            limit: 20
        )
        let addEndpoint = MastodonEndpoint.addAccountsToList(id: "list-1")
        let removeEndpoint = MastodonEndpoint.removeAccountsFromList(id: "list-1")
        let query = fetchEndpoint.queryItems ?? []

        #expect(fetchEndpoint.method == "GET")
        #expect(fetchEndpoint.path == "/api/v1/lists/list-1/accounts")
        #expect(query.first(where: { $0.name == "max_id" })?.value == "55")
        #expect(query.first(where: { $0.name == "since_id" })?.value == "44")
        #expect(query.first(where: { $0.name == "limit" })?.value == "20")

        #expect(addEndpoint.method == "POST")
        #expect(addEndpoint.path == "/api/v1/lists/list-1/accounts")
        #expect(removeEndpoint.method == "DELETE")
        #expect(removeEndpoint.path == "/api/v1/lists/list-1/accounts")
    }

    @Test @MainActor func conversationDetailBuildOutgoingTextAddsMissingMentions() async throws {
        let me = makeAccount(id: "me")
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")

        let result = ConversationDetailViewModel.buildOutgoingText(
            draft: "hello world",
            participants: [me, alice, bob],
            currentUserID: me.id
        )

        #expect(result.contains("@\(alice.acct.lowercased())"))
        #expect(result.contains("@\(bob.acct.lowercased())"))
        #expect(result.hasSuffix("hello world"))
    }

    @Test @MainActor func conversationDetailBuildOutgoingTextAvoidsDuplicateMentions() async throws {
        let me = makeAccount(id: "me")
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")

        let draft = "  hi @\(alice.acct)  "
        let result = ConversationDetailViewModel.buildOutgoingText(
            draft: draft,
            participants: [me, alice, bob],
            currentUserID: me.id
        )

        let aliceMention = "@\(alice.acct.lowercased())"
        let bobMention = "@\(bob.acct.lowercased())"
        #expect(result.components(separatedBy: aliceMention).count - 1 == 1)
        #expect(result.contains(bobMention))
        #expect(result.hasSuffix("hi @\(alice.acct)"))
    }

    @Test @MainActor func conversationDetailHasSendableContentRejectsWhitespace() async throws {
        #expect(ConversationDetailViewModel.hasSendableContent(" \n\t  ") == false)
        #expect(ConversationDetailViewModel.hasSendableContent(" hello ") == true)
    }

    @Test @MainActor func conversationStreamEventIDTracksMessageAndUnreadState() async throws {
        let first = StreamEvent.conversation(
            conversationId: "c1",
            unread: true,
            lastStatus: makeStatus(id: "message-1")
        )
        let second = StreamEvent.conversation(
            conversationId: "c1",
            unread: true,
            lastStatus: makeStatus(id: "message-2")
        )
        let read = StreamEvent.conversation(
            conversationId: "c1",
            unread: false,
            lastStatus: makeStatus(id: "message-2")
        )

        #expect(first.id != second.id)
        #expect(second.id != read.id)
    }

    @Test @MainActor func directMessagesStreamConversationEventMovesConversationToTop() async throws {
        let api = MockMastodonAPI()
        let viewModel = DirectMessagesViewModel(apiClient: api)
        let olderStatus = makeStatus(id: "old", createdAt: Date(timeIntervalSince1970: 100))
        let newerStatus = makeStatus(id: "new", createdAt: Date(timeIntervalSince1970: 200))

        viewModel.conversations = [
            makeConversation(id: "c1", unread: false, lastStatus: olderStatus),
            makeConversation(id: "c2", unread: false, lastStatus: makeStatus(id: "other"))
        ]

        viewModel.handleStreamEvent(
            .conversation(conversationId: "c1", unread: true, lastStatus: newerStatus)
        )

        #expect(viewModel.conversations.first?.id == "c1")
        #expect(viewModel.conversations.first?.unread == true)
        #expect(viewModel.conversations.first?.lastStatus?.id == "new")
    }

    @Test @MainActor func directMessagesDeleteEventRefreshesConversationPreview() async throws {
        let api = MockMastodonAPI()
        let viewModel = DirectMessagesViewModel(apiClient: api)
        let deletedStatus = makeStatus(id: "deleted")
        let refreshedStatus = makeStatus(id: "replacement")

        viewModel.conversations = [
            makeConversation(id: "c1", unread: false, lastStatus: deletedStatus)
        ]
        api.fetchConversationsHandler = { _, _, _ in
            [
                Conversation(
                    id: "c1",
                    unread: false,
                    accounts: [],
                    lastStatus: refreshedStatus,
                    updatedAt: Date()
                )
            ]
        }

        viewModel.handleStreamEvent(.delete(statusId: "deleted"))
        try await Task.sleep(nanoseconds: 80_000_000)

        #expect(api.fetchConversationsCallCount == 1)
        #expect(viewModel.conversations.first?.lastStatus?.id == "replacement")
    }

    @Test @MainActor func directMessagesFindsExistingConversationByParticipantID() async throws {
        let api = MockMastodonAPI()
        let viewModel = DirectMessagesViewModel(apiClient: api)
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")

        viewModel.conversations = [
            makeConversation(id: "c1", unread: false, accounts: [alice], lastStatus: nil),
            makeConversation(id: "c2", unread: false, accounts: [bob], lastStatus: nil),
        ]

        let found = viewModel.conversation(withParticipantID: "bob")
        let missing = viewModel.conversation(withParticipantID: "carol")

        #expect(found?.id == "c2")
        #expect(missing == nil)
    }

    @Test @MainActor func directMessagesPaginationUsesOpaqueCursorAndDeduplicatesPages() async {
        let api = MockMastodonAPI()
        var requestedCursors: [String?] = []
        api.fetchConversationsPageHandler = { maxID, limit in
            requestedCursors.append(maxID)
            #expect(limit == 20)
            if maxID == nil {
                let first = self.makeConversation(
                    id: "conversation-1",
                    unread: false,
                    lastStatus: nil
                )
                return ConversationsPage(
                    conversations: [first, first],
                    nextMaxID: "opaque:next-page"
                )
            }
            #expect(maxID == "opaque:next-page")
            return ConversationsPage(
                conversations: [
                    self.makeConversation(id: "conversation-1", unread: false, lastStatus: nil),
                    self.makeConversation(id: "conversation-2", unread: true, lastStatus: nil),
                ],
                nextMaxID: nil
            )
        }
        let viewModel = DirectMessagesViewModel(apiClient: api)

        await viewModel.loadInitial()
        await viewModel.loadMore()

        #expect(requestedCursors.count == 2)
        #expect(requestedCursors[0] == nil)
        #expect(requestedCursors[1] == "opaque:next-page")
        #expect(viewModel.conversations.map(\.id) == ["conversation-1", "conversation-2"])
    }

    @Test @MainActor func draftConversationUsesDraftPrefixAndParticipants() async throws {
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")

        let draft = Conversation.draft(participants: [alice, bob])

        #expect(draft.isDraft)
        #expect(draft.unread == false)
        #expect(draft.accounts.count == 2)
        #expect(draft.lastStatus == nil)
    }

    @Test @MainActor func conversationDetailStreamConversationEventUpsertsMessages() async throws {
        let api = MockMastodonAPI()
        let me = makeAccount(id: "me")
        let alice = makeAccount(id: "alice")
        let conversation = Conversation(
            id: "c1",
            unread: false,
            accounts: [me, alice],
            lastStatus: nil
        )
        let viewModel = ConversationDetailViewModel(conversation: conversation, apiClient: api)
        let initial = makeStatus(
            id: "m1",
            createdAt: Date(timeIntervalSince1970: 100),
            content: "initial",
            account: alice
        )
        let updated = makeStatus(
            id: "m1",
            createdAt: Date(timeIntervalSince1970: 100),
            content: "edited",
            account: alice
        )

        viewModel.handleStreamEvent(
            .conversation(conversationId: "c1", unread: true, lastStatus: initial)
        )
        viewModel.handleStreamEvent(
            .conversation(conversationId: "c1", unread: true, lastStatus: updated)
        )

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.id == "m1")
        #expect(viewModel.messages.first?.content == "edited")
    }

    @Test @MainActor func conversationDetailDeleteEventRemovesMessageAndUpdatesLastStatus()
        async throws
    {
        let api = MockMastodonAPI()
        let me = makeAccount(id: "me")
        let alice = makeAccount(id: "alice")
        let conversation = Conversation(
            id: "c1",
            unread: false,
            accounts: [me, alice],
            lastStatus: nil
        )
        let viewModel = ConversationDetailViewModel(conversation: conversation, apiClient: api)
        let first = makeStatus(
            id: "m1",
            createdAt: Date(timeIntervalSince1970: 100),
            account: alice
        )
        let second = makeStatus(
            id: "m2",
            createdAt: Date(timeIntervalSince1970: 200),
            account: alice
        )

        viewModel.handleStreamEvent(
            .conversation(conversationId: "c1", unread: true, lastStatus: first)
        )
        viewModel.handleStreamEvent(
            .conversation(conversationId: "c1", unread: true, lastStatus: second)
        )
        viewModel.handleStreamEvent(.delete(statusId: "m2"))

        #expect(viewModel.messages.count == 1)
        #expect(viewModel.messages.first?.id == "m1")
        #expect(viewModel.conversation.lastStatus?.id == "m1")
    }

    @Test @MainActor func conversationDetailSendFailureRetainsDraftAndRetrySucceeds() async throws {
        let api = MockMastodonAPI()
        let me = makeAccount(id: "me")
        let alice = makeAccount(id: "alice")
        let conversation = Conversation(
            id: "c1",
            unread: false,
            accounts: [me, alice],
            lastStatus: makeStatus(id: "existing", account: alice)
        )
        let viewModel = ConversationDetailViewModel(conversation: conversation, apiClient: api)
        let posted = makeStatus(
            id: "posted",
            createdAt: Date(timeIntervalSince1970: 300),
            account: alice
        )
        var capturedText: String?
        api.postStatusHandler = { text, _, _, _, _, _, _, _, _ in
            capturedText = text
            throw MockMastodonAPI.MockError.forcedFailure
        }

        viewModel.draftMessage = "hello retry"
        let initialSend = await viewModel.sendMessage(currentUserID: me.id)

        #expect(initialSend == false)
        #expect(viewModel.draftMessage == "hello retry")
        #expect(viewModel.sendErrorMessage != nil)
        #expect(viewModel.lastFailedDraft == "hello retry")
        #expect(viewModel.canRetryLastFailedSend == true)

        api.postStatusHandler = { text, _, _, _, _, _, _, _, _ in
            capturedText = text
            return posted
        }
        viewModel.draftMessage = ""
        let retrySend = await viewModel.retryLastFailedSend(currentUserID: me.id)

        #expect(retrySend == true)
        #expect(capturedText?.contains("@\(alice.acct.lowercased())") == true)
        #expect(capturedText?.hasSuffix("hello retry") == true)
        #expect(viewModel.draftMessage.isEmpty)
        #expect(viewModel.sendErrorMessage == nil)
        #expect(viewModel.lastFailedDraft == nil)
        #expect(viewModel.messages.last?.id == "posted")
    }

    @Test @MainActor func composeRemoveMediaUsesStableIdentityAndClearsUploadState() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        let attachments = (1...4).map {
            makeComposeMediaAttachment(id: "media-\($0)", state: .uploaded)
        }

        viewModel.mediaAttachments = attachments
        viewModel.mediaUploadStates = Dictionary(
            uniqueKeysWithValues: attachments.map { ($0.id, .uploaded) }
        )

        #expect(viewModel.removeMedia(id: "media-3"))

        #expect(viewModel.mediaAttachments.map(\.id) == ["media-1", "media-2", "media-4"])
        #expect(viewModel.mediaUploadStates["media-3"] == nil)
        #expect(viewModel.removeMedia(id: "missing") == false)
        #expect(viewModel.mediaAttachments.map(\.id) == ["media-1", "media-2", "media-4"])
    }

    @Test @MainActor func composeViewModelOwnsPreparedMediaUploadLifecycle() async throws {
        let api = MockMastodonAPI()
        var capturedData: Data?
        var capturedMimeType: String?
        api.uploadMediaHandler = { data, mimeType, _ in
            capturedData = data
            capturedMimeType = mimeType
            return Status.Attachment(
                id: "server-media",
                type: "image",
                url: URL(string: "https://example.com/media.jpg")!,
                previewURL: URL(string: "https://example.com/media-preview.jpg")!
            )
        }
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        let sourceData = Data([0x01, 0x02, 0x03])
        let prepared = ComposeMediaProcessor.PreparedMedia(
            uploadData: sourceData,
            uploadMimeType: "image/jpeg",
            mediaType: "image",
            previewImage: nil
        )

        let outcome = await viewModel.importPreparedMedia(prepared)

        #expect(outcome == .uploaded)
        #expect(capturedData == sourceData)
        #expect(capturedMimeType == "image/jpeg")
        #expect(viewModel.mediaAttachments.map(\.id) == ["server-media"])
        #expect(viewModel.mediaAttachments.first?.uploadState.isUploaded == true)
        #expect(viewModel.mediaAttachments.first?.sourceUploadData == nil)
        #expect(viewModel.mediaUploadStates["server-media"]?.isUploaded == true)
    }

    @Test @MainActor func composePhotoReservationsCapAndCreateImmediatePlaceholders() throws {
        let viewModel = ComposeViewModel(
            context: .newPost,
            apiClient: MockMastodonAPI()
        )
        let existing = [
            makeComposeMediaAttachment(id: "existing-1", state: .uploaded),
            makeComposeMediaAttachment(id: "existing-2", state: .uploaded),
        ]
        viewModel.mediaAttachments = existing
        viewModel.mediaUploadStates = Dictionary(
            uniqueKeysWithValues: existing.map { ($0.id, .uploaded) }
        )

        let reservationIDs = viewModel.reservePhotoImports(count: 4)

        #expect(reservationIDs.count == 2)
        #expect(
            viewModel.mediaAttachments.map(\.id)
                == ["existing-1", "existing-2"] + reservationIDs
        )
        for reservationID in reservationIDs {
            let attachment = try #require(viewModel.mediaAttachment(id: reservationID))
            #expect(attachment.url.scheme == "temp")
            #expect(attachment.previewImage == nil)
            if case .uploading(let progress) = attachment.uploadState {
                #expect(progress == 0)
            } else {
                Issue.record("Photo reservation must begin as an uploading placeholder")
            }
            if case .uploading(let progress) = viewModel.mediaUploadStates[reservationID] {
                #expect(progress == 0)
            } else {
                Issue.record("Photo reservation must publish immediate upload state")
            }
        }

        let cancelledID = try #require(reservationIDs.first)
        viewModel.cancelPhotoImportReservation(id: cancelledID)
        #expect(viewModel.mediaAttachment(id: cancelledID) == nil)
        #expect(viewModel.mediaUploadStates[cancelledID] == nil)
    }

    @Test @MainActor func composeReservedPhotoUploadsPreservePickerOrderWhenFinishingOutOfOrder()
        async throws
    {
        let api = MockMastodonAPI()
        api.uploadMediaHandler = { data, _, _ in
            let marker = try #require(data.first)
            let delay: UInt64 = switch marker {
            case 1: 120_000_000
            case 2: 60_000_000
            default: 10_000_000
            }
            try await Task.sleep(nanoseconds: delay)
            return Status.Attachment(
                id: "server-\(marker)",
                type: "image",
                url: URL(string: "https://example.test/server-\(marker).png")!
            )
        }
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        let reservationIDs = viewModel.reservePhotoImports(count: 3)
        let preparedMedia = (1...3).map { marker in
            ComposeMediaProcessor.PreparedMedia(
                uploadData: Data([UInt8(marker)]),
                uploadMimeType: "image/png",
                mediaType: "image",
                previewImage: nil
            )
        }

        async let first = viewModel.importPreparedMedia(
            preparedMedia[0], reservationID: reservationIDs[0]
        )
        async let second = viewModel.importPreparedMedia(
            preparedMedia[1], reservationID: reservationIDs[1]
        )
        async let third = viewModel.importPreparedMedia(
            preparedMedia[2], reservationID: reservationIDs[2]
        )
        let outcomes = await [first, second, third]

        #expect(outcomes.allSatisfy { $0 == .uploaded })
        #expect(viewModel.mediaAttachments.map(\.id) == ["server-1", "server-2", "server-3"])
    }

    @Test @MainActor func composePhotoReservationCleansDecodeFailureAndRetainsUploadFailure()
        async throws
    {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        let decodeReservation = try #require(viewModel.reservePhotoImports(count: 1).first)

        let decodeOutcome = await viewModel.importPhotoData(
            Data("not-an-image".utf8),
            reservationID: decodeReservation
        )

        #expect(decodeOutcome == .failed(.imageProcessing))
        #expect(viewModel.mediaAttachment(id: decodeReservation) == nil)
        #expect(viewModel.mediaUploadStates[decodeReservation] == nil)

        api.uploadMediaHandler = { _, _, _ in
            throw MockMastodonAPI.MockError.forcedFailure
        }
        let uploadReservation = try #require(viewModel.reservePhotoImports(count: 1).first)
        let sourceData = Data([0x01, 0x02, 0x03])
        let uploadOutcome = await viewModel.importPreparedMedia(
            ComposeMediaProcessor.PreparedMedia(
                uploadData: sourceData,
                uploadMimeType: "image/png",
                mediaType: "image",
                previewImage: nil
            ),
            reservationID: uploadReservation
        )

        #expect(uploadOutcome == .failed(.upload))
        let failedAttachment = try #require(
            viewModel.mediaAttachment(id: uploadReservation)
        )
        #expect(failedAttachment.sourceUploadData == sourceData)
        if case .failed = failedAttachment.uploadState {
            // Expected: the user can retry this reserved upload.
        } else {
            Issue.record("Upload failure must retain a retryable failed attachment")
        }
        if case .failed = viewModel.mediaUploadStates[uploadReservation] {
            // Expected: the media grid observes the failed state.
        } else {
            Issue.record("Upload failure must retain its published failed state")
        }
    }

    @Test @MainActor func composeMediaDeletionSupportsEveryFourAttachmentOrder() throws {
        func permutations(_ values: [String]) -> [[String]] {
            guard values.count > 1 else { return [values] }
            return values.indices.flatMap { index in
                var remaining = values
                let selected = remaining.remove(at: index)
                return permutations(remaining).map { [selected] + $0 }
            }
        }

        let attachmentIDs = ["media-1", "media-2", "media-3", "media-4"]
        let removalOrders = permutations(attachmentIDs)
        #expect(removalOrders.count == 24)

        for removalOrder in removalOrders {
            let viewModel = ComposeViewModel(
                context: .newPost,
                apiClient: MockMastodonAPI()
            )
            let attachments = attachmentIDs.map {
                makeComposeMediaAttachment(id: $0, state: .uploaded)
            }
            viewModel.mediaAttachments = attachments
            viewModel.mediaUploadStates = Dictionary(
                uniqueKeysWithValues: attachments.map { ($0.id, .uploaded) }
            )

            for attachmentID in removalOrder {
                #expect(viewModel.removeMedia(id: attachmentID))
                #expect(viewModel.mediaAttachment(id: attachmentID) == nil)
                #expect(viewModel.mediaUploadStates[attachmentID] == nil)
                #expect(
                    viewModel.makeDraft(category: .manual).payload.mediaAttachments.map(\.id)
                        == viewModel.mediaAttachments.map(\.id)
                )
            }

            #expect(viewModel.mediaAttachments.isEmpty)
            #expect(viewModel.mediaUploadStates.isEmpty)
        }
    }

    @Test @MainActor func composeAltTextUpdateFollowsAttachmentIdentityAfterDeletion() throws {
        let viewModel = ComposeViewModel(
            context: .newPost,
            apiClient: MockMastodonAPI()
        )
        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "media-1", state: .uploaded),
            makeComposeMediaAttachment(id: "media-2", state: .uploaded),
            makeComposeMediaAttachment(id: "media-3", state: .uploaded),
        ]

        #expect(viewModel.removeMedia(id: "media-1"))
        #expect(viewModel.updateMediaAltText(id: "media-3", altText: "third image"))
        #expect(viewModel.mediaAttachment(id: "media-2")?.description == nil)
        #expect(viewModel.mediaAttachment(id: "media-3")?.description == "third image")
        #expect(viewModel.updateMediaAltText(id: "media-1", altText: "missing") == false)
    }

    @Test @MainActor func composeRemovingInFlightMediaDoesNotResurrectAttachment() async throws {
        let api = MockMastodonAPI()
        api.uploadMediaHandler = { _, _, _ in
            try await Task.sleep(nanoseconds: 120_000_000)
            return Status.Attachment(
                id: "server-media",
                type: "image",
                url: URL(string: "https://example.com/server-media.png")!,
                previewURL: URL(string: "https://example.com/server-media-preview.png")!
            )
        }
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        let prepared = ComposeMediaProcessor.PreparedMedia(
            uploadData: tinyPNGData(),
            uploadMimeType: "image/png",
            mediaType: "image",
            previewImage: nil
        )

        let uploadTask = Task { @MainActor in
            await viewModel.importPreparedMedia(prepared)
        }
        await waitUntil(timeout: 1) { !viewModel.mediaAttachments.isEmpty }
        let temporaryID = try #require(viewModel.mediaAttachments.first?.id)

        #expect(viewModel.removeMedia(id: temporaryID))
        let outcome = await uploadTask.value

        #expect(outcome == .cancelled)
        #expect(viewModel.mediaAttachments.isEmpty)
        #expect(viewModel.mediaUploadStates.isEmpty)
    }

    @Test @MainActor func composeCanPublishRequiresStableMediaUploadState() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        viewModel.content = "hello"

        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "uploading", state: .uploading(progress: 0.4))
        ]
        #expect(viewModel.canPublish == false)

        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "failed", state: .failed(error: nil))
        ]
        #expect(viewModel.canPublish == false)

        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "uploaded", state: .uploaded)
        ]
        #expect(viewModel.canPublish)
    }

    @Test @MainActor func composePublishBlockerReflectsMediaAndContentState() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)

        #expect(viewModel.publishBlocker == .emptyContent)
        #expect(viewModel.publishDisabledReason == nil)

        viewModel.content = "hello"
        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "uploading", state: .uploading(progress: 0.1))
        ]
        #expect(viewModel.publishBlocker == .mediaUploading)
        #expect(viewModel.publishDisabledReason == MoroL10n.Compose.validationMediaUploading)

        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "failed", state: .failed(error: nil))
        ]
        #expect(viewModel.publishBlocker == .mediaUploadFailed)
        #expect(viewModel.publishDisabledReason == MoroL10n.Compose.validationMediaUploadFailed)
    }

    @Test @MainActor func composePublishAllowsMediaOnlyStatus() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        var capturedText: String?
        var capturedMediaIDs: [String]?

        api.postStatusHandler = { text, _, mediaIDs, _, _, _, _, _, _ in
            capturedText = text
            capturedMediaIDs = mediaIDs
            return self.makeStatus(id: "media-only-posted")
        }

        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(
                id: "uploaded-media",
                url: URL(string: "https://example.com/media.png")!,
                state: .uploaded
            )
        ]

        #expect(viewModel.publishBlocker == nil)
        #expect(viewModel.canPublish)

        _ = try await viewModel.publish()

        #expect(capturedText == "")
        #expect(capturedMediaIDs == ["uploaded-media"])
    }

    @Test @MainActor func composeOriginalPostSummaryPrefersSpoilerTextAndBuildsBadges() async throws {
        let quoted = makeStatus(id: "quoted-context")
        let status = makeStatus(
            id: "reply-context",
            content: "<p>正文内容</p>",
            mediaAttachments: [
                Status.Attachment(
                    id: "att-1",
                    type: "image",
                    url: URL(string: "https://example.com/image.png")!,
                    previewURL: nil,
                    description: nil,
                    blurhash: nil,
                    meta: nil
                )
            ],
            quote: Status.Quote(state: .accepted, quotedStatus: quoted),
            spoilerText: "CW 摘要"
        )

        let summary = ComposeOriginalPostSummary(
            status: status,
            presentationStyle: .reply
        )

        #expect(summary.previewText == "CW 摘要")
        #expect(
            summary.badges.map { $0.text } == [
                MoroL10n.ComposeOriginal.badgeCW,
                MoroL10n.ComposeOriginal.badgeMediaSingular,
                MoroL10n.ComposeOriginal.badgeQuote,
            ])
        #expect(summary.contextLabel == MoroL10n.ComposeOriginal.replyTo("@user_acct-reply-context@example.com"))
    }

    @Test @MainActor func composeOriginalPostSummaryFallsBackToMetadataWhenBodyEmpty() async throws {
        let poll = Status.Poll(
            id: "poll",
            expiresAt: nil,
            expired: false,
            multiple: false,
            votesCount: 0,
            votersCount: nil,
            options: [
                Status.Poll.PollOption(title: "A", votesCount: nil),
                Status.Poll.PollOption(title: "B", votesCount: nil)
            ],
            voted: nil,
            ownVotes: nil
        )
        let status = makeStatus(
            id: "poll-context",
            content: "<p><br></p>",
            poll: poll
        )

        let summary = ComposeOriginalPostSummary(
            status: status,
            presentationStyle: .quote
        )

        #expect(summary.previewText == MoroL10n.ComposeOriginal.badgePoll)
        #expect(summary.badges.map { $0.text } == [MoroL10n.ComposeOriginal.badgePoll])
        #expect(summary.contextLabel == MoroL10n.ComposeOriginal.quoting("@user_acct-poll-context@example.com"))
    }

    @Test @MainActor func composePublishFiltersOutTemporaryMediaIDs() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        var capturedMediaIDs: [String]?

        api.postStatusHandler = { _, _, mediaIDs, _, _, _, _, _, _ in
            capturedMediaIDs = mediaIDs
            return self.makeStatus(id: "posted")
        }

        viewModel.content = "hello"
        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(
                id: "uploaded-real",
                url: URL(string: "https://example.com/media.png")!,
                state: .uploaded
            ),
            makeComposeMediaAttachment(
                id: "temp-upload",
                url: URL(string: "temp://temp-upload")!,
                state: .uploaded
            )
        ]

        _ = try await viewModel.publish()

        #expect(capturedMediaIDs == ["uploaded-real"])
    }

    @Test @MainActor func composePublishRejectsFailedOrUploadingMedia() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        viewModel.content = "hello"

        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "failed", state: .failed(error: nil))
        ]

        do {
            _ = try await viewModel.publish()
            Issue.record("Expected uploadFailed error when failed media exists")
        } catch let error as ComposeError {
            guard case .uploadFailed = error else {
                Issue.record("Unexpected error: \(error.localizedDescription)")
                return
            }
        }

        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "uploading", state: .uploading(progress: 0.2))
        ]

        do {
            _ = try await viewModel.publish()
            Issue.record("Expected mediaUploading error when media is uploading")
        } catch let error as ComposeError {
            guard case .mediaUploading = error else {
                Issue.record("Unexpected error: \(error.localizedDescription)")
                return
            }
        }
    }

    @Test @MainActor func composePublishAllowsPollOnlyAndSendsPollPayload() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        var capturedPoll: StatusPollPayload?
        var capturedText: String?
        var capturedMediaIDs: [String]?

        api.postStatusHandler = { text, _, mediaIDs, _, _, _, _, _, poll in
            capturedText = text
            capturedMediaIDs = mediaIDs
            capturedPoll = poll
            return self.makeStatus(id: "poll-posted")
        }

        viewModel.content = ""
        viewModel.isPollActive = true
        viewModel.pollOptions = [" 选项A ", "选项B", "   "]
        viewModel.pollMultiple = true
        viewModel.pollExpiresIn = 3600

        #expect(viewModel.canPublish)
        _ = try await viewModel.publish()

        #expect(capturedText == "")
        #expect(capturedMediaIDs == nil)
        #expect(capturedPoll?.options == ["选项A", "选项B"])
        #expect(capturedPoll?.multiple == true)
        #expect(capturedPoll?.expiresIn == 3600)
    }

    @Test @MainActor func composePublishUsesExplicitSelectedLanguage() async throws {
        let settings = AppSettings.shared
        let previousDefaultLanguage = settings.defaultPostLanguage
        let previousRecentLanguages = settings.recentPostLanguageCodes
        defer {
            settings.defaultPostLanguage = previousDefaultLanguage
            settings.recentPostLanguageCodes = previousRecentLanguages
        }
        settings.defaultPostLanguage = "en"
        settings.recentPostLanguageCodes = []

        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        var capturedLanguage: String?

        api.postStatusHandler = { _, _, _, _, _, _, _, language, _ in
            capturedLanguage = language
            return self.makeStatus(id: "language-posted")
        }

        viewModel.content = "hello"
        viewModel.selectedLanguageCode = "ja"

        _ = try await viewModel.publish()

        #expect(capturedLanguage == "ja")
        #expect(settings.recentPostLanguageCodes == ["ja"])
    }

    @Test @MainActor func composePublishFallsBackToDefaultPostLanguage() async throws {
        let settings = AppSettings.shared
        let previousDefaultLanguage = settings.defaultPostLanguage
        let previousRecentLanguages = settings.recentPostLanguageCodes
        defer {
            settings.defaultPostLanguage = previousDefaultLanguage
            settings.recentPostLanguageCodes = previousRecentLanguages
        }
        settings.defaultPostLanguage = "fr"
        settings.recentPostLanguageCodes = []

        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        var capturedLanguage: String?

        api.postStatusHandler = { _, _, _, _, _, _, _, language, _ in
            capturedLanguage = language
            return self.makeStatus(id: "default-language-posted")
        }

        viewModel.content = "bonjour"
        viewModel.selectedLanguageCode = ""

        _ = try await viewModel.publish()

        #expect(capturedLanguage == "fr")
        #expect(settings.recentPostLanguageCodes == ["fr"])
    }

    @Test @MainActor func localizationPackageResolvesStringsFromModuleBundle() async throws {
        #expect(MoroL10n.Navigation.home != "nav.tab.home")
        #expect(MoroL10n.Common.close != "common.close")
        #expect(MoroL10n.AccountMgmt.deleteAccount != "accountMgmt.deleteAccount")
        #expect(MoroL10n.AccountMgmt.deleteSectionTitle != "accountMgmt.deleteSectionTitle")
        #expect(MoroL10n.AccountMgmt.deleteFooter("m.somincola.org").contains("m.somincola.org"))
        #expect(MoroL10n.Settings.appSection != "settings.section.app")
        #expect(MoroL10n.Settings.switchAccount != "settings.row.switchAccount")
        #expect(MoroL10n.Settings.aboutSection != "settings.section.about")
        #expect(MoroL10n.Settings.thisServer != "settings.row.thisServer")
        #expect(MoroL10n.Settings.aboutMoro != "settings.row.aboutMoro")
    }

    @Test @MainActor func localizationPackageFollowsPreferredLocalization() async throws {
        // Strings resolve through the standard bundle lookup, following the
        // runner's preferred localization rather than a hardcoded language.
        #expect(MoroL10n.GeneralSettings.title != "general.title")
        #expect(MoroL10n.Compose.navigationNewPost != "compose.navigation.newPost")
        #expect(MoroL10n.Compose.navigationReply != "compose.navigation.reply")
        #expect(MoroL10n.Compose.navigationQuote != "compose.navigation.quote")
        #expect(MoroL10n.Compose.navigationEdit != "compose.navigation.edit")
        let summary = PostLanguageCatalog.selectionSummary(
            for: "",
            defaultBehavior: .appDefault(defaultLanguageCode: "zh-Hans")
        )
        #expect(summary == MoroL10n.Language.followAppDefault(
            PostLanguageCatalog.displayName(for: "zh-Hans")))
        #expect(!PostLanguageCatalog.displayName(for: "zh-Hans").isEmpty)
        #expect(MoroL10n.Navigation.notificationsUnread(3) != "nav.tab.notifications.unread")
        #expect(MoroL10n.Navigation.messagesUnread(2) != "nav.tab.messages.unread")
    }

    @Test @MainActor func notificationUnreadStoreDeduplicatesPushAndSuppressesVisibleBanner() async throws {
        let suiteName = "NotificationUnreadStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let badgeRecorder = BadgeValueRecorder()
        let streamEvents = PassthroughSubject<StreamEvent, Never>()
        let api = MockMastodonAPI()
        api.fetchUnreadNotificationCountHandler = { 0 }
        let store = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: streamEvents.eraseToAnyPublisher(),
            badgeSetter: { count in await badgeRecorder.set(count) }
        )

        await store.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )
        store.setNotificationListVisible(true)
        let payload: [AnyHashable: Any] = [
            "x": "session-a",
            "notification_id": "notification-1",
        ]

        let firstShouldPresent = await store.receiveRemoteNotification(userInfo: payload)
        let duplicateShouldPresent = await store.receiveRemoteNotification(userInfo: payload)
        await Task.yield()

        #expect(firstShouldPresent == false)
        #expect(duplicateShouldPresent == false)
        #expect(store.activeUnreadCount == 1)
        #expect(store.unreadCount(for: "session-a") == 1)
        #expect(badgeRecorder.values.last == 1)
    }

    @Test @MainActor func notificationUnreadStoreMarksReadOnlyAfterServerMarkerSucceeds() async throws {
        let suiteName = "NotificationUnreadStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let api = MockMastodonAPI()
        api.fetchUnreadNotificationCountHandler = { 4 }
        var savedNotificationID: String?
        var shouldFailMarkerSave = true
        api.saveMarkerHandler = { _, notifications in
            if shouldFailMarkerSave {
                throw MockMastodonAPI.MockError.forcedFailure
            }
            savedNotificationID = notifications
            return Marker()
        }
        let store = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(),
            badgeSetter: { _ in }
        )

        await store.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )
        #expect(store.activeUnreadCount == 4)

        await store.markActiveNotificationsRead(through: "notification-4")
        #expect(store.activeUnreadCount == 4)

        shouldFailMarkerSave = false
        await store.markActiveNotificationsRead(through: "notification-4")

        #expect(savedNotificationID == "notification-4")
        #expect(store.activeUnreadCount == 0)
    }

    @Test @MainActor func notificationUnreadStoreAdoptsServiceExtensionCountWithoutDoubleCounting() async throws {
        let suiteName = "NotificationUnreadStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ["session-a": 1],
            forKey: "notification_unread_counts_by_session_v1"
        )
        defaults.set(
            ["session-a": ["notification-1"]],
            forKey: "notification_unread_recent_ids_by_session_v1"
        )
        let api = MockMastodonAPI()
        api.fetchUnreadNotificationCountHandler = { 1 }
        let store = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(),
            badgeSetter: { _ in }
        )

        await store.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )
        _ = await store.receiveRemoteNotification(
            userInfo: [
                "x": "session-a",
                "notification_id": "notification-1",
            ]
        )

        #expect(store.activeUnreadCount == 1)
    }

    @Test @MainActor func notificationUnreadStoreFallsBackToMarkersOnOlderServers() async throws {
        let suiteName = "NotificationUnreadStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let api = MockMastodonAPI()
        api.fetchUnreadNotificationCountHandler = {
            throw APIError.http(statusCode: 404, data: nil)
        }
        api.fetchMarkersHandler = { _ in
            Marker(
                notifications: MarkerContent(
                    lastReadId: "100",
                    updatedAt: Date(),
                    version: 1
                )
            )
        }
        api.fetchNotificationsHandler = { maxID, sinceID, limit, _ in
            #expect(maxID == nil)
            #expect(sinceID == "100")
            #expect(limit == 80)
            return [
                self.makeNotification(id: "102", type: "follow"),
                self.makeNotification(id: "101", type: "favourite"),
            ]
        }
        let store = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(),
            badgeSetter: { _ in }
        )

        await store.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )

        #expect(store.activeUnreadCount == 2)
    }

    @Test @MainActor func inboxBadgeExcludesRetainedConversationUnreadAndDeduplicatesMessageEvents() async throws {
        let suiteName = "InboxUnreadStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let badgeRecorder = BadgeValueRecorder()
        let streamEvents = PassthroughSubject<StreamEvent, Never>()
        let api = MockMastodonAPI()
        api.fetchUnreadNotificationCountHandler = { 0 }
        api.fetchConversationsHandler = { _, _, _ in
            [
                self.makeConversation(id: "message-1", unread: true, lastStatus: nil),
                self.makeConversation(id: "message-2", unread: true, lastStatus: nil),
                self.makeConversation(id: "message-3", unread: false, lastStatus: nil),
            ]
        }
        let notificationStore = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(),
            badgeSetter: { count in await badgeRecorder.set(count) }
        )
        let inboxStore = InboxUnreadStore(
            notificationUnreadStore: notificationStore,
            userDefaults: defaults,
            streamEvents: streamEvents.eraseToAnyPublisher()
        )

        await notificationStore.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )
        await inboxStore.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )
        notificationStore.recordIncomingNotification(
            sessionID: "session-a",
            notificationID: "notification-1"
        )
        await waitUntil(timeout: 1) {
            inboxStore.notificationUnreadCount == 1 && badgeRecorder.values.last == 1
        }

        #expect(inboxStore.messageUnreadCount == 2)
        #expect(inboxStore.totalUnreadCount == 1)
        #expect(badgeRecorder.values.last == 1)

        streamEvents.send(
            .conversation(conversationId: "message-4", unread: true, lastStatus: nil)
        )
        streamEvents.send(
            .conversation(conversationId: "message-4", unread: true, lastStatus: nil)
        )
        await waitUntil(timeout: 1) { inboxStore.messageUnreadCount == 3 }
        #expect(inboxStore.totalUnreadCount == 1)

        streamEvents.send(
            .conversation(conversationId: "message-4", unread: false, lastStatus: nil)
        )
        await waitUntil(timeout: 1) { inboxStore.messageUnreadCount == 2 }
        inboxStore.markConversationRead(id: "message-1")

        #expect(inboxStore.messageUnreadCount == 1)
        #expect(inboxStore.totalUnreadCount == 1)
    }

    @Test @MainActor func inboxUnreadReconciliationTraversesOpaqueConversationCursors() async throws {
        let suiteName = "InboxUnreadStorePaginationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            ["session-a": ["stale-conversation"]],
            forKey: InboxUnreadPersistenceKeys.directMessageUnreadConversationIDsBySession
        )
        let api = MockMastodonAPI()
        var requestedCursors: [String?] = []
        api.fetchConversationsPageHandler = { maxID, limit in
            requestedCursors.append(maxID)
            #expect(limit == 40)
            if maxID == nil {
                return ConversationsPage(
                    conversations: [
                        self.makeConversation(id: "visible-read", unread: false, lastStatus: nil)
                    ],
                    nextMaxID: "opaque:older"
                )
            }
            #expect(maxID == "opaque:older")
            return ConversationsPage(
                conversations: [
                    self.makeConversation(id: "older-unread", unread: true, lastStatus: nil)
                ],
                nextMaxID: nil
            )
        }
        let notificationStore = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(),
            badgeSetter: { _ in }
        )
        let inboxStore = InboxUnreadStore(
            notificationUnreadStore: notificationStore,
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher()
        )

        await inboxStore.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )

        #expect(requestedCursors.count == 2)
        #expect(requestedCursors[0] == nil)
        #expect(requestedCursors[1] == "opaque:older")
        #expect(inboxStore.messageUnreadCount == 1)
    }

    @Test @MainActor func notificationOpenResolvesDirectMentionToConversation() async throws {
        let suiteName = "InboxUnreadStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sender = makeAccount(id: "sender")
        let status = makeStatus(
            id: "direct-status",
            account: sender,
            visibility: "direct"
        )
        let conversation = makeConversation(
            id: "conversation-1",
            unread: true,
            accounts: [sender],
            lastStatus: status
        )
        let api = MockMastodonAPI()
        api.fetchConversationsHandler = { _, _, _ in [conversation] }
        api.fetchNotificationHandler = { id in
            #expect(id == "notification-1")
            return self.makeNotification(id: id, type: "mention", account: sender, status: status)
        }
        let notificationStore = NotificationUnreadStore(
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher(),
            badgeSetter: { _ in }
        )
        let inboxStore = InboxUnreadStore(
            notificationUnreadStore: notificationStore,
            userDefaults: defaults,
            streamEvents: Empty<StreamEvent, Never>().eraseToAnyPublisher()
        )

        await inboxStore.activate(
            sessionID: "session-a",
            availableSessionIDs: ["session-a"],
            apiClient: api
        )
        await notificationStore.handleNotificationResponse(
            userInfo: [
                "x": "session-a",
                "notification_id": "notification-1",
                "notification_type": "mention",
            ]
        )
        let request = try #require(notificationStore.pendingOpenRequest)
        let resolved = await PushNotificationResolver.resolve(request.payload, apiClient: api)

        #expect(request.sessionID == "session-a")
        #expect(request.payload.notificationType == "mention")
        guard case .conversation(let resolvedConversation) = resolved else {
            Issue.record("Expected the exact direct-message conversation")
            return
        }
        #expect(resolvedConversation.id == "conversation-1")
    }

    @Test @MainActor func statusTranslationViewModelUsesRemoteProvider() async throws {
        let api = MockMastodonAPI()
        let languagesStore = TranslationLanguagesStore()
        let viewModel = StatusTranslationViewModel(translationLanguagesStore: languagesStore)
        let status = makeStatus(
            id: "status-translate",
            content: "<p>こんにちは、世界</p>",
            language: "ja"
        )

        api.translateStatusHandler = { id, targetLanguage in
            #expect(id == "status-translate")
            #expect(targetLanguage == "en")
            return StatusTranslationPayload(
                content: "<p>Hello, world</p>",
                detectedSourceLanguage: "ja",
                provider: "DeepL",
                spoilerText: nil
            )
        }

        await languagesStore.loadIfNeeded(apiClient: api)
        viewModel.configure(
            status: status,
            apiClient: api,
            mode: .remote,
            targetLanguageCode: "en"
        )
        #expect(viewModel.canOfferTranslation)

        await viewModel.translate()

        #expect(viewModel.translatedResult?.translatedText == "<p>Hello, world</p>")
        #expect(viewModel.translatedResult?.provider == .remote)
        #expect(viewModel.translatedResult?.providerName == "DeepL")
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.translationSummary.contains("DeepL"))
        #expect(viewModel.canOfferTranslation)
        #expect(viewModel.isTranslated)
    }

    @Test @MainActor func statusTranslationViewModelHidesActionForSameLanguage() async throws {
        let api = MockMastodonAPI()
        let viewModel = StatusTranslationViewModel()
        let status = makeStatus(
            id: "status-same-language",
            content: "<p>Hello again</p>",
            language: "en-US"
        )

        viewModel.configure(
            status: status,
            apiClient: api,
            mode: .remote,
            targetLanguageCode: "en"
        )

        #expect(viewModel.canOfferTranslation == false)
        #expect(viewModel.availabilityReason == MoroL10n.Translation.sameLanguage)
    }

    @Test @MainActor func statusTranslationViewModelMapsInstanceUnavailableFailure() async throws {
        let api = MockMastodonAPI()
        let languagesStore = TranslationLanguagesStore()
        let viewModel = StatusTranslationViewModel(translationLanguagesStore: languagesStore)
        let status = makeStatus(
            id: "status-instance-unavailable",
            content: "<p>Bonjour</p>",
            language: "fr"
        )

        api.translateStatusHandler = { _, _ in
            throw APIError.http(statusCode: 404, data: nil)
        }

        await languagesStore.loadIfNeeded(apiClient: api)
        viewModel.configure(
            status: status,
            apiClient: api,
            mode: .remote,
            targetLanguageCode: "en"
        )

        await viewModel.translate()

        #expect(viewModel.translatedResult == nil)
        #expect(viewModel.errorMessage == MoroL10n.Translation.unavailableOnInstance)
    }

    @Test @MainActor func composeInitialPayloadAppliesTransientState() async throws {
        let api = MockMastodonAPI()
        let replyTarget = makeStatus(id: "reply-target")
        let manualDraft = ComposeDraft(
            id: UUID().uuidString,
            accountID: "me",
            category: .manual,
            target: ComposeDraftTarget(
                kind: .reply,
                referenceStatus: replyTarget.displayStatus,
                inReplyToID: replyTarget.displayStatus.id
            ),
            payload: ComposeDraftPayload(
                content: "@reply-target hello",
                contentWarning: "cw",
                isContentWarningActive: true,
                visibility: .followers,
                mediaAttachments: [],
                isPollActive: true,
                pollOptions: ["A", "B"],
                pollMultiple: true,
                pollExpiresIn: 86400,
                isSchedulingEnabled: true,
                scheduledAt: Date().addingTimeInterval(3600),
                selectedLanguageCode: "fr",
                quotePolicyRawValue: ComposeViewModel.QuotePolicy.followers.rawValue
            ),
            createdAt: Date(),
            updatedAt: Date()
        )

        let restoredViewModel = ComposeViewModel(
            context: manualDraft.target.composeContext,
            apiClient: api,
            currentUserID: "me",
            initialDraft: manualDraft
        )

        #expect(restoredViewModel.content == "@reply-target hello")
        #expect(restoredViewModel.contentWarning == "cw")
        #expect(restoredViewModel.isContentWarningActive == true)
        #expect(restoredViewModel.visibility == .followers)
        #expect(restoredViewModel.quotePolicy == .followers)
        #expect(restoredViewModel.isPollActive == true)
        #expect(restoredViewModel.pollOptions == ["A", "B"])
        #expect(restoredViewModel.pollMultiple == true)
        #expect(restoredViewModel.selectedLanguageCode == "fr")
        #expect(restoredViewModel.isSchedulingEnabled == false)
        #expect(restoredViewModel.scheduledPublishDate == nil)
    }

    @Test @MainActor func composeDraftableContentIgnoresBlankNewPostText() async throws {
        let viewModel = ComposeViewModel(
            context: .newPost,
            apiClient: MockMastodonAPI(),
            currentUserID: "me"
        )

        viewModel.content = " \n\t "
        #expect(viewModel.hasDraftableContent == false)

        viewModel.content = "\n  hello  "
        #expect(viewModel.hasDraftableContent == true)
    }

    @Test @MainActor func composeDraftableContentIgnoresReplyMentionOnlyText() async throws {
        let alice = makeAccount(id: "alice", username: "alice")
        let bobMention = Status.Mention(
            id: "bob",
            username: "bob",
            url: URL(string: "https://example.com/@bob")!,
            acct: "bob@example.com"
        )
        let replyTarget = makeStatus(
            id: "reply-target",
            account: alice,
            mentions: [bobMention]
        )
        let viewModel = ComposeViewModel(
            context: .reply(to: replyTarget),
            apiClient: MockMastodonAPI(),
            currentUserID: "me"
        )

        #expect(viewModel.content == "@alice@example.com @bob@example.com ")
        #expect(viewModel.hasDraftableContent == false)

        viewModel.content = "@alice@example.com \n @bob@example.com"
        #expect(viewModel.hasDraftableContent == false)

        viewModel.content = "@alice@example.com thanks"
        #expect(viewModel.hasDraftableContent == true)
    }

    @Test func composeDraftPayloadDecodesOlderSchemaWithSafeDefaults() throws {
        let legacyPayload = Data(#"{"content":"legacy draft"}"#.utf8)

        let payload = try JSONDecoder().decode(ComposeDraftPayload.self, from: legacyPayload)

        #expect(payload.content == "legacy draft")
        #expect(payload.visibility == .public)
        #expect(payload.mediaAttachments.isEmpty)
        #expect(payload.pollOptions == ["", ""])
        #expect(payload.isSchedulingEnabled == false)
        #expect(payload.scheduledAt == nil)
        #expect(payload.selectedLanguageCode.isEmpty)
        #expect(payload.quotePolicyRawValue == ComposeViewModel.QuotePolicy.anyone.rawValue)
    }

    @Test @MainActor func composeRestoredManualDraftKeepsIdentityAcrossAutosave() throws {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = ComposeDraft(
            id: "manual-draft",
            accountID: "me",
            category: .manual,
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "before"),
            createdAt: createdAt,
            updatedAt: createdAt
        )
        let viewModel = ComposeViewModel(
            context: .newPost,
            apiClient: MockMastodonAPI(),
            currentUserID: "me",
            initialDraft: original
        )
        viewModel.content = "after"

        let updated = viewModel.makeDraft(category: .auto)

        #expect(updated.id == original.id)
        #expect(updated.createdAt == original.createdAt)
        #expect(updated.category == .manual)
        #expect(updated.payload.content == "after")
    }

    @Test func composeDraftStoreDeduplicatesAutoRecoveryAndPreservesManualDrafts() throws {
        let suiteName = "compose-draft-store-dedup-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = ComposeDraftStore(userDefaults: userDefaults)
        let target = ComposeDraftTarget(kind: .reply, inReplyToID: "status-1")
        let firstDate = Date(timeIntervalSince1970: 100)
        let firstAuto = ComposeDraft(
            id: "auto-1",
            accountID: "me",
            category: .auto,
            target: target,
            payload: makeComposeDraftPayload(content: "first"),
            createdAt: firstDate,
            updatedAt: firstDate
        )
        let secondAuto = ComposeDraft(
            id: "auto-2",
            accountID: "me",
            category: .auto,
            target: target,
            payload: makeComposeDraftPayload(content: "second"),
            createdAt: firstDate.addingTimeInterval(10),
            updatedAt: firstDate.addingTimeInterval(10)
        )
        let manual = ComposeDraft(
            id: "manual-1",
            accountID: "me",
            category: .manual,
            target: target,
            payload: makeComposeDraftPayload(content: "manual"),
            createdAt: firstDate,
            updatedAt: firstDate
        )

        #expect(store.save(firstAuto))
        #expect(store.save(secondAuto))
        #expect(store.save(manual))

        let drafts = store.drafts(for: "me", matching: target)
        #expect(drafts.count == 2)
        #expect(drafts.first?.id == manual.id)
        let auto = try #require(drafts.first(where: { $0.category == .auto }))
        #expect(auto.id == secondAuto.id)
        #expect(auto.createdAt == firstAuto.createdAt)
        #expect(auto.payload.content == "second")
    }

    @Test func composeDraftStoreRecoversValidDraftBesideMalformedEntry() throws {
        let suiteName = "compose-draft-store-recovery-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let validDraft = ComposeDraft(
            id: "recoverable",
            accountID: "me",
            category: .manual,
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "keep me"),
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        var storedData = Data("[".utf8)
        storedData.append(try JSONEncoder().encode(validDraft))
        storedData.append(Data(",{\"invalid\":true}]".utf8))
        userDefaults.set(storedData, forKey: "compose_drafts_v1")

        let store = ComposeDraftStore(userDefaults: userDefaults)
        let recovered = store.drafts(for: "me")

        #expect(recovered.map(\.id) == [validDraft.id])
        #expect(userDefaults.data(forKey: "compose_drafts_v1_corrupt_backup") == storedData)
    }

    @Test @MainActor func sharedComposeDraftStagingStoreStagesAndRemovesAttachments() async throws {
        let suiteName = "shared-compose-draft-staging-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let baseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-draft-staging-\(UUID().uuidString)", isDirectory: true)
        let sourceFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-source-\(UUID().uuidString).txt", isDirectory: false)

        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: baseDirectoryURL)
            try? FileManager.default.removeItem(at: sourceFileURL)
        }

        try Data("hello from share".utf8).write(to: sourceFileURL)

        let stagingStore = SharedComposeDraftStagingStore(
            userDefaults: userDefaults,
            baseDirectoryURL: baseDirectoryURL
        )
        let stagedItem = try stagingStore.stage(
            accountID: "me",
            sourceApplication: "ShareExtension",
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "shared draft"),
            attachments: [
                SharedComposeDraftAttachmentInput(
                    sourceURL: sourceFileURL,
                    fileName: "shared.txt",
                    mimeType: "text/plain"
                )
            ]
        )

        let pendingItem = try #require(stagingStore.nextPendingItem())
        let attachment = try #require(pendingItem.attachments.first)
        let stagedAttachmentURL = stagingStore.attachmentFileURL(for: attachment)

        #expect(stagedItem.id == pendingItem.id)
        #expect(FileManager.default.fileExists(atPath: stagedAttachmentURL.path))

        stagingStore.removeItem(id: stagedItem.id)

        #expect(stagingStore.pendingItems().isEmpty)
        #expect(FileManager.default.fileExists(atPath: stagedAttachmentURL.path) == false)
    }

    @Test @MainActor func sharedComposeStagingAcknowledgesEachImportedAttachment() async throws {
        let suiteName = "shared-compose-progress-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        let baseDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-progress-\(UUID().uuidString)", isDirectory: true)
        let firstSource = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-first-\(UUID().uuidString).txt")
        let secondSource = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-second-\(UUID().uuidString).txt")
        defer {
            userDefaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: baseDirectoryURL)
            try? FileManager.default.removeItem(at: firstSource)
            try? FileManager.default.removeItem(at: secondSource)
        }
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let store = SharedComposeDraftStagingStore(
            userDefaults: userDefaults,
            baseDirectoryURL: baseDirectoryURL
        )
        let staged = try store.stage(
            accountID: "me",
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "shared"),
            attachments: [
                SharedComposeDraftAttachmentInput(
                    sourceURL: firstSource,
                    mimeType: "text/plain",
                    id: "first"
                ),
                SharedComposeDraftAttachmentInput(
                    sourceURL: secondSource,
                    mimeType: "text/plain",
                    id: "second"
                ),
            ]
        )
        let firstReference = try #require(staged.attachments.first(where: { $0.id == "first" }))
        let secondReference = try #require(staged.attachments.first(where: { $0.id == "second" }))
        let firstURL = store.attachmentFileURL(for: firstReference)
        let secondURL = store.attachmentFileURL(for: secondReference)

        #expect(store.acknowledgeImportedAttachment(itemID: staged.id, attachmentID: "first"))
        #expect(store.pendingItems().first?.attachments.map(\.id) == ["second"])
        #expect(FileManager.default.fileExists(atPath: firstURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: secondURL.path))

        #expect(store.acknowledgeImportedAttachment(itemID: staged.id, attachmentID: "second"))
        #expect(store.pendingItems().isEmpty)
        #expect(FileManager.default.fileExists(atPath: secondURL.path) == false)
    }

    @Test @MainActor func sharedComposeImportCoordinatorBuildsTransientComposeStateAndKeepsAttachmentStage() async throws {
        let draftSuiteName = "shared-compose-import-drafts-\(UUID().uuidString)"
        let stagingSuiteName = "shared-compose-import-staging-\(UUID().uuidString)"
        let draftDefaults = try #require(UserDefaults(suiteName: draftSuiteName))
        let stagingDefaults = try #require(UserDefaults(suiteName: stagingSuiteName))
        let stagingDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-import-\(UUID().uuidString)", isDirectory: true)
        let sourceFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-import-\(UUID().uuidString).txt", isDirectory: false)

        defer {
            draftDefaults.removePersistentDomain(forName: draftSuiteName)
            stagingDefaults.removePersistentDomain(forName: stagingSuiteName)
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
            try? FileManager.default.removeItem(at: sourceFileURL)
        }

        try Data("hello from extension".utf8).write(to: sourceFileURL)

        let stagingStore = SharedComposeDraftStagingStore(
            userDefaults: stagingDefaults,
            baseDirectoryURL: stagingDirectoryURL
        )
        let draftStore = ComposeDraftStore(
            userDefaults: draftDefaults,
            stagingStore: stagingStore
        )

        let stagedItem = try draftStore.stageSharedDraft(
            accountID: "me",
            sourceApplication: "ShareExtension",
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "shared import body"),
            attachments: [
                SharedComposeDraftAttachmentInput(
                    sourceURL: sourceFileURL,
                    fileName: "shared.txt",
                    mimeType: "text/plain"
                )
            ]
        )

        let coordinator = SharedComposeImportCoordinator(draftStore: draftStore)
        let resolution = try #require(
            coordinator.consumeNextImportableDraft(activeAccountID: "me")
        )

        #expect(resolution.draft.category == .manual)
        #expect(resolution.draft.id == "shared-\(stagedItem.id)")
        #expect(resolution.draft.payload.content == "shared import body")
        #expect(resolution.sharedImport?.stagingItemID == stagedItem.id)
        #expect(draftStore.pendingSharedStagingItems().count == 1)
        #expect(draftStore.draft(id: resolution.draft.id) != nil)

        var updatedDraft = resolution.draft
        updatedDraft.payload = makeComposeDraftPayload(content: "partial import progress")
        #expect(draftStore.save(updatedDraft))
        let retryResolution = try #require(
            coordinator.consumeNextImportableDraft(activeAccountID: "me")
        )
        #expect(retryResolution.draft.payload.content == "partial import progress")
    }

    @Test @MainActor func sharedComposeImportPersistsTextBeforeRemovingAttachmentlessStage() throws {
        let draftSuiteName = "shared-compose-no-attachment-drafts-\(UUID().uuidString)"
        let stagingSuiteName = "shared-compose-no-attachment-staging-\(UUID().uuidString)"
        let draftDefaults = try #require(UserDefaults(suiteName: draftSuiteName))
        let stagingDefaults = try #require(UserDefaults(suiteName: stagingSuiteName))
        let stagingDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-no-attachment-\(UUID().uuidString)", isDirectory: true)
        defer {
            draftDefaults.removePersistentDomain(forName: draftSuiteName)
            stagingDefaults.removePersistentDomain(forName: stagingSuiteName)
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
        }

        let stagingStore = SharedComposeDraftStagingStore(
            userDefaults: stagingDefaults,
            baseDirectoryURL: stagingDirectoryURL
        )
        let draftStore = ComposeDraftStore(
            userDefaults: draftDefaults,
            stagingStore: stagingStore
        )
        let staged = try draftStore.stageSharedDraft(
            accountID: "me",
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "persist before consume")
        )

        let resolution = try #require(
            SharedComposeImportCoordinator(draftStore: draftStore)
                .consumeNextImportableDraft(activeAccountID: "me")
        )

        #expect(resolution.draft.id == "shared-\(staged.id)")
        #expect(resolution.sharedImport == nil)
        #expect(draftStore.pendingSharedStagingItems().isEmpty)
        #expect(draftStore.draft(id: resolution.draft.id)?.payload.content == "persist before consume")
    }

    @Test @MainActor func sharedComposeImportPersistsCompletedMediaBeforeCancellation() async throws {
        let draftSuiteName = "shared-compose-cancel-drafts-\(UUID().uuidString)"
        let stagingSuiteName = "shared-compose-cancel-staging-\(UUID().uuidString)"
        let draftDefaults = try #require(UserDefaults(suiteName: draftSuiteName))
        let stagingDefaults = try #require(UserDefaults(suiteName: stagingSuiteName))
        let stagingDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-cancel-\(UUID().uuidString)", isDirectory: true)
        let firstSource = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-cancel-first-\(UUID().uuidString).png")
        let secondSource = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-cancel-second-\(UUID().uuidString).png")
        defer {
            draftDefaults.removePersistentDomain(forName: draftSuiteName)
            stagingDefaults.removePersistentDomain(forName: stagingSuiteName)
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
            try? FileManager.default.removeItem(at: firstSource)
            try? FileManager.default.removeItem(at: secondSource)
        }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let imageData = try #require(image.pngData())
        try imageData.write(to: firstSource)
        try imageData.write(to: secondSource)

        let stagingStore = SharedComposeDraftStagingStore(
            userDefaults: stagingDefaults,
            baseDirectoryURL: stagingDirectoryURL
        )
        let draftStore = ComposeDraftStore(
            userDefaults: draftDefaults,
            stagingStore: stagingStore
        )
        _ = try draftStore.stageSharedDraft(
            accountID: "me",
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "keep completed upload"),
            attachments: [
                SharedComposeDraftAttachmentInput(
                    sourceURL: firstSource,
                    mimeType: "image/png",
                    id: "first"
                ),
                SharedComposeDraftAttachmentInput(
                    sourceURL: secondSource,
                    mimeType: "image/png",
                    id: "second"
                ),
            ]
        )
        let resolution = try #require(
            SharedComposeImportCoordinator(draftStore: draftStore)
                .consumeNextImportableDraft(activeAccountID: "me")
        )
        let sharedImport = try #require(resolution.sharedImport)

        let api = MockMastodonAPI()
        var uploadCount = 0
        api.uploadMediaHandler = { _, _, _ in
            uploadCount += 1
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            return Status.Attachment(
                id: "server-media-\(uploadCount)",
                type: "image",
                url: URL(string: "https://example.com/media-\(uploadCount).png")!,
                previewURL: URL(string: "https://example.com/media-\(uploadCount)-preview.png")!
            )
        }
        let viewModel = ComposeViewModel(
            context: resolution.draft.target.composeContext,
            apiClient: api,
            currentUserID: "me",
            initialDraft: resolution.draft
        )

        let importTask = Task { @MainActor in
            await viewModel.importSharedAttachments(
                from: sharedImport,
                draftStore: draftStore
            )
        }
        let outcome = await importTask.value

        #expect(outcome == .partial)
        #expect(uploadCount == 1)
        #expect(draftStore.draft(id: resolution.draft.id)?.payload.mediaAttachments.map(\.id) == ["server-media-1"])
        #expect(draftStore.pendingSharedStagingItems().first?.attachments.map(\.id) == ["second"])
    }

    @Test @MainActor func sharedComposeImportCoordinatorSkipsSharedDraftForDifferentActiveAccount() async throws {
        let draftSuiteName = "shared-compose-import-skip-drafts-\(UUID().uuidString)"
        let stagingSuiteName = "shared-compose-import-skip-staging-\(UUID().uuidString)"
        let draftDefaults = try #require(UserDefaults(suiteName: draftSuiteName))
        let stagingDefaults = try #require(UserDefaults(suiteName: stagingSuiteName))
        let stagingDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-compose-import-skip-\(UUID().uuidString)", isDirectory: true)

        defer {
            draftDefaults.removePersistentDomain(forName: draftSuiteName)
            stagingDefaults.removePersistentDomain(forName: stagingSuiteName)
            try? FileManager.default.removeItem(at: stagingDirectoryURL)
        }

        let stagingStore = SharedComposeDraftStagingStore(
            userDefaults: stagingDefaults,
            baseDirectoryURL: stagingDirectoryURL
        )
        let draftStore = ComposeDraftStore(
            userDefaults: draftDefaults,
            stagingStore: stagingStore
        )

        _ = try draftStore.stageSharedDraft(
            accountID: "someone-else",
            sourceApplication: "ShareExtension",
            target: ComposeDraftTarget(kind: .newPost),
            payload: makeComposeDraftPayload(content: "foreign shared draft")
        )

        let coordinator = SharedComposeImportCoordinator(draftStore: draftStore)
        let resolution = coordinator.consumeNextImportableDraft(activeAccountID: "me")

        #expect(resolution == nil)
        #expect(draftStore.pendingSharedStagingItems().count == 1)
    }

    @Test @MainActor func accountSessionStorePublishesSharedSnapshotForActiveSession() async throws {
        let sessionSuiteName = "account-session-store-\(UUID().uuidString)"
        let bootstrapSuiteName = "account-session-bootstrap-\(UUID().uuidString)"
        let sessionDefaults = try #require(UserDefaults(suiteName: sessionSuiteName))
        let bootstrapDefaults = try #require(UserDefaults(suiteName: bootstrapSuiteName))
        let keychain = KeychainService(
            service: "com.somincola.moro.tests.\(UUID().uuidString)",
            accessGroup: nil
        )

        defer {
            sessionDefaults.removePersistentDomain(forName: sessionSuiteName)
            bootstrapDefaults.removePersistentDomain(forName: bootstrapSuiteName)
            try? keychain.deleteAll()
        }

        let bootstrapStore = SharedActiveAccountSessionBootstrapStore(userDefaults: bootstrapDefaults)
        let sessionStore = AccountSessionStore(
            keychain: keychain,
            userDefaults: sessionDefaults,
            legacyUserDefaults: nil,
            bootstrapStore: bootstrapStore
        )

        let instanceURL = try #require(URL(string: "https://mastodon.example"))
        let account = makeAccount(id: "me", displayName: "Moro User")
        let savedSession = try sessionStore.saveSession(
            token: "test-token",
            account: account,
            instanceURL: instanceURL,
            activate: true
        )

        let snapshot = try #require(bootstrapStore.load())
        #expect(snapshot.sessionID == savedSession.id)
        #expect(snapshot.account.id == account.id)
        #expect(snapshot.instanceURL == instanceURL)
        #expect(snapshot.tokenStorageKey == savedSession.tokenStorageKey)
    }

    @Test @MainActor func accountSessionStoreClearsSharedSnapshotWhenLastSessionIsRemoved() async throws {
        let sessionSuiteName = "account-session-remove-\(UUID().uuidString)"
        let bootstrapSuiteName = "account-session-remove-bootstrap-\(UUID().uuidString)"
        let sessionDefaults = try #require(UserDefaults(suiteName: sessionSuiteName))
        let bootstrapDefaults = try #require(UserDefaults(suiteName: bootstrapSuiteName))
        let keychain = KeychainService(
            service: "com.somincola.moro.tests.\(UUID().uuidString)",
            accessGroup: nil
        )

        defer {
            sessionDefaults.removePersistentDomain(forName: sessionSuiteName)
            bootstrapDefaults.removePersistentDomain(forName: bootstrapSuiteName)
            try? keychain.deleteAll()
        }

        let bootstrapStore = SharedActiveAccountSessionBootstrapStore(userDefaults: bootstrapDefaults)
        let sessionStore = AccountSessionStore(
            keychain: keychain,
            userDefaults: sessionDefaults,
            legacyUserDefaults: nil,
            bootstrapStore: bootstrapStore
        )

        let instanceURL = try #require(URL(string: "https://mastodon.example"))
        let savedSession = try sessionStore.saveSession(
            token: "test-token",
            account: makeAccount(id: "me"),
            instanceURL: instanceURL,
            activate: true
        )

        #expect(bootstrapStore.load() != nil)

        try sessionStore.removeSession(id: savedSession.id)

        #expect(bootstrapStore.load() == nil)
    }

    @Test @MainActor func composeRedraftUsesStoredReplyTargetWhenPublishing() async throws {
        let api = MockMastodonAPI()
        var capturedReplyID: String?
        var capturedLanguage: String?

        api.publishStatusResultHandler = { text, _, _, inReplyToID, spoilerText, _, quotingID, language, _, poll in
            capturedReplyID = inReplyToID
            capturedLanguage = language
            #expect(text == "Hello reply")
            #expect(spoilerText == "cw")
            #expect(quotingID == nil)
            #expect(poll?.options == ["One", "Two"])
            return .posted(self.makeStatus(id: "redraft-posted"))
        }

        let poll = Status.Poll(
            id: "poll-1",
            expiresAt: nil,
            expired: false,
            multiple: false,
            votesCount: 0,
            votersCount: nil,
            options: [
                .init(title: "One", votesCount: nil),
                .init(title: "Two", votesCount: nil),
            ],
            voted: nil,
            ownVotes: nil
        )
        let replyStatus = makeStatus(
            id: "reply-1",
            content: "<p>Hello reply</p>",
            inReplyToID: "parent-1",
            spoilerText: "cw",
            visibility: MastodonVisibility.followers.rawValue,
            language: "es",
            poll: poll
        )
        let draft = ComposeDraft.redraft(from: replyStatus, accountID: "me")
        let viewModel = ComposeViewModel(
            context: draft.target.composeContext,
            apiClient: api,
            currentUserID: "me",
            initialDraft: draft
        )

        _ = try await viewModel.publish()

        #expect(capturedReplyID == "parent-1")
        #expect(capturedLanguage == "es")
    }

    @Test @MainActor func composePublishIgnoresSchedulingStateWhileFeatureIsDisabled() async throws {
        let api = MockMastodonAPI()
        let feedCoordinator = FeedCoordinator.shared
        let scheduledDate = Date().addingTimeInterval(2 * 60 * 60)
        var capturedScheduledAt: Date?
        defer {
            feedCoordinator.mostRecentUpdate = nil
        }

        api.publishStatusResultHandler = { _, _, _, _, _, _, _, _, scheduledAt, _ in
            capturedScheduledAt = scheduledAt
            return .posted(self.makeStatus(id: "posted-now"))
        }

        let viewModel = ComposeViewModel(
            context: .newPost,
            apiClient: api,
            feedCoordinator: feedCoordinator
        )
        viewModel.content = "hello future"
        viewModel.isSchedulingEnabled = true
        viewModel.scheduledAt = scheduledDate
        feedCoordinator.mostRecentUpdate = nil

        let result = try await viewModel.publish()

        guard case .posted(let status) = result else {
            Issue.record("Expected immediate publish while scheduling is disabled")
            return
        }

        #expect(ComposeFeatureAvailability.scheduledPublishing == false)
        #expect(viewModel.isScheduledPublishingActive == false)
        #expect(capturedScheduledAt == nil)
        #expect(status.id == "posted-now")
        #expect(feedCoordinator.mostRecentUpdate != nil)
    }

    @Test @MainActor func composeEditPublishesUpdatedStatusAndPreservesExistingMedia() async throws {
        let api = MockMastodonAPI()
        let feedCoordinator = FeedCoordinator.shared
        let attachment = Status.Attachment(
            id: "media-1",
            type: "image",
            url: URL(string: "https://example.com/image.png")!,
            previewURL: URL(string: "https://example.com/image-preview.png")!,
            description: "old alt"
        )
        let original = makeStatus(
            id: "edit-1",
            content: "<p>Hello old</p>",
            mediaAttachments: [attachment],
            visibility: MastodonVisibility.unlisted.rawValue,
            language: "fr"
        )
        var capturedID: String?
        var capturedMediaIDs: [String]?
        var capturedLanguage: String?
        defer {
            feedCoordinator.mostRecentUpdate = nil
        }

        api.editStatusHandler = { id, text, visibility, mediaIDs, _, spoilerText, _, _, language, poll in
            capturedID = id
            capturedMediaIDs = mediaIDs
            capturedLanguage = language
            #expect(text == "Hello updated")
            #expect(visibility == .unlisted)
            #expect(spoilerText == "")
            #expect(poll == nil)
            return self.makeStatus(
                id: id,
                content: "<p>Hello updated</p>",
                mediaAttachments: [attachment],
                visibility: MastodonVisibility.unlisted.rawValue,
                language: language
            )
        }

        let viewModel = ComposeViewModel(
            context: .edit(status: original),
            apiClient: api,
            feedCoordinator: feedCoordinator
        )
        api.fetchStatusSourceHandler = { id in
            StatusSource(id: id, text: "Hello old", spoilerText: "")
        }
        await viewModel.loadEditingSourceIfNeeded()
        viewModel.content = "Hello updated"

        let result = try await viewModel.publish()

        guard case .posted(let updatedStatus) = result else {
            Issue.record("Expected posted result when editing a status")
            return
        }

        #expect(capturedID == original.id)
        #expect(capturedMediaIDs == [attachment.id])
        #expect(capturedLanguage == "fr")
        #expect(updatedStatus.id == original.id)
        guard case .post(let publishedStatus)? = feedCoordinator.mostRecentUpdate else {
            Issue.record("Expected FeedCoordinator to publish the edited status")
            return
        }
        #expect(publishedStatus.id == updatedStatus.id)
    }

    @Test @MainActor func composeValidationIgnoresScheduledDateWhileFeatureIsDisabled() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        viewModel.content = "hello"
        viewModel.isSchedulingEnabled = true
        viewModel.scheduledAt = Date().addingTimeInterval(60)

        #expect(viewModel.isScheduledPublishingActive == false)
        #expect(viewModel.scheduledPublishDate == nil)
        #expect(viewModel.publishBlocker == nil)
        #expect(viewModel.publishDisabledReason == nil)
    }

    @Test @MainActor func composePublishRejectsPollWithMedia() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        viewModel.content = "hello"
        viewModel.isPollActive = true
        viewModel.pollOptions = ["A", "B"]
        viewModel.mediaAttachments = [
            makeComposeMediaAttachment(id: "uploaded", state: .uploaded)
        ]

        #expect(viewModel.publishBlocker == .pollCannotIncludeMedia)
        #expect(viewModel.publishDisabledReason == MoroL10n.Compose.validationPollCannotIncludeMedia)

        do {
            _ = try await viewModel.publish()
            Issue.record("Expected pollCannotIncludeMedia error when poll and media coexist")
        } catch let error as ComposeError {
            guard case .pollCannotIncludeMedia = error else {
                Issue.record("Unexpected error: \(error.localizedDescription)")
                return
            }
        }
    }

    @Test @MainActor func composePublishRejectsPollWithInsufficientOptions() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        viewModel.isPollActive = true
        viewModel.pollOptions = ["Only one", "   "]

        #expect(viewModel.publishBlocker == .pollNeedsMoreOptions)
        #expect(viewModel.publishDisabledReason == nil)

        do {
            _ = try await viewModel.publish()
            Issue.record("Expected invalidPoll error for insufficient poll options")
        } catch let error as ComposeError {
            guard case .invalidPoll = error else {
                Issue.record("Unexpected error: \(error.localizedDescription)")
                return
            }
        }
    }

    @Test @MainActor func composePublishRejectsContentExceedingCharacterLimit() async throws {
        let api = MockMastodonAPI()
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        viewModel.content = String(repeating: "a", count: viewModel.maxCharacters + 1)

        #expect(viewModel.publishBlocker == .characterLimitExceeded)
        #expect(viewModel.canPublish == false)
        #expect(viewModel.publishDisabledReason == nil)

        do {
            _ = try await viewModel.publish()
            Issue.record("Expected characterLimitExceeded error when content is over max length")
        } catch let error as ComposeError {
            guard case .characterLimitExceeded = error else {
                Issue.record("Unexpected error: \(error.localizedDescription)")
                return
            }
        }
    }

    @Test @MainActor func contentConcealSyncKeepsExpandedStateForSameStatus() async throws {
        let viewModel = ContentConcealViewModel(
            statusID: "status-1",
            hasContentWarning: true,
            hasFilterWarning: false,
            spoilerText: "CW",
            filterWarningText: nil
        )

        #expect(viewModel.isContentRevealed == false)
        viewModel.toggleContentWarning()
        #expect(viewModel.isContentRevealed == true)

        // Simulate like/reblog update: same status, warning meta unchanged.
        viewModel.sync(
            statusID: "status-1",
            hasContentWarning: true,
            hasFilterWarning: false,
            spoilerText: "CW",
            filterWarningText: nil
        )
        #expect(viewModel.isContentRevealed == true)
    }

    @Test @MainActor func contentConcealSyncResetsForDifferentStatusID() async throws {
        let viewModel = ContentConcealViewModel(
            statusID: "status-1",
            hasContentWarning: true,
            hasFilterWarning: false,
            spoilerText: "CW",
            filterWarningText: nil
        )
        viewModel.toggleContentWarning()
        #expect(viewModel.isContentRevealed == true)

        // Switching to another post should reset conceal state.
        viewModel.sync(
            statusID: "status-2",
            hasContentWarning: true,
            hasFilterWarning: false,
            spoilerText: "CW 2",
            filterWarningText: nil
        )
        #expect(viewModel.isContentRevealed == false)
        #expect(viewModel.statusID == "status-2")
    }

    @Test @MainActor func searchViewModelLoadsMoreWithOffsetPagination() async throws {
        let api = MockMastodonAPI()
        api.searchHandler = { _, type, _, limit, offset in
            let resolvedOffset = offset ?? 0
            if type != .statuses {
                return SearchResults()
            }

            let pageSize = resolvedOffset == 0 ? limit : 5
            let statuses = (0..<pageSize).map { index in
                self.makeStatus(id: "status-\(resolvedOffset + index)")
            }
            return SearchResults(statuses: statuses)
        }

        let viewModel = SearchViewModel(apiClient: api, initialQuery: "swift")
        viewModel.scope = .statuses
        viewModel.submitSearch()
        await waitUntil(timeout: 1.0) { !viewModel.isLoading }

        #expect(viewModel.results.statuses.count == 20)
        #expect(api.searchCallOffsets == [0])
        #expect(api.searchCallTypes == [.statuses])

        viewModel.loadMoreIfNeeded()
        await waitUntil(timeout: 1.0) { !viewModel.isLoadingMore }

        #expect(viewModel.results.statuses.count == 25)
        #expect(api.searchCallOffsets == [0, 20])
        #expect(api.searchCallLimits == [20, 40])

        viewModel.loadMoreIfNeeded()
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(api.searchCallOffsets == [0, 20])
    }

    @Test @MainActor func searchViewModelStopsPagingWhenAppendAddsNoUniqueResults() async throws {
        let api = MockMastodonAPI()
        api.searchHandler = { _, type, _, limit, offset in
            let resolvedOffset = offset ?? 0
            guard type == .statuses else { return SearchResults() }

            if resolvedOffset == 0 {
                let statuses = (0..<limit).map { index in
                    self.makeStatus(id: "status-\(index)")
                }
                return SearchResults(statuses: statuses)
            }

            // Return full page but all duplicated IDs from first page.
            let duplicated = (0..<20).map { index in
                self.makeStatus(id: "status-\(index)")
            }
            return SearchResults(statuses: duplicated)
        }

        let viewModel = SearchViewModel(apiClient: api, initialQuery: "swift")
        viewModel.scope = .statuses
        viewModel.submitSearch()
        await waitUntil(timeout: 1.0) { !viewModel.isLoading }

        #expect(viewModel.results.statuses.count == 20)
        #expect(api.searchCallOffsets == [0])

        viewModel.loadMoreIfNeeded()
        await waitUntil(timeout: 1.0) { !viewModel.isLoadingMore }

        // No unique additions after append -> stop further pagination.
        #expect(viewModel.results.statuses.count == 20)
        #expect(api.searchCallOffsets == [0, 20])

        viewModel.loadMoreIfNeeded()
        try? await Task.sleep(nanoseconds: 60_000_000)
        #expect(api.searchCallOffsets == [0, 20])
    }

    @Test @MainActor func searchViewModelResetsOffsetWhenScopeChanges() async throws {
        let api = MockMastodonAPI()
        api.searchHandler = { _, type, _, limit, offset in
            let resolvedOffset = offset ?? 0
            switch type {
            case .accounts:
                let accounts = (0..<limit).map { index in
                    self.makeAccount(id: "account-\(resolvedOffset + index)")
                }
                return SearchResults(accounts: accounts)
            case .hashtags:
                let tags = (0..<limit).map { index in
                    SearchTag(
                        name: "tag-\(resolvedOffset + index)",
                        url: URL(string: "https://example.com/tags/\(resolvedOffset + index)")!,
                        history: nil
                    )
                }
                return SearchResults(hashtags: tags)
            default:
                return SearchResults()
            }
        }

        let viewModel = SearchViewModel(apiClient: api, initialQuery: "mastodon")
        viewModel.scope = .accounts
        viewModel.submitSearch()
        await waitUntil(timeout: 1.0) { !viewModel.isLoading }

        viewModel.loadMoreIfNeeded()
        await waitUntil(timeout: 1.0) { !viewModel.isLoadingMore }

        viewModel.scope = .hashtags
        viewModel.submitSearch()
        await waitUntil(timeout: 1.0) { !viewModel.isLoading }

        #expect(api.searchCallTypes == [.accounts, .accounts, .hashtags])
        #expect(api.searchCallOffsets == [0, 20, 0])
        #expect(viewModel.results.accounts.isEmpty)
        #expect(viewModel.results.hashtags.count == 20)
    }

    @Test @MainActor func searchViewModelDoesNotPaginateCombinedScope() async throws {
        let api = MockMastodonAPI()
        api.searchHandler = { _, type, _, limit, _ in
            #expect(type == nil)
            return SearchResults(
                statuses: (0..<limit).map { index in
                    self.makeStatus(id: "status-\(index)")
                }
            )
        }

        let viewModel = SearchViewModel(apiClient: api, initialQuery: "moro")
        viewModel.scope = .all // Explicit legacy API scope; Explore defaults to Accounts.
        viewModel.submitSearch()
        await waitUntil(timeout: 1.0) { !viewModel.isLoading }
        viewModel.loadMoreIfNeeded()
        try? await Task.sleep(nanoseconds: 60_000_000)

        #expect(api.searchCallOffsets == [0])
        #expect(api.searchCallLimits == [20])
    }

    @Test @MainActor func searchViewModelRejectsStaleResponseAfterQueryChanges() async throws {
        let api = MockMastodonAPI()
        api.searchHandler = { query, _, _, _, _ in
            if query == "old" {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            return SearchResults(statuses: [self.makeStatus(id: "status-\(query)")])
        }

        let viewModel = SearchViewModel(apiClient: api, initialQuery: "old")
        viewModel.scope = .statuses
        viewModel.submitSearch()

        viewModel.markTyping(query: "new", scope: .statuses)
        viewModel.submitSearch()
        await waitUntil(timeout: 1.0) { !viewModel.isLoading }
        try? await Task.sleep(nanoseconds: 160_000_000)

        #expect(viewModel.results.statuses.map(\.id) == ["status-new"])
        #expect(api.searchCallOffsets == [0, 0])
    }

    @Test @MainActor func profileViewModelIncorporatesFeedCoordinatorPostUpdate() async throws {
        let api = MockMastodonAPI()
        let feedCoordinator = FeedCoordinator.shared
        feedCoordinator.mostRecentUpdate = nil

        let viewModel = ProfileViewModel(
            apiClient: api,
            accountID: "target-account",
            currentAccountID: "current-account",
            feedCoordinator: feedCoordinator
        )
        viewModel.posts = [
            makeStatus(id: "status-1", content: "before-update"),
            makeStatus(id: "status-2", content: "unchanged")
        ]

        let updated = makeStatus(id: "status-1", content: "after-update")
        feedCoordinator.publishUpdate(.post(updated))
        await waitUntil(timeout: 0.5) {
            viewModel.posts.first(where: { $0.id == "status-1" })?.content == "after-update"
        }

        #expect(viewModel.posts.count == 2)
        #expect(viewModel.posts.first(where: { $0.id == "status-1" })?.content == "after-update")
        #expect(viewModel.posts.first(where: { $0.id == "status-2" })?.content == "unchanged")

        feedCoordinator.mostRecentUpdate = nil
    }

    @Test @MainActor func profileViewModelIncorporatesFeedCoordinatorDeleteUpdate() async throws {
        let api = MockMastodonAPI()
        let feedCoordinator = FeedCoordinator.shared
        feedCoordinator.mostRecentUpdate = nil

        let viewModel = ProfileViewModel(
            apiClient: api,
            accountID: "target-account",
            currentAccountID: "current-account",
            feedCoordinator: feedCoordinator
        )
        viewModel.posts = [
            makeStatus(id: "status-1"),
            makeStatus(id: "status-2"),
            makeStatus(id: "status-3")
        ]

        feedCoordinator.publishUpdate(.deletedPost("status-2"))
        await waitUntil(timeout: 0.5) {
            viewModel.posts.contains(where: { $0.id == "status-2" }) == false
        }

        #expect(viewModel.posts.count == 2)
        #expect(viewModel.posts.contains(where: { $0.id == "status-1" }))
        #expect(viewModel.posts.contains(where: { $0.id == "status-2" }) == false)
        #expect(viewModel.posts.contains(where: { $0.id == "status-3" }))

        feedCoordinator.mostRecentUpdate = nil
    }

    @Test @MainActor func newConversationViewModelInitialStateDeduplicatesAndExcludesCurrentUser()
        async throws
    {
        let api = MockMastodonAPI()
        let me = makeAccount(id: "me")
        let alice = makeAccount(id: "alice")
        let duplicateAlice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")

        let viewModel = NewConversationViewModel(
            apiClient: api,
            recentAccounts: [me, alice, duplicateAlice, bob],
            currentUserID: me.id
        )

        #expect(viewModel.displayAccounts.map(\.id) == ["alice", "bob"])
    }

    @Test @MainActor func newConversationViewModelSearchFiltersCurrentUserAndResetsToRecent()
        async throws
    {
        let api = MockMastodonAPI()
        let me = makeAccount(id: "me")
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")

        api.searchHandler = { _, type, _, _, _ in
            #expect(type == .accounts)
            return SearchResults(accounts: [me, bob, bob])
        }

        let viewModel = NewConversationViewModel(
            apiClient: api,
            recentAccounts: [alice],
            currentUserID: me.id
        )

        viewModel.query = "bob"
        viewModel.searchNow()
        await waitUntil(timeout: 1.0) {
            if case .loaded = viewModel.loadingState {
                return true
            }
            if case .error = viewModel.loadingState {
                return true
            }
            return false
        }

        #expect(viewModel.displayAccounts.map(\.id) == ["bob"])

        viewModel.query = ""
        viewModel.searchNow()
        #expect(viewModel.displayAccounts.map(\.id) == ["alice"])
    }

    @Test @MainActor func accountGovernanceMutedAccountsLoadAndReleaseRemovesAccount() async throws {
        let api = MockMastodonAPI()
        let alice = makeAccount(id: "alice")
        let bob = makeAccount(id: "bob")
        var releasedIDs: [String] = []

        api.fetchMutedAccountsHandler = { _, _, limit in
            #expect(limit == 200)
            return [alice, bob]
        }
        api.unmuteAccountHandler = { id in
            releasedIDs.append(id)
            return self.makeRelationship(id: id, muting: false)
        }

        let viewModel = AccountGovernanceViewModel(kind: .muted, apiClient: api)
        await viewModel.loadInitial()

        #expect(viewModel.accounts.map(\.id) == ["alice", "bob"])
        #expect(viewModel.transientErrorMessage == nil)

        await viewModel.release(alice)

        #expect(releasedIDs == ["alice"])
        #expect(viewModel.accounts.map(\.id) == ["bob"])
        #expect(viewModel.transientErrorMessage == nil)
    }

    @Test @MainActor func accountGovernanceBlockedReleaseFailureKeepsAccountAndError() async throws {
        let api = MockMastodonAPI()
        let eve = makeAccount(id: "eve")

        api.fetchBlockedAccountsHandler = { _, _, _ in
            [eve]
        }
        api.unblockAccountHandler = { _ in
            throw MockMastodonAPI.MockError.forcedFailure
        }

        let viewModel = AccountGovernanceViewModel(kind: .blocked, apiClient: api)
        await viewModel.loadInitial()
        await viewModel.release(eve)

        #expect(viewModel.accounts.map(\.id) == ["eve"])
        #expect(viewModel.transientErrorMessage == MoroL10n.Governance.blockReleaseFailedDetail)
    }

    @Test @MainActor func notificationsViewModelKeepsTypesDisabledForPush() async throws {
        let api = MockMastodonAPI()
        let settings = AppSettings.shared
        let originalPolicy = settings.notificationPolicy
        let originalMentions = settings.receiveMentionsAndReplies
        let originalBoosts = settings.receiveBoosts
        let originalFavourites = settings.receiveFavourites
        let originalFollowers = settings.receiveNewFollowers

        defer {
            settings.notificationPolicy = originalPolicy
            settings.receiveMentionsAndReplies = originalMentions
            settings.receiveBoosts = originalBoosts
            settings.receiveFavourites = originalFavourites
            settings.receiveNewFollowers = originalFollowers
        }

        settings.notificationPolicy = .anyone
        settings.receiveMentionsAndReplies = true
        settings.receiveBoosts = true
        settings.receiveFavourites = false
        settings.receiveNewFollowers = true

        api.fetchNotificationsHandler = { _, _, limit, _ in
            #expect(limit == 30)
            return [
                self.makeNotification(id: "n-1", type: "mention", account: self.makeAccount(id: "alice")),
                self.makeNotification(id: "n-2", type: "favourite", account: self.makeAccount(id: "bob"))
            ]
        }

        let viewModel = NotificationsViewModel(apiClient: api)
        await viewModel.loadInitial()

        #expect(viewModel.notifications.count == 2)
        #expect(viewModel.filterInsight == NotificationFilterInsight(
            fetchedCount: 2,
            visibleCount: 2,
            hiddenByTypeCount: 0,
            hiddenByPolicyCount: 0,
            policy: .anyone
        ))
    }

    @Test @MainActor func pushSourcePolicyDoesNotFilterTheInbox() async throws {
        let api = MockMastodonAPI()
        let settings = AppSettings.shared
        let originalPolicy = settings.notificationPolicy
        let originalMentions = settings.receiveMentionsAndReplies
        let originalBoosts = settings.receiveBoosts
        let originalFavourites = settings.receiveFavourites
        let originalFollowers = settings.receiveNewFollowers

        defer {
            settings.notificationPolicy = originalPolicy
            settings.receiveMentionsAndReplies = originalMentions
            settings.receiveBoosts = originalBoosts
            settings.receiveFavourites = originalFavourites
            settings.receiveNewFollowers = originalFollowers
        }

        settings.notificationPolicy = .followers
        settings.receiveMentionsAndReplies = true
        settings.receiveBoosts = true
        settings.receiveFavourites = true
        settings.receiveNewFollowers = true

        api.fetchNotificationsHandler = { _, _, _, _ in
            [
                self.makeNotification(id: "n-1", type: "mention", account: self.makeAccount(id: "alice")),
                self.makeNotification(id: "n-2", type: "reblog", account: self.makeAccount(id: "bob"))
            ]
        }
        api.fetchRelationshipsHandler = { _ in
            Issue.record("Inbox loading must not fetch relationships for a local push policy")
            return []
        }

        let viewModel = NotificationsViewModel(apiClient: api)
        await viewModel.loadInitial()

        #expect(viewModel.notifications.count == 2)
        #expect(viewModel.filterInsight == NotificationFilterInsight(
            fetchedCount: 2,
            visibleCount: 2,
            hiddenByTypeCount: 0,
            hiddenByPolicyCount: 0,
            policy: .anyone
        ))
    }

}

private extension moroTests {
    actor AsyncCounter {
        private var count: Int = 0

        func increment() {
            count += 1
        }

        func value() -> Int {
            count
        }
    }

    actor AsyncURLRecorder {
        private var urls: [URL] = []

        func append(_ url: URL) {
            urls.append(url)
        }

        func values() -> [URL] {
            urls
        }
    }

    func tinyPNGData() -> Data {
        // 1x1 transparent PNG.
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO7+3WQAAAAASUVORK5CYII="
        return Data(base64Encoded: base64) ?? Data()
    }

    func makeComposeDraftPayload(content: String) -> ComposeDraftPayload {
        ComposeDraftPayload(
            content: content,
            contentWarning: "",
            isContentWarningActive: false,
            visibility: .public,
            mediaAttachments: [],
            isPollActive: false,
            pollOptions: ["", ""],
            pollMultiple: false,
            pollExpiresIn: 24 * 60 * 60,
            isSchedulingEnabled: false,
            scheduledAt: nil,
            selectedLanguageCode: "",
            quotePolicyRawValue: ComposeViewModel.QuotePolicy.anyone.rawValue
        )
    }

    // MARK: - Thread / poll regression tests

    @Test @MainActor func statusUpdatingPollReplacesPollAndPreservesFields() {
        let before = Status.Poll(
            id: "poll-1", expiresAt: nil, expired: false, multiple: false,
            votesCount: 0, votersCount: nil,
            options: [
                Status.Poll.PollOption(title: "A", votesCount: nil),
                Status.Poll.PollOption(title: "B", votesCount: nil)
            ],
            voted: false, ownVotes: nil
        )
        let after = Status.Poll(
            id: "poll-1", expiresAt: nil, expired: false, multiple: false,
            votesCount: 1, votersCount: nil,
            options: [
                Status.Poll.PollOption(title: "A", votesCount: 1),
                Status.Poll.PollOption(title: "B", votesCount: 0)
            ],
            voted: true, ownVotes: nil
        )
        let status = makeStatus(id: "s1", inReplyToID: "parent-1", poll: before)

        let updated = status.updating(poll: after)

        #expect(updated.poll?.id == "poll-1")
        #expect(updated.poll?.voted == true)
        #expect(updated.poll?.votesCount == 1)
        // updating(poll:) replaces only the poll and keeps every other field, unlike the
        // hand-rebuilt Status that dropped filtered/pinned/editedAt.
        #expect(updated.id == "s1")
        #expect(updated.inReplyToID == "parent-1")
    }

    @Test @MainActor func statusUpdatingPollTargetsNestedReblogPoll() {
        let before = Status.Poll(
            id: "poll-reblog", expiresAt: nil, expired: false, multiple: false,
            votesCount: 0, votersCount: nil,
            options: [
                Status.Poll.PollOption(title: "A", votesCount: nil),
                Status.Poll.PollOption(title: "B", votesCount: nil)
            ],
            voted: false, ownVotes: nil
        )
        let after = Status.Poll(
            id: "poll-reblog", expiresAt: nil, expired: false, multiple: false,
            votesCount: 1, votersCount: 1,
            options: [
                Status.Poll.PollOption(title: "A", votesCount: 0),
                Status.Poll.PollOption(title: "B", votesCount: 1)
            ],
            voted: true, ownVotes: [1]
        )
        let original = makeStatus(id: "poll-original", poll: before)
        let wrapper = makeStatus(id: "poll-wrapper", reblog: Indirect(original))

        let updated = wrapper.updating(poll: after)

        #expect(updated.poll == nil)
        #expect(updated.displayStatus.id == "poll-original")
        #expect(updated.displayStatus.poll?.voted == true)
        #expect(updated.displayStatus.poll?.ownVotes == [1])
        #expect(updated.displayStatus.poll?.votesCount == 1)
    }

    @Test @MainActor func accountUpdatingFollowersCountPreservesEmojis() {
        let emoji = Account.Emoji(
            shortcode: "blob",
            url: URL(string: "https://example.test/blob.gif")!,
            staticURL: URL(string: "https://example.test/blob.png")!
        )
        let account = Account(
            id: "a1", username: "u", acct: "u@x", displayName: ":blob: U", note: "",
            avatar: "", avatarStatic: "", header: "", headerStatic: "",
            followersCount: 10, followingCount: 5, statusesCount: 3,
            emojis: [emoji]
        )

        let updated = account.updating(followersCount: 11)

        #expect(updated.followersCount == 11)
        // Custom display-name emojis must survive (the hand-rebuilt Account dropped them).
        #expect(updated.emojis.first?.shortcode == "blob")
        #expect(updated.id == "a1")
        #expect(updated.followingCount == 5)
    }

    // MARK: - Notifications robustness regression tests

    @Test @MainActor func notificationsLoadInitialRetriesAfterError() async {
        let api = MockMastodonAPI()
        let settings = AppSettings.shared
        let originalPolicy = settings.notificationPolicy
        let originalMentions = settings.receiveMentionsAndReplies
        defer {
            settings.notificationPolicy = originalPolicy
            settings.receiveMentionsAndReplies = originalMentions
        }
        settings.notificationPolicy = .anyone
        settings.receiveMentionsAndReplies = true

        var shouldFail = true
        api.fetchNotificationsHandler = { _, _, _, _ in
            if shouldFail { throw MockMastodonAPI.MockError.forcedFailure }
            return [self.makeNotification(id: "n-1", type: "mention", account: self.makeAccount(id: "alice"))]
        }

        let viewModel = NotificationsViewModel(apiClient: api)
        await viewModel.loadInitial()
        #expect(viewModel.notifications.isEmpty)
        let isError: Bool = { if case .error = viewModel.loadingState { return true } else { return false } }()
        #expect(isError)

        // The error-state retry button calls loadInitial again; it must actually re-load
        // (the old `.idle`-only guard turned this into a no-op).
        shouldFail = false
        await viewModel.loadInitial()
        #expect(viewModel.notifications.count == 1)
    }

    @Test @MainActor func notificationsRefreshFailureKeepsExistingListLoaded() async {
        let api = MockMastodonAPI()
        let settings = AppSettings.shared
        let originalPolicy = settings.notificationPolicy
        let originalMentions = settings.receiveMentionsAndReplies
        defer {
            settings.notificationPolicy = originalPolicy
            settings.receiveMentionsAndReplies = originalMentions
        }
        settings.notificationPolicy = .anyone
        settings.receiveMentionsAndReplies = true

        var shouldFail = false
        api.fetchNotificationsHandler = { _, _, _, _ in
            if shouldFail { throw MockMastodonAPI.MockError.forcedFailure }
            return [self.makeNotification(id: "n-1", type: "mention", account: self.makeAccount(id: "alice"))]
        }

        let viewModel = NotificationsViewModel(apiClient: api)
        await viewModel.loadInitial()
        #expect(viewModel.notifications.count == 1)

        // A failed refresh must keep the existing list and stay .loaded (so loadMore still
        // works), not drop to .error.
        shouldFail = true
        await viewModel.refresh()
        #expect(viewModel.notifications.count == 1)
        let isLoaded: Bool = { if case .loaded = viewModel.loadingState { return true } else { return false } }()
        #expect(isLoaded)
    }

    // MARK: - Timeline robustness regression tests

    @Test @MainActor func fetchNewStatusesKeepsPendingBannerOnFetchError() async {
        let api = MockMastodonAPI()
        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: TimelineCache(maxCachedStatuses: 50),
            cacheClientID: "timeline-g1-\(UUID().uuidString)"
        )
        viewModel.trackPendingStatusID("new-1")
        #expect(viewModel.pendingNewStatusIDs.contains("new-1"))

        api.fetchHomeTimelineHandler = { _, _, _ in
            throw MockMastodonAPI.MockError.forcedFailure
        }
        let succeeded = await viewModel.fetchNewStatuses(providesFeedback: false)

        // The "N new" indicator must survive a failed banner-tap fetch (the bug cleared it
        // and fired a success haptic as if it had succeeded).
        #expect(!succeeded)
        #expect(viewModel.pendingNewStatusIDs.contains("new-1"))
    }

    @Test @MainActor func forcedNewStatusFetchWorksWithoutStreamPendingIDs() async {
        let api = MockMastodonAPI()
        api.fetchHomeTimelineHandler = { _, _, _ in
            [self.makeStatus(id: "new-1")]
        }
        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: TimelineCache(maxCachedStatuses: 50),
            cacheClientID: "timeline-g2-\(UUID().uuidString)"
        )

        let succeeded = await viewModel.fetchNewStatuses(
            force: true,
            providesFeedback: false
        )

        #expect(succeeded)
        #expect(viewModel.statuses.map(\.id) == ["new-1"])
    }

    @Test @MainActor func loadMoreDeduplicatesOverlappingStatuses() async {
        let api = MockMastodonAPI()
        let config = TimelineViewModel.BootstrapConfig(
            initialLoadLimit: 2,
            refreshLoadLimit: 2,
            paginationLoadLimit: 2,
            initialRenderCap: 50,
            cacheHydrationSoftTimeoutNanoseconds: 10_000_000,
            deferredFillBatchSize: 4,
            deferredFillStepNanoseconds: 1_000_000,
            deferredFillInitialDelayNanoseconds: 1_000_000
        )
        api.fetchHomeTimelineHandler = { maxID, _, _ in
            if maxID == nil {
                return [self.makeStatus(id: "s2"), self.makeStatus(id: "s1")]
            }
            // Next page overlaps s1 (already present) and adds the genuinely-new s0.
            return [self.makeStatus(id: "s1"), self.makeStatus(id: "s0")]
        }
        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: TimelineCache(maxCachedStatuses: 50),
            cacheClientID: "timeline-g2-\(UUID().uuidString)",
            bootstrapConfig: config
        )

        await viewModel.loadInitial()
        await viewModel.loadMore()

        let ids = viewModel.statuses.map(\.id)
        #expect(Set(ids).count == ids.count)  // no duplicate IDs in the list
        #expect(ids.contains("s0"))           // the genuinely-new item was appended
    }

    @Test @MainActor func refreshPreservesOldRowsWithAnExplicitGap() async {
        let api = MockMastodonAPI()
        let config = TimelineViewModel.BootstrapConfig(
            initialLoadLimit: 2,
            refreshLoadLimit: 2,
            paginationLoadLimit: 2,
            initialRenderCap: 50,
            cacheHydrationSoftTimeoutNanoseconds: 10_000_000,
            deferredFillBatchSize: 4,
            deferredFillStepNanoseconds: 1_000_000,
            deferredFillInitialDelayNanoseconds: 1_000_000
        )
        api.fetchHomeTimelineHandler = { maxID, sinceID, _ in
            if maxID == nil, sinceID == nil {
                return [self.makeStatus(id: "old2"), self.makeStatus(id: "old1")]
            }
            // Refresh (sinceID set) returns a FULL page of new posts → a gap is likely.
            return [self.makeStatus(id: "new2"), self.makeStatus(id: "new1")]
        }
        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: TimelineCache(maxCachedStatuses: 50),
            cacheClientID: "timeline-gap-\(UUID().uuidString)",
            bootstrapConfig: config
        )

        await viewModel.loadInitial()
        await viewModel.refresh()

        #expect(viewModel.statuses.map(\.id) == ["new2", "new1", "old2", "old1"])
        #expect(viewModel.gaps.first?.afterID == "new1")
        #expect(viewModel.gaps.first?.beforeID == "old2")
    }

    @Test @MainActor func timelinePullRefreshDisarmsWhenPulledBackBeforeRelease() {
        let bridge = TimelineScrollBridge()
        let homeSubject = bridge.pullRefreshSubject(for: .home)
        let localSubject = bridge.pullRefreshSubject(for: .local)

        #expect(
            bridge.updatePullRefreshDistance(
                44,
                threshold: 40,
                for: .home,
                isSelected: true
            )
        )
        #expect(homeSubject.value.distance == 44)
        #expect(localSubject.value.distance == 0)

        #expect(
            bridge.updatePullRefreshDistance(
                24,
                threshold: 40,
                for: .home,
                isSelected: true
            ) == false
        )
        #expect(
            bridge.commitPullRefresh(
                for: .home,
                threshold: 40,
                isSelected: true
            ) == false
        )
        #expect(homeSubject.value.distance == 0)
        #expect(homeSubject.value.isRefreshing == false)
    }

    @Test @MainActor func timelinePullRefreshCommitsOnceAfterArmedRelease() {
        let bridge = TimelineScrollBridge()
        let subject = bridge.pullRefreshSubject(for: .local)

        _ = bridge.updatePullRefreshDistance(
            48,
            threshold: 40,
            for: .local,
            isSelected: true
        )
        #expect(
            bridge.commitPullRefresh(
                for: .local,
                threshold: 40,
                isSelected: true
            )
        )
        #expect(subject.value.isRefreshing)
        #expect(subject.value.isPinned)
        #expect(subject.value.distance == 40)
        #expect(
            bridge.commitPullRefresh(
                for: .local,
                threshold: 40,
                isSelected: true
            ) == false
        )

        bridge.finishPullRefresh(for: .local)
        #expect(subject.value.isRefreshing == false)
        #expect(subject.value.distance == 0)
    }

    @Test @MainActor func timelineRefreshDeduplicatesConcurrentRequests() async {
        let api = MockMastodonAPI()
        var requestCount = 0
        api.fetchHomeTimelineHandler = { _, _, _ in
            requestCount += 1
            try? await Task.sleep(for: .milliseconds(80))
            return [self.makeStatus(id: "new-1")]
        }
        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: TimelineCache(maxCachedStatuses: 20),
            cacheClientID: "refresh-dedupe-\(UUID().uuidString)"
        )

        async let first = viewModel.refresh(trigger: .pull)
        async let second = viewModel.refresh(trigger: .tabRetap)
        let results = await [first, second]

        #expect(requestCount == 1)
        for result in results {
            #expect(result.succeeded)
        }
        #expect(viewModel.statuses.map(\.id) == ["new-1"])
    }

    @Test @MainActor func failedRefreshKeepsPaginationAvailable() async {
        let api = MockMastodonAPI()
        let config = TimelineViewModel.BootstrapConfig(
            initialLoadLimit: 2,
            refreshLoadLimit: 2,
            paginationLoadLimit: 2,
            initialRenderCap: 10,
            cacheHydrationSoftTimeoutNanoseconds: 1_000_000,
            deferredFillBatchSize: 2,
            deferredFillStepNanoseconds: 1_000_000,
            deferredFillInitialDelayNanoseconds: 1_000_000
        )
        api.fetchHomeTimelineHandler = { maxID, sinceID, _ in
            if sinceID != nil {
                throw MockMastodonAPI.MockError.forcedFailure
            }
            if maxID == nil {
                return [self.makeStatus(id: "s2"), self.makeStatus(id: "s1")]
            }
            return [self.makeStatus(id: "s0")]
        }
        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: TimelineCache(maxCachedStatuses: 20),
            cacheClientID: "refresh-failure-\(UUID().uuidString)",
            bootstrapConfig: config
        )

        await viewModel.loadInitial()
        let result = await viewModel.refresh(trigger: .pull)
        if case .failure = result {
        } else {
            Issue.record("Expected refresh failure")
        }

        await viewModel.loadMore()
        #expect(viewModel.statuses.map(\.id) == ["s2", "s1", "s0"])
        #expect(viewModel.loadMoreFailed == false)
    }

    @Test @MainActor func refreshShowsLatestPageBeforeFillingTheGap() async {
        let api = MockMastodonAPI()
        let config = TimelineViewModel.BootstrapConfig(
            initialLoadLimit: 2,
            refreshLoadLimit: 2,
            paginationLoadLimit: 2,
            initialRenderCap: 20,
            cacheHydrationSoftTimeoutNanoseconds: 1_000_000,
            deferredFillBatchSize: 2,
            deferredFillStepNanoseconds: 1_000_000,
            deferredFillInitialDelayNanoseconds: 1_000_000
        )
        api.fetchHomeTimelineHandler = { maxID, sinceID, _ in
            if sinceID == nil {
                return [self.makeStatus(id: "old2"), self.makeStatus(id: "old1")]
            }
            switch maxID {
            case nil:
                return [self.makeStatus(id: "new4"), self.makeStatus(id: "new3")]
            case "new3":
                return [self.makeStatus(id: "new2"), self.makeStatus(id: "new1")]
            default:
                return []
            }
        }
        let viewModel = TimelineViewModel(
            apiClient: api,
            timelineType: .home,
            timelineCache: TimelineCache(maxCachedStatuses: 20),
            cacheClientID: "refresh-catchup-\(UUID().uuidString)",
            bootstrapConfig: config
        )

        await viewModel.loadInitial()
        let result = await viewModel.refresh(trigger: .newPosts)

        if case .success(let insertedCount, let replaced) = result {
            #expect(insertedCount == 2)
            #expect(replaced == false)
        } else {
            Issue.record("Expected catch-up refresh success")
        }
        #expect(viewModel.statuses.map(\.id) == ["new4", "new3", "old2", "old1"])
        if let gap = viewModel.gaps.first {
            #expect(await viewModel.loadGap(id: gap.id))
            #expect(await viewModel.loadGap(id: gap.id))
        } else { Issue.record("Expected a pageable gap") }
        #expect(viewModel.gaps.isEmpty)
        #expect(
            viewModel.statuses.map(\.id)
                == ["new4", "new3", "new2", "new1", "old2", "old1"]
        )
    }

    @Test @MainActor func timelinePageSessionsKeepIndependentAnchors() {
        let store = TimelinePageSessionStore()
        let home = store.session(for: .home)
        let local = store.session(for: .local)

        home.recordContentOffset(420)
        local.recordContentOffset(840)
        home.updateVisibility(statusID: "home-2", index: 2, isVisible: true)
        home.updateVisibility(statusID: "home-1", index: 1, isVisible: true)
        local.updateVisibility(statusID: "local-4", index: 4, isVisible: true)
        home.commitVisibleAnchor(for: .idle)
        local.commitVisibleAnchor(for: .idle)
        home.freezeVisibility()
        home.updateVisibility(statusID: "home-1", index: 1, isVisible: false)
        home.updateVisibility(statusID: "home-9", index: 9, isVisible: true)

        #expect(store.session(for: .home) === home)
        #expect(store.session(for: .local) === local)
        #expect(home.contentOffsetY == 420)
        #expect(local.contentOffsetY == 840)
        #expect(home.topVisibleStatusID == "home-1")
        #expect(local.topVisibleStatusID == "local-4")

        home.resumeVisibilityTracking()
        home.updateVisibility(statusID: "home-9", index: 9, isVisible: true)
        home.commitVisibleAnchor(for: .idle)
        #expect(home.topVisibleStatusID == "home-9")
    }

    @Test @MainActor func timelineDetectionDeduplicatesEventsAndResetsAcrossAccounts() {
        let manager = TimelineDetectionManager.shared
        let api = MockMastodonAPI()
        manager.configure(apiClient: api, scopeID: "account-a")
        manager.clearAllCounts()

        manager.incrementCount(for: .following, latestID: "status-1")
        manager.incrementCount(for: .following, latestID: "status-1")
        manager.flushPendingCounts()

        #expect(manager.newItemsCounts[.following] == 1)

        let snapshot = manager.snapshot(for: .following)
        manager.incrementCount(for: .following, latestID: "status-2")
        manager.flushPendingCounts()
        manager.resolve(snapshot)
        #expect(manager.newItemsCounts[.following] == 1)

        manager.configure(apiClient: api, scopeID: "account-b")
        #expect(manager.newItemsCounts[.following] == 0)
        #expect(manager.newItemsCounts[.local] == 0)
        #expect(manager.newItemsCounts[.federated] == 0)
    }

    @Test @MainActor func streamWatcherPublishesEveryRapidEvent() {
        let watcher = StreamWatcher.shared
        var receivedIDs: [String] = []
        let cancellable = watcher.events.sink { receivedIDs.append($0.id) }
        defer { cancellable.cancel() }

        watcher.emitPostEvent(for: makeStatus(id: "rapid-1"))
        watcher.emitEditEvent(for: makeStatus(id: "rapid-2"))
        watcher.emitDeleteEvent(for: "rapid-3")

        #expect(receivedIDs.count == 3)
        #expect(receivedIDs[0] == "update_rapid-1")
        #expect(receivedIDs[1].hasPrefix("edit_rapid-2_"))
        #expect(receivedIDs[2].hasPrefix("delete_rapid-3_"))
    }

    @Test @MainActor func composeNewPostPublishesCreatedPostEvent() async throws {
        let api = MockMastodonAPI()
        let coordinator = FeedCoordinator.shared
        api.postStatusHandler = { text, _, _, _, _, _, _, _, _ in
            self.makeStatus(id: "created-1", content: text)
        }
        let viewModel = ComposeViewModel(
            context: .newPost,
            apiClient: api,
            feedCoordinator: coordinator
        )
        viewModel.content = "New post"

        _ = try await viewModel.publish()

        guard case .createdPost(let status)? = coordinator.mostRecentUpdate else {
            Issue.record("Expected a created post event")
            return
        }
        #expect(status.id == "created-1")
    }

    // MARK: - Compose instance character limit

    @Test @MainActor func composeLoadInstanceLimitsAppliesInstanceMaxCharacters() async {
        let api = MockMastodonAPI()
        api.fetchInstanceV2Handler = {
            MastodonInstanceV2(
                domain: "x", title: "X", description: nil, thumbnail: nil, contact: nil,
                registrations: nil, rules: nil, languages: nil,
                configuration: InstanceConfiguration(statuses: .init(maxCharacters: 5000))
            )
        }
        let viewModel = ComposeViewModel(context: .newPost, apiClient: api)
        #expect(viewModel.maxCharacters == 500)  // default before the fetch

        await viewModel.loadInstanceLimits()

        #expect(viewModel.maxCharacters == 5000)  // raised from the instance configuration
    }

    @Test @MainActor func composeReusesCachedInstanceCharacterLimit() async {
        let api = MockMastodonAPI()
        api.instanceMetadataCacheKey = "test://\(UUID().uuidString)"
        api.fetchInstanceV2Handler = {
            MastodonInstanceV2(
                domain: "x", title: "X", description: nil, thumbnail: nil, contact: nil,
                registrations: nil, rules: nil, languages: nil,
                configuration: InstanceConfiguration(statuses: .init(maxCharacters: 5000))
            )
        }

        let firstViewModel = ComposeViewModel(context: .newPost, apiClient: api)
        await firstViewModel.loadInstanceLimits()
        let secondViewModel = ComposeViewModel(context: .newPost, apiClient: api)
        await secondViewModel.loadInstanceLimits()

        #expect(firstViewModel.maxCharacters == 5000)
        #expect(secondViewModel.maxCharacters == 5000)
        #expect(api.fetchInstanceV2CallCount == 1)
    }

    @Test @MainActor func instanceMetadataStoreRestoresFreshDiskCacheWithoutRefetching() async throws {
        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "instance-metadata-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let api = MockMastodonAPI()
        api.instanceMetadataCacheKey = "https://cache.example"
        api.fetchInstanceV2Handler = {
            MastodonInstanceV2(
                domain: "cache.example", title: "Cache", description: nil,
                thumbnail: nil, contact: nil, registrations: nil, rules: nil,
                languages: nil,
                configuration: InstanceConfiguration(statuses: .init(maxCharacters: 4096)),
                version: "4.4.0"
            )
        }

        let firstStore = InstanceMetadataStore(cacheDirectory: cacheRoot)
        _ = try await firstStore.load(apiClient: api)

        let restoredStore = InstanceMetadataStore(cacheDirectory: cacheRoot)
        let restored = try await restoredStore.load(apiClient: api)

        #expect(restored.domain == "cache.example")
        #expect(restored.version == "4.4.0")
        #expect(restored.configuration?.statuses?.maxCharacters == 4096)
        #expect(api.fetchInstanceV2CallCount == 1)
    }

    @Test @MainActor func emojiCatalogDiskCacheMigratesLegacyUserDefaults() throws {
        let suiteName = "emoji-cache-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(
            "emoji-catalog-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: cacheRoot) }

        let domain = "emoji.example"
        let emoji = CustomEmoji(
            shortcode: "wave",
            url: URL(string: "https://emoji.example/wave.gif")!,
            staticURL: URL(string: "https://emoji.example/wave.png")!,
            visibleInPicker: true,
            category: "People"
        )
        defaults.set(
            try JSONEncoder().encode([emoji]),
            forKey: "emoji_cache_\(domain)"
        )

        let migrated = EmojiCatalogDiskCache.load(
            domain: domain,
            cacheDirectory: cacheRoot,
            legacyUserDefaults: defaults
        )
        let restored = EmojiCatalogDiskCache.load(
            domain: domain,
            cacheDirectory: cacheRoot,
            legacyUserDefaults: defaults
        )

        #expect(migrated?.emojis == [emoji])
        #expect(restored?.emojis == [emoji])
        #expect(defaults.data(forKey: "emoji_cache_\(domain)") == nil)
    }

    @Test @MainActor func memoryPressureFlushesSoftCaches() {
        let cm = CacheManager.shared
        cm.accountCache.set(makeAccount(id: "mem-pressure-1"))
        #expect(cm.accountCache.count >= 1)

        // A non-critical warning drops the soft caches (account/thread + image memory).
        cm.handleMemoryPressure(critical: false)

        #expect(cm.accountCache.count == 0)
    }

    @Test @MainActor func videoPlayerObserverReleasesWhenOwnerDropsLastReference() async {
        weak var releasedObserver: VideoPlayerObserver?
        var observer: VideoPlayerObserver? = VideoPlayerObserver()
        observer?.setPlayer(
            url: URL(fileURLWithPath: "/tmp/moro-video-lifetime-test.mp4"),
            isGIF: false
        )
        releasedObserver = observer

        observer = nil
        await Task.yield()

        #expect(releasedObserver == nil)
    }

    @Test @MainActor func postMenuRelationshipCacheEvictsLeastRecentlyUsedAccount() async {
        let api = MockMastodonAPI()
        api.fetchRelationshipsHandler = { ids in
            ids.map { self.makeRelationship(id: $0) }
        }
        let center = PostMenuActionCenter(apiClient: api, relationshipCacheLimit: 2)
        let alice = makeStatus(id: "alice-status", account: makeAccount(id: "alice"))
        let bob = makeStatus(id: "bob-status", account: makeAccount(id: "bob"))
        let charlie = makeStatus(id: "charlie-status", account: makeAccount(id: "charlie"))

        _ = center.handlers(for: alice, onReport: { _ in })
        await waitUntil(timeout: 1) { api.fetchRelationshipsCallIDs.count == 1 }
        _ = center.handlers(for: bob, onReport: { _ in })
        await waitUntil(timeout: 1) { api.fetchRelationshipsCallIDs.count == 2 }

        // Refresh Alice's recency before adding Charlie, so Bob is the LRU entry.
        _ = center.handlers(for: alice, onReport: { _ in })
        _ = center.handlers(for: charlie, onReport: { _ in })
        await waitUntil(timeout: 1) { api.fetchRelationshipsCallIDs.count == 3 }

        _ = center.handlers(for: bob, onReport: { _ in })
        await waitUntil(timeout: 1) { api.fetchRelationshipsCallIDs.count == 4 }

        #expect(api.fetchRelationshipsCallIDs == ["alice", "bob", "charlie", "bob"])
    }

    @Test @MainActor func bookmarkRemovalKeepsFailedItemAvailableForRetry() async {
        let api = MockMastodonAPI()
        let first = makeStatus(id: "bookmark-1")
        let second = makeStatus(id: "bookmark-2")
        api.fetchBookmarkedStatusesHandler = { _, _, _ in [first, second] }
        api.unbookmarkStatusHandler = { _ in throw MockMastodonAPI.MockError.forcedFailure }

        let viewModel = BookmarksViewModel(apiClient: api)
        await viewModel.loadInitial()
        await viewModel.removeBookmark(first)

        #expect(viewModel.statuses.map(\.id) == [first.id, second.id])
        #expect(api.unbookmarkStatusCallIDs == [first.id])
        #expect(viewModel.transientErrorMessage == MoroL10n.BookmarksVM.removeFailedDetail)
        #expect(viewModel.removingIDs.isEmpty)

        api.unbookmarkStatusHandler = { _ in first }
        await viewModel.removeBookmark(first)

        #expect(viewModel.statuses.map(\.id) == [second.id])
        #expect(api.unbookmarkStatusCallIDs == [first.id, first.id])
        #expect(viewModel.transientErrorMessage == nil)
    }

    @Test @MainActor func currentAccountSynchronizesServerPrivacyPreferences() {
        let settings = AppSettings.shared
        let previous = (
            settings.manuallyApproveFollowRequests,
            settings.showFollowersAndFollowing,
            settings.suggestMyAccountToOthers,
            settings.appearInSearchEngines,
            settings.defaultPostVisibility,
            settings.serverDefaultPostLanguage
        )
        defer {
            settings.manuallyApproveFollowRequests = previous.0
            settings.showFollowersAndFollowing = previous.1
            settings.suggestMyAccountToOthers = previous.2
            settings.appearInSearchEngines = previous.3
            settings.defaultPostVisibility = previous.4
            settings.serverDefaultPostLanguage = previous.5
        }

        let account = makeAccount(
            id: "privacy-account",
            source: Account.Source(
                language: "fr",
                privacy: "private",
                hideCollections: true,
                discoverable: false,
                indexable: true
            ),
            locked: true
        )

        let appState = AppState()
        appState.currentAccount = account

        #expect(settings.manuallyApproveFollowRequests)
        #expect(!settings.showFollowersAndFollowing)
        #expect(!settings.suggestMyAccountToOthers)
        #expect(settings.appearInSearchEngines)
        #expect(settings.defaultPostVisibility == .followersOnly)
        #expect(settings.serverDefaultPostLanguage == "fr")
    }

    func makeAccount(
        id: String = "account",
        username: String? = nil,
        displayName: String? = nil,
        note: String = "",
        avatar: String = "",
        avatarStatic: String = "",
        header: String = "",
        headerStatic: String = "",
        fields: [AccountField] = [],
        emojis: [Account.Emoji] = [],
        url: String? = nil,
        source: Account.Source? = nil,
        locked: Bool = false,
        showMedia: Bool? = nil,
        showMediaReplies: Bool? = nil
    ) -> Account {
        let resolvedUsername = username ?? "user_\(id)"
        return Account(
            id: id,
            username: resolvedUsername,
            acct: "\(resolvedUsername)@example.com",
            displayName: displayName ?? "User \(id)",
            note: note,
            avatar: avatar,
            avatarStatic: avatarStatic,
            header: header,
            headerStatic: headerStatic,
            followersCount: 0,
            followingCount: 0,
            statusesCount: 0,
            locked: locked,
            fields: fields,
            emojis: emojis,
            url: url ?? "https://example.com/@\(resolvedUsername)",
            source: source,
            showMedia: showMedia,
            showMediaReplies: showMediaReplies
        )
    }

    func makeRelationship(
        id: String,
        following: Bool = false,
        followedBy: Bool = false,
        blocking: Bool = false,
        blockedBy: Bool = false,
        muting: Bool = false,
        mutingNotifications: Bool = false,
        requested: Bool = false,
        domainBlocking: Bool = false,
        endorsed: Bool = false,
        notifying: Bool = false,
        note: String? = nil
    ) -> Relationship {
        Relationship(
            id: id,
            following: following,
            followedBy: followedBy,
            blocking: blocking,
            blockedBy: blockedBy,
            muting: muting,
            mutingNotifications: mutingNotifications,
            requested: requested,
            domainBlocking: domainBlocking,
            endorsed: endorsed,
            notifying: notifying,
            note: note
        )
    }

    func makeConversation(
        id: String,
        unread: Bool,
        accounts: [Account] = [],
        lastStatus: Status?,
        updatedAt: Date? = nil
    ) -> Conversation {
        Conversation(
            id: id,
            unread: unread,
            accounts: accounts,
            lastStatus: lastStatus,
            updatedAt: updatedAt
        )
    }

    func makeStatus(
        id: String,
        createdAt: Date = Date(),
        content: String? = nil,
        account: Account? = nil,
        mediaAttachments: [Status.Attachment] = [],
        favouritesCount: Int = 0,
        reblogsCount: Int = 0,
        repliesCount: Int = 0,
        bookmarked: Bool = false,
        favourited: Bool = false,
        reblogged: Bool = false,
        reblog: Indirect<Status>? = nil,
        quote: Status.Quote? = nil,
        inReplyToID: String? = nil,
        spoilerText: String? = nil,
        visibility: String? = nil,
        language: String? = nil,
        poll: Status.Poll? = nil,
        mentions: [Status.Mention]? = nil,
        tags: [Status.Tag]? = nil,
        filtered: [Status.FilterResult]? = nil,
        pinned: Bool? = nil,
        card: Status.PreviewCard? = nil
    ) -> Status {
        Status(
            id: id,
            content: content ?? "status-\(id)",
            createdAt: createdAt,
            account: account ?? makeAccount(id: "acct-\(id)"),
            mediaAttachments: mediaAttachments,
            favouritesCount: favouritesCount,
            reblogsCount: reblogsCount,
            repliesCount: repliesCount,
            bookmarked: bookmarked,
            favourited: favourited,
            reblogged: reblogged,
            reblog: reblog,
            quote: quote,
            inReplyToID: inReplyToID,
            spoilerText: spoilerText,
            visibility: visibility,
            language: language,
            mentions: mentions,
            tags: tags,
            card: card,
            poll: poll,
            filtered: filtered,
            pinned: pinned
        )
    }

    func makeNotification(
        id: String,
        type: String,
        groupKey: String? = nil,
        createdAt: Date = Date(),
        account: Account? = nil,
        status: Status? = nil,
        fallback: NotificationFallback? = nil,
        collection: NotificationCollectionSummary? = nil
    ) -> NotificationItem {
        NotificationItem(
            id: id,
            type: type,
            groupKey: groupKey,
            createdAt: createdAt,
            account: account ?? makeAccount(id: "acct-\(id)"),
            status: status,
            fallback: fallback,
            collection: collection
        )
    }

    func makeComposeMediaAttachment(
        id: String,
        url: URL = URL(string: "https://example.com/\(UUID().uuidString).png")!,
        state: MediaAttachment.UploadState
    ) -> MediaAttachment {
        MediaAttachment(
            id: id,
            url: url,
            previewURL: nil,
            type: "image",
            description: nil,
            focus: nil,
            uploadState: state
        )
    }

    @MainActor
    func waitUntil(timeout: TimeInterval, condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}

struct MockAccountStatusesCall {
    let id: String
    let maxID: String?
    let limit: Int
    let excludeReplies: Bool
    let excludeReblogs: Bool
    let onlyMedia: Bool
    let pinned: Bool
}

struct MockUpdateAccountProfileCall {
    let displayName: String?
    let note: String?
    let avatar: AccountProfileImageUpload?
    let header: AccountProfileImageUpload?
    let removeAvatar: Bool
    let removeHeader: Bool
    let fields: [AccountField]?
}

@MainActor
private final class BadgeValueRecorder {
    private(set) var values: [Int] = []

    func set(_ value: Int) async {
        values.append(value)
    }
}

final class MockMastodonAPI: MastodonAPI {
    var ownFeaturedTagsHandler: (() async throws -> [FeaturedTag])?
    var unfeatureTagHandler: ((String) async throws -> Void)?
    func fetchOwnFeaturedTags() async throws -> [FeaturedTag] {
        try await ownFeaturedTagsHandler?() ?? []
    }
    func unfeatureTag(id: String) async throws {
        guard let unfeatureTagHandler else { throw MockError.unimplemented }
        try await unfeatureTagHandler(id)
    }
    var profileDisplayUpdateHandler: ((ProfileDisplayUpdate) async throws -> EditableProfile)?
    var credentialsUpdateHandler: ((Bool?) async throws -> Account)?
    func updateProfileDisplay(_ update: ProfileDisplayUpdate) async throws -> EditableProfile {
        guard let profileDisplayUpdateHandler else { throw MockError.unimplemented }
        return try await profileDisplayUpdateHandler(update)
    }
    var fetchEditableProfileHandler: (() async throws -> EditableProfile)?
    var accountFeaturedTagsHandler: ((String) async throws -> [FeaturedTag])?
    var taggedStatusesHandler: ((String, String?, String?, Bool) async throws -> [Status])?
    var taggedStatusesCalls: [(id: String, tag: String?, maxID: String?, pinned: Bool)] = []

    func fetchEditableProfile() async throws -> EditableProfile {
        guard let fetchEditableProfileHandler else { throw MockError.unimplemented }
        return try await fetchEditableProfileHandler()
    }
    func fetchAccountFeaturedTags(accountID: String) async throws -> [FeaturedTag] {
        try await accountFeaturedTagsHandler?(accountID) ?? []
    }
    func fetchAccountStatuses(id: String, maxID: String?, sinceID: String?, limit: Int,
        excludeReplies: Bool, excludeReblogs: Bool, onlyMedia: Bool, pinned: Bool, tagged: String?) async throws -> [Status] {
        taggedStatusesCalls.append((id, tagged, maxID, pinned))
        if let taggedStatusesHandler { return try await taggedStatusesHandler(id, tagged, maxID, pinned) }
        guard tagged == nil else { throw MockError.unimplemented }
        return try await fetchAccountStatuses(id: id, maxID: maxID, sinceID: sinceID, limit: limit,
            excludeReplies: excludeReplies, excludeReblogs: excludeReblogs, onlyMedia: onlyMedia, pinned: pinned)
    }

    func fetchTag(name: String) async throws -> SearchTag { throw MockError.unimplemented }
    func setTagFollowed(name: String, followed: Bool) async throws -> SearchTag { throw MockError.unimplemented }
    func fetchFollowedTags(maxID: String?, limit: Int) async throws -> FollowedTagsPage { throw MockError.unimplemented }

    enum MockError: Error {
        case unimplemented
        case forcedFailure
    }

    var instanceMetadataCacheKey: String?
    var fetchConversationsCallCount = 0
    var fetchInstanceV2CallCount = 0
    var searchCallOffsets: [Int] = []
    var searchCallTypes: [MastodonSearchType?] = []
    var searchCallLimits: [Int] = []
    var uploadMediaHandler: ((Data, String, String?) async throws -> Status.Attachment)?
    var fetchStatusDetailCallIDs: [String] = []
    var fetchStatusContextCallIDs: [String] = []
    var fetchNotificationsHandler:
        ((String?, String?, Int, MastodonNotificationScope) async throws -> [NotificationItem])?
    var fetchNotificationHandler: ((String) async throws -> NotificationItem)?
    var fetchUnreadNotificationCountHandler: (() async throws -> Int)?
    var fetchNotificationPolicyHandler: (() async throws -> ServerNotificationPolicy)?
    var updateNotificationPolicyHandler:
        ((ServerNotificationPolicy) async throws -> ServerNotificationPolicy)?
    var fetchMarkersHandler: (([MarkerTimeline]) async throws -> Marker)?
    var saveMarkerHandler: ((String?, String?) async throws -> Marker)?
    var fetchRelationshipsHandler: (([String]) async throws -> [Relationship])?
    var authorizeFollowRequestHandler: ((String) async throws -> Relationship)?
    var rejectFollowRequestHandler: ((String) async throws -> Relationship)?
    var fetchRelationshipsCallIDs: [String] = []
    var fetchConversationsHandler: ((String?, String?, Int) async throws -> [Conversation])?
    var fetchConversationsPageHandler: ((String?, Int) async throws -> ConversationsPage)?
    var fetchHomeTimelineHandler: ((String?, String?, Int) async throws -> [Status])?
    var fetchBookmarkedStatusesHandler: ((String?, String?, Int) async throws -> [Status])?
    var fetchPublicTimelineHandler: ((Bool, String?, String?, String?, Int) async throws -> [Status])?
    var fetchAccountStatusesHandler:
        ((String, String?, String?, Int, Bool, Bool, Bool, Bool) async throws -> [Status])?
    var fetchAccountStatusesCalls: [MockAccountStatusesCall] = []
    var fetchAccountFollowersHandler: ((String, String?, Int) async throws -> [Account])?
    var fetchAccountFollowingHandler: ((String, String?, Int) async throws -> [Account])?
    var fetchAccountFollowersCalls: [(id: String, maxID: String?, limit: Int)] = []
    var fetchAccountFollowingCalls: [(id: String, maxID: String?, limit: Int)] = []
    var searchHandler: ((String, MastodonSearchType?, Bool, Int, Int?) async throws -> SearchResults)?
    var fetchStatusDetailHandler: ((String) async throws -> Status)?
    var fetchStatusSourceHandler: ((String) async throws -> StatusSource)?
    var fetchStatusContextHandler: ((String) async throws -> StatusContext)?
    var verifyCredentialsHandler: (() async throws -> Account)?
    var updateAccountProfileHandler:
        ((
            String?,
            String?,
            AccountProfileImageUpload?,
            AccountProfileImageUpload?,
            Bool,
            Bool,
            [AccountField]?
        ) async throws -> Account)?
    var updateAccountProfileCalls: [MockUpdateAccountProfileCall] = []
    var translateStatusHandler: ((String, String?) async throws -> StatusTranslationPayload)?
    var fetchMutedAccountsHandler: ((String?, String?, Int?) async throws -> [Account])?
    var fetchBlockedAccountsHandler: ((String?, String?, Int?) async throws -> [Account])?
    var followAccountHandler: ((String, Bool?, Bool?) async throws -> Relationship)?
    var unfollowAccountHandler: ((String) async throws -> Relationship)?
    var followAccountCallIDs: [String] = []
    var unfollowAccountCallIDs: [String] = []
    var unmuteAccountHandler: ((String) async throws -> Relationship)?
    var unblockAccountHandler: ((String) async throws -> Relationship)?
    var favouriteStatusHandler: ((String) async throws -> Status)?
    var unfavouriteStatusHandler: ((String) async throws -> Status)?
    var reblogStatusHandler: ((String) async throws -> Status)?
    var unreblogStatusHandler: ((String) async throws -> Status)?
    var unbookmarkStatusHandler: ((String) async throws -> Status)?
    var unbookmarkStatusCallIDs: [String] = []
    var postStatusHandler:
        ((
            String,
            MastodonVisibility,
            [String]?,
            String?,
            String?,
            Bool?,
            String?,
            String?,
            StatusPollPayload?
        ) async throws -> Status)?
    var editStatusHandler:
        ((
            String,
            String,
            MastodonVisibility,
            [String]?,
            String?,
            String?,
            Bool?,
            String?,
            String?,
            StatusPollPayload?
        ) async throws -> Status)?
    var publishStatusResultHandler:
        ((
            String,
            MastodonVisibility,
            [String]?,
            String?,
            String?,
            Bool?,
            String?,
            String?,
            Date?,
            StatusPollPayload?
        ) async throws -> StatusPublishResult)?

    func fetchInstance() async throws -> MastodonInstance { throw MockError.unimplemented }
    var fetchInstanceV2Handler: (() async throws -> MastodonInstanceV2)?
    func fetchInstanceV2() async throws -> MastodonInstanceV2 {
        fetchInstanceV2CallCount += 1
        if let fetchInstanceV2Handler { return try await fetchInstanceV2Handler() }
        throw MockError.unimplemented
    }
    func createOAuthApp(clientName: String, redirectURIs: String, scopes: String, website: String?)
        async throws -> OAuthApp
    {
        throw MockError.unimplemented
    }
    func exchangeOAuthToken(
        code: String, clientID: String, clientSecret: String, redirectURI: String,
        codeVerifier: String?
    ) async throws -> OAuthTokenResponse {
        throw MockError.unimplemented
    }
    func verifyCredentials() async throws -> Account {
        if let verifyCredentialsHandler { return try await verifyCredentialsHandler() }
        throw MockError.unimplemented
    }
    var fetchAccountHandler: ((String) async throws -> Account)?
    func fetchAccount(id: String) async throws -> Account {
        if let fetchAccountHandler { return try await fetchAccountHandler(id) }
        throw MockError.unimplemented
    }
    func lookupAccount(acct: String) async throws -> Account { throw MockError.unimplemented }
    func fetchAccountStatuses(
        id: String,
        maxID: String?,
        sinceID: String?,
        limit: Int,
        excludeReplies: Bool,
        excludeReblogs: Bool,
        onlyMedia: Bool,
        pinned: Bool
    ) async throws -> [Status] {
        fetchAccountStatusesCalls.append(
            MockAccountStatusesCall(
                id: id,
                maxID: maxID,
                limit: limit,
                excludeReplies: excludeReplies,
                excludeReblogs: excludeReblogs,
                onlyMedia: onlyMedia,
                pinned: pinned
            )
        )
        if let fetchAccountStatusesHandler {
            return try await fetchAccountStatusesHandler(
                id,
                maxID,
                sinceID,
                limit,
                excludeReplies,
                excludeReblogs,
                onlyMedia,
                pinned
            )
        }
        throw MockError.unimplemented
    }
    func fetchAccountFollowers(id: String, maxID: String?, limit: Int) async throws -> [Account] {
        fetchAccountFollowersCalls.append((id: id, maxID: maxID, limit: limit))
        if let fetchAccountFollowersHandler {
            return try await fetchAccountFollowersHandler(id, maxID, limit)
        }
        throw MockError.unimplemented
    }
    func fetchAccountFollowing(id: String, maxID: String?, limit: Int) async throws -> [Account] {
        fetchAccountFollowingCalls.append((id: id, maxID: maxID, limit: limit))
        if let fetchAccountFollowingHandler {
            return try await fetchAccountFollowingHandler(id, maxID, limit)
        }
        throw MockError.unimplemented
    }
    func fetchRelationships(accountIDs: [String]) async throws -> [Relationship] {
        fetchRelationshipsCallIDs.append(contentsOf: accountIDs)
        if let fetchRelationshipsHandler {
            return try await fetchRelationshipsHandler(accountIDs)
        }
        throw MockError.unimplemented
    }
    func followAccount(id: String, reblogs: Bool?, notify: Bool?) async throws -> Relationship {
        followAccountCallIDs.append(id)
        if let followAccountHandler {
            return try await followAccountHandler(id, reblogs, notify)
        }
        throw MockError.unimplemented
    }
    func unfollowAccount(id: String) async throws -> Relationship {
        unfollowAccountCallIDs.append(id)
        if let unfollowAccountHandler {
            return try await unfollowAccountHandler(id)
        }
        throw MockError.unimplemented
    }
    func authorizeFollowRequest(accountID: String) async throws -> Relationship {
        if let authorizeFollowRequestHandler {
            return try await authorizeFollowRequestHandler(accountID)
        }
        throw MockError.unimplemented
    }
    func rejectFollowRequest(accountID: String) async throws -> Relationship {
        if let rejectFollowRequestHandler {
            return try await rejectFollowRequestHandler(accountID)
        }
        throw MockError.unimplemented
    }
    func muteAccount(id: String) async throws -> Relationship { throw MockError.unimplemented }
    func unmuteAccount(id: String) async throws -> Relationship {
        if let unmuteAccountHandler {
            return try await unmuteAccountHandler(id)
        }
        throw MockError.unimplemented
    }
    func blockAccount(id: String) async throws -> Relationship { throw MockError.unimplemented }
    func unblockAccount(id: String) async throws -> Relationship {
        if let unblockAccountHandler {
            return try await unblockAccountHandler(id)
        }
        throw MockError.unimplemented
    }
    func updateAccountCredentials(
        discoverable: Bool?,
        locked: Bool?,
        indexable: Bool?,
        hideCollections: Bool?,
        privacy: String?
    ) async throws -> Account {
        if let credentialsUpdateHandler { return try await credentialsUpdateHandler(hideCollections) }
        throw MockError.unimplemented
    }
    func updateAccountProfile(
        displayName: String?,
        note: String?,
        avatar: AccountProfileImageUpload?,
        header: AccountProfileImageUpload?,
        removeAvatar: Bool,
        removeHeader: Bool,
        fields: [AccountField]?
    ) async throws -> Account {
        updateAccountProfileCalls.append(
            MockUpdateAccountProfileCall(
                displayName: displayName,
                note: note,
                avatar: avatar,
                header: header,
                removeAvatar: removeAvatar,
                removeHeader: removeHeader,
                fields: fields
            )
        )
        if let updateAccountProfileHandler {
            return try await updateAccountProfileHandler(
                displayName,
                note,
                avatar,
                header,
                removeAvatar,
                removeHeader,
                fields
            )
        }
        throw MockError.unimplemented
    }
    func fetchHomeTimeline(maxID: String?, sinceID: String?, limit: Int) async throws -> [Status] {
        if let fetchHomeTimelineHandler {
            return try await fetchHomeTimelineHandler(maxID, sinceID, limit)
        }
        throw MockError.unimplemented
    }
    func fetchPublicTimeline(
        local: Bool,
        maxID: String?,
        sinceID: String?,
        minID: String?,
        limit: Int
    ) async throws -> [Status] {
        if let fetchPublicTimelineHandler {
            return try await fetchPublicTimelineHandler(local, maxID, sinceID, minID, limit)
        }
        throw MockError.unimplemented
    }
    func fetchHashtagTimeline(tag: String, maxID: String?, sinceID: String?, limit: Int)
        async throws -> [Status]
    {
        throw MockError.unimplemented
    }
    func search(
        query: String,
        type: MastodonSearchType?,
        resolve: Bool,
        limit: Int,
        offset: Int?
    ) async throws -> SearchResults {
        searchCallOffsets.append(offset ?? 0)
        searchCallTypes.append(type)
        searchCallLimits.append(limit)
        if let searchHandler {
            return try await searchHandler(query, type, resolve, limit, offset)
        }
        throw MockError.unimplemented
    }
    func fetchTrendingTags(limit: Int?) async throws -> [SearchTag] { throw MockError.unimplemented }
    func fetchTrendingStatuses(limit: Int?) async throws -> [Status] {
        throw MockError.unimplemented
    }
    func fetchDirectoryAccounts(
        limit: Int?,
        offset: Int?,
        order: MastodonDirectoryOrder?,
        local: Bool?
    ) async throws -> [Account] {
        throw MockError.unimplemented
    }
    func fetchAnnouncements() async throws -> [Announcement] {
        throw MockError.unimplemented
    }
    func dismissAnnouncement(id: String) async throws {
        throw MockError.unimplemented
    }
    func addAnnouncementReaction(id: String, name: String) async throws {
        throw MockError.unimplemented
    }
    func removeAnnouncementReaction(id: String, name: String) async throws {
        throw MockError.unimplemented
    }
    func fetchStatusDetail(id: String) async throws -> Status {
        fetchStatusDetailCallIDs.append(id)
        if let fetchStatusDetailHandler {
            return try await fetchStatusDetailHandler(id)
        }
        return Status(
            id: id,
            content: "status-\(id)",
            createdAt: Date(),
            account: Account(
                id: "acct-\(id)",
                username: "user_\(id)",
                acct: "user_\(id)@example.com",
                displayName: "User \(id)",
                note: "",
                avatar: "",
                avatarStatic: "",
                header: "",
                headerStatic: "",
                followersCount: 0,
                followingCount: 0,
                statusesCount: 0
            ),
            mediaAttachments: [],
            favouritesCount: 0,
            reblogsCount: 0,
            repliesCount: 0,
            bookmarked: false,
            favourited: false,
            reblogged: false
        )
    }
    func fetchStatusContext(id: String) async throws -> StatusContext {
        fetchStatusContextCallIDs.append(id)
        if let fetchStatusContextHandler {
            return try await fetchStatusContextHandler(id)
        }
        return StatusContext(ancestors: [], descendants: [])
    }
    func fetchStatusHistory(id: String) async throws -> [StatusEditHistoryItem] {
        throw MockError.unimplemented
    }
    func fetchStatusSource(id: String) async throws -> StatusSource {
        if let fetchStatusSourceHandler {
            return try await fetchStatusSourceHandler(id)
        }
        throw MockError.unimplemented
    }
    func translateStatus(id: String, targetLanguage: String?) async throws -> StatusTranslationPayload {
        if let translateStatusHandler {
            return try await translateStatusHandler(id, targetLanguage)
        }
        throw MockError.unimplemented
    }
    var fetchTranslationLanguagesHandler: (() async throws -> [String: [String]])?
    func fetchTranslationLanguages() async throws -> [String: [String]] {
        if let fetchTranslationLanguagesHandler {
            return try await fetchTranslationLanguagesHandler()
        }
        // Default matrix covering the languages exercised by the translation
        // tests (source → supported targets), mirroring an instance with a
        // translation backend.
        return [
            "ja": ["en", "zh-Hans", "fr"],
            "fr": ["en", "zh-Hans"],
            "de": ["en", "zh-Hans"],
            "zh": ["en", "fr"],
        ]
    }
    func postStatus(text: String, visibility: MastodonVisibility, mediaIDs: [String]) async throws
        -> Status
    {
        return try await postStatus(
            text: text,
            visibility: visibility,
            mediaIDs: mediaIDs,
            inReplyToID: nil,
            spoilerText: nil,
            sensitive: nil,
            quotingID: nil,
            language: nil,
            poll: nil
        )
    }
    func fetchNotifications(
        maxID: String?,
        sinceID: String?,
        limit: Int,
        scope: MastodonNotificationScope
    ) async throws
        -> [NotificationItem]
    {
        if let fetchNotificationsHandler {
            return try await fetchNotificationsHandler(maxID, sinceID, limit, scope)
        }
        throw MockError.unimplemented
    }
    func fetchUnreadNotificationCount() async throws -> Int {
        if let fetchUnreadNotificationCountHandler {
            return try await fetchUnreadNotificationCountHandler()
        }
        return 0
    }

    func fetchNotification(id: String) async throws -> NotificationItem {
        guard let fetchNotificationHandler else { throw MockError.unimplemented }
        return try await fetchNotificationHandler(id)
    }
    func fetchNotificationPolicy() async throws -> ServerNotificationPolicy {
        guard let fetchNotificationPolicyHandler else {
            throw APIError.http(statusCode: 404, data: nil)
        }
        return try await fetchNotificationPolicyHandler()
    }
    func updateNotificationPolicy(_ policy: ServerNotificationPolicy) async throws
        -> ServerNotificationPolicy
    {
        guard let updateNotificationPolicyHandler else {
            throw APIError.http(statusCode: 404, data: nil)
        }
        return try await updateNotificationPolicyHandler(policy)
    }
    func fetchScheduledStatuses(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [ScheduledStatus]
    {
        throw MockError.unimplemented
    }
    func cancelScheduledStatus(id: String) async throws { throw MockError.unimplemented }
    func fetchConversations(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Conversation]
    {
        fetchConversationsCallCount += 1
        if let fetchConversationsHandler {
            return try await fetchConversationsHandler(maxID, sinceID, limit)
        }
        return []
    }
    func fetchConversationsPage(maxID: String?, limit: Int) async throws -> ConversationsPage {
        if let fetchConversationsPageHandler {
            return try await fetchConversationsPageHandler(maxID, limit)
        }
        return ConversationsPage(
            conversations: try await fetchConversations(maxID: maxID, sinceID: nil, limit: limit),
            nextMaxID: nil
        )
    }
    func fetchBookmarkedPage(maxID: String?, limit: Int) async throws -> BookmarkedStatusesPage {
        BookmarkedStatusesPage(statuses: try await fetchBookmarkedStatuses(maxID: maxID, sinceID: nil, limit: limit), nextMaxID: nil)
    }

    func fetchBookmarkedStatuses(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Status]
    {
        if let fetchBookmarkedStatusesHandler {
            return try await fetchBookmarkedStatusesHandler(maxID, sinceID, limit)
        }
        throw MockError.unimplemented
    }
    func fetchFavouritedStatuses(maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Status]
    {
        throw MockError.unimplemented
    }
    func fetchLists() async throws -> [MastodonList] { throw MockError.unimplemented }
    func fetchAccountLists(accountID: String) async throws -> [MastodonList] { throw MockError.unimplemented }
    func createList(title: String, repliesPolicy: MastodonList.RepliesPolicy?) async throws
        -> MastodonList
    {
        throw MockError.unimplemented
    }
    func updateList(id: String, title: String, repliesPolicy: MastodonList.RepliesPolicy?) async throws
        -> MastodonList
    {
        throw MockError.unimplemented
    }
    func deleteList(id: String) async throws { throw MockError.unimplemented }
    func fetchListAccounts(listID: String, maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Account]
    {
        throw MockError.unimplemented
    }
    func addAccountsToList(listID: String, accountIDs: [String]) async throws {
        throw MockError.unimplemented
    }
    func removeAccountsFromList(listID: String, accountIDs: [String]) async throws {
        throw MockError.unimplemented
    }
    func fetchListTimeline(id: String, maxID: String?, sinceID: String?, limit: Int) async throws
        -> [Status]
    {
        throw MockError.unimplemented
    }
    func fetchPushSubscription() async throws -> PushSubscription {
        throw MockError.unimplemented
    }
    func createPushSubscription(
        endpoint: String, p256dh: String, auth: String,
        alerts: PushSubscription.Alerts, policy: String?
    ) async throws -> PushSubscription {
        throw MockError.unimplemented
    }
    func updatePushSubscription(alerts: PushSubscription.Alerts, policy: String?) async throws
        -> PushSubscription
    {
        throw MockError.unimplemented
    }
    func deletePushSubscription() async throws { throw MockError.unimplemented }
    func fetchFilters() async throws -> [ServerFilter] { throw MockError.unimplemented }
    func createFilter(
        title: String,
        keyword: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async throws -> ServerFilter {
        throw MockError.unimplemented
    }
    func updateFilter(
        id: String,
        title: String,
        contexts: [ServerFilter.Context],
        action: ServerFilter.Action
    ) async throws -> ServerFilter {
        throw MockError.unimplemented
    }
    func deleteFilter(id: String) async throws { throw MockError.unimplemented }
    func addFilterKeyword(filterID: String, keyword: String, wholeWord: Bool) async throws
        -> ServerFilter.Keyword
    {
        throw MockError.unimplemented
    }
    func updateFilterKeyword(keywordID: String, keyword: String, wholeWord: Bool) async throws
        -> ServerFilter.Keyword
    {
        throw MockError.unimplemented
    }
    func deleteFilterKeyword(keywordID: String) async throws { throw MockError.unimplemented }
    func fetchMutedAccounts(maxID: String?, sinceID: String?, limit: Int?) async throws -> [Account] {
        if let fetchMutedAccountsHandler {
            return try await fetchMutedAccountsHandler(maxID, sinceID, limit)
        }
        throw MockError.unimplemented
    }
    func fetchBlockedAccounts(maxID: String?, sinceID: String?, limit: Int?) async throws -> [Account] {
        if let fetchBlockedAccountsHandler {
            return try await fetchBlockedAccountsHandler(maxID, sinceID, limit)
        }
        throw MockError.unimplemented
    }
    func fetchDomainBlocks(maxID: String?, sinceID: String?, limit: Int?) async throws -> [String] {
        throw MockError.unimplemented
    }
    func blockDomain(_ domain: String) async throws { throw MockError.unimplemented }
    func unblockDomain(_ domain: String) async throws { throw MockError.unimplemented }
    func markConversationRead(id: String) async throws -> Conversation {
        throw MockError.unimplemented
    }
    func deleteConversation(id: String) async throws { throw MockError.unimplemented }
    func favouriteStatus(id: String) async throws -> Status {
        if let favouriteStatusHandler {
            return try await favouriteStatusHandler(id)
        }
        throw MockError.unimplemented
    }
    func unfavouriteStatus(id: String) async throws -> Status {
        if let unfavouriteStatusHandler {
            return try await unfavouriteStatusHandler(id)
        }
        throw MockError.unimplemented
    }
    func reblogStatus(id: String) async throws -> Status {
        if let reblogStatusHandler {
            return try await reblogStatusHandler(id)
        }
        throw MockError.unimplemented
    }
    func unreblogStatus(id: String) async throws -> Status {
        if let unreblogStatusHandler {
            return try await unreblogStatusHandler(id)
        }
        throw MockError.unimplemented
    }
    func bookmarkStatus(id: String) async throws -> Status { throw MockError.unimplemented }
    func unbookmarkStatus(id: String) async throws -> Status {
        unbookmarkStatusCallIDs.append(id)
        if let unbookmarkStatusHandler {
            return try await unbookmarkStatusHandler(id)
        }
        throw MockError.unimplemented
    }
    func votePoll(pollID: String, choices: [Int]) async throws -> Status.Poll {
        throw MockError.unimplemented
    }
    func uploadMedia(data: Data, mimeType: String, description: String?) async throws
        -> Status.Attachment
    {
        if let uploadMediaHandler {
            return try await uploadMediaHandler(data, mimeType, description)
        }
        throw MockError.unimplemented
    }
    func updateMedia(id: String, description: String?, focus: String?) async throws
        -> Status.Attachment
    {
        throw MockError.unimplemented
    }
    func fetchCustomEmojis() async throws -> [CustomEmoji] { throw MockError.unimplemented }
    func postStatus(
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        language: String?,
        poll: StatusPollPayload?
    ) async throws -> Status {
        if let postStatusHandler {
            return try await postStatusHandler(
                text,
                visibility,
                mediaIDs,
                inReplyToID,
                spoilerText,
                sensitive,
                quotingID,
                language,
                poll
            )
        }
        throw MockError.unimplemented
    }
    func editStatus(
        id: String,
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        language: String?,
        poll: StatusPollPayload?
    ) async throws -> Status {
        if let editStatusHandler {
            return try await editStatusHandler(
                id,
                text,
                visibility,
                mediaIDs,
                inReplyToID,
                spoilerText,
                sensitive,
                quotingID,
                language,
                poll
            )
        }
        throw MockError.unimplemented
    }
    var publishIdempotencyKeys: [String?] = []

    func publishStatus(
        text: String,
        visibility: MastodonVisibility,
        mediaIDs: [String]?,
        inReplyToID: String?,
        spoilerText: String?,
        sensitive: Bool?,
        quotingID: String?,
        quoteApprovalPolicy: MastodonQuoteApprovalPolicy?,
        language: String?,
        scheduledAt: Date?,
        poll: StatusPollPayload?,
        idempotencyKey: String?
    ) async throws -> StatusPublishResult {
        publishIdempotencyKeys.append(idempotencyKey)
        if let publishStatusResultHandler {
            return try await publishStatusResultHandler(
                text,
                visibility,
                mediaIDs,
                inReplyToID,
                spoilerText,
                sensitive,
                quotingID,
                language,
                scheduledAt,
                poll
            )
        }

        if scheduledAt == nil {
            let status = try await postStatus(
                text: text,
                visibility: visibility,
                mediaIDs: mediaIDs,
                inReplyToID: inReplyToID,
                spoilerText: spoilerText,
                sensitive: sensitive,
                quotingID: quotingID,
                language: language,
                poll: poll
            )
            return .posted(status)
        }

        throw MockError.unimplemented
    }
    func report(accountID: String, statusIDs: [String], comment: String) async throws -> ReportResponse
    {
        throw MockError.unimplemented
    }
    func deleteStatus(id: String) async throws { throw MockError.unimplemented }
    func pinStatus(id: String) async throws -> Status { throw MockError.unimplemented }
    func unpinStatus(id: String) async throws -> Status { throw MockError.unimplemented }
    func fetchMarkers(timelines: [MarkerTimeline]) async throws -> Marker {
        if let fetchMarkersHandler {
            return try await fetchMarkersHandler(timelines)
        }
        throw MockError.unimplemented
    }
    func saveMarker(home: String?, notifications: String?) async throws -> Marker {
        if let saveMarkerHandler {
            return try await saveMarkerHandler(home, notifications)
        }
        throw MockError.unimplemented
    }
}
