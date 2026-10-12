//
//  Typography.swift
//  moro
//
//  Defines reusable font styles for Moro.
//

import SwiftUI

struct MoroTypography {
    // Mapped to semantic text styles so they scale with Dynamic Type. Each style's
    // default size matches the previous fixed size (title3=20, headline=17,
    // subheadline=15, footnote=13), so default-size appearance is unchanged.
    let title = Font.system(.title3, weight: .semibold)
    let subtitle = Font.system(.headline)
    let body = Font.system(.subheadline)
    let bodyStrong = Font.system(.subheadline, weight: .semibold)
    let caption = Font.system(.footnote)

    let bodyLineHeight: CGFloat = 20
    let titleLineHeight: CGFloat = 24
    let captionLineHeight: CGFloat = 16
}
