import SwiftUI

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
        if let verticalFoldX, verticalFoldX > rootWidth * 0.3, verticalFoldX < rootWidth * 0.7 {
            return verticalFoldX
        }
        return min(max(rootWidth * 0.42, 360), 460)
    }

    private static func verticalFoldX(in proxy: GeometryProxy) -> CGFloat? {
        guard #available(iOS 27.1, *) else { return nil }
        let folds = proxy.reservedRegions(kind: .division, options: .includeInactive)
        return folds.first { $0.frame.height > $0.frame.width }?.frame.midX
    }

    var body: some View {
        HStack(spacing: 0) {
            list()
                .frame(width: isSplit ? listColumnWidth : nil)
            if isSplit {
                Rectangle()
                    .fill(theme.colors.borderSubtle)
                    .frame(width: 0.5)
                    .ignoresSafeArea()
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
        .onChange(of: isSplit, initial: true) { _, split in
            updateThreadRouting(isSplit: split)
        }
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
