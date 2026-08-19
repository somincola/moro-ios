//
//  MoroSectionTextBlock.swift
//  moro
//
//  Shared title + helper copy block for settings, forms, and low-frequency pages.
//

import SwiftUI

struct MoroSectionTextBlock: View {
    @Environment(\.moroTheme) private var theme

    let title: String?
    let message: String?
    var icon: String? = nil
    var tint: Color? = nil
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: theme.spacing.s) {
            if let icon {
                Image(systemName: icon)
                    .moroScaledFont(size: compact ? 12 : 13, weight: .semibold)
                    .foregroundStyle(tint ?? theme.colors.textSecondary)
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                if let title {
                    Text(title)
                        .font(theme.typography.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.colors.textPrimary)
                }

                if let message, !message.isEmpty {
                    Text(message)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    MoroSectionTextBlock(
        title: "系统推送与诊断",
        message: "这里只说明边界，不承载额外卡片。",
        icon: "iphone.badge.waveform",
        tint: .blue
    )
}
