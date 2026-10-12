//
//  PrivacyProtectionViewModifier.swift
//  moro
//
//  Obscures app content before iOS captures its app-switcher snapshot.
//

import Combine
import SwiftUI

enum PrivacyProtectionPolicy {
    static let shieldBackgroundOpacity = 1.0

    /// `.inactive` is the app switcher (and Control/Notification Center), so it
    /// must be covered before iOS shows the card. A system permission alert that
    /// Moro itself raised also makes the scene inactive; covering the app then
    /// only hides the context the alert is asking about. `.background` is always
    /// covered so the saved snapshot never shows content.
    static func shouldObscureContent(for scenePhase: ScenePhase, isPresentingSystemPrompt: Bool = false) -> Bool {
        switch scenePhase {
        case .active: return false
        case .inactive: return !isPresentingSystemPrompt
        default: return true
        }
    }
}

/// Marks the span of a system prompt Moro requested (photo or notification
/// permission) so the inactive phase it causes doesn't raise the privacy shield.
@MainActor
final class PrivacyProtectionCenter: ObservableObject {
    static let shared = PrivacyProtectionCenter()

    @Published private(set) var isPresentingSystemPrompt = false
    private var activePrompts = 0

    /// The prompt's callback can arrive a beat before the scene is active again;
    /// keep the exemption briefly so the shield doesn't flash on the way back.
    private let settleDelay: Duration = .milliseconds(400)

    func whilePresentingSystemPrompt<T>(_ operation: () async throws -> T) async rethrows -> T {
        activePrompts += 1
        isPresentingSystemPrompt = true
        defer {
            activePrompts -= 1
            if activePrompts == 0 {
                Task { [settleDelay] in
                    try? await Task.sleep(for: settleDelay)
                    if self.activePrompts == 0 { self.isPresentingSystemPrompt = false }
                }
            }
        }
        return try await operation()
    }
}

struct PrivacyProtectionViewModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var protection = PrivacyProtectionCenter.shared

    func body(content: Content) -> some View {
        let obscuresContent = PrivacyProtectionPolicy.shouldObscureContent(
            for: scenePhase,
            isPresentingSystemPrompt: protection.isPresentingSystemPrompt
        )

        content
            .overlay {
                if obscuresContent {
                    PrivacyShieldView()
                        .transition(.identity)
                }
            }
            .animation(nil, value: scenePhase)
    }
}

struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .opacity(PrivacyProtectionPolicy.shieldBackgroundOpacity)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    Image(AppIconManager.shared.currentChoice.previewAssetName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 6)

                    Text("Moro")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Label(MoroL10n.PrivacyProtection.message, systemImage: "shield.lefthalf.filled")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    func privacyProtectedWhenInactive() -> some View {
        modifier(PrivacyProtectionViewModifier())
    }
}

#Preview("Privacy Shield") {
    PrivacyShieldView()
}
