//
//  FiltersSettingsView.swift
//  moro
//
//  Server-side content filters and domain-block management page.
//

import SwiftUI

struct FiltersSettingsView: View {
    @Environment(\.moroTheme) private var theme
    @StateObject private var viewModel: FiltersSettingsViewModel

    @State private var showEditor = false
    @State private var editorDraft = FilterEditorDraft.new
    @State private var isSavingEditor = false
    @State private var showDomainBlockPrompt = false
    @State private var domainInput = ""

    init(apiClient: MastodonAPI) {
        _viewModel = StateObject(wrappedValue: FiltersSettingsViewModel(apiClient: apiClient))
    }

    var body: some View {
        MoroSettingsList {
            if let transientErrorMessage = viewModel.transientErrorMessage {
                Section {
                    HStack(alignment: .top, spacing: theme.spacing.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(theme.colors.error)
                            .padding(.top, 2)
                        Text(transientErrorMessage)
                            .font(theme.typography.caption)
                            .foregroundStyle(theme.colors.textPrimary)
                    }
                    .padding(.vertical, theme.spacing.xs)
                }
            }

            filterSection
            domainBlockSection
        }
        .moroSettingsSwitchStyle()
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Filters.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorDraft = .new
                    showEditor = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(MoroL10n.Filters.newFilter)
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .task {
            await viewModel.loadInitial()
        }
        .sheet(isPresented: $showEditor) {
            FilterEditorSheet(
                draft: $editorDraft,
                isSaving: isSavingEditor,
                onCancel: {
                    showEditor = false
                },
                onSave: {
                    await saveEditor()
                },
                onUpsertKeyword: upsertKeywordHandler,
                onDeleteKeyword: deleteKeywordHandler
            )
        }
        .alert(MoroL10n.Filters.domainBlockTitle, isPresented: $showDomainBlockPrompt) {
            TextField("example.social", text: $domainInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button(MoroL10n.Common.cancel, role: .cancel) {
                domainInput = ""
            }
            Button(MoroL10n.Filters.domainBlockAction) {
                Task {
                    let success = await viewModel.blockDomain(domainInput)
                    if success {
                        domainInput = ""
                    }
                }
            }
        } message: {
            Text(MoroL10n.Filters.domainBlockMessage)
        }
    }

    @ViewBuilder
    private var filterSection: some View {
        if viewModel.filters.isEmpty && isLoadingState {
            Section {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, theme.spacing.m)
            }
        } else if viewModel.filters.isEmpty, case .error(let error) = viewModel.loadingState {
            Section {
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    Text(MoroL10n.Filters.loadFailed)
                        .font(theme.typography.body)
                        .fontWeight(.semibold)
                    Text(error.localizedDescription)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Text(MoroL10n.Filters.retry)
                            .font(theme.typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.colors.primaryForeground)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(theme.colors.primary500))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, theme.spacing.xs)
            }
        } else if viewModel.filters.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: theme.spacing.s) {
                    Text(MoroL10n.Filters.emptyTitle)
                        .font(theme.typography.body)
                        .fontWeight(.semibold)
                    Text(MoroL10n.Filters.emptyMessage)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    Button {
                        editorDraft = .new
                        showEditor = true
                    } label: {
                        Text(MoroL10n.Filters.newFilter)
                            .font(theme.typography.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.colors.primaryForeground)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(theme.colors.primary500))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, theme.spacing.xs)
            }
        } else {
            Section {
                ForEach(viewModel.filters) { filter in
                    FilterRow(filter: filter) {
                        editorDraft = .from(filter)
                        showEditor = true
                    }
                    .accessibilityIdentifier("filters.rule.\(filter.id)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task {
                                await viewModel.deleteFilter(filter)
                            }
                        } label: {
                            Label {
                                Text(MoroL10n.Filters.delete)
                            } icon: {
                                MoroMenuGlyph(systemImage: "trash", tintColor: .white)
                            }
                            .labelStyle(.titleAndIcon)
                        }
                        .tint(theme.colors.error)
                        .accessibilityIdentifier("filters.delete.\(filter.id)")
                    }
                }
            } header: {
                MoroSettingsSectionHeader(title: MoroL10n.Filters.sectionRules)
            } footer: {
                Text(MoroL10n.Filters.sectionRulesFooter)
            }
        }
    }

    @ViewBuilder
    private var domainBlockSection: some View {
        Section {
            if isLoadingState && viewModel.domainBlocks.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if viewModel.domainBlocks.isEmpty {
                Text(MoroL10n.Filters.domainBlockEmpty)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                ForEach(viewModel.domainBlocks, id: \.self) { domain in
                    HStack {
                        Text(domain)
                            .font(theme.typography.body)
                            .foregroundStyle(theme.colors.textPrimary)
                            .accessibilityIdentifier("filters.domain.\(domain)")
                        Spacer()
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task { await viewModel.unblockDomain(domain) }
                        } label: {
                            Label {
                                Text(MoroL10n.Filters.domainBlockUnblock)
                            } icon: {
                                MoroMenuGlyph(systemImage: "trash", tintColor: .white)
                            }
                            .labelStyle(.titleAndIcon)
                        }
                        .tint(theme.colors.error)
                        .accessibilityIdentifier("filters.unblock.\(domain)")
                    }
                }
            }

            Button {
                showDomainBlockPrompt = true
            } label: {
                Label(MoroL10n.Filters.domainBlockAddLabel, systemImage: "globe.badge.chevron.backward")
            }
        } header: {
            MoroSettingsSectionHeader(title: MoroL10n.Filters.sectionDomains)
        } footer: {
            Text(MoroL10n.Filters.sectionDomainsFooter)
        }
    }

    private var isLoadingState: Bool {
        if case .idle = viewModel.loadingState {
            return true
        }
        if case .loading = viewModel.loadingState {
            return true
        }
        return false
    }

    private var upsertKeywordHandler: ((String?, String, Bool) async -> ServerFilter.Keyword?)? {
        guard editorDraft.filterID != nil else { return nil }
        return { keywordID, keyword, wholeWord in
            await upsertKeyword(keywordID: keywordID, keyword: keyword, wholeWord: wholeWord)
        }
    }

    private var deleteKeywordHandler: ((ServerFilter.Keyword) async -> Bool)? {
        guard editorDraft.filterID != nil else { return nil }
        return { keyword in
            await deleteKeyword(keyword)
        }
    }

    private func saveEditor() async {
        guard !isSavingEditor else { return }
        isSavingEditor = true

        let contexts = Array(editorDraft.contexts)
        let title = editorDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)

        var success = false
        if let editingID = editorDraft.filterID {
            success = await viewModel.updateFilter(
                id: editingID,
                title: title,
                contexts: contexts,
                action: editorDraft.action
            )
        } else {
            let keyword = editorDraft.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            success = await viewModel.createFilter(
                title: title,
                keyword: keyword,
                contexts: contexts,
                action: editorDraft.action
            )
        }

        isSavingEditor = false
        if success {
            showEditor = false
        }
    }

    private func upsertKeyword(
        keywordID: String?,
        keyword: String,
        wholeWord: Bool
    ) async -> ServerFilter.Keyword? {
        guard let filterID = editorDraft.filterID else { return nil }

        if let keywordID {
            if let updated = await viewModel.updateKeyword(
                filterID: filterID,
                keywordID: keywordID,
                keyword: keyword,
                wholeWord: wholeWord
            ) {
                if let index = editorDraft.existingKeywords.firstIndex(where: { $0.id == updated.id }) {
                    editorDraft.existingKeywords[index] = updated
                }
                return updated
            }
            return nil
        }

        if let created = await viewModel.addKeyword(
            filterID: filterID,
            keyword: keyword,
            wholeWord: wholeWord
        ) {
            editorDraft.existingKeywords.append(created)
            return created
        }
        return nil
    }

    private func deleteKeyword(_ keyword: ServerFilter.Keyword) async -> Bool {
        guard let filterID = editorDraft.filterID else { return false }
        let success = await viewModel.deleteKeyword(
            filterID: filterID,
            keywordID: keyword.id
        )
        if success {
            editorDraft.existingKeywords.removeAll { $0.id == keyword.id }
        }
        return success
    }
}

