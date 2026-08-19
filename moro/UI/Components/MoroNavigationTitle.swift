//
//  MoroNavigationTitle.swift
//  moro
//
//  Compact navigation title for Moro screens.
//

import SwiftUI

struct MoroNavigationTitle: View {
    let title: String
    var subtitle: String?
    var alignment: HorizontalAlignment = .leading

    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(theme.typography.title)
                .foregroundStyle(theme.colors.textPrimary)

            if let subtitle {
                Text(subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .multilineTextAlignment(alignment == .center ? .center : .leading)
    }
}

#Preview {
    MoroNavigationTitle(title: "Home", subtitle: "Reading-first timeline")
}

