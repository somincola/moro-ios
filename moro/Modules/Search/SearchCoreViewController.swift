//
//  SearchCoreViewController.swift
//  moro
//
//  Search controller lifecycle, rendering, and query orchestration.
//

import SwiftUI
#if os(iOS)
import UIKit

@MainActor
final class SearchCoreViewController: UIViewController {
    typealias Scope = SearchViewModel.Scope

    enum SearchTriggerPolicy {
        case debounceAndSearchKey
        case searchKeyOnly
    }

    struct SectionModel {
        enum Kind: Hashable {
            case accounts
            case statuses
            case hashtags
        }

        let kind: Kind
        let title: String
        let rows: [Row]
    }

    enum Row {
        case account(Account)
        case status(Status)
        case hashtag(SearchTag)
    }

    enum ViewMode: Equatable {
        case placeholder
        case typing
        case loading
        case error(String)
        case empty
        case results
    }

    private struct RenderSnapshot: Equatable {
        let mode: ViewMode
        let sectionFingerprints: [Int]
        let isLoadingMore: Bool
        let loadMoreFailed: Bool
        let queryIsEmpty: Bool
    }

    struct DiscoveryState {
        var accounts: [Account] = []
        var statuses: [Status] = []
        var hashtags: [SearchTag] = []
        var hasLoaded = false
        var errorMessage: String?
        var isLoading = false
        var isLoadingMoreAccounts = false
        var hasMoreAccounts = false
        var nextAccountOffset = 0
    }

    let apiClient: MastodonAPI
    let searchState: SearchViewModel
    private let initialQuery: String?
    var appliedTheme: MoroTheme

    var onOpenProfile: ((Account) -> Void)?
    var onOpenStatus: ((Status) -> Void)?
    var onOpenHashtag: ((String) -> Void)?

    let initialPageSize = 20
    let paginationPageSize = 40
    let triggerPolicy: SearchTriggerPolicy = .debounceAndSearchKey
    private let debounceNanoseconds: UInt64 = 280_000_000
    let minimumDebouncedQueryLength = 2

    private let searchBar = UISearchBar(frame: .zero)
    private let scopeControl = UISegmentedControl(items: Scope.allCases.map(\.title))
    private let scopeIndicatorView = UIView()
    private let scopeMenuButton = UIButton(type: .system)
    private let tableView = UITableView(frame: .zero, style: .plain)
    let refreshControl = UIRefreshControl()
    private var scopeHeightConstraint: NSLayoutConstraint!

