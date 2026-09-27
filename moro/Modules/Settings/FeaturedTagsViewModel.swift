import Foundation
import Combine

@MainActor
final class FeaturedTagsViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    @Published private(set) var tags: [FeaturedTag] = []
    @Published private(set) var suggestions: [SearchTag] = []
    @Published private(set) var limits = ProfileLimits()
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var error: String?
    @Published var input = ""
    private let apiClient: MastodonAPI

    init(apiClient: MastodonAPI) { self.apiClient = apiClient }

    var availableSuggestions: [SearchTag] {
        let names = Set(tags.map { $0.name.lowercased() })
        return suggestions.filter { !names.contains($0.name.lowercased()) }
    }

    func load() async {
        guard !isLoading, !isSaving else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let loaded = try await apiClient.fetchOwnFeaturedTags()
            let suggested = (try? await apiClient.fetchFeaturedTagSuggestions()) ?? []
            let metadata = try? await InstanceMetadataStore.shared.load(apiClient: apiClient)
            try Task.checkCancellation()
            tags = loaded
            suggestions = suggested
            if let limits = metadata?.configuration?.accounts { self.limits = limits }
            hasLoaded = true
        } catch is CancellationError {
        } catch {
            self.error = error.localizedDescription
        }
    }

    @discardableResult
    func add(_ value: String? = nil) async -> Bool {
        guard hasLoaded, !isSaving, !isLoading else { return false }
        guard tags.count < limits.featuredTagCount else {
            error = MoroL10n.ProfileEditing.limitReached
            return false
        }
        var name = (value ?? input).trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        if name.hasPrefix("#") { name.removeFirst() }
        guard !name.isEmpty, !name.contains(where: { $0.isWhitespace || $0 == "#" }),
              !tags.contains(where: { $0.name.lowercased() == name.lowercased() }) else {
            error = MoroL10n.ProfileEditing.invalidTag
            return false
        }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let added = try await apiClient.featureTag(name: name)
            if !tags.contains(where: { $0.id == added.id }) { tags.append(added) }
            if value == nil { input = "" }
            ProfilePresentationPreferences.shared.curationChanged()
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func remove(_ tag: FeaturedTag) async {
        guard !isSaving, !isLoading else { return }
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            try await apiClient.unfeatureTag(id: tag.id)
            tags.removeAll { $0.id == tag.id }
            ProfilePresentationPreferences.shared.curationChanged()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
