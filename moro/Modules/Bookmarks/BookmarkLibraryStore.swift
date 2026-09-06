import CryptoKit
import Foundation

/// Account-scoped reading state and a bounded, disposable copy of bookmark bodies.
@MainActor
final class BookmarkLibraryStore {
    private struct Snapshot: Codable {
        let statuses: [Status]
        let updatedAt: Date
    }

    static let capacity = 200
    private(set) var cachedStatuses: [Status] = []
    private(set) var readIDs: Set<String>
    private(set) var updatedAt: Date?
    private let fileURL: URL
    private let defaults: UserDefaults
    private let readKey: String

    init(accountKey: String, directory: URL? = nil, defaults: UserDefaults = .standard) {
        let digest = SHA256.hash(data: Data(accountKey.utf8)).map { String(format: "%02x", $0) }.joined()
        let directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BookmarkLibrary", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("\(digest).json")
        self.defaults = defaults
        readKey = "bookmark_read_ids_v1.\(digest)"
        readIDs = Set(defaults.stringArray(forKey: readKey) ?? [])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL), let snapshot = try? decoder.decode(Snapshot.self, from: data) {
            cachedStatuses = Array(snapshot.statuses.prefix(Self.capacity))
            updatedAt = snapshot.updatedAt
        }
    }

    func setRead(_ read: Bool, id: String) {
        if read { readIDs.insert(id) } else { readIDs.remove(id) }
        defaults.set(readIDs.sorted(), forKey: readKey)
    }

    func cache(_ statuses: [Status], complete: Bool) {
        var seen = Set<String>()
        cachedStatuses = Array((complete ? statuses : statuses + cachedStatuses)
            .filter { seen.insert($0.id).inserted }.prefix(Self.capacity))
        updatedAt = Date()
        persist()
    }

    func remove(id: String) {
        cachedStatuses.removeAll { $0.id == id || $0.displayStatus.id == id }
        setRead(false, id: id)
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Snapshot(statuses: cachedStatuses, updatedAt: updatedAt ?? Date())) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
