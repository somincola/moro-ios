//
//  RelationshipStoreTests.swift
//  moroTests
//

import Combine
import Foundation
import Testing

@testable import moro

extension moroTests {
    @Test @MainActor func relationshipStoreKeepsEachSessionSeparateAndEvictsLeastRecent() {
        let store = RelationshipStore(limit: 2, updates: PassthroughSubject<UpdatedElement, Never>())
        store.store(makeRelationship(id: "a", following: true), scope: "one")
        store.store(makeRelationship(id: "a", following: false), scope: "two")
        #expect(store.relationship(for: "a", scope: "one")?.following == true)
        #expect(store.relationship(for: "a", scope: "two")?.following == false)

        // "one/a" was just read, so adding a third entry evicts "two/a".
        _ = store.relationship(for: "a", scope: "one")
        store.store(makeRelationship(id: "b"), scope: "one")
        #expect(store.relationship(for: "a", scope: "one") != nil)
        #expect(store.relationship(for: "a", scope: "two") == nil)
    }

    @Test @MainActor func relationshipStoreRecordsBroadcastChangesForTheActiveSession() {
        let updates = PassthroughSubject<UpdatedElement, Never>()
        let store = RelationshipStore(updates: updates)
        store.activeScope = "session"
        updates.send(.relationship(makeRelationship(id: "followed", following: true)))
        #expect(store.relationship(for: "followed", scope: "session")?.following == true)
    }

    @Test @MainActor func profileOpensOnTheLastKnownFollowStateThenRevalidates() async {
        let store = RelationshipStore(updates: PassthroughSubject<UpdatedElement, Never>())
        store.activeScope = "session"
        store.store(makeRelationship(id: "friend", following: true), scope: "session")
        let api = MockMastodonAPI()
        api.fetchRelationshipsHandler = { _ in [self.makeRelationship(id: "friend", following: false)] }

        let model = ProfileViewModel(
            apiClient: api, accountID: "friend", currentAccountID: "me", relationshipStore: store
        )
        // Known before any request: no "Follow" guess, no placeholder.
        #expect(model.isRelationshipResolved)
        #expect(model.relationship?.following == true)

        await model.loadRelationship()
        #expect(model.relationship?.following == false)
        #expect(store.relationship(for: "friend", scope: "session")?.following == false)
    }

    @Test @MainActor func unknownRelationshipStaysUnresolvedUntilTheServerAnswers() async {
        let store = RelationshipStore(updates: PassthroughSubject<UpdatedElement, Never>())
        store.activeScope = "session"
        let api = MockMastodonAPI()
        api.fetchRelationshipsHandler = { _ in [self.makeRelationship(id: "stranger", following: true)] }

        let model = ProfileViewModel(
            apiClient: api, accountID: "stranger", currentAccountID: "me", relationshipStore: store
        )
        #expect(!model.isRelationshipResolved)
        #expect(model.relationship == nil)

        // A response that arrives after switching accounts still belongs to the session
        // the profile was opened in.
        store.activeScope = "other-session"
        await model.loadRelationship()
        #expect(model.isRelationshipResolved)
        #expect(store.relationship(for: "stranger", scope: "session")?.following == true)
        #expect(store.relationship(for: "stranger", scope: "other-session") == nil)
    }

    @Test @MainActor func failedRelationshipCheckStillSettlesTheFollowButton() async {
        let store = RelationshipStore(updates: PassthroughSubject<UpdatedElement, Never>())
        let api = MockMastodonAPI()
        api.fetchRelationshipsHandler = { _ in throw URLError(.notConnectedToInternet) }
        let model = ProfileViewModel(
            apiClient: api, accountID: "offline", currentAccountID: "me", relationshipStore: store
        )
        await model.loadRelationship()
        #expect(model.isRelationshipResolved)
        #expect(model.relationship == nil)
    }
}
