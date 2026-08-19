//
//  MoroCardSurfaceStyle.swift
//  moro
//
//  Shared card surface style for consistent corner radius and border treatment.
//

import SwiftUI

enum MoroCardSurfaceTone {
    case base
    case elevated
    case subtle
}

private struct MoroCardSurfaceModifier: ViewModifier {
    @Environment(\.moroTheme) private var theme

    let cornerRadius: CGFloat
    let tone: MoroCardSurfaceTone
    let bordered: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fillColor)
            )
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                }
            }
    }

    private var fillColor: Color {
        switch tone {
        case .base:
            return theme.colors.surfaceBase
        case .elevated:
            return theme.colors.surfaceElevated
        case .subtle:
            return theme.colors.surfaceSubtle
        }
    }
}

extension View {
    func moroCardSurface(
        cornerRadius: CGFloat = 14,
        tone: MoroCardSurfaceTone = .base,
        bordered: Bool = true
    ) -> some View {
        modifier(
            MoroCardSurfaceModifier(
                cornerRadius: cornerRadius,
                tone: tone,
                bordered: bordered
            )
        )
    }
}

