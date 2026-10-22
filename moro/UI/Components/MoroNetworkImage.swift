//
//  MoroNetworkImage.swift
//  moro
//
//  Fills its frame with a network image (aspect-fill by default), backed by
//  SDWebImage (download + memory/disk cache + decode-time downsampling for large
//  images + animated support). The wrapper takes exactly the proposed frame, so
//  callers that pin a height — e.g. the profile banner — get no gap.
//

import SwiftUI

struct MoroNetworkImage: View {
    /// Decode cap for inline images. The fullscreen viewer looks its thumbnail up in the
    /// cache with the same value, so it must stay shared.
    static let thumbnailPixelSize: CGFloat = 2000

    let url: URL?
    var contentMode: ContentMode
    /// Keep chrome/avatar/link-preview imagery static by default. Media surfaces can opt in.
    var playAnimations: Bool

    init(
        url: URL?,
        placeholder: UIImage? = nil,
        contentMode: ContentMode = .fill,
        playAnimations: Bool = false
    ) {
        self.url = url
        self.contentMode = contentMode
        self.playAnimations = playAnimations
    }

    var body: some View {
        SDWebRemoteImage(
            url: url,
            // A generous cap: only outsized images (e.g. a banner) shrink; previews,
            // emoji and link thumbnails are already small and pass through untouched.
            thumbnailPixelSize: Self.thumbnailPixelSize,
            contentMode: contentMode == .fit ? .scaleAspectFit : .scaleAspectFill,
            allowsAnimation: playAnimations
        )
    }
}
