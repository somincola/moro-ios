//
//  ComposeMediaProcessor.swift
//  moro
//
//  Serial background preparation for media selected by the composer.
//

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
        mediaType: String
    ) throws -> PreparedMedia {
        // Keep the payload self-contained after the security-scoped URL closes so
        // failed uploads can still be retried without retaining a mapped file.
        let data = try Data(contentsOf: url)
        return try prepareImportedData(data, mimeType: mimeType, mediaType: mediaType)
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
