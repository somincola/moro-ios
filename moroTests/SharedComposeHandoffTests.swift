import Foundation
import Darwin
import Testing
import UIKit
@testable import moro

@Suite(.serialized)
@MainActor
struct SharedComposeHandoffTests {
    @Test func handoffAcceptsOnlyAnOpaqueShareIDAndTracksTheEditorLifetime() {
        let handoff = SharedComposeHandoff(notificationCenter: NotificationCenter())
        let id = UUID().uuidString
        #expect(handoff.receive(URL(string: "moro://share/compose?item=\(id)")!))
        #expect(handoff.requestedItemID == id)
        for url in ["moro://oauth/callback?item=\(id)", "https://share/compose?item=\(id)",
                    "moro://share/compose?item=../private", "moro://share/compose?item=\(id)&file=/private/a",
                    "moro://user@share/compose?item=\(id)", "moro://share/compose?item=\(id)#extra"] {
            #expect(!handoff.receive(URL(string: url)!))
        }
        let editor = SharedComposeEditingSession(handoff: handoff)
        editor.activate()
        editor.activate()
        #expect(handoff.hasPresentedEditor)
        editor.finish()
        #expect(!handoff.hasPresentedEditor)
        handoff.acknowledge(id)
        #expect(handoff.requestedItemID == nil)
    }

    @Test func incomingBatchAppendsToExistingTextAndMediaWithoutPublishingOrMakingAManualDraft() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        var uploads = 0
        api.uploadMediaHandler = { _, _, _ in
            uploads += 1
            return Self.serverAttachment("upload-\(uploads)")
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        model.content = "Existing text"
        model.mediaAttachments = [Self.serverMedia("existing")]
        let item = try fixture.stage(text: "Shared caption", count: 2)
        let payload = Self.importPayload(item)
        #expect(await model.importSharedAttachments(from: payload, draftStore: fixture.store) == .complete)
        #expect(model.content == "Existing text\n\nShared caption")
        #expect(model.mediaAttachments.map(\.id) == ["existing", "upload-1", "upload-2"])
        #expect(uploads == 2)
        #expect(fixture.store.pendingSharedStagingItems().isEmpty)
        let savedID = try #require(model.activeDraftID)
        let saved = try #require(fixture.store.draft(id: savedID))
        #expect(saved.category == .auto)
        #expect(saved.sharedImportItemIDs == [item.id])
        #expect(saved.payload.mediaAttachments.last?.sharedImportAttachmentID == item.attachments.last?.id)
        // A repeated foreground/URL delivery may not duplicate text or upload media again.
        #expect(await model.importSharedAttachments(from: payload, draftStore: fixture.store) == .complete)
        #expect(uploads == 2)
        #expect(model.content == "Existing text\n\nShared caption")
        #expect(fixture.store.save(model.makeDraft(category: .manual)))
        #expect(fixture.store.draft(id: saved.id)?.category == .manual)
    }

