//
//  NotificationRow.swift
//  moro
//
//  Data-driven notification row layouts.
//

import SwiftUI
import UIKit

nonisolated enum NotificationQuotePresentation: Equatable {
    /// No quote preview shown (no quote, or `quotedUpdate` whose main target IS already the quoted post).
    case none
    /// Full-width lightweight quoted card below the main row (for `kind == .quote`).
    /// Never renders a second thumbnail when the quoting post already displays a trailing media thumbnail.
    case fullWidthCard(showsQuotedThumbnail: Bool)
    /// Single-line left-bar quote hint inside the summary for interaction notifications (like/boost/mention)
    /// so the row stays compact and never stacks two thumbnails side by side.
    case inlineHint
    /// Pending or unavailable quote placeholder.
    case placeholder(Status.QuoteState)

    static func resolve(kind: NotificationKind, status: Status) -> Self {
        guard kind != .quotedUpdate, let quote = status.quote else {
            return .none
        }
        guard let quoted = quote.displayableStatus?.displayStatus else {
            return .placeholder(quote.state)
        }
        if kind == .quote {
            let mainHasMedia = !status.mediaAttachments.isEmpty
            let quotedHasMedia = !quoted.mediaAttachments.isEmpty
            return .fullWidthCard(showsQuotedThumbnail: !mainHasMedia && quotedHasMedia)
        }
        return .inlineHint
    }
}

struct NotificationRow: View {
    let notification: NotificationDisplayItem
    var reportURL: URL? = nil
    var onAvatarTap: (() -> Void)? = nil
    var onStatusTap: ((Status) -> Void)? = nil
    var onAccountTap: (() -> Void)? = nil
    var onActorsTap: (() -> Void)? = nil
    var onAcceptFollowRequest: (() -> Void)? = nil
    var onRejectFollowRequest: (() -> Void)? = nil
    var isAcceptingFollowRequest: Bool = false
    var isRejectingFollowRequest: Bool = false
    var statusTapAccessibilityIdentifier: String? = nil

    @Environment(\.moroTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .subheadline) private var identityLineHeight: CGFloat = 20
    @ScaledMetric(relativeTo: .body) private var timestampPointSize: CGFloat = 13

    private enum Metrics {
        static let leadingSize: CGFloat = 44
        static let actionIconSize: CGFloat = 22
        static let actorAvatarSize: CGFloat = 30
        static let thumbnailSize: CGFloat = 76
    }

    private var kind: NotificationKind { notification.kind }
    private var descriptor: NotificationPresentationDescriptor { kind.descriptor }
    private var primaryAccount: Account? { notification.presentationAccount }
    private var isMultiActorNotification: Bool { notification.actorCount > 1 }
    private var additionalActorCount: Int { max(notification.actorCount - 1, 0) }
    private var isReply: Bool { kind == .mention && notification.status?.inReplyToID != nil }
    private var actionText: String { kind.actionText(isReply: isReply) }
    private var effectiveStatusTarget: Status? { notification.effectiveStatusTarget }

    private var subtleMetaColor: Color {
        colorScheme == .dark ? theme.colors.textSecondary : theme.colors.textTertiary
    }

    private var resolvedIconName: String {
        if UIImage(systemName: descriptor.iconName) != nil {
            return descriptor.iconName
        }
        return UIImage(systemName: "bell.fill") != nil ? "bell.fill" : "bell"
    }

    private var iconColor: Color {
        switch descriptor.accent {
        case .favourite:
            return Color(hex: 0xFF3B5C)
        case .reblog:
            return theme.colors.success
        case .quote:
            return theme.colors.primary600
        case .warning:
            return theme.colors.error
        case .standard:
            return theme.colors.textSecondary
        }
    }

