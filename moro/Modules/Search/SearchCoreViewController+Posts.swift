import SwiftUI
import UIKit

extension SearchCoreViewController {
    func hostedPlaybackContent(_ content: AnyView) -> AnyView {
        AnyView(content
            .environment(\.moroPlaybackScope, playbackScope)
            .environment(\.moroUIKitScrollVisibility, avatarVisibility))
    }

    func configureAccountPlayback(_ cell: SearchResultLineCell) {
        cell.makeAccountView = { [weak self] account in
            guard let self else { return AnyView(EmptyView()) }
            let content = self.makeAccountView?(account)
                ?? AnyView(SearchAccountRowContentView(account: account).moroTheme(self.appliedTheme))
            return self.hostedPlaybackContent(content)
        }
    }

    func isStatusRow(at indexPath: IndexPath) -> Bool {
        guard mode == .results, sections.indices.contains(indexPath.section),
              sections[indexPath.section].rows.indices.contains(indexPath.row),
              case .status = sections[indexPath.section].rows[indexPath.row] else { return false }
        return true
    }

    func configureStatusCell(_ cell: UITableViewCell, status: Status) {
        cell.selectionStyle = .none
        cell.accessoryType = .none
        cell.backgroundColor = appliedTheme.uiKitPalette.surfaceBase
        let content = makeStatusView?(status, { [weak self] pollID, choices in
            await self?.votePoll(pollID: pollID, choices: choices) ?? false
        }) ?? AnyView(TimelinePostRow(status: status, threadContext: .none).moroTheme(appliedTheme))
        let hosted = hostedPlaybackContent(content)
        cell.contentConfiguration = UIHostingConfiguration { hosted }.margins(.all, 0)
    }

    func votePoll(pollID: String, choices: [Int]) async -> Bool {
        do {
            let poll = try await apiClient.votePoll(pollID: pollID, choices: choices)
            // Merge into the latest row: a reaction may have completed while voting.
            guard let status = (searchState.results.statuses + discovery.statuses)
                .first(where: { $0.displayStatus.poll?.id == pollID }) else { return false }
            FeedCoordinator.shared.publishUpdate(.post(status.updating(poll: poll)))
            return true
        } catch {
            AppLogger.error("Search poll vote failed: \(error)")
            return false
        }
    }

    func refreshVisibleStatusRows() {
        guard interaction.page != .entry else { return }
        for index in tableView.indexPathsForVisibleRows ?? [] where isStatusRow(at: index) {
            guard case .status(let status) = sections[index.section].rows[index.row],
                  let cell = tableView.cellForRow(at: index) else { continue }
            configureStatusCell(cell, status: status)
        }
    }

    func incorporatePostUpdate(_ update: UpdatedElement) {
        let transform: ([Status]) -> [Status]
        switch update {
        case .post(let status):
            transform = { statuses in
                statuses.map { $0.incorporatingDisplayStatusUpdate(status.displayStatus) }
            }
        case .deletedPost(let id):
            transform = { statuses in statuses.filter { $0.id != id && $0.displayStatus.id != id } }
        default:
            return
        }
        discovery.statuses = transform(discovery.statuses)
        searchState.transformStatuses(transform)
    }
}
