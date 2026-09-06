//
//  SearchCoreViewController+DataSource.swift
//  moro
//
//  Search input and table view delegate/data-source behavior.
//

#if os(iOS)
import SwiftUI
import UIKit

extension SearchCoreViewController: UISearchBarDelegate {
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool {
        guard allowsSearchFocus else { return false }
        beginSearchEntry()
        return true
    }

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        beginSearchEntry()
        interaction.draftQuery = searchText
        updateEntryContent()
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // A return key confirming an IME candidate is not a search submission.
        guard searchBar.searchTextField.markedTextRange == nil else { return }
        submitQuery(searchBar.text ?? "", scope: selectedScope)
    }

    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        cancelSearchEntry()
    }

    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        // Dismissing the keyboard leaves the entry page and its draft intact.
    }
}

extension SearchCoreViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        switch mode {
        case .placeholder, .loading, .empty:
            return 0
        case .error:
            return 1
        case .results:
            return sections.count + (showsPaginationSection ? 1 : 0)
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .placeholder, .loading, .empty:
            return 0
        case .error:
            return 1
        case .results:
            if showsPaginationSection, section == sections.count {
                return 1
            }
            guard sections.indices.contains(section) else { return 0 }
            return sections[section].rows.count
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch mode {
        case .error(let message):
            let cell = tableView.dequeueReusableCell(withIdentifier: "StateCell", for: indexPath)
            let palette = appliedTheme.uiKitPalette
            var config = UIListContentConfiguration.subtitleCell()
            config.text = trimmedQuery.isEmpty ? MoroL10n.Search.errorDiscoverFailed : MoroL10n.Search.errorSearchFailed
            config.secondaryText = message
            config.secondaryTextProperties.numberOfLines = 2
            config.textProperties.color = palette.textPrimary
            config.secondaryTextProperties.color = palette.textSecondary
            config.textProperties.font = palette.font(forTextStyle: .body, weight: .semibold)
            config.secondaryTextProperties.font = palette.font(forTextStyle: .subheadline)
            cell.contentConfiguration = config
            cell.accessoryType = .disclosureIndicator
            applyStateCellTheme(cell, palette: palette)
            return cell

        case .results:
            if showsPaginationSection, indexPath.section == sections.count {
                guard
                    let cell = tableView.dequeueReusableCell(
                        withIdentifier: SearchLoadingMoreCell.reuseIdentifier,
                        for: indexPath
                    ) as? SearchLoadingMoreCell
                else {
                    return UITableViewCell()
                }
                if loadMoreFailed {
                    cell.configureRetry { [weak self] in
                        self?.retryLoadMore()
                    }
                } else {
                    cell.configureLoading()
                }
                cell.apply(theme: appliedTheme)
                return cell
            }

            guard sections.indices.contains(indexPath.section) else {
                return UITableViewCell()
            }
            let section = sections[indexPath.section]
            let row = section.rows[indexPath.row]
            let reuseIdentifier: String
            if case .account = row {
                reuseIdentifier = SearchResultLineCell.accountReuseIdentifier
            } else {
                reuseIdentifier = SearchResultLineCell.reuseIdentifier
            }
            guard
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: reuseIdentifier,
                    for: indexPath
                ) as? SearchResultLineCell
            else {
                return UITableViewCell()
            }
            cell.configure(with: rowContent(for: row), theme: appliedTheme)
            return cell

        case .placeholder, .loading, .empty:
            return UITableViewCell()
        }
    }
}

extension SearchCoreViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        guard case .results = mode,
            sections.indices.contains(indexPath.section),
            sections[indexPath.section].rows.indices.contains(indexPath.row),
            case .hashtag = sections[indexPath.section].rows[indexPath.row]
        else {
            return UITableView.automaticDimension
        }

        let palette = appliedTheme.uiKitPalette
        let textHeight = palette.font(forTextStyle: .subheadline, weight: .semibold).lineHeight
            + palette.font(forTextStyle: .caption2).lineHeight
        return max(60, ceil(textHeight + 24))
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        .leastNormalMagnitude
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        defer { tableView.deselectRow(at: indexPath, animated: true) }

        switch mode {
        case .error:
            if trimmedQuery.isEmpty {
                loadDiscoveryIfNeeded(forceRefresh: true)
            } else {
                startSearch(reset: true)
            }

        case .results:
            guard sections.indices.contains(indexPath.section) else { return }
            let row = sections[indexPath.section].rows[indexPath.row]
            prepareForNavigation()
            switch row {
            case .account(let account):
                onOpenProfile?(account)
            case .status(let status):
                onOpenStatus?(status)
            case .hashtag(let tag):
                onOpenHashtag?(tag.name)
            }

        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard interaction.page != .entry, case .results = mode else { return }
        guard sections.indices.contains(indexPath.section) else { return }

        if trimmedQuery.isEmpty {
            guard sections[indexPath.section].kind == .accounts else { return }
            guard !discovery.isLoading, !discovery.isLoadingMoreAccounts, discovery.hasMoreAccounts else { return }
            let lastRowIndex = sections[indexPath.section].rows.count - 1
            if indexPath.row >= max(lastRowIndex - 1, 0) {
                loadDiscovery(resetAccounts: false)
            }
            return
        }

        guard !isLoading, !isLoadingMore, !loadMoreFailed, hasMoreResults else { return }
        let lastSectionIndex = sections.count - 1
        guard indexPath.section == lastSectionIndex else { return }
        let lastRowIndex = sections[lastSectionIndex].rows.count - 1

        if indexPath.row >= max(lastRowIndex - 1, 0) {
            startSearch(reset: false)
        }
    }
}
#endif
