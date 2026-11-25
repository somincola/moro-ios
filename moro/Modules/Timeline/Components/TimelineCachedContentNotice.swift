import SwiftUI

struct TimelineCachedContentNotice: View {
    @Environment(\.moroTheme) private var theme
    let retry: () -> Void

    var body: some View {
        MoroInlineNoticeBanner(
            message: MoroL10n.Lists.cachedTimelineHint,
            tone: .neutral,
            actionTitle: MoroL10n.Lists.retry,
            action: retry,
            messageAccessibilityIdentifier: "timeline.cacheHint",
            actionAccessibilityIdentifier: "timeline.cacheRetry"
        )
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, theme.spacing.s)
    }
}
