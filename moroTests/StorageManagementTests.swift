import Foundation
import Testing
import UIKit
@testable import moro

@Suite(.serialized) @MainActor
struct StorageManagementTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("storage-tests-" + UUID().uuidString)
    }
    private func solidImage(_ color: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
    }

    @Test func imageCacheServesSeededImagesAsStillsAndForgetsRemovedOnes() async {
        let url = URL(string: "https://example.invalid/storage-tests/\(UUID().uuidString).png")!
        let frames = [solidImage(.red), solidImage(.blue)]
        let animated = UIImage.animatedImage(with: frames, duration: 0.2)!
        ImageCache.shared.setImage(animated, for: url)

        // Callers draw with Image(uiImage:), so an animated entry comes back as its first frame.
        let cached = ImageCache.shared.image(for: url)
        #expect(cached != nil)
        #expect(cached?.images == nil)
        let loaded = await ImageCache.shared.loadReportingSource(from: url)
        #expect(loaded?.downloaded == false)

        ImageCache.shared.removeImages(for: [url])
        #expect(ImageCache.shared.image(for: url) == nil)
    }

    @Test func imageCacheLoadEndsWhenItsTaskIsCancelled() async {
        // Never answers; without cancellation this would wait for the request timeout.
        let url = URL(string: "http://10.255.255.1/storage-tests/\(UUID().uuidString).png")!
        let task = Task { await ImageCache.shared.load(from: url) }
        try? await Task.sleep(for: .milliseconds(50))
        let cancelled = Date()
        task.cancel()
        let image = await task.value
        #expect(image == nil)
        // A load that ignored cancellation would wait out the 60 s request timeout. The bound
        // is generous because CI runs tests in parallel on few cores, and a busy main actor
        // can delay the resumption by several seconds (12.8 s once on GitHub's runner).
        #expect(Date().timeIntervalSince(cancelled) < 30)
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
