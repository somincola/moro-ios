//
//  SearchCells.swift
//  moro
//
//  UIKit search state views, reusable cells, and row presentation helpers.
//

import SwiftUI
#if os(iOS)
import UIKit

final class SearchLandingPlaceholderView: UIView {
    private let iconBubble = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func apply(theme: MoroTheme) {
        let palette = theme.uiKitPalette
        backgroundColor = .clear
        iconBubble.backgroundColor = .clear
        titleLabel.font = palette.font(forTextStyle: .title3, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        subtitleLabel.font = palette.font(forTextStyle: .callout)
        subtitleLabel.textColor = palette.textSecondary
    }

    private func setupViews() {
        let palette = MoroTheme().uiKitPalette
        backgroundColor = .clear
        iconBubble.translatesAutoresizingMaskIntoConstraints = false
        iconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        iconBubble.backgroundColor = .clear

        iconView.image = UIImage(named: "ExploreEmptyMascot")?.withRenderingMode(.alwaysOriginal)
        iconView.contentMode = .scaleAspectFit

        titleLabel.font = palette.font(forTextStyle: .title3, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.text = MoroL10n.Search.exploreTitle
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = palette.font(forTextStyle: .callout)
        subtitleLabel.textColor = palette.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.text = MoroL10n.Search.exploreSubtitle
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.addArrangedSubview(iconBubble)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)

        addSubview(stackView)
        iconBubble.addSubview(iconView)

        NSLayoutConstraint.activate([
            iconBubble.widthAnchor.constraint(equalToConstant: 128),
            iconBubble.heightAnchor.constraint(equalToConstant: 128),

            iconView.centerXAnchor.constraint(equalTo: iconBubble.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBubble.centerYAnchor),
            iconView.widthAnchor.constraint(equalTo: iconBubble.widthAnchor),
            iconView.heightAnchor.constraint(equalTo: iconBubble.heightAnchor),

            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            subtitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stackView.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: stackView.trailingAnchor),
        ])
    }
}

final class SearchCenterStateView: UIView {
    enum AnimationStyle {
        case none
        case typingCursor
        case searchingIndicator
    }

    private let iconView = UIImageView()
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let stackView = UIStackView()
    private let animationStyle: AnimationStyle
    private let showsIndicator: Bool
    private let usesAssetImage: Bool
    private var isAnimationActive = false

    private let typingOpacityAnimationKey = "search.state.typing.opacity"
    private let typingFloatAnimationKey = "search.state.typing.float"
    private let searchingScaleAnimationKey = "search.state.loading.scale"
    private let searchingOpacityAnimationKey = "search.state.loading.opacity"

    init(
        iconName: String?,
        assetName: String? = nil,
        imageSize: CGSize = CGSize(width: 30, height: 30),
        title: String?,
        subtitle: String? = nil,
        showsIndicator: Bool,
        animationStyle: AnimationStyle
    ) {
        self.animationStyle = animationStyle
        self.showsIndicator = showsIndicator
        usesAssetImage = assetName != nil
        super.init(frame: .zero)
        setupViews(
            iconName: iconName,
            assetName: assetName,
            imageSize: imageSize,
            title: title,
            subtitle: subtitle,
            showsIndicator: showsIndicator
        )
    }

    required init?(coder: NSCoder) {
        animationStyle = .none
        showsIndicator = false
        usesAssetImage = false
        super.init(coder: coder)
        setupViews(
            iconName: "magnifyingglass",
            assetName: nil,
            imageSize: CGSize(width: 30, height: 30),
            title: nil,
            subtitle: nil,
            showsIndicator: false
        )
    }

