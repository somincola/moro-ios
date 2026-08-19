//
//  Spacing.swift
//  moro
//
//  Centralized spacing scale using 4pt grid.
//

import CoreGraphics

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

    // Timeline specific
    let timelineVertical: CGFloat = 14
    let timelineAvatarBody: CGFloat = 10
    let timelineBodyActions: CGFloat = 12
    let timelinePadding: CGFloat = 16
    /// 20 (row horizontal padding) + 44 (avatar) + 12 (avatar/content gap)
    let timelineDividerInset: CGFloat = 76
    /// 48 (detail avatar) + 12 (avatar/content gap)
    let detailDividerInset: CGFloat = 60
}
