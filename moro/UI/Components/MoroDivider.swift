//
//  MoroDivider.swift
//  moro
//
//  Thin divider matching design system.
//

import SwiftUI

struct MoroDivider: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.displayScale) private var displayScale
    
    private let leadingInset: CGFloat
    private let trailingInset: CGFloat
    private let height: CGFloat?
    
    init(leadingInset: CGFloat = 0, trailingInset: CGFloat = 0, height: CGFloat? = nil) {
        self.leadingInset = leadingInset
        self.trailingInset = trailingInset
        self.height = height
    }

    var body: some View {
        Rectangle()
            .fill(theme.colors.divider)
            .frame(height: height ?? (1 / displayScale))
            .padding(.leading, leadingInset)
            .padding(.trailing, trailingInset)
    }
}

#Preview {
    MoroDivider()
}
