import Combine
import Foundation

@MainActor
final class TopicFollowModel: ObservableObject {
    @Published private(set) var following: Bool?
    @Published private(set) var isBusy = false
    @Published private(set) var error: Error?
    private let apiClient: MastodonAPI
    private let name: String

    init(apiClient: MastodonAPI, name: String) {
        self.apiClient = apiClient
        self.name = name
    }

    func load() async {
        guard !isBusy, following == nil else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let tag = try await apiClient.fetchTag(name: name)
            try Task.checkCancellation()
            guard let state = tag.following else { throw URLError(.cannotParseResponse) }
            following = state
            error = nil
        } catch is CancellationError {
        } catch { self.error = error }
    }

    func toggle() async {
        guard !isBusy, let following else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            let tag = try await apiClient.setTagFollowed(name: name, followed: !following)
            try Task.checkCancellation()
            guard let state = tag.following else { throw URLError(.cannotParseResponse) }
            self.following = state
            error = nil
        } catch is CancellationError {
        } catch { self.error = error }
    }
}
