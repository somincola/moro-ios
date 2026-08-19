//
//  RegistrationRulesView.swift
//  moro
//
//  Step 3 of sign-up: the server's rules, with a language switcher. Rules default to
//  the system language (or English); each rule falls back to its default text when the
//  selected language is missing.
//

import SwiftUI

struct RegistrationRulesView: View {
    let rules: [MastodonInstanceRule]
    let onContinue: () -> Void

    @Environment(\.moroTheme) private var theme
    @State private var selectedLanguage: String

    init(rules: [MastodonInstanceRule], onContinue: @escaping () -> Void) {
        self.rules = rules
        self.onContinue = onContinue
        _selectedLanguage = State(initialValue: Self.defaultLanguage(for: rules))
    }

    /// Languages the rules carry translations for, plus English as the universal fallback.
    private var availableLanguages: [String] {
        var set = Set<String>()
        for rule in rules {
            for key in (rule.translations ?? [:]).keys {
                set.insert(key.lowercased())
            }
        }
        set.insert("en")
        return set.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.spacing.xl) {
                header

                rulesList
            }
            .padding(theme.spacing.xl)
            .padding(.bottom, 80)
        }
        .background(theme.colors.surfaceBase)
        .navigationTitle(MoroL10n.Registration.navTitleRules)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            continueFooter
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: theme.spacing.l) {
                headerText

                Spacer(minLength: theme.spacing.m)

                if availableLanguages.count > 1 {
                    languageMenu
                }
            }

            VStack(alignment: .leading, spacing: theme.spacing.m) {
                headerText

                if availableLanguages.count > 1 {
                    languageMenu
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headerText: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            Text(MoroL10n.Login.Info.rulesTitle)
                .moroScaledFont(size: 24, weight: .semibold, relativeTo: .title3)
                .foregroundStyle(theme.colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(MoroL10n.Registration.summaryRules)
                .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var rulesList: some View {
        if rules.isEmpty {
            Text(MoroL10n.Registration.noRules)
                .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                .foregroundStyle(theme.colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(theme.spacing.l)
                .moroCardSurface(cornerRadius: 18, tone: .base)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    ruleRow(index: index, rule: rule)

                    if index < rules.count - 1 {
                        Rectangle()
                            .fill(theme.colors.borderSubtle)
                            .frame(height: 1)
                            .padding(.leading, 48)
                    }
                }
            }
            .padding(.horizontal, theme.spacing.l)
            .moroCardSurface(cornerRadius: 18, tone: .base)
        }
    }

    private func ruleRow(index: Int, rule: MastodonInstanceRule) -> some View {
        HStack(alignment: .top, spacing: theme.spacing.m) {
            Text(String(format: "%02d", index + 1))
                .moroScaledFont(size: 12, weight: .semibold, relativeTo: .footnote)
                .monospacedDigit()
                .foregroundStyle(theme.colors.textTertiary)
                .frame(width: 32, alignment: .leading)
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: theme.spacing.s) {
                Text(HTMLParser.stripHTML(rule.localizedText(languageIdentifiers: [selectedLanguage])))
                    .moroScaledFont(size: 16, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(theme.colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let hint = ruleHint(rule) {
                    Text(hint)
                        .moroScaledFont(size: 14, weight: .regular, relativeTo: .subheadline)
                        .foregroundStyle(theme.colors.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, theme.spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var languageMenu: some View {
        Menu {
            ForEach(availableLanguages, id: \.self) { lang in
                Button {
                    selectedLanguage = lang
                } label: {
                    if lang == selectedLanguage {
                        Label(Self.autonym(for: lang), systemImage: "checkmark")
                    } else {
                        Text(Self.autonym(for: lang))
                    }
                }
            }
        } label: {
            HStack(spacing: theme.spacing.xs) {
                Text(Self.autonym(for: selectedLanguage))
                    .moroScaledFont(size: 13, weight: .semibold, relativeTo: .footnote)
                Image(systemName: "chevron.down")
                    .moroScaledFont(size: 10, weight: .semibold)
            }
            .foregroundStyle(theme.colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(theme.colors.surfaceSubtle))
            .overlay {
                Capsule()
                    .stroke(theme.colors.borderSubtle, lineWidth: 1)
            }
        }
    }

    private var continueFooter: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.colors.borderSubtle)
                .frame(height: 1)

            Button {
                onContinue()
            } label: {
                Text(MoroL10n.Registration.continueButton)
                    .moroScaledFont(size: 15, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(theme.colors.primaryForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.colors.primary500)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, theme.spacing.xl)
            .padding(.top, theme.spacing.m)
            .padding(.bottom, theme.spacing.m)
        }
        .background(theme.colors.surfaceBase)
    }

    private static func defaultLanguage(for rules: [MastodonInstanceRule]) -> String {
        var available = Set<String>()
        for rule in rules {
            for key in (rule.translations ?? [:]).keys {
                available.insert(key.lowercased())
            }
        }
        available.insert("en")

        if let system = Locale.preferredLanguages.first {
            let lower = system.lowercased()
            if available.contains(lower) { return lower }
            let primary = system.split(separator: "-").first.map { String($0).lowercased() } ?? lower
            if available.contains(primary) { return primary }
        }
        return available.contains("en") ? "en" : (available.sorted().first ?? "en")
    }

    private func ruleHint(_ rule: MastodonInstanceRule) -> String? {
        guard let hint = rule.localizedHint(languageIdentifiers: [selectedLanguage]) else { return nil }
        let stripped = HTMLParser.stripHTML(hint).trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.isEmpty ? nil : stripped
    }

    /// Each language written in its OWN language (autonym): en → "English", zh-Hans →
    /// "简体中文", zh-Hant → "繁體中文", fr → "français", …
    private static func autonym(for code: String) -> String {
        let key = code.lowercased()
        let overrides: [String: String] = [
            "en": "English",
            "zh": "简体中文", "zh-hans": "简体中文", "zh-cn": "简体中文", "zh-sg": "简体中文",
            "zh-hant": "繁體中文", "zh-tw": "繁體中文", "zh-hk": "繁體中文", "zh-mo": "繁體中文",
        ]
        if let override = overrides[key] { return override }
        let locale = Locale(identifier: code)
        if let name = locale.localizedString(forIdentifier: code), !name.isEmpty {
            return name
        }
        if let name = locale.localizedString(forLanguageCode: code), !name.isEmpty {
            return name
        }
        return code.uppercased()
    }
}
