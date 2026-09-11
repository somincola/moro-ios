import Foundation
import Testing
@testable import moro

@Suite(.serialized) @MainActor
struct AppSupportTests {
    @Test func feedbackCreatesIndependentEditableDraftsWithoutPersonalDiagnostics() {
        let first = MoroFeedbackDraft.make(accountID: "account-a")
        let second = MoroFeedbackDraft.make(accountID: "account-a")
        #expect(first.id != second.id)
        #expect(first.category == .manual && first.payload.visibility == .public)
        #expect(first.payload.content == "@acacius@m.somincola.org #Moro\n\n")
        #expect(!first.payload.content.contains("account-a"))
        #expect(first.payload.mediaAttachments.isEmpty && !first.payload.isSchedulingEnabled)
    }
}
