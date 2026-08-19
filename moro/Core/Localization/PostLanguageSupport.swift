//
//  PostLanguageSupport.swift
//  moro
//
//  Shared helpers for language selection in settings and compose.
//

import Foundation

public enum PostLanguageDefaultBehavior {
    case systemDefault
    case appDefault(defaultLanguageCode: String)
    /// The account's server-side default posting language (from
    /// verify_credentials). An empty code falls back to the system default.
    case serverDefault(languageCode: String)
}

/// The language the app UI is actually displayed in — the resolved app
/// localization, clamped to the bundle's shipped languages and falling back to
/// the development region (English). `Bundle.main.preferredLocalizations.first`
/// is both the target
/// language for post translation and the yardstick for showing the translate
/// control (a post is translatable only into the UI language).
public enum MoroAppLanguage {
    public static var current: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }
}

public struct PostLanguageOption: Identifiable, Hashable {
    public let code: String
    public let displayName: String
    public let nativeName: String?

    public var id: String { code }
}

public enum PostLanguageCatalog {
    private static let curatedCodes = [
        "en", "zh-Hans", "zh-Hant", "ja", "ko", "fr", "de", "es", "pt-BR", "it",
        "ru", "uk", "ar", "hi", "id", "tr", "vi", "th"
    ]

    public static var options: [PostLanguageOption] {
        buildOptions()
    }

    private static func buildOptions() -> [PostLanguageOption] {
        let systemLanguageCodes = Locale.LanguageCode.isoLanguageCodes.map(\.identifier)
        let prioritizedCodes = curatedCodes + Locale.preferredLanguages + systemLanguageCodes
        var orderedCodes: [String] = []
        var seenCodes = Set<String>()

        for identifier in prioritizedCodes {
            let normalized = normalize(identifier)
            guard !normalized.isEmpty else { continue }
            if seenCodes.insert(normalized).inserted {
                orderedCodes.append(normalized)
            }
        }

        let prioritizedSet = Set((curatedCodes + Locale.preferredLanguages).map { normalize($0) })
        let preferredCodes = orderedCodes.filter { prioritizedSet.contains($0) }
        let remainingCodes = orderedCodes.filter { !prioritizedSet.contains($0) }
        let preferred = sortedOptions(for: preferredCodes)
        let remainder = sortedOptions(for: remainingCodes)
        return preferred + remainder
    }

    public static func displayName(for code: String) -> String {
        if code.isEmpty {
            return MoroL10n.Language.systemDefault
        }
        return makeOption(for: code)?.displayName ?? code
    }

    public static func canonicalLanguageCode(for identifier: String) -> String {
        normalize(identifier)
    }

    public static var systemDefaultLanguageCode: String {
        if let preferred = Locale.preferredLanguages.first, !preferred.isEmpty {
            let normalized = normalize(preferred)
            if !normalized.isEmpty {
                return normalized
            }
        }

        let identifier = Locale.autoupdatingCurrent.identifier
        let normalized = normalize(identifier)
        return normalized.isEmpty ? "en" : normalized
    }

    public static func selectionSummary(
        for code: String,
        defaultBehavior: PostLanguageDefaultBehavior
    ) -> String {
        if !code.isEmpty {
            return displayName(for: code)
        }

        switch defaultBehavior {
        case .systemDefault:
            return MoroL10n.Language.systemDefault
        case .appDefault(let defaultLanguageCode):
            let currentDefault = defaultLanguageCode.isEmpty
                ? MoroL10n.Language.systemDefault
                : displayName(for: defaultLanguageCode)
            return MoroL10n.Language.followAppDefault(currentDefault)
        case .serverDefault(let languageCode):
            guard !languageCode.isEmpty else { return MoroL10n.Language.systemDefault }
            return MoroL10n.Language.followAccountDefault(displayName(for: languageCode))
        }
    }

    public static func defaultOptionTitle(for behavior: PostLanguageDefaultBehavior) -> String {
        switch behavior {
        case .systemDefault:
            return MoroL10n.Language.systemDefault
        case .appDefault(let defaultLanguageCode):
            let currentDefault = defaultLanguageCode.isEmpty
                ? MoroL10n.Language.systemDefault
                : displayName(for: defaultLanguageCode)
            return MoroL10n.Language.followAppDefault(currentDefault)
        case .serverDefault(let languageCode):
            guard !languageCode.isEmpty else { return MoroL10n.Language.systemDefault }
            return MoroL10n.Language.followAccountDefault(displayName(for: languageCode))
        }
    }

    private static func makeOption(for identifier: String) -> PostLanguageOption? {
        let normalized = normalize(identifier)
        return makeOption(normalized)
    }

    private static func sortedOptions(for codes: [String]) -> [PostLanguageOption] {
        codes
            .compactMap { makeOption($0) }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private static func makeOption(_ code: String) -> PostLanguageOption? {
        let displayName = localizedDisplayName(for: code, locale: MoroL10n.preferredLocale)
        guard !displayName.isEmpty else { return nil }

        let nativeLocale = Locale(identifier: code)
        let nativeName = localizedDisplayName(for: code, locale: nativeLocale)
        let secondaryName: String?
        if nativeName.isEmpty || nativeName.compare(displayName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            secondaryName = nil
        } else {
            secondaryName = nativeName
        }

        return PostLanguageOption(
            code: code,
            displayName: displayName,
            nativeName: secondaryName
        )
    }

    private static func localizedDisplayName(for code: String, locale: Locale) -> String {
        if let identifierName = locale.localizedString(forIdentifier: code), !identifierName.isEmpty {
            return titleCased(identifierName, locale: locale)
        }
        if let languageName = locale.localizedString(forLanguageCode: code), !languageName.isEmpty {
            return titleCased(languageName, locale: locale)
        }
        return code
    }

    private static func titleCased(_ value: String, locale: Locale) -> String {
        let identifier = locale.identifier.lowercased()
        if identifier.hasPrefix("zh") || identifier.hasPrefix("ja") || identifier.hasPrefix("ko") {
            return value
        }
        return value.capitalized(with: locale)
    }

    private static func normalize(_ identifier: String) -> String {
        let normalized = identifier.replacingOccurrences(of: "_", with: "-")
        let lowercased = normalized.lowercased()

        if lowercased.hasPrefix("zh-hans") {
            return "zh-Hans"
        }
        if lowercased.hasPrefix("zh-hant") {
            return "zh-Hant"
        }
        if lowercased.hasPrefix("pt-br") {
            return "pt-BR"
        }

        let locale = Locale(identifier: normalized)
        if let languageCode = locale.language.languageCode?.identifier, !languageCode.isEmpty {
            return languageCode
        }
        if let fallback = normalized.split(separator: "-").first, !fallback.isEmpty {
            return String(fallback)
        }
        return normalized
    }
}