    var body: some View {
        if let reportURL {
            Link(destination: reportURL) {
                rowContent.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .environment(\.openURL, OpenURLAction { _ in .systemAction })
            .accessibilityIdentifier("notifications.report.\(notification.id)")
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        Group {
            switch descriptor.layoutFamily {
            case .postAction:
                postActionRow
            case .personEvent:
                personEventRow
            case .contentEvent:
                contentEventRow
            case .systemEvent:
                systemEventRow
            }
        }
        .padding(.horizontal, theme.spacing.contentHorizontalInset)
        .padding(.vertical, 12)
    }

    // MARK: - Layout families

    private var postActionRow: some View {
        HStack(alignment: .top, spacing: 12) {
            semanticIconColumn

            VStack(alignment: .leading, spacing: 8) {
                trailingMediaLayout(status: effectiveStatusTarget) {
                    VStack(alignment: .leading, spacing: 7) {
                        actorAvatarStrip
                        postActionSummary

                        if descriptor.showsStatusPreview, let status = effectiveStatusTarget {
                            inlineStatusSummary(status: status)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if descriptor.showsStatusPreview,
                   let status = effectiveStatusTarget,
                   case .fullWidthCard(let showsQuotedThumbnail) = NotificationQuotePresentation.resolve(
                       kind: kind,
                       status: status
                   ),
                   let quotedStatus = status.quote?.displayableStatus?.displayStatus
                {
                    fullWidthQuotedCard(
                        quotedStatus,
                        parentStatus: status,
                        showsThumbnail: showsQuotedThumbnail
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var personEventRow: some View {
        HStack(alignment: .top, spacing: 12) {
            personLeadingView

            trailingMediaLayout(status: effectiveStatusTarget) {
                VStack(alignment: .leading, spacing: 5) {
                    personHeader
                    actionLabel

                    if descriptor.showsStatusPreview, let status = effectiveStatusTarget {
                        inlineStatusSummary(status: status)
                    } else if hasCollectionContent {
                        collectionSummary
                    } else if let fallback = notification.fallback {
                        fallbackSummary(fallback, includesTitle: false)
                    }

                    if shouldShowFollowRequestActions {
                        followRequestActionRow
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var contentEventRow: some View {
        HStack(alignment: .top, spacing: 12) {
            contentEventLeadingView

            trailingMediaLayout(status: effectiveStatusTarget) {
                VStack(alignment: .leading, spacing: 5) {
                    personHeader
                    actionLabel

                    if descriptor.showsStatusPreview, let status = effectiveStatusTarget {
                        inlineStatusSummary(status: status)
                    } else if hasCollectionContent {
                        collectionSummary
                    } else if let fallback = notification.fallback {
                        fallbackSummary(fallback, includesTitle: false)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionLabel: some View {
        eventButton(part: "action") {
            styledAction(Text(actionText))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func styledAction(_ text: Text) -> some View {
        text
            .moroScaledFont(size: 14, weight: .medium)
            .foregroundStyle(theme.colors.textSecondary)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var systemEventRow: some View {
        HStack(alignment: .top, spacing: 12) {
            semanticIconColumn

            VStack(alignment: .leading, spacing: 5) {
                if kind == .adminReport {
                    reportSummary
                } else if let fallback = notification.fallback {
                    fallbackSummary(fallback, includesTitle: true)
                } else {
                    Text(actionText)
                        .moroScaledFont(size: 15, weight: .semibold)
                        .foregroundStyle(theme.colors.textPrimary)

                    if let account = primaryAccount {
                        HStack(spacing: 4) {
                            Text("@\(account.acct)")
                                .moroScaledFont(size: 13)
                                .lineLimit(1)
                            metaTime
                        }
                        .foregroundStyle(subtleMetaColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reportSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            styledAction(Text("\(reportTitle) \(timestampWithSeparator)"))
            if let reason = notification.report?.notificationReason {
                Text(verbatim: reason)
                    .moroScaledFont(size: 14)
                    .foregroundStyle(theme.colors.textSecondary)
            } else if notification.report == nil, let fallback = notification.fallback {
                fallbackSummary(fallback, includesTitle: false)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var reportTitle: Text {
        if let report = notification.report {
            var usernameStyle = AttributeContainer()
            usernameStyle.foregroundColor = theme.colors.textPrimary
            usernameStyle.inlinePresentationIntent = .stronglyEmphasized
            return Text(report.notificationTitle(usernameAttributes: usernameStyle))
        }
        let title = notification.fallback.map { plainText(fromHTML: $0.title) } ?? MoroL10n.Notifications.badgeReport
        return Text(verbatim: title)
    }

    // MARK: - Leading content

    @ViewBuilder
    private var contentEventLeadingView: some View {
        if effectiveStatusTarget != nil, primaryAccount != nil {
            personLeadingView
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: resolvedIconName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(iconColor)
                        .frame(width: 18, height: 18)
                        .background(theme.colors.surfaceSubtle, in: Circle())
                        .overlay(Circle().stroke(theme.colors.background, lineWidth: 2))
                        .offset(x: 3, y: 3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } else {
            semanticIconColumn
        }
    }

    private var semanticIconColumn: some View {
        Image(systemName: resolvedIconName)
            .moroScaledFont(size: Metrics.actionIconSize, weight: .semibold)
            .foregroundStyle(iconColor)
            .frame(width: Metrics.leadingSize, height: Metrics.leadingSize, alignment: .top)
            .padding(.top, 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var personLeadingView: some View {
        if let account = primaryAccount {
            Button(action: { onAvatarTap?() }) {
                MoroAvatar(
                    imageURL: account.avatarAnimatedURL,
                    staticImageURL: account.avatarURL,
                    initials: account.displayNameInitials, seed: account.placeholderSeed,
                    size: Metrics.leadingSize,
                    allowsAnimation: true
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(MoroL10n.Notifications.accessibilityOpenProfile)
        } else {
            semanticIconColumn
        }
    }

    private var actorAvatarStrip: some View {
        Button(action: actorTapAction) {
            HStack(spacing: -7) {
                ForEach(Array(notification.accounts.prefix(3)), id: \.id) { account in
                    MoroAvatar(
                        imageURL: account.avatarAnimatedURL,
                        staticImageURL: account.avatarURL,
                        initials: account.displayNameInitials, seed: account.placeholderSeed,
                        size: Metrics.actorAvatarSize,
                        allowsAnimation: true
                    )
                    .overlay(
                        Circle()
                            .stroke(theme.colors.background, lineWidth: 2)
                    )
                }

                if notification.actorCount > 3 {
                    Text("+\(notification.actorCount - 3)")
                        .moroScaledFont(size: 11, weight: .semibold)
                        .foregroundStyle(theme.colors.textSecondary)
                        .frame(width: Metrics.actorAvatarSize, height: Metrics.actorAvatarSize)
                        .background(Circle().fill(theme.colors.surfaceSubtle))
                        .overlay(Circle().stroke(theme.colors.background, lineWidth: 2))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notifications.actors.\(notification.id)")
        .accessibilityLabel(
            isMultiActorNotification
                ? MoroL10n.Notifications.accessibilityActorList
                : MoroL10n.Notifications.accessibilityOpenProfile
        )
    }

    // MARK: - Actor text

    @ViewBuilder
    private var personHeader: some View {
        if let account = primaryAccount {
            HStack(alignment: .center, spacing: 4) {
                // The person opens their profile; the time belongs to the post.
                Button(action: { onAccountTap?() }) {
                    HStack(alignment: .center, spacing: 4) {
                        actorDisplayName(account)
                            .layoutPriority(2)

                        accountHandle(account)
                            .layoutPriority(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .layoutPriority(1)
                .accessibilityIdentifier("notifications.actor.\(notification.id)")

                eventButton(part: "time") { metaTime }
            }
            .frame(minHeight: identityLineHeight, alignment: .center)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 4) {
                Text(MoroL10n.Notifications.unknownUser)
                    .moroScaledFont(size: 14, weight: .semibold)
                metaTime
            }
        }
    }

    @ViewBuilder
    private var postActionSummary: some View {
        if let account = primaryAccount {
            // The name opens the person (or the list of people); "liked your post · 2h"
            // describes the post, so it opens the post like its preview does.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 4) {
                    actorNameButton { actorDisplayName(account, usesIntrinsicWidth: true) }

                    eventButton(part: "action") { postActionAndTimeText(usesIntrinsicWidth: true) }
                }
                .fixedSize(horizontal: true, vertical: false)
                .frame(minHeight: identityLineHeight, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    actorNameButton { actorDisplayName(account) }

                    eventButton(part: "action") {
                        postActionAndTimeText()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actorNameButton<Label: View>(@ViewBuilder label: () -> Label) -> some View {
        Button(action: actorTapAction) {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notifications.actor.\(notification.id)")
    }

    /// The action text and the time open the post the notification is about, like its
    /// preview and thumbnail. Without a post (a follow, say) they fall back to the person.
    private func eventButton<Label: View>(part: String, @ViewBuilder label: () -> Label) -> some View {
        Button(action: eventTapAction) {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("notifications.\(part).\(notification.id)")
    }

    private func eventTapAction() {
        if let status = effectiveStatusTarget, let onStatusTap {
            onStatusTap(status)
        } else {
            actorTapAction()
        }
    }

    @ViewBuilder
    private func actorDisplayName(
        _ account: Account,
        usesIntrinsicWidth: Bool = false
    ) -> some View {
        let name = AccountDisplayNameView(
            account: account,
            typography: .bodyStrong,
            textColor: theme.colors.textPrimary,
            lineLimit: 1,
            truncationMode: .tail,
            minimumScaleFactor: 0.9,
            allowsTightening: true
        )
        .frame(minHeight: identityLineHeight, alignment: .center)

        if usesIntrinsicWidth {
            name.fixedSize(horizontal: true, vertical: false)
        } else {
            name
        }
    }

    @ViewBuilder
    private func accountHandle(
        _ account: Account,
        usesIntrinsicWidth: Bool = false
    ) -> some View {
        let handle = Text("@\(account.acct)")
            .moroScaledFont(size: 13)
            .foregroundStyle(subtleMetaColor)
            .lineLimit(1)
            .truncationMode(.middle)

        if usesIntrinsicWidth {
            handle.fixedSize(horizontal: true, vertical: false)
        } else {
            handle
        }
    }

    @ViewBuilder
    private func postActionAndTimeText(usesIntrinsicWidth: Bool = false) -> some View {
        let text = (
            Text(postActionSecondaryText)
                .foregroundColor(theme.colors.textSecondary)
                + Text(" · \(DateFormatting.relativeString(for: notification.createdAt))")
                .foregroundColor(subtleMetaColor)
        )
            .moroScaledFont(size: 14)
            .lineLimit(2)
            .lineSpacing(1)
            .multilineTextAlignment(.leading)

        if usesIntrinsicWidth {
            text.fixedSize(horizontal: true, vertical: false)
        } else {
            text.fixedSize(horizontal: false, vertical: true)
        }
    }

    private var postActionSecondaryText: String {
        if isMultiActorNotification {
            return MoroL10n.Notifications.actionMultiActor(additionalActorCount, actionText)
        }
        return actionText
    }

    private var timestampWithSeparator: Text {
        Text(verbatim: "·\u{00a0}\(DateFormatting.relativeString(for: notification.createdAt))")
            .font(.system(size: timestampPointSize))
            .foregroundStyle(subtleMetaColor)
    }

    private var metaTime: some View {
        timestampWithSeparator.lineLimit(1).fixedSize()
    }

    private func actorTapAction() {
        if isMultiActorNotification {
            onActorsTap?()
        } else if onAccountTap != nil {
            onAccountTap?()
        } else {
            onAvatarTap?()
        }
    }

    // MARK: - Status content

    @ViewBuilder
    private func trailingMediaLayout<Content: View>(
        status: Status?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            if let status, !status.mediaAttachments.isEmpty {
                if let onStatusTap {
                    Button {
                        onStatusTap(status)
                    } label: {
                        statusThumbnail(status)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                    .accessibilityLabel(
                        statusPreviewText(for: status) ?? actionText
                    )
                } else {
                    statusThumbnail(status)
                        .padding(.top, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inlineStatusSummary(status: Status) -> some View {
        let previewElements = statusPreviewElements(for: status)
        let quotePresentation = NotificationQuotePresentation.resolve(kind: kind, status: status)
        let lineLimit = kind == .mention ? 3 : 2

        let content = VStack(alignment: .leading, spacing: 5) {
            if let previewElements {
                compactPreviewText(
                    elements: previewElements,
                    fontSize: 14,
                    textColor: theme.colors.textSecondary,
                    lineLimit: lineLimit
                )
            }

            switch quotePresentation {
            case .inlineHint:
                if let quotedStatus = status.quote?.displayableStatus?.displayStatus {
                    inlineQuoteHintRow(quotedStatus)
                }
            case .placeholder(let state):
                compactQuotePlaceholderBadge(for: state)
            case .fullWidthCard, .none:
                EmptyView()
            }

            if let metadata = statusPreviewMetadata(for: status, includesQuoteFallback: quotePresentation == .none) {
                Text(metadata)
                    .font(theme.typography.caption)
                    .foregroundStyle(subtleMetaColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if let onStatusTap {
            Button {
                onStatusTap(status)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .applyAccessibilityIdentifier(statusTapAccessibilityIdentifier)
        } else {
            content
        }
    }

    @ViewBuilder
    private func compactPreviewText(
        elements: [ContentElement],
        fontSize: CGFloat,
        textColor: Color,
        lineLimit: Int
    ) -> some View {
        if elements.containsCustomEmoji {
            let style = InlineTextStyle(
                textColor: textColor,
                linkColor: textColor,
                codeBackgroundColor: theme.colors.surfaceSubtle,
                codeFontSize: max(12, fontSize - 1),
                underlinesLinks: false,
                linksAreInteractive: false
            )
            let runs = InlineTextRunBuilder.runs(for: elements, style: style)
            InlineEmojiText(runs: runs, emojiSize: fontSize + 2)
                .moroScaledFont(size: fontSize)
                .foregroundStyle(textColor)
                .lineLimit(lineLimit)
                .lineSpacing(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)
                .accessibilityLabel(elements.plainTextValue)
        } else {
            Text(elements.plainTextValue)
                .moroScaledFont(size: fontSize)
                .foregroundStyle(textColor)
                .lineLimit(lineLimit)
                .lineSpacing(2)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Ultra-lightweight single-line left-bar quote hint for interaction notifications
    /// (likes, boosts, mentions) so the row stays uncluttered beside a trailing thumbnail.
    private func inlineQuoteHintRow(_ quotedStatus: Status) -> some View {
        let authorName = quotedStatus.account.displayNameFormatted
        let quoteElements = statusPreviewElements(for: quotedStatus, includeEmptyFallback: false)
        let fallbackSummary: String? = quoteElements == nil && !quotedStatus.mediaAttachments.isEmpty
            ? MoroL10n.Post.quoteMediaCount(quotedStatus.mediaAttachments.count)
            : nil
        let textColor = subtleMetaColor

        let style = InlineTextStyle(
            textColor: textColor,
            linkColor: textColor,
            codeBackgroundColor: theme.colors.surfaceSubtle,
            codeFontSize: 12,
            underlinesLinks: false,
            linksAreInteractive: false
        )
        var authorPrefix = AttributedString("\(authorName)：")
        authorPrefix.foregroundColor = theme.colors.textSecondary
        authorPrefix.inlinePresentationIntent = .stronglyEmphasized

        var runs: [InlineTextRun] = [.text(authorPrefix)]
        if let quoteElements {
            runs.append(contentsOf: InlineTextRunBuilder.runs(for: quoteElements, style: style))
        } else if let fallbackSummary {
            runs.append(.text(AttributedString(fallbackSummary)))
        } else {
            runs.append(.text(AttributedString(MoroL10n.Notifications.containsQuote)))
        }

        let hasEmoji = quoteElements?.containsCustomEmoji == true
        let accessibilityText = "\(authorName)：\(quoteElements?.plainTextValue ?? fallbackSummary ?? MoroL10n.Notifications.containsQuote)"

        return HStack(alignment: .center, spacing: 6) {
            Capsule()
                .fill(theme.colors.textTertiary.opacity(colorScheme == .dark ? 0.50 : 0.35))
                .frame(width: 2, height: 14)
                .accessibilityHidden(true)

            Group {
                if hasEmoji {
                    InlineEmojiText(runs: runs, emojiSize: 15)
                        .allowsHitTesting(false)
                } else {
                    Text(InlineTextRunBuilder.flattened(runs))
                }
            }
            .moroScaledFont(size: 13)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("notifications.quoteHint.\(notification.id)")
    }

    /// Full-width lightweight quoted card reserved for `kind == .quote` notifications.
    /// Placed below `trailingMediaLayout` so it spans the full content width and never shows
    /// a second thumbnail alongside the quoting post's own media.
    @ViewBuilder
    private func fullWidthQuotedCard(
        _ quotedStatus: Status,
        parentStatus: Status,
        showsThumbnail: Bool
    ) -> some View {
        let quoteElements = statusPreviewElements(for: quotedStatus, includeEmptyFallback: false)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        let borderColor = colorScheme == .dark
            ? theme.colors.borderSubtle
            : theme.colors.textPrimary.opacity(0.10)

        let card = HStack(alignment: .top, spacing: 10) {
            if showsThumbnail {
                NotificationMediaThumbnail(
                    attachments: quotedStatus.mediaAttachments,
                    isSensitive: quotedStatus.sensitive,
                    size: 46
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 5) {
                    MoroAvatar(
                        imageURL: quotedStatus.account.avatarAnimatedURL,
                        staticImageURL: quotedStatus.account.avatarURL,
                        initials: quotedStatus.account.displayNameInitials,
                        seed: quotedStatus.account.placeholderSeed,
                        size: 16,
                        allowsAnimation: false
                    )

                    AccountDisplayNameView(
                        account: quotedStatus.account,
                        typography: .captionStrong,
                        textColor: theme.colors.textPrimary,
                        lineLimit: 1,
                        fitsInlineWidth: true,
                        truncationMode: .tail
                    )
                }

                if let quoteElements {
                    compactPreviewText(
                        elements: quoteElements,
                        fontSize: 13,
                        textColor: theme.colors.textSecondary,
                        lineLimit: 2
                    )
                } else if !quotedStatus.mediaAttachments.isEmpty {
                    Text(MoroL10n.Post.quoteMediaCount(quotedStatus.mediaAttachments.count))
                        .font(theme.typography.caption)
                        .foregroundStyle(subtleMetaColor)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(shape.fill(theme.colors.surfaceSubtle))
        .overlay(shape.strokeBorder(borderColor, lineWidth: 0.75))
        .clipShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("notifications.quoteCard.\(notification.id)")

        if let onStatusTap {
            Button {
                onStatusTap(parentStatus)
            } label: {
                card
            }
            .buttonStyle(.plain)
        } else {
            card
        }
    }

    private func compactQuotePlaceholderBadge(for state: Status.QuoteState) -> some View {
        let icon = state == .pending ? "clock" : "quote.bubble"
        let title = state == .pending
            ? MoroL10n.Post.quotePendingTitle
            : MoroL10n.Post.quoteUnavailableTitle
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        return HStack(spacing: 5) {
            Image(systemName: icon)
                .moroScaledFont(size: 11, weight: .medium)
            Text(title)
                .font(theme.typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(subtleMetaColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(shape.fill(theme.colors.surfaceSubtle))
        .overlay(shape.strokeBorder(theme.colors.borderSubtle, lineWidth: 0.75))
        .clipShape(shape)
    }

    private func statusThumbnail(_ status: Status) -> some View {
        NotificationMediaThumbnail(
            attachments: status.mediaAttachments,
            isSensitive: status.sensitive,
            size: Metrics.thumbnailSize
        )
    }

    private func statusPreviewElements(
        for status: Status,
        includeEmptyFallback: Bool = true
    ) -> [ContentElement]? {
        let spoiler = status.spoilerText?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !spoiler.isEmpty {
            return [.text(spoiler)]
        }

        let compacted = ContentParser.parseToElements(
            html: status.content,
            mentions: status.mentions,
            tags: status.tags,
            emojis: status.emojis,
            options: .statusBody
        )
        .compactedForInlinePreview

        if !compacted.isEmpty {
            return compacted
        }
        if includeEmptyFallback, status.mediaAttachments.isEmpty, status.quote == nil {
            return [.text(MoroL10n.Notifications.noTextContent)]
        }
        return nil
    }

    private func statusPreviewText(for status: Status) -> String? {
        statusPreviewElements(for: status)?.plainTextValue
    }

    private func statusPreviewMetadata(
        for status: Status,
        includesQuoteFallback: Bool = true
    ) -> String? {
        var segments: [String] = []
        if status.poll != nil {
            segments.append(MoroL10n.Notifications.containsPoll)
        }
        if includesQuoteFallback, status.quote?.displayableStatus != nil {
            segments.append(MoroL10n.Notifications.containsQuote)
        }
        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    // MARK: - Collection and fallback content

    private var hasCollectionContent: Bool {
        let name = notification.collection?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = notification.collection?.description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name?.isEmpty == false || description?.isEmpty == false
    }

    private var collectionSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let name = notification.collection?.name, !name.isEmpty {
                Text(name)
                    .moroScaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(1)
            }

            if let description = notification.collection?.description {
                let plainDescription = plainText(fromHTML: description)
                if !plainDescription.isEmpty {
                    Text(plainDescription)
                        .moroScaledFont(size: 14)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func fallbackSummary(
        _ fallback: NotificationFallback,
        includesTitle: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if includesTitle {
                Text(plainText(fromHTML: fallback.title))
                    .moroScaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(theme.colors.textPrimary)
                    .lineLimit(2)
            }

            if let summary = fallback.summary {
                let plainSummary = plainText(fromHTML: summary)
                if !plainSummary.isEmpty {
                    Text(plainSummary)
                        .moroScaledFont(size: 14)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineLimit(3)
                }
            }

            if let details = fallback.details {
                let plainDetails = plainText(fromHTML: details)
                if !plainDetails.isEmpty, plainDetails != plainText(fromHTML: fallback.summary ?? "") {
                    Text(plainDetails)
                        .font(theme.typography.caption)
                        .foregroundStyle(subtleMetaColor)
                        .lineLimit(2)
                }
            }
        }
    }

    private func plainText(fromHTML html: String) -> String {
        ContentParser.parseToElements(html: html)
            .normalizedInlinePlainText
    }

    // MARK: - Follow request

    private var shouldShowFollowRequestActions: Bool {
        kind == .followRequest
            && notification.actorCount == 1
            && onAcceptFollowRequest != nil
            && onRejectFollowRequest != nil
    }

    private var followRequestActionRow: some View {
        HStack(spacing: theme.spacing.s) {
            Button {
                onAcceptFollowRequest?()
            } label: {
                HStack(spacing: 4) {
                    if isAcceptingFollowRequest {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark")
                            .moroScaledFont(size: 11, weight: .semibold)
                    }
                    Text(MoroL10n.Notifications.accept)
                        .font(theme.typography.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(theme.colors.primary600)
                .padding(.horizontal, theme.spacing.s)
                .padding(.vertical, 6)
                .background(theme.colors.primary50)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAcceptingFollowRequest || isRejectingFollowRequest)
            .accessibilityLabel(MoroL10n.Notifications.acceptAccessibility)

            Button {
                onRejectFollowRequest?()
            } label: {
                HStack(spacing: 4) {
                    if isRejectingFollowRequest {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Image(systemName: "xmark")
                            .moroScaledFont(size: 11, weight: .semibold)
                    }
                    Text(MoroL10n.Notifications.reject)
                        .font(theme.typography.caption)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(theme.colors.error)
                .padding(.horizontal, theme.spacing.s)
                .padding(.vertical, 6)
                .background(theme.colors.error.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAcceptingFollowRequest || isRejectingFollowRequest)
            .accessibilityLabel(MoroL10n.Notifications.rejectAccessibility)

            Spacer()
        }
    }
}

private extension View {
    @ViewBuilder
    func applyAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

#Preview {
    let account = Account(
        id: "1",
        username: "testuser",
        acct: "testuser@mastodon.social",
        displayName: "Test User",
        note: "",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 0,
        followingCount: 0,
        statusesCount: 0
    )
    let notification = NotificationItem(
        id: "1",
        type: "mention",
        createdAt: Date().addingTimeInterval(-3600),
        account: account,
        status: nil
    )

    ScrollView {
        NotificationRow(notification: NotificationDisplayItem(from: notification))
    }
    .moroTheme(MoroTheme())
}
