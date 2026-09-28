import Combine
import Foundation

@MainActor
final class BookmarksViewModel: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum LoadingState { case idle, loading, loadingMore, loaded, error(Error) }
    enum ReadingFilter: String, CaseIterable {
        case all, unread, read
        var title: String {
            switch self {
            case .all: MoroL10n.BookmarkReading.all
            case .unread: MoroL10n.BookmarkReading.unread
            case .read: MoroL10n.BookmarkReading.read
            }
        }
    }

    @Published private(set) var statuses: [Status] = []
    @Published private(set) var loadingState: LoadingState = .idle
    @Published private(set) var transientErrorMessage: String?
    @Published private(set) var removingIDs: Set<String> = []
    @Published private(set) var loadMoreFailed = false
    @Published private(set) var hasMore = false
    @Published private(set) var isOfflineSnapshot = false
    @Published private(set) var readIDs: Set<String> = []
    @Published var searchQuery = ""
    @Published var readingFilter: ReadingFilter = .all

    private let apiClient: MastodonAPI
    private let library: BookmarkLibraryStore?
    private let coordinator: FeedCoordinator
    private var searchIndex: [String: String] = [:]
    private var currentMaxID: String?
    private var visitedCursors: Set<String> = []
    // A later page can overlap an earlier one; keep confirmed removals out of that page.
    private var removedDuringPaging: Set<String> = []
    private var isRequestInFlight = false
    private var didLoadInitial = false
    private var updates: AnyCancellable?

    init(apiClient: MastodonAPI, library: BookmarkLibraryStore? = nil, feedCoordinator: FeedCoordinator? = nil) {
        self.apiClient = apiClient
        self.library = library
        coordinator = feedCoordinator ?? .shared
        statuses = library?.cachedStatuses ?? []
        readIDs = library?.readIDs ?? []
        rebuildSearchIndex()
        updates = coordinator.updates.sink { [weak self] in self?.incorporate($0) }
    }

    var isLoading: Bool {
        switch loadingState { case .loading, .loadingMore: true; default: false }
    }

    var filteredStatuses: [Status] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return statuses.filter { status in
            let isRead = readIDs.contains(status.displayStatus.id)
            let matchesReading = readingFilter == .all || (readingFilter == .read ? isRead : !isRead)
            return matchesReading && (query.isEmpty || searchIndex[status.id, default: ""].localizedStandardContains(query))
        }
    }

    func setRead(_ read: Bool, status: Status) {
        let id = status.displayStatus.id
        if read { readIDs.insert(id) } else { readIDs.remove(id) }
        library?.setRead(read, id: id)
    }

    func loadInitial() async {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        await fetch(reset: true)
    }

    func refresh() async { await fetch(reset: true) }

    func loadMore() async {
        guard hasMore, currentMaxID != nil, !isOfflineSnapshot else { return }
        await fetch(reset: false)
    }

    private func fetch(reset: Bool) async {
        guard !isRequestInFlight, removingIDs.isEmpty else { return }
        isRequestInFlight = true
        loadingState = reset ? .loading : .loadingMore
        loadMoreFailed = false
        if reset { removedDuringPaging = [] }
        let cursor = reset ? nil : currentMaxID
        defer { isRequestInFlight = false }
        do {
            let page = try await apiClient.fetchBookmarkedPage(maxID: cursor, limit: 20)
            try Task.checkCancellation()
            if reset { statuses = []; visitedCursors = [] }
            var seen = Set(statuses.map(\.id))
            statuses.append(contentsOf: page.statuses.filter {
                !removedDuringPaging.contains($0.displayStatus.id) && seen.insert($0.id).inserted
            })
            if let cursor { visitedCursors.insert(cursor) }
            currentMaxID = page.nextMaxID.flatMap { visitedCursors.contains($0) ? nil : $0 }
            hasMore = currentMaxID != nil
            loadingState = .loaded
            transientErrorMessage = nil
            isOfflineSnapshot = false
            rebuildSearchIndex()
            library?.cache(statuses, complete: !hasMore)
        } catch is CancellationError {
            didLoadInitial = false
            loadingState = statuses.isEmpty ? .idle : .loaded
        } catch {
            if reset {
                isOfflineSnapshot = !statuses.isEmpty
                loadingState = .error(error)
                transientErrorMessage = statuses.isEmpty ? MoroL10n.BookmarksVM.loadFailed : MoroL10n.BookmarkReading.offline
            } else {
                loadingState = .loaded
                loadMoreFailed = true
            }
        }
    }

    func removeBookmark(_ status: Status) async {
        guard !isRequestInFlight, !removingIDs.contains(status.id) else { return }
        removingIDs.insert(status.id)
        defer { removingIDs.remove(status.id) }
        do {
            let updated = try await apiClient.unbookmarkStatus(id: status.displayStatus.id)
            try Task.checkCancellation()
            guard !updated.bookmarked else { throw URLError(.cannotParseResponse) }
            removeLocal(id: status.displayStatus.id)
            coordinator.publishUpdate(.post(updated))
            transientErrorMessage = nil
            AppFeedbackCenter.shared.showSuccess(MoroL10n.BookmarksVM.removed)
        } catch {
            transientErrorMessage = MoroL10n.BookmarksVM.removeFailedDetail
            AppFeedbackCenter.shared.showError(MoroL10n.BookmarksVM.removeFailed)
        }
    }

    private func rebuildSearchIndex() {
        searchIndex = Dictionary(statuses.map { status in
            let post = status.displayStatus
            let elements = ContentParser.parseToElements(html: post.content, options: .statusBody)
            let urls = elements.compactMap { element -> String? in
                if case .link(_, let url) = element { return url.absoluteString }
                return nil
            }
            let text = [elements.plainTextValue, post.account.acct, post.account.displayName,
                        post.spoilerText ?? ""] + (post.tags ?? []).map(\.name) + urls
            return (status.id, text.joined(separator: "\n"))
        }, uniquingKeysWith: { _, latest in latest })
    }

    private func removeLocal(id: String) {
        removedDuringPaging.insert(id)
        statuses.removeAll { $0.id == id || $0.displayStatus.id == id }
        readIDs.remove(id)
        library?.remove(id: id)
        rebuildSearchIndex()
    }

    private func incorporate(_ update: UpdatedElement) {
        switch update {
        case .deletedPost(let id): removeLocal(id: id)
        case .post(let post):
            if post.bookmarked { removedDuringPaging.remove(post.id) }
            guard statuses.contains(where: { $0.displayStatus.id == post.id }) else { return }
            if !post.bookmarked { removeLocal(id: post.id) }
            else {
                statuses = statuses.map { $0.incorporatingDisplayStatusUpdate(post) }
                library?.cache(statuses, complete: false)
                rebuildSearchIndex()
            }
        default: break
        }
    }
}
