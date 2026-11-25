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
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    private let mascotView = MoroMascotUIView(expression: .curious)
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
        mascotView.apply(theme: theme)
        titleLabel.font = palette.font(forTextStyle: .headline, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        subtitleLabel.font = palette.font(forTextStyle: .subheadline)
        subtitleLabel.textColor = palette.textSecondary
    }

    private func setupViews() {
        let palette = MoroTheme().uiKitPalette
        backgroundColor = .clear
        mascotView.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = palette.font(forTextStyle: .headline, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.text = MoroL10n.Search.exploreTitle
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subtitleLabel.font = palette.font(forTextStyle: .subheadline)
        subtitleLabel.textColor = palette.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.text = MoroL10n.Search.exploreSubtitle
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12
        stackView.addArrangedSubview(mascotView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.setCustomSpacing(6, after: titleLabel)

        addSubview(stackView)

        let leadingConstraint = stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28)
        leadingConstraint.priority = UILayoutPriority(999)
        let trailingConstraint = stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28)
        trailingConstraint.priority = UILayoutPriority(999)
        let preferredWidthConstraint = stackView.widthAnchor.constraint(equalTo: widthAnchor, constant: -56)
        preferredWidthConstraint.priority = UILayoutPriority(998)
        let maxWidthConstraint = stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        maxWidthConstraint.priority = UILayoutPriority(999)
        let titleWidthConstraint = titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        titleWidthConstraint.priority = UILayoutPriority(998)
        let subtitleStackCapConstraint = subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor)
        subtitleStackCapConstraint.priority = UILayoutPriority(999)
        let subtitleMaxWidthConstraint = subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        subtitleMaxWidthConstraint.priority = UILayoutPriority(999)
        let subtitlePreferredWidthConstraint = subtitleLabel.widthAnchor.constraint(equalToConstant: 280)
        subtitlePreferredWidthConstraint.priority = UILayoutPriority(749)

        NSLayoutConstraint.activate([
            mascotView.widthAnchor.constraint(equalToConstant: 62),
            mascotView.heightAnchor.constraint(equalToConstant: 62),

            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            leadingConstraint,
            trailingConstraint,
            preferredWidthConstraint,
            maxWidthConstraint,
            titleWidthConstraint,
            subtitleStackCapConstraint,
            subtitleMaxWidthConstraint,
            subtitlePreferredWidthConstraint,
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableTitleWidth = max(0, min(bounds.width - 56, 340))
        if availableTitleWidth > 0, abs(titleLabel.preferredMaxLayoutWidth - availableTitleWidth) > 0.5 {
            titleLabel.preferredMaxLayoutWidth = availableTitleWidth
            titleLabel.invalidateIntrinsicContentSize()
        }
        let availableSubtitleWidth = max(0, min(availableTitleWidth, 280))
        if availableSubtitleWidth > 0, abs(subtitleLabel.preferredMaxLayoutWidth - availableSubtitleWidth) > 0.5 {
            subtitleLabel.preferredMaxLayoutWidth = availableSubtitleWidth
            subtitleLabel.invalidateIntrinsicContentSize()
        }
    }
}

final class SearchCenterStateView: UIView {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    enum AnimationStyle {
        case none
        case typingCursor
        case searchingIndicator
    }

    private let iconView = UIImageView()
    private var mascotView: MoroMascotUIView?
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let stackView = UIStackView()
    private let animationStyle: AnimationStyle
    private let showsIndicator: Bool
    private let usesAssetImage: Bool
    private var onAction: (() -> Void)?
    private var isAnimationActive = false

    private let typingOpacityAnimationKey = "search.state.typing.opacity"
    private let typingFloatAnimationKey = "search.state.typing.float"
    private let searchingScaleAnimationKey = "search.state.loading.scale"
    private let searchingOpacityAnimationKey = "search.state.loading.opacity"

