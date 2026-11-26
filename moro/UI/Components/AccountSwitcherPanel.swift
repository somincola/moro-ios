//
//  AccountSwitcherPanel.swift
//  moro
//
//  The quick account switcher raised from the Me tab: a floating capsule of
//  account avatars. The UIKit controller owns the gesture and placement; this
//  file only renders state.
//

import Combine
import SwiftUI
import UIKit

struct AccountSwitcherEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case account(sessionID: String)
        case addAccount
    }

    let id: String
    let kind: Kind
    let avatarURL: URL?
    let title: String
    let handle: String
    let isCurrent: Bool

    static func entries(
        sessions: [StoredAccountSession],
        activeSessionID: String?,
        addTitle: String
    ) -> [AccountSwitcherEntry] {
        // Priority outward from the Me tab, independent of its position on screen.
        let current = sessions.first { $0.id == activeSessionID }
        let others = sessions
            .filter { $0.id != activeSessionID }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
        var result = current.map { [entry(for: $0, isCurrent: true)] } ?? []
        result += others.map { entry(for: $0, isCurrent: false) }
        result.append(AccountSwitcherEntry(
            id: "add", kind: .addAccount, avatarURL: nil,
            title: addTitle, handle: "", isCurrent: false
        ))
        return result
    }

    private static func entry(for session: StoredAccountSession, isCurrent: Bool) -> AccountSwitcherEntry {
        let account = session.account
        let handle = account.acct.contains("@")
            ? "@\(account.acct)" : "@\(account.acct)@\(session.instanceHost)"
        let name = account.displayNameFormatted.trimmingCharacters(in: .whitespacesAndNewlines)
        return AccountSwitcherEntry(
            id: session.id, kind: .account(sessionID: session.id),
            avatarURL: account.avatarURL, title: name.isEmpty ? account.username : name,
            handle: handle, isCurrent: isCurrent
        )
    }
}

@MainActor
final class AccountSwitcherModel: ObservableObject {
    nonisolated deinit {}

    nonisolated enum Placement: Equatable { case aboveTabBar, belowTabBar }

    @Published var entries: [AccountSwitcherEntry] = []
    @Published var isPresented = false
    /// Released without choosing: the panel stays and takes taps.
    @Published var isSticky = false
    @Published var hoveredID: String?
    /// Hidden while its snapshot flies to the tab bar.
    @Published var flyingID: String?
    @Published var layout = AccountSwitcherLayout()
    /// Item frames in the host view's coordinates, for hit testing the drag.
    var itemFrames: [String: CGRect] = [:]

    var onSelect: (AccountSwitcherEntry) -> Void = { _ in }
    var onDismiss: () -> Void = {}
}

/// Physical coordinates in the overlay. The same geometry drives drawing, animation and drag selection.
struct AccountSwitcherLayout: Equatable {
    var source: CGPoint = .zero
    var frame: CGRect = .zero
    var placement: AccountSwitcherModel.Placement = .aboveTabBar
    var slots: [Int] = []
    private var visibleCount = 0
    var scrolls: Bool { slots.count > visibleCount }
    var opensRight = false

    init() {}

