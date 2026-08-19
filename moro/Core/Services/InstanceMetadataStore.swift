//
//  InstanceMetadataStore.swift
//  moro
//
//  Shared cache-first access to the authenticated server's /api/v2/instance payload.
//


import Foundation

@MainActor
final class InstanceMetadataStore {
    enum RefreshPolicy {
        case refreshIfStale
        case forceRefresh
    }

    private struct CacheRecord: Codable {
        let instance: MastodonInstanceV2
        let fetchedAt: Date
    }

    static let shared = InstanceMetadataStore()

    private let cacheDirectory: URL
    private let freshnessInterval: TimeInterval
    private var recordsByInstance: [String: CacheRecord] = [:]
    private var diskCheckedKeys: Set<String> = []
    private var inFlightLoads: [String: Task<MastodonInstanceV2, Error>] = [:]

    init(
        cacheDirectory: URL? = nil,
        freshnessInterval: TimeInterval = 12 * 60 * 60
    ) {
        let baseDirectory = cacheDirectory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.cacheDirectory = baseDirectory.appendingPathComponent(
            "InstanceMetadata",
            isDirectory: true
        )
        self.freshnessInterval = freshnessInterval
    }

    func cachedInstance(for apiClient: MastodonAPI) -> MastodonInstanceV2? {
        guard let key = cacheKey(for: apiClient) else { return nil }
        return recordsByInstance[key]?.instance
    }

    @discardableResult
    func load(
        apiClient: MastodonAPI,
        policy: RefreshPolicy = .refreshIfStale,
        now: Date = Date()
    ) async throws -> MastodonInstanceV2 {
        guard let key = cacheKey(for: apiClient) else {
            return try await apiClient.fetchInstanceV2()
        }

        let cachedRecord = await loadRecordFromDiskIfNeeded(for: key)
        let cacheAge = cachedRecord.map { now.timeIntervalSince($0.fetchedAt) }
        if policy == .refreshIfStale,
           let cachedRecord,
           let cacheAge,
           cacheAge >= 0,
           cacheAge < freshnessInterval {
            return cachedRecord.instance
        }

        do {
            return try await refresh(apiClient: apiClient, key: key, now: now)
        } catch {
            if policy == .refreshIfStale, let cachedRecord {
                return cachedRecord.instance
            }
            throw error
        }
    }

    private func refresh(
        apiClient: MastodonAPI,
        key: String,
        now: Date
    ) async throws -> MastodonInstanceV2 {
        if let inFlight = inFlightLoads[key] {
            return try await inFlight.value
        }

        let task = Task {
            try await apiClient.fetchInstanceV2()
        }
        inFlightLoads[key] = task

        do {
            let instance = try await task.value
            inFlightLoads[key] = nil
            let record = CacheRecord(instance: instance, fetchedAt: now)
            recordsByInstance[key] = record
            await persist(record, for: key)
            return instance
        } catch {
            inFlightLoads[key] = nil
            throw error
        }
    }

    private func loadRecordFromDiskIfNeeded(for key: String) async -> CacheRecord? {
        if let cached = recordsByInstance[key] {
            return cached
        }
        guard diskCheckedKeys.insert(key).inserted else { return nil }

        let fileURL = cacheFileURL(for: key)
        let data = await Task.detached(priority: .utility) {
            try? Data(contentsOf: fileURL, options: [.mappedIfSafe])
        }.value
        guard let data,
              let record = try? JSONDecoder().decode(CacheRecord.self, from: data) else {
            return nil
        }
        recordsByInstance[key] = record
        return record
    }

    private func persist(_ record: CacheRecord, for key: String) async {
        guard let data = try? JSONEncoder().encode(record) else { return }
        let directory = cacheDirectory
        let fileURL = cacheFileURL(for: key)
        await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            try? fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }.value
    }

    private func cacheKey(for apiClient: MastodonAPI) -> String? {
        guard let rawKey = apiClient.instanceMetadataCacheKey else { return nil }
        if let url = URL(string: rawKey),
           let scheme = url.scheme?.lowercased(),
           let host = url.host?.lowercased() {
            let port = url.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        let normalized = rawKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private func cacheFileURL(for key: String) -> URL {
        let fileName = Data(key.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return cacheDirectory.appendingPathComponent("\(fileName).json")
    }
}
