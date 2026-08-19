//
//  PageScaffold.swift
//  moro
//
//  Shared page layout with floating header and consistent background.
//

import SwiftUI

struct PageScaffold<Leading: View, Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String?
    var headerHeight: CGFloat = 52
    let titleSize: CGFloat?
    let scene: MoroSceneDescriptor
    let leading: () -> Leading
    let trailing: () -> Trailing
    let content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        headerHeight: CGFloat = 52,
        titleSize: CGFloat? = nil,
        scene: MoroSceneDescriptor = .legacyPageScaffold,
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerHeight = headerHeight
        self.titleSize = titleSize
        self.scene = scene
        self.leading = leading
        self.trailing = trailing
        self.content = content
    }

    private var resolvedHeaderHeight: CGFloat {
        subtitle == nil ? headerHeight : max(headerHeight, 66)
    }

    var body: some View {
        MoroSceneHost(descriptor: scene) {
            ZStack(alignment: .top) {
                content()
                    .padding(.top, resolvedHeaderHeight)

                header
            }
        }
        .navigationBarHidden(true)
    }

    @ViewBuilder
    private var header: some View {
        MoroTopBar(
            role: scene.topBar,
            title: title,
            subtitle: subtitle,
            height: resolvedHeaderHeight,
            titleSize: titleSize,
            leading: {
                leading()
            },
            trailing: {
                trailing()
            }
        )
    }
}
