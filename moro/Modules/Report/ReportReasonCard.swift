import SwiftUI

struct ReportReasonCard: View {
    @Environment(\.moroTheme) private var theme
    let reason: ReportReason
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(reason.title)
                        .moroScaledFont(size: 17, weight: .medium)
                        .foregroundStyle(theme.colors.primary500)
                    Text(reason.description)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineSpacing(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ReportSelectionIndicator(isSelected: isSelected)
            }
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .bottom) { MoroDivider() }
    }
}

/// A monochrome selection mark with an explicit inverse foreground in both appearances.
struct ReportSelectionIndicator: View {
    @Environment(\.moroTheme) private var theme
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 22
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(theme.colors.primary500)
                Image(systemName: "checkmark")
                    .font(.system(size: diameter * theme.fontScale * 0.5, weight: .bold))
                    .foregroundStyle(theme.colors.primaryForeground)
            } else {
                Circle().strokeBorder(theme.colors.textSecondary, lineWidth: 1)
            }
        }
        .frame(width: diameter * theme.fontScale, height: diameter * theme.fontScale)
        .accessibilityHidden(true)
    }
}

#Preview("Reasons · Light") {
    @Previewable @State var selected: ReportReason? = .spam
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(MoroL10n.Report.reasonLabel)
                    .font(.title.bold())
                    .padding(.bottom, 28)
                ForEach(ReportReason.allCases) { reason in
                    ReportReasonCard(reason: reason, isSelected: selected == reason) { selected = reason }
                }
            }
            .padding(24)
        }
        .navigationTitle(MoroL10n.Profile.report)
        .navigationBarTitleDisplayMode(.inline)
    }
    .moroTheme(MoroTheme(colorScheme: .light))
    .preferredColorScheme(.light)
}

#Preview("Reasons · Dark / Large Text") {
    @Previewable @State var selected: ReportReason? = .violation
    ScrollView {
        VStack(spacing: 0) {
            ForEach(ReportReason.allCases) { reason in
                ReportReasonCard(reason: reason, isSelected: selected == reason) { selected = reason }
            }
        }
        .padding(24)
    }
    .background(MoroTheme(colorScheme: .dark).colors.surfaceBase)
    .moroTheme(MoroTheme(colorScheme: .dark, dynamicTypeSize: .accessibility1))
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility1)
}
