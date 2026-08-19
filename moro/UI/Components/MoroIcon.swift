//
//  MoroIcon.swift
//  moro
//
//  Simple wrapper around SF Symbols respecting theme colors.
//

import SwiftUI

struct MoroIcon: View {
    let systemName: String
    var size: CGFloat = 17
    var color: Color?

    @Environment(\.moroTheme) private var theme

    var body: some View {
        Image(systemName: systemName)
            .moroScaledFont(size: size, weight: .regular)
            .foregroundStyle(color ?? theme.colors.textSecondary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

#Preview {
    MoroIcon(systemName: "heart")
}

