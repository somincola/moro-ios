//
//  Account+CacheBust.swift
//  moro
//
//  Appends a fresh `moro_cb` token to the avatar / header URLs so image loaders treat them
//  as new and refetch. Needed whenever the media changed but the server reused the URL — the
//  per-view MoroAvatars are keyed by URL string, so an unchanged URL never reloads (the home
//  header, drawer and account list would keep showing the cached image). Used after an in-app
//  Edit Profile save and after pulling-to-refresh one's own profile (web-side avatar swaps).
//

import Foundation

extension Account {
    func withCacheBustedMedia(avatar: Bool = true, header: Bool = true) -> Account {
        guard avatar || header else { return self }
        let token = String(Int(Date().timeIntervalSince1970))
        return Account(
            id: id,
            username: username,
            acct: acct,
            displayName: displayName,
            note: note,
            avatar: avatar ? Self.cacheBustedMediaURLString(from: self.avatar, token: token) : self.avatar,
            avatarStatic: avatar ? Self.cacheBustedMediaURLString(from: avatarStatic, token: token) : avatarStatic,
            header: header ? Self.cacheBustedMediaURLString(from: self.header, token: token) : self.header,
            headerStatic: header ? Self.cacheBustedMediaURLString(from: headerStatic, token: token) : headerStatic,
            followersCount: followersCount,
            followingCount: followingCount,
            statusesCount: statusesCount,
            createdAt: createdAt,
            locked: locked,
            bot: bot,
            fields: fields,
            url: url,
            moved: moved?.value,
            suspended: suspended,
            limited: limited
        )
    }

    private static func cacheBustedMediaURLString(from rawURL: String, token: String) -> String {
        guard !rawURL.isEmpty,
            let url = URL(string: rawURL),
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return rawURL
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "moro_cb" }
        items.append(URLQueryItem(name: "moro_cb", value: token))
        components.queryItems = items
        return components.url?.absoluteString ?? rawURL
    }
}
