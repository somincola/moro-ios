//
//  ReportStatusRow.swift
//  moro
//
//  Row component for selecting statuses to report.
//

import SwiftUI

struct ReportStatusRow: View {
    @Environment(\.moroTheme) private var theme
    
    let status: Status
    let isSelected: Bool
    let onToggle: () -> Void
    
    private var displayStatus: Status {
        status.displayStatus
    }
    
    var body: some View {
        HStack(spacing: theme.spacing.m) {
            // Avatar
            MoroAvatar(
                imageURL: displayStatus.account.avatarAnimatedURL,
                staticImageURL: displayStatus.account.avatarURL,
                initials: displayStatus.account.displayNameInitials,
                size: 36
            )
            
            // Content Preview
            VStack(alignment: .leading, spacing: 4) {
                // Username
                AccountDisplayNameView(
                    account: displayStatus.account,
                    typography: .captionStrong,
                    textColor: theme.colors.textPrimary,
                    lineLimit: 1
                )
                
                // Content
                Text(HTMLParser.stripHTML(displayStatus.content))
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: theme.colors.primary500))
        }
        .padding(.vertical, theme.spacing.s)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle()
        }
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
    
    VStack {
        ReportStatusRow(status: sampleStatus, isSelected: true, onToggle: {})
        Divider()
        ReportStatusRow(status: sampleStatus, isSelected: false, onToggle: {})
    }
    .padding()
}
