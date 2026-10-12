import SwiftUI

enum ComposePreviewContent {
    static func elements(for text: String) -> [ContentElement] {
        ContentParser.parseToElements(html: html(for: text), options: [.autoDetectPlainLinks, .preserveInlineWhitespace])
    }

    /// Compose accepts plain source text. Escape it before using the native HTML renderer.
    static func html(for text: String) -> String {
        "<p>" + text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: "<br>") + "</p>"
    }
}

struct ComposePreviewSheet: View {
    @ObservedObject var viewModel: ComposeViewModel
    let account: Account?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.moroTheme) private var theme

    var body: some View {
        let bodyFont = theme.postUIFont()
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: theme.spacing.m) {
                    if let account {
                        HStack(spacing: theme.spacing.s) {
                            MoroAvatar(imageURL: account.avatarURL, initials: account.displayNameInitials, size: 40)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(account.displayName).font(theme.typography.subtitle)
                                Text("@\(account.acct)").font(theme.typography.caption)
                                    .foregroundStyle(theme.colors.textSecondary)
                            }
                        }
                    }
                    if viewModel.isContentWarningActive, !viewModel.contentWarning.isEmpty {
                        Text(viewModel.contentWarning).font(Font(theme.postUIFont(sizeAdjustment: -1, weight: .semibold)))
                            .accessibilityIdentifier("compose.previewCW")
                        MoroDivider()
                    }
                    RichTextContentView(
                        elements: ComposePreviewContent.elements(for: viewModel.content),
                        emojiSize: bodyFont.pointSize * 1.25,
                        fontOverride: Font(bodyFont),
                        uiFontOverride: bodyFont,
                        lineSpacing: 4 * bodyFont.pointSize / 16,
                        onLinkTap: { action in
                            switch action {
                            case .link(let url), .mention(_, let url), .hashtag(_, let url): openURL(url)
                            }
                        }
                    )
                    .accessibilityIdentifier("compose.previewBody")
                    ComposeMediaGridView(attachments: viewModel.mediaAttachments,
                        onRemove: { _ in }, onEditAlt: { _ in }, onRetry: { _ in }, showsEditingControls: false)
                    if viewModel.isPollActive {
                        ForEach(Array(viewModel.pollOptions.enumerated()), id: \.offset) { _, option in
                            Label(option, systemImage: viewModel.pollMultiple ? "square" : "circle")
                                .font(Font(theme.postUIFont(sizeAdjustment: -3)))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }
                    }
                    if case .quote(let original) = viewModel.context, let original {
                        ComposeOriginalPostSection(originalStatus: original, presentationStyle: .quote)
                    }
                }
                .padding(theme.spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(theme.colors.surfaceBase)
            .navigationTitle(MoroL10n.ComposeReading.preview)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(MoroL10n.Common.done) { dismiss() }.accessibilityIdentifier("compose.previewDone")
                }
            }
        }
    }
}

struct ComposeMediaOrderSheet: View {
    @ObservedObject var viewModel: ComposeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(viewModel.mediaAttachments.enumerated()), id: \.element.id) { index, attachment in
                        HStack(spacing: theme.spacing.m) {
                            Text("\(index + 1)").monospacedDigit()
                                .foregroundStyle(theme.colors.textSecondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(attachment.description?.isEmpty == false ? attachment.description! : MoroL10n.ComposeReading.attachment(index + 1))
                                    .lineLimit(2)
                                if !attachment.uploadState.isUploaded {
                                    Text(MoroL10n.ComposeReading.uploadPending)
                                        .font(theme.typography.caption)
                                        .foregroundStyle(theme.colors.textSecondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("compose.order.\(attachment.id)")
                        .accessibilityAction(named: MoroL10n.ComposeReading.moveUp) {
                            if index > 0 { viewModel.moveMedia(from: IndexSet(integer: index), to: index - 1) }
                        }
                        .accessibilityAction(named: MoroL10n.ComposeReading.moveDown) {
                            if index + 1 < viewModel.mediaAttachments.count {
                                viewModel.moveMedia(from: IndexSet(integer: index), to: index + 2)
                            }
                        }
                    }
                    .onMove(perform: viewModel.moveMedia)
                } footer: {
                    Text(MoroL10n.ComposeReading.orderHint)
                }
            }
            .environment(\.editMode, .constant(.active))
            .moroSettingsListChrome()
            .navigationTitle(MoroL10n.ComposeReading.mediaOrder)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(MoroL10n.Common.done) { dismiss() }.accessibilityIdentifier("compose.orderDone")
                }
            }
        }
    }
}