    init(
        iconName: String? = nil,
        assetName: String? = nil,
        mascotExpression: MoroMascotExpression? = nil,
        imageSize: CGSize = CGSize(width: 58, height: 58),
        title: String?,
        subtitle: String? = nil,
        showsIndicator: Bool = false,
        animationStyle: AnimationStyle = .none,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil
    ) {
        self.animationStyle = animationStyle
        self.showsIndicator = showsIndicator
        self.usesAssetImage = assetName != nil
        self.onAction = onAction
        if let mascotExpression {
            self.mascotView = MoroMascotUIView(expression: mascotExpression)
        }
        super.init(frame: .zero)
        setupViews(
            iconName: iconName,
            assetName: assetName,
            imageSize: imageSize,
            title: title,
            subtitle: subtitle,
            showsIndicator: showsIndicator,
            actionTitle: actionTitle
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
            showsIndicator: false,
            actionTitle: nil
        )
    }

    func update(title: String?, subtitle: String?) {
        titleLabel.text = title
        titleLabel.isHidden = title == nil || title?.isEmpty == true
        subtitleLabel.text = subtitle
        subtitleLabel.isHidden = subtitle == nil || subtitle?.isEmpty == true
        updateAccessibility()
    }

    func apply(theme: MoroTheme) {
        let palette = theme.uiKitPalette
        if !usesAssetImage {
            iconView.tintColor = palette.textSecondary
        }
        mascotView?.apply(theme: theme)
        indicator.color = palette.textSecondary
        titleLabel.font = palette.font(forTextStyle: .headline, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        subtitleLabel.font = palette.font(forTextStyle: .subheadline)
        subtitleLabel.textColor = palette.textSecondary

        if !actionButton.isHidden {
            var config = actionButton.configuration ?? UIButton.Configuration.filled()
            config.baseBackgroundColor = UIColor(theme.colors.primary500)
            config.baseForegroundColor = UIColor(theme.colors.primaryForeground)
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = palette.font(forTextStyle: .subheadline, weight: .semibold)
                return outgoing
            }
            actionButton.configuration = config
        }
    }

