#if DEBUG
import AVFoundation
import SDWebImage
import SwiftUI

/// Offline production rows for viewport, GIF replay, export and avatar resource checks.
struct TimelineMediaHarnessView: View {
    @State private var posts: [Status] = []
    @State private var autoplay = ProcessInfo.processInfo.environment["UITEST_MEDIA_AUTOPLAY_OFF"] != "1"
    @State private var scope = MediaPlaybackScope(isActive: true, allowsAnimatedAvatars: true)
    @State private var sceneActive = true

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Autoplay GIFs", isOn: $autoplay).accessibilityIdentifier("media.harness.autoplay")
                Button(sceneActive ? "Cover timeline" : "Return to timeline") {
                    sceneActive.toggle()
                    scope.isActive = sceneActive
                }.accessibilityIdentifier("media.harness.cover")
            }.padding(.horizontal)
            TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                Text("active:\(TimelineAvatarAnimationPool.shared.activeCount) warm:\(TimelineAvatarAnimationPool.shared.warmCount) video:\(TimelineVideoPlayerPool.shared.activeCount)")
                    .font(.caption.monospacedDigit())
                    .accessibilityIdentifier("media.harness.resources")
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(posts) { post in
                        TimelinePostRow(status: post, threadContext: .none)
                        Divider()
                    }
                }
            }
            .accessibilityIdentifier("media.harness.timeline")
            .onScrollPhaseChange { _, phase in scope.isScrolling = phase != .idle }
        }
        .environment(\.moroPlaybackScope, scope)
        .environment(\.moroMediaPrefs, MoroMediaPreferences(autoplayGIFs: autoplay, videoAutoplayMode: .always))
        .moroTheme(MoroTheme())
        .task {
            do { posts = try await TimelineMediaFixture.posts() }
            catch { AppFeedbackCenter.shared.showError(error.localizedDescription) }
        }
    }
}

@MainActor enum TimelineMediaFixture {
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TimelineMediaFixture", isDirectory: true)
    static var avatarURL: URL { directory.appendingPathComponent("avatar.gif") }
    static var stillURL: URL { directory.appendingPathComponent("still.png") }
    static var videoURL: URL { directory.appendingPathComponent("animated.mp4") }

    static func prepare() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = ProfileMediaFixture.gifData(size: CGSize(width: 240, height: 240), frameDuration: 1)
        try data.write(to: avatarURL, options: .atomic)
        let image = SDAnimatedImage(data: data)!
        let still = UIImage(cgImage: image.cgImage!)
        try still.pngData()!.write(to: stillURL, options: .atomic)
        await SDImageCache.shared.store(image, imageData: data, forKey: avatarURL.absoluteString, toDisk: true)
        await SDImageCache.shared.store(still, forKey: stillURL.absoluteString, toDisk: true)
        for side: CGFloat in [96, 128, 132, 160, 2000, 8192] {
            let context: [SDWebImageContextOption: Any] = [.imageThumbnailPixelSize: NSValue(cgSize: CGSize(width: side, height: side))]
            let key = SDWebImageManager.shared.cacheKey(for: stillURL, context: context)!
            await SDImageCache.shared.store(still, forKey: key, toDisk: true)
        }
        if !FileManager.default.fileExists(atPath: videoURL.path) { try await makeVideo(at: videoURL) }
    }

    static func posts() async throws -> [Status] {
        try await prepare()
        let account = Account(id: "media-fixture", username: "media", acct: "media", displayName: "Media fixture",
            note: "", avatar: avatarURL.absoluteString, avatarStatic: stillURL.absoluteString,
            header: "", headerStatic: "", followersCount: 0, followingCount: 0, statusesCount: 30)
        return (0..<30).map { index in
            let raw = index == 1
            let attachment = Status.Attachment(id: "fixture-\(index)", type: raw ? "image" : index == 2 ? "video" : "gifv",
                url: raw ? avatarURL : videoURL, previewURL: stillURL,
                meta: .init(original: .init(width: 320, height: 180, aspect: 16.0 / 9.0), small: nil))
            return Status(id: "media-\(index)", content: "<p>\(raw ? "Original GIF" : index == 2 ? "Video" : "GIFV") playback fixture \(index)</p>",
                createdAt: Date(), account: account, mediaAttachments: [attachment],
                favouritesCount: 0, reblogsCount: 0, repliesCount: 0,
                bookmarked: false, favourited: false, reblogged: false)
        }
    }

    private static func makeVideo(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 96,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB])
        writer.add(input)
        guard writer.startWriting() else { throw MediaExportService.ExportError.saveFailed }
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<15 {
            while !input.isReadyForMoreMediaData, writer.status == .writing {
                try await Task.sleep(for: .milliseconds(10))
            }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 160, 96, kCVPixelFormatType_32ARGB, nil, &buffer)
            guard let pixels = buffer else { throw MediaExportService.ExportError.saveFailed }
            CVPixelBufferLockBaseAddress(pixels, [])
            if let address = CVPixelBufferGetBaseAddress(pixels) {
                address.assumingMemoryBound(to: UInt32.self).initialize(
                    repeating: frame < 7 ? 0xFFFF0000 : 0xFF00FF00,
                    count: CVPixelBufferGetBytesPerRow(pixels) * 96 / MemoryLayout<UInt32>.stride)
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            guard adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                throw MediaExportService.ExportError.saveFailed
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw MediaExportService.ExportError.saveFailed }
    }
}
#endif
