//
//  MoroReadableColumn.swift
//  moro
//

import SwiftUI

extension View {
    /// Caps reading content at a comfortable line length and centers it in the space it is
    /// given. On iPhone in portrait the content is already narrower than the cap, so nothing
    /// changes; on a wide display, such as iPhone Duo's inner display in landscape, posts stop
    /// stretching from edge to edge.
    func moroReadableColumn() -> some View {
        frame(maxWidth: MoroLayoutMetrics.readableColumnWidth)
            .frame(maxWidth: .infinity)
    }

    /// The same reading column for a `List`, which can't be framed narrower without cutting
    /// off its row backgrounds and swipe actions. The list stays full width and moves its
    /// rows' content in from both sides by the width beyond the cap: nothing on iPhone in
    /// portrait, where that width is zero.
    func moroReadableListMargins() -> some View {
        modifier(ReadableListMargins())
    }
}

private struct ReadableListMargins: ViewModifier {
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.horizontal, max(0, (width - MoroLayoutMetrics.readableColumnWidth) / 2))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                width = newWidth
            }
    }
}