    init(source: CGPoint, bar: CGRect, column: CGRect?, safeArea: CGRect, count: Int, rightToLeft: Bool) {
        self.source = source
        guard count > 0 else { return }
        let margin = AccountSwitcherMetrics.edgeMargin
        let gap = AccountSwitcherMetrics.gapToTabBar
        let spacing = AccountSwitcherMetrics.spacing
        let height = AccountSwitcherMetrics.avatarSize + 2 * AccountSwitcherMetrics.padding
        let step = AccountSwitcherMetrics.avatarSize + spacing
        var left = safeArea.minX + margin
        var right = safeArea.maxX - margin
        var centerY: CGFloat
        if let column {
            opensRight = column.midX < safeArea.midX
            if opensRight { left = max(left, column.maxX + gap) }
            else { right = min(right, column.minX - gap) }
            centerY = source.y
        } else {
            let offset = source.x - safeArea.midX
            opensRight = abs(offset) <= 1 ? rightToLeft : offset < 0
            placement = bar.midY >= safeArea.midY ? .aboveTabBar : .belowTabBar
            centerY = placement == .aboveTabBar ? bar.minY - gap - height / 2 : bar.maxY + gap + height / 2
        }
        centerY = min(max(centerY, safeArea.minY + height / 2), safeArea.maxY - height / 2)
        let capacity = max(1, 1 + Int(floor((right - left - height) / step)))
        let visible = min(count, capacity)
        let width = height + CGFloat(visible - 1) * step
        visibleCount = visible

        // Pick a slot near Me, then shift the capsule just enough to line up their centers.
        // At an edge the accounts fan inward. In the middle both sides are within reach.
        let centered = min(max(source.x - width / 2, left), right - width)
        let fraction = (source.x - centered - height / 2) / step
        let closest = opensRight ? ceil(fraction - 0.5) : floor(fraction + 0.5)
        let current = min(max(Int(closest), 0), visible - 1)
        let x = max(left, min(source.x - height / 2 - CGFloat(current) * step, right - width))
        frame = CGRect(x: x, y: centerY - height / 2, width: width, height: height)

        let nearestFirst = (0..<visible).sorted { a, b in
            let da = abs(a - current), db = abs(b - current)
            return da == db ? (opensRight ? a > b : a < b) : da < db
        }
        var visibleSlots = Array(repeating: 0, count: visible)
        for (priority, slot) in nearestFirst.enumerated() { visibleSlots[slot] = priority }
        let overflow = Array(visible..<count)
        slots = opensRight ? visibleSlots + overflow : Array(overflow.reversed()) + visibleSlots
    }

    /// The held gesture uses resting positions even while the spring is still opening.
    /// The overflow row can scroll only after release, when selection is by direct tap.
    func entryIndex(at point: CGPoint) -> Int? {
        let slack = AccountSwitcherMetrics.spacing / 2 + AccountSwitcherMetrics.padding
        let band = frame.union(CGRect(origin: source, size: CGSize(width: 1, height: 1)))
            .insetBy(dx: -slack, dy: -70)
        guard visibleCount > 0, band.contains(point) else { return nil }
        let step = AccountSwitcherMetrics.avatarSize + AccountSwitcherMetrics.spacing
        let nearest = ((point.x - frame.minX - frame.height / 2) / step).rounded()
        let index = min(max(Int(nearest), 0), visibleCount - 1)
        let first = opensRight ? 0 : slots.count - visibleCount
        return slots[first + index]
    }
}

/// Every account is the same size; the current one wears the same ring as the Me tab's
/// avatar when selected, so the panel and the tab bar speak one visual language.
enum AccountSwitcherMetrics {
    static let avatarSize: CGFloat = 44
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 8
    static let edgeMargin: CGFloat = 12
    static let gapToTabBar: CGFloat = 12
    static let ringWidth: CGFloat = 2
    static let ringGap: CGFloat = 2
    static let hoverScale: CGFloat = 1.08
    static let hoverLift: CGFloat = 2

    static func layoutSize(of entry: AccountSwitcherEntry) -> CGFloat { avatarSize }

    /// Scale applied on top of the layout size, so frames (and hit testing) never move.
    static func scale(of entry: AccountSwitcherEntry, hovered: AccountSwitcherEntry?) -> CGFloat {
        hovered?.id == entry.id ? hoverScale : 1
    }

    static func lift(of entry: AccountSwitcherEntry, hovered: AccountSwitcherEntry?) -> CGFloat {
        hovered?.id == entry.id ? hoverLift : 0
    }

    /// The point size the avatar (without its ring) is drawn at right now.
    static func visualSize(of entry: AccountSwitcherEntry, hovered: AccountSwitcherEntry?) -> CGFloat {
        layoutSize(of: entry) * scale(of: entry, hovered: hovered)
    }
}

