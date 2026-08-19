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

    private struct CatalogLocalization: Decodable {
        let stringUnit: CatalogStringUnit
    }

    private struct CatalogStringUnit: Decodable {
        let state: String
        let value: String
    }

    private let expectedLocales: Set<String> = [
        "de-DE", "en-US", "es-ES", "fr-FR", "it", "ja", "pt-PT", "zh-Hans", "zh-Hant",
    ]

    private let expectedAppLocales: Set<String> = [
        "de", "en", "es", "fr", "it", "ja", "pt-PT", "zh-Hans", "zh-Hant",
    ]

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    func testAllStoreLocalesUseCanonicalBrandURLs() throws {
        let appInfo = try loadMetadata(
            at: "metadata/app-store/app-info",
            as: AppInfoMetadata.self
        )
        let version = try loadMetadata(
            at: "metadata/app-store/version/1.0.0",
            as: VersionMetadata.self
        )

        XCTAssertEqual(Set(appInfo.keys), expectedLocales)
        XCTAssertEqual(Set(version.keys), expectedLocales)

        for (locale, metadata) in appInfo {
            XCTAssertEqual(
                metadata.privacyPolicyUrl,
                MoroBrand.privacyPolicyURL.absoluteString,
                locale
            )
            XCTAssertEqual(
                metadata.privacyChoicesUrl,
                MoroBrand.termsOfUseURL.absoluteString,
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
            at: "metadata/app-store/version/1.0.0",
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
            at: "metadata/app-store/version/1.0.0",
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
        let catalogURL = repositoryRoot
            .appendingPathComponent("moro/Resources/Localizations/Moro.xcstrings")
        let catalog = try String(contentsOf: catalogURL, encoding: .utf8)
        let obsoleteCopy = [
            "https://somincola.org/moro",
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
                XCTAssertEqual(localization.stringUnit.state, "translated", "\(key) [\(locale)]")
                XCTAssertFalse(
                    localization.stringUnit.value
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty,
                    "\(key) [\(locale)]"
                )
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
            let expectedPlaceholders = try formatPlaceholders(
                in: sourceLocalization.stringUnit.value
            )

            for (locale, localization) in entry.localizations {
                XCTAssertEqual(
                    try formatPlaceholders(in: localization.stringUnit.value),
                    expectedPlaceholders,
                    "\(key) [\(locale)]"
                )
            }
        }
    }

    func testMoroL10nOnlyReferencesCatalogKeys() throws {
        let catalog = try loadStringCatalog()
        let sourceURL = repositoryRoot
            .appendingPathComponent("moro/Core/Localization/MoroL10n.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
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
            let sourceURL = repositoryRoot.appendingPathComponent(sourcePath)
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for reference in forbiddenReferences {
                XCTAssertFalse(
                    source.localizedCaseInsensitiveContains(reference),
                    "\(sourcePath): \(reference)"
                )
            }
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: repositoryRoot.appendingPathComponent("MoroProducts.storekit").path
            )
        )
    }

    private func loadMetadata<Value: Decodable>(
        at relativePath: String,
        as type: Value.Type
    ) throws -> [String: Value] {
        let directory = repositoryRoot.appendingPathComponent(relativePath)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        var values: [String: Value] = [:]

        for file in files where file.pathExtension == "json" {
            values[file.deletingPathExtension().lastPathComponent] = try JSONDecoder().decode(
                Value.self,
                from: Data(contentsOf: file)
            )
        }
        return values
    }

    private func loadStringCatalog() throws -> StringCatalog {
        let catalogURL = repositoryRoot
            .appendingPathComponent("moro/Resources/Localizations/Moro.xcstrings")
        return try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: catalogURL))
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