    func apply(theme: MoroTheme) {
        let palette = theme.uiKitPalette
        if !usesAssetImage {
            iconView.tintColor = palette.textSecondary
        }
        indicator.color = palette.textSecondary
        titleLabel.font = palette.font(forTextStyle: .callout, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        subtitleLabel.font = palette.font(forTextStyle: .footnote)
        subtitleLabel.textColor = palette.textSecondary
    }

    private func setupViews(
        iconName: String?,
        assetName: String?,
        imageSize: CGSize,
        title: String?,
        subtitle: String?,
        showsIndicator: Bool
    ) {
        let palette = MoroTheme().uiKitPalette
        backgroundColor = .clear
        iconView.translatesAutoresizingMaskIntoConstraints = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        if let assetName {
            iconView.image = UIImage(named: assetName)?.withRenderingMode(.alwaysOriginal)
            iconView.contentMode = .scaleAspectFit
        } else if let iconName {
            iconView.image = UIImage(systemName: iconName)
            iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold)
            iconView.tintColor = palette.textSecondary
            iconView.contentMode = .scaleAspectFit
        }

        titleLabel.font = palette.font(forTextStyle: .callout, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.text = title
        titleLabel.numberOfLines = 2
        titleLabel.isHidden = title == nil
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = palette.font(forTextStyle: .footnote)
        subtitleLabel.textColor = palette.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 3
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.adjustsFontForContentSizeCategory = true

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10

        if showsIndicator {
            stackView.addArrangedSubview(indicator)
        }
        if assetName != nil || iconName != nil {
            stackView.addArrangedSubview(iconView)
        }
        if title != nil {
            stackView.addArrangedSubview(titleLabel)
        }
        if subtitle != nil {
            stackView.addArrangedSubview(subtitleLabel)
            stackView.setCustomSpacing(5, after: titleLabel)
        }

        iconView.isAccessibilityElement = false
        titleLabel.isAccessibilityElement = false
        subtitleLabel.isAccessibilityElement = false
        let accessibilityText = [title, subtitle].compactMap { $0 }.joined(separator: ". ")
        isAccessibilityElement = !accessibilityText.isEmpty
        accessibilityLabel = accessibilityText

        addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
        ])
        if assetName != nil {
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: imageSize.width),
                iconView.heightAnchor.constraint(equalToConstant: imageSize.height),
            ])
        }
    }

    func setAnimationActive(_ active: Bool) {
        guard active != isAnimationActive else { return }
        isAnimationActive = active

        if !active {
            stopIndicatorIfNeeded()
            iconView.layer.removeAnimation(forKey: typingOpacityAnimationKey)
            iconView.layer.removeAnimation(forKey: typingFloatAnimationKey)
            indicator.layer.removeAnimation(forKey: searchingScaleAnimationKey)
            indicator.layer.removeAnimation(forKey: searchingOpacityAnimationKey)
            return
        }

        startIndicatorIfNeeded()
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        switch animationStyle {
        case .none:
            break
        case .typingCursor:
            addTypingCursorAnimationIfNeeded()
        case .searchingIndicator:
            addSearchingIndicatorAnimationIfNeeded()
        }
    }

    private func startIndicatorIfNeeded() {
        guard showsIndicator else { return }
        indicator.startAnimating()
    }

    private func stopIndicatorIfNeeded() {
        guard showsIndicator else { return }
        indicator.stopAnimating()
    }

    private func addTypingCursorAnimationIfNeeded() {
        guard iconView.layer.animation(forKey: typingOpacityAnimationKey) == nil else { return }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.35
        opacity.toValue = 1
        opacity.duration = 0.63
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconView.layer.add(opacity, forKey: typingOpacityAnimationKey)

        let float = CABasicAnimation(keyPath: "transform.translation.y")
        float.fromValue = 0.9
        float.toValue = -0.9
        float.duration = 0.63
        float.autoreverses = true
        float.repeatCount = .infinity
        float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        iconView.layer.add(float, forKey: typingFloatAnimationKey)
    }

    private func addSearchingIndicatorAnimationIfNeeded() {
        guard showsIndicator else { return }
        guard indicator.layer.animation(forKey: searchingScaleAnimationKey) == nil else { return }

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.96
        scale.toValue = 1.03
        scale.duration = 0.68
        scale.autoreverses = true
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        indicator.layer.add(scale, forKey: searchingScaleAnimationKey)

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.84
        opacity.toValue = 1
        opacity.duration = 0.68
        opacity.autoreverses = true
        opacity.repeatCount = .infinity
        opacity.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        indicator.layer.add(opacity, forKey: searchingOpacityAnimationKey)
    }
}

final class SearchLoadingMoreCell: UITableViewCell {
    static let reuseIdentifier = "LoadingMoreCell"

