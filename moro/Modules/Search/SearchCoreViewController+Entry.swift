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
        searchTrailingRegular = searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SearchLayoutMetrics.searchBarOuterHorizontalInset)
        searchTrailingWithCancel = searchBar.trailingAnchor.constraint(equalTo: cancelEntryButton.leadingAnchor)
        NSLayoutConstraint.activate([
            cancelEntryButton.topAnchor.constraint(equalTo: searchBar.topAnchor),
            cancelEntryButton.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor),
            cancelEntryButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SearchLayoutMetrics.contentHorizontalInset),
            cancelEntryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    func setupResultActions() {
        resultActions.translatesAutoresizingMaskIntoConstraints = false
        resultActions.axis = .horizontal
        resultActions.distribution = .equalSpacing
        resultActions.addArrangedSubview(discoveryButton)
        resultActions.addArrangedSubview(saveSearchButton)
        view.addSubview(resultActions)
        resultActionsHeight = resultActions.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            resultActions.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            resultActions.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SearchLayoutMetrics.contentHorizontalInset),
            resultActions.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SearchLayoutMetrics.contentHorizontalInset),
            resultActionsHeight,
        ])
        discoveryButton.accessibilityIdentifier = "search.discovery"
        saveSearchButton.accessibilityIdentifier = "search.save"
        discoveryButton.addAction(UIAction { [weak self] _ in self?.showDiscovery() }, for: .touchUpInside)
        saveSearchButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.library.save(query: self.trimmedQuery, scope: self.selectedScope)
            self.updateSearchChrome()
        }, for: .touchUpInside)
    }

    func setupEntryUI() {
        addChild(entryHost)
        entryHost.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(entryHost.view)
        NSLayoutConstraint.activate([
            entryHost.view.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            entryHost.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            entryHost.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            entryHost.view.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
        entryHost.didMove(toParent: self)
        entryHost.view.isHidden = true
    }

    func beginSearchEntry() {
        guard interaction.page != .entry else { return }
        entryReturnOffset = tableView.contentOffset
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
                },
                onManage: { [weak self] in
                    self?.searchBar.searchTextField.resignFirstResponder()
                    self?.onManageSavedSearches?()
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
        interaction.cancelEntry()
        searchBar.text = interaction.submittedQuery
        searchBar.searchTextField.resignFirstResponder()
        setCancelButtonVisible(false)
        updateSearchChrome()
        refreshViewState()
        view.layoutIfNeeded()
        tableView.setContentOffset(entryReturnOffset, animated: false)
    }

    func submitQuery(_ query: String, scope: Scope) {
        guard interaction.submit(query, scope: scope) else { return }
        searchBar.text = interaction.submittedQuery
        scopeControl.selectedSegmentIndex = scope.rawValue
        library.record(query: interaction.submittedQuery, scope: scope)
        searchBar.searchTextField.resignFirstResponder()
        setCancelButtonVisible(false)
        updateSearchChrome()
        startSearch(reset: true)
        tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
    }

    func showDiscovery() {
        interaction.showDiscovery()
        searchBar.text = ""
        scopeControl.selectedSegmentIndex = discoveryScope.rawValue
        searchBar.searchTextField.resignFirstResponder()
        setCancelButtonVisible(false)
        updateSearchChrome()
        clearSearchState()
        loadDiscoveryIfNeeded()
        view.layoutIfNeeded()
        tableView.setContentOffset(discoveryOffset, animated: false)
    }

    func updateSearchChrome() {
        guard isViewLoaded else { return }
        let isEntry = interaction.page == .entry
        let isResults = interaction.page == .results
        entryHost.view.isHidden = !isEntry
        tableView.isHidden = isEntry
        resultActions.isHidden = !isResults
        resultActionsHeight.constant = isResults
            ? (appliedTheme.dynamicTypeSize.isAccessibilitySize ? 64 : 44) : 0
        updateScopePresentation()
        let palette = appliedTheme.uiKitPalette
        entryHost.view.backgroundColor = palette.canvasBackground
        let saved = library.isSaved(query: trimmedQuery, scope: selectedScope)
        for (button, title, symbol) in [
            (discoveryButton, MoroL10n.Search.returnDiscovery, "chevron.backward"),
            (saveSearchButton, saved ? MoroL10n.Search.searchSaved : MoroL10n.Search.saveSearch, saved ? "bookmark.fill" : "bookmark"),
        ] {
            var configuration = UIButton.Configuration.plain()
            configuration.title = title
            configuration.image = UIImage(systemName: symbol)
            configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            configuration.imagePadding = 6
            configuration.contentInsets = .zero
            configuration.baseForegroundColor = palette.textSecondary
            configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: min(palette.font(forTextStyle: .subheadline).pointSize, 22))
                return outgoing
            }
            button.configuration = configuration
        }
        saveSearchButton.isEnabled = !saved
    }
}
