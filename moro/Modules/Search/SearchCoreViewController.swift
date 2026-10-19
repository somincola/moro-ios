//
//  SearchCoreViewController.swift
//  moro
//
//  Search controller lifecycle, rendering, and query orchestration.
//

import SwiftUI
import Combine
#if os(iOS)
import UIKit

@MainActor
final class SearchCoreViewController: UIViewController {
    typealias Scope = SearchViewModel.Scope

    struct SectionModel {
        enum Kind: Hashable {
            case accounts
            case statuses
            case hashtags
        }

        let kind: Kind
        let rows: [Row]
    }

    enum Row {
        case account(Account)
        case status(Status)
        case hashtag(SearchTag)
    }

    enum ViewMode: Equatable {
        case placeholder
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
        /// False when the accounts are server suggestions, which have no further pages.
        var accountsArePaged = true
    }

    /// One part of the discovery page: what loaded, or why it didn't.
    struct DiscoveryResult<Value> {
        let value: Value?
        let error: Error?
    }

    let apiClient: MastodonAPI
    let searchState: SearchViewModel
    private let initialQuery: String?
    private let initialScope: Scope
    let library: SearchLibraryStore
    var interaction = SearchInteractionState()
    var discoveryOffset: CGPoint = .zero
    var discoveryScope: Scope = .accounts
    private(set) var allowsSearchFocus = false
    var appliedTheme: MoroTheme

    typealias PollVoteHandler = (String, [Int]) async -> Bool
    var makeStatusView: ((Status, @escaping PollVoteHandler) -> AnyView)?
    private var feedSubscription: AnyCancellable?

    var onOpenProfile: ((Account) -> Void)?
    var onOpenStatus: ((Status) -> Void)?
    var onOpenHashtag: ((String) -> Void)?
    var onEntryStateChanged: ((Bool) -> Void)?

    let initialPageSize = 20
    let paginationPageSize = 40

    let searchBar = UISearchBar(frame: .zero)
    private var searchBarHeightConstraint: NSLayoutConstraint!
    private var searchFieldHeightConstraint: NSLayoutConstraint!
    let cancelEntryButton = UIButton(type: .system)
    var searchTrailingRegular: NSLayoutConstraint!
    var searchTrailingWithCancel: NSLayoutConstraint!
    let scopeControl = UISegmentedControl(items: Scope.exploreScopes.map(\.title))
    private let scopeIndicatorView = UIView()
    private let scopeMenuButton = SearchScopeMenuButton(type: .system)
    let tableView = UITableView(frame: .zero, style: .plain)
    let refreshControl = UIRefreshControl()
    /// Highest Explore re-tap already handled; earlier events are never replayed.
    private var handledTabReselection = 0
    private var scopeHeightConstraint: NSLayoutConstraint!
    let entryHost = UIHostingController(rootView: AnyView(EmptyView()))

