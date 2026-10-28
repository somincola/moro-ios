//
//  Spacing.swift
//  moro
//
//  Centralized spacing scale using 4pt grid.
//

import CoreGraphics

/// Layout values shared by SwiftUI and UIKit page chrome.
enum MoroLayoutMetrics {
    static let contentHorizontalInset: CGFloat = 16
    static let timelineAvatarSize: CGFloat = 44
    static let timelineAvatarContentSpacing: CGFloat = 12

    static let timelineDividerInset =
        contentHorizontalInset + timelineAvatarSize + timelineAvatarContentSpacing

    /// The widest a column of posts grows before it centers instead (see `moroReadableColumn`).
    static let readableColumnWidth: CGFloat = 680
}

struct MoroSpacing {
    let micro: CGFloat = 2
    let xs: CGFloat = 4
    let hairline: CGFloat = 6
    let s: CGFloat = 8
    let sm: CGFloat = 10
    let m: CGFloat = 12
    let l: CGFloat = 16
    let xl: CGFloat = 20
    let xxl: CGFloat = 24
    let xxxl: CGFloat = 32

    /// Canonical horizontal edge for page headers and primary page content.
    let contentHorizontalInset: CGFloat = MoroLayoutMetrics.contentHorizontalInset

    // Timeline specific
    let timelineVertical: CGFloat = 14
    let timelineAvatarBody: CGFloat = 10
    let timelineBodyActions: CGFloat = 12
    var timelinePadding: CGFloat { contentHorizontalInset }
    /// Page inset + timeline avatar + avatar/content gap.
    var timelineDividerInset: CGFloat { MoroLayoutMetrics.timelineDividerInset }
    /// 48 (detail avatar) + 12 (avatar/content gap)
    let detailDividerInset: CGFloat = 60
}
