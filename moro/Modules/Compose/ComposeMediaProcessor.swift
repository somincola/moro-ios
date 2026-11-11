//
//  ComposeMediaProcessor.swift
//  moro
//
//  Serial background preparation for media selected by the composer.
//

import AVFoundation
import Foundation
import ImageIO
import UIKit

actor ComposeMediaProcessor {
    struct PreparedMedia: @unchecked Sendable {
        let uploadData: Data
        let uploadMimeType: String
        let mediaType: String
        let previewImage: UIImage?
    }

    enum ProcessingError: Error {
        case invalidImage
        /// Still above the server's video limit after re-encoding to 720p.
        case videoTooLarge
    }

    static let shared = ComposeMediaProcessor()

    private let maximumUploadPixelSize: CGFloat = 1920
    private let maximumPreviewPixelSize: CGFloat = 720

    func preparePhotoData(_ data: Data) throws -> PreparedMedia {
        try autoreleasepool {
            try Task.checkCancellation()
            guard let uploadImage = downsampledImage(
                from: data,
                maximumPixelSize: maximumUploadPixelSize
            ), let uploadData = uploadImage.jpegData(compressionQuality: 0.8) else {
                throw ProcessingError.invalidImage
            }

            try Task.checkCancellation()
            return PreparedMedia(
                uploadData: uploadData,
                uploadMimeType: "image/jpeg",
                mediaType: "image",
                previewImage: downsampledImage(
                    from: uploadData,
                    maximumPixelSize: maximumPreviewPixelSize
                )
            )
        }
    }

    func prepareCameraImage(_ image: UIImage) throws -> PreparedMedia {
        try autoreleasepool {
            try Task.checkCancellation()
            let uploadImage = resizedImage(image, maximumPixelSize: maximumUploadPixelSize)
            guard let uploadData = uploadImage.jpegData(compressionQuality: 0.8) else {
                throw ProcessingError.invalidImage
            }

            try Task.checkCancellation()
            return PreparedMedia(
                uploadData: uploadData,
                uploadMimeType: "image/jpeg",
                mediaType: "image",
                previewImage: resizedImage(
                    uploadImage,
                    maximumPixelSize: maximumPreviewPixelSize
                )
            )
        }
    }

    func prepareFile(
        at url: URL,
        mimeType: String,
        mediaType: String,
        videoSizeLimit: Int = ComposeMediaSelectionPolicy.defaultVideoSizeLimit
    ) async throws -> PreparedMedia {
        if mediaType == "video" {
            return try await prepareVideoFile(at: url, mimeType: mimeType, sizeLimit: videoSizeLimit)
        }
        // Keep the payload self-contained after the security-scoped URL closes so
        // failed uploads can still be retried without retaining a mapped file.
        let data = try Data(contentsOf: url)
        return try prepareImportedData(data, mimeType: mimeType, mediaType: mediaType)
    }

    /// Uploads the original when it fits the server's limit. A larger video (a minute of
    /// 4K is several hundred MB) is re-encoded to 1080p, then 720p, before giving up.
    func prepareVideoFile(at url: URL, mimeType: String, sizeLimit: Int) async throws -> PreparedMedia {
        try Task.checkCancellation()
        let preview = await videoThumbnail(for: url)
        var uploadURL = url
        var uploadMimeType = mimeType
        var exportedURL: URL?
        defer { if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) } }

        if fileSize(of: url) > sizeLimit {
            var fitted = false
            var didExport = false
            var exportError: Error?
            for preset in [AVAssetExportPreset1920x1080, AVAssetExportPreset1280x720] {
                try Task.checkCancellation()
                if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("moro-video-\(UUID().uuidString).mp4")
                exportedURL = destination
                guard let session = AVAssetExportSession(asset: AVURLAsset(url: url), presetName: preset) else {
                    continue
                }
                session.shouldOptimizeForNetworkUse = true
                do {
                    try await session.export(to: destination, as: .mp4)
                    didExport = true
                } catch {
                    try Task.checkCancellation()
                    exportError = error
                    continue
                }
                if fileSize(of: destination) <= sizeLimit {
                    uploadURL = destination
                    uploadMimeType = "video/mp4"
                    fitted = true
                    break
                }
            }
            guard fitted else {
                if !didExport, let exportError { throw exportError }
                throw ProcessingError.videoTooLarge
            }
        }

        try Task.checkCancellation()
        let data = try Data(contentsOf: uploadURL)
        return PreparedMedia(
            uploadData: data, uploadMimeType: uploadMimeType, mediaType: "video", previewImage: preview)
    }

    private func fileSize(of url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    private func videoThumbnail(for url: URL) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumPreviewPixelSize, height: maximumPreviewPixelSize)
        guard let (image, _) = try? await generator.image(at: .zero) else { return nil }
        return UIImage(cgImage: image)
    }

    func prepareImportedData(
        _ data: Data,
        mimeType: String,
        mediaType: String
    ) throws -> PreparedMedia {
        try autoreleasepool {
            try Task.checkCancellation()
            return PreparedMedia(
                uploadData: data,
                uploadMimeType: mimeType,
                mediaType: mediaType,
                previewImage: mediaType == "image"
                    ? downsampledImage(
                        from: data,
                        maximumPixelSize: maximumPreviewPixelSize
                    )
                    : nil
            )
        }
    }

    private func downsampledImage(
        from data: Data,
        maximumPixelSize: CGFloat
    ) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(max(1, maximumPixelSize)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    private func resizedImage(
        _ image: UIImage,
        maximumPixelSize: CGFloat
    ) -> UIImage {
        let longestEdge = max(image.size.width, image.size.height)
        guard longestEdge > maximumPixelSize, longestEdge > 0 else { return image }

        let scale = maximumPixelSize / longestEdge
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