    private let indicator = UIActivityIndicatorView(style: .medium)
    private let retryButton = UIButton(type: .system)
    private var onRetry: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func apply(theme: MoroTheme) {
        let palette = theme.uiKitPalette
        backgroundColor = .clear
        contentView.backgroundColor = palette.surfaceBase
        indicator.color = palette.textSecondary

        guard var configuration = retryButton.configuration else { return }
        configuration.baseForegroundColor = palette.textSecondary
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = palette.font(forTextStyle: .footnote)
            return outgoing
        }
        retryButton.configuration = configuration
    }

    /// Spinner shown while the next page is loading.
    func configureLoading() {
        onRetry = nil
        retryButton.isHidden = true
        indicator.startAnimating()
    }

    /// Tappable "tap to retry" affordance shown after a load-more failure.
    func configureRetry(onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        indicator.stopAnimating()
        retryButton.isHidden = false
    }

    private func setupViews() {
        let palette = MoroTheme().uiKitPalette
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        indicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(indicator)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        var config = UIButton.Configuration.plain()
        config.title = MoroL10n.Common.loadMoreRetry
        config.image = UIImage(systemName: "arrow.clockwise")
        config.imagePadding = 6
        config.baseForegroundColor = palette.textSecondary
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = palette.font(forTextStyle: .footnote)
            return outgoing
        }
        retryButton.configuration = config
        retryButton.addAction(
            UIAction { [weak self] _ in self?.onRetry?() },
            for: .touchUpInside
        )
        contentView.addSubview(retryButton)

        NSLayoutConstraint.activate([
            indicator.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            indicator.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            retryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }
}

final class SearchSectionHeaderView: UITableViewHeaderFooterView {
    static let reuseIdentifier = "SearchSectionHeaderView"

    private let titleLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    func configure(title: String, theme: MoroTheme) {
        titleLabel.text = title
        apply(theme: theme)
    }

    func apply(theme: MoroTheme) {
        let palette = theme.uiKitPalette
        backgroundView?.backgroundColor = palette.canvasBackground
        contentView.backgroundColor = palette.canvasBackground
        titleLabel.font = palette.font(forTextStyle: .caption1, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        titleLabel.numberOfLines = UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory
            ? 0
            : 1
    }

    private func setupViews() {
        let palette = MoroTheme().uiKitPalette
        contentView.backgroundColor = .clear
        contentView.preservesSuperviewLayoutMargins = false
        contentView.directionalLayoutMargins = .zero
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = palette.font(forTextStyle: .caption1, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        // Header trait drives VoiceOver's heading-rotor navigation between sections.
        titleLabel.accessibilityTraits.insert(.header)

        contentView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: SearchLayoutMetrics.contentHorizontalInset
            ),
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            titleLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
        ])
    }
}

final class SearchResultLineCell: UITableViewCell {
    static let reuseIdentifier = "SearchResultLineCell"
    static let accountReuseIdentifier = "SearchAccountResultLineCell"

    enum Kind {
        case account
        case status
        case hashtag
    }

    struct ContentModel {
        let kind: Kind
        let avatarURL: URL?
        let title: String
        let subtitle: String?
        let body: String?
        let iconName: String?
        let iconTintColor: UIColor?
        let account: Account?

        init(
            kind: Kind,
            avatarURL: URL?,
            title: String,
            subtitle: String?,
            body: String?,
            iconName: String?,
            iconTintColor: UIColor?,
            account: Account? = nil
        ) {
            self.kind = kind
            self.avatarURL = avatarURL
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.iconName = iconName
            self.iconTintColor = iconTintColor
            self.account = account
        }
    }

    private let leadingContainer = UIView()
    private let avatarImageView = UIImageView()
    private var avatarLoadTask: Task<Void, Never>?
    private let fallbackIconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let bodyLabel = UILabel()
    private let chevronImageView = UIImageView(image: UIImage(systemName: "chevron.right"))
    private let textStack = UIStackView()
    private let separatorLine = UIView()