struct AccountSwitcherOverlay: View {
    @ObservedObject var model: AccountSwitcherModel
    @Environment(\.moroTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var presentAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.34, dampingFraction: 0.8)
    }

    @Environment(\.layoutDirection) private var contentDirection

    var body: some View {
        let layout = model.layout
        let atRest = model.isPresented || reduceMotion
        ZStack {
            Color.black
                .opacity(model.isPresented ? (theme.colorScheme == .dark ? 0.22 : 0.1) : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.onDismiss() }
                .accessibilityHidden(true)

            capsule
                .scaleEffect(atRest ? 1 : 0.25)
                .opacity(model.isPresented ? 1 : 0)
                .position(
                    x: atRest ? layout.frame.midX : layout.source.x,
                    y: atRest ? layout.frame.midY : layout.source.y
                )
        }
        .overlayPreferenceValue(AccountSwitcherFramesKey.self) { frames in hoverLabel(frames: frames) }
        // The controller supplies physical UIKit coordinates, including in RTL layouts.
        .environment(\.layoutDirection, .leftToRight)
        .coordinateSpace(name: AccountSwitcherOverlay.space)
        .onPreferenceChange(AccountSwitcherFramesKey.self) { model.itemFrames = $0 }
        .animation(presentAnimation, value: model.isPresented)
        .animation(.snappy(duration: 0.2), value: model.hoveredID)
    }

    static let space = "accountSwitcher"

    private var hoveredEntryForEmphasis: AccountSwitcherEntry? {
        model.hoveredID.flatMap { id in model.entries.first { $0.id == id } }
    }

    private var hoveredEntry: AccountSwitcherEntry? {
        guard let id = model.hoveredID, model.flyingID == nil else { return nil }
        return model.entries.first { $0.id == id }
    }

    @ViewBuilder
    private func hoverLabel(frames: [String: CGRect]) -> some View {
        if model.isPresented, let entry = hoveredEntry, let frame = frames[entry.id] {
            let panel = model.layout.frame
            let above = model.layout.placement == .aboveTabBar
            GeometryReader { proxy in
                let margin = AccountSwitcherMetrics.edgeMargin
                AccountSwitcherLabel(entry: entry)
                    .environment(\.layoutDirection, contentDirection)
                    .padding(.horizontal, margin)
                    .alignmentGuide(.leading) { size in
                        -min(max(0, frame.midX - size.width / 2), max(0, proxy.size.width - size.width))
                    }
                    .alignmentGuide(.top) { size in
                        -(above ? panel.minY - 14 - size.height : panel.maxY + 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var capsule: some View {
        Group {
            if model.layout.scrolls {
                let anchor: UnitPoint = model.layout.opensRight ? .leading : .trailing
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) { items }
                        .scrollIndicators(.hidden)
                        .defaultScrollAnchor(anchor)
                        .scrollDisabled(!model.isSticky)
                        .onChange(of: model.isPresented) { _, presented in
                            let edge = model.layout.opensRight ? model.layout.slots.first : model.layout.slots.last
                            if presented, let edge, model.entries.indices.contains(edge) {
                                proxy.scrollTo(model.entries[edge].id, anchor: anchor)
                            }
                        }
                }
                .id(model.layout.opensRight)
            } else {
                items
            }
        }
        .frame(width: model.layout.frame.width, height: model.layout.frame.height)
        .modifier(AccountSwitcherCapsuleBackground())
        .accessibilityElement(children: .contain)
    }

    private var items: some View {
        let entries = model.layout.slots.compactMap { index in
            model.entries.indices.contains(index) ? model.entries[index] : nil
        }
        return HStack(spacing: AccountSwitcherMetrics.spacing) {
            ForEach(entries) { entry in
                AccountSwitcherItem(
                    entry: entry,
                    hovered: hoveredEntryForEmphasis,
                    placement: model.layout.placement
                )
                .environment(\.layoutDirection, contentDirection)
                .opacity(model.flyingID == entry.id ? 0 : 1)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: AccountSwitcherFramesKey.self,
                            value: [entry.id: proxy.frame(in: .named(AccountSwitcherOverlay.space))]
                        )
                    }
                }
                .contentShape(Circle())
                .onTapGesture { model.onSelect(entry) }
                .accessibilityIdentifier(entry.kind == .addAccount
                    ? "accountSwitcher.add" : "accountSwitcher.account.\(entry.id)")
            }
        }
        .padding(AccountSwitcherMetrics.padding)
    }
}

