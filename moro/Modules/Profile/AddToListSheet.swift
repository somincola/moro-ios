//
//  AddToListSheet.swift
//  moro
//
//  Lets the user add/remove an account to/from their lists from the profile
//  more menu. Shows every list with a checkmark for the ones already
//  containing the account; tapping a row toggles membership.
//

import SwiftUI

struct AddToListSheet: View {
    let account: Account
    let apiClient: MastodonAPI

    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme

    private enum LoadState {
        case loading
        case loaded
        case empty
        case failed
    }

    @State private var lists: [MastodonList] = []
    @State private var memberListIDs: Set<String> = []
    @State private var mutatingIDs: Set<String> = []
    @State private var loadState: LoadState = .loading
    @State private var showCreateList = false
    @State private var newListTitle = ""
    @State private var isCreatingList = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(MoroL10n.AddToList.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(theme.colors.background, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            newListTitle = ""
                            showCreateList = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .disabled(isCreatingList)
                        .accessibilityLabel(MoroL10n.Lists.newList)
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        MoroToolbarButton(MoroL10n.Common.done, kind: .confirm) { dismiss() }
                    }
                }
        }
        .task { await load() }
        .alert(MoroL10n.Lists.newList, isPresented: $showCreateList) {
            TextField(MoroL10n.Lists.formNamePlaceholder, text: $newListTitle)
            Button(MoroL10n.Common.cancel, role: .cancel) {}
            Button(MoroL10n.Lists.formCreate) {
                Task { await createListAndAddAccount() }
            }
            .disabled(newListTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            centeredMessage { ProgressView() }
        case .failed:
            centeredMessage {
                VStack(spacing: theme.spacing.s) {
                    Text(MoroL10n.AddToList.loadFailed)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                    Button(MoroL10n.AddToList.retry) {
                        Task { await load() }
                    }
                    .font(theme.typography.bodyStrong)
                    .foregroundStyle(theme.colors.primary500)
                }
            }
        case .empty:
            centeredMessage {
                VStack(spacing: theme.spacing.m) {
                    Image(systemName: "list.bullet.rectangle")
                        .moroScaledFont(size: 30, weight: .regular)
                        .foregroundStyle(theme.colors.textTertiary)
                    Text(MoroL10n.AddToList.empty)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                        .multilineTextAlignment(.center)
                    Button(MoroL10n.Lists.newList) {
                        newListTitle = ""
                        showCreateList = true
                    }
                    .font(theme.typography.bodyStrong)
                    .foregroundStyle(theme.colors.textPrimary)
                }
                .padding(.horizontal, theme.spacing.xl)
            }
        case .loaded:
            List {
                ForEach(lists) { list in
                    listRow(list)
                        .listRowBackground(theme.colors.background)
                        .listRowSeparatorTint(theme.colors.borderSubtle)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.colors.background)
        }
    }

    private func listRow(_ list: MastodonList) -> some View {
        let isMember = memberListIDs.contains(list.id)
        let isMutating = mutatingIDs.contains(list.id)

        return Button {
            Task { await toggle(list) }
        } label: {
            HStack(spacing: theme.spacing.m) {
                Image(systemName: "list.bullet.rectangle")
                    .moroScaledFont(size: 16, weight: .regular)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: 24)

                Text(list.title)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)

                Spacer()

                if isMutating {
                    ProgressView().controlSize(.small)
                } else if isMember {
                    Image(systemName: "checkmark")
                        .moroScaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(theme.colors.primary500)
                }
            }
            .padding(.vertical, theme.spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isMutating)
        .accessibilityLabel(list.title)
        .accessibilityValue(
            isMember ? MoroL10n.AddToList.inList : MoroL10n.AddToList.notInList)
    }

    @ViewBuilder
    private func centeredMessage<Inner: View>(@ViewBuilder _ inner: () -> Inner) -> some View {
        VStack {
            Spacer()
            inner()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.colors.background)
    }

    // MARK: - Data

    private func load() async {
        loadState = .loading
        do {
            async let allLists = apiClient.fetchLists()
            async let memberLists = apiClient.fetchAccountLists(accountID: account.id)
            let (all, member) = try await (allLists, memberLists)
            lists = all
            memberListIDs = Set(member.map(\.id))
            loadState = all.isEmpty ? .empty : .loaded
        } catch {
            loadState = .failed
        }
    }

    private func toggle(_ list: MastodonList) async {
        guard !mutatingIDs.contains(list.id) else { return }
        mutatingIDs.insert(list.id)
        defer { mutatingIDs.remove(list.id) }

        let isMember = memberListIDs.contains(list.id)
        do {
            if isMember {
                try await apiClient.removeAccountsFromList(
                    listID: list.id, accountIDs: [account.id])
                memberListIDs.remove(list.id)
            } else {
                try await apiClient.addAccountsToList(listID: list.id, accountIDs: [account.id])
                memberListIDs.insert(list.id)
            }
        } catch {
            AppFeedbackCenter.shared.showError(
                isMember ? MoroL10n.AddToList.removeFailed : MoroL10n.AddToList.addFailed)
        }
    }

    private func createListAndAddAccount() async {
        let title = newListTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !isCreatingList else { return }

        isCreatingList = true
        defer { isCreatingList = false }

        do {
            let created = try await apiClient.createList(title: title, repliesPolicy: nil)
            lists.insert(created, at: 0)
            loadState = .loaded

            do {
                try await apiClient.addAccountsToList(
                    listID: created.id,
                    accountIDs: [account.id]
                )
                memberListIDs.insert(created.id)
                AppFeedbackCenter.shared.showSuccess(MoroL10n.ListsVM.created)
            } catch {
                AppFeedbackCenter.shared.showError(MoroL10n.AddToList.addFailed)
            }
        } catch {
            AppFeedbackCenter.shared.showError(MoroL10n.ListsVM.createFailedShort)
        }
    }
}
