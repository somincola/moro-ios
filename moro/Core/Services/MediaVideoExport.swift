import AVFoundation
import Photos
import UIKit
import UniformTypeIdentifiers

extension MediaExportService {
    struct VideoFile {
        let url: URL
        let type: UTType
    }

    /// GIFV is a video file on Mastodon. Keep that original, rather than exporting a still
    /// frame or renaming MP4 bytes to .gif. Downloads and Photos both use files on disk.
    static func loadVideo(from url: URL, session: URLSession = .shared) async throws -> VideoFile {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedMedia/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let downloaded: URL
            let mime: String?
            if url.isFileURL {
                downloaded = url
                mime = nil
            } else {
                let result = try await session.download(from: url)
                downloaded = result.0
                mime = result.1.mimeType
                guard let response = result.1 as? HTTPURLResponse,
                      (200..<300).contains(response.statusCode) else {
                    try? FileManager.default.removeItem(at: downloaded)
                    throw ExportError.downloadFailed
                }
            }
            let type = mime.flatMap { UTType(mimeType: $0) }.flatMap { $0.conforms(to: .movie) ? $0 : nil }
                ?? UTType(filenameExtension: url.pathExtension).flatMap { $0.conforms(to: .movie) ? $0 : nil }
                ?? .mpeg4Movie
            let destination = directory.appendingPathComponent("media.\(type.preferredFilenameExtension ?? "mp4")")
            if url.isFileURL {
                try FileManager.default.copyItem(at: downloaded, to: destination)
            } else {
                try FileManager.default.moveItem(at: downloaded, to: destination)
            }
            try Task.checkCancellation()
            let tracks = try await AVURLAsset(url: destination).loadTracks(withMediaType: .video)
            guard !tracks.isEmpty else { throw ExportError.downloadFailed }
            return VideoFile(url: destination, type: type)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            if error is CancellationError { throw error }
            throw ExportError.downloadFailed
        }
    }

    static func saveToPhotos(_ file: VideoFile) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        try Task.checkCancellation()
        guard status == .authorized || status == .limited else { throw ExportError.photoAccessDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = file.type.identifier
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: file.url, options: options)
            }
        } catch { throw ExportError.saveFailed }
    }
}

extension MediaExportAction {
    static func available(for attachment: Status.Attachment) -> [Self] {
        attachment.type == "gifv" || attachment.type == "video" ? [.save, .share] : allCases
    }

    @MainActor
    func perform(on attachment: Status.Attachment, sourceView: UIView? = nil) async throws -> String? {
        guard attachment.type == "gifv" || attachment.type == "video" else {
            return try await perform(on: attachment.url, sourceView: sourceView)
        }
        let file = try await MediaExportService.loadVideo(from: attachment.url)
        do {
            try Task.checkCancellation()
            switch self {
            case .save:
                defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
                try await MediaExportService.saveToPhotos(file)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return MoroL10n.MediaExport.saved
            case .share:
                MediaExportService.presentShareSheet(for: file.url, sourceView: sourceView,
                                                    removeAfterSharing: true)
                return nil
            case .copy:
                throw MediaExportService.ExportError.downloadFailed
            }
        } catch {
            try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
            throw error
        }
    }
}
