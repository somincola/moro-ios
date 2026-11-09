//
//  AppStoreMetadataTests.swift
//  moroTests
//


import Foundation
import XCTest

@testable import moro

final class AppStoreMetadataTests: XCTestCase {
    private struct AppInfoMetadata: Decodable {
        let name: String
        let subtitle: String
        let privacyPolicyUrl: String
        let privacyChoicesUrl: String
    }

    private struct VersionMetadata: Decodable {
        let description: String
        let keywords: String
        let marketingUrl: String
        let promotionalText: String
        let supportUrl: String
    }

    private struct StringCatalog: Decodable {
        let sourceLanguage: String
        let strings: [String: CatalogEntry]
    }

    private struct CatalogEntry: Decodable {
        let localizations: [String: CatalogLocalization]
    }

    /// A plain string, or plural variants (one, other, …) that each carry their own unit.
    private struct CatalogLocalization: Decodable {
        let stringUnit: CatalogStringUnit?
        let variations: CatalogVariations?

        /// Every form a reader can see, keyed by plural category ("" for a plain string).
        var forms: [(name: String, unit: CatalogStringUnit)] {
            if let stringUnit { return [("", stringUnit)] }
            return (variations?.plural ?? [:])
                .sorted { $0.key < $1.key }
                .map { ($0.key, $0.value.stringUnit) }
        }
    }

    private struct CatalogVariations: Decodable {
        let plural: [String: CatalogPluralForm]?
    }

    private struct CatalogPluralForm: Decodable {
        let stringUnit: CatalogStringUnit
    }

    private struct CatalogStringUnit: Decodable {
        let state: String
        let value: String
    }

    /// The newest version folder, the one the next submission uses (see the fixture script).
    private static let currentVersionMetadata = "metadata/app-store/version/current"

    private let expectedLocales: Set<String> = [
        "de-DE", "en-US", "es-ES", "fr-FR", "it", "ja", "pt-PT", "zh-Hans", "zh-Hant",
    ]

    private let expectedAppLocales: Set<String> = [
        "de", "en", "es", "fr", "it", "ja", "pt-PT", "zh-Hans", "zh-Hant",
    ]

