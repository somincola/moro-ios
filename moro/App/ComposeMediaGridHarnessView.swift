//
//  ComposeMediaGridHarnessView.swift
//  moro
//
//  Deterministic UI-test harness for attachment identity and repeated deletion.
//

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
        [
            ("media-1", "image"),
            ("media-2", "video"),
            ("media-3", "image"),
            ("media-4", "image"),
        ].map { id, type in
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