private struct FilterRow: View {
    @Environment(\.moroTheme) private var theme

    let filter: ServerFilter
    let onTapEdit: () -> Void

    var body: some View {
        Button(action: onTapEdit) {
            VStack(alignment: .leading, spacing: theme.spacing.xs) {
                HStack {
                    Text(filter.title)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textPrimary)
                    Spacer()
                    Text(filter.filterAction.localizedTitle)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                }

                Text(filter.context.filter { $0 != .unknown }.map(\.localizedTitle).joined(separator: " · "))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)

                if !filter.keywords.isEmpty {
                    Text(MoroL10n.Filters.keywords(filter.keywords.map(\.keyword).joined(separator: "、")))
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.vertical, theme.spacing.xs)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct FilterEditorDraft {
    let filterID: String?
    var title: String
    var keyword: String
    var contexts: Set<ServerFilter.Context>
    var action: ServerFilter.Action
    var existingKeywords: [ServerFilter.Keyword]

    static let supportedContexts: [ServerFilter.Context] = [
        .home, .notifications, .public, .thread, .account,
    ]

    static let new = FilterEditorDraft(
        filterID: nil,
        title: "",
        keyword: "",
        contexts: [.home],
        action: .warn,
        existingKeywords: []
    )

    static func from(_ filter: ServerFilter) -> FilterEditorDraft {
        let contexts = Set(filter.context.filter { $0 != .unknown })
        return FilterEditorDraft(
            filterID: filter.id,
            title: filter.title,
            keyword: "",
            contexts: contexts.isEmpty ? [.home] : contexts,
            action: filter.filterAction == .unknown ? .warn : filter.filterAction,
            existingKeywords: filter.keywords
        )
    }

    var isEditing: Bool {
        filterID != nil
    }

    var canSave: Bool {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanTitle.isEmpty || contexts.isEmpty {
            return false
        }
        if isEditing {
            return true
        }
        return !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct FilterEditorSheet: View {
    @Environment(\.moroTheme) private var theme
    @Binding var draft: FilterEditorDraft

    let isSaving: Bool
    let onCancel: () -> Void
    let onSave: () async -> Void
    let onUpsertKeyword: ((String?, String, Bool) async -> ServerFilter.Keyword?)?
    let onDeleteKeyword: ((ServerFilter.Keyword) async -> Bool)?

    @State private var keywordInput = ""
    @State private var keywordWholeWord = true
    @State private var editingKeywordID: String?
    @State private var isKeywordSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section(moroHeader: MoroL10n.Filters.formTitleSection) {
                    TextField(MoroL10n.Filters.formTitlePlaceholder, text: $draft.title)
                }
                .listRowBackground(theme.colors.groupedSurface)

                if draft.isEditing {
                    keywordEditingSection
                        .listRowBackground(theme.colors.groupedSurface)
                } else {
                    Section(moroHeader: MoroL10n.Filters.formKeywordsSection) {
                        TextField(MoroL10n.Filters.formKeywordPlaceholder, text: $draft.keyword)
                    }
                    .listRowBackground(theme.colors.groupedSurface)
                }

                Section(moroHeader: MoroL10n.Filters.formActionSection) {
                    Picker(MoroL10n.Filters.formActionLabel, selection: $draft.action) {
                        Text(ServerFilter.Action.warn.localizedTitle).tag(ServerFilter.Action.warn)
                        Text(ServerFilter.Action.hide.localizedTitle).tag(ServerFilter.Action.hide)
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(theme.colors.groupedSurface)

                Section(moroHeader: MoroL10n.Filters.formScopeSection) {
                    ForEach(FilterEditorDraft.supportedContexts, id: \.self) { context in
                        Toggle(
                            context.localizedTitle,
                            isOn: Binding(
                                get: { draft.contexts.contains(context) },
                                set: { enabled in
                                    if enabled {
                                        draft.contexts.insert(context)
                                    } else {
                                        draft.contexts.remove(context)
                                    }
                                }
                            )
                        )
                    }
                }
                .listRowBackground(theme.colors.groupedSurface)
            }
            .moroSettingsSwitchStyle()
            .moroSettingsListChrome()
            .tint(theme.colors.primary500)
            .navigationTitle(draft.isEditing ? MoroL10n.Filters.formEditTitle : MoroL10n.Filters.newFilter)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(MoroL10n.Filters.formCancel) {
                        onCancel()
                    }
                    .disabled(isSaving || isKeywordSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(draft.isEditing ? MoroL10n.Filters.formSave : MoroL10n.Filters.formCreate) {
                        Task { await onSave() }
                    }
                    .disabled(isSaving || !draft.canSave || isKeywordSaving)
                }
            }
            .overlay {
                if isSaving {
                    ZStack {
                        theme.colors.textPrimary.opacity(0.12).ignoresSafeArea()
                        ProgressView()
                            .padding(20)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var keywordEditingSection: some View {
        Section {
            if draft.existingKeywords.isEmpty {
                Text(MoroL10n.Filters.formNoKeywords)
                    .foregroundStyle(theme.colors.textSecondary)
            } else {
                ForEach(draft.existingKeywords) { keyword in
                    Button {
                        editingKeywordID = keyword.id
                        keywordInput = keyword.keyword
                        keywordWholeWord = keyword.wholeWord
                    } label: {
                        HStack {
                            Text(keyword.keyword)
                                .foregroundStyle(theme.colors.textPrimary)
                            Spacer()
                            if keyword.wholeWord {
                                Text(MoroL10n.Filters.formWholeWord)
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            if editingKeywordID == keyword.id {
                                Image(systemName: "pencil.circle.fill")
                                    .foregroundStyle(theme.colors.primary500)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            Task { await deleteKeyword(keyword) }
                        } label: {
                            Label {
                                Text(MoroL10n.Filters.delete)
                            } icon: {
                                MoroMenuGlyph(systemImage: "trash", tintColor: .white)
                            }
                            .labelStyle(.titleAndIcon)
                        }
                        .tint(theme.colors.error)
                    }
                }
            }

            TextField(MoroL10n.Filters.formNewKeywordPlaceholder, text: $keywordInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Toggle(MoroL10n.Filters.formMatchWholeWord, isOn: $keywordWholeWord)

            Button(editingKeywordID == nil ? MoroL10n.Filters.formAddKeyword : MoroL10n.Filters.formUpdateKeyword) {
                Task { await upsertKeyword() }
            }
            .disabled(keywordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isKeywordSaving)

            if editingKeywordID != nil {
                Button(MoroL10n.Filters.formCancelEditKeyword) {
                    resetKeywordEditor()
                }
                .font(theme.typography.caption)
            }
        } header: {
            MoroSettingsSectionHeader(title: MoroL10n.Filters.formKeywordsSectionHeader)
        } footer: {
            Text(MoroL10n.Filters.formKeywordsFooter)
        }
    }

    private func upsertKeyword() async {
        guard !isKeywordSaving else { return }
        guard let onUpsertKeyword else { return }

        let trimmed = keywordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isKeywordSaving = true
        defer { isKeywordSaving = false }

        let result = await onUpsertKeyword(editingKeywordID, trimmed, keywordWholeWord)
        if result != nil {
            resetKeywordEditor()
        }
    }

    private func deleteKeyword(_ keyword: ServerFilter.Keyword) async {
        guard let onDeleteKeyword else { return }
        guard !isKeywordSaving else { return }

        isKeywordSaving = true
        defer { isKeywordSaving = false }

        let success = await onDeleteKeyword(keyword)
        if success, editingKeywordID == keyword.id {
            resetKeywordEditor()
        }
    }

    private func resetKeywordEditor() {
        editingKeywordID = nil
        keywordInput = ""
        keywordWholeWord = true
    }
}
