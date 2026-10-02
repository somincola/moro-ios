import SwiftUI

/// Profile and post entry points share the same report flow.
struct AccountReportView: View {
    let account: Account
    let apiClient: MastodonAPI
    let onDismiss: () -> Void

    var body: some View {
        ReportView(account: account, apiClient: apiClient, onDismiss: onDismiss)
    }
}
