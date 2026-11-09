//
//  ComposeMediaGridHarnessView.swift
//  moro
//
//  Deterministic UI-test harness for attachment identity and repeated deletion.
//

#if DEBUG
import SwiftUI

struct ComposeMediaGridHarnessView: View {
    @State private var attachments = Self.makeAttachments()

    var body: some View {
        VStack(spacing: 16) {
            Text(attachments.map(\.id).joined(separator: ","))
                .font(.caption.monospaced())
                .accessibilityIdentifier("compose.media.ids")

            ComposeMediaGridView(
                attachments: attachments,
                onRemove: { attachmentID in
                    attachments.removeAll { $0.id == attachmentID }
                },
                onEditAlt: { _ in },
                onRetry: { _ in }
            )

            Button("Reset") {
                attachments = Self.makeAttachments()
            }
            .accessibilityIdentifier("compose.media.reset")
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }

    private static func makeAttachments() -> [MediaAttachment] {
        // Instances may allow more than 4 attachments; UITEST_COMPOSE_MEDIA_COUNT exercises that grid.
        let count = Int(ProcessInfo.processInfo.environment["UITEST_COMPOSE_MEDIA_COUNT"] ?? "") ?? 4
        return (1...max(1, count)).map { index in
            ("media-\(index)", index == 2 ? "video" : "image")
        }.map { id, type in
            MediaAttachment(
                id: id,
                url: URL(string: "about:blank#\(id)")!,
                previewURL: nil,
                type: type,
                description: nil,
                focus: nil,
                uploadState: .uploaded
            )
        }
    }
}
#endif
