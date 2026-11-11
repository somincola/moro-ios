//
//  ComposeMediaType.swift
//  moro
//
//  Resolves a file extension to a correct MIME type + coarse media kind for upload.
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

nonisolated enum ComposeMediaType {
    /// Resolve a file extension to `(mimeType, mediaKind)` where `mediaKind` is `"image"`
    /// or `"video"`. Uses `UTType`, so e.g. `jpg` maps to `image/jpeg` (not the invalid
    /// `image/jpg` some servers reject) and `mov` to `video/quicktime`.
    static func resolve(fileExtension rawExtension: String) -> (mimeType: String, mediaKind: String) {
        let ext = rawExtension.lowercased()

        if let mime = UTType(filenameExtension: ext)?.preferredMIMEType {
            if mime.hasPrefix("video/") { return (mime, "video") }
            if mime.hasPrefix("image/") { return (mime, "image") }
        }

        // Fallback for extensions UTType can't resolve on this device.
        switch ext {
        case "mp4": return ("video/mp4", "video")
        case "mov": return ("video/quicktime", "video")
        case "jpg", "jpeg": return ("image/jpeg", "image")
        case "png": return ("image/png", "image")
        case "gif": return ("image/gif", "image")
        case "heic": return ("image/heic", "image")
        case "webp": return ("image/webp", "image")
        default: return ("image/jpeg", "image")
        }
    }
}

/// Photos' URL is valid only during the transfer callback. Own a copy until the
/// import finishes, then remove it on success, failure or cancellation.
nonisolated struct ComposePickedVideo: Transferable {
    let url: URL

    var mimeType: String {
        let resolved = ComposeMediaType.resolve(fileExtension: url.pathExtension)
        return resolved.mediaKind == "video" ? resolved.mimeType : "video/quicktime"
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            try ComposePickedVideo(copying: received.file)
        }
    }

    init(copying source: URL) throws {
        try Task.checkCancellation()
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("moro-picked-video-\(UUID().uuidString).\(ext)")
        do {
            try FileManager.default.copyItem(at: source, to: url)
            try Task.checkCancellation()
        } catch {
            removeTemporaryFile()
            throw error
        }
    }

    func removeTemporaryFile() { try? FileManager.default.removeItem(at: url) }
}
