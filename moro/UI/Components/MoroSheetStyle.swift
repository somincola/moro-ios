//
//  MoroSheetStyle.swift
//  moro
//
//  Shared sheet surface style to keep modal presentation consistent across modules.
//

import SwiftUI

private struct MoroSheetSurfaceModifier: ViewModifier {
    @Environment(\.moroTheme) private var theme

    let detents: Set<PresentationDetent>
    let dragIndicator: Visibility
    let cornerRadius: CGFloat?

    func body(content: Content) -> some View {
        content
            .presentationDetents(detents)
            .presentationDragIndicator(dragIndicator)
            .presentationCornerRadius(cornerRadius)
            .presentationBackground(theme.colors.background)
    }
}

extension View {
    /// Apply Moro's default sheet appearance and behavior.
    func moroSheetSurface(
        detents: Set<PresentationDetent>,
        dragIndicator: Visibility = .visible,
        cornerRadius: CGFloat? = 16
    ) -> some View {
        modifier(
            MoroSheetSurfaceModifier(
                detents: detents,
                dragIndicator: dragIndicator,
                cornerRadius: cornerRadius
            )
        )
    }
}

