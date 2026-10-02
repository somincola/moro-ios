import SwiftUI

struct ReportStatusRow: View {
    @Environment(\.moroTheme) private var theme
    let status: Status
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(status.createdAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textSecondary)
                    if let warning = status.spoilerText, !warning.isEmpty {
                        Text(warning)
                            .moroScaledFont(size: 16, weight: .medium)
                    }
                    // The report list is an excerpt; collapse paragraph gaps without changing stored content.
                    let content = HTMLParser.stripHTML(status.content)
                        .split(whereSeparator: \.isNewline).joined(separator: " ")
                    if !content.isEmpty {
                        Text(content)
                            .moroScaledFont(size: 16)
                            .lineSpacing(4)
                            .lineLimit(4)
                    }
                    if !status.mediaAttachments.isEmpty {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 56, maximum: 56), spacing: 8)],
                            alignment: .leading,
                            spacing: 8
                        ) {
                            ForEach(status.mediaAttachments) { attachment in
                                NotificationMediaThumbnail(
                                    attachments: [attachment],
                                    isSensitive: status.sensitive,
                                    size: 56
                                )
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ReportSelectionIndicator(isSelected: isSelected)
                    .padding(.top, 2)
            }
            .foregroundStyle(theme.colors.primary500)
            .multilineTextAlignment(.leading)
            .padding(.vertical, 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(
            status.mediaAttachments.isEmpty ? "" : MoroL10n.Report.mediaCount(status.mediaAttachments.count)
        )
        .overlay(alignment: .bottom) { MoroDivider() }
    }
}

#Preview {
    let sampleAccount = Account(
        id: "1",
        username: "testuser",
        acct: "testuser@mastodon.social",
        displayName: "Test User",
        note: "",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 100,
        followingCount: 50,
        statusesCount: 200
    )

    let sampleStatus = Status(
        id: "1",
        content: "<p>This is a sample status content that might be problematic.</p>",
        createdAt: Date(),
        account: sampleAccount,
        mediaAttachments: [],
        favouritesCount: 10,
        reblogsCount: 5,
        repliesCount: 2,
        bookmarked: false,
        favourited: false,
        reblogged: false
    )

    ScrollView {
        VStack(spacing: 0) {
            ReportStatusRow(status: sampleStatus, isSelected: true, onToggle: {})
            ReportStatusRow(status: sampleStatus, isSelected: false, onToggle: {})
        }
        .padding(24)
    }
    .moroTheme(MoroTheme(colorScheme: .light))
}
