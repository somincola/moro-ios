//
//  PollView.swift
//  moro
//
//  Enhanced poll view with voting functionality, progress bars, and visual highlights.
//

import SwiftUI

/// Compact poll view with multiline options, explicit submission feedback, and results.
struct PollView: View {
    let poll: Status.Poll
    let onVote: (([Int]) async -> Bool)?

    @Environment(\.moroTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedChoices: Set<Int> = []
    @State private var submittedChoices: Set<Int> = []
    @State private var isSubmitting = false
    @State private var voteFailed = false

    private enum Metrics {
        static let sectionSpacing: CGFloat = 8
        static let optionCornerRadius: CGFloat = 8
        static let optionHorizontalPadding: CGFloat = 10
        static let optionVerticalPadding: CGFloat = 8
        static let optionMinHeight: CGFloat = 44
        static let optionContentSpacing: CGFloat = 8
        static let optionMaximumLineCount = 3
        static let selectionIconSize: CGFloat = 16
        static let resultSpacing: CGFloat = 5
        static let voteCheckIconSize: CGFloat = 13
        static let percentageMinimumWidth: CGFloat = 48
        static let clockIconSize: CGFloat = 11
        static let metadataSpacing: CGFloat = 6
        static let selectedBorderWidth: CGFloat = 1.5
        static let normalBorderWidth: CGFloat = 1
    }

    init(poll: Status.Poll, onVote: (([Int]) async -> Bool)? = nil) {
        self.poll = poll
        self.onVote = onVote
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                pollOptionView(option: option, index: index)
            }

            if canVote, !selectedChoices.isEmpty {
                voteButton
            }

            if voteFailed {
                Label(MoroL10n.Poll.voteFailed, systemImage: "exclamationmark.circle.fill")
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            pollMetadata
        }
        .onChange(of: poll.id) { _, _ in
            resetTransientState()
        }
        .onChange(of: poll.voted) { _, voted in
            guard voted == true else { return }
            if let ownVotes = poll.ownVotes {
                submittedChoices.formUnion(ownVotes)
            }
            selectedChoices.removeAll()
            isSubmitting = false
            voteFailed = false
        }
    }

    private var hasVoted: Bool {
        poll.voted == true
            || !(poll.ownVotes?.isEmpty ?? true)
            || !submittedChoices.isEmpty
    }

    private var showsResults: Bool {
        hasVoted || poll.expired
    }

    private var showsSelectionControls: Bool {
        onVote != nil && !hasVoted && !poll.expired
    }

    private var canVote: Bool {
        showsSelectionControls && !isSubmitting
    }

