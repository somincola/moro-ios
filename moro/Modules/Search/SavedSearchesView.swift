import SwiftUI

struct SavedSearchesRouteView: View {
    @Environment(\.activeAccountKey) private var accountKey

    var body: some View {
        SavedSearchesView(accountKey: accountKey).id(accountKey)
    }
}

struct SavedSearchesView: View {
    @Environment(\.moroTheme) private var theme
    @Environment(\.appRouter) private var router
    @StateObject private var library: SearchLibraryStore
    @State private var editingItem: SearchLibraryItem?

    init(accountKey: String, defaults: UserDefaults = .standard) {
        _library = StateObject(wrappedValue: SearchLibraryStore(accountKey: accountKey, defaults: defaults))
    }

    var body: some View {
        MoroSettingsList {
            Section {
                if library.saved.isEmpty {
                    Text(MoroL10n.Search.noSaved)
                        .foregroundStyle(theme.colors.textSecondary)
                        .padding(.vertical, theme.spacing.m)
                }
                ForEach(library.saved) { item in
                    HStack {
                        Button {
                            router.navigate(to: .search(query: item.query, scope: item.scope.rawValue))
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title).foregroundStyle(theme.colors.textPrimary)
                                Text(item.name.isEmpty ? item.scope.title : "\(item.query) · \(item.scope.title)")
                                    .font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button { editingItem = item } label: {
                            Image(systemName: "pencil")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(MoroL10n.Search.renameSearch)
                    }
                    .swipeActions {
                        Button(MoroL10n.Common.delete, role: .destructive) {
                            library.removeSaved(id: item.id)
                        }
                    }
                }
            } footer: {
                Text(MoroL10n.Search.localSearches)
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.Search.savedTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { library.reload() }
        .sheet(item: $editingItem) { item in
            SavedSearchNameSheet(item: item, library: library)
                .presentationDetents([.medium])
        }
    }
}

private struct SavedSearchNameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme
    let item: SearchLibraryItem
    @ObservedObject var library: SearchLibraryStore
    @State private var name: String
    @FocusState private var isFocused: Bool

    init(item: SearchLibraryItem, library: SearchLibraryStore) {
        self.item = item
        self.library = library
        _name = State(initialValue: item.title)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(MoroL10n.Search.searchName, text: $name)
                    .focused($isFocused)
                    .submitLabel(.done)
                    .onSubmit(save)
                    .listRowBackground(theme.colors.groupedSurface)
                Text("\(item.query) · \(item.scope.title)")
                    .foregroundStyle(.secondary)
                    .listRowBackground(theme.colors.groupedSurface)
            }
            .moroSettingsListChrome()
            .navigationTitle(MoroL10n.Search.renameSearch)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(MoroL10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(MoroL10n.Common.save, action: save)
                }
            }
            .task { isFocused = true }
        }
    }

    private func save() {
        library.rename(id: item.id, name: name)
        dismiss()
    }
}
