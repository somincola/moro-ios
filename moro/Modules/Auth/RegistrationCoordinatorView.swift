//
//  RegistrationCoordinatorView.swift
//  moro
//
//  Self-contained sign-up flow presented modally from login:
//  pick a server → review server info → fill the form → result.
//  Closing the flow returns to the login screen.
//

import SwiftUI

struct RegistrationCoordinatorView: View {
    @ObservedObject var authService: AuthService
    let onAuthenticated: (String, Account, URL) -> Void
    let onClose: () -> Void

    @State private var path: [Route] = []

    enum Route: Hashable {
        case serverInfo(domain: String)
        case rules(domain: String)
        case form(domain: String)
    }

    var body: some View {
        NavigationStack(path: $path) {
            RegistrationServerPickerView(
                onClose: onClose,
                onSelectServer: { domain in
                    path.append(.serverInfo(domain: domain))
                }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .serverInfo(let domain):
                    ServerInfoView(
                        authService: authService,
                        domain: domain,
                        onContinue: {
                            path.append(.rules(domain: domain))
                        }
                    )
                case .rules(let domain):
                    RegistrationRulesView(
                        rules: authService.currentRegistrationInfo?.rules ?? [],
                        onContinue: {
                            path.append(.form(domain: domain))
                        }
                    )
                case .form(let domain):
                    RegistrationFlowView(
                        authService: authService,
                        instanceDomain: domain,
                        onRegistrationAuthenticated: onAuthenticated,
                        onRequestBackToLogin: { _, _ in
                            onClose()
                        }
                    )
                }
            }
        }
    }
}
