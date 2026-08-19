//
//  ComposeContextWrapper.swift
//  moro
//
//  Wrapper to make ComposeContext identifiable for sheet presentation.
//

import Foundation

struct ComposeContextWrapper: Identifiable {
    let id = UUID()
    let context: ComposeViewModel.ComposeContext
    let draft: ComposeDraft?
    let sharedImport: SharedComposeAttachmentImportPayload?

    init(
        context: ComposeViewModel.ComposeContext,
        draft: ComposeDraft? = nil,
        sharedImport: SharedComposeAttachmentImportPayload? = nil
    ) {
        self.context = context
        self.draft = draft
        self.sharedImport = sharedImport
    }
}
