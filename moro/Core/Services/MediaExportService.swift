//
//  MediaExportService.swift
//  moro
//
//  Saves, shares and copies post images using the original file rather than
//  the downscaled rendition shown on screen, so quality and GIF animation survive.
//

import Photos
import SDWebImage
import UIKit
import UniformTypeIdentifiers

@MainActor
enum MediaExportService {
    enum ExportError: Error {
        case downloadFailed
        case photoAccessDenied
        case saveFailed
    }

    /// A downloaded original with the type sniffed from its bytes (servers often
    /// serve extension-less or mislabeled URLs).
    struct ImageFile {
        let data: Data
        let type: UTType

        var fileExtension: String { type.preferredFilenameExtension ?? "jpg" }
    }

    // MARK: - Loading

    static func loadImage(from url: URL) async throws -> ImageFile {
        // The original is often already on disk (opened before, or a GIF that
        // autoplayed); only hit the network when it is not.
        let key = url.absoluteString
        if let cached = await Task.detached(priority: .userInitiated, operation: {
            SDImageCache.shared.diskImageData(forKey: key)
        }).value, UIImage(data: cached) != nil {
            return ImageFile(data: cached, type: sniffType(cached, url: url))
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ExportError.downloadFailed
            }
            guard UIImage(data: data) != nil else { throw ExportError.downloadFailed }
            return ImageFile(data: data, type: sniffType(data, url: url))
        } catch let error as ExportError {
            throw error
        } catch {
            throw ExportError.downloadFailed
        }
    }

    nonisolated static func sniffType(_ data: Data, url: URL) -> UTType {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
            let identifier = CGImageSourceGetType(source) as String?,
            let type = UTType(identifier) {
            return type
        }
        return UTType(filenameExtension: url.pathExtension) ?? .jpeg
    }

    // MARK: - Actions

    static func saveToPhotos(_ file: ImageFile) async throws {
        var status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard status == .authorized || status == .limited else { throw ExportError.photoAccessDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let options = PHAssetResourceCreationOptions()
                options.uniformTypeIdentifier = file.type.identifier
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: file.data, options: options)
            }
        } catch {
            throw ExportError.saveFailed
        }
    }

    static func copy(_ file: ImageFile) {
        if file.type.conforms(to: .gif) {
            UIPasteboard.general.setData(file.data, forPasteboardType: UTType.gif.identifier)
        } else if let image = UIImage(data: file.data) {
            UIPasteboard.general.image = image
        }
    }

    /// Writes the original to a temporary file so the share sheet offers
    /// "Save Image" and other apps receive the real format and name.
    static func shareableFile(_ file: ImageFile, sourceURL: URL) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SharedMedia", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        let name = (stem.isEmpty ? "image" : stem) + "." + file.fileExtension
        let destination = directory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: destination)
        try file.data.write(to: destination, options: .atomic)
        return destination
    }

    static func presentShareSheet(for fileURL: URL, sourceView: UIView? = nil) {
        guard let presenter = topViewController() else { return }
        let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            let anchor = sourceView ?? presenter.view
            popover.sourceView = anchor
            popover.sourceRect = anchor.map { CGRect(x: $0.bounds.midX, y: $0.bounds.midY, width: 1, height: 1) } ?? .zero
        }
        presenter.present(controller, animated: true)
    }

    static func message(for error: Error) -> String {
        switch error as? ExportError {
        case .photoAccessDenied: return MoroL10n.MediaExport.photoAccessDenied
        case .saveFailed: return MoroL10n.MediaExport.saveFailed
        default: return MoroL10n.MediaExport.downloadFailed
        }
    }

    private static func topViewController() -> UIViewController? {
        UIApplication.shared.moroTopViewController()
    }
}

/// The three actions offered from a long press, in the order they appear.
enum MediaExportAction: CaseIterable {
    case save, share, copy

    var title: String {
        switch self {
        case .save: return MoroL10n.MediaExport.saveToPhotos
        case .share: return MoroL10n.MediaExport.share
        case .copy: return MoroL10n.MediaExport.copy
        }
    }

    var systemImage: String {
        switch self {
        case .save: return "square.and.arrow.down"
        case .share: return "square.and.arrow.up"
        case .copy: return "doc.on.doc"
        }
    }

    /// Runs the action against the original file. Returns the success message to
    /// show, or nil when the share sheet takes over.
    @MainActor
    func perform(on url: URL, sourceView: UIView? = nil) async throws -> String? {
        let file = try await MediaExportService.loadImage(from: url)
        switch self {
        case .save:
            try await MediaExportService.saveToPhotos(file)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return MoroL10n.MediaExport.saved
        case .copy:
            MediaExportService.copy(file)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return MoroL10n.MediaExport.copied
        case .share:
            let fileURL = try MediaExportService.shareableFile(file, sourceURL: url)
            MediaExportService.presentShareSheet(for: fileURL, sourceView: sourceView)
            return nil
        }
    }
}
