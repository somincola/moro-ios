//
//  ReportReasonCard.swift
//  moro
//
//  Card component for displaying a report reason option.
//

import SwiftUI

struct ReportReasonCard: View {
    @Environment(\.moroTheme) private var theme
    
    let reason: ReportReason
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: theme.spacing.m) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? theme.colors.primary500 : theme.colors.textTertiary, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    
                    if isSelected {
                        Circle()
                            .fill(theme.colors.primary500)
                            .frame(width: 12, height: 12)
                    }
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(reason.title)
                        .font(theme.typography.subtitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                    
                    Text(reason.description)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }
                
                Spacer()
                
                // Checkmark when selected
                if isSelected {
                    Image(systemName: "checkmark")
                        .moroScaledFont(size: 14, weight: .bold)
                        .foregroundStyle(theme.colors.primary500)
                }
            }
            .padding(theme.spacing.m)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? theme.colors.surfaceBase : theme.colors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? theme.colors.primary500 : theme.colors.border, lineWidth: isSelected ? 2 : 1)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(theme.colors.primary500)
                        .frame(width: 3)
                        .padding(.vertical, 8)
                        .padding(.leading, 6)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 12) {
        ReportReasonCard(reason: .offensive, isSelected: true, onTap: {})
        ReportReasonCard(reason: .spam, isSelected: false, onTap: {})
    }
    .padding()
    .background(Color.gray.opacity(0.1))
}
