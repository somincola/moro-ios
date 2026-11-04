import Combine
import SwiftUI

/// Where the two columns meet. Pure so it can be tested without an unfolded iPhone Duo.
enum ThreadSplitLayout {
    static let listMinimumWidth: CGFloat = 320
    static let threadMinimumWidth: CGFloat = 400
    /// Narrowest root width that can show a second column (iPhone Duo inner display held
    /// landscape); anything narrower, including the outer display, stays one column.
    static let splitMinimumWidth: CGFloat = 820
    /// Dragging the divider this close to the trailing edge closes the panel.
    static let closeDragWidth: CGFloat = 280

    /// The panel closes when the divider is let go within `closeDragWidth` of the edge.
    static func closesPanel(dividerX: CGFloat, rootWidth: CGFloat) -> Bool {
        dividerX > rootWidth - closeDragWidth
    }

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

    /// Widths a drag settles on when it comes within `snapDistance`: the fold (where the
    /// columns sit when folding), half and a third of the root.
    static let snapDistance: CGFloat = 12

    static func detents(rootWidth: CGFloat, foldX: CGFloat?) -> [CGFloat] {
        var detents = [rootWidth / 2, rootWidth / 3]
        if let foldX, foldX > rootWidth * 0.3, foldX < rootWidth * 0.7 { detents.insert(foldX, at: 0) }
        var unique: [CGFloat] = []
        for detent in detents.map({ clamp($0, rootWidth: rootWidth) })
        where !unique.contains(where: { abs($0 - detent) < snapDistance }) {
            unique.append(detent)
        }
        return unique
    }

    static func snapped(_ width: CGFloat, rootWidth: CGFloat, foldX: CGFloat?) -> (width: CGFloat, detent: CGFloat?) {
        let nearest = detents(rootWidth: rootWidth, foldX: foldX).min { abs($0 - width) < abs($1 - width) }
        if let nearest, abs(nearest - width) <= snapDistance { return (nearest, nearest) }
        return (width, nil)
    }

    static func isResizable(rootWidth: CGFloat, foldX: CGFloat?, isFoldActive: Bool) -> Bool {
        guard isFoldActive, let foldX else { return true }
        return !(foldX > rootWidth * 0.3 && foldX < rootWidth * 0.7)
    }
}

/// Which post each tab's panel shows, so the list can mark the row it came from. Shared
/// because the timeline pager hosts its pages in their own hosting controllers, which the
/// SwiftUI environment does not reach.
@MainActor
final class ThreadSplitSelection: ObservableObject {
    static let shared = ThreadSplitSelection()
    @Published private(set) var statusIDs: [MainTab: String] = [:]

    // iOS 26.0–26.2 crash releasing a main-actor object off the main thread.
    nonisolated deinit {}

    func set(_ statusID: String?, for tab: MainTab) {
        guard statusIDs[tab] != statusID else { return }
        statusIDs[tab] = statusID
    }

    func contains(_ statusID: String) -> Bool {
        statusIDs.values.contains(statusID)
    }
}

/// The open post's actions, raised into the tab's system bar. On iPhone Duo, Home keeps its
/// controls in the bar that runs down the side; with the panel open that bar shows the
/// panel's close button and the post's actions instead of the timeline's.
@MainActor
final class ThreadSplitPanelBar: ObservableObject {
    struct Actions {
        var editHistory: AnyView?
        var readingOptions: AnyView
        var more: AnyView
    }

    @Published private(set) var actions: Actions?
    private var owner: UUID?

    nonisolated deinit {}

    func publish(_ actions: Actions, owner: UUID) {
        self.owner = owner
        self.actions = actions
    }

    func withdraw(owner: UUID) {
        guard self.owner == owner else { return }
        self.owner = nil
        actions = nil
    }
}

extension EnvironmentValues {
    /// Set inside the panel when its actions belong in the system bar.
    @Entry var threadSplitPanelBar: ThreadSplitPanelBar? = nil
    /// Set on the list while the panel owns the system bar: the list leaves its items out.
    @Entry var threadSplitPanelOwnsBar = false
}

