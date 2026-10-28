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
}
