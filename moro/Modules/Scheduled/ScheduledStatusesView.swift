//
//  ScheduledStatusesView.swift
//  moro
//
//  Scheduled statuses list (MVP).
//

import SwiftUI

struct ScheduledStatusesView: View {
    @StateObject private var viewModel: ScheduledStatusesViewModel
    @Environment(\.moroTheme) private var theme

    init(apiClient: MastodonAPI) {
        _viewModel = StateObject(wrappedValue: ScheduledStatusesViewModel(apiClient: apiClient))
    }

    var body: some View {
        ContentStateContainer(state: contentState) {
            contentList
        }
        .navigationTitle(MoroL10n.Scheduled.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadInitial()
        }
    }

    private var isLoadingMore: Bool {
        if case .loadingMore = viewModel.loadingState { return true }
        return false
    }

    private var contentState: ContentState {
        if viewModel.items.isEmpty, case .loading = viewModel.loadingState {
            return .loading(.list)
        }
        if viewModel.items.isEmpty, case .error(let error) = viewModel.loadingState {
            return .error(
                ErrorStateSpec(
                    title: MoroL10n.Scheduled.loadFailed,
                    message: error.localizedDescription,
                    actionTitle: MoroL10n.Scheduled.retry,
                    action: {
                        Task { await viewModel.loadInitial() }
                    },
                    alignment: .leading
                )
            )
        }
        if viewModel.items.isEmpty {
            return .empty(
                EmptyStateSpec(
                    icon: "clock.badge.checkmark",
                    title: MoroL10n.Scheduled.emptyTitle,
                    message: MoroL10n.Scheduled.emptyMessage,
                    actionTitle: MoroL10n.Scheduled.refresh,
                    action: {
                        Task { await viewModel.refresh() }
                    },
                    alignment: .leading
                )
            )
        }
        return .loaded
    }

    @ViewBuilder
    private var contentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Text(MoroL10n.Scheduled.subtitle)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.bottom, theme.spacing.s)

                if let transientErrorMessage = viewModel.transientErrorMessage {
                    MoroSectionTextBlock(
                        title: MoroL10n.Scheduled.actionFailed,
                        message: transientErrorMessage,
                        icon: "exclamationmark.triangle.fill",
                        tint: theme.colors.error
                    )
                    .padding(.horizontal, theme.spacing.m)
                    .padding(.bottom, theme.spacing.s)
                }

                ForEach(Array(viewModel.items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await viewModel.cancel(item) }
                            } label: {
                                Label(MoroL10n.Scheduled.cancel, systemImage: "xmark.circle")
                            }
                            .disabled(viewModel.isCancelling(item.id))
                        }

                    if index < viewModel.items.count - 1 {
                        MoroDivider()
                            .padding(.leading, theme.spacing.m)
                    }

                    if viewModel.items.count - index <= 3 {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadMore() }
                            }
                    }
                }

                PaginationFooter(
                    isLoadingMore: isLoadingMore,
                    didFail: viewModel.loadMoreFailed,
                    onRetry: { Task { await viewModel.loadMore() } }
                )
            }
            .padding(.vertical, theme.spacing.s)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func row(_ item: ScheduledStatus) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(spacing: theme.spacing.s) {
                Label(
                    scheduledDateText(item.scheduledAt),
                    systemImage: "calendar.badge.clock"
                )
                .font(theme.typography.caption)
                .foregroundStyle(theme.colors.primary500)

                Spacer()

                if viewModel.isCancelling(item.id) {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Text(MoroL10n.Scheduled.pending)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textTertiary)
                }
            }

            Text(item.previewText)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textPrimary)
                .lineLimit(3)

            if item.mediaAttachments.isEmpty == false {
                HStack(spacing: 6) {
                    Image(systemName: "photo.on.rectangle")
                        .moroScaledFont(size: 11, weight: .medium)
                    Text(MoroL10n.Scheduled.mediaCount(item.mediaAttachments.count))
                        .font(theme.typography.caption)
                }
                .foregroundStyle(theme.colors.textSecondary)
            }
        }
        .padding(.horizontal, theme.spacing.m)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scheduledDateText(_ date: Date) -> String {
        date.formatted(.dateTime.month().day().hour().minute())
    }
}

#Preview {
    let appState = AppState()
    let interceptor = AuthInterceptor(tokenProvider: appState)
    let client = MastodonClient(authInterceptor: interceptor)

    return ScheduledStatusesView(apiClient: client)
        .environmentObject(appState)
        .moroTheme(MoroTheme())
}
