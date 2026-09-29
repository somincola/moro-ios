import Foundation
import Testing

@testable import moro

@Suite(.serialized)
@MainActor
struct ReportFlowTests {
    private let fixtures = moroTests()

    @Test func allReasonsUseTheCorrectStepsAndOnlySubmitAtTheEnd() async throws {
        for reason in ReportReason.allCases {
            let api = MockMastodonAPI()
            api.fetchInstanceHandler = { try instanceWithRules() }
            api.reportHandler = { _ in try response() }
            let model = ReportViewModel(
                apiClient: api, account: fixtures.makeAccount(), feedCoordinator: FeedCoordinator())
            #expect(!model.canProceedToNextStep)
            model.goToNextStep()
            #expect(model.currentStep == .reason)
            model.selectedReason = reason
            model.goToNextStep()
            if reason == .dislike {
                #expect(model.currentStep == .result)
                await model.submitReport()
                #expect(!model.isSubmitted)
                #expect(api.reportRequests.isEmpty)
                model.goToPreviousStep()
                #expect(model.currentStep == .reason)
                continue
            }
            if reason == .violation {
                #expect(model.currentStep == .rules)
                model.goToNextStep()
                #expect(model.currentStep == .rules)
                await model.prepareCurrentStep()
                model.toggleRuleSelection("not-a-rule")
                #expect(!model.canProceedToNextStep)
                model.toggleRuleSelection("1")
                model.toggleRuleSelection("2")
                #expect(model.selectedRuleIDs == ["1", "2"])
                model.goToNextStep()
            }
            #expect(model.currentStep == .selectPosts)
            #expect(model.selectedStatusIDs.isEmpty)
            #expect(model.canProceedToNextStep)
            #expect(api.reportRequests.isEmpty)
            // Attaching posts is optional, including account-level spam reports.
            model.goToNextStep()
            #expect(model.currentStep == .comment)
            #expect(api.reportRequests.isEmpty)
            await model.submitReport()
            #expect(model.isSubmitted)
            #expect(model.currentStep == .result)
            let request = try #require(api.reportRequests.first)
            #expect(request.category == reason.category)
            #expect(request.comment.isEmpty)
            #expect(request.statusIDs.isEmpty)
            #expect(request.ruleIDs == (reason == .violation ? ["1", "2"] : nil))
            model.goToPreviousStep()
            await model.submitReport()
            #expect(model.currentStep == .result)
            #expect(api.reportRequests.count == 1)
        }
    }

    @Test func rulesFailClosedAndRetryWhileBackNavigationPreservesTheDraft() async throws {
        let api = MockMastodonAPI()
        let account = fixtures.makeAccount()
        let status = fixtures.makeStatus(id: "initial", account: account)
        let model = ReportViewModel(apiClient: api, status: status, feedCoordinator: FeedCoordinator())
        model.selectedReason = .violation
        model.goToNextStep()
        await model.prepareCurrentStep()
        #expect(model.stepError?.context == .loadRules)
        #expect(!model.canProceedToNextStep)
        api.fetchInstanceHandler = { try instanceWithRules(empty: true) }
        await model.retryStepErrorAction()
        #expect(model.rules.isEmpty)
        #expect(!model.canProceedToNextStep)
        api.fetchInstanceHandler = { try instanceWithRules() }
        await model.loadRules()
        model.toggleRuleSelection("2")
        model.goToNextStep()
        model.goToNextStep()
        model.customComment = "  Additional context\n"
        model.goToPreviousStep()
        #expect(model.currentStep == .selectPosts)
        model.toggleStatusSelection(status.id)
        model.goToPreviousStep()
        #expect(model.currentStep == .rules)
        #expect(model.selectedRuleIDs == ["2"])
        model.goToPreviousStep()
        model.selectedReason = .other
        model.goToNextStep()
        model.goToNextStep()
        #expect(model.customComment == "  Additional context\n")
        model.customComment = String(repeating: "字", count: ReportViewModel.commentLimit + 1)
        await model.submitReport()
        #expect(api.reportRequests.isEmpty)
        model.customComment = "  Additional context\n"
        await model.submitReport()
        #expect(model.currentStep == .comment)
        #expect(model.stepError?.context == .submit)
        #expect(model.customComment == "  Additional context\n")
        api.reportHandler = { _ in try response() }
        await model.retryStepErrorAction()
        let request = try #require(api.reportRequests.last)
        #expect(request.category == .other)
        #expect(request.ruleIDs == nil)  // Previously selected rules must not change the category.
        #expect(request.comment == "Additional context")
        #expect(request.statusIDs.isEmpty)
        #expect(model.currentStep == .result)
        let body = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(body["account_id"] as? String == account.id)
        #expect(body["category"] as? String == "other")
        #expect(body["rule_ids"] == nil)
        #expect(body["comment"] as? String == "Additional context")
    }

