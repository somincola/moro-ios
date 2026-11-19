import Foundation
import Testing
@testable import moro

extension moroTests {
    @Test @MainActor func memberSearchDebouncesAndDiscardsStaleErrorsEvenForTheSameQuery() async {
        let api = MockMastodonAPI()
        let model = ListMembersViewModel(apiClient: api, listID: "list")
        let (started, signal) = AsyncStream<Void>.makeStream()
        let (release, resume) = AsyncStream<Void>.makeStream()
        var calls: [String] = []
        let match = makeAccount(id: "latest")
        api.searchFollowedAccountsHandler = { query, limit in
            calls.append(query)
            #expect(limit == 20)
            if calls.count == 1 {
                signal.yield(())
                for await _ in release { break }
                throw APIError.cancelled
            }
            return [match]
        }

        model.searchQuery = "ne"
        let abandoned = model.searchRequest
        let debounce = Task { await model.search(abandoned) }
        debounce.cancel()
        await debounce.value
        #expect(calls.isEmpty)

        model.searchQuery = "needle"
        let firstRequest = model.searchRequest
        let slow = Task { await model.search(firstRequest) }
        for await _ in started { break }
        model.searchQuery = "needles"
        model.searchQuery = "needle"
        await model.search(model.searchRequest)
        resume.yield(())
        await slow.value
        #expect(calls == ["needle", "needle"])
        guard case .results(let accounts) = model.searchState else {
            Issue.record("A superseded error replaced the active results")
            return
        }
        #expect(accounts.map(\.id) == ["latest"])
    }

    @Test @MainActor func changingOrRetryingMemberSearchClearsTheCurrentFailure() async {
        let api = MockMastodonAPI()
        let model = ListMembersViewModel(apiClient: api, listID: "list")
        api.searchFollowedAccountsHandler = { _, _ in throw APIError.networkUnavailable }
        model.searchQuery = "林"
        await model.search(model.searchRequest)
        guard case .failed = model.searchState else { Issue.record("The current failure needs a retry"); return }
        api.searchFollowedAccountsHandler = { _, _ in [] }
        model.retrySearch()
        guard case .searching = model.searchState else { Issue.record("Retry must clear the error immediately"); return }
        await model.search(model.searchRequest)
        guard case .results(let accounts) = model.searchState else { Issue.record("Successful retry must replace the error"); return }
        #expect(accounts.isEmpty)
        model.searchQuery = " "
        guard case .idle = model.searchState else { Issue.record("Clearing search must show the member list"); return }
    }

    @Test @MainActor func memberEditsSurviveOverlappingReadsAndOnlyLockThePendingAccount() async {
        let api = MockMastodonAPI()
        let model = ListMembersViewModel(apiClient: api, listID: "list")
        let added = makeAccount(id: "new")
        let existing = makeAccount(id: "existing")
        let (readStarted, signalRead) = AsyncStream<Void>.makeStream()
        let (releaseRead, resumeRead) = AsyncStream<Void>.makeStream()
        let (writeStarted, signalWrite) = AsyncStream<Void>.makeStream()
        let (releaseWrite, resumeWrite) = AsyncStream<Void>.makeStream()
        var adds = 0
        api.listAccountsHandler = { _, limit in
            #expect(limit == 0)
            return [existing]
        }
        await model.loadInitial()
        api.listAccountsHandler = { _, _ in
            signalRead.yield(())
            for await _ in releaseRead { break }
            return [existing]
        }
        api.addListAccountsHandler = { list, ids in
            adds += 1
            #expect(list == "list" && ids == ["new"])
            signalWrite.yield(())
            for await _ in releaseWrite { break }
        }
        api.removeListAccountsHandler = { _, _ in throw APIError.networkUnavailable }
        let read = Task { await model.refresh() }
        for await _ in readStarted { break }
        let write = Task { await model.setMembership(of: added, included: true) }
        for await _ in writeStarted { break }
        #expect(model.mutatingAccountIDs == ["new"])
        await model.setMembership(of: added, included: true)
        await model.setMembership(of: existing, included: false)
        #expect(model.mutationErrors["existing"] != nil)
        #expect(model.members.map(\.id) == ["existing"])
        api.removeListAccountsHandler = { _, _ in }
        await model.setMembership(of: existing, included: false)
        resumeWrite.yield(())
        await write.value
        resumeRead.yield(())
        await read.value
        #expect(adds == 1)
        #expect(model.members.map(\.id) == ["new"])
        #expect(model.mutatingAccountIDs.isEmpty && model.mutationErrors.isEmpty)
    }

    @Test func profileConnectionCountsUseCompactSuffixesAndLocalDecimalSeparators() {
        let english = Locale(identifier: "en_US")
        for (count, expected) in [(0, "0"), (998, "998"), (1_000, "1k"), (1_052, "1.1k"),
                                  (18_500, "18.5k"), (999_950, "1m"), (1_200_000, "1.2m")] {
            #expect(ProfileConnectionKind.compactCount(count, locale: english) == expected)
        }
        #expect(ProfileConnectionKind.compactCount(18_500, locale: Locale(identifier: "de_DE")) == "18,5k")
    }
}
