//
//  TranslationLanguagesStore.swift
//  moro
//
//  Session cache of the instance's supported translation pairs from
//  GET /api/v1/instance/translation_languages. The translate control appears
//  only for a pair the instance can translate. Reset on logout or account
//  switch via CacheManager.clearAll().
//

import Combine
import Foundation

@MainActor
final class TranslationLanguagesStore: ObservableObject {
    static let shared = TranslationLanguagesStore()

    /// Source code (lowercased) → supported target codes, as returned by the
    /// instance. `nil` until the first load resolves (or the instance has no
    /// translation backend — which returns `{}`, hiding the control).
    @Published private(set) var languages: [String: [String]]?

    private var loadTask: Task<Void, Never>?

    init() {}

    func loadIfNeeded(apiClient: MastodonAPI) async {
        if languages != nil { return }
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task {
            // A failure (network, V1 instance without the endpoint) leaves
            // `languages` nil so the next caller retries. An instance with no
            // translation backend returns {}, which correctly disables the
            // control everywhere.
            if let map = try? await apiClient.fetchTranslationLanguages() {
                languages = Dictionary(
                    map.map { ($0.key.lowercased(), $0.value) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        }
        loadTask = task
        await task.value
        loadTask = nil
    }

    /// The source must be looked up by the post's raw language tag —
    /// `languages[@status.language]` — with NO primary-subtag fallback. A post
    /// tagged "zh-CN" misses the matrix's "zh" key, so the server refuses
    /// ("this action is not allowed"), so the control must stay hidden.
    /// Only the TARGET side is matched loosely (the server splits the target
    /// to its primary subtag), tolerant of casing across backends.
    /// Returns `false` until the matrix loads, so a tap can never 404/422.
    func canTranslate(postLanguage: String, into uiLanguage: String) -> Bool {
        guard let languages else { return false }
        guard let targets = languages[postLanguage.lowercased()] else { return false }
        return targets.contains { matches($0, uiLanguage) }
    }

    func reset() {
        loadTask?.cancel()
        loadTask = nil
        languages = nil
    }

    /// Two language tags refer to the same language if they match in full
    /// (case-insensitively) or share a primary subtag — "zh-HANS"/"zh-Hans",
    /// "en"/"en-GB", etc.
    private func matches(_ a: String, _ b: String) -> Bool {
        if a.caseInsensitiveCompare(b) == .orderedSame { return true }
        return primarySubtag(a).caseInsensitiveCompare(primarySubtag(b)) == .orderedSame
    }

    private func primarySubtag(_ code: String) -> String {
        String(code.split(separator: "-").first ?? Substring(code))
    }
}
