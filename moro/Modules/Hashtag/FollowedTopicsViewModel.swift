import Combine
import Foundation

@MainActor
final class FollowedTopicsViewModel: ObservableObject {
    @Published private(set) var tags: [SearchTag] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var nextMaxID: String?
    @Published private(set) var removing = Set<String>()
    @Published private(set) var removalError: Error?
    private(set) var hasLoaded = false
    private var visitedCursors = Set<String>()
    private var failedRefresh = false
    private let apiClient: MastodonAPI

    init(apiClient: MastodonAPI) { self.apiClient = apiClient }

    func load(refresh: Bool = false) async {
        guard !isLoading, removing.isEmpty, refresh || !hasLoaded || nextMaxID != nil else { return }
        isLoading = true
        error = nil
        let cursor = refresh ? nil : nextMaxID
        defer { isLoading = false }
        do {
            let page = try await apiClient.fetchFollowedTags(maxID: cursor, limit: 100)
            try Task.checkCancellation()
            if refresh { visitedCursors = []; tags = []; removalError = nil }
            var seen = Set(tags.map(\.id))
            tags.append(contentsOf: page.tags.filter { seen.insert($0.id).inserted })
            if let cursor { visitedCursors.insert(cursor) }
            nextMaxID = page.nextMaxID.flatMap { visitedCursors.contains($0) ? nil : $0 }
            hasLoaded = true
        } catch is CancellationError {
        } catch { self.error = error; failedRefresh = refresh }
    }

    func retry() async { await load(refresh: failedRefresh) }

    func unfollow(_ tag: SearchTag) async {
        guard !isLoading, !removing.contains(tag.id) else { return }
        removing.insert(tag.id)
        removalError = nil
        defer { removing.remove(tag.id) }
        do {
            let result = try await apiClient.setTagFollowed(name: tag.name, followed: false)
            try Task.checkCancellation()
            guard result.following == false else { throw URLError(.cannotParseResponse) }
            tags.removeAll { $0.id == tag.id }
        } catch is CancellationError {
        } catch { removalError = error }
    }
}