/// Tints the row whose post is open in the panel.
struct ThreadSplitRowHighlight: ViewModifier {
    let statusID: String
    @ObservedObject private var selection = ThreadSplitSelection.shared
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        content.background {
            if selection.contains(statusID) {
                theme.colors.themeTint.opacity(0.10)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: selection.contains(statusID))
    }
}

/// A tab root that, on iPhone Duo's inner display held landscape, can open a panel on the
/// right next to its list. The list stays full width until something is opened: the panel
/// appears on demand and closes again (close button, Esc, or dragging the divider to the
/// right edge), so nothing sits empty waiting for a selection.
///
/// While the panel can open, opening a post from the list (`.statusDetail` on this tab's
/// router, with the tab at its root) fills the panel instead of pushing. Pages pushed on top
/// (a profile, say) keep pushing. Leaving the wide layout carries the open panel over as a
/// pushed page so the reader keeps their place.
struct ThreadSplitView<ListColumn: View>: View {
    @ObservedObject var coordinator: RootTabCoordinator
    let tab: MainTab
    let router: AppRouter
    let apiClient: MastodonAPI
    /// Explore lists people and topics too: opening one fills the second column like a post
    /// does. Elsewhere only posts do, and profiles keep pushing.
    var opensProfilesAndTopics = false
    @ViewBuilder let list: () -> ListColumn

    @Environment(\.moroTheme) private var theme
    @EnvironmentObject private var appState: AppState
    @Environment(\.cacheManager) private var cacheManager
    /// The reader's list width as a share of the root, shared by every tab; 0 is automatic.
    @AppStorage("threadSplit.listFraction") private var preferredListFraction: Double = 0
    /// The list width while the divider is being dragged.
    @State private var draggedListWidth: CGFloat?
    /// The fold is bent (half open, book style): the columns stay at it.
    @State private var isFoldActive = false
    @GestureState private var isDividerPressed = false
    @State private var snappedDetent: CGFloat?
    @State private var isDividerAtLimit = false
    @State private var lockedDividerOffset: CGFloat = 0
    @State private var grabberNudge: CGFloat = 0
    @State private var showsDividerHint = false
    /// The divider has been dragged far enough right that letting go closes the panel.
    @State private var isPendingClose = false
    @AppStorage("threadSplit.dividerIntroduced") private var hasIntroducedDivider = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let dividerFeedback = UISelectionFeedbackGenerator()
    private let limitFeedback = UIImpactFeedbackGenerator(style: .rigid)

    @State private var rootWidth: CGFloat = 0
    /// x of the display's fold when it runs top to bottom (inner display held landscape), in
    /// this view's space. Reported even fully open, so the columns don't move when folding.
    @State private var verticalFoldX: CGFloat?
    /// What the second column shows: a post, or in Explore a profile or a topic.
    @State private var detailRoute: Route?
    /// The second column's own stack. Opening something from the list replaces its root;
    /// links inside it (a post on that profile, say) push within the column, with a back
    /// button, and leave the list where it was.
    @StateObject private var columnRouter = AppRouter()
    @StateObject private var panelBar = ThreadSplitPanelBar()

    /// On iPhone Duo every tab keeps its controls in the system bar (down the side when held
    /// landscape), so the panel's close button and actions go there too.
    private var raisesPanelActions: Bool {
        coordinator.usesSystemHomeBar
    }

    private var isSplit: Bool {
        coordinator.usesSystemHomeBar && rootWidth >= ThreadSplitLayout.splitMinimumWidth
    }

    /// The panel is on screen: wide enough, and something has been opened.
    private var isPanelOpen: Bool {
        isSplit && detailRoute != nil
    }