    private lazy var placeholderView: SearchLandingPlaceholderView = {
        let container = SearchLandingPlaceholderView()
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focusSearchInput))
        container.addGestureRecognizer(tapGesture)
        return container
    }()

    private lazy var typingStateView = SearchCenterStateView(
        iconName: "text.cursor",
        title: MoroL10n.Search.typingHint,
        showsIndicator: false,
        animationStyle: .typingCursor
    )

    private lazy var loadingStateView = SearchCenterStateView(
        iconName: nil,
        title: MoroL10n.Search.loading,
        showsIndicator: true,
        animationStyle: .searchingIndicator
    )

    private lazy var emptyStateView = SearchCenterStateView(
        iconName: "tray",
        title: MoroL10n.Search.emptyNoMatch,
        subtitle: MoroL10n.Search.emptyNoMatchHint,
        showsIndicator: false,
        animationStyle: .none
    )

    private lazy var discoveryEmptyStateView = SearchCenterStateView(
        iconName: nil,
        assetName: "ExploreEmptyMascot",
        imageSize: CGSize(width: 116, height: 116),
        title: MoroL10n.Search.emptyNoDiscover,
        showsIndicator: false,
        animationStyle: .none
    )

    var sections: [SectionModel] = []
    var mode: ViewMode = .placeholder

    private var results: SearchResults { searchState.results }
    private var errorMessage: String? { searchState.errorMessage }
    var isLoading: Bool { searchState.isLoading }
    var isLoadingMore: Bool { searchState.isLoadingMore }
    var hasMoreResults: Bool { searchState.hasMoreResults }
    var loadMoreFailed: Bool { searchState.loadMoreFailed }
    private var hasSearchedCurrentQuery: Bool { searchState.hasSearchedCurrentQuery }
    var pendingSearchQuery: String?

    var debounceTask: Task<Void, Never>?
    private var isCancelButtonVisible = false
    private let scopeSelectionFeedback = UISelectionFeedbackGenerator()
    private var lastScopeSelectionIndex: Int = Scope.all.rawValue
    private var lastRenderSnapshot: RenderSnapshot?
    private var lastRenderedSections: [SectionModel] = []
    var discovery = DiscoveryState()
    var discoveryTask: Task<Void, Never>?
    var discoveryRequestID = UUID()

    init(apiClient: MastodonAPI, initialQuery: String?, theme: MoroTheme) {
        self.apiClient = apiClient
        self.searchState = SearchViewModel(apiClient: apiClient, initialQuery: initialQuery)
        self.initialQuery = initialQuery
        self.appliedTheme = theme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupUI()
        setupSearchBar()
        setupScopeControl()
        setupTableView()
        setupScopeSwipeGestures()
        apply(theme: appliedTheme)
        searchState.onResultsReceived = { results in
            SearchStatusPreviewCache.shared.prewarm(statuses: results.statuses)
        }
        searchState.onStateChange = { [weak self] in
            guard let self else { return }
            self.endRefreshingIfNeeded()
            self.refreshViewState()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange(_:)),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )

        var hasInitialSearch = false
        if let initialQuery {
            let trimmed = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                searchBar.text = trimmed
                startSearch(reset: true, overrideQuery: trimmed)
                hasInitialSearch = true
            }
        }

        if !hasInitialSearch {
            loadDiscoveryIfNeeded()
        }

        refreshViewState()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        _ = becomeFirstResponder()
        scopeSelectionFeedback.prepare()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutScopeIndicator()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        searchState.clearCache()
    }

    func apply(theme: MoroTheme) {
        appliedTheme = theme
        guard isViewLoaded else { return }

        let palette = theme.uiKitPalette
        overrideUserInterfaceStyle = palette.interfaceStyle
        view.backgroundColor = palette.canvasBackground

        searchBar.backgroundColor = .clear
        searchBar.barTintColor = palette.canvasBackground
        searchBar.tintColor = palette.primary
        searchBar.searchTextField.backgroundColor = palette.surfaceSubtle
        searchBar.searchTextField.textColor = palette.textPrimary
        searchBar.searchTextField.tintColor = palette.primary
        applySearchChromeSizing(palette: palette)
        searchBar.searchTextField.attributedPlaceholder = NSAttributedString(
            string: searchBar.placeholder ?? MoroL10n.Search.placeholder,
            attributes: [.foregroundColor: palette.textTertiary]
        )

        scopeControl.backgroundColor = .clear
        scopeControl.setTitleTextAttributes([
            .font: chromeFont(
                palette: palette,
                textStyle: .subheadline,
                maximumPointSize: SearchLayoutMetrics.maximumScopePointSize
            ),
            .foregroundColor: palette.textSecondary,
        ], for: .normal)
        scopeControl.setTitleTextAttributes([
            .font: chromeFont(
                palette: palette,
                textStyle: .subheadline,
                weight: .semibold,
                maximumPointSize: SearchLayoutMetrics.maximumScopePointSize
            ),
            .foregroundColor: palette.textPrimary,
        ], for: .selected)
        scopeIndicatorView.backgroundColor = palette.textPrimary
        updateScopePresentation(palette: palette)

        tableView.backgroundColor = palette.canvasBackground
        tableView.indicatorStyle = theme.colorScheme == .dark ? .white : .black
        refreshControl.tintColor = palette.textSecondary

        placeholderView.apply(theme: theme)
        typingStateView.apply(theme: theme)
        loadingStateView.apply(theme: theme)
        emptyStateView.apply(theme: theme)
        discoveryEmptyStateView.apply(theme: theme)

        for cell in tableView.visibleCells {
            switch cell {
            case let resultCell as SearchResultLineCell:
                resultCell.apply(theme: theme)
            case let loadingCell as SearchLoadingMoreCell:
                loadingCell.apply(theme: theme)
            default:
                applyStateCellTheme(cell, palette: palette)
            }
        }

        for section in 0..<tableView.numberOfSections {
            (tableView.headerView(forSection: section) as? SearchSectionHeaderView)?.apply(theme: theme)
        }

        view.setNeedsLayout()
        layoutScopeIndicator()
    }

    @objc
    private func contentSizeCategoryDidChange(_ notification: Notification) {
        apply(theme: appliedTheme)
        UIView.performWithoutAnimation {
            tableView.beginUpdates()
            tableView.endUpdates()
        }
    }

    func applyStateCellTheme(
        _ cell: UITableViewCell,
        palette: MoroUIKitThemePalette
    ) {
        cell.backgroundColor = palette.surfaceBase
        cell.contentView.backgroundColor = palette.surfaceBase
        cell.tintColor = palette.textSecondary

        guard var configuration = cell.contentConfiguration as? UIListContentConfiguration else { return }
        configuration.textProperties.color = palette.textPrimary
        configuration.secondaryTextProperties.color = palette.textSecondary
        configuration.textProperties.font = palette.font(forTextStyle: .body, weight: .semibold)
        configuration.secondaryTextProperties.font = palette.font(forTextStyle: .subheadline)
        cell.contentConfiguration = configuration
    }

    override var keyCommands: [UIKeyCommand]? {
        let focus = UIKeyCommand(input: "f", modifierFlags: [.command], action: #selector(focusSearchInput))
        focus.discoverabilityTitle = MoroL10n.Search.keyboardFocus
        let dismiss = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(handleEscapeKey))
        dismiss.discoverabilityTitle = MoroL10n.Search.keyboardDismiss
        return [focus, dismiss]
    }

    override var canBecomeFirstResponder: Bool {
        true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        debounceTask?.cancel()
        discoveryTask?.cancel()
    }

    var trimmedQuery: String {
        (searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var selectedScope: Scope {
        Scope(rawValue: scopeControl.selectedSegmentIndex) ?? .all
    }

    private var isDiscoveryMode: Bool {
        trimmedQuery.isEmpty
    }

    private var displayedResults: SearchResults {
        if isDiscoveryMode {
            return SearchResults(
                accounts: discovery.accounts,
                statuses: discovery.statuses,
                hashtags: discovery.hashtags
            )
        }
        return results
    }

    private var hasVisibleResultContent: Bool {
        let currentResults = displayedResults
        switch selectedScope {
        case .all:
            return !currentResults.accounts.isEmpty
                || !currentResults.statuses.isEmpty
                || !currentResults.hashtags.isEmpty
        case .accounts:
            return !currentResults.accounts.isEmpty
        case .statuses:
            return !currentResults.statuses.isEmpty
        case .hashtags:
            return !currentResults.hashtags.isEmpty
        }
    }

    var hasAnyDiscoveryContent: Bool {
        !discovery.accounts.isEmpty || !discovery.statuses.isEmpty || !discovery.hashtags.isEmpty
    }

    var showsPaginationSection: Bool {
        if isDiscoveryMode {
            return discovery.isLoadingMoreAccounts && isSectionVisible(.accounts)
        }
        return isLoadingMore || loadMoreFailed
    }

    private func displayHandle(for account: Account) -> String {
        let handle = account.acct.isEmpty ? account.username : account.acct
        return "@\(handle)"
    }

    private func normalizedInlineText(_ raw: String) -> String {
        let collapsedWhitespace = raw.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedPreviewText(_ raw: String) -> String {
        let trimmed = normalizedInlineText(raw)
        return trimmed.isEmpty ? MoroL10n.Search.noTextContent : trimmed
    }

    private func accountNotePreview(for account: Account) -> String? {
        let note = account.notePreviewText
        return note.isEmpty ? nil : note
    }

    func rowContent(for row: Row) -> SearchResultLineCell.ContentModel {
        switch row {
        case .account(let account):
            return SearchResultLineCell.ContentModel(
                kind: .account,
                avatarURL: account.avatarURL,
                title: account.displayNameFormatted,
                subtitle: displayHandle(for: account),
                body: accountNotePreview(for: account),
                iconName: nil,
                iconTintColor: nil,
                account: account
            )

        case .status(let wrappedStatus):
            let status = wrappedStatus.displayStatus
            return SearchResultLineCell.ContentModel(
                kind: .status,
                avatarURL: status.account.avatarURL,
                title: status.account.displayNameFormatted,
                subtitle: "\(displayHandle(for: status.account)) · \(DateFormatting.relativeString(for: status.createdAt))",
                body: normalizedPreviewText(statusPreviewText(for: status)),
                iconName: nil,
                iconTintColor: nil
            )

        case .hashtag(let tag):
            return SearchResultLineCell.ContentModel(
                kind: .hashtag,
                avatarURL: nil,
                title: "#\(tag.name)",
                subtitle: tag.activitySummary ?? MoroL10n.Search.hashtagFallback,
                body: nil,
                iconName: "number",
                iconTintColor: nil
            )
        }
    }

    private func setupUI() {
        view.backgroundColor = appliedTheme.uiKitPalette.canvasBackground

        searchBar.translatesAutoresizingMaskIntoConstraints = false
        scopeControl.translatesAutoresizingMaskIntoConstraints = false
        scopeMenuButton.translatesAutoresizingMaskIntoConstraints = false
        tableView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(searchBar)
        view.addSubview(scopeControl)
        view.addSubview(scopeMenuButton)
        view.addSubview(tableView)

        scopeHeightConstraint = scopeControl.heightAnchor.constraint(equalToConstant: 40)

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: SearchLayoutMetrics.searchBarOuterHorizontalInset
            ),
            searchBar.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -SearchLayoutMetrics.searchBarOuterHorizontalInset
            ),
            searchBar.heightAnchor.constraint(equalToConstant: 46),

            scopeControl.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            scopeControl.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: SearchLayoutMetrics.contentHorizontalInset
            ),
            scopeControl.trailingAnchor.constraint(
                equalTo: view.trailingAnchor,
                constant: -SearchLayoutMetrics.contentHorizontalInset
            ),
            scopeHeightConstraint,

            scopeMenuButton.topAnchor.constraint(equalTo: scopeControl.topAnchor),
            scopeMenuButton.leadingAnchor.constraint(equalTo: scopeControl.leadingAnchor),
            scopeMenuButton.trailingAnchor.constraint(equalTo: scopeControl.trailingAnchor),
            scopeMenuButton.bottomAnchor.constraint(equalTo: scopeControl.bottomAnchor),

            tableView.topAnchor.constraint(equalTo: scopeControl.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func setupSearchBar() {
        let palette = appliedTheme.uiKitPalette
        searchBar.searchBarStyle = .minimal
        searchBar.placeholder = MoroL10n.Search.placeholder
        searchBar.delegate = self
        searchBar.tintColor = palette.primary
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.searchTextField.autocorrectionType = .no
        searchBar.searchTextField.spellCheckingType = .no
        searchBar.searchTextField.returnKeyType = .search
        searchBar.searchTextField.enablesReturnKeyAutomatically = true
        searchBar.searchTextField.backgroundColor = palette.surfaceSubtle
        searchBar.searchTextField.textColor = palette.textPrimary
        searchBar.searchTextField.layer.cornerRadius = 12
        searchBar.searchTextField.layer.cornerCurve = .continuous
        searchBar.searchTextField.layer.masksToBounds = true
        applySearchChromeSizing(palette: palette)
        setCancelButtonVisible(false)
    }

    private func applySearchChromeSizing(palette: MoroUIKitThemePalette) {
        searchBar.searchTextField.font = chromeFont(
            palette: palette,
            textStyle: .body,
            maximumPointSize: SearchLayoutMetrics.maximumSearchFieldPointSize
        )
        if let glassIconView = searchBar.searchTextField.leftView as? UIImageView {
            glassIconView.tintColor = palette.textSecondary
            glassIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
                pointSize: SearchLayoutMetrics.searchGlyphPointSize,
                weight: .regular
            )
        }
        if let clearButton = searchBar.searchTextField.value(forKey: "clearButton") as? UIButton {
            clearButton.tintColor = palette.textSecondary
            clearButton.setPreferredSymbolConfiguration(
                UIImage.SymbolConfiguration(
                    pointSize: SearchLayoutMetrics.clearGlyphPointSize,
                    weight: .semibold
                ),
                forImageIn: .normal
            )
        }
    }

    private func setupScopeControl() {
        let palette = appliedTheme.uiKitPalette
        scopeControl.selectedSegmentIndex = Scope.all.rawValue
        scopeControl.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        scopeControl.isHidden = false
        scopeControl.backgroundColor = .clear
        scopeControl.selectedSegmentTintColor = .clear
        scopeControl.setBackgroundImage(UIImage(), for: .normal, barMetrics: .default)
        scopeControl.setBackgroundImage(UIImage(), for: .selected, barMetrics: .default)
        scopeControl.setBackgroundImage(UIImage(), for: .highlighted, barMetrics: .default)
        scopeControl.setDividerImage(UIImage(), forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)
        scopeControl.setTitleTextAttributes([
            .font: chromeFont(
                palette: palette,
                textStyle: .subheadline,
                maximumPointSize: SearchLayoutMetrics.maximumScopePointSize
            ),
            .foregroundColor: palette.textSecondary,
        ], for: .normal)
        scopeControl.setTitleTextAttributes([
            .font: chromeFont(
                palette: palette,
                textStyle: .subheadline,
                weight: .semibold,
                maximumPointSize: SearchLayoutMetrics.maximumScopePointSize
            ),
            .foregroundColor: palette.textPrimary,
        ], for: .selected)

        scopeIndicatorView.backgroundColor = palette.textPrimary
        scopeIndicatorView.layer.cornerRadius = 1
        scopeIndicatorView.isUserInteractionEnabled = false
        scopeControl.addSubview(scopeIndicatorView)

        scopeMenuButton.contentHorizontalAlignment = .center
        scopeMenuButton.showsMenuAsPrimaryAction = true
        scopeMenuButton.isHidden = true
        updateScopePresentation(palette: palette)
    }

    private func updateScopePresentation(palette: MoroUIKitThemePalette? = nil) {
        guard isViewLoaded else { return }

        let resolvedPalette = palette ?? appliedTheme.uiKitPalette
        let usesMenu = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
        scopeControl.isHidden = usesMenu
        scopeIndicatorView.isHidden = usesMenu
        scopeMenuButton.isHidden = !usesMenu
        scopeHeightConstraint.constant = usesMenu ? 60 : 40

        guard usesMenu else { return }

        var configuration = UIButton.Configuration.plain()
        configuration.title = selectedScope.title
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            pointSize: 12,
            weight: .semibold
        )
        configuration.baseForegroundColor = resolvedPalette.textPrimary
        configuration.titleLineBreakMode = .byTruncatingTail
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            incoming in
            var outgoing = incoming
            outgoing.font = self.chromeFont(
                palette: resolvedPalette,
                textStyle: .headline,
                weight: .semibold,
                maximumPointSize: SearchLayoutMetrics.maximumSearchFieldPointSize
            )
            return outgoing
        }
        scopeMenuButton.configuration = configuration
        scopeMenuButton.menu = UIMenu(children: Scope.allCases.map { scope in
            UIAction(
                title: scope.title,
                image: UIImage(systemName: scope == selectedScope ? "checkmark" : "circle"),
                state: scope == selectedScope ? .on : .off
            ) { [weak self] _ in
                self?.selectScope(scope)
            }
        })
        scopeMenuButton.accessibilityLabel = selectedScope.title
    }

    private func chromeFont(
        palette: MoroUIKitThemePalette,
        textStyle: UIFont.TextStyle,
        weight: UIFont.Weight = .regular,
        maximumPointSize: CGFloat
    ) -> UIFont {
        let preferredFont = palette.font(forTextStyle: textStyle, weight: weight)
        guard UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory else {
            return preferredFont
        }
        return UIFont.systemFont(
            ofSize: min(preferredFont.pointSize, maximumPointSize),
            weight: weight
        )
    }

    private func layoutScopeIndicator() {
        guard scopeControl.numberOfSegments > 0,
            scopeControl.selectedSegmentIndex >= 0
        else { return }

        let segmentWidth = scopeControl.bounds.width / CGFloat(scopeControl.numberOfSegments)
        let indicatorWidth: CGFloat = 24
        scopeIndicatorView.frame = CGRect(
            x: segmentWidth * CGFloat(scopeControl.selectedSegmentIndex)
                + (segmentWidth - indicatorWidth) / 2,
            y: scopeControl.bounds.height - 2,
            width: indicatorWidth,
            height: 2
        )
        scopeControl.bringSubviewToFront(scopeIndicatorView)
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.alwaysBounceVertical = true
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.sectionFooterHeight = .leastNormalMagnitude
        tableView.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 12, right: 0)
        tableView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)
        tableView.fillerRowHeight = 0
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 88
        tableView.register(
            SearchResultLineCell.self,
            forCellReuseIdentifier: SearchResultLineCell.reuseIdentifier
        )
        tableView.register(
            SearchResultLineCell.self,
            forCellReuseIdentifier: SearchResultLineCell.accountReuseIdentifier
        )
        tableView.register(
            SearchSectionHeaderView.self,
            forHeaderFooterViewReuseIdentifier: SearchSectionHeaderView.reuseIdentifier
        )
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StateCell")
        tableView.register(SearchLoadingMoreCell.self, forCellReuseIdentifier: SearchLoadingMoreCell.reuseIdentifier)
        refreshControl.addTarget(self, action: #selector(handlePullToRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }

    private func setupScopeSwipeGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleScopeSwipe(_:)))
        swipeLeft.direction = .left
        swipeLeft.numberOfTouchesRequired = 1
        swipeLeft.cancelsTouchesInView = false

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleScopeSwipe(_:)))
        swipeRight.direction = .right
        swipeRight.numberOfTouchesRequired = 1
        swipeRight.cancelsTouchesInView = false

        tableView.addGestureRecognizer(swipeLeft)
        tableView.addGestureRecognizer(swipeRight)
    }

    @objc
    private func focusSearchInput() {
        searchBar.searchTextField.becomeFirstResponder()
    }

    @objc
    private func handleEscapeKey() {
        searchBar.searchTextField.resignFirstResponder()
    }

    @objc
    private func handleScopeSwipe(_ gesture: UISwipeGestureRecognizer) {
        let step: Int
        switch gesture.direction {
        case .left:
            step = 1
        case .right:
            step = -1
        default:
            return
        }
        switchScope(by: step)
    }

    private func switchScope(by step: Int) {
        let currentIndex = scopeControl.selectedSegmentIndex
        let nextIndex = max(0, min(Scope.allCases.count - 1, currentIndex + step))
        guard nextIndex != currentIndex else { return }
        scopeControl.selectedSegmentIndex = nextIndex
        scopeChanged()
    }

    private func selectScope(_ scope: Scope) {
        guard scopeControl.selectedSegmentIndex != scope.rawValue else { return }
        scopeControl.selectedSegmentIndex = scope.rawValue
        scopeChanged()
    }

    @objc
    private func scopeChanged() {
        fireScopeSelectionFeedbackIfNeeded()
        layoutScopeIndicator()
        updateScopePresentation()
        let query = trimmedQuery
        guard !query.isEmpty else {
            if !discovery.hasLoaded {
                loadDiscoveryIfNeeded()
            } else {
                refreshViewState()
            }
            return
        }
        switch triggerPolicy {
        case .searchKeyOnly:
            cancelInFlightSearchRequests()
            if applyCachedResultsForCurrentScope(query: query) {
                return
            }
            prepareForManualSearch(keepResults: false)
            transitionToTypingStateIfNeeded(forceReload: true)
        case .debounceAndSearchKey:
            searchState.markTyping(query: query, scope: selectedScope)
            if query.count >= minimumDebouncedQueryLength {
                startSearch(reset: true, overrideQuery: query)
            } else {
                debounceTask?.cancel()
                pendingSearchQuery = nil
                refreshViewState()
            }
        }
    }

    func scheduleDebouncedSearch(for query: String) {
        debounceTask?.cancel()
        pendingSearchQuery = query
        debounceTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            guard self.pendingSearchQuery == query else { return }
            self.startSearch(reset: true, overrideQuery: query)
        }
    }

    func startSearch(reset: Bool, overrideQuery: String? = nil) {
        let query = (overrideQuery ?? trimmedQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearchState()
            loadDiscoveryIfNeeded()
            return
        }
        pendingSearchQuery = nil
        cancelDiscoveryRequests()
        searchState.query = query
        searchState.scope = selectedScope
        if reset {
            searchState.submitSearch()
        } else {
            searchState.loadMoreIfNeeded()
        }
    }

    /// Re-run the failed load-more page when the user taps the inline retry footer.
    /// startSearch(reset:) clears loadMoreFailed, marks loading, and refreshes the footer.
    func retryLoadMore() {
        searchState.retryLoadMore()
    }

    func clearSearchState() {
        lastRenderSnapshot = nil
        lastRenderedSections = []
        searchState.clearState(scope: selectedScope)
    }

    func prepareForManualSearch(keepResults: Bool) {
        searchState.query = trimmedQuery
        searchState.prepareForManualSearch(scope: selectedScope, keepResults: keepResults)
    }

    func transitionToTypingStateIfNeeded(forceReload: Bool = false) {
        let currentSections = tableView.numberOfSections
        let isTypingMode: Bool
        if case .typing = mode {
            isTypingMode = true
        } else {
            isTypingMode = false
        }
        let shouldReload =
            forceReload
            || !isTypingMode
            || currentSections != 0
        mode = .typing
        sections.removeAll()
        setBackgroundStateView(typingStateView)
        tableView.separatorStyle = .none
        if shouldReload {
            UIView.performWithoutAnimation {
                tableView.reloadData()
            }
        }
        lastRenderSnapshot = RenderSnapshot(
            mode: .typing,
            sectionFingerprints: [],
            isLoadingMore: false,
            loadMoreFailed: false,
            queryIsEmpty: false
        )
        lastRenderedSections = []
    }

    func refreshViewState() {
        let query = trimmedQuery

        if query.isEmpty {
            if discovery.isLoading && !hasVisibleResultContent {
                mode = .loading
            } else if let discoveryError = discovery.errorMessage, !hasVisibleResultContent {
                mode = .error(discoveryError)
            } else if hasVisibleResultContent {
                mode = .results
            } else if discovery.hasLoaded {
                mode = .empty
            } else {
                mode = .placeholder
            }
        } else if isLoading && !hasVisibleResultContent {
            mode = .loading
        } else if let errorMessage, !hasVisibleResultContent {
            mode = .error(errorMessage)
        } else if hasVisibleResultContent {
            mode = .results
        } else if hasSearchedCurrentQuery {
            mode = .empty
        } else {
            mode = .typing
        }

        rebuildSections()

        switch mode {
        case .placeholder:
            setBackgroundStateView(placeholderView)
            tableView.separatorStyle = .none
        case .typing:
            setBackgroundStateView(typingStateView)
            tableView.separatorStyle = .none
        case .loading:
            setBackgroundStateView(loadingStateView)
            tableView.separatorStyle = .none
        case .empty:
            setBackgroundStateView(query.isEmpty ? discoveryEmptyStateView : emptyStateView)
            tableView.separatorStyle = .none
        default:
            setBackgroundStateView(nil)
            tableView.separatorStyle = .none
        }

        let snapshot = RenderSnapshot(
            mode: mode,
            sectionFingerprints: sectionFingerprints(),
            isLoadingMore: showsPaginationSection,
            loadMoreFailed: loadMoreFailed,
            queryIsEmpty: query.isEmpty
        )
        let previousSnapshot = lastRenderSnapshot
        guard snapshot != previousSnapshot else { return }

        if let previousSnapshot {
            if shouldSkipReloadForListlessTransition(from: previousSnapshot, to: snapshot) {
                lastRenderSnapshot = snapshot
                lastRenderedSections = []
                return
            }

            if applyIncrementalResultsTransition(from: previousSnapshot, to: snapshot) {
                lastRenderSnapshot = snapshot
                lastRenderedSections = mode == .results ? sections : []
                return
            }
        }

        lastRenderSnapshot = snapshot
        UIView.performWithoutAnimation {
            tableView.reloadData()
        }
        lastRenderedSections = mode == .results ? sections : []
    }

    private func setBackgroundStateView(_ view: UIView?) {
        let nextStateView = view as? SearchCenterStateView
        let backgroundDidChange = tableView.backgroundView !== view
        if let currentStateView = tableView.backgroundView as? SearchCenterStateView, currentStateView !== nextStateView {
            currentStateView.setAnimationActive(false)
        }

        if backgroundDidChange {
            tableView.backgroundView = view
            if let nextStateView {
                nextStateView.alpha = 0
                UIView.animate(
                    withDuration: 0.18,
                    delay: 0,
                    options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseInOut]
                ) {
                    nextStateView.alpha = 1
                }
            }
        }

        nextStateView?.setAnimationActive(true)

        if backgroundDidChange,
           nextStateView === emptyStateView,
           UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(notification: .layoutChanged, argument: nextStateView)
        }
    }

    private func rebuildSections() {
        sections.removeAll()

        let currentResults = displayedResults

        if isSectionVisible(.accounts), !currentResults.accounts.isEmpty {
            sections.append(
                SectionModel(
                    kind: .accounts,
                    title: sectionTitle(for: .accounts),
                    rows: currentResults.accounts.map(Row.account)
                )
            )
        }

        if isSectionVisible(.statuses), !currentResults.statuses.isEmpty {
            sections.append(
                SectionModel(
                    kind: .statuses,
                    title: sectionTitle(for: .statuses),
                    rows: currentResults.statuses.map(Row.status)
                )
            )
        }

        if isSectionVisible(.hashtags), !currentResults.hashtags.isEmpty {
            sections.append(
                SectionModel(
                    kind: .hashtags,
                    title: sectionTitle(for: .hashtags),
                    rows: currentResults.hashtags.map(Row.hashtag)
                )
            )
        }
    }

    private func isSectionVisible(_ kind: SectionModel.Kind) -> Bool {
        switch selectedScope {
        case .all:
            return true
        case .accounts:
            return kind == .accounts
        case .statuses:
            return kind == .statuses
        case .hashtags:
            return kind == .hashtags
        }
    }

    private func sectionTitle(for kind: SectionModel.Kind) -> String {
        if isDiscoveryMode {
            switch kind {
            case .accounts:
                return MoroL10n.Search.discoverDirectory
            case .statuses:
                return MoroL10n.Search.discoverTrendingPosts
            case .hashtags:
                return MoroL10n.Search.discoverTrendingTags
            }
        }

        switch kind {
        case .accounts:
            return MoroL10n.Search.resultAccounts
        case .statuses:
            return MoroL10n.Search.resultPosts
        case .hashtags:
            return MoroL10n.Search.resultHashtags
        }
    }

    private func statusPreviewText(for status: Status) -> String {
        SearchStatusPreviewCache.shared.text(for: status)
    }

    func cancelInFlightSearchRequests() {
        debounceTask?.cancel()
        pendingSearchQuery = nil
        searchState.cancel()
    }

    func endRefreshingIfNeeded() {
        guard refreshControl.isRefreshing else { return }
        refreshControl.endRefreshing()
    }

    private func applyCachedResultsForCurrentScope(query: String) -> Bool {
        searchState.applyCachedResults(query: query, scope: selectedScope)
    }

    private func sectionFingerprints() -> [Int] {
        sections.map { section in
            var hasher = Hasher()
            hasher.combine(section.kind)
            hasher.combine(section.title)
            hasher.combine(section.rows.count)
            for row in section.rows.prefix(8) {
                switch row {
                case .account(let account):
                    hasher.combine(account.id)
                case .status(let status):
                    hasher.combine(status.id)
                case .hashtag(let tag):
                    hasher.combine(tag.name.lowercased())
                }
            }
            return hasher.finalize()
        }
    }

    private func rowIdentity(_ row: Row) -> String {
        switch row {
        case .account(let account):
            return "a:\(account.id)"
        case .status(let status):
            return "s:\(status.id)"
        case .hashtag(let tag):
            return "t:\(tag.name.lowercased())"
        }
    }

    private func isListlessMode(_ mode: ViewMode) -> Bool {
        switch mode {
        case .placeholder, .typing, .loading, .empty:
            return true
        case .error, .results:
            return false
        }
    }

    private func shouldSkipReloadForListlessTransition(
        from oldSnapshot: RenderSnapshot,
        to newSnapshot: RenderSnapshot
    ) -> Bool {
        isListlessMode(oldSnapshot.mode) && isListlessMode(newSnapshot.mode)
    }

    private func applyIncrementalResultsTransition(
        from oldSnapshot: RenderSnapshot,
        to newSnapshot: RenderSnapshot
    ) -> Bool {
        guard case .results = oldSnapshot.mode, case .results = newSnapshot.mode else { return false }

        let oldSections = lastRenderedSections
        let newSections = sections
        guard oldSections.count == newSections.count else { return false }

        let expectedOldSectionCount = oldSections.count + (oldSnapshot.isLoadingMore ? 1 : 0)
        guard tableView.numberOfSections == expectedOldSectionCount else {
            return false
        }

        if oldSnapshot.sectionFingerprints == newSnapshot.sectionFingerprints {
            guard oldSnapshot.isLoadingMore != newSnapshot.isLoadingMore else { return false }
            return applyLoadingSectionTransition(
                oldLoading: oldSnapshot.isLoadingMore,
                newLoading: newSnapshot.isLoadingMore,
                baseSectionCount: newSections.count
            )
        }

        guard let insertedRows = appendedRows(from: oldSections, to: newSections) else {
            return false
        }
        guard !insertedRows.isEmpty || oldSnapshot.isLoadingMore != newSnapshot.isLoadingMore else {
            return false
        }

        UIView.performWithoutAnimation {
            tableView.performBatchUpdates {
                if oldSnapshot.isLoadingMore && !newSnapshot.isLoadingMore {
                    if tableView.numberOfSections > oldSections.count {
                        tableView.deleteSections(IndexSet(integer: oldSections.count), with: .none)
                    }
                } else if !oldSnapshot.isLoadingMore && newSnapshot.isLoadingMore {
                    tableView.insertSections(IndexSet(integer: newSections.count), with: .none)
                }
                if !insertedRows.isEmpty {
                    tableView.insertRows(at: insertedRows, with: .none)
                }
            }
        }
        return true
    }

    private func applyLoadingSectionTransition(
        oldLoading: Bool,
        newLoading: Bool,
        baseSectionCount: Int
    ) -> Bool {
        guard oldLoading != newLoading else { return false }
        let expectedOldSectionCount = baseSectionCount + (oldLoading ? 1 : 0)
        guard tableView.numberOfSections == expectedOldSectionCount else { return false }

        UIView.performWithoutAnimation {
            tableView.performBatchUpdates {
                if oldLoading && !newLoading {
                    guard tableView.numberOfSections > baseSectionCount else { return }
                    tableView.deleteSections(IndexSet(integer: baseSectionCount), with: .none)
                } else if !oldLoading && newLoading {
                    tableView.insertSections(IndexSet(integer: baseSectionCount), with: .none)
                }
            }
        }
        return true
    }

    private func appendedRows(from oldSections: [SectionModel], to newSections: [SectionModel]) -> [IndexPath]? {
        guard oldSections.count == newSections.count else { return nil }
        var inserted: [IndexPath] = []
        var hasGrowth = false

        for sectionIndex in oldSections.indices {
            let oldSection = oldSections[sectionIndex]
            let newSection = newSections[sectionIndex]
            guard oldSection.kind == newSection.kind else { return nil }
            guard newSection.rows.count >= oldSection.rows.count else { return nil }

            for rowIndex in 0..<oldSection.rows.count {
                guard rowIdentity(oldSection.rows[rowIndex]) == rowIdentity(newSection.rows[rowIndex]) else {
                    return nil
                }
            }

            guard newSection.rows.count > oldSection.rows.count else { continue }
            hasGrowth = true
            for rowIndex in oldSection.rows.count..<newSection.rows.count {
                inserted.append(IndexPath(row: rowIndex, section: sectionIndex))
            }
        }

        return hasGrowth ? inserted : []
    }

    func setCancelButtonVisible(_ visible: Bool) {
        guard isCancelButtonVisible != visible else { return }
        isCancelButtonVisible = visible
        searchBar.setShowsCancelButton(visible, animated: false)
    }

    private func fireScopeSelectionFeedbackIfNeeded() {
        let selectedIndex = scopeControl.selectedSegmentIndex
        guard selectedIndex != lastScopeSelectionIndex else { return }
        lastScopeSelectionIndex = selectedIndex
        scopeSelectionFeedback.selectionChanged()
        scopeSelectionFeedback.prepare()
    }

    @objc
    private func handlePullToRefresh() {
        if trimmedQuery.isEmpty {
            loadDiscoveryIfNeeded(forceRefresh: true)
        } else {
            debounceTask?.cancel()
            pendingSearchQuery = nil
            startSearch(reset: true)
        }
    }
}
#endif
