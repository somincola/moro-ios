import SwiftUI

/// Where the two columns meet. Pure so it can be tested without an unfolded iPhone Duo.
enum ThreadSplitLayout {
    static let listMinimumWidth: CGFloat = 320
    static let threadMinimumWidth: CGFloat = 400

    /// - Half open (`isFoldActive`), the columns meet at the fold so neither runs across the
    ///   crease, whatever the reader chose.
    /// - Fully open, the reader's width (`preferredFraction` of the root) wins; without one,
    ///   the fold's position (where it sits when folding), else a fixed share.
    static func listWidth(rootWidth: CGFloat, foldX: CGFloat?, isFoldActive: Bool,
        preferredFraction: Double?) -> CGFloat {
        let usableFold = foldX.flatMap { $0 > rootWidth * 0.3 && $0 < rootWidth * 0.7 ? $0 : nil }
        if isFoldActive, let usableFold { return usableFold }
        if let preferredFraction, preferredFraction > 0 {
            return clamp(rootWidth * preferredFraction, rootWidth: rootWidth)
        }
        if let usableFold { return usableFold }
        return min(max(rootWidth * 0.42, 360), 460)
    }

    /// Keeps both columns readable while dragging.
    static func clamp(_ listWidth: CGFloat, rootWidth: CGFloat) -> CGFloat {
        let maximum = max(listMinimumWidth, rootWidth - threadMinimumWidth)
        return min(max(listWidth, listMinimumWidth), maximum)
    }

    static func isResizable(rootWidth: CGFloat, foldX: CGFloat?, isFoldActive: Bool) -> Bool {
        guard isFoldActive, let foldX else { return true }
        return !(foldX > rootWidth * 0.3 && foldX < rootWidth * 0.7)
    }
}

/// A tab root that, on iPhone Duo's inner display held landscape, shows its list in a left
/// column and the opened thread in a right column; otherwise it is just the list.
///
/// While split, opening a post from the list (`.statusDetail` on this tab's router, with the
/// tab at its root) fills the thread column instead of pushing. Pages pushed on top (a
/// profile, say) keep pushing. Leaving the split layout carries the open thread over as a
/// pushed page so the reader keeps their place.
struct ThreadSplitView<ListColumn: View>: View {
    @ObservedObject var coordinator: RootTabCoordinator
    let tab: MainTab
    let router: AppRouter
    let apiClient: MastodonAPI
    @ViewBuilder let list: () -> ListColumn

    @Environment(\.moroTheme) private var theme
    /// The reader's list width as a share of the root, shared by every tab; 0 is automatic.
    @AppStorage("threadSplit.listFraction") private var preferredListFraction: Double = 0
    /// The list width while the divider is being dragged.
    @State private var draggedListWidth: CGFloat?
    /// The fold is bent (half open, book style): the columns stay at it.
    @State private var isFoldActive = false

    /// Narrowest root width that gets two columns (iPhone Duo inner display held landscape);
    /// anything narrower, including the outer display, stays one column.
    private let splitMinimumWidth: CGFloat = 820

    @State private var rootWidth: CGFloat = 0
    /// x of the display's fold when it runs top to bottom (inner display held landscape), in
    /// this view's space. Reported even fully open, so the columns don't move when folding.
    @State private var verticalFoldX: CGFloat?
    /// The thread shown in the second column.
    @State private var threadStatus: Status?

    private var isSplit: Bool {
        coordinator.usesSystemHomeBar && rootWidth >= splitMinimumWidth
    }

    /// The columns split at the fold, so neither column's content runs across the crease when
    /// half open; without a usable fold, a fixed share of the width.
    private var listColumnWidth: CGFloat {
        draggedListWidth ?? ThreadSplitLayout.listWidth(
            rootWidth: rootWidth, foldX: verticalFoldX, isFoldActive: isFoldActive,
            preferredFraction: preferredListFraction)
    }

    private var isResizable: Bool {
        ThreadSplitLayout.isResizable(rootWidth: rootWidth, foldX: verticalFoldX, isFoldActive: isFoldActive)
    }

