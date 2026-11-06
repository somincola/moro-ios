import SwiftUI

/// The dismiss (✕) and confirm (✓) buttons of sheets and forms.
///
/// On iOS 26 and later they use the system close/confirm roles with a symbol, so the bar draws
/// the standard glass buttons and, on iPhone Duo, can move them into the vertical side bar (a
/// text-only item can't go vertical and would fall into the overflow menu). The title stays the
/// accessibility label. Earlier systems keep the text button.
struct MoroToolbarButton: View {
    enum Kind {
        /// Cancel / close: ✕, placed with `.cancellationAction`.
        case close
        /// Done / save / create: ✓, placed with `.confirmationAction`.
        case confirm
    }

    private let title: String
    private let kind: Kind
    private let systemImage: String?
    private let identifier: String?
    private let action: () -> Void

    /// `identifier` is the accessibility identifier for iOS 18–25. On iOS 26+ the bar turns the
    /// button into a system item that carries no identifier; UI tests match its title there.
    init(
        _ title: String,
        kind: Kind,
        systemImage: String? = nil,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
        self.identifier = identifier
        self.action = action
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: kind == .close ? .close : .confirm, action: action) {
                Label(title, systemImage: symbol)
            }
        } else if let identifier {
            textButton.accessibilityIdentifier(identifier)
        } else {
            textButton
        }
    }

    private var textButton: some View {
        Button(title, action: action)
            .fontWeight(kind == .confirm ? .semibold : nil)
    }

    private var symbol: String {
        systemImage ?? (kind == .close ? "xmark" : "checkmark")
    }
}