    private var leadingWidthConstraint: NSLayoutConstraint?
    private var leadingHeightConstraint: NSLayoutConstraint?
    private var leadingTopConstraint: NSLayoutConstraint?
    private var currentContent: ContentModel?
    private var hostedAccount: Account?
    private var appliedTheme = MoroTheme()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
        setHostedAccountMode(false)
        avatarLoadTask?.cancel()
        avatarImageView.image = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        bodyLabel.text = nil
        subtitleLabel.isHidden = false
        bodyLabel.isHidden = false
        accessibilityLabel = nil
        currentContent = nil
        hostedAccount = nil
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        applyInteractionState(animated: animated)
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        applyInteractionState(animated: animated)
    }

    func configure(with content: ContentModel, theme: MoroTheme) {
        currentContent = content
        appliedTheme = theme
        let palette = theme.uiKitPalette

        if let account = content.account, content.kind == .account {
            configureAccountRow(account: account, theme: theme)
            return
        }

        hostedAccount = nil
        contentConfiguration = nil
        setHostedAccountMode(false)
        titleLabel.text = content.title
        subtitleLabel.text = content.subtitle
        bodyLabel.text = content.body

        subtitleLabel.isHidden = (content.subtitle ?? "").isEmpty
        bodyLabel.isHidden = (content.body ?? "").isEmpty

        let isTagRow = content.kind == .hashtag
        let leadingSize: CGFloat = isTagRow ? 24 : 44
        leadingWidthConstraint?.constant = leadingSize
        leadingHeightConstraint?.constant = leadingSize
        leadingTopConstraint?.constant = isTagRow ? 13 : 12
        leadingContainer.layer.cornerRadius = leadingSize / 2

        if isTagRow {
            avatarImageView.isHidden = true
            fallbackIconView.isHidden = false
            fallbackIconView.image = UIImage(systemName: content.iconName ?? "number")
            fallbackIconView.tintColor = content.iconTintColor ?? palette.textSecondary
            leadingContainer.backgroundColor = (content.iconTintColor ?? palette.textSecondary).withAlphaComponent(0.12)
        } else {
            fallbackIconView.isHidden = true
            avatarImageView.isHidden = false
            leadingContainer.backgroundColor = palette.surfaceSubtle
            avatarImageView.image = UIImage(systemName: "person.crop.circle.fill")
            avatarImageView.tintColor = palette.textTertiary
            if let avatarURL = content.avatarURL {
                avatarLoadTask?.cancel()
                avatarLoadTask = Task { @MainActor [weak self] in
                    guard let image = await ImageCache.shared.load(from: avatarURL),
                        !Task.isCancelled
                    else { return }
                    self?.avatarImageView.image = image
                }
            }
        }

        bodyLabel.numberOfLines = 2

        var components: [String] = [content.title]
        if let subtitle = content.subtitle, !subtitle.isEmpty {
            components.append(subtitle)
        }
        if let body = content.body, !body.isEmpty {
            components.append(body)
        }
        accessibilityLabel = components.joined(separator: "，")
        accessibilityHint = MoroL10n.Search.accessibilityOpenDetail
        accessibilityTraits = .button
        apply(theme: theme)
    }

    func apply(theme: MoroTheme) {
        appliedTheme = theme
        let palette = theme.uiKitPalette

        backgroundColor = .clear
        contentView.backgroundColor = palette.surfaceBase
        titleLabel.font = palette.font(forTextStyle: .subheadline, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        subtitleLabel.font = palette.font(forTextStyle: .caption2)
        subtitleLabel.textColor = palette.textSecondary
        bodyLabel.font = palette.font(forTextStyle: .subheadline)
        bodyLabel.textColor = palette.textSecondary
        chevronImageView.tintColor = palette.textTertiary
        separatorLine.backgroundColor = palette.divider
        separatorLine.alpha = 1

        if let content = currentContent {
            let iconColor = content.iconTintColor ?? palette.textSecondary
            if content.kind == .hashtag {
                fallbackIconView.tintColor = iconColor
                leadingContainer.backgroundColor = iconColor.withAlphaComponent(0.12)
            } else {
                leadingContainer.backgroundColor = palette.surfaceSubtle
                avatarImageView.tintColor = palette.textTertiary
            }
        }

        if let hostedAccount {
            installHostedAccountConfiguration(account: hostedAccount, theme: theme)
        }

        applyInteractionState(animated: false)
    }

    private func configureAccountRow(account: Account, theme: MoroTheme) {
        hostedAccount = account
        setHostedAccountMode(true)

        var components: [String] = [account.displayNameFormatted, "@\(account.acct.isEmpty ? account.username : account.acct)"]
        if !account.notePreviewText.isEmpty {
            components.append(account.notePreviewText)
        }
        accessibilityLabel = components.joined(separator: "，")
        accessibilityHint = MoroL10n.Search.accessibilityOpenDetail
        accessibilityTraits = .button
        apply(theme: theme)
    }

    private func installHostedAccountConfiguration(account: Account, theme: MoroTheme) {
        contentConfiguration = UIHostingConfiguration {
            SearchAccountRowContentView(account: account)
                .moroTheme(theme)
        }
        .margins(.all, 0)
    }

    private func setupViews() {
        let palette = appliedTheme.uiKitPalette
        backgroundColor = .clear
        contentView.backgroundColor = palette.surfaceBase
        selectionStyle = .none

        leadingContainer.translatesAutoresizingMaskIntoConstraints = false
        avatarImageView.translatesAutoresizingMaskIntoConstraints = false
        fallbackIconView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        chevronImageView.translatesAutoresizingMaskIntoConstraints = false
        textStack.translatesAutoresizingMaskIntoConstraints = false
        separatorLine.translatesAutoresizingMaskIntoConstraints = false

        leadingContainer.layer.cornerCurve = .continuous
        leadingContainer.clipsToBounds = true

        avatarImageView.contentMode = .scaleAspectFill
        avatarImageView.clipsToBounds = true

        fallbackIconView.contentMode = .scaleAspectFit
        fallbackIconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            pointSize: 12,
            weight: .semibold
        )

        titleLabel.font = palette.font(forTextStyle: .subheadline, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        titleLabel.numberOfLines = 1
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = palette.font(forTextStyle: .caption2)
        subtitleLabel.textColor = palette.textSecondary
        subtitleLabel.numberOfLines = 1
        subtitleLabel.adjustsFontForContentSizeCategory = true

        bodyLabel.font = palette.font(forTextStyle: .subheadline)
        bodyLabel.textColor = palette.textSecondary
        bodyLabel.numberOfLines = 2
        bodyLabel.adjustsFontForContentSizeCategory = true

        chevronImageView.tintColor = palette.textTertiary
        chevronImageView.contentMode = .scaleAspectFit
        chevronImageView.setContentHuggingPriority(.required, for: .horizontal)
        chevronImageView.setContentCompressionResistancePriority(.required, for: .horizontal)

        textStack.axis = .vertical
        textStack.spacing = 2
        textStack.alignment = .fill
        textStack.addArrangedSubview(titleLabel)
        textStack.addArrangedSubview(subtitleLabel)
        textStack.addArrangedSubview(bodyLabel)

        separatorLine.backgroundColor = palette.divider
        separatorLine.alpha = 1

        contentView.addSubview(leadingContainer)
        leadingContainer.addSubview(avatarImageView)
        leadingContainer.addSubview(fallbackIconView)
        contentView.addSubview(chevronImageView)
        contentView.addSubview(textStack)
        contentView.addSubview(separatorLine)

        leadingWidthConstraint = leadingContainer.widthAnchor.constraint(equalToConstant: 40)
        leadingHeightConstraint = leadingContainer.heightAnchor.constraint(equalToConstant: 40)
        leadingTopConstraint = leadingContainer.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10)

        NSLayoutConstraint.activate([
            leadingContainer.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: SearchLayoutMetrics.contentHorizontalInset
            ),
            leadingTopConstraint!,
            leadingWidthConstraint!,
            leadingHeightConstraint!,

            avatarImageView.leadingAnchor.constraint(equalTo: leadingContainer.leadingAnchor),
            avatarImageView.trailingAnchor.constraint(equalTo: leadingContainer.trailingAnchor),
            avatarImageView.topAnchor.constraint(equalTo: leadingContainer.topAnchor),
            avatarImageView.bottomAnchor.constraint(equalTo: leadingContainer.bottomAnchor),

            fallbackIconView.centerXAnchor.constraint(equalTo: leadingContainer.centerXAnchor),
            fallbackIconView.centerYAnchor.constraint(equalTo: leadingContainer.centerYAnchor),
            fallbackIconView.widthAnchor.constraint(equalToConstant: 13),
            fallbackIconView.heightAnchor.constraint(equalToConstant: 13),

            chevronImageView.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -SearchLayoutMetrics.contentHorizontalInset
            ),
            chevronImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: 7),
            chevronImageView.heightAnchor.constraint(equalToConstant: 12),

            textStack.leadingAnchor.constraint(equalTo: leadingContainer.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: chevronImageView.leadingAnchor, constant: -10),
            textStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 11),
            textStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -11),

            separatorLine.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separatorLine.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separatorLine.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            separatorLine.heightAnchor.constraint(equalToConstant: 0.5),
        ])
    }

    private func setHostedAccountMode(_ isHosted: Bool) {
        leadingContainer.isHidden = isHosted
        textStack.isHidden = isHosted
        chevronImageView.isHidden = isHosted
        separatorLine.isHidden = isHosted
    }

    private func applyInteractionState(animated: Bool) {
        let isActive = isHighlighted || isSelected
        let palette = appliedTheme.uiKitPalette
        let update = {
            self.contentView.backgroundColor = isActive ? palette.surfaceElevated : palette.surfaceBase
        }
        if animated {
            UIView.animate(withDuration: 0.16, delay: 0, options: [.curveEaseOut, .allowUserInteraction]) {
                update()
            }
        } else {
            update()
        }
    }
}

