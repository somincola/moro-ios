//
//  SharedComposeImportCoordinator.swift
//  moro
//
//  Consumes share-extension staging items and turns them into an initial compose payload.
//

import Foundation

struct SharedComposeAttachmentImportPayload: Equatable {
    let stagingItemID: String
    let sourceApplication: String?
    let attachments: [SharedComposeDraftAttachmentReference]
    var text: String = ""
}

struct SharedComposeImportResolution: Equatable {
    let draft: ComposeDraft
    let sharedImport: SharedComposeAttachmentImportPayload?
}

final class SharedComposeImportCoordinator {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let draftStore: ComposeDraftStore

    init(draftStore: ComposeDraftStore = .shared) {
        self.draftStore = draftStore
    }

    func consumeNextImportableDraft(activeAccountID: String?) -> SharedComposeImportResolution? {
        let pending = draftStore.pendingSharedStagingItems().filter {
            guard itemMatchesActiveAccount($0, activeAccountID: activeAccountID) else { return false }
            // Explicitly saved work belongs in Drafts. A failed attachment must not
            // immediately reopen the editor the user just chose to save and close.
            let owner = draftStore.draftOwningSharedImport($0.id)
            guard owner == nil || owner?.accountID == activeAccountID else { return false }
            return owner?.category != .manual || $0.id == SharedComposeHandoff.shared.requestedItemID
        }
        guard let stagedItem = pending.first(where: { $0.id == SharedComposeHandoff.shared.requestedItemID }) ?? pending.first else {
            return nil
        }

        let stagedDraft = stagedItem.asImportRecoveryDraft(accountID: activeAccountID)
        let draft: ComposeDraft
        if let existingDraft = draftStore.draftForSharedImport(stagedItem.id, accountID: activeAccountID) {
            // Preserve attachments already uploaded during an earlier partial import.
            draft = existingDraft
        } else {
            guard draftStore.save(stagedDraft) else {
                AppLogger.error("Failed to persist shared compose draft before opening it")
                return nil
            }
            draft = stagedDraft
        }

        if stagedItem.attachments.isEmpty {
            draftStore.removePendingSharedStagingItem(id: stagedItem.id)
        }

        let sharedImport: SharedComposeAttachmentImportPayload?
        if stagedItem.attachments.isEmpty {
            sharedImport = nil
        } else {
            sharedImport = SharedComposeAttachmentImportPayload(
                stagingItemID: stagedItem.id,
                sourceApplication: stagedItem.sourceApplication,
                attachments: stagedItem.attachments,
                text: stagedItem.payload.content
            )
        }

        SharedComposeHandoff.shared.acknowledge(stagedItem.id)
        return SharedComposeImportResolution(
            draft: draft,
            sharedImport: sharedImport
        )
    }

    private func itemMatchesActiveAccount(
        _ item: SharedComposeDraftStagingItem,
        activeAccountID: String?
    ) -> Bool {
        guard let itemAccountID = item.accountID else { return true }
        guard let activeAccountID else { return false }
        return itemAccountID == activeAccountID
    }
}
