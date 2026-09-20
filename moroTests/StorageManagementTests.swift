import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct StorageManagementTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("storage-tests-" + UUID().uuidString)
    }
    private let firstURL = URL(string: "https://example.com/first.png")!
    private let secondURL = URL(string: "https://example.com/second.png")!

    @Test func diskQuotaAndClearAwaitQueuedWritesAndRejectOldDownloads() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ImageDiskCache(directory: directory, maximumBytes: 5)
        let generation = cache.writeGeneration
        cache.store(Data([1, 2, 3]), for: firstURL, generation: generation)
        #expect(await cache.size() == 3)
        cache.store(Data([4, 5, 6]), for: secondURL, generation: generation)
        #expect(await cache.size() == 3)
        #expect(cache.data(for: firstURL) == nil)
        #expect(cache.data(for: secondURL) == Data([4, 5, 6]))
        try await cache.clear()
        cache.store(Data([7]), for: firstURL, generation: generation)
        #expect(await cache.size() == 0)
        cache.store(Data([8]), for: firstURL, generation: cache.writeGeneration)
        #expect(await cache.size() == 1)
    }

    @Test func imageExpirationAndDiskInventoryWorkAcrossInstances() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ImageDiskCache(directory: directory)
        cache.store(Data([1, 2]), for: firstURL, generation: cache.writeGeneration)
        #expect(await cache.size() == 2)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-8 * 86_400)], ofItemAtPath: files[0].path)
        let cold = ImageDiskCache(directory: directory)
        #expect(await cold.size() == 0)
        #expect(cold.data(for: firstURL) == nil)
    }

    @Test func sizeReflectsFilesPurgedByTheSystem() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = ImageDiskCache(directory: directory)
        cache.store(Data([1, 2, 3]), for: firstURL, generation: cache.writeGeneration)
        #expect(await cache.size() == 3)
        try FileManager.default.removeItem(at: directory)
        #expect(await cache.size() == 0)
    }

    @Test func clearIsScopedAndDoesNotTouchSiblingUserFiles() async throws {
        let root = directory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let draftAttachment = root.appendingPathComponent("draft-photo.jpg")
        try Data([1, 2, 3]).write(to: draftAttachment)
        let cache = ImageDiskCache(directory: root.appendingPathComponent("images"))
        cache.store(Data([4]), for: firstURL, generation: cache.writeGeneration)
        try await cache.clear()
        #expect(try Data(contentsOf: draftAttachment) == Data([1, 2, 3]))
    }

    @Test func timelineClearKeepsUnreadMarkersAcrossColdReloadAndPendingPersistence() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = TimelineCache(directory: directory)
        for account in ["a", "b"] {
            await cache.set(statuses: [ThreadReadingFixtures.status("1")], for: account, filter: .home)
            await cache.setLastSeenStatuses(["1"], for: account, filter: .home)
        }
        #expect(await cache.contentDiskSize() > 0)
        try await cache.clearContentCache()
        await cache.flushPendingWrites()
        #expect(await cache.contentDiskSize() == 0)
        let cold = TimelineCache(directory: directory)
        for account in ["a", "b"] {
            #expect(await cold.getStatuses(for: account, filter: .home) == nil)
            #expect(await cold.getLastSeenStatuses(for: account, filter: .home) == ["1"])
        }
    }
}