struct SearchAccountRowContentView: View {
    @Environment(\.moroTheme) private var theme

    let account: Account

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MoroAvatar(
                imageURL: account.avatarAnimatedURL,
                staticImageURL: account.avatarURL,
                initials: account.displayNameInitials,
                size: 44
            )

            VStack(alignment: .leading, spacing: 3) {
                AccountDisplayNameView(
                    account: account,
                    typography: .bodyStrong,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 1,
                    truncationMode: .tail,
                    minimumScaleFactor: 0.9,
                    allowsTightening: true
                )

                Text("@\(account.acct.isEmpty ? account.username : account.acct)")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !account.noteContentElements.isEmpty {
                    SearchAccountNotePreviewView(account: account)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .moroScaledFont(size: 11, weight: .semibold)
                .foregroundStyle(theme.colors.textTertiary)
                .padding(.top, 3)
        }
        .padding(.horizontal, SearchLayoutMetrics.contentHorizontalInset)
        .padding(.vertical, 11)
        .background(theme.colors.surfaceBase)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.colors.divider)
                .frame(height: 0.5)
        }
    }
}

struct SearchAccountNotePreviewView: View {
    let account: Account

    @Environment(\.moroMediaPrefs) private var mediaPrefs
    @Environment(\.moroTheme) private var theme

