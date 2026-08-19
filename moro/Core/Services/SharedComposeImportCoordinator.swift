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
}

struct SharedComposeImportResolution: Equatable {
    let draft: ComposeDraft
    let sharedImport: SharedComposeAttachmentImportPayload?
}

final class SharedComposeImportCoordinator {
    private let draftStore: ComposeDraftStore

    init(draftStore: ComposeDraftStore = .shared) {
        self.draftStore = draftStore
    }

    func consumeNextImportableDraft(activeAccountID: String?) -> SharedComposeImportResolution? {
        guard let stagedItem = draftStore.pendingSharedStagingItems().first(where: {
            itemMatchesActiveAccount($0, activeAccountID: activeAccountID)
        }) else {
            return nil
        }

        let stagedDraft = stagedItem.asManualDraft()
        let draft: ComposeDraft
        if let existingDraft = draftStore.draft(id: stagedDraft.id) {
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
                attachments: stagedItem.attachments
            )
        }

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