    private var panelAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.32)
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
                .environment(\.threadSplitPanelOwnsBar, raisesPanelActions && isPanelOpen)
                .frame(width: isPanelOpen ? listColumnWidth : nil)
                .frame(maxWidth: isPanelOpen ? nil : .infinity)
            if isPanelOpen {
                columnDivider
                threadColumn
                    .frame(maxWidth: .infinity)
                    .opacity(isPendingClose ? 0.45 : 1)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
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
        .toolbar {
            if raisesPanelActions && isPanelOpen {
                panelToolbar
            }
        }
        .onChange(of: isSplit, initial: true) { _, split in
            updateThreadRouting(isSplit: split)
        }
        .onChange(of: detailRoute, initial: true) { _, route in
            if case .statusDetail(let status) = route {
                ThreadSplitSelection.shared.set(status.id, for: tab)
            } else {
                ThreadSplitSelection.shared.set(nil, for: tab)
            }
        }
    }

    /// Back to the full-width list.
    private func closePanel() {
        withAnimation(panelAnimation) {
            detailRoute = nil
        }
        columnRouter.path = NavigationPath()
        isPendingClose = false
        draggedListWidth = nil
    }

    @ToolbarContentBuilder
    private var panelToolbar: some ToolbarContent {
        // Deeper in the panel (a reply opened from the thread, say) it steps back first.
        ToolbarItem(placement: .topBarLeading) {
            if columnRouter.path.isEmpty { closeButton } else { panelBackButton }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let actions = panelBar.actions {
                if let editHistory = actions.editHistory { editHistory }
                actions.readingOptions
                actions.more
            }
        }
    }

    private var panelBackButton: some View {
        Button { columnRouter.pop() } label: {
            Label(MoroL10n.UtilityButton.back, systemImage: "chevron.left")
                .labelStyle(.iconOnly)
        }
        .keyboardShortcut("[", modifiers: .command)
        .accessibilityIdentifier("threadSplit.back")
    }

    /// Pages opened inside the panel. On Home a post keeps the panel's look: its actions,
    /// and the way back, go in the system bar like the first post's.
    @ViewBuilder
    private func columnDestination(_ route: Route) -> some View {
        if raisesPanelActions, case .statusDetail(let status) = route {
            StatusDetailView(status: status, apiClient: apiClient, isEmbedded: true)
                .navigationBarBackButtonHidden(true)
        } else {
            routeFactory.view(for: route)
        }
    }

    private var closeButton: some View {
        Button(action: closePanel) {
            Label(MoroL10n.Common.close, systemImage: "xmark")
                .labelStyle(.iconOnly)
        }
        .keyboardShortcut(.cancelAction)
        .accessibilityIdentifier("threadSplit.close")
    }

    private static var coordinateSpace: String { "threadSplit" }

    /// The hairline between the columns, with a grabber in the middle so it reads as
    /// something to drag (the same cue as iPad's split view). Fully open it resizes the list,
    /// snapping to the fold, half and a third; double tap resets it. Half open it stays at
    /// the fold: the grabber hides and a drag only gives a little and says why.
    private var columnDivider: some View {
        let isActive = isDividerPressed || draggedListWidth != nil
        return Rectangle()
            .fill(isActive ? theme.colors.themeTint : theme.colors.borderSubtle)
            .frame(width: isActive ? 2 : 0.5)
            .frame(width: 0.5)
            .ignoresSafeArea()
            .overlay {
                if isResizable {
                    grabber(isActive: isActive)
                        .offset(x: grabberNudge)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                Color.clear
                    .frame(width: 24)
                    .contentShape(Rectangle())
                    .gesture(isResizable ? dividerDrag : nil)
                    .simultaneousGesture(isResizable ? nil : lockedDividerDrag)
                    .simultaneousGesture(TapGesture(count: 2).onEnded {
                        if isResizable { resetListWidth() }
                    })
                    .accessibilityElement()
                    .accessibilityLabel(MoroL10n.StatusDetail.splitDivider)
                    .accessibilityValue("\(Int((listColumnWidth / max(rootWidth, 1) * 100).rounded()))%")
                    .accessibilityHint(isResizable ? MoroL10n.StatusDetail.splitDividerHint : MoroL10n.StatusDetail.splitDividerLocked)
                    .accessibilityAdjustableAction { direction in
                        guard isResizable else { return }
                        let step = rootWidth * 0.05
                        let next = direction == .increment ? listColumnWidth + step : listColumnWidth - step
                        setListWidth(ThreadSplitLayout.clamp(next, rootWidth: rootWidth))
                    }
                    .accessibilityAction(named: MoroL10n.StatusDetail.splitDividerReset) {
                        if isResizable { resetListWidth() }
                    }
                    .accessibilityIdentifier("threadSplit.divider")
            }
            .offset(x: lockedDividerOffset)
            .overlay(alignment: .leading) {
                if showsDividerHint {
                    dividerHint
                        .fixedSize()
                        .offset(x: 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .leading)))
                }
            }
            .animation(.snappy(duration: 0.18), value: isActive)
            .task(id: isResizable) { await introduceDividerIfNeeded() }
    }

    private func grabber(isActive: Bool) -> some View {
        Capsule()
            .fill(isActive ? theme.colors.themeTint : theme.colors.textTertiary)
            .frame(width: isActive ? 6 : 4, height: isActive ? 48 : 36)
            .overlay { Capsule().stroke(theme.colors.surfaceBase, lineWidth: 1.5) }
            .accessibilityIdentifier("threadSplit.grabber")
    }

    private var dividerHint: some View {
        HStack(spacing: theme.spacing.s) {
            Image(systemName: "arrow.left.and.right")
                .moroScaledFont(size: 13, weight: .semibold)
            Text(MoroL10n.StatusDetail.splitDividerHint)
                .font(theme.typography.caption)
        }
        .foregroundStyle(theme.colors.themeTintForeground)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.colors.themeTint, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .onTapGesture { dismissDividerHint() }
        .accessibilityHidden(true)
        .accessibilityIdentifier("threadSplit.dividerHint")
    }

    private var dividerDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.coordinateSpace))
            .updating($isDividerPressed) { _, pressed, _ in pressed = true }
            .onChanged { value in
                guard abs(value.translation.width) > 2 || draggedListWidth != nil else { return }
                if draggedListWidth == nil {
                    dividerFeedback.selectionChanged()
                    dismissDividerHint()
                }
                let closes = ThreadSplitLayout.closesPanel(dividerX: value.location.x, rootWidth: rootWidth)
                if closes != isPendingClose {
                    limitFeedback.impactOccurred()
                    withAnimation(.easeOut(duration: 0.15)) { isPendingClose = closes }
                }
                if closes {
                    // Follows the finger towards the edge, so letting go reads as closing.
                    draggedListWidth = min(value.location.x, rootWidth - 40)
                    snappedDetent = nil
                    isDividerAtLimit = false
                    return
                }
                let raw = ThreadSplitLayout.clamp(value.location.x, rootWidth: rootWidth)
                let snap = ThreadSplitLayout.snapped(raw, rootWidth: rootWidth, foldX: verticalFoldX)
                if snap.detent != snappedDetent {
                    if snap.detent != nil { dividerFeedback.selectionChanged() }
                    snappedDetent = snap.detent
                }
                let atLimit = raw != value.location.x
                if atLimit, !isDividerAtLimit { limitFeedback.impactOccurred() }
                isDividerAtLimit = atLimit
                draggedListWidth = snap.width
            }
            .onEnded { _ in
                if isPendingClose {
                    closePanel()
                    snappedDetent = nil
                    isDividerAtLimit = false
                    return
                }
                if let draggedListWidth { setListWidth(draggedListWidth) }
                draggedListWidth = nil
                snappedDetent = nil
                isDividerAtLimit = false
            }
    }

    /// Half open: the line gives a few points, springs back, and says why it won't move.
    private var lockedDividerDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                lockedDividerOffset = max(-8, min(8, value.translation.width * 0.15))
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { lockedDividerOffset = 0 }
                limitFeedback.impactOccurred()
                AppFeedbackCenter.shared.showInfo(MoroL10n.StatusDetail.splitDividerLocked)
            }
    }

    /// The first time the columns can be resized, the grabber sways twice and a note says
    /// what it does. Once dragged (or tapped away) it never shows again.
    private func introduceDividerIfNeeded() async {
        guard isResizable, !hasIntroducedDivider else { return }
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled, isResizable, !hasIntroducedDivider else { return }
        withAnimation(.easeOut(duration: 0.25)) { showsDividerHint = true }
        if !reduceMotion {
            for offset in [6.0, -6.0, 6.0, -6.0, 0.0] {
                withAnimation(.easeInOut(duration: 0.16)) { grabberNudge = offset }
                try? await Task.sleep(for: .milliseconds(170))
                guard !Task.isCancelled else { break }
            }
            grabberNudge = 0
        }
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        dismissDividerHint()
    }

    private func dismissDividerHint() {
        hasIntroducedDivider = true
        guard showsDividerHint else { return }
        withAnimation(.easeIn(duration: 0.2)) { showsDividerHint = false }
    }

    private func setListWidth(_ width: CGFloat) {
        guard rootWidth > 0 else { return }
        preferredListFraction = Double(width / rootWidth)
    }

    private func resetListWidth() {
        withAnimation(.snappy) { preferredListFraction = 0 }
    }

    /// Routes the second column takes from the list.
    static func opensInColumn(_ route: Route, opensProfilesAndTopics: Bool) -> Bool {
        switch route {
        case .statusDetail:
            return true
        case .userProfile, .mentionUser, .accountLookup, .hashtag:
            return opensProfilesAndTopics
        default:
            return false
        }
    }

    private func updateThreadRouting(isSplit: Bool) {
        guard isSplit else {
            router.inPlaceRouteHandler = nil
            // One column again: what was open on the right becomes a pushed page.
            if let route = detailRoute {
                detailRoute = nil
                columnRouter.path = NavigationPath()
                router.navigate(to: route)
            }
            return
        }
        router.inPlaceRouteHandler = { [coordinator, tab, opensProfilesAndTopics] route in
            guard coordinator.isAtRoot(tab),
                Self.opensInColumn(route, opensProfilesAndTopics: opensProfilesAndTopics)
            else { return false }
            columnRouter.path = NavigationPath()
            withAnimation(.snappy(duration: 0.32)) { detailRoute = route }
            return true
        }
    }

    private var routeFactory: AppRouteViewFactory {
        AppRouteViewFactory(apiClient: apiClient, appState: appState, cacheManager: cacheManager)
    }

    @ViewBuilder
    private func columnRoot(_ route: Route) -> some View {
        if case .statusDetail(let status) = route {
            // The embedded thread draws its own title row, with the close button.
            StatusDetailView(
                status: status, apiClient: apiClient, isEmbedded: true,
                embeddedLeadingAction: AnyView(closeButton))
                // Hiding the column's bar reaches the tab's own bar too; on Home that bar
                // carries the panel's actions, so it stays.
                .toolbar(raisesPanelActions ? .automatic : .hidden, for: .navigationBar)
        } else {
            routeFactory.view(for: route)
                .toolbar {
                    // With the system bar, the panel's close button is already there.
                    if !raisesPanelActions {
                        ToolbarItem(placement: .topBarLeading) { closeButton }
                    }
                }
        }
    }

    @ViewBuilder
    private var threadColumn: some View {
        if let detailRoute {
            NavigationStack(path: $columnRouter.path) {
                columnRoot(detailRoute)
                    .navigationDestination(for: Route.self) { columnDestination($0) }
            }
            .environmentObject(columnRouter)
            .environment(\.appRouter, columnRouter)
            .environment(\.threadSplitPanelBar, raisesPanelActions ? panelBar : nil)
            .id(detailRoute)
            .accessibilityIdentifier("threadSplit.detail")
        }
    }
}