    @ViewBuilder
    private func pollOptionView(option: Status.Poll.PollOption, index: Int) -> some View {
        let votes = option.votesCount ?? 0
        let totalVotes = poll.votesCount
        let percentage = totalVotes > 0 ? Double(votes) / Double(totalVotes) : 0.0
        let isUserChoice = (poll.ownVotes?.contains(index) ?? false) || submittedChoices.contains(index)
        let isLeading = isLeadingOption(votes: votes)
        let isSelected = selectedChoices.contains(index)

        Button(action: {
            guard canVote else { return }
            toggleSelection(index: index)
        }) {
            ZStack(alignment: .leading) {
                GeometryReader { geometry in
                    if showsResults {
                        RoundedRectangle(cornerRadius: Metrics.optionCornerRadius)
                            .fill(progressBarColor(isUserChoice: isUserChoice))
                            .frame(width: geometry.size.width * percentage)
                    }
                }

                HStack(alignment: .top, spacing: Metrics.optionContentSpacing) {
                    if showsSelectionControls {
                        Image(systemName: selectionIconName(isSelected: isSelected))
                            .moroScaledFont(size: Metrics.selectionIconSize)
                            .foregroundStyle(isSelected ? theme.colors.primary500 : theme.colors.textSecondary)
                            .frame(width: Metrics.selectionIconSize, height: Metrics.selectionIconSize)
                            .padding(.top, 1)
                    }

                    Text(option.title)
                        .font(theme.typography.caption)
                        .foregroundStyle(theme.colors.textPrimary)
                        .fontWeight(isUserChoice ? .semibold : .regular)
                        .multilineTextAlignment(.leading)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : Metrics.optionMaximumLineCount)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(1)

                    if showsResults {
                        HStack(alignment: .top, spacing: Metrics.resultSpacing) {
                            if isUserChoice {
                                Image(systemName: "checkmark.circle.fill")
                                    .moroScaledFont(size: Metrics.voteCheckIconSize)
                                    .foregroundStyle(theme.colors.success)
                            }

                            Text(percentage, format: .percent.precision(.fractionLength(1)))
                                .font(theme.typography.caption)
                                .fontWeight(isLeading || isUserChoice ? .semibold : .medium)
                                .monospacedDigit()
                                .foregroundStyle(resultTextColor(isUserChoice: isUserChoice, isLeading: isLeading))
                                .frame(minWidth: Metrics.percentageMinimumWidth, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, Metrics.optionHorizontalPadding)
                .padding(.vertical, Metrics.optionVerticalPadding)
            }
            .frame(minHeight: Metrics.optionMinHeight)
            .background(
                RoundedRectangle(cornerRadius: Metrics.optionCornerRadius)
                    .fill(backgroundColor(isSelected: isSelected, isUserChoice: isUserChoice))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.optionCornerRadius)
                    .stroke(
                        borderColor(isSelected: isSelected, isUserChoice: isUserChoice),
                        lineWidth: isSelected || isUserChoice
                            ? Metrics.selectedBorderWidth
                            : Metrics.normalBorderWidth
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canVote)
        .accessibilityAddTraits(isUserChoice ? .isSelected : [])
    }

    private var voteButton: some View {
        Button(action: submitVote) {
            ZStack {
                Text(MoroL10n.Poll.vote)
                    .opacity(isSubmitting ? 0 : 1)

                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.colors.primaryForeground)
                }
            }
            .font(theme.typography.caption)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Metrics.optionMinHeight)
            .foregroundStyle(theme.colors.primaryForeground)
            .background(theme.colors.primary500)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.optionCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    @ViewBuilder
    private var pollMetadata: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    voteCountLabel
                    pollStatusLabel
                    multipleChoiceLabel
                }
            } else {
                HStack(spacing: Metrics.metadataSpacing) {
                    voteCountLabel

                    if hasPollStatus {
                        metadataSeparator
                        pollStatusLabel
                    }

                    if showsMultipleChoiceLabel {
                        metadataSeparator
                        multipleChoiceLabel
                    }
                }
            }
        }
        .font(theme.typography.caption)
        .foregroundStyle(theme.colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var voteCountLabel: some View {
        Text(MoroL10n.Poll.votesCount(poll.votesCount))
    }

    @ViewBuilder
    private var pollStatusLabel: some View {
        if poll.expired {
            Text(MoroL10n.Poll.ended)
        } else if let expiresAt = poll.expiresAt {
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .moroScaledFont(size: Metrics.clockIconSize)
                Text(relativeTimeString(to: expiresAt))
            }
        }
    }

    @ViewBuilder
    private var multipleChoiceLabel: some View {
        if showsMultipleChoiceLabel {
            Text(MoroL10n.Poll.multipleChoice)
                .foregroundStyle(theme.colors.primary500)
        }
    }

    private var metadataSeparator: some View {
        Text("·")
    }

    private var hasPollStatus: Bool {
        poll.expired || poll.expiresAt != nil
    }

    private var showsMultipleChoiceLabel: Bool {
        poll.multiple && !hasVoted && !poll.expired
    }

    private func toggleSelection(index: Int) {
        if poll.multiple {
            if selectedChoices.contains(index) {
                selectedChoices.remove(index)
            } else {
                selectedChoices.insert(index)
            }
        } else {
            selectedChoices = [index]
        }
        voteFailed = false
    }

    private func submitVote() {
        guard let onVote, !selectedChoices.isEmpty, !isSubmitting else { return }

        let choices = Array(selectedChoices).sorted()
        isSubmitting = true
        voteFailed = false

        Task { @MainActor in
            let succeeded = await onVote(choices)
            isSubmitting = false

            if succeeded {
                submittedChoices = Set(choices)
                selectedChoices.removeAll()
            } else {
                voteFailed = true
            }
        }
    }

    private func isLeadingOption(votes: Int) -> Bool {
        guard showsResults else { return false }
        let maxVotes = poll.options.compactMap { $0.votesCount }.max() ?? 0
        return votes > 0 && votes == maxVotes
    }

    private func selectionIconName(isSelected: Bool) -> String {
        if poll.multiple {
            return isSelected ? "checkmark.square.fill" : "square"
        }
        return isSelected ? "circle.inset.filled" : "circle"
    }

    private func progressBarColor(isUserChoice: Bool) -> Color {
        if isUserChoice {
            return theme.colors.success.opacity(0.16)
        }
        return theme.colors.textSecondary.opacity(0.12)
    }

    private func resultTextColor(isUserChoice: Bool, isLeading: Bool) -> Color {
        if isUserChoice { return theme.colors.success }
        if isLeading { return theme.colors.textPrimary }
        return theme.colors.textSecondary
    }

    private func backgroundColor(isSelected: Bool, isUserChoice: Bool) -> Color {
        if isSelected {
            return theme.colors.primary500.opacity(0.07)
        } else if isUserChoice {
            return theme.colors.success.opacity(0.05)
        } else {
            return theme.colors.surfaceSubtle
        }
    }

    private func borderColor(isSelected: Bool, isUserChoice: Bool) -> Color {
        if isSelected {
            return theme.colors.primary500
        } else if isUserChoice {
            return theme.colors.success
        } else {
            return theme.colors.border
        }
    }

    private func resetTransientState() {
        selectedChoices.removeAll()
        submittedChoices.removeAll()
        isSubmitting = false
        voteFailed = false
    }

    private func relativeTimeString(to date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval < 0 {
            return MoroL10n.Poll.statusEnded
        }

        let hours = Int(interval / 3600)
        let days = hours / 24

        if days > 0 {
            return MoroL10n.Poll.endsInDays(days)
        } else if hours > 0 {
            return MoroL10n.Poll.endsInHours(hours)
        } else {
            let minutes = Int(interval / 60)
            return MoroL10n.Poll.endsInMinutes(minutes)
        }
    }
}