    private func setupViews(
        iconName: String?,
        assetName: String?,
        imageSize: CGSize,
        title: String?,
        subtitle: String?,
        showsIndicator: Bool,
        actionTitle: String?
    ) {
        let palette = MoroTheme().uiKitPalette
        backgroundColor = .clear
        iconView.translatesAutoresizingMaskIntoConstraints = false
        mascotView?.translatesAutoresizingMaskIntoConstraints = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        actionButton.translatesAutoresizingMaskIntoConstraints = false
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

        titleLabel.font = palette.font(forTextStyle: .headline, weight: .semibold)
        titleLabel.textColor = palette.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.text = title
        titleLabel.numberOfLines = 2
        titleLabel.isHidden = title == nil
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        subtitleLabel.font = palette.font(forTextStyle: .subheadline)
        subtitleLabel.textColor = palette.textSecondary
        subtitleLabel.textAlignment = .center
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 3
        subtitleLabel.isHidden = subtitle == nil
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        if let actionTitle, onAction != nil {
            var config = UIButton.Configuration.filled()
            config.title = actionTitle
            config.cornerStyle = .capsule
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20)
            actionButton.configuration = config
            actionButton.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .touchUpInside)
            actionButton.isHidden = false
            actionButton.accessibilityIdentifier = "search.retry"
        } else {
            actionButton.isHidden = true
        }

        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 12

        if showsIndicator {
            stackView.addArrangedSubview(indicator)
        }
        if let mascotView {
            stackView.addArrangedSubview(mascotView)
        } else if assetName != nil || iconName != nil {
            stackView.addArrangedSubview(iconView)
        }
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.setCustomSpacing(6, after: titleLabel)
        if !actionButton.isHidden {
            stackView.addArrangedSubview(actionButton)
            stackView.setCustomSpacing(16, after: subtitleLabel)
        }

        addSubview(stackView)
        let leadingConstraint = stackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 28)
        leadingConstraint.priority = UILayoutPriority(999)
        let trailingConstraint = stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -28)
        trailingConstraint.priority = UILayoutPriority(999)
        let preferredWidthConstraint = stackView.widthAnchor.constraint(equalTo: widthAnchor, constant: -56)
        preferredWidthConstraint.priority = UILayoutPriority(998)
        let maxWidthConstraint = stackView.widthAnchor.constraint(lessThanOrEqualToConstant: 340)
        maxWidthConstraint.priority = UILayoutPriority(999)
        let titleWidthConstraint = titleLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        titleWidthConstraint.priority = UILayoutPriority(998)
        let subtitleStackCapConstraint = subtitleLabel.widthAnchor.constraint(lessThanOrEqualTo: stackView.widthAnchor)
        subtitleStackCapConstraint.priority = UILayoutPriority(999)
        let subtitleMaxWidthConstraint = subtitleLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280)
        subtitleMaxWidthConstraint.priority = UILayoutPriority(999)
        let subtitlePreferredWidthConstraint = subtitleLabel.widthAnchor.constraint(equalToConstant: 280)
        subtitlePreferredWidthConstraint.priority = UILayoutPriority(749)

        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: centerYAnchor),
            leadingConstraint,
            trailingConstraint,
            preferredWidthConstraint,
            maxWidthConstraint,
            titleWidthConstraint,
            subtitleStackCapConstraint,
            subtitleMaxWidthConstraint,
            subtitlePreferredWidthConstraint,
        ])
        if let mascotView {
            NSLayoutConstraint.activate([
                mascotView.widthAnchor.constraint(equalToConstant: imageSize.width),
                mascotView.heightAnchor.constraint(equalToConstant: imageSize.height),
            ])
        } else if assetName != nil {
            NSLayoutConstraint.activate([
                iconView.widthAnchor.constraint(equalToConstant: imageSize.width),
                iconView.heightAnchor.constraint(equalToConstant: imageSize.height),
            ])
        }
        if !actionButton.isHidden {
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        }

        apply(theme: MoroTheme())
        updateAccessibility()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let availableTitleWidth = max(0, min(bounds.width - 56, 340))
        if availableTitleWidth > 0, abs(titleLabel.preferredMaxLayoutWidth - availableTitleWidth) > 0.5 {
            titleLabel.preferredMaxLayoutWidth = availableTitleWidth
            titleLabel.invalidateIntrinsicContentSize()
        }
        let availableSubtitleWidth = max(0, min(availableTitleWidth, 280))
        if availableSubtitleWidth > 0, abs(subtitleLabel.preferredMaxLayoutWidth - availableSubtitleWidth) > 0.5 {
            subtitleLabel.preferredMaxLayoutWidth = availableSubtitleWidth
            subtitleLabel.invalidateIntrinsicContentSize()
        }
    }

    private func updateAccessibility() {
        iconView.isAccessibilityElement = false
        if actionButton.isHidden {
            titleLabel.isAccessibilityElement = false
            subtitleLabel.isAccessibilityElement = false
            let accessibilityText = [titleLabel.text, subtitleLabel.text]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
            isAccessibilityElement = !accessibilityText.isEmpty
            accessibilityLabel = accessibilityText
        } else {
            isAccessibilityElement = false
            titleLabel.isAccessibilityElement = true
            subtitleLabel.isAccessibilityElement = true
        }
    }

    func setAnimationActive(_ active: Bool) {
        guard active != isAnimationActive else { return }
        isAnimationActive = active
        mascotView?.setAnimationActive(active)

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
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    static let reuseIdentifier = "LoadingMoreCell"

    private let mascotView = MoroMascotUIView(expression: .thinking)
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

    override func prepareForReuse() {
        super.prepareForReuse()
        mascotView.setAnimationActive(false)
    }

    func apply(theme: MoroTheme) {
        let palette = theme.uiKitPalette
        backgroundColor = .clear
        contentView.backgroundColor = palette.surfaceBase
        mascotView.apply(theme: theme)

        guard var configuration = retryButton.configuration else { return }
        configuration.baseForegroundColor = palette.textPrimary
        configuration.baseBackgroundColor = UIColor(theme.colors.surfaceSubtle)
        configuration.background.strokeColor = UIColor(theme.colors.borderSubtle)
        configuration.background.strokeWidth = 0.9
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = palette.font(forTextStyle: .footnote, weight: .semibold)
            return outgoing
        }
        retryButton.configuration = configuration
    }

    /// Minimalist breathing mascot shown while the next page is loading.
    func configureLoading() {
        onRetry = nil
        retryButton.isHidden = true
        mascotView.isHidden = false
        mascotView.setAnimationActive(true)
    }

    /// Tappable capsule retry affordance shown after a load-more failure.
    func configureRetry(onRetry: @escaping () -> Void) {
        self.onRetry = onRetry
        mascotView.setAnimationActive(false)
        mascotView.isHidden = true
        retryButton.isHidden = false
    }

    private func setupViews() {
        let palette = MoroTheme().uiKitPalette
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none

        mascotView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(mascotView)

        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.isHidden = true
        var config = UIButton.Configuration.filled()
        config.title = MoroL10n.Common.loadMoreRetry
        config.image = UIImage(systemName: "arrow.clockwise")
        config.imagePadding = 6
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        config.baseForegroundColor = palette.textPrimary
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = palette.font(forTextStyle: .footnote, weight: .semibold)
            return outgoing
        }
        retryButton.configuration = config
        retryButton.addAction(
            UIAction { [weak self] _ in self?.onRetry?() },
            for: .touchUpInside
        )
        contentView.addSubview(retryButton)

        NSLayoutConstraint.activate([
            mascotView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            mascotView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            mascotView.widthAnchor.constraint(equalToConstant: 32),
            mascotView.heightAnchor.constraint(equalToConstant: 32),
            retryButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            retryButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
    }
}

