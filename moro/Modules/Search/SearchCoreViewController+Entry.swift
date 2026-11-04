import SwiftUI
import UIKit

extension SearchCoreViewController {
    func setupCancelEntryButton() {
        cancelEntryButton.translatesAutoresizingMaskIntoConstraints = false
        cancelEntryButton.setTitle(MoroL10n.Common.cancel, for: .normal)
        cancelEntryButton.accessibilityIdentifier = "search.cancel"
        cancelEntryButton.isHidden = true
        cancelEntryButton.setContentHuggingPriority(.required, for: .horizontal)
        cancelEntryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cancelEntryButton.addAction(UIAction { [weak self] _ in self?.cancelSearchEntry() }, for: .touchUpInside)
        view.addSubview(cancelEntryButton)
        searchTrailingRegular = searchBar.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor, constant: -SearchLayoutMetrics.searchBarOuterHorizontalInset)
        searchTrailingWithCancel = searchBar.trailingAnchor.constraint(equalTo: cancelEntryButton.leadingAnchor)
        NSLayoutConstraint.activate([
            cancelEntryButton.topAnchor.constraint(equalTo: searchBar.topAnchor),
            cancelEntryButton.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor),
            cancelEntryButton.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor, constant: -SearchLayoutMetrics.contentHorizontalInset),
            cancelEntryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    func setupEntryUI() {
        addChild(entryHost)
        entryHost.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(entryHost.view)
        NSLayoutConstraint.activate([
            entryHost.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            entryHost.view.leadingAnchor.constraint(equalTo: readableGuide.leadingAnchor),
            entryHost.view.trailingAnchor.constraint(equalTo: readableGuide.trailingAnchor),
            entryHost.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        entryHost.didMove(toParent: self)
        entryHost.view.isHidden = true
    }

    func beginSearchEntry() {
        guard interaction.page != .entry else { return }
        if interaction.page == .discovery {
            discoveryOffset = tableView.contentOffset
            discoveryScope = selectedScope
        }
        interaction.beginEntry()
        library.reload()
        updateSearchChrome()
        updateEntryContent()
        setCancelButtonVisible(true)
    }

    func updateEntryContent() {
        entryHost.rootView = AnyView(
            SearchEntryView(
                library: library,
                query: interaction.draftQuery,
                onSubmit: { [weak self] query, scope in
                    guard let self else { return }
                    if scope == nil, self.searchBar.searchTextField.markedTextRange != nil { return }
                    self.submitQuery(query, scope: scope ?? self.selectedScope)
                }
            )
            .moroTheme(appliedTheme)
            .environment(\.colorScheme, appliedTheme.colorScheme)
            .environment(\.dynamicTypeSize, appliedTheme.dynamicTypeSize)
        )
    }

    func cancelSearchEntry() {
        guard interaction.page == .entry else {
            searchBar.searchTextField.resignFirstResponder()
            return
        }
        showDiscovery()
    }

    func submitQuery(_ query: String, scope: Scope) {
        let scope = scope.exploreScope
        guard interaction.submit(query, scope: scope) else { return }
        searchBar.text = interaction.submittedQuery
        scopeControl.selectedSegmentIndex = scope.segmentIndex
        library.record(query: interaction.submittedQuery, scope: scope)
        searchBar.searchTextField.resignFirstResponder()
        setCancelButtonVisible(false)
        updateSearchChrome()
        startSearch(reset: true)
        setListContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
    }

    func showDiscovery() {
        interaction.showDiscovery()
        searchBar.text = ""
        scopeControl.selectedSegmentIndex = discoveryScope.segmentIndex
        searchBar.searchTextField.resignFirstResponder()
        setCancelButtonVisible(false)
        updateSearchChrome()
        clearSearchState()
        loadDiscoveryIfNeeded()
        view.layoutIfNeeded()
        setListContentOffset(discoveryOffset, animated: false)
    }

    func updateSearchChrome() {
        guard isViewLoaded else { return }
        let isEntry = interaction.page == .entry
        entryHost.view.isHidden = !isEntry
        tableView.isHidden = isEntry
        updateMediaPlaybackActivity()
        updateScopePresentation()
        let palette = appliedTheme.uiKitPalette
        entryHost.view.backgroundColor = palette.canvasBackground
        onEntryStateChanged?(isEntry)
    }
}
