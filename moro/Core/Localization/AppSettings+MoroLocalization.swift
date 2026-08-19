//
//  AppSettings+MoroLocalization.swift
//  moro
//
//  App-owned glue that depends on both AppSettings and the localization package.
//

import Foundation
import MoroLocalization

extension AppSettings {
    var defaultPostLanguageSummary: String {
        PostLanguageCatalog.selectionSummary(
            for: defaultPostLanguage,
            defaultBehavior: defaultPostLanguageBehavior
        )
    }

    /// Describes where the default posting language comes from, for labelling
    /// the "default" option: an explicit in-app override, the server account
    /// default (`source.language`), or — when neither is set ("Automatic" on
    /// the server) — the system/app language.
    var defaultPostLanguageBehavior: PostLanguageDefaultBehavior {
        let explicit = defaultPostLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return .appDefault(defaultLanguageCode: explicit)
        }
        if !serverDefaultPostLanguage.isEmpty {
            return .serverDefault(languageCode: serverDefaultPostLanguage)
        }
        return .systemDefault
    }

    /// Translation target is the resolved app UI language, independent of the
    /// posting language. This follows the iOS per-app language setting.
    var preferredTranslationTargetLanguageCode: String {
        MoroAppLanguage.current
    }

    var preferredTranslationTargetLanguageSummary: String {
        PostLanguageCatalog.displayName(for: preferredTranslationTargetLanguageCode)
    }

    var contentTranslationModeSummary: String {
        contentTranslationMode.localizedName
    }
}
