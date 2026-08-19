//
//  MoroCard.swift
//  moro
//
//  Lightweight container for grouping content (no heavy shadows).
//

import SwiftUI

struct MoroCard<Content: View>: View {
    @Environment(\.moroTheme) private var theme

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            content
        }
        .padding(theme.spacing.l)
        .background(theme.colors.background)
    }
}

#Preview {
    MoroCard {
        Text("Timeline item placeholder")
        MoroDivider()
        Text("Actions go here")
    }
    .padding()
    .background(Color(.systemGray6))
}

