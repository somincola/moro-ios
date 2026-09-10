import Combine
import Foundation
import StoreKit

nonisolated enum MoroAppStore {
    static let appID = 6776115614
    static let productURL = URL(string: "https://apps.apple.com/app/id6776115614")!
    static let reviewURL = URL(string: "https://apps.apple.com/app/id6776115614?action=write-review")!

    /// StoreKit uses ISO alpha-3; Lookup requires alpha-2.
    static func lookupCountry(_ code: String) -> String? {
        guard code.allSatisfy(\.isASCII), (2...3).contains(code.count) else { return nil }
        let region = Locale(identifier: "und_" + code).region?.identifier.uppercased()
        guard let region, region.count == 2, Locale.Region.isoRegions.contains(Locale.Region(region)) else { return nil }
        return region
    }

    static func isNewer(_ candidate: String, than installed: String) -> Bool {
        func components(_ version: String) -> [Int]? {
            let parts = version.split(separator: ".", omittingEmptySubsequences: false)
            guard !parts.isEmpty else { return nil }
            let values = parts.compactMap { part -> Int? in
                guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
                return Int(part)
            }
            return values.count == parts.count ? values : nil
        }
        guard let lhs = components(candidate), let rhs = components(installed) else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}

nonisolated struct AppStoreRelease: Codable, Equatable, Sendable {
    let version: String

    static func decodeLookup(_ data: Data) throws -> AppStoreRelease? {
        struct Response: Decodable {
            struct Item: Decodable {
                let trackId: Int
                let bundleId: String
                let version: String
            }
            let results: [Item]
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard let item = response.results.first(where: {
            $0.trackId == MoroAppStore.appID && $0.bundleId == "com.somincola.moro"
        }) else { return nil }
        guard MoroAppStore.isNewer(item.version, than: "0") else { throw URLError(.cannotParseResponse) }
        return AppStoreRelease(version: item.version)
    }

    static func fetch(country: String) async throws -> AppStoreRelease? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")!
        components.queryItems = [
            URLQueryItem(name: "id", value: String(MoroAppStore.appID)),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity", value: "software")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try decodeLookup(data)
    }
}

@MainActor
final class AppUpdateStore: ObservableObject {
    static let shared = AppUpdateStore()
    enum CheckState { case unknown, checking, checked, unavailable, failed }
    private struct Snapshot: Codable {
        let country: String
        let release: AppStoreRelease?
        let checkedAt: Date
    }

    let currentVersion: String
    @Published private(set) var latestRelease: AppStoreRelease?
    @Published private(set) var state: CheckState = .unknown
    @Published private(set) var seenVersion: String?
    private let defaults: UserDefaults
    private let fetch: (String) async throws -> AppStoreRelease?
    private let country: () async -> String
    private let now: () -> Date
    private var snapshot: Snapshot?
    private var retryAfter: Date?
    private var lastAttemptCountry: String?
    private static let snapshotKey = "appUpdate.snapshot.v1"
    private static let seenKey = "appUpdate.seenVersion"

    init(
        currentVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        country: @escaping () async -> String = {
            let storefront = await Storefront.current
            return storefront.flatMap { MoroAppStore.lookupCountry($0.countryCode) }
                ?? Locale.current.region.flatMap { MoroAppStore.lookupCountry($0.identifier) } ?? "US"
        },
        fetch: @escaping (String) async throws -> AppStoreRelease? = AppStoreRelease.fetch
    ) {
        self.currentVersion = currentVersion
        self.defaults = defaults
        self.now = now
        self.country = country
        self.fetch = fetch
        seenVersion = defaults.string(forKey: Self.seenKey)
        snapshot = defaults.data(forKey: Self.snapshotKey).flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) }
        latestRelease = snapshot?.release
        lastAttemptCountry = snapshot?.country
    }

    var hasUpdate: Bool {
        latestRelease.map { MoroAppStore.isNewer($0.version, than: currentVersion) } ?? false
    }
    var hasUnseenUpdate: Bool { hasUpdate && seenVersion != latestRelease?.version }

    func markUpdateSeen() {
        guard hasUpdate, let version = latestRelease?.version else { return }
        seenVersion = version
        defaults.set(version, forKey: Self.seenKey)
    }

    func check(force: Bool = false) async {
        guard state != .checking else { return }
        state = .checking
        let storefront = await country()
        guard !Task.isCancelled else { state = .unknown; return }
        if lastAttemptCountry != storefront { latestRelease = nil; retryAfter = nil }
        lastAttemptCountry = storefront
        if !force, let snapshot, snapshot.country == storefront,
           (0..<86_400).contains(now().timeIntervalSince(snapshot.checkedAt)) {
            latestRelease = snapshot.release
            state = snapshot.release == nil ? .unavailable : .checked
            return
        }
        if !force, let retryAfter, now() < retryAfter { state = .failed; return }
        do {
            let release = try await fetch(storefront)
            try Task.checkCancellation()
            let result = Snapshot(country: storefront, release: release, checkedAt: now())
            snapshot = result
            latestRelease = release
            retryAfter = nil
            defaults.set(try JSONEncoder().encode(result), forKey: Self.snapshotKey)
            state = release == nil ? .unavailable : .checked
        } catch {
            if Task.isCancelled { state = .unknown; return }
            retryAfter = now().addingTimeInterval(3_600)
            state = .failed
        }
    }
}
