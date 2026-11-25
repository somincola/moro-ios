import SwiftUI

struct NavigationCustomizationView: View {
    @Environment(\.moroTheme) private var theme
    @ObservedObject var coordinator: RootTabCoordinator
    let accountHandle: String?

    private var layout: NavigationTabLayout { coordinator.tabLayout }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    if let accountHandle {
                        Text(verbatim: accountHandle)
                            .font(theme.typography.bodyStrong)
                            .accessibilityIdentifier("navigationCustomization.account")
                    }
                    Text(MoroL10n.NavigationCustomization.selectionHint(
                        minimum: NavigationTabLayout.minimumCount, maximum: NavigationTabLayout.maximumCount
                    ))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    Text(MoroL10n.NavigationCustomization.drawerHint)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                        .accessibilityIdentifier("navigationCustomization.drawerHint")
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 14, alignment: .top),
                                         count: 3), spacing: 16) {
                    ForEach(MainTab.allCases, id: \.self) { tab in
                        choice(tab)
                    }
                }
            }
            .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset)
            .padding(.vertical, 18)
            .moroReadableColumn()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            preview
                .padding(.horizontal, MoroSettingsMetrics.pageHorizontalInset)
                .padding(.vertical, 12)
                .moroReadableColumn()
                .background(theme.colors.surfaceBase)
                .overlay(alignment: .top) { MoroDivider() }
        }
        .moroSettingsPageChrome()
        .navigationTitle(MoroL10n.NavigationCustomization.title)
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: layout)
    }

    private func choice(_ tab: MainTab) -> some View {
        let selected = layout.tabs.contains(tab)
        let available = layout.canToggle(tab)
        let tile = RoundedRectangle(cornerRadius: 14)
        return Button {
            coordinator.toggleTab(tab)
        } label: {
            VStack(spacing: 6) {
                tile.fill(theme.colors.surfaceSubtle)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        tile.strokeBorder(selected ? theme.colors.themeTint : theme.colors.borderSubtle,
                                          lineWidth: selected ? 2 : 0.5)
                    }
                    .overlay {
                        Image(systemName: selected ? tab.filledIcon : tab.icon)
                            .font(.title2.weight(.medium))
                    }
                Text(tab.title)
                    .font(theme.typography.caption)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(theme.colors.textPrimary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("navigationCustomization.choice.\(tab.rawValue)")
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    previewTitle
                    Spacer(minLength: 12)
                    restoreButton
                }
                VStack(alignment: .leading, spacing: 2) {
                    previewTitle
                    restoreButton
                }
            }
            NavigationLayoutPreview(layout: layout, onMove: coordinator.moveTab)
            Text(MoroL10n.NavigationCustomization.dragHint)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
        }
    }

    private var previewTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(MoroL10n.NavigationCustomization.preview)
                .font(theme.typography.subtitle)
                .foregroundStyle(theme.colors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(MoroL10n.NavigationCustomization.count(layout.tabs.count, NavigationTabLayout.maximumCount))
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
                .accessibilityIdentifier("navigationCustomization.count")
        }
    }

    private var restoreButton: some View {
        Button(MoroL10n.NavigationCustomization.restore, action: coordinator.restoreDefaultTabLayout)
            .font(theme.typography.bodyStrong)
            .frame(minHeight: 44)
            .disabled(layout == NavigationTabLayout())
            .accessibilityIdentifier("navigationCustomization.restore")
    }
}

private struct NavigationLayoutPreview: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag: Drag?
    @State private var width: CGFloat = 0

    let layout: NavigationTabLayout
    let onMove: (MainTab, Int) -> Void

    private struct Drag {
        let tab: MainTab
        let translation: CGFloat
    }

    private var direction: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }
    private var slotWidth: CGFloat { width / CGFloat(layout.tabs.count) }
    private var animation: Animation? { reduceMotion ? nil : .snappy(duration: 0.2) }

    var body: some View {
        let tabs = layout.tabs
        let target = drag.flatMap { move in
            tabs.firstIndex(of: move.tab).map { destination(from: $0, translation: move.translation) }
        }
        let previewLayout = if let drag, let target { layout.moving(drag.tab, to: target) } else { layout }

        HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let isDragging = drag?.tab == tab
                previewItem(tab, index: index)
                    .background {
                        if isDragging {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(theme.colors.surfaceBase)
                        }
                    }
                    .offset(x: isDragging
                        ? dragOffset(from: index, translation: drag?.translation ?? 0)
                        : CGFloat((previewLayout.tabs.firstIndex(of: tab) ?? index) - index) * slotWidth * direction)
                    .animation(isDragging ? nil : animation, value: target)
                    .zIndex(isDragging ? 1 : 0)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .padding(.vertical, 5)
        .background(theme.colors.surfaceSubtle, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(theme.colors.borderSubtle, lineWidth: 0.5)
        }
        .coordinateSpace(name: "navigationLayoutPreview")
    }

    private func previewItem(_ tab: MainTab, index: Int) -> some View {
        Image(systemName: tab.icon)
            .font(.system(size: 21))
            .foregroundStyle(theme.colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .named("navigationLayoutPreview"))
                    .updating($drag) { value, state, _ in
                        state = Drag(tab: tab, translation: value.translation.width)
                    }
                    .onEnded { value in
                        withAnimation(animation) {
                            onMove(tab, destination(from: index, translation: value.translation.width))
                        }
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.title)
            .accessibilityValue(MoroL10n.NavigationCustomization.position(index + 1, layout.tabs.count))
            .accessibilityAdjustableAction { adjustment in
                switch adjustment {
                case .increment: onMove(tab, index + 1)
                case .decrement: onMove(tab, index - 1)
                @unknown default: break
                }
            }
            .accessibilityIdentifier("navigationCustomization.preview.\(tab.rawValue)")
    }

    private func destination(from index: Int, translation: CGFloat) -> Int {
        guard slotWidth > 0 else { return index }
        let steps = Int((translation * direction / slotWidth).rounded())
        return min(max(index + steps, 0), layout.tabs.count - 1)
    }

    private func dragOffset(from index: Int, translation: CGFloat) -> CGFloat {
        let leading = CGFloat(-index) * slotWidth
        let trailing = CGFloat(layout.tabs.count - index - 1) * slotWidth
        return min(max(translation * direction, leading), trailing) * direction
    }
}
