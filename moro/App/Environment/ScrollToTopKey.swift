//
//  ScrollToTopKey.swift
//  moro
//
//  Environment value for "the selected tab was tapped again".
//

import SwiftUI

/// One re-tap of the already-selected root tab. Every re-tap gets a new `sequence`, so
/// `onChange` fires for each tap and no reset timer is needed. Root pages react the same
/// way: away from the top they scroll back up, at the top they refresh.
struct TabReselection: Equatable, Sendable {
    let tab: MainTab
    let sequence: Int
}

private struct TabReselectionKey: EnvironmentKey {
    static let defaultValue: TabReselection? = nil
}

extension EnvironmentValues {
    /// The latest re-tap of a root tab, injected only into that tab's root page.
    var tabReselection: TabReselection? {
        get { self[TabReselectionKey.self] }
        set { self[TabReselectionKey.self] = newValue }
    }
}

extension View {
    /// Runs `action` for each new re-tap of `tab`. A re-tap that happened before this view
    /// appeared (for example before an account switch rebuilt the page) is never replayed.
    func onTabReselect(_ tab: MainTab, perform action: @escaping () -> Void) -> some View {
        modifier(TabReselectModifier(tab: tab, action: action))
    }
}

private struct TabReselectModifier: ViewModifier {
    @Environment(\.tabReselection) private var reselection
    @State private var handledSequence: Int?
    let tab: MainTab
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                if handledSequence == nil { handledSequence = reselection?.sequence ?? 0 }
            }
            .onChange(of: reselection) { _, event in
                guard let event, event.sequence > (handledSequence ?? 0) else { return }
                handledSequence = event.sequence
                guard event.tab == tab else { return }
                action()
            }
    }
}
