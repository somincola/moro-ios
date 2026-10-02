//
//  NavigationIconFactory.swift
//  moro
//
//  Custom-drawn navigation glyphs. TypeBar intentionally uses a
//  typographic language instead of mirroring SF Symbols.
//

import UIKit

enum NavigationIconFactory {
    static func image(
        for tab: MainTab,
        style: AppSettings.NavigationStyle,
        selected: Bool,
        primaryColor: UIColor,
        secondaryColor: UIColor,
        backgroundColor: UIColor = .clear,
        size: CGFloat = 30
    ) -> UIImage? {
        guard style == .editorial else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)

        return renderer.image { context in
            let rect = CGRect(x: 0, y: 0, width: size, height: size)
            let active = selected ? primaryColor : secondaryColor

            switch style {
            case .current:
                break
            case .editorial:
                drawTypeGlyph(
                    tab,
                    in: rect,
                    color: active,
                    fill: backgroundColor,
                    selected: selected
                )
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    // MARK: - Type Bar

    private static func drawTypeGlyph(
        _ tab: MainTab,
        in rect: CGRect,
        color: UIColor,
        fill: UIColor,
        selected: Bool
    ) {
        let text = String(tab.title.prefix(1))

        if selected {
            let underline = UIBezierPath(
                roundedRect: CGRect(x: rect.midX - 8, y: rect.maxY - 5, width: 16, height: 2.5),
                cornerRadius: 1.25
            )
            color.withAlphaComponent(0.9).setFill()
            underline.fill()
        }

        let font = UIFont.systemFont(ofSize: 17, weight: selected ? .black : .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: 0.8,
        ]
        let size = text.size(withAttributes: attributes)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 - 1)
        text.draw(at: origin, withAttributes: attributes)
    }
}
