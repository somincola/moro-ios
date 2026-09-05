import Combine
import Foundation

struct SearchLibraryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let query: String
    let scope: SearchViewModel.Scope
    var name: String

    var title: String { name.isEmpty ? query : name }
}

/// Local, explicitly submitted searches. Account identity is supplied by the route
/// environment, so identical account IDs on different instances cannot share data.
@MainActor
final class SearchLibraryStore: ObservableObject {
    @Published private(set) var recent: [SearchLibraryItem] = []
    @Published private(set) var saved: [SearchLibraryItem] = []
    private let defaults: UserDefaults
    private let storageKey: String

    private struct Snapshot: Codable {
        var recent: [SearchLibraryItem]
        var saved: [SearchLibraryItem]
    }

    init(accountKey: String, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storageKey = "search_library_v1.\(accountKey)"
        reload()
    }

    func reload() {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            recent = []
            saved = []
            return
        }
        recent = Array(snapshot.recent.prefix(20))
        saved = snapshot.saved
    }

    func record(query: String, scope: SearchViewModel.Scope) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        recent.removeAll { $0.query.caseInsensitiveCompare(query) == .orderedSame }
        recent.insert(SearchLibraryItem(id: UUID(), query: query, scope: scope, name: ""), at: 0)
        recent = Array(recent.prefix(20))
        persist()
    }

    func isSaved(query: String, scope: SearchViewModel.Scope) -> Bool {
        saved.contains { $0.query == query && $0.scope == scope }
    }

    func save(query: String, scope: SearchViewModel.Scope) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSaved(query: query, scope: scope) else { return }
        saved.append(SearchLibraryItem(id: UUID(), query: query, scope: scope, name: ""))
        persist()
    }

    func rename(id: UUID, name: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }) else { return }
        saved[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    func removeRecent(id: UUID) {
        recent.removeAll { $0.id == id }
        persist()
    }

    func clearRecent() {
        recent = []
        persist()
    }

    func removeSaved(id: UUID) {
        saved.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Snapshot(recent: recent, saved: saved)) {
            defaults.set(data, forKey: storageKey)
        }
    }
}
