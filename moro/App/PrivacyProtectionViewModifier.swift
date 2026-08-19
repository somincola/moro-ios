//
//  PrivacyProtectionViewModifier.swift
//  moro
//
//  Obscures app content before iOS captures its app-switcher snapshot.
//

import SwiftUI

enum PrivacyProtectionPolicy {
    static let shieldBackgroundOpacity = 1.0

    static func shouldObscureContent(for scenePhase: ScenePhase) -> Bool {
        scenePhase != .active
    }
}

struct PrivacyProtectionViewModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        let obscuresContent = PrivacyProtectionPolicy.shouldObscureContent(for: scenePhase)

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
