//
//  Typography.swift
//  moro
//
//  Defines reusable font styles for Moro.
//

import SwiftUI
import UIKit

struct MoroTypography {
    // Mapped to semantic text styles so they scale with Dynamic Type. Each style's
    // default size matches the previous fixed size (title3=20, headline=17,
    // subheadline=15, footnote=13), so default-size appearance is unchanged.
    let title: Font
    let subtitle: Font
    let body: Font
    let bodyStrong: Font
    let caption: Font

    let bodyLineHeight: CGFloat = 20
    let titleLineHeight: CGFloat = 24
    let captionLineHeight: CGFloat = 16

    /// `fontScale` is the in-app font scale, stacked on
    /// top of Dynamic Type. At 1.0 the semantic styles are used directly (identical to
    /// the previous behaviour); otherwise the base sizes are multiplied by the scale
    /// and run through `UIFontMetrics` for `dynamicTypeSize`, so both scalings apply.
    init(fontScale: CGFloat = 1.0, dynamicTypeSize: DynamicTypeSize = .large) {
        if fontScale == 1.0 {
            title = Font.system(.title3, weight: .semibold)
            subtitle = Font.system(.headline)
            body = Font.system(.subheadline)
            bodyStrong = Font.system(.subheadline, weight: .semibold)
            caption = Font.system(.footnote)
        } else {
            let traits = UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
            func scaled(
                _ base: CGFloat, _ style: UIFont.TextStyle, _ weight: UIFont.Weight = .regular
            ) -> Font {
                Font(
                    UIFontMetrics(forTextStyle: style).scaledFont(
                        for: .systemFont(ofSize: base * fontScale, weight: weight),
                        compatibleWith: traits
                    )
                )
            }
            title = scaled(20, .title3, .semibold)
            subtitle = scaled(17, .headline, .semibold)
            body = scaled(15, .subheadline)
            bodyStrong = scaled(15, .subheadline, .semibold)
            caption = scaled(13, .footnote)
        }
    }
}
