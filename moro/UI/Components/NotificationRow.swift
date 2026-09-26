//
//  NotificationRow.swift
//  moro
//
//  Data-driven notification row layouts.
//

import SwiftUI
import UIKit

struct NotificationRow: View {
    let notification: NotificationDisplayItem
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
        Text(actionText)
            .moroScaledFont(size: 14, weight: .medium)
            .foregroundStyle(theme.colors.textSecondary)
            .lineLimit(2)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var systemEventRow: some View {
        HStack(alignment: .top, spacing: 12) {
            semanticIconColumn

            VStack(alignment: .leading, spacing: 5) {
                if let fallback = notification.fallback {
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
                    initials: account.displayNameInitials,
                    size: Metrics.leadingSize
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
                        initials: account.displayNameInitials,
                        size: Metrics.actorAvatarSize
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
            Button(action: { onAccountTap?() }) {
                HStack(alignment: .center, spacing: 4) {
                    actorDisplayName(account)
                        .layoutPriority(2)

                    accountHandle(account)
                        .layoutPriority(1)

                    metaTime
                }
                .frame(minHeight: normalizedIdentityLineHeight, alignment: .center)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
            Button(action: actorTapAction) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 4) {
                        actorDisplayName(account, usesIntrinsicWidth: true)

                        postActionAndTimeText(usesIntrinsicWidth: true)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: normalizedIdentityLineHeight, alignment: .center)

                    VStack(alignment: .leading, spacing: 2) {
                        actorDisplayName(account)

                        postActionAndTimeText()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
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
        .frame(minHeight: normalizedIdentityLineHeight, alignment: .center)

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

    private var metaTime: some View {
        HStack(spacing: 4) {
            Text("·")
            Text(DateFormatting.relativeString(for: notification.createdAt))
                .lineLimit(1)
        }
        .moroScaledFont(size: 13)
        .foregroundStyle(subtleMetaColor)
        .fixedSize()
    }

    private var normalizedIdentityLineHeight: CGFloat {
        identityLineHeight * theme.fontScale
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
        HStack(alignment: .center, spacing: 12) {
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
                    .accessibilityLabel(
                        statusPreviewText(for: status) ?? actionText
                    )
                } else {
                    statusThumbnail(status)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inlineStatusSummary(status: Status) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            if let text = statusPreviewText(for: status) {
                Text(text)
                    .moroScaledFont(size: 14)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(kind == .mention ? 3 : 2)
                    .lineSpacing(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let metadata = statusPreviewMetadata(for: status) {
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

    private func statusThumbnail(_ status: Status) -> some View {
        NotificationMediaThumbnail(
            attachments: status.mediaAttachments,
            isSensitive: status.sensitive,
            size: Metrics.thumbnailSize
        )
    }

    private func statusPreviewText(for status: Status) -> String? {
        let spoiler = status.spoilerText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !spoiler.isEmpty {
            return spoiler
        }

        let plainText = ContentParser.parseToElements(
            html: status.content,
            mentions: status.mentions,
            tags: status.tags,
            emojis: status.emojis
        )
        .plainTextValue
        .trimmingCharacters(in: .whitespacesAndNewlines)

        if !plainText.isEmpty {
            return plainText
        }
        return status.mediaAttachments.isEmpty ? MoroL10n.Notifications.noTextContent : nil
    }

    private func statusPreviewMetadata(for status: Status) -> String? {
        var segments: [String] = []
        if status.poll != nil {
            segments.append(MoroL10n.Notifications.containsPoll)
        }
        if status.quote?.displayableStatus != nil {
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
            .plainTextValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