    var body: some View {
        let elements = account.noteContentElements
        if elements.containsCustomEmoji {
            MixedTextEmojiView(
                elements: elements,
                emojiSize: 14,
                playAnimations: mediaPrefs.playAnimations,
                textColor: UIColor(theme.colors.textSecondary),
                linkColor: UIColor(theme.colors.textSecondary),
                codeBackgroundColor: UIColor(theme.colors.surfaceSubtle),
                font: theme.uiKitPalette.font(forTextStyle: .subheadline),
                lineSpacing: 1,
                lineLimit: 2,
                lineBreakMode: .byTruncatingTail,
                isSelectable: false
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(elements.plainTextValue)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .lineSpacing(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

final class SearchStatusPreviewCache {
    static let shared = SearchStatusPreviewCache()

    private let cache = NSCache<NSString, NSString>()
    private let workerQueue = DispatchQueue(
        label: "moro.search.preview-cache",
        qos: .utility
    )

    private init() {
        cache.countLimit = 300
    }

    func prewarm(statuses: [Status]) {
        guard !statuses.isEmpty else { return }
        let payload = statuses.map { ($0.id, $0.content) }
        workerQueue.async { [cache] in
            for (id, content) in payload {
                let key = "\(id)|\(content.hashValue)" as NSString
                if cache.object(forKey: key) != nil {
                    continue
                }
                let plainText = HTMLParser.stripHTML(content)
                cache.setObject(plainText as NSString, forKey: key)
            }
        }
    }

    func text(for status: Status) -> String {
        let key = "\(status.id)|\(status.content.hashValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached as String
        }

        let plainText = HTMLParser.stripHTML(status.content)
        cache.setObject(plainText as NSString, forKey: key)
        return plainText
    }
}

extension SearchTag {
    var activitySummary: String? {
        guard let history else { return nil }
        let totalUses = history.compactMap { Int($0.uses) }.reduce(0, +)
        guard totalUses > 0 else { return nil }
        return MoroL10n.Search.hashtagRecentUses(totalUses)
    }
}
#endif
