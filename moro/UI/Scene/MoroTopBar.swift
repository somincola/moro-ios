//
//  MoroTopBar.swift
//  moro
//
//  Shared top bar whose visual role is supplied by a Scene descriptor.
//

import SwiftUI

struct MoroTopBar<Leading: View, Trailing: View>: View {
    @Environment(\.moroTheme) private var theme

    let role: MoroTopBarRole
    let title: String
    let subtitle: String?
    let height: CGFloat
    let titleSize: CGFloat?
    let leading: Leading
    let trailing: Trailing

    init(
        role: MoroTopBarRole,
        title: String,
        subtitle: String? = nil,
        height: CGFloat = 52,
        titleSize: CGFloat? = nil,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.role = role
        self.title = title
        self.subtitle = subtitle
        self.height = height
        self.titleSize = titleSize
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            leading

            VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 2) {
                Group {
                    if let titleSize {
                        Text(title)
                            .moroScaledFont(size: titleSize, weight: .semibold, relativeTo: .title2)
                    } else {
                        Text(title)
                            .font(theme.typography.title)
                            .fontWeight(.bold)
                    }
                }

                if let subtitle {
                    Text(subtitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(role.secondaryForegroundColor(in: theme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(role.foregroundColor(in: theme))
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .frame(height: height, alignment: .bottom)
        .background(role.backgroundColor(in: theme))
        .overlay(alignment: .bottom) {
            if role.showsDivider {
                Rectangle()
                    .fill(theme.colors.borderSubtle)
                    .frame(height: 1)
            }
        }
    }
}