    private static func verticalFoldX(in proxy: GeometryProxy, includeInactive: Bool = true) -> CGFloat? {
        // Reserved regions are an iOS 27.1 SDK API (Swift 6.4); older toolchains, such as
        // CI's Xcode 26, build without them.
        #if compiler(>=6.4)
        guard #available(iOS 27.1, *) else { return nil }
        let folds = includeInactive
            ? proxy.reservedRegions(kind: .division, options: .includeInactive)
            : proxy.reservedRegions(kind: .division)
        return folds.first { $0.frame.height > $0.frame.width }?.frame.midX
        #else
        return nil
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            list()
                .frame(width: isSplit ? listColumnWidth : nil)
            if isSplit {
                columnDivider
                threadColumn
                    .frame(maxWidth: .infinity)
            }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            rootWidth = width
        }
        .onGeometryChange(for: CGFloat?.self) { proxy in
            Self.verticalFoldX(in: proxy)
        } action: { foldX in
            verticalFoldX = foldX
        }
        .onGeometryChange(for: Bool.self) { proxy in
            Self.verticalFoldX(in: proxy, includeInactive: false) != nil
        } action: { active in
            isFoldActive = active
            if active { draggedListWidth = nil }
        }
        .coordinateSpace(.named(Self.coordinateSpace))
        .onChange(of: isSplit, initial: true) { _, split in
            updateThreadRouting(isSplit: split)
        }
    }

    private static var coordinateSpace: String { "threadSplit" }

    /// A hairline that, fully open, can be dragged to resize the list (double tap resets it).
    /// Its touch area is wider than the line; half open it stays at the fold.
    private var columnDivider: some View {
        Rectangle()
            .fill(draggedListWidth == nil ? theme.colors.borderSubtle : theme.colors.themeTint)
            .frame(width: draggedListWidth == nil ? 0.5 : 2)
            .frame(width: 0.5)
            .ignoresSafeArea()
            .overlay {
                if isResizable {
                    Color.clear
                        .frame(width: 24)
                        .contentShape(Rectangle())
                        .gesture(dividerDrag)
                        .onTapGesture(count: 2) { resetListWidth() }
                        .accessibilityElement()
                        .accessibilityLabel(MoroL10n.StatusDetail.splitDivider)
                        .accessibilityValue("\(Int((listColumnWidth / max(rootWidth, 1) * 100).rounded()))%")
                        .accessibilityAdjustableAction { direction in
                            let step = rootWidth * 0.05
                            let current = listColumnWidth
                            let next = direction == .increment ? current + step : current - step
                            setListWidth(ThreadSplitLayout.clamp(next, rootWidth: rootWidth))
                        }
                        .accessibilityAction(named: MoroL10n.StatusDetail.splitDividerReset) { resetListWidth() }
                        .accessibilityIdentifier("threadSplit.divider")
                }
            }
    }

    private var dividerDrag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { value in
                if draggedListWidth == nil { UISelectionFeedbackGenerator().selectionChanged() }
                draggedListWidth = ThreadSplitLayout.clamp(value.location.x, rootWidth: rootWidth)
            }
            .onEnded { _ in
                if let draggedListWidth { setListWidth(draggedListWidth) }
                draggedListWidth = nil
            }
    }

    private func setListWidth(_ width: CGFloat) {
        guard rootWidth > 0 else { return }
        preferredListFraction = Double(width / rootWidth)
    }

    private func resetListWidth() {
        withAnimation(.snappy) { preferredListFraction = 0 }
    }

    private func updateThreadRouting(isSplit: Bool) {
        guard isSplit else {
            router.inPlaceRouteHandler = nil
            if let status = threadStatus {
                threadStatus = nil
                router.navigate(to: .statusDetail(status))
            }
            return
        }
        router.inPlaceRouteHandler = { [coordinator, tab] route in
            guard case .statusDetail(let status) = route, coordinator.isAtRoot(tab) else {
                return false
            }
            threadStatus = status
            return true
        }
    }

    @ViewBuilder
    private var threadColumn: some View {
        if let threadStatus {
            StatusDetailView(status: threadStatus, apiClient: apiClient, isEmbedded: true)
                .id(threadStatus.id)
        } else {
            VStack(spacing: theme.spacing.m) {
                Image(systemName: "text.bubble")
                    .moroScaledFont(size: 40, weight: .light)
                Text(MoroL10n.StatusDetail.splitPlaceholder)
                    .font(theme.typography.body)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(theme.colors.textSecondary)
            .padding(theme.spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("threadSplit.placeholder")
        }
    }
}
