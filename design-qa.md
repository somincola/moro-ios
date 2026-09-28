# Profile info refinement — 2026-09-28

final result: passed

## Scope and visual evidence

- Scope: the approved continuous-surface profile bio and metadata refinement. Banner, identity, tabs, routing, networking and scroll coordination are unchanged.
- Source visual truth: `/Users/nagihsu/.codex/generated_images/01a0da1d-ba87-7ed2-8238-a6007f7d3a97/exec-2ab7c7e4-c17a-4945-a8fc-5ea6a1e76bc1.png` (1364 × 1153, conceptual detail crop; no device-density metadata).
- Implementation: iPhone 17 Pro, iOS 26.2, 402 × 874 pt; native screenshots are 1206 × 2622 px at 3×. CSS size is not applicable to this native SwiftUI app.
- Density normalization: native screenshots are interpreted at 3 px/pt; compare the reference's statistics-through-fields region at the same content width, not its full image height against the phone. The reference is an illustrative crop, not an exact-size screen specification.
- State: dedicated DEBUG profile harness, same three bio paragraphs, two fields and statistics as the reference; existing fixture avatar, title and featured tags intentionally retained. Production account data is not changed.
- Light/default: `/private/tmp/moro-profile-info-final-captures/C684EB57-6B90-4AA0-B853-A3867523D20F.png`.
- Dark/default: `/private/tmp/moro-profile-info-final-captures/EDA2229F-D82C-471B-95BB-5049F9632B57.png`.
- Light/Accessibility XXXL, scrolled bio: `/private/tmp/moro-profile-info-final-captures/23C71271-F8F1-478D-9B2D-BBA2C721DACB.png`.
- Dark/Accessibility XXXL, scrolled bio: `/private/tmp/moro-profile-info-final-captures/DA81476F-A34C-4FC1-9DFB-EDC67C1393A6.png`.
- Light/Accessibility XXXL, visible last field: `/private/tmp/moro-profile-info-final-captures/CF213FEA-ED85-4D88-962C-91C58D7ACB00.png`.
- Dark/Accessibility XXXL, visible last field: `/private/tmp/moro-profile-info-final-captures/CD0D33B6-1E17-477F-8FF4-F878B2C48ACC.png`.

## Comparison and findings

The reference and the native light/default capture were opened together in one comparison input, alongside dark/default and large-text captures. The focused reference itself covers the statistics, bio, field labels, links, verification symbol and tab transition; these were readable in the native captures without another cropped asset.

- Typography: system 15pt bio with 2pt additional line spacing and 6pt paragraph spacing; both spacing metrics and the bio font respond to Dynamic Type. Full content is preserved, with no line limit. Field labels use 12pt medium text, values retain 15pt medium text.
- Spacing/layout: continuous base surface, 16pt content margins, no inset card padding or rounded card borders. Metadata retains label-above-value layout, 3pt label gap and 0.5pt inter-field separator. Statistics keep their existing accessible tap targets.
- Colors/tokens: semantic `surfaceBase`, `textPrimary`, `textSecondary`, `contentLink` and `success`; light mode is white, dark mode follows the existing dark palette. No hard-coded white background.
- Assets/icons: no new raster assets or dependencies; existing SF Symbol verification mark reduced to 11pt, beside the verified value. The concept crop contains no other new artwork.
- Copy/content: all three approved bio paragraphs and both metadata values are displayed; fixtures do not replace production content. Parser output remains unchanged. Native paragraph spacing is explicitly enabled only by profile bio.
- Interactions: profile tab transitions, featured-tag round trip, navigation return and light/dark top-pinning pass existing regression checks. Large-text gestures scroll the whole profile; final field bounds are asserted below the navigation bar and above the profile tabs, not merely `isHittable`.

No actionable P0/P1/P2 visual differences remain within the changed info region.

## Comparison history and validation

1. Initial implementation matched the approved white-surface direction. The first large-text screenshots were taken before scrolling and did not expose the bio; these were insufficient as visual evidence for long content.
2. Added real scroll gestures and captures. Tightened field visibility assertions because accessibility hit-testing alone can report a field behind the docked tabs as hittable. The final captures show the last field fully above the tabs in both themes. No additional production layout changes were needed.
3. One new unit test initially assumed a different existing emoji whitespace convention and compared different numeric types inside a test macro. Corrected the assertions, then reran the suite successfully; no production behavior was changed to satisfy these test-only assumptions.

- Build: succeeded on iOS 26.2.
- 36 distinct related tests passed across the targeted runs: parser, post-content correctness, profile presentation, immediate rich text, native emoji attachments, chrome/refresh state and four profile UI cases. No final skipped tests.
- Initial parser/profile/UI results: `/private/tmp/moro-profile-info-regression.xcresult` (30 passed, one subsequently corrected test assertion failed).
- Corrected rich-text and additional chrome/emoji checks: `/private/tmp/moro-profile-info-unit-recheck.xcresult` (8 passed).
- Final four-state scrolling/visibility UI case: `/private/tmp/moro-profile-info-visibility-qa.xcresult` (1 passed, covers both themes and sizes).
- `git diff --check`: passed.

## Limits and follow-up

- Existing Accessibility XXXL tab-label wrapping is retained; this change does not redesign the tab bar.
- UI runs emit `Publishing changes from within view updates is not allowed` during startup, without an attributed source location. Its origin is not established by this visual change; it remains a separate diagnostic concern, not a clean-log claim. Initial test compilation also reports concurrency warnings in untouched test files.
- These are simulator/harness checks, not a claim of physical-device or live-account verification. No new server write or cache behavior was introduced.
