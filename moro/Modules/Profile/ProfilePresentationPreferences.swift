import Foundation
import Combine

/// A viewer preference, scoped to the signed-in session rather than the viewed profile.
@MainActor
final class ProfilePresentationPreferences: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let shared = ProfilePresentationPreferences()
    @Published private(set) var revision = 0
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func showsFeaturedTags(accountKey: String) -> Bool {
        defaults.object(forKey: key(accountKey)) as? Bool ?? true
    }

    func setShowsFeaturedTags(_ enabled: Bool, accountKey: String) {
        guard enabled != showsFeaturedTags(accountKey: accountKey) else { return }
        defaults.set(enabled, forKey: key(accountKey))
        revision += 1
    }

    func curationChanged() { revision += 1 }

    static func shouldShowTags(enabled: Bool, tags: [FeaturedTag]) -> Bool {
        enabled && !tags.isEmpty
    }

    private func key(_ accountKey: String) -> String { "profile.featuredTags.visible.v1.\(accountKey)" }
}
