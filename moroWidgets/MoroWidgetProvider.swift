//
//  MoroWidgetProvider.swift
//  moroWidgets
//


import Foundation
import WidgetKit

struct MoroWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: MoroWidgetDataSnapshot?
    let avatarData: Data?

    static let placeholder = MoroWidgetEntry(
        date: Date(),
        snapshot: MoroWidgetDataSnapshot(
            sessionID: "preview",
            account: MoroWidgetAccount(
                id: "preview",
                username: "moro",
                acct: "moro@social.example",
                displayName: "Moro",
                avatar: "",
                avatarStatic: "",
                followersCount: 1_248,
                followingCount: 386
            ),
            unreadCount: 8,
            updatedAt: Date()
        ),
        avatarData: nil
    )
}

struct MoroWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MoroWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (MoroWidgetEntry) -> Void) {
        if context.isPreview {
            completion(.placeholder)
            return
        }
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MoroWidgetEntry>) -> Void) {
        let snapshot = MoroWidgetSharedStore.loadSnapshot()
        let cachedData = snapshot.flatMap {
            MoroWidgetSharedStore.cachedAvatarData(
                accountID: $0.account.id,
                sourceURL: $0.account.avatarURL
            )
        }

        guard let snapshot, cachedData == nil, let avatarURL = snapshot.account.avatarURL else {
            finishTimeline(snapshot: snapshot, avatarData: cachedData, completion: completion)
            return
        }

        Task {
            let avatarData = await fetchAvatarData(from: avatarURL)
            if let avatarData {
                MoroWidgetSharedStore.cacheAvatarData(
                    avatarData,
                    accountID: snapshot.account.id,
                    sourceURL: avatarURL
                )
            }
            finishTimeline(snapshot: snapshot, avatarData: avatarData, completion: completion)
        }
    }

    private func makeEntry() -> MoroWidgetEntry {
        let snapshot = MoroWidgetSharedStore.loadSnapshot()
        let avatarData = snapshot.flatMap {
            MoroWidgetSharedStore.cachedAvatarData(
                accountID: $0.account.id,
                sourceURL: $0.account.avatarURL
            )
        }
        return MoroWidgetEntry(date: Date(), snapshot: snapshot, avatarData: avatarData)
    }

    private func finishTimeline(
        snapshot: MoroWidgetDataSnapshot?,
        avatarData: Data?,
        completion: @escaping (Timeline<MoroWidgetEntry>) -> Void
    ) {
        let entry = MoroWidgetEntry(date: Date(), snapshot: snapshot, avatarData: avatarData)
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
            ?? Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func fetchAvatarData(from url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.cachePolicy = .returnCacheDataElseLoad
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
            let httpResponse = response as? HTTPURLResponse,
            (200..<300).contains(httpResponse.statusCode),
            !data.isEmpty,
            data.count <= 3_000_000
        else {
            return nil
        }
        return data
    }
}