    private lazy var placeholderView: SearchLandingPlaceholderView = {
        let container = SearchLandingPlaceholderView()
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(focusSearchInput))
        container.addGestureRecognizer(tapGesture)
        return container
    }()

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
    private var isCancelButtonVisible = false
    private let scopeSelectionFeedback = UISelectionFeedbackGenerator()
    private var lastScopeSelectionIndex = 0
    private var lastRenderSnapshot: RenderSnapshot?
    private var lastRenderedSections: [SectionModel] = []
    var discovery = DiscoveryState()
    var discoveryTask: Task<Void, Never>?
    var discoveryRequestID = UUID()

    init(apiClient: MastodonAPI, initialQuery: String?, theme: MoroTheme,
         accountKey: String = "no-active-session", initialScope: Scope = .accounts,
         library: SearchLibraryStore? = nil) {
        self.apiClient = apiClient
        self.searchState = SearchViewModel(apiClient: apiClient, initialQuery: initialQuery)
        self.initialQuery = initialQuery
        self.initialScope = initialScope.exploreScope
        self.library = library ?? SearchLibraryStore(accountKey: accountKey)
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
        scopeControl.selectedSegmentIndex = initialScope.segmentIndex
        setupEntryUI()
        setupTableView()
        setupScopeSwipeGestures()
        apply(theme: appliedTheme)
        feedSubscription = FeedCoordinator.shared.updates.sink { [weak self] update in
            self?.incorporatePostUpdate(update)
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
                submitQuery(trimmed, scope: initialScope)
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
        // UIKit may try to restore the previous input responder while popping a route.
        // A list page must stay a list until the user explicitly focuses the field.
        if interaction.page != .entry { searchBar.searchTextField.resignFirstResponder() }
        allowsSearchFocus = true
        scopeSelectionFeedback.prepare()
        library.reload()
        updateSearchChrome()
        if interaction.page == .entry { updateEntryContent() }
    }

    override func viewWillAppear(_ animated: Bool) {
        allowsSearchFocus = false
        super.viewWillAppear(animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        prepareForNavigation()
        super.viewWillDisappear(animated)
    }

    func prepareForNavigation() {
        allowsSearchFocus = false
        view.endEditing(true)
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
        cancelEntryButton.setTitleColor(palette.textPrimary, for: .normal)
        cancelEntryButton.titleLabel?.font = chromeFont(palette: palette, textStyle: .body, maximumPointSize: SearchLayoutMetrics.maximumSearchFieldPointSize)
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

        refreshVisibleStatusRows()
        updateSearchChrome()
        if interaction.page == .entry { updateEntryContent() }
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
        discoveryTask?.cancel()
    }

    var trimmedQuery: String {
        interaction.submittedQuery
    }

    var selectedScope: Scope {
        let index = scopeControl.selectedSegmentIndex
        return Scope.exploreScopes.indices.contains(index) ? Scope.exploreScopes[index] : .accounts
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
        case .all, .accounts:
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

    private func accountNotePreview(for account: Account) -> String? {
        let note = account.notePreviewText
        return note.isEmpty ? nil : note
    }

    func rowContent(for row: Row) -> SearchResultLineCell.ContentModel? {
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

        case .status:
            return nil // Posts use TimelinePostRow, never a text preview cell.

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
        setupCancelEntryButton()
        view.addSubview(scopeControl)
        view.addSubview(scopeMenuButton)
        view.addSubview(tableView)

        scopeHeightConstraint = scopeControl.heightAnchor.constraint(equalToConstant: 40)
        searchBarHeightConstraint = searchBar.heightAnchor.constraint(
            equalToConstant: SearchLayoutMetrics.searchFieldHeight
                + SearchLayoutMetrics.searchFieldVerticalInset * 2
        )

        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchBar.leadingAnchor.constraint(
                equalTo: view.leadingAnchor,
                constant: SearchLayoutMetrics.searchBarOuterHorizontalInset
            ),
            searchTrailingRegular,
            searchBarHeightConstraint,

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
        searchBar.setSearchFieldBackgroundImage(UIImage(), for: .normal)
        searchBar.placeholder = MoroL10n.Search.placeholder
        searchBar.delegate = self
        searchBar.tintColor = palette.primary
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.searchTextField.autocorrectionType = .no
        searchBar.searchTextField.spellCheckingType = .no
        searchBar.searchTextField.accessibilityIdentifier = "search.input"
        searchBar.searchTextField.returnKeyType = .search
        searchBar.searchTextField.enablesReturnKeyAutomatically = true
        searchBar.searchTextField.backgroundColor = palette.surfaceSubtle
        searchBar.searchTextField.textColor = palette.textPrimary
        searchBar.searchTextField.layer.cornerRadius = SearchLayoutMetrics.searchFieldCornerRadius
        searchBar.searchTextField.layer.cornerCurve = .continuous
        searchBar.searchTextField.layer.masksToBounds = true
        // UIKit's default field can overflow a compact bar on newer system versions.
        searchBar.searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchFieldHeightConstraint = searchBar.searchTextField.heightAnchor.constraint(
            equalToConstant: SearchLayoutMetrics.searchFieldHeight
        )
        NSLayoutConstraint.activate([
            searchFieldHeightConstraint,
            searchBar.searchTextField.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchBar.searchTextField.leadingAnchor.constraint(
                equalTo: searchBar.leadingAnchor,
                constant: SearchLayoutMetrics.searchBarInternalFieldInset
            ),
            searchBar.searchTextField.trailingAnchor.constraint(
                equalTo: searchBar.trailingAnchor,
                constant: -SearchLayoutMetrics.searchBarInternalFieldInset
            ),
        ])
        applySearchChromeSizing(palette: palette)
        setCancelButtonVisible(false)
    }

    private func applySearchChromeSizing(palette: MoroUIKitThemePalette) {
        let font = chromeFont(
            palette: palette,
            textStyle: .body,
            maximumPointSize: SearchLayoutMetrics.maximumSearchFieldPointSize
        )
        searchBar.searchTextField.font = font
        let fieldHeight = max(SearchLayoutMetrics.searchFieldHeight, ceil(font.lineHeight) + 12)
        searchFieldHeightConstraint.constant = fieldHeight
        searchBarHeightConstraint.constant = fieldHeight
            + SearchLayoutMetrics.searchFieldVerticalInset * 2
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
        scopeControl.accessibilityIdentifier = "search.scope"
        scopeMenuButton.accessibilityIdentifier = "search.scopeMenu"
        let palette = appliedTheme.uiKitPalette
        scopeControl.selectedSegmentIndex = Scope.accounts.segmentIndex
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

        scopeMenuButton.onMenuWillDisplay = { [weak self] in
            self?.allowsSearchFocus = false
        }
        scopeMenuButton.onMenuDidEnd = { [weak self] in
            guard let self else { return }
            self.searchBar.searchTextField.resignFirstResponder()
            self.allowsSearchFocus = self.viewIfLoaded?.window != nil
        }
        scopeMenuButton.contentHorizontalAlignment = .center
        scopeMenuButton.showsMenuAsPrimaryAction = true
        scopeMenuButton.isHidden = true
        updateScopePresentation(palette: palette)
    }

    func updateScopePresentation(palette: MoroUIKitThemePalette? = nil) {
        guard isViewLoaded else { return }

        let resolvedPalette = palette ?? appliedTheme.uiKitPalette
        let isEntry = interaction.page == .entry
        let usesMenu = appliedTheme.dynamicTypeSize.isAccessibilitySize
        scopeControl.isHidden = isEntry || usesMenu
        scopeIndicatorView.isHidden = isEntry || usesMenu
        scopeMenuButton.isHidden = isEntry || !usesMenu
        scopeHeightConstraint.constant = isEntry ? 0 : (usesMenu ? 60 : 40)

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
        scopeMenuButton.menu = UIMenu(children: Scope.exploreScopes.map { scope in
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
        guard appliedTheme.dynamicTypeSize.isAccessibilitySize else {
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
        tableView.accessibilityIdentifier = "search.results"
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
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SearchTimelinePostCell")
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
        swipeLeft.delegate = self

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleScopeSwipe(_:)))
        swipeRight.direction = .right
        swipeRight.numberOfTouchesRequired = 1
        swipeRight.cancelsTouchesInView = false
        swipeRight.delegate = self

        tableView.addGestureRecognizer(swipeLeft)
        tableView.addGestureRecognizer(swipeRight)
    }

    @objc
    private func focusSearchInput() {
        searchBar.searchTextField.becomeFirstResponder()
    }

    @objc
    private func handleEscapeKey() {
        cancelSearchEntry()
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
        let nextIndex = max(0, min(Scope.exploreScopes.count - 1, currentIndex + step))
        guard nextIndex != currentIndex else { return }
        scopeControl.selectedSegmentIndex = nextIndex
        scopeChanged()
    }

    private func selectScope(_ scope: Scope) {
        guard scopeControl.selectedSegmentIndex != scope.segmentIndex else { return }
        scopeControl.selectedSegmentIndex = scope.segmentIndex
        scopeChanged()
    }

    @objc
    private func scopeChanged() {
        guard interaction.page != .entry else { return }
        fireScopeSelectionFeedbackIfNeeded()
        layoutScopeIndicator()
        updateScopePresentation()
        if trimmedQuery.isEmpty {
            loadDiscoveryIfNeeded()
            refreshViewState()
        } else {
            interaction.submit(trimmedQuery, scope: selectedScope)
            library.record(query: trimmedQuery, scope: selectedScope)
            updateSearchChrome()
            startSearch(reset: true)
            tableView.setContentOffset(CGPoint(x: 0, y: -tableView.adjustedContentInset.top), animated: false)
        }
    }

    func startSearch(reset: Bool, overrideQuery: String? = nil) {
        let query = (overrideQuery ?? trimmedQuery).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            clearSearchState()
            loadDiscoveryIfNeeded()
            return
        }
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

    func refreshViewState() {
        guard interaction.page != .entry else {
            updateEntryContent()
            return
        }
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
            mode = .loading
        }

        rebuildSections()

        switch mode {
        case .placeholder:
            setBackgroundStateView(placeholderView)
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
        guard snapshot != previousSnapshot else {
            // IDs and row counts may stay unchanged after edits, poll votes or reactions.
            refreshVisibleStatusRows()
            lastRenderedSections = sections
            return
        }

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
                    rows: currentResults.accounts.map(Row.account)
                )
            )
        }

        if isSectionVisible(.statuses), !currentResults.statuses.isEmpty {
            sections.append(
                SectionModel(
                    kind: .statuses,
                    rows: currentResults.statuses.map(Row.status)
                )
            )
        }

        if isSectionVisible(.hashtags), !currentResults.hashtags.isEmpty {
            sections.append(
                SectionModel(
                    kind: .hashtags,
                    rows: currentResults.hashtags.map(Row.hashtag)
                )
            )
        }
    }

    private func isSectionVisible(_ kind: SectionModel.Kind) -> Bool {
        switch selectedScope {
        case .all, .accounts:
            return kind == .accounts
        case .statuses:
            return kind == .statuses
        case .hashtags:
            return kind == .hashtags
        }
    }

    func cancelInFlightSearchRequests() {
        searchState.cancel()
    }

    func endRefreshingIfNeeded() {
        guard refreshControl.isRefreshing else { return }
        refreshControl.endRefreshing()
    }

    private func sectionFingerprints() -> [Int] {
        sections.map { section in
            var hasher = Hasher()
            hasher.combine(section.kind)
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
        case .placeholder, .loading, .empty:
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
        // UISearchBar disables its own cancel control when it resigns first responder.
        // Entry remains active without a keyboard, so this control has its own lifetime.
        cancelEntryButton.isHidden = !visible
        NSLayoutConstraint.deactivate([searchTrailingRegular, searchTrailingWithCancel])
        NSLayoutConstraint.activate([visible ? searchTrailingWithCancel : searchTrailingRegular])
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
            startSearch(reset: true)
        }
    }

    // MARK: - Tab re-tap

    func markTabReselectionSeen(_ event: TabReselection?) {
        handledTabReselection = max(handledTabReselection, event?.sequence ?? 0)
    }

    /// Same as the other root tabs: away from the top, scroll up; at the top, refresh with
    /// the visible system indicator. Ignored while the search field owns the screen.
    func handleTabReselection(_ event: TabReselection?) {
        guard let event, event.sequence > handledTabReselection else { return }
        handledTabReselection = event.sequence
        guard event.tab == .explore, interaction.page != .entry, viewIfLoaded?.window != nil else { return }

        let topOffset = -tableView.adjustedContentInset.top
        if tableView.contentOffset.y > topOffset + 1 {
            tableView.setContentOffset(CGPoint(x: 0, y: topOffset), animated: true)
        } else if !refreshControl.isRefreshing {
            MoroRefreshFeedback.armed()
            refreshControl.beginRefreshing()
            tableView.setContentOffset(
                CGPoint(x: 0, y: topOffset - refreshControl.frame.height), animated: true)
            handlePullToRefresh()
        }
    }
}
#endif