    private lazy var repositorySnapshot: Result<[String: Data], Error> = Result {
        // Cloud's test worker has the built test bundle, not the source checkout.
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "RepositoryFixtures", withExtension: "plist")
        )
        return try PropertyListDecoder().decode([String: Data].self, from: Data(contentsOf: url))
    }

    func testAllStoreLocalesUseCanonicalBrandURLs() throws {
        let appInfo = try loadMetadata(
            at: "metadata/app-store/app-info",
            as: AppInfoMetadata.self
        )
        let version = try loadMetadata(
            at: Self.currentVersionMetadata,
            as: VersionMetadata.self
        )

        XCTAssertEqual(Set(appInfo.keys), expectedLocales)
        // A version can add store-only languages (Arabic since 1.0.5) on top of the app's.
        XCTAssertTrue(Set(version.keys).isSuperset(of: expectedLocales))

        for (locale, metadata) in appInfo {
            XCTAssertEqual(
                metadata.privacyPolicyUrl,
                MoroBrand.privacyPolicyURL.absoluteString,
                locale
            )
            // The privacy policy's "Data retention and your choices" section is where users
            // learn how to manage and delete their data.
            XCTAssertEqual(
                metadata.privacyChoicesUrl,
                MoroBrand.privacyPolicyURL.absoluteString,
                locale
            )
        }

        for (locale, metadata) in version {
            XCTAssertEqual(metadata.marketingUrl, MoroBrand.websiteURL.absoluteString, locale)
            XCTAssertEqual(metadata.supportUrl, MoroBrand.supportURL.absoluteString, locale)
        }
    }

    func testStoreMetadataFitsAppStoreCharacterLimits() throws {
        let appInfo = try loadMetadata(
            at: "metadata/app-store/app-info",
            as: AppInfoMetadata.self
        )
        let version = try loadMetadata(
            at: Self.currentVersionMetadata,
            as: VersionMetadata.self
        )

        for (locale, metadata) in appInfo {
            XCTAssertLessThanOrEqual(metadata.name.count, 30, "\(locale) name")
            XCTAssertLessThanOrEqual(metadata.subtitle.count, 30, "\(locale) subtitle")
        }

        for (locale, metadata) in version {
            XCTAssertLessThanOrEqual(metadata.description.count, 4_000, "\(locale) description")
            XCTAssertLessThanOrEqual(metadata.keywords.count, 100, "\(locale) keywords")
            XCTAssertLessThanOrEqual(metadata.promotionalText.count, 170, "\(locale) promotional text")
        }
    }

    func testDescriptionsDoNotAdvertiseRemovedThemeColorSwitching() throws {
        let version = try loadMetadata(
            at: Self.currentVersionMetadata,
            as: VersionMetadata.self
        )
        let obsoleteClaims = [
            "multiple themes",
            "mehreren Designs",
            "múltiples temas",
            "plusieurs thèmes",
            "più temi",
            "複数のテーマ",
            "vários temas",
            "多种主题",
            "多種主題",
        ]

        for (locale, metadata) in version {
            for claim in obsoleteClaims {
                XCTAssertFalse(metadata.description.localizedCaseInsensitiveContains(claim), "\(locale): \(claim)")
            }
        }
    }

    func testAppLocalizationCatalogHasNoLegacyBrandCopy() throws {
        let catalog = try sourceText(at: "moro/Resources/Localizations/Moro.xcstrings")
        let obsoleteCopy = [
            "https://somincola.org/moro",
            "moro.somincola.com",
            "support@somincola.org",
            "privacy@somincola.org",
            "contract@somincola.org",
            "lavender",
            "薰衣草",
        ]

        for value in obsoleteCopy {
            XCTAssertFalse(catalog.localizedCaseInsensitiveContains(value), value)
        }
    }

    func testAppLocalizationCatalogCoversEverySupportedLocale() throws {
        let catalog = try loadStringCatalog()

        XCTAssertEqual(catalog.sourceLanguage, "zh-Hans")
        XCTAssertTrue(expectedAppLocales.contains(catalog.sourceLanguage))

        for (key, entry) in catalog.strings {
            XCTAssertEqual(Set(entry.localizations.keys), expectedAppLocales, key)

            for (locale, localization) in entry.localizations {
                XCTAssertFalse(localization.forms.isEmpty, "\(key) [\(locale)] has no string")
                for form in localization.forms {
                    XCTAssertEqual(form.unit.state, "translated", "\(key) [\(locale)] \(form.name)")
                    XCTAssertFalse(
                        form.unit.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                        "\(key) [\(locale)] \(form.name)"
                    )
                }
            }
        }
    }

    func testAppLocalizationCatalogPreservesFormatPlaceholdersAcrossLocales() throws {
        let catalog = try loadStringCatalog()

        for (key, entry) in catalog.strings {
            let sourceLocalization = try XCTUnwrap(
                entry.localizations[catalog.sourceLanguage],
                "\(key) is missing its source localization"
            )
            let sourceForm = try XCTUnwrap(sourceLocalization.forms.first, "\(key) has no source string")
            let expectedPlaceholders = try formatPlaceholders(in: sourceForm.unit.value)

            // Every plural form must keep the source's arguments, so any count formats safely.
            for (locale, localization) in entry.localizations {
                for form in localization.forms {
                    XCTAssertEqual(
                        try formatPlaceholders(in: form.unit.value),
                        expectedPlaceholders,
                        "\(key) [\(locale)] \(form.name)"
                    )
                }
            }
        }
    }

    func testMoroL10nOnlyReferencesCatalogKeys() throws {
        let catalog = try loadStringCatalog()
        let source = try sourceText(at: "moro/Core/Localization/MoroL10n.swift")
        let expression = try NSRegularExpression(
            pattern: #"(?:text|format)\(\s*\"([^\"]+)\""#
        )
        let sourceRange = NSRange(source.startIndex..<source.endIndex, in: source)
        let sourceNSString = source as NSString
        let referencedKeys: Set<String> = Set(
            expression.matches(in: source, range: sourceRange).compactMap { match -> String? in
                guard match.numberOfRanges > 1 else { return nil }
                return sourceNSString.substring(with: match.range(at: 1))
            }
        )

        XCTAssertFalse(referencedKeys.isEmpty)
        for key in referencedKeys {
            XCTAssertNotNil(catalog.strings[key], key)
        }
    }

    func testAppTargetHasNoInAppPurchaseReferences() throws {
        let sourcePaths = [
            "moro/Resources/Localizations/Moro.xcstrings",
            "moro/Core/Localization/MoroL10n.swift",
            "moro.xcodeproj/project.pbxproj",
            "moro.xcodeproj/xcshareddata/xcschemes/moro.xcscheme",
            "moro.xcodeproj/xcshareddata/xcschemes/moroShareExtension.xcscheme",
        ]
        let forbiddenReferences = [
            "Moro Premium",
            "com.somincola.moro.premium",
            "MoroProducts.storekit",
            "StoreKitConfigurationFileReference",
            "restore purchases",
            "one-time purchase",
        ]

        for sourcePath in sourcePaths {
            let source = try sourceText(at: sourcePath)
            for reference in forbiddenReferences {
                XCTAssertFalse(
                    source.localizedCaseInsensitiveContains(reference),
                    "\(sourcePath): \(reference)"
                )
            }
        }

        XCTAssertNil(try repositorySnapshot.get()["MoroProducts.storekit"])
    }

    private func loadMetadata<Value: Decodable>(
        at relativePath: String,
        as type: Value.Type
    ) throws -> [String: Value] {
        let files = try repositorySnapshot.get().filter { $0.key.hasPrefix(relativePath + "/") }
        XCTAssertFalse(files.isEmpty, "Missing repository fixtures: \(relativePath)")
        var values: [String: Value] = [:]

        for (path, data) in files where path.hasSuffix(".json") {
            let file = URL(fileURLWithPath: path)
            values[file.deletingPathExtension().lastPathComponent] = try JSONDecoder().decode(
                Value.self,
                from: data
            )
        }
        return values
    }

    private func loadStringCatalog() throws -> StringCatalog {
        try JSONDecoder().decode(
            StringCatalog.self,
            from: sourceData(at: "moro/Resources/Localizations/Moro.xcstrings")
        )
    }

    private func sourceData(at path: String) throws -> Data {
        try XCTUnwrap(try repositorySnapshot.get()[path], "Missing repository fixture: \(path)")
    }

    private func sourceText(at path: String) throws -> String {
        try XCTUnwrap(String(data: sourceData(at: path), encoding: .utf8), "Invalid UTF-8: \(path)")
    }

    private func formatPlaceholders(in value: String) throws -> [String] {
        let expression = try NSRegularExpression(
            pattern: #"%(?:\d+\$)?(?:@|lld|%)"#
        )
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let valueNSString = value as NSString

        return expression.matches(in: value, range: range)
            .map { match in
                valueNSString.substring(with: match.range)
                    .replacingOccurrences(
                        of: #"%\d+\$"#,
                        with: "%",
                        options: .regularExpression
                    )
            }
            .sorted()
    }
}