    @Test func postPickerUsesOriginalAuthorAndFiltersDuplicatesAndBoosts() async throws {
        let api = MockMastodonAPI()
        let account = fixtures.makeAccount(id: "author")
        let original = fixtures.makeStatus(id: "original", account: account)
        let wrapper = fixtures.makeStatus(id: "wrapper", reblog: Indirect(original))
        let foreign = fixtures.makeStatus(id: "foreign")
        let foreignBoost = fixtures.makeStatus(
            id: "foreign-boost", account: account, reblog: Indirect(foreign))
        let model = ReportViewModel(apiClient: api, status: wrapper, feedCoordinator: FeedCoordinator())
        #expect(model.account.id == account.id)
        #expect(model.selectedStatusIDs == [original.id])
        let posts = (1...17).map { fixtures.makeStatus(id: "post-\($0)", account: account) }
        api.fetchAccountStatusesHandler = { id, cursor, _, _, _, excludeBoosts, _, _ in
            #expect(id == account.id)
            #expect(excludeBoosts)
            return cursor == nil ? [original, foreign, foreignBoost] + posts : [posts.last!, original]
        }
        await model.loadUserStatuses()
        #expect(model.userStatuses.count == 18)
        #expect(model.hasMoreStatuses)
        model.toggleStatusSelection(foreign.id)
        #expect(model.selectedStatusIDs == [original.id])
        model.toggleStatusSelection(posts[0].id)
        await model.loadUserStatuses(loadMore: true)
        #expect(model.userStatuses.count == 18)
        #expect(!model.hasMoreStatuses)
        #expect(api.fetchAccountStatusesCalls.last?.maxID == "post-17")
        api.fetchAccountStatusesHandler = { _, _, _, _, _, _, _, _ in
            throw MockMastodonAPI.MockError.forcedFailure
        }
        await model.loadUserStatuses()
        #expect(model.stepError?.context == .loadStatuses)
        #expect(model.selectedStatusIDs == [original.id, posts[0].id])
        #expect(model.userStatuses.count == 18)
    }

    @Test func submittingCannotDuplicateOrNavigateAwayWhileInFlight() async throws {
        let api = MockMastodonAPI()
        let (started, start) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        api.reportHandler = { _ in
            start.yield(())
            for await _ in released { break }
            return try response()
        }
        let model = ReportViewModel(
            apiClient: api, account: fixtures.makeAccount(), feedCoordinator: FeedCoordinator())
        model.selectedReason = .spam
        model.goToNextStep()
        model.goToNextStep()
        let submission = Task { await model.submitReport() }
        for await _ in started { break }
        #expect(model.isBusy)
        #expect(!model.canProceedToNextStep)
        model.goToPreviousStep()
        #expect(model.currentStep == .comment)
        await model.submitReport()
        #expect(api.reportRequests.count == 1)
        release.yield(())
        await submission.value
        #expect(model.currentStep == .result)
        #expect(!model.isBusy)
    }

    @Test func latePostLoadingFailureDoesNotReplaceTheSubmittedResult() async throws {
        let api = MockMastodonAPI()
        let (started, start) = AsyncStream<Void>.makeStream()
        let (released, release) = AsyncStream<Void>.makeStream()
        api.fetchAccountStatusesHandler = { _, _, _, _, _, _, _, _ in
            start.yield(())
            for await _ in released { break }
            throw MockMastodonAPI.MockError.forcedFailure
        }
        api.reportHandler = { _ in try response() }
        let model = ReportViewModel(
            apiClient: api, account: fixtures.makeAccount(), feedCoordinator: FeedCoordinator())
        model.selectedReason = .spam
        model.goToNextStep()
        let loading = Task { await model.loadUserStatuses() }
        for await _ in started { break }
        model.goToNextStep()
        await model.submitReport()
        release.yield(())
        await loading.value
        #expect(model.isSubmitted)
        #expect(model.currentStep == .result)
        #expect(model.stepError == nil)
    }

