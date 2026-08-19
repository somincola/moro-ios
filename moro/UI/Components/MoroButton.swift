//
//  MoroButton.swift
//  moro
//
//  Reusable branded button.
//

import SwiftUI

struct MoroButton: View {
    enum Kind {
        case primary
        case secondary
        case tertiary
    }

    let title: String
    let kind: Kind
    var isLoading: Bool = false
    let action: () -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(theme.typography.subtitle)
                    .opacity(isLoading ? 0 : 1)

                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(textColor)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundColor(textColor)
            .background(backgroundColor)
            .overlay(border)
            .cornerRadius(10)
            .opacity(isEnabled || isLoading ? 1 : 0.4)
        }
        .buttonStyle(.plain)
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary:
            return theme.colors.primary500
        case .secondary:
            return Color.clear
        case .tertiary:
            return Color.clear
        }
    }

    private var textColor: Color {
        switch kind {
        case .primary:
            return theme.colors.primaryForeground
        case .secondary, .tertiary:
            return theme.colors.primary500
        }
    }

    private var border: some View {
        Group {
            if kind == .secondary {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(theme.colors.primary300, lineWidth: 1)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.clear, lineWidth: 0)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        MoroButton(title: "Primary", kind: .primary) {}
        MoroButton(title: "Secondary", kind: .secondary) {}
        MoroButton(title: "Tertiary", kind: .tertiary) {}
        MoroButton(title: "Loading", kind: .primary, isLoading: true) {}
    }
    .padding()
}