private struct AccountSwitcherItem: View {
    let entry: AccountSwitcherEntry
    let hovered: AccountSwitcherEntry?
    let placement: AccountSwitcherModel.Placement
    @Environment(\.moroTheme) private var theme

    private var size: CGFloat { AccountSwitcherMetrics.layoutSize(of: entry) }
    /// Others recede only while a different account is previewed, not while resting on
    /// the current one, so the first glance at the panel stays fully legible.
    private var isDimmed: Bool {
        guard let hovered, hovered.id != entry.id else { return false }
        return !hovered.isCurrent
    }

    var body: some View {
        avatar
            .frame(width: size, height: size)
            .scaleEffect(AccountSwitcherMetrics.scale(of: entry, hovered: hovered))
            .offset(y: (placement == .aboveTabBar ? -1 : 1) * AccountSwitcherMetrics.lift(of: entry, hovered: hovered))
            .opacity(isDimmed ? 0.7 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(entry.kind == .addAccount
                ? entry.title : "\(entry.title), \(entry.handle)")
            .accessibilityAddTraits(entry.isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    /// The decoded image the switcher prefetched (the same one that flies to the Me tab),
    /// falling back to the regular remote avatar view.
    @ViewBuilder
    private var accountImage: some View {
        if let url = entry.avatarURL, let image = ImageCache.shared.image(for: url) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            MoroAvatar(imageURL: entry.avatarURL, staticImageURL: entry.avatarURL, size: size)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch entry.kind {
        case .account:
            accountImage
                .frame(width: size, height: size)
                .clipShape(Circle())
                // A hairline keeps pale avatars from dissolving into the glass.
                .overlay(Circle().strokeBorder(theme.colors.textPrimary.opacity(0.08), lineWidth: 0.5))
                .overlay {
                    if entry.isCurrent {
                        // Same ring as the selected Me tab avatar: a hairline gap, then the ring.
                        Circle()
                            .strokeBorder(theme.colors.textPrimary, lineWidth: AccountSwitcherMetrics.ringWidth)
                            .padding(-(AccountSwitcherMetrics.ringGap + AccountSwitcherMetrics.ringWidth))
                            .accessibilityHidden(true)
                    }
                }
        case .addAccount:
            Image(systemName: "plus")
                .moroScaledFont(size: 15, weight: .semibold)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(theme.colors.textPrimary.opacity(0.07)))
        }
    }
}

private struct AccountSwitcherLabel: View {
    let entry: AccountSwitcherEntry
    @Environment(\.moroTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.title)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.textPrimary)
            if !entry.handle.isEmpty {
                Text(entry.handle)
                    .font(.caption2)
                    .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .modifier(AccountSwitcherLabelBackground())
    }
}

private struct AccountSwitcherCapsuleBackground: ViewModifier {
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // A light surface tint keeps whatever sits underneath (the compose button,
            // media) from refracting through and muddying the avatars.
            content.glassEffect(
                .regular.tint(theme.colors.groupedSurface.opacity(theme.colorScheme == .dark ? 0.5 : 0.6)),
                in: Capsule()
            )
        } else {
            content
                .background(.thickMaterial, in: Capsule())
                // A hairline that reads on both a bright feed and the dark scrim.
                .overlay(Capsule().strokeBorder(
                    theme.colorScheme == .dark ? Color.white.opacity(0.14) : theme.colors.borderSubtle.opacity(0.6),
                    lineWidth: theme.colorScheme == .dark ? 0.75 : 0.5
                ))
                .shadow(color: .black.opacity(theme.colorScheme == .dark ? 0.4 : 0.14), radius: 18, y: 8)
        }
    }
}

private struct AccountSwitcherLabelBackground: ViewModifier {
    @Environment(\.moroTheme) private var theme

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
    }
}

private struct AccountSwitcherFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
