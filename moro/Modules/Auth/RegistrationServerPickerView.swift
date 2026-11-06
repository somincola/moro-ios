//
//  RegistrationServerPickerView.swift
//  moro
//
//  Step 1 of sign-up: choose a federated server or browse the full directory.
//  Selecting one moves on to the server info step.
//

import SwiftUI

struct RegistrationServerPickerView: View {
    let onClose: () -> Void
    let onSelectServer: (String) -> Void

    @Environment(\.moroTheme) private var theme
    @State private var customDomain = RecommendedServers.primary
    @State private var formatError = false
    @FocusState private var customFieldFocused: Bool

    private let popularServers = RecommendedServers.others

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: theme.spacing.xxxl) {
                        header
                        customServerSection
                    }

                    Spacer(minLength: theme.spacing.xxxl)

                    popularSection
                }
                .padding(.horizontal, theme.spacing.xl)
                .padding(.top, theme.spacing.xxl)
                .padding(.bottom, 56)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
            .background(theme.colors.surfaceBase)
        }
        .navigationTitle(MoroL10n.Login.Server.navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                MoroToolbarButton(MoroL10n.Common.close, kind: .close) { onClose() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: theme.spacing.l) {
            Image("AppIconPreviewDefault")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(theme.colors.borderSubtle, lineWidth: 1)
                }
                .shadow(color: theme.colors.textPrimary.opacity(0.08), radius: 14, y: 8)
                .accessibilityHidden(true)

            VStack(spacing: theme.spacing.s) {
                Text(MoroL10n.Login.Server.title)
                    .font(theme.typography.title)
                    .foregroundStyle(theme.colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(MoroL10n.Login.Server.subtitle)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Server input

    private var customServerSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.m) {
            Text(MoroL10n.Login.instanceAddress)
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.textPrimary)

            HStack(spacing: theme.spacing.s) {
                Image(systemName: "globe")
                    .moroScaledFont(size: 16)
                    .foregroundStyle(theme.colors.textSecondary)

                TextField(RecommendedServers.primary, text: $customDomain)
                    .font(theme.typography.body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($customFieldFocused)
                    .onSubmit { submitCustom() }
                    .onChange(of: customDomain) { _, _ in formatError = false }

                if !customDomain.isEmpty {
                    Button {
                        customDomain = ""
                        formatError = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .moroScaledFont(size: 16)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    submitCustom()
                } label: {
                    Image(systemName: "arrow.right.circle.fill")
                        .moroScaledFont(size: 26, weight: .semibold)
                        .foregroundStyle(customDomainIsEmpty ? theme.colors.textTertiary : theme.colors.primary500)
                }
                .buttonStyle(.plain)
                .disabled(customDomainIsEmpty)
                .accessibilityLabel(MoroL10n.Login.Server.continueButton)
            }
            .padding(.horizontal, theme.spacing.m)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.colors.surfaceSubtle)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        formatError ? theme.colors.error : theme.colors.borderSubtle,
                        lineWidth: 1
                    )
            )

            if formatError {
                Text(MoroL10n.Login.errorInvalidFormat)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.error)
            }
        }
    }

    // MARK: - Popular

    private var popularSection: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text(MoroL10n.Login.Server.popularTitle)
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.textPrimary)

            VStack(spacing: 0) {
                ForEach(popularServers, id: \.self) { server in
                    Button {
                        selectServer(server)
                    } label: {
                        HStack(spacing: theme.spacing.m) {
                            Text(server)
                                .font(theme.typography.bodyStrong)
                                .foregroundStyle(theme.colors.textPrimary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .moroScaledFont(size: 13, weight: .semibold)
                                .foregroundStyle(theme.colors.textTertiary)
                        }
                        .padding(.vertical, theme.spacing.m)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    MoroDivider()
                }

                browseAllRow
            }
            .padding(.horizontal, theme.spacing.m)
            .moroCardSurface(cornerRadius: 16, tone: .base)
        }
    }

    private var browseAllRow: some View {
        Button {
            guard let url = URL(string: "https://joinmastodon.org/servers") else { return }
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: theme.spacing.m) {
                Image(systemName: "safari")
                    .moroScaledFont(size: 14, weight: .semibold)
                    .foregroundStyle(theme.colors.primary500)
                    .frame(width: 28, height: 28)

                Text(MoroL10n.Login.Server.browseAll)
                    .font(theme.typography.bodyStrong)
                    .foregroundStyle(theme.colors.primary500)

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right")
                    .moroScaledFont(size: 12, weight: .semibold)
                    .foregroundStyle(theme.colors.primary500)
            }
            .padding(.vertical, theme.spacing.m)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Actions

    private var customDomainIsEmpty: Bool {
        customDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitCustom() {
        let domain = AuthDomainUtility.sanitize(customDomain)
        guard AuthDomainUtility.isLikelyDomain(domain) else {
            formatError = true
            return
        }
        selectServer(domain)
    }

    private func selectServer(_ value: String) {
        let domain = AuthDomainUtility.sanitize(value)
        guard AuthDomainUtility.isLikelyDomain(domain) else {
            customDomain = value
            customFieldFocused = true
            formatError = true
            return
        }
        customFieldFocused = false
        formatError = false
        onSelectServer(domain)
    }
}
