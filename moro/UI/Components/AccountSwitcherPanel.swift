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
        // Left to right: add, older accounts, most recent, then the current account
        // nearest the Me tab, so the likeliest target is the shortest slide away.
        let current = sessions.first { $0.id == activeSessionID }
        let others = sessions
            .filter { $0.id != activeSessionID }
            .sorted { $0.lastUsedAt < $1.lastUsedAt }
        var result = [AccountSwitcherEntry(
            id: "add", kind: .addAccount, avatarURL: nil,
            title: addTitle, handle: "", isCurrent: false
        )]
        result += others.map { entry(for: $0, isCurrent: false) }
        if let current { result.append(entry(for: current, isCurrent: true)) }
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
    @Published var placement: Placement = .aboveTabBar
    /// Distance from the host's trailing edge to the panel's trailing edge.
    @Published var trailingInset: CGFloat = 16
    /// Distance from the host's bottom (or top, below placement) to the panel.
    @Published var edgeInset: CGFloat = 100
    /// Item frames in the host view's coordinates, for hit testing the drag.
    var itemFrames: [String: CGRect] = [:]

    var onSelect: (AccountSwitcherEntry) -> Void = { _ in }
    var onDismiss: () -> Void = {}
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

    var body: some View {
        ZStack(alignment: model.placement == .aboveTabBar ? .bottomTrailing : .topTrailing) {
            // A quiet scrim focuses the panel; in sticky mode it also dismisses on tap.
            Color.black
                .opacity(model.isPresented ? (theme.colorScheme == .dark ? 0.22 : 0.1) : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { model.onDismiss() }
                .accessibilityHidden(true)

            panel
                .padding(.trailing, model.trailingInset)
                .padding(model.placement == .aboveTabBar ? .bottom : .top, model.edgeInset)
                .scaleEffect(
                    model.isPresented || reduceMotion ? 1 : 0.5,
                    anchor: model.placement == .aboveTabBar ? .bottomTrailing : .topTrailing
                )
                .opacity(model.isPresented ? 1 : 0)
        }
        .coordinateSpace(name: AccountSwitcherOverlay.space)
        .onPreferenceChange(AccountSwitcherFramesKey.self) { model.itemFrames = $0 }
        .animation(presentAnimation, value: model.isPresented)
        .animation(.snappy(duration: 0.2), value: model.hoveredID)
    }

    static let space = "accountSwitcher"

    private var panel: some View {
        VStack(alignment: .trailing, spacing: 14) {
            if model.placement == .aboveTabBar { hoverLabel }
            capsule
            if model.placement == .belowTabBar { hoverLabel }
        }
    }

    private var hoveredEntryForEmphasis: AccountSwitcherEntry? {
        model.hoveredID.flatMap { id in model.entries.first { $0.id == id } }
    }

    private var hoveredEntry: AccountSwitcherEntry? {
        guard let id = model.hoveredID, model.flyingID == nil else { return nil }
        return model.entries.first { $0.id == id }
    }

    /// One caption for the hovered account, centred over its avatar but kept
    /// inside the capsule's trailing edge and the screen's leading margin.
    @ViewBuilder
    private var hoverLabel: some View {
        if let entry = hoveredEntry, let frame = model.itemFrames[entry.id] {
            let capsuleTrailing = (model.itemFrames.values.map(\.maxX).max() ?? frame.maxX)
                + AccountSwitcherMetrics.padding
            let toItemCenter = capsuleTrailing - frame.midX
            AccountSwitcherLabel(entry: entry)
                .fixedSize()
                .alignmentGuide(.trailing) { dimensions in
                    let centred = max(0, toItemCenter - dimensions.width / 2)
                    let leadingLimit = max(0, capsuleTrailing - AccountSwitcherMetrics.edgeMargin - dimensions.width)
                    return dimensions.width + min(centred, leadingLimit)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.92,
                    anchor: model.placement == .aboveTabBar ? .bottom : .top)))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var capsule: some View {
        HStack(spacing: AccountSwitcherMetrics.spacing) {
            ForEach(model.entries) { entry in
                AccountSwitcherItem(
                    entry: entry,
                    hovered: hoveredEntryForEmphasis,
                    placement: model.placement
                )
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
        .modifier(AccountSwitcherCapsuleBackground())
        .accessibilityElement(children: .contain)
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
