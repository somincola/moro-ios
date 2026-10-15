//
//  EditProfileDraftTests.swift
//  moroTests
//

import Foundation
import Testing

@testable import moro

extension moroTests {
    @Test @MainActor func editProfileIgnoresABlankRowAndDropsItOnSave() async throws {
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = {
            EditableProfile(id: "account", displayName: "", note: "",
                fields: [AccountField(name: "Website", value: "https://moro.example")])
        }
        api.updateAccountProfileHandler = { _, _, _, _, _, _, fields in self.makeAccount(fields: fields ?? []) }
        api.verifyCredentialsHandler = { self.makeAccount() }
        let model = EditProfileViewModel(apiClient: api, initialAccount: makeAccount())
        await model.load()
        let appState = AppState()
        defer { AppFeedbackCenter.shared.dismiss() }

        let blank = try #require(model.addField())
        #expect(!model.hasUnsavedChanges)
        #expect(!model.invalidFieldIDs.contains(blank))

        model.fields[0].value = "https://moro.example/new"
        #expect(model.canSave)
        #expect(await model.save(to: appState))
        let submitted = try #require(api.updateAccountProfileCalls.first?.fields)
        #expect(submitted.map(\.name) == ["Website"])
        #expect(model.fields.count == 1)
    }

    @Test @MainActor func editProfileRevertsStagedImagesToTheServerCopy() async {
        let account = makeAccount(
            avatar: "https://cdn.example.com/avatar.png", avatarStatic: "https://cdn.example.com/avatar.png",
            header: "https://cdn.example.com/header.png", headerStatic: "https://cdn.example.com/header.png")
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = { EditableProfile(id: "account", displayName: "", note: "", fields: []) }
        let model = EditProfileViewModel(apiClient: api, initialAccount: account)
        await model.load()

        model.markAvatarRemoved()
        model.markHeaderRemoved()
        #expect(model.hasPendingAvatarChange && model.hasPendingHeaderChange)
        #expect(!model.canRemoveAvatar && !model.canRemoveHeader)

        model.revertAvatar()
        #expect(!model.hasPendingAvatarChange)
        #expect(model.canRemoveAvatar)
        #expect(model.hasUnsavedChanges, "The header removal is still staged")
        model.revertHeader()
        #expect(!model.hasUnsavedChanges)
    }

    @Test @MainActor func editProfileMovesAFieldOneStepAndStopsAtTheEnds() async {
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = {
            EditableProfile(id: "account", displayName: "", note: "", fields: [
                AccountField(name: "A", value: "1"), AccountField(name: "B", value: "2"),
                AccountField(name: "C", value: "3"),
            ])
        }
        let model = EditProfileViewModel(apiClient: api, initialAccount: makeAccount())
        await model.load()
        let first = model.fields[0].id

        model.moveField(id: first, by: -1)
        #expect(model.fields.map(\.name) == ["A", "B", "C"])
        model.moveField(id: first, by: 1)
        #expect(model.fields.map(\.name) == ["B", "A", "C"])
        #expect(model.hasUnsavedChanges)
        model.moveField(id: first, by: -1)
        #expect(!model.hasUnsavedChanges)
    }

    @Test @MainActor func editProfileOnlyFlagsEditedFieldTextOverTheLimit() async throws {
        let long = String(repeating: "x", count: 300)
        let api = MockMastodonAPI()
        api.fetchEditableProfileHandler = {
            EditableProfile(id: "account", displayName: "", note: "", fields: [AccountField(name: "Site", value: long)])
        }
        let model = EditProfileViewModel(apiClient: api, initialAccount: makeAccount())
        await model.load()
        let id = model.fields[0].id
        #expect(model.limits.fieldValueLength < long.count)
        #expect(model.overLimitFieldIDs.isEmpty, "Accepted text stays valid under a lower limit")

        model.fields[0].name = "Website"
        #expect(model.overLimitFieldIDs.isEmpty)
        model.fields[0].value = long + "y"
        #expect(model.overLimitFieldIDs == [id])
    }
}
