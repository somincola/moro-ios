//
//  ComposeDraftsSheet.swift
//  moro
//
//  Saved drafts list. Tap to restore into compose, swipe to delete.
//

import SwiftUI

struct ComposeDraftsSheet: View {
    let accountID: String?
    let draftStore: ComposeDraftStore
    let onRestore: (ComposeDraft) -> Void

    @Environment(\.moroTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [ComposeDraft] = []

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    emptyState
                } else {
                    draftList
                }
            }
            .navigationTitle(MoroL10n.ComposeDrafts.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(MoroL10n.Common.done) {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            drafts = draftStore.drafts(for: accountID)
        }
    }

    private var emptyState: some View {
        VStack(spacing: theme.spacing.m) {
            Image(systemName: "doc.text")
                .moroScaledFont(size: 40)
                .foregroundStyle(theme.colors.textTertiary)
            Text(MoroL10n.ComposeDrafts.emptyTitle)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
            Text(MoroL10n.ComposeDrafts.emptyMessage)
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(theme.spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var draftList: some View {
        List {
            ForEach(drafts) { draft in
                Button {
                    onRestore(draft)
                } label: {
                    draftRow(draft)
                }
                .listRowBackground(theme.colors.background)
            }
            .onDelete { indexSet in
                var didFail = false
                for index in indexSet {
                    if !draftStore.removeDraft(id: drafts[index].id) {
                        didFail = true
                    }
                }
                drafts = draftStore.drafts(for: accountID)
                if didFail {
                    AppFeedbackCenter.shared.showError(MoroL10n.ComposeDrafts.saveFailed)
                }
            }
        }
        .listStyle(.plain)
    }

    private func draftRow(_ draft: ComposeDraft) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.xs) {
            HStack(spacing: theme.spacing.s) {
                Text(draft.contextLabel)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.primary500)

                if draft.category == .auto {
                    Text(draft.categoryLabel)
                        .moroScaledFont(size: 10, weight: .medium)
                        .foregroundStyle(theme.colors.textTertiary)
                        .padding(.horizontal, theme.spacing.xs)
                        .padding(.vertical, theme.spacing.micro)
                        .background(
                            Capsule()
                                .fill(theme.colors.surfaceBase)
                        )
                }

                Spacer()

                Text(DateFormatting.relativeString(for: draft.updatedAt))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
            }

            Text(draft.displayPreviewText)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(3)

            if draft.payload.isPollActive {
                Label(MoroL10n.ComposeDrafts.pollBadge, systemImage: "chart.bar")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            if !draft.payload.mediaAttachments.isEmpty {
                Label(
                    "\(draft.payload.mediaAttachments.count)",
                    systemImage: "photo"
                )
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .padding(.vertical, theme.spacing.xs)
    }
}
