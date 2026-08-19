// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MoroModules",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MoroLocalization",
            targets: ["MoroLocalization"]
        ),
    ],
    targets: [
        .target(
            name: "MoroLocalization",
            path: "moro",
            sources: [
                "Core/Localization/MoroL10n.swift",
                "Core/Localization/PostLanguageSupport.swift",
                "Core/Services/TranslationService.swift",
            ],
            resources: [
                .process("Resources/Localizations/Moro.xcstrings"),
            ]
        ),
    ]
)
