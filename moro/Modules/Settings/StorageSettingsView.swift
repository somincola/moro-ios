import SwiftUI

struct StorageSettingsView: View {
    @ObservedObject private var store = StorageManagementStore.shared
    @State private var confirmsClear = false

    var body: some View {
        List {
            Section {
                usageRow(MoroL10n.AppSupport.images, bytes: store.usage?.images)
                usageRow(MoroL10n.AppSupport.timelines, bytes: store.usage?.timelines)
                usageRow(MoroL10n.AppSupport.responses, bytes: store.usage?.responses)
                usageRow(MoroL10n.AppSupport.total, bytes: store.usage?.total)
                    .fontWeight(.medium)
            } footer: {
                Text(MoroL10n.AppSupport.cacheDetail)
            }
            Section {
                Button(role: .destructive) { confirmsClear = true } label: {
                    HStack {
                        Text(store.isClearing ? MoroL10n.AppSupport.clearing : MoroL10n.AppSupport.clearCache)
                        Spacer()
                        if store.isClearing { ProgressView() }
                    }
                }
                .disabled(store.isClearing || store.usage == nil)
                .accessibilityIdentifier("storage.clear")
            } footer: {
                Text(MoroL10n.AppSupport.preservedData)
            }
            if store.failed {
                Text(MoroL10n.AppSupport.clearFailed).foregroundStyle(.secondary)
            }
        }
        .moroSettingsListChrome()
        .navigationTitle(MoroL10n.AppSupport.storage)
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.refresh() }
        .confirmationDialog(MoroL10n.AppSupport.clearCache, isPresented: $confirmsClear, titleVisibility: .visible) {
            Button(MoroL10n.AppSupport.clearCache, role: .destructive) {
                Task { await store.clear() }
            }
            Button(MoroL10n.Common.cancel, role: .cancel) {}
        } message: { Text(MoroL10n.AppSupport.preservedData) }
    }

    private func usageRow(_ title: String, bytes: Int64?) -> some View {
        HStack {
            Text(title)
            Spacer()
            if let bytes { Text(StorageManagementStore.formatted(bytes)).foregroundStyle(.secondary) }
            else { ProgressView() }
        }
    }
}