    @Test func aBatchThatDoesNotFitIsKeptIntactUntilSlotsAreAvailable() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        var uploads = 0
        api.uploadMediaHandler = { _, _, _ in uploads += 1; return Self.serverAttachment("new-\(uploads)") }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        model.content = "Keep this"
        model.mediaAttachments = (0..<3).map { Self.serverMedia("old-\($0)") }
        let item = try fixture.stage(text: "Do not append yet", count: 2)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .blocked)
        #expect(model.content == "Keep this")
        #expect(uploads == 0)
        #expect(fixture.store.pendingSharedStagingItems().first?.attachments.count == 2)
        #expect(fixture.store.drafts(for: "me").isEmpty)
        _ = model.removeMedia(id: "old-0")
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .complete)
        #expect(model.mediaAttachments.count == 4)
    }

    @Test func activePollAndPublishingKeepTheIncomingFilesWithoutChangingTheEditor() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let model = ComposeViewModel(context: .newPost, apiClient: MockMastodonAPI(), currentUserID: "me")
        let item = try fixture.stage(text: "Caption", count: 1)
        model.isPollActive = true
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .blocked)
        model.isPollActive = false
        model.isPublishing = true
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .blocked)
        #expect(model.content.isEmpty && model.mediaAttachments.isEmpty)
        #expect(fixture.store.pendingSharedStagingItems().count == 1)
    }

    @Test func recoveryFindsTheExistingEditorAndUploadsOnlyTheFailedRemainder() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        var uploads = 0
        api.uploadMediaHandler = { _, _, _ in
            uploads += 1
            if uploads == 2 { throw URLError(.notConnectedToInternet) }
            return Self.serverAttachment("upload-\(uploads)")
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        model.content = "Keep original"
        let item = try fixture.stage(text: "Shared text", count: 2)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .partial)
        let id = try #require(model.activeDraftID)
        #expect(!id.hasPrefix(ComposeDraftStore.sharedDraftIDPrefix))
        #expect(fixture.store.pendingSharedStagingItems().first?.attachments.count == 1)
        let resolution = try #require(SharedComposeImportCoordinator(draftStore: fixture.store)
            .consumeNextImportableDraft(activeAccountID: "me"))
        #expect(resolution.draft.id == id)
        let restored = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me", initialDraft: resolution.draft)
        #expect(await restored.importSharedAttachments(from: try #require(resolution.sharedImport), draftStore: fixture.store) == .complete)
        #expect(restored.content == "Keep original\n\nShared text")
        #expect(restored.mediaAttachments.map(\.id) == ["upload-1", "upload-3"])
        #expect(uploads == 3)
        #expect(fixture.store.pendingSharedStagingItems().isEmpty)
    }

    @Test func discardingAnExistingEditorClearsItsShareEvenIfTheUploadFinishesLate() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        var response: CheckedContinuation<Status.Attachment, Never>?
        api.uploadMediaHandler = { _, _, _ in
            await withCheckedContinuation { response = $0 }
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        model.content = "An existing editor"
        let item = try fixture.stage(text: "Shared", count: 1)
        let task = Task { await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) }
        try await wait { response != nil }
        model.cancelSharedImports()
        task.cancel()
        #expect(fixture.store.removeDraft(id: try #require(model.activeDraftID)))
        response?.resume(returning: Self.serverAttachment("late-response"))
        #expect(await task.value == .cancelled)
        #expect(fixture.store.drafts(for: "me").isEmpty)
        #expect(fixture.store.pendingSharedStagingItems().isEmpty)
    }

    @Test func explicitlySavingAFailedImportDoesNotImmediatelyReopenTheEditor() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        api.uploadMediaHandler = { _, _, _ in throw URLError(.notConnectedToInternet) }
        let item = try fixture.stage(text: "Keep in Drafts", count: 1)
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .failed)
        #expect(model.draftPersistenceBlocker == nil, "Staged originals make a failed shared upload safe to save")
        #expect(fixture.store.save(model.makeDraft(category: .manual)))
        #expect(SharedComposeImportCoordinator(draftStore: fixture.store).consumeNextImportableDraft(activeAccountID: "me") == nil)
        #expect(fixture.store.drafts(for: "me").first?.category == .manual)
        #expect(fixture.store.pendingSharedStagingItems().count == 1)
    }

    @Test func importingDoesNotReplaceAnUnrelatedAutomaticDraftAndAnOpenRootIsNotReplaced() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let previous = ComposeDraft(id: "previous", accountID: "me", category: .auto,
            target: .init(kind: .newPost), payload: Self.payload("Unrelated automatic draft"), createdAt: Date(), updatedAt: Date())
        #expect(fixture.store.save(previous))
        let item = try fixture.stage(text: "Incoming", count: 1)
        let root = RootTabCoordinator()
        root.openCompose()
        let editorID = root.composeContext?.id
        let importer = SharedComposeImportCoordinator(draftStore: fixture.store)
        #expect(root.presentPendingSharedImport(using: importer, accountID: "me") == nil)
        #expect(root.composeContext?.id == editorID)
        #expect(fixture.store.pendingSharedStagingItems().first?.id == item.id)
        root.composeContext = nil
        #expect(root.presentPendingSharedImport(using: importer, accountID: "me") != nil)
        #expect(fixture.store.draft(id: previous.id)?.payload.content == "Unrelated automatic draft")
        #expect(fixture.store.drafts(for: "me").count == 2)
        #expect(root.composeContext?.draft?.category == .auto)
    }

    @Test func switchingDraftsStopsTheOldBatchFromUploadingIntoTheRestoredDraft() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        var uploads = 0
        var response: CheckedContinuation<Status.Attachment, Never>?
        api.uploadMediaHandler = { _, _, _ in
            uploads += 1
            return await withCheckedContinuation { response = $0 }
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        let item = try fixture.stage(text: "Old batch", count: 2)
        let task = Task { await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) }
        try await wait { response != nil }
        let restored = ComposeDraft(id: "restored", accountID: "me", category: .manual,
            target: .init(kind: .newPost), payload: Self.payload("Other draft"), createdAt: Date(), updatedAt: Date())
        model.applyRestoredDraft(restored)
        response?.resume(returning: Self.serverAttachment("old-response"))
        #expect(await task.value == .cancelled)
        #expect(uploads == 1)
        #expect(model.content == "Other draft" && model.mediaAttachments.isEmpty)
        #expect(fixture.store.pendingSharedStagingItems().first?.attachments.count == 2)
    }

    @Test func anInitiallyUnboundShareCannotMoveToAnotherAccountAfterBeingClaimed() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let item = try fixture.store.stageSharedDraft(accountID: nil, target: .init(kind: .newPost),
            payload: Self.payload("Unbound share"))
        let recovery = item.asImportRecoveryDraft(accountID: "me")
        #expect(fixture.store.save(recovery))
        let coordinator = SharedComposeImportCoordinator(draftStore: fixture.store)
        #expect(coordinator.consumeNextImportableDraft(activeAccountID: "other-account") == nil)
        #expect(fixture.store.draft(id: recovery.id)?.accountID == "me")
        #expect(fixture.store.pendingSharedStagingItems().count == 1)
        #expect(coordinator.consumeNextImportableDraft(activeAccountID: "me")?.draft.id == recovery.id)
    }

    @Test func aCancelledBatchBlocksPublishingUntilEveryRemainingSharedImageIsImported() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        var uploads = 0
        api.uploadMediaHandler = { _, _, _ in
            uploads += 1
            if uploads == 2 { withUnsafeCurrentTask { $0?.cancel() } }
            return Self.serverAttachment("upload-\(uploads)")
        }
        let item = try fixture.stage(text: "Four photos", count: 4)
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        let operation = Task { await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) }
        #expect(await operation.value == .partial)
        #expect(model.mediaAttachments.count == 2 && !model.hasFailedMedia && !model.hasUploadingMedia)
        #expect(model.publishBlocker == .sharedImportIncomplete && !model.canPublish)
        do { _ = try await model.publish(); Issue.record("A partial share must not publish just its uploaded half") }
        catch ComposeError.sharedImportIncomplete {}
        #expect(api.publishIdempotencyKeys.isEmpty)

        let savedID = try #require(model.activeDraftID)
        let saved = try #require(fixture.store.draft(id: savedID))
        let restored = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me", initialDraft: saved)
        #expect(!restored.canPublish, "A restored shared draft is blocked before its queue has been checked")
        restored.configureSharedImportRecovery(using: fixture.store)
        #expect(!restored.canPublish)
        let remaining = try #require(fixture.store.pendingSharedStagingItems().first)
        #expect(remaining.attachments.count == 2)
        #expect(await restored.importSharedAttachments(from: Self.importPayload(remaining), draftStore: fixture.store) == .complete)
        #expect(restored.mediaAttachments.map(\.id) == ["upload-1", "upload-2", "upload-3", "upload-4"])
        #expect(restored.canPublish && !restored.hasPendingSharedMedia)
        #expect(api.publishIdempotencyKeys.isEmpty)
    }

    @Test func failedSharedImagesCanBeSavedButCannotBePublished() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        api.uploadMediaHandler = { _, _, _ in throw URLError(.notConnectedToInternet) }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        let item = try fixture.stage(text: "Keep all photos", count: 1)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .failed)
        #expect(model.draftPersistenceBlocker == nil && model.publishBlocker == .mediaUploadFailed)
        do { _ = try await model.publish(); Issue.record("A failed shared attachment must block the request") }
        catch ComposeError.uploadFailed {}
        #expect(api.publishIdempotencyKeys.isEmpty)
    }

    @Test func aBusyIndexCannotAcknowledgeOrDeleteFilesAndBlocksPublishing() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let item = try fixture.stage(text: "Keep originals", count: 1)
        let reference = try #require(item.attachments.first)
        let file = fixture.store.sharedAttachmentFileURL(for: reference)
        let defaults = try #require(UserDefaults(suiteName: fixture.suites[1]))
        let metadata = defaults.data(forKey: "shared_compose_draft_staging_items_v1")
        let recovery = item.asImportRecoveryDraft(accountID: "me")
        #expect(fixture.store.save(recovery))
        let model = ComposeViewModel(context: .newPost, apiClient: MockMastodonAPI(), currentUserID: "me",
            initialDraft: recovery)
        model.configureSharedImportRecovery(using: fixture.store)
        let lockURL = fixture.directory.appendingPathComponent("staging/.index.lock")
        let descriptor = Darwin.open(lockURL.path, O_RDWR)
        try #require(descriptor >= 0)
        defer { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        #expect(!fixture.store.acknowledgeImportedSharedAttachment(stagingItemID: item.id, attachmentID: reference.id))
        #expect(!fixture.store.removePendingSharedStagingItem(id: item.id))
        #expect(!fixture.store.removeDraft(id: recovery.id))
        #expect(fixture.store.draft(id: recovery.id) != nil, "A failed discard must retain the recovery owner")
        #expect(defaults.data(forKey: "shared_compose_draft_staging_items_v1") == metadata)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!model.canPublish && model.hasPendingSharedMedia)
        do { _ = try fixture.store.pendingSharedStagingItemsForPublishing(); Issue.record("Busy index must not read as empty") }
        catch {}
    }

    @Test func aCorruptIndexCannotMakeAnIncompleteShareLookReadyToPublish() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        api.uploadMediaHandler = { _, _, _ in Self.serverAttachment("uploaded") }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        let item = try fixture.stage(text: "Do not bypass validation", count: 1)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .complete)
        #expect(model.canPublish)
        let defaults = try #require(UserDefaults(suiteName: fixture.suites[1]))
        defaults.set(Data("invalid-index".utf8), forKey: "shared_compose_draft_staging_items_v1")
        // The direct call re-reads the index authoritatively, even before the UI snapshot refreshes.
        do { _ = try await model.publish(); Issue.record("Unreadable recovery state must block publishing") }
        catch ComposeError.sharedImportIncomplete {}
        #expect(api.publishIdempotencyKeys.isEmpty)
        #expect(!model.canPublish && model.publishBlocker == .sharedImportIncomplete)
        #expect(model.sharedStagingUnreadable, "The editor must offer the explicit discard")
    }

    @Test func discardingRepairsAnUnreadableIndexInsteadOfTrappingTheDraft() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        var uploads = 0
        api.uploadMediaHandler = { _, _, _ in
            uploads += 1
            if uploads > 1 { throw URLError(.notConnectedToInternet) }
            return Self.serverAttachment("uploaded-\(uploads)")
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        let item = try fixture.stage(text: "Two photos", count: 2)
        let other = try fixture.stage(text: "Unrelated share", count: 1)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .partial)
        let defaults = try #require(UserDefaults(suiteName: fixture.suites[1]))
        let valid = try #require(defaults.data(forKey: "shared_compose_draft_staging_items_v1"))
        // Corrupt only the draft's own entry; the unrelated share must survive the repair.
        var rows = try #require(JSONSerialization.jsonObject(with: valid) as? [[String: Any]])
        let index = try #require(rows.firstIndex { $0["id"] as? String == item.id })
        rows[index]["createdAt"] = "not-a-date"
        defaults.set(try JSONSerialization.data(withJSONObject: rows), forKey: "shared_compose_draft_staging_items_v1")

        model.refreshPendingSharedMedia()
        #expect(model.sharedStagingUnreadable && !model.canPublish)
        #expect(model.discardRemainingSharedImports(using: fixture.store))
        #expect(!model.sharedStagingUnreadable && model.canPublish)
        #expect(model.mediaAttachments.map(\.id) == ["uploaded-1"], "Uploaded media survives an explicit discard")
        #expect(try fixture.store.pendingSharedStagingItemsForPublishing().map(\.id) == [other.id])
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("staging/\(item.id)").path))
        #expect(defaults.data(forKey: "shared_compose_draft_staging_items_v1_corrupt_backup") != nil)
        #expect(api.publishIdempotencyKeys.isEmpty)
    }

    @Test func aDraftCanBeDiscardedWhileItsShareIndexIsUnreadable() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let item = try fixture.stage(text: "Trapped?", count: 1)
        let recovery = item.asImportRecoveryDraft(accountID: "me")
        #expect(fixture.store.save(recovery))
        let defaults = try #require(UserDefaults(suiteName: fixture.suites[1]))
        defaults.set(Data("invalid-index".utf8), forKey: "shared_compose_draft_staging_items_v1")
        #expect(fixture.store.removeDraft(id: recovery.id))
        #expect(fixture.store.draft(id: recovery.id) == nil)
        #expect(try fixture.store.pendingSharedStagingItemsForPublishing().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("staging/\(item.id)").path))
    }

    @Test func briefIndexContentionIsRetriedAndDoesNotFlipThePublishButton() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        api.uploadMediaHandler = { _, _, _ in Self.serverAttachment("uploaded") }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        let item = try fixture.stage(text: "Ready", count: 1)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .complete)
        #expect(model.canPublish)

        let lockURL = fixture.directory.appendingPathComponent("staging/.index.lock")
        let descriptor = Darwin.open(lockURL.path, O_RDWR)
        try #require(descriptor >= 0)
        defer { Darwin.close(descriptor) }
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        // Rendering reads the snapshot and never touches the cross-process lock.
        #expect(model.canPublish && !model.hasPendingSharedMedia)
        // A peer releasing within the retry window is waited for, not reported as a failure.
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(50)) { flock(descriptor, LOCK_UN) }
        #expect(try fixture.store.pendingSharedStagingItemsForPublishing().isEmpty)
    }

    @Test func aSharedBatchReservesEveryTileUpFrontAndKeepsLocalPreviews() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        var tileCountsAtUpload: [Int] = []
        var uploads = 0
        api.uploadMediaHandler = { _, _, _ in
            tileCountsAtUpload.append(model.mediaAttachments.count)
            uploads += 1
            return Self.serverAttachment("upload-\(uploads)")
        }
        let item = try fixture.stage(text: "Four at once", count: 4)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .complete)
        #expect(tileCountsAtUpload == [4, 4, 4, 4], "The grid must not reflow after each upload")
        #expect(model.mediaAttachments.map(\.id) == ["upload-1", "upload-2", "upload-3", "upload-4"])
        #expect(model.mediaAttachments.allSatisfy { $0.previewImage != nil }, "Uploaded tiles keep their local preview")
    }

    @Test func cancellingMidBatchLeavesNoEndlessSpinners() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        api.uploadMediaHandler = { _, _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return Self.serverAttachment("uploaded")
        }
        let item = try fixture.stage(text: "Interrupted", count: 4)
        let operation = Task { await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) }
        #expect(await operation.value == .partial)
        #expect(model.mediaAttachments.map(\.id) == ["uploaded"])
        #expect(!model.hasUploadingMedia)
        #expect(try #require(fixture.store.pendingSharedStagingItems().first).attachments.count == 3,
            "Unstarted files stay staged for the resume")
    }

    @Test func aShareCancelledInTheExtensionAfterMoroReadItLeavesNothingBehind() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        model.content = "Existing text"
        let item = try fixture.stage(text: "Cancelled share", count: 2)
        #expect(fixture.store.removePendingSharedStagingItem(id: item.id))
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .withdrawn)
        #expect(model.content == "Existing text" && model.mediaAttachments.isEmpty)
        #expect(model.sharedImportFailureMessage == nil)
        #expect(api.publishIdempotencyKeys.isEmpty)
    }

    @Test func aShareWithdrawnMidBatchKeepsOnlyWhatAlreadyUploaded() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        let item = try fixture.stage(text: "Withdrawn later", count: 3)
        api.uploadMediaHandler = { _, _, _ in
            _ = fixture.store.removePendingSharedStagingItem(id: item.id)
            return Self.serverAttachment("uploaded")
        }
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .withdrawn)
        #expect(model.mediaAttachments.map(\.id) == ["uploaded"])
        #expect(!model.hasUploadingMedia && !model.hasFailedMedia && model.sharedImportFailureMessage == nil)
        #expect(model.canPublish)
    }

    @Test func anInstanceThatAllowsMoreAttachmentsTakesASecondFullBatch() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        api.instanceMetadataCacheKey = "test://\(UUID().uuidString)"
        api.fetchInstanceV2Handler = { Self.instance(maxMediaAttachments: 8) }
        var uploads = 0
        api.uploadMediaHandler = { _, _, _ in
            uploads += 1
            return Self.serverAttachment("upload-\(uploads)")
        }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        model.mediaAttachments = (1...4).map { Self.serverMedia("existing-\($0)") }
        let item = try fixture.stage(text: "Four more", count: 4)
        // The share arrives before the editor's limits task ran: the import must load them itself.
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .complete)
        #expect(model.maxMediaAttachments == 8 && model.mediaAttachments.count == 8)
        #expect(model.remainingMediaAttachmentSlots == 0 && model.canPublish)
    }

    @Test func onAStandardInstanceAnOverflowingShareWaitsAndOpensAfterPublishingTheCurrentPost() async throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let api = MockMastodonAPI()
        api.instanceMetadataCacheKey = "test://\(UUID().uuidString)"
        api.fetchInstanceV2Handler = { Self.instance(maxMediaAttachments: 4) }
        let model = ComposeViewModel(context: .newPost, apiClient: api, currentUserID: "me")
        model.content = "Current post"
        model.mediaAttachments = (1...4).map { Self.serverMedia("existing-\($0)") }
        #expect(fixture.store.save(model.makeDraft(category: .auto)))
        let item = try fixture.stage(text: "Four more", count: 4)
        #expect(await model.importSharedAttachments(from: Self.importPayload(item), draftStore: fixture.store) == .blocked)
        #expect(model.sharedImportFailureMessage == MoroL10n.ShareImport.mediaLimit(4))
        #expect(model.mediaAttachments.count == 4 && model.content == "Current post", "Nothing is truncated or overwritten")
        // The current post stays publishable; the waiting share is not part of it.
        #expect(model.canPublish && !model.hasPendingSharedMedia)
        // Once that editor closes (published or discarded), the root opens the share in a new post.
        let resolution = try #require(SharedComposeImportCoordinator(draftStore: fixture.store)
            .consumeNextImportableDraft(activeAccountID: "me"))
        #expect(resolution.sharedImport?.stagingItemID == item.id)
        #expect(resolution.sharedImport?.attachments.count == 4)
    }

    @Test func instanceAttachmentLimitIsSanitized() {
        #expect(ComposeMediaSelectionPolicy.attachmentLimit(reportedByInstance: nil) == 4)
        #expect(ComposeMediaSelectionPolicy.attachmentLimit(reportedByInstance: 0) == 4)
        #expect(ComposeMediaSelectionPolicy.attachmentLimit(reportedByInstance: 8) == 8)
        #expect(ComposeMediaSelectionPolicy.attachmentLimit(reportedByInstance: 500) == 20)
        #expect(ComposeMediaSelectionPolicy.remainingSlots(existingCount: 4, limit: 8) == 4)
    }

    private static func instance(maxMediaAttachments: Int) -> MastodonInstanceV2 {
        MastodonInstanceV2(
            domain: "x", title: "X", description: nil, thumbnail: nil, contact: nil,
            registrations: nil, rules: nil, languages: nil,
            configuration: InstanceConfiguration(statuses: .init(maxCharacters: 500, maxMediaAttachments: maxMediaAttachments)))
    }

    @Test func launchSweepRemovesOnlyWhatNothingWillEverImport() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let staging = fixture.directory.appendingPathComponent("staging")
        let now = Date()
        let old = now.addingTimeInterval(-8 * 24 * 3600)
        func stage(at date: Date) throws -> SharedComposeDraftStagingItem {
            let source = fixture.directory.appendingPathComponent("sweep-source.png")
            try Data([1]).write(to: source)
            return try fixture.store.stageSharedDraft(accountID: "me", target: .init(kind: .newPost),
                payload: Self.payload("Sweep"), attachments: [.init(sourceURL: source, mimeType: "image/png", id: "a")],
                now: date)
        }
        let forgotten = try stage(at: old)          // unclaimed for over a week
        let claimed = try stage(at: old)            // just as old, but a draft owns it
        let recent = try stage(at: now)             // unclaimed but new
        #expect(fixture.store.save(claimed.asImportRecoveryDraft(accountID: "me")))

        // Left behind without an index entry: an interrupted stage and a stray cancel marker.
        let orphan = staging.appendingPathComponent(UUID().uuidString)
        let fresh = staging.appendingPathComponent(UUID().uuidString)
        let marker = staging.appendingPathComponent(SharedComposeDraftStagingStore.cancelledMarkerPrefix + UUID().uuidString)
        for directory in [orphan, fresh] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        #expect(FileManager.default.createFile(atPath: marker.path, contents: Data()))
        let stale = [FileAttributeKey.modificationDate: now.addingTimeInterval(-2 * 3600)]
        try FileManager.default.setAttributes(stale, ofItemAtPath: orphan.path)
        try FileManager.default.setAttributes(stale, ofItemAtPath: marker.path)

        #expect(fixture.store.sweepSharedStaging(now: now) == 2)
        #expect(Set(fixture.store.pendingSharedStagingItems().map(\.id)) == [claimed.id, recent.id])
        func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
        #expect(!exists(staging.appendingPathComponent(forgotten.id)) && !exists(orphan) && !exists(marker))
        #expect(exists(staging.appendingPathComponent(claimed.id)) && exists(staging.appendingPathComponent(recent.id)))
        #expect(exists(fresh), "A share being staged right now is never touched")
        #expect(fixture.store.sweepSharedStaging(now: now) == 0)
    }

    @Test func aShareCancelledWhileTheIndexIsBusyNeverReachesTheEditor() throws {
        let fixture = try StoreFixture()
        defer { fixture.cleanup() }
        let item = try fixture.stage(text: "Cancelled in the share sheet", count: 1)
        let staging = fixture.directory.appendingPathComponent("staging")
        let extensionStore = MoroShareExtensionDraftStagingStore(
            userDefaults: try #require(UserDefaults(suiteName: fixture.suites[1])), baseDirectoryURL: staging)
        let descriptor = Darwin.open(staging.appendingPathComponent(".index.lock").path, O_RDWR)
        try #require(descriptor >= 0)
        try #require(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        do {
            try extensionStore.remove(itemID: item.id)
            Issue.record("A held lock must make the index update fail")
        } catch {}
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)

        #expect(fixture.store.pendingSharedStagingItems().isEmpty, "The tombstone hides the cancelled share")
        #expect(try fixture.store.pendingSharedStagingItemsForPublishing().isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: staging.path)
        #expect(leftovers == [".index.lock"], "Index entry, files and tombstone are purged: \(leftovers)")
    }

    private static func serverAttachment(_ id: String) -> Status.Attachment {
        .init(id: id, type: "image", url: URL(string: "https://fixture.invalid/\(id).png")!)
    }
    private static func serverMedia(_ id: String) -> MediaAttachment {
        .init(id: id, url: URL(string: "https://fixture.invalid/\(id).png")!, previewURL: nil,
            type: "image", description: nil, focus: nil, uploadState: .uploaded)
    }
    private static func importPayload(_ item: SharedComposeDraftStagingItem) -> SharedComposeAttachmentImportPayload {
        .init(stagingItemID: item.id, sourceApplication: item.sourceApplication,
            attachments: item.attachments, text: item.payload.content)
    }
    private static func payload(_ text: String) -> ComposeDraftPayload {
        .init(content: text, contentWarning: "", isContentWarningActive: false, visibility: .public,
            mediaAttachments: [], isPollActive: false, pollOptions: ["", ""], pollMultiple: false,
            pollExpiresIn: 86400, isSchedulingEnabled: false, scheduledAt: nil,
            selectedLanguageCode: "", quotePolicyRawValue: ComposeViewModel.QuotePolicy.anyone.rawValue)
    }
    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(condition())
    }

    @MainActor
    private struct StoreFixture {
        let store: ComposeDraftStore
        let directory: URL
        let suites: [String]
        init() throws {
            suites = ["share-drafts-\(UUID())", "share-staging-\(UUID())"]
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("share-test-\(UUID())")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            store = ComposeDraftStore(userDefaults: try #require(UserDefaults(suiteName: suites[0])),
                stagingStore: SharedComposeDraftStagingStore(userDefaults: try #require(UserDefaults(suiteName: suites[1])),
                    baseDirectoryURL: directory.appendingPathComponent("staging")))
        }
        func stage(text: String, count: Int) throws -> SharedComposeDraftStagingItem {
            let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
                UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }
            let source = directory.appendingPathComponent("source.png")
            try #require(image.pngData()).write(to: source)
            return try store.stageSharedDraft(accountID: "me", target: .init(kind: .newPost), payload: SharedComposeHandoffTests.payload(text),
                attachments: (0..<count).map { .init(sourceURL: source, mimeType: "image/png", id: "source-\($0)") })
        }
        func cleanup() {
            for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
