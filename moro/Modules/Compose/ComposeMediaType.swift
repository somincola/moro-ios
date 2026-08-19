//
//  ComposeMediaType.swift
//  moro
//
//  Resolves a file extension to a correct MIME type + coarse media kind for upload.
//

import Foundation
import UniformTypeIdentifiers

enum ComposeMediaType {
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
