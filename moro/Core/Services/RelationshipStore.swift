//
//  RelationshipStore.swift
//  moro
//
//  Last-known relationships with other accounts, per signed-in session, so a
//  profile can open on the right Follow state instead of guessing "Follow" while
//  the relationship request is in flight. Every reader still revalidates.
//

import Combine
import Foundation

@MainActor
final class RelationshipStore {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = RelationshipStore()

    /// The signed-in session new readers and writers belong to. Callers capture it
    /// when they are created so a late response can never land in another account.
    var activeScope = ""

    private let limit: Int
    private var entries: [String: Relationship] = [:]
    private var recency: [String] = []
    private var subscription: AnyCancellable?

    init(limit: Int = 600, updates: PassthroughSubject<UpdatedElement, Never>? = nil) {
        self.limit = max(1, limit)
        subscription = (updates ?? FeedCoordinator.shared.updates).sink { [weak self] update in
            guard let self, case .relationship(let relationship) = update else { return }
            self.store(relationship, scope: self.activeScope)
        }
    }

    func relationship(for accountID: String, scope: String) -> Relationship? {
        let key = Self.key(scope, accountID)
        guard let relationship = entries[key] else { return nil }
        touch(key)
        return relationship
    }

    func store(_ relationship: Relationship, scope: String) {
        guard !relationship.id.isEmpty else { return }
        let key = Self.key(scope, relationship.id)
        entries[key] = relationship
        touch(key)
        while recency.count > limit {
            entries.removeValue(forKey: recency.removeFirst())
        }
    }

    private func touch(_ key: String) {
        if let index = recency.lastIndex(of: key) { recency.remove(at: index) }
        recency.append(key)
    }

    private static func key(_ scope: String, _ accountID: String) -> String {
        "\(scope)\u{1F}\(accountID)"
    }
}