/// Suspend search-field focus restoration for the full native menu presentation.
final class SearchScopeMenuButton: UIButton {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    var onMenuWillDisplay: (() -> Void)?
    var onMenuDidEnd: (() -> Void)?

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willDisplayMenuFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        onMenuWillDisplay?()
        super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    }

    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        willEndFor configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionAnimating?
    ) {
        super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
        if let animator {
            animator.addCompletion { [weak self] in self?.onMenuDidEnd?() }
        } else {
            onMenuDidEnd?()
        }
    }
}

final class SearchResultLineCell: UITableViewCell {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

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
    var makeAccountView: ((Account) -> AnyView)?
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
        makeAccountView = nil
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
            makeAccountView?(account) ?? AnyView(SearchAccountRowContentView(account: account).moroTheme(theme))
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
                initials: account.displayNameInitials, seed: account.placeholderSeed,
                size: 44,
                allowsAnimation: true
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
        .padding(.vertical, 10)
        .background(theme.colors.surfaceBase)
    }
}

struct SearchAccountNotePreviewView: View {
    let account: Account

    @Environment(\.moroTheme) private var theme

    var body: some View {
        let elements = account.noteContentElements.compactedForInlinePreview
        if elements.containsCustomEmoji {
            // Same SwiftUI text as the plain preview below, so both have the same font and
            // line height. Links are plain text here: a tap opens the profile row.
            InlineEmojiText(
                runs: InlineTextRunBuilder.runs(
                    for: elements,
                    style: InlineTextStyle(
                        textColor: theme.colors.textSecondary,
                        linkColor: theme.colors.textSecondary,
                        codeBackgroundColor: theme.colors.surfaceSubtle,
                        codeFontSize: theme.uiKitPalette.font(forTextStyle: .subheadline).pointSize,
                        linksAreInteractive: false
                    )
                ),
                emojiSize: 14
            )
            .font(theme.typography.body)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(2)
            .truncationMode(.tail)
            .lineSpacing(1)
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

extension SearchTag {
    var activitySummary: String? {
        guard let history else { return nil }
        let totalUses = history.compactMap { Int($0.uses) }.reduce(0, +)
        guard totalUses > 0 else { return nil }
        return MoroL10n.Search.hashtagRecentUses(totalUses)
    }
}
#endif