    @Test func optionalActionsOnlyUpdateAfterServerSuccessAndDoNotSendReports() async throws {
        let api = MockMastodonAPI()
        let account = fixtures.makeAccount()
        let coordinator = FeedCoordinator()
        let model = ReportViewModel(apiClient: api, account: account, feedCoordinator: coordinator)
        let profile = ProfileViewModel(apiClient: api, accountID: account.id, feedCoordinator: coordinator)
        let menu = PostMenuActionCenter(apiClient: api, feedCoordinator: coordinator)
        let timeline = TimelineViewModel(
            apiClient: api, feedCoordinator: coordinator,
            cacheClientID: "report-tests-\(UUID().uuidString)")
        let post = fixtures.makeStatus(id: "target-post", account: account)
        let boost = fixtures.makeStatus(id: "target-boost", reblog: Indirect(post))
        let otherPost = fixtures.makeStatus(id: "unrelated")
        timeline.statuses = [post, boost, otherPost]
        profile.relationship = fixtures.makeRelationship(id: account.id, following: true)
        api.fetchRelationshipsHandler = { _ in [fixtures.makeRelationship(id: account.id, following: true)] }
        model.selectedReason = .dislike
        model.goToNextStep()
        await model.prepareCurrentStep()
        #expect(model.relationship?.following == true)
        #expect(api.unfollowAccountCallIDs.isEmpty)
        await model.performAccountAction(.unfollow)
        #expect(model.relationship?.following == true)
        #expect(model.stepError?.context == .accountAction)
        #expect(coordinator.mostRecentUpdate == nil)
        api.unfollowAccountHandler = { id in fixtures.makeRelationship(id: id) }
        await model.performAccountAction(.unfollow)
        #expect(model.hasUnfollowed)
        #expect(profile.relationship?.following == false)
        await model.performAccountAction(.unfollow)
        #expect(api.unfollowAccountCallIDs.count == 2)  // Failed attempt + successful retry only.
        api.muteAccountHandler = { id in fixtures.makeRelationship(id: id, muting: true) }
        await model.performAccountAction(.mute)
        #expect(model.isActionCompleted(.mute))
        #expect(profile.relationship?.muting == true)
        #expect(timeline.statuses.map(\.id) == [otherPost.id])
        #expect(
            menu.handlers(for: post, prefetchRelationship: false, onReport: { _ in }).isMutingUser == true)
        api.blockAccountHandler = { id in fixtures.makeRelationship(id: id, blocking: true, muting: true) }
        await model.performAccountAction(.block)
        #expect(model.isActionCompleted(.block))
        #expect(profile.relationship?.blocking == true)
        #expect(
            menu.handlers(for: post, prefetchRelationship: false, onReport: { _ in }).isBlockingUser == true)
        #expect(!model.isSubmitted)
        #expect(api.reportRequests.isEmpty)
    }

    @Test func violationPayloadIncludesSelectedRulesAndPostIDs() throws {
        let request = ReportRequest(
            accountID: "author", statusIDs: ["post"], comment: "Details",
            category: .violation, ruleIDs: ["1", "2"])
        let body = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(body["account_id"] as? String == "author")
        #expect(body["status_ids"] as? [String] == ["post"])
        #expect(body["category"] as? String == "violation")
        #expect(body["rule_ids"] as? [String] == ["1", "2"])
        #expect(body["comment"] as? String == "Details")
    }

    private func instanceWithRules(empty: Bool = false) throws -> MastodonInstance {
        let rules = empty ? [] : [["id": "1", "text": "No spam"], ["id": "2", "text": "Be respectful"]]
        let data = try JSONSerialization.data(withJSONObject: [
            "uri": "example.com", "title": "Example", "description": "", "rules": rules,
        ])
        return try JSONDecoder().decode(MastodonInstance.self, from: data)
    }

    private func response() throws -> ReportResponse {
        try JSONDecoder().decode(ReportResponse.self, from: Data(#"{"id":"report"}"#.utf8))
    }
}
