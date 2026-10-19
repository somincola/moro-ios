//
//  ScaledSystemFont.swift
//  moro
//
//  Dynamic Type helper: a fixed-point system font that scales with the user's
//  text-size setting (via @ScaledMetric) while preserving its exact base size at
//  the default content size. Use `.moroScaledFont(size:weight:design:relativeTo:)`
//  anywhere `.font(.system(size:weight:design:))` was used so icons, badges, and
//  text all respect Dynamic Type.
//

import SwiftUI
import UIKit

private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo textStyle: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(
            .system(
                size: size,
                weight: weight,
                design: design
            )
        )
    }
}

extension View {
    /// A system font of `size`/`weight`/`design` that scales with Dynamic Type,
    /// relative to `textStyle`. At the default text size the result matches
    /// `.font(.system(size:weight:design:))`.
    func moroScaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledSystemFont(size: size, weight: weight, design: design, relativeTo: textStyle))
    }
}

extension UIFont {
    /// A system font of `size`/`weight` that scales with Dynamic Type relative to
    /// `textStyle`. For UIKit text (UILabel/UITextView paths) that can't use
    /// `@ScaledMetric`. Scaled for the current content size category at call time.
    @MainActor
    static func moroScaled(
        ofSize size: CGFloat,
        weight: UIFont.Weight = .regular,
        relativeTo textStyle: UIFont.TextStyle = .body
    ) -> UIFont {
        UIFontMetrics(forTextStyle: textStyle)
            .scaledFont(
                for: .systemFont(
                    ofSize: size,
                    weight: weight
                )
            )
    }
}

extension DynamicTypeSize {
    /// Maps SwiftUI's Dynamic Type size to the UIKit content size category so
    /// component-owned UIKit text paths scale identically to SwiftUI text.
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}
