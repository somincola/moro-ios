import Darwin
import Foundation
import Testing

/// Compile the extension's actual sources into this test target; do not mirror its writer.
@MainActor
struct ShareExtensionStagingTests {
    @Test func cancelledServiceCannotStartALatePreparation() async throws {
        let importer = MoroShareExtensionImportService()
        await importer.cancel()
        do {
            _ = try await importer.prepare(inputItems: [], accountID: "me")
            Issue.record("Cancellation must win even before the preparation task starts")
        } catch is CancellationError {}
    }

    @Test func movesOwnedCopiesWithoutHoldingTheIndexLockAndPreservesExistingMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data(#"[{"id":"existing","future_field":{"keep":true}}]"#.utf8)
        fixture.defaults.set(original, forKey: Fixture.indexKey)
        var moved = 0
        let writer = fixture.writer { source, destination in
            let descriptor = Darwin.open(fixture.lockURL.path, O_CREAT | O_RDWR, 0o600)
            defer { if descriptor >= 0 { Darwin.close(descriptor) } }
            try #require(descriptor >= 0)
            try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0, "Bulk file I/O must not hold the index lock")
            flock(descriptor, LOCK_UN)
            try FileManager.default.moveItem(at: source, to: destination)
            moved += 1
        }
        let content = try fixture.content()
        let id = try writer.stage(accountID: "me", content: content)
        let rows = try fixture.index()
        #expect(moved == 2 && rows.count == 2)
        #expect((rows.first?["future_field"] as? [String: Bool])?["keep"] == true)
        let attachments = try #require(rows.last?["attachments"] as? [[String: String]])
        #expect(attachments.map { $0["id"] } == ["image-0", "image-1"])
        for (index, attachment) in attachments.enumerated() {
            let relativePath = try #require(attachment["relativePath"])
            let stored = fixture.group.appendingPathComponent(relativePath)
            #expect(try Data(contentsOf: stored) == Data([UInt8(index + 1)]))
            #expect(!FileManager.default.fileExists(atPath: content.attachments[index].sourceURL.path))
        }
        try writer.remove(itemID: id)
        #expect(try fixture.index().count == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.group.appendingPathComponent(id).path))
    }

    @Test(arguments: [1, 2])
    func cancellingDuringFileTransferLeavesNoIndexEntryOrSharedFiles(cancelAfter: Int) async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let content = try fixture.content()
        var moved = 0
        let writer = fixture.writer { source, destination in
            try FileManager.default.moveItem(at: source, to: destination)
            moved += 1
            if moved == cancelAfter { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let operation = Task {
            do {
                _ = try writer.stage(accountID: "me", content: content)
                return false
            } catch is CancellationError { return true } catch {
                Issue.record("Unexpected cancellation error: \(error)")
                return false
            }
        }
        #expect(await operation.value)
        #expect(moved == cancelAfter)
        #expect(fixture.defaults.data(forKey: Fixture.indexKey) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.group.path).isEmpty)
        #expect(!Task.isCancelled)
    }

    @Test func cancellingBeforeStagingDoesNotMoveAnyFile() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let content = try fixture.content()
        let writer = fixture.writer()
        let operation = Task { try writer.stage(accountID: "me", content: content) }
        operation.cancel()
        do {
            _ = try await operation.value
            Issue.record("Expected cancellation before staging")
        } catch is CancellationError {}
        #expect(fixture.defaults.data(forKey: Fixture.indexKey) == nil)
        #expect(content.attachments.allSatisfy { FileManager.default.fileExists(atPath: $0.sourceURL.path) })
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.group.path).isEmpty)
    }

    @Test func busyIndexFailsWithoutOverwritingMetadataOrLeavingTransferredFiles() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let original = Data(#"[{"id":"existing"}]"#.utf8)
        fixture.defaults.set(original, forKey: Fixture.indexKey)
        let content = try fixture.content()
        let descriptor = Darwin.open(fixture.lockURL.path, O_CREAT | O_RDWR, 0o600)
        try #require(descriptor >= 0)
        defer {
            flock(descriptor, LOCK_UN)
            Darwin.close(descriptor)
        }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        do {
            _ = try fixture.writer().stage(accountID: "me", content: content)
            Issue.record("Expected a busy index")
        } catch {}
        #expect(fixture.defaults.data(forKey: Fixture.indexKey) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.group.path) == [".index.lock"])
    }

    @Test func briefContentionWithTheAppIsRetriedInsteadOfFailingTheShare() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let content = try fixture.content()
        let descriptor = Darwin.open(fixture.lockURL.path, O_CREAT | O_RDWR, 0o600)
        try #require(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) { flock(descriptor, LOCK_UN) }
        let id = try fixture.writer().stage(accountID: "me", content: content)
        #expect(try fixture.index().map { $0["id"] as? String } == [id])
    }

    @Test func anUnreadableIndexDoesNotBlockNewSharesAndIsBackedUp() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let garbage = Data("not-json".utf8)
        fixture.defaults.set(garbage, forKey: Fixture.indexKey)
        let id = try fixture.writer().stage(accountID: "me", content: try fixture.content())
        #expect(try fixture.index().map { $0["id"] as? String } == [id])
        #expect(fixture.defaults.data(forKey: Fixture.indexKey + "_corrupt_backup") == garbage)
    }

    @Test func aFailedCancellationLeavesATombstone() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let writer = fixture.writer()
        let id = try writer.stage(accountID: "me", content: try fixture.content())
        let descriptor = Darwin.open(fixture.lockURL.path, O_CREAT | O_RDWR, 0o600)
        try #require(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(throws: (any Error).self) { try writer.remove(itemID: id) }
        let marker = fixture.group.appendingPathComponent(MoroShareExtensionSharedContainer.cancelledMarkerPrefix + id)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.group.appendingPathComponent(id).path))
    }

    private struct Fixture {
        static let indexKey = "shared_compose_draft_staging_items_v1"
        let suite = "share-extension-staging-\(UUID())"
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("extension-staging-\(UUID())")
        let defaults: UserDefaults
        var group: URL { root.appendingPathComponent("group") }
        var lockURL: URL { group.appendingPathComponent(".index.lock") }

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        }
        func writer(transfer: ((URL, URL) throws -> Void)? = nil) -> MoroShareExtensionDraftStagingStore {
            .init(userDefaults: defaults, baseDirectoryURL: group, transferFile: transfer)
        }
        func content() throws -> MoroShareExtensionLoadedContent {
            let temporary = root.appendingPathComponent("owned")
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
            let attachments = try (0..<2).map { index -> MoroShareExtensionPreparedAttachment in
                let source = temporary.appendingPathComponent("\(index).png")
                try Data([UInt8(index + 1)]).write(to: source)
                return .init(sourceURL: source, fileName: "\(index).png", mimeType: "image/png", id: "image-\(index)")
            }
            return .init(text: "Caption", attachments: attachments, temporaryDirectoryURL: temporary)
        }
        func index() throws -> [[String: Any]] {
            let data = try #require(defaults.data(forKey: Self.indexKey))
            return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        }
        func cleanup() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
    }
}
