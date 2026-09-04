import Foundation

// The test worker in Xcode Cloud has build products, but no source checkout.
// Snapshot only the inputs inspected by AppStoreMetadataTests into its bundle.
let environment = ProcessInfo.processInfo.environment
guard let sourceRoot = environment["SRCROOT"],
      let outputPath = environment["SCRIPT_OUTPUT_FILE_0"] else {
    fatalError("Run this script from the test target's fixture build phase")
}
let repository = URL(fileURLWithPath: sourceRoot, isDirectory: true)
let fileManager = FileManager.default
var snapshot: [String: Data] = [:]

for directory in ["metadata/app-store/app-info", "metadata/app-store/version/1.0.0"] {
    let names = try fileManager.contentsOfDirectory(atPath: repository.appendingPathComponent(directory).path)
    for name in names where name.hasSuffix(".json") {
        let path = "\(directory)/\(name)"
        snapshot[path] = try Data(contentsOf: repository.appendingPathComponent(path))
    }
}

for path in [
    "moro/Resources/Localizations/Moro.xcstrings",
    "moro/Core/Localization/MoroL10n.swift",
    "moro.xcodeproj/project.pbxproj",
    "moro.xcodeproj/xcshareddata/xcschemes/moro.xcscheme",
    "moro.xcodeproj/xcshareddata/xcschemes/moroShareExtension.xcscheme",
] {
    snapshot[path] = try Data(contentsOf: repository.appendingPathComponent(path))
}

// Keep the negative existence assertion without declaring a nonexistent file
// as a required input. Only directory names are read; its contents aren't needed.
if try fileManager.contentsOfDirectory(atPath: sourceRoot).contains("MoroProducts.storekit") {
    snapshot["MoroProducts.storekit"] = Data()
}

let encoder = PropertyListEncoder()
encoder.outputFormat = .binary
// A single declared output also replaces deleted inputs on incremental builds.
try encoder.encode(snapshot).write(to: URL(fileURLWithPath: outputPath))
print("Packaged \(snapshot.count) repository fixtures for unit tests")
