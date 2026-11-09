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

func addJSONFiles(in directory: String, as snapshotDirectory: String) throws {
    let names = try fileManager.contentsOfDirectory(atPath: repository.appendingPathComponent(directory).path)
    for name in names where name.hasSuffix(".json") {
        snapshot["\(snapshotDirectory)/\(name)"] = try Data(
            contentsOf: repository.appendingPathComponent("\(directory)/\(name)"))
    }
}

// Released versions keep the copy and links they shipped with, so the tests check the
// newest version folder, the one the next submission will use, under a stable name.
let versionsDirectory = "metadata/app-store/version"
let versionNumber = { (name: String) in name.split(separator: ".").map { Int($0) ?? 0 } }
let currentVersion = try fileManager.contentsOfDirectory(
    atPath: repository.appendingPathComponent(versionsDirectory).path
).filter { $0.first?.isNumber == true }
    .max { versionNumber($0).lexicographicallyPrecedes(versionNumber($1)) }
guard let currentVersion else { fatalError("No App Store version metadata in \(versionsDirectory)") }

try addJSONFiles(in: "metadata/app-store/app-info", as: "metadata/app-store/app-info")
try addJSONFiles(in: "\(versionsDirectory)/\(currentVersion)", as: "\(versionsDirectory)/current")

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
