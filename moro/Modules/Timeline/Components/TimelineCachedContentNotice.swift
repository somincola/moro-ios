import SwiftUI

struct TimelineCachedContentNotice: View {
    @Environment(\.moroTheme) private var theme
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Label(MoroL10n.Lists.cachedTimelineHint, systemImage: "exclamationmark.triangle")
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("timeline.cacheHint")
            Button(MoroL10n.Lists.retry, action: retry)
                .frame(minHeight: 44)
                .accessibilityIdentifier("timeline.cacheRetry")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(theme.spacing.m)
    }
}
