import Combine
import SwiftUI

@MainActor
final class StatusEngagementViewModel: ObservableObject {
    nonisolated deinit {}

    struct Page {
        var accounts: [Account] = []
        var nextMaxID: String?
        var visitedCursors = Set<String>()
        var hasLoaded = false
        var isLoading = false
        var error: Error?
    }

    private let statusID: String
    private let apiClient: MastodonAPI
    @Published private var pages: [StatusEngagementKind: Page] = [:]

    init(statusID: String, apiClient: MastodonAPI) {
        self.statusID = statusID
        self.apiClient = apiClient
    }

    subscript(kind: StatusEngagementKind) -> Page { pages[kind] ?? Page() }

    func load(_ kind: StatusEngagementKind, after cursor: String? = nil) async {
        var page = self[kind]
        guard !page.isLoading, cursor == page.nextMaxID, cursor != nil || !page.hasLoaded else { return }
        page.isLoading = true
        page.error = nil
        pages[kind] = page
        do {
            let response = try await apiClient.fetchStatusEngagement(id: statusID, kind: kind, maxID: cursor)
            try Task.checkCancellation()
            var knownIDs = Set(page.accounts.map(\.id))
            page.accounts.append(contentsOf: response.accounts.filter { knownIDs.insert($0.id).inserted })
            if let cursor { page.visitedCursors.insert(cursor) }
            page.nextMaxID = response.nextMaxID.flatMap { page.visitedCursors.contains($0) ? nil : $0 }
            page.hasLoaded = true
        } catch {
            if !Task.isCancelled { page.error = error }
        }
        page.isLoading = false
        pages[kind] = page
    }
}

struct StatusEngagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var router = AppRouter()
    @StateObject private var model: StatusEngagementViewModel
    @State private var selection: StatusEngagementKind

    let status: Status
    let apiClient: MastodonAPI

    init(status: Status, apiClient: MastodonAPI) {
        self.status = status
        self.apiClient = apiClient
        _model = StateObject(wrappedValue: StatusEngagementViewModel(statusID: status.id, apiClient: apiClient))
        _selection = State(initialValue: status.favouritesCount == 0 && status.reblogsCount > 0 ? .boosts : .favourites)
    }

    var body: some View {
        VStack(spacing: 0) {
            MoroSectionTabBar(
                tabs: [.favourites, .boosts],
                selection: selection,
                title: tabTitle,
                accessibilityIdentifier: { $0 == .favourites ? "engagement.tab.favourites" : "engagement.tab.boosts" },
                onSelect: { selection = $0 }
            )
            .moroReadableColumn()
            MoroDivider()

            accounts(for: selection)
                .id(selection)

            MoroDivider()
            MoroSectionTextBlock(title: nil, message: MoroL10n.StatusDetail.engagementSourceNote)
                .padding(.horizontal, theme.spacing.contentHorizontalInset)
                .padding(.vertical, theme.spacing.s)
                .moroReadableColumn()
        }
        .background(theme.colors.surfaceBase)
        .navigationTitle(MoroL10n.StatusDetail.engagementTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                MoroNavigationControlButton(kind: .close) { dismiss() }
                    .accessibilityIdentifier("engagement.close")
            }
        }
        .onChange(of: selection, initial: true) { _, kind in
            Task { await model.load(kind) }
        }
        .withRouter(apiClient: apiClient, router: router)
        .moroSheetSurface(detents: router.path.isEmpty && !dynamicTypeSize.isAccessibilitySize ? [.medium, .large] : [.large])
    }

    private func tabTitle(_ kind: StatusEngagementKind) -> String {
        switch kind {
        case .favourites: MoroL10n.StatusDetail.likesCount(status.favouritesCount.formatted(.number.locale(locale)))
        case .boosts: MoroL10n.StatusDetail.boostsCount(status.reblogsCount.formatted(.number.locale(locale)))
        }
    }

    @ViewBuilder
    private func accounts(for kind: StatusEngagementKind) -> some View {
        let page = model[kind]
        if let error = page.error, page.accounts.isEmpty {
            InlineFeedbackCard(kind: .error, message: error.localizedDescription,
                               actionTitle: MoroL10n.StatusDetail.retry) {
                Task { await model.load(kind, after: page.nextMaxID) }
            }
            .padding(theme.spacing.m)
            .frame(maxHeight: .infinity, alignment: .top)
        } else if page.accounts.isEmpty && page.nextMaxID == nil {
            Group {
                if page.hasLoaded {
                    Text(MoroL10n.StatusDetail.engagementEmpty)
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textSecondary)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(page.accounts) { account in
                    ProfileConnectionAccountRow(account: account, showsConnectionCounts: false) {
                        router.navigate(to: .userProfile(account))
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(theme.colors.surfaceBase)

                if let cursor = page.nextMaxID {
                    Group {
                        if page.error != nil {
                            PaginationFooter(isLoadingMore: false, didFail: true) {
                                Task { await model.load(kind, after: cursor) }
                            }
                        } else {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .onAppear { Task { await model.load(kind, after: cursor) } }
                        }
                    }
                    .id(cursor)
                    .listRowSeparator(.hidden)
                    .listRowBackground(theme.colors.surfaceBase)
                }
            }
            .listStyle(.plain)
            .moroReadableListMargins()
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
        }
    }
}