// MARK: - Preview

#Preview {
    let samplePoll = Status.Poll(
        id: "1",
        expiresAt: Date().addingTimeInterval(86400 * 5 + 3600 * 20), // 5 days, 20 hours
        expired: false,
        multiple: false,
        votesCount: 13,
        votersCount: 13,
        options: [
            Status.Poll.PollOption(title: "思源宋体", votesCount: 4),
            Status.Poll.PollOption(title: "霞鹜文楷", votesCount: 9)
        ],
        voted: nil,
        ownVotes: nil
    )

    let votedPoll = Status.Poll(
        id: "2",
        expiresAt: Date().addingTimeInterval(86400 * 2),
        expired: false,
        multiple: false,
        votesCount: 13,
        votersCount: 13,
        options: [
            Status.Poll.PollOption(title: "如果只能选一个世界上最讨厌的生物，我会选择它", votesCount: 0),
            Status.Poll.PollOption(title: "非常讨厌，特别讨厌，超级讨厌", votesCount: 9),
            Status.Poll.PollOption(title: "超爱，但屏幕粉，不是很希望真实见面破坏这份浪漫", votesCount: 4)
        ],
        voted: true,
        ownVotes: [1]
    )

    let multiChoicePoll = Status.Poll(
        id: "3",
        expiresAt: Date().addingTimeInterval(3600 * 3),
        expired: false,
        multiple: true,
        votesCount: 25,
        votersCount: 10,
        options: [
            Status.Poll.PollOption(title: "选项 A", votesCount: 8),
            Status.Poll.PollOption(title: "选项 B", votesCount: 12),
            Status.Poll.PollOption(title: "选项 C", votesCount: 5)
        ],
        voted: true,
        ownVotes: [0, 1]
    )

    ScrollView {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("未投票状态")
                    .font(.headline)
                PollView(poll: samplePoll) { _ in true }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("已投票状态")
                    .font(.headline)
                PollView(poll: votedPoll)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("多选投票（已投票）")
                    .font(.headline)
                PollView(poll: multiChoicePoll)
            }
        }
        .padding()
    }
    .moroTheme(MoroTheme())
}
