//
//  LaunchScreenView.swift
//  moro
//
//  SwiftUI launch screen displayed while restoring session state.
//

import SwiftUI

struct LaunchScreenView: View {
    @Environment(\.moroTheme) private var theme
    
    var body: some View {
        ZStack {
            theme.colors.background.ignoresSafeArea()
            
            VStack(spacing: theme.spacing.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(theme.colors.primary500)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 40)
                        .foregroundStyle(theme.colors.primaryForeground)
                }
                .shadow(color: theme.colors.primary500.opacity(0.3), radius: 10, x: 0, y: 5)
            }
        }
    }
}

#Preview {
    LaunchScreenView()
        .moroTheme(MoroTheme())
}
