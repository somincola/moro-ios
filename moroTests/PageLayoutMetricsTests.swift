import CoreGraphics
import Testing
@testable import moro

@Suite
struct PageLayoutMetricsTests {
    @Test func primaryPageEdgesShareOneHorizontalInset() {
        let spacing = MoroSpacing()

        #expect(MoroLayoutMetrics.contentHorizontalInset == 16)
        #expect(spacing.contentHorizontalInset == MoroLayoutMetrics.contentHorizontalInset)
        #expect(spacing.timelinePadding == MoroLayoutMetrics.contentHorizontalInset)
        #expect(SearchLayoutMetrics.contentHorizontalInset == MoroLayoutMetrics.contentHorizontalInset)
    }

    @Test func timelineDividerTracksTheRenderedAvatarColumn() {
        let expected = MoroLayoutMetrics.contentHorizontalInset
            + MoroLayoutMetrics.timelineAvatarSize
            + MoroLayoutMetrics.timelineAvatarContentSpacing

        #expect(MoroLayoutMetrics.timelineDividerInset == expected)
        #expect(MoroSpacing().timelineDividerInset == expected)
        #expect(expected == 72)
    }
}
