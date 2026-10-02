//
//  RegistrationFlowView.swift
//  moro
//
//  In-app account registration flow: form -> pending/authenticated.
//

import SwiftUI
import UIKit
import SafariServices

struct RegistrationFlowView: View {
    private enum Step {
        case form
        case pending
    }

    private enum FormField: Hashable {
        case username
        case email
        case password
        case passwordConfirmation
        case reason
    }

    @ObservedObject var authService: AuthService
    let instanceDomain: String
    let onRegistrationAuthenticated: (String, Account, URL) -> Void
    var onRequestBackToLogin: ((String, String?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.moroTheme) private var theme
    @FocusState private var focusedField: FormField?

    @State private var step: Step = .form
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var dateOfBirth: Date?
    @State private var birthdayDraft = Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    @State private var reason = ""
    @State private var agreedToRules = false
    @State private var isSubmitting = false
    @State private var hasAttemptedSubmit = false
    @State private var pendingEmail = ""
    @State private var pendingHint = ""
    @State private var pendingRequiresApproval = false
    @State private var showingBirthdayPicker = false
    @State private var safariSheetURL: SafariSheetURL?
    @State private var feedbackMessage: String?
    @State private var feedbackKind: AppFeedbackKind = .info

    private var registrationInfo: InstanceRegistrationInfo? {
        authService.currentRegistrationInfo
    }

    private var requiresReason: Bool {
        registrationInfo?.reasonRequired ?? false
    }

    private var minAgeRequirement: Int? {
        registrationInfo?.minAge
    }

    private var termsURL: URL? {
        guard !instanceDomain.isEmpty else { return nil }
        return URL(string: "https://\(instanceDomain)/terms")
    }

    private var privacyPolicyURL: URL? {
        guard !instanceDomain.isEmpty else { return nil }
        return URL(string: "https://\(instanceDomain)/privacy-policy")
    }

    private var resendConfirmationURL: URL? {
        guard !instanceDomain.isEmpty else { return nil }
        return URL(string: "https://\(instanceDomain)/auth/confirmation/new")
    }

    private var birthdaySelectionRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let minimum = calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)) ?? Date.distantPast
        if let minAge = minAgeRequirement,
            let maximum = calendar.date(byAdding: .year, value: -minAge, to: Date())
        {
            return minimum...maximum
        }
        return minimum...Date()
    }

    private var defaultBirthday: Date {
        if let minAge = minAgeRequirement,
            let recommended = Calendar.current.date(byAdding: .year, value: -minAge, to: Date())
        {
            return recommended
        }
        return Calendar.current.date(byAdding: .year, value: -18, to: Date()) ?? Date()
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isUsernameValid: Bool {
        !trimmedUsername.isEmpty && isUsernameFormatValid
    }

    private var isUsernameFormatValid: Bool {
        trimmedUsername.range(of: #"^[A-Za-z0-9_]+$"#, options: .regularExpression) != nil
    }

    private var isEmailFormatValid: Bool {
        isValidEmail(trimmedEmail)
    }

    private var isPasswordLengthValid: Bool {
        password.count >= 8
    }

    private var isPasswordConfirmed: Bool {
        !passwordConfirmation.isEmpty && password == passwordConfirmation
    }

    private var isReasonValid: Bool {
        !requiresReason || !trimmedReason.isEmpty
    }

    private var isBirthdaySelected: Bool {
        dateOfBirth != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: theme.spacing.l) {
                switch step {
                case .form:
                    if let feedbackMessage {
                        InlineFeedbackCard(
                            kind: feedbackKind,
                            message: feedbackMessage
                        )
                    }

                    formContent
                case .pending:
                    pendingContent
                }
            }
            .padding(.horizontal, theme.spacing.xl)
            .padding(.top, theme.spacing.xl)
            .padding(.bottom, step == .form ? 80 : 0)
        }
        .background(theme.colors.surfaceBase)
        .safeAreaInset(edge: .bottom) {
            submitFooter
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(step == .pending)
        .onChange(of: editingSignature) { _, _ in
            clearEditingFeedbackIfNeeded()
        }
        .sheet(item: $safariSheetURL) { item in
            SafariSheetView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showingBirthdayPicker) {
            birthdayPickerSheet
        }
    }

    /// Single value tracking every editable field, so one `.onChange` clears the validation
    /// feedback (seven separate modifiers blew the body's type-check budget).
    private var editingSignature: String {
        "\(username)|\(email)|\(password)|\(passwordConfirmation)|\(dateOfBirth?.timeIntervalSince1970 ?? -1)|\(reason)|\(agreedToRules)"
    }

    private var navigationTitle: String {
        switch step {
        case .form:
            return MoroL10n.Registration.navTitleForm
        case .pending:
            return pendingRequiresApproval ? MoroL10n.Registration.navTitlePendingApproval : MoroL10n.Registration.navTitlePendingEmail
        }
    }

    /// The system back button steps back through the sign-up flow.
    private func cancelToLogin() {
        if let onRequestBackToLogin {
            onRequestBackToLogin(instanceDomain, nil)
        } else {
            dismiss()
        }
    }

    private var formContent: some View {
        VStack(spacing: theme.spacing.l) {
            if registrationInfo?.registrationsOpen == false {
                InlineFeedbackCard(
                    kind: .error,
                    message: registrationInfo?.registrationMessage?.isEmpty == false
                        ? (registrationInfo?.registrationMessage ?? MoroL10n.Registration.closedForbidden)
                        : MoroL10n.Registration.closedForbiddenLong
                )
            }

            formFieldsGroup

            agreementCard
        }
    }

    private var formFieldsGroup: some View {
        VStack(spacing: 0) {
            fieldRow(label: MoroL10n.Registration.fieldUsername, error: usernameError, isRequired: true) {
                HStack(spacing: 0) {
                    TextField("", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .textContentType(.username)
                        .submitLabel(.next)
                        .font(theme.typography.body)
                        .focused($focusedField, equals: .username)
                        .onSubmit {
                            focusedField = .email
                        }
                        .onChange(of: username) { _, newValue in
                            let sanitized = sanitizedUsername(newValue)
                            if sanitized != newValue {
                                username = sanitized
                            }
                        }

                    Text("@\(instanceDomain)")
                        .font(theme.typography.body)
                        .foregroundStyle(theme.colors.textTertiary)
                        .lineLimit(1)
                }
            }

            fieldDivider

            fieldRow(label: MoroL10n.Registration.fieldEmail, error: emailError, isRequired: true) {
                // `Text(verbatim:)` skips LocalizedStringKey markdown parsing — otherwise the
                // email-shaped placeholder gets auto-linked and rendered in the accent colour.
                TextField("", text: $email, prompt: Text(verbatim: "name@example.com"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .submitLabel(.next)
                    .font(theme.typography.body)
                    .focused($focusedField, equals: .email)
                    .onSubmit {
                        focusedField = .password
                    }
            }

            fieldDivider

            fieldRow(label: MoroL10n.Registration.fieldPassword, error: passwordError, isRequired: true) {
                SecureField(MoroL10n.Registration.fieldPasswordPlaceholder, text: $password)
                    .textContentType(.newPassword)
                    .submitLabel(.next)
                    .font(theme.typography.body)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        focusedField = .passwordConfirmation
                    }
            }

            fieldDivider

            fieldRow(label: MoroL10n.Registration.fieldConfirmPassword, error: passwordConfirmationError, isRequired: true) {
                SecureField(MoroL10n.Registration.fieldConfirmPasswordPlaceholder, text: $passwordConfirmation)
                    .textContentType(.newPassword)
                    .submitLabel(requiresReason ? .next : .done)
                    .font(theme.typography.body)
                    .focused($focusedField, equals: .passwordConfirmation)
                    .onSubmit {
                        focusedField = requiresReason ? .reason : nil
                    }
            }

            fieldDivider

            fieldRow(label: MoroL10n.Registration.fieldBirthday, hint: birthdayHint, error: birthdayError, isRequired: true) {
                Button {
                    focusedField = nil
                    birthdayDraft = dateOfBirth ?? defaultBirthday
                    showingBirthdayPicker = true
                } label: {
                    HStack(spacing: theme.spacing.xs) {
                        Text(formattedBirthday)
                            .font(theme.typography.body)
                            .foregroundStyle(dateOfBirth == nil ? theme.colors.textTertiary : theme.colors.textPrimary)

                        Image(systemName: "chevron.down")
                            .moroScaledFont(size: 11, weight: .semibold)
                            .foregroundStyle(theme.colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            if requiresReason {
                fieldDivider

                verticalFieldRow(label: MoroL10n.Registration.fieldReason, hint: reasonHint, error: reasonError, isRequired: true) {
                    TextField(MoroL10n.Registration.fieldReasonPlaceholder, text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                        .submitLabel(.done)
                        .font(theme.typography.body)
                        .focused($focusedField, equals: .reason)
                        .onSubmit {
                            focusedField = nil
                        }
                }
            }
        }
    }

    /// Bottom-pinned primary CTA, mirroring the rules page footer. Only the form step shows it;
    /// the pending step carries its own centered "back to login" button.
    @ViewBuilder private var submitFooter: some View {
        if step == .form {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(theme.colors.borderSubtle)
                    .frame(height: 1)

                submitButton
                    .frame(maxWidth: 260)
                    .padding(.horizontal, theme.spacing.xl)
                    .padding(.top, theme.spacing.m)
                    .padding(.bottom, theme.spacing.m)
            }
            .background(theme.colors.surfaceBase)
        }
    }

    private var submitButton: some View {
        let isEnabled = canSubmit && !isSubmitting
        let canAttempt = registrationInfo?.registrationsOpen != false && !isSubmitting
        let isProminent = isEnabled || isSubmitting

        return Button {
            submitRegistration()
        } label: {
            ZStack {
                Text(isSubmitting ? MoroL10n.Registration.submitting : submitButtonTitle)
                    .font(theme.typography.subtitle)
                    .opacity(isSubmitting ? 0 : 1)

                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.colors.primaryForeground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .foregroundStyle(isProminent ? theme.colors.primaryForeground : theme.colors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isProminent ? theme.colors.primary500 : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isProminent ? Color.clear : theme.colors.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canAttempt)
        .opacity(canAttempt ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.15), value: isProminent)
    }

    private var birthdayPickerSheet: some View {
        VStack(spacing: theme.spacing.l) {
            HStack {
                Button(MoroL10n.Common.cancel) {
                    showingBirthdayPicker = false
                }
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.textSecondary)

                Spacer()

                Text(MoroL10n.Registration.fieldBirthday)
                    .font(theme.typography.subtitle)
                    .foregroundStyle(theme.colors.textPrimary)

                Spacer()

                Button(MoroL10n.Common.done) {
                    dateOfBirth = birthdayDraft
                    showingBirthdayPicker = false
                }
                .font(theme.typography.bodyStrong)
                .foregroundStyle(theme.colors.primary500)
            }
            .padding(.horizontal, theme.spacing.xl)

            DatePicker(
                MoroL10n.Registration.fieldBirthdayPicker,
                selection: $birthdayDraft,
                in: birthdaySelectionRange,
                displayedComponents: .date
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
        }
        .padding(.top, theme.spacing.l)
        .padding(.bottom, theme.spacing.xl)
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }

    private var pendingContent: some View {
        VStack(spacing: theme.spacing.m) {
            Image(systemName: pendingRequiresApproval ? "clock.badge.checkmark" : "checkmark.circle.fill")
                .moroScaledFont(size: 56, weight: .regular)
                .foregroundStyle(pendingRequiresApproval ? theme.colors.primary500 : theme.colors.success)
                .padding(.bottom, theme.spacing.s)

            Text(pendingRequiresApproval ? MoroL10n.Registration.headlinePendingApproval : MoroL10n.Registration.pendingConfirmEmail)
                .font(theme.typography.title)
                .foregroundStyle(theme.colors.textPrimary)
                .multilineTextAlignment(.center)

            // Open registration → "verify your email"; approval → "awaiting review, you'll
            // get an email once approved".
            Text(pendingRequiresApproval ? MoroL10n.Registration.summaryPendingApproval : MoroL10n.Registration.successEmail)
                .font(theme.typography.body)
                .foregroundStyle(theme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !pendingEmail.isEmpty {
                Text(MoroL10n.Registration.pendingAccount(pendingEmail))
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textTertiary)
                    .multilineTextAlignment(.center)
            }

            if !pendingHint.isEmpty {
                Text(pendingHint)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            MoroButton(title: MoroL10n.Registration.pendingBackToLogin, kind: .primary) {
                cancelToLogin()
            }
            .padding(.top, theme.spacing.m)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, theme.spacing.xl)
    }

    private struct SafariSheetURL: Identifiable {
        let id = UUID()
        let url: URL
    }

    private struct SafariSheetView: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> SFSafariViewController {
            let controller = SFSafariViewController(url: url)
            controller.dismissButtonStyle = .close
            return controller
        }

        func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
            // no-op
        }
    }

    private func fieldRow<Content: View>(
        label: String,
        hint: String? = nil,
        error: String? = nil,
        isRequired: Bool = false,
        @ViewBuilder input: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            requiredLabel(label, isRequired: isRequired)

            input()
                .foregroundStyle(theme.colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 30)

            if let message = error ?? hint {
                Text(message)
                    .font(theme.typography.caption)
                    .foregroundStyle(error == nil ? theme.colors.textTertiary : theme.colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func verticalFieldRow<Content: View>(
        label: String,
        hint: String? = nil,
        error: String? = nil,
        isRequired: Bool = false,
        @ViewBuilder input: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            requiredLabel(label, isRequired: isRequired)

            input()
                .foregroundStyle(theme.colors.textPrimary)

            if let message = error ?? hint {
                Text(message)
                    .font(theme.typography.caption)
                    .foregroundStyle(error == nil ? theme.colors.textTertiary : theme.colors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, theme.spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requiredLabel(_ label: String, isRequired: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .font(theme.typography.caption)
                .fontWeight(.semibold)
                .foregroundStyle(theme.colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if isRequired {
                Text("*")
                    .font(theme.typography.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(theme.colors.error)
            }
        }
    }

    private var fieldDivider: some View {
        Rectangle()
            .fill(theme.colors.borderSubtle)
            .frame(height: 1)
    }

    private var agreementCard: some View {
        VStack(alignment: .leading, spacing: theme.spacing.s) {
            HStack(alignment: .top, spacing: theme.spacing.m) {
                Button {
                    agreedToRules.toggle()
                } label: {
                    Image(systemName: agreedToRules ? "checkmark.circle.fill" : "circle")
                        .moroScaledFont(size: 22, weight: .semibold)
                        .foregroundStyle(agreedToRules ? theme.colors.primary500 : theme.colors.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(MoroL10n.Registration.agreement)
                .accessibilityAddTraits(agreedToRules ? .isSelected : [])

                agreementConsentText
                    .font(theme.typography.caption)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let agreementError {
                Text(agreementError)
                    .font(theme.typography.caption)
                    .foregroundStyle(theme.colors.error)
                    .padding(.leading, 28 + theme.spacing.m)
            }
        }
        .padding(.top, theme.spacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Consent line with the terms-of-service and privacy-policy as inline tappable links,
    /// built from markdown so they sit inside the sentence. Plain text uses the secondary
    /// colour; the link runs are explicitly tinted so they read clearly as links. Tapping a
    /// link opens its URL.
    private var agreementConsentText: Text {
        let terms = termsURL?.absoluteString ?? ""
        let privacy = privacyPolicyURL?.absoluteString ?? ""
        let markdown = MoroL10n.Registration.agreementConsent(termsURL: terms, privacyURL: privacy)
        guard var attributed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return Text(MoroL10n.Registration.agreement)
        }
        attributed.foregroundColor = theme.colors.textSecondary
        // Tint link runs without the heavier default underline so the consent row stays quiet.
        let linkRanges = attributed.runs.filter { $0.link != nil }.map(\.range)
        for range in linkRanges {
            attributed[range].foregroundColor = theme.colors.primary500
        }
        return Text(attributed)
    }

    private var birthdayHint: String? {
        return minAgeRequirement.map { MoroL10n.Registration.hintMinAge($0) }
    }

    private var formattedBirthday: String {
        guard let dateOfBirth else { return MoroL10n.Registration.birthdayPlaceholder }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = MoroL10n.preferredLocale
        formatter.dateStyle = .medium
        return formatter.string(from: dateOfBirth)
    }

    private var reasonHint: String {
        if trimmedReason.isEmpty {
            return MoroL10n.Registration.hintReasonEmpty
        }
        return MoroL10n.Registration.hintReasonFilled
    }

    private var submitButtonTitle: String {
        registrationInfo?.approvalRequired == true ? MoroL10n.Registration.submitApproval : MoroL10n.Registration.submitRegister
    }

    private var canSubmit: Bool {
        if registrationInfo?.registrationsOpen == false {
            return false
        }
        if !isUsernameValid {
            return false
        }
        if !isEmailFormatValid {
            return false
        }
        if !isPasswordLengthValid || !isPasswordConfirmed {
            return false
        }
        if !isReasonValid {
            return false
        }
        if !isBirthdaySelected {
            return false
        }
        if !isAgeRequirementSatisfied {
            return false
        }
        return agreedToRules
    }

    private func clearEditingFeedbackIfNeeded() {
        guard step == .form else { return }
        feedbackMessage = nil
    }

    private func focusFirstInvalidField() {
        if !isUsernameValid {
            focusedField = .username
        } else if !isEmailFormatValid {
            focusedField = .email
        } else if !isPasswordLengthValid {
            focusedField = .password
        } else if !isPasswordConfirmed {
            focusedField = .passwordConfirmation
        } else if requiresReason, !isReasonValid {
            focusedField = .reason
        } else {
            focusedField = nil
        }
    }

    private func submitRegistration() {
        hasAttemptedSubmit = true

        guard canSubmit else {
            feedbackKind = .error
            if registrationInfo?.registrationsOpen == false {
                feedbackMessage = MoroL10n.Registration.closedForbidden
            } else if let firstValidationError {
                feedbackMessage = firstValidationError
            } else if !isAgeRequirementSatisfied, let minAge = minAgeRequirement {
                feedbackMessage = MoroL10n.Registration.errorAgeNotMet(minAge)
            } else {
                feedbackMessage = MoroL10n.Registration.errorValidationFailed
            }
            focusFirstInvalidField()
            return
        }

        feedbackMessage = nil
        isSubmitting = true

        guard let dateOfBirth else {
            isSubmitting = false
            return
        }

        let request = AccountRegistrationRequest(
            username: trimmedUsername,
            email: trimmedEmail,
            password: password,
            reason: requiresReason ? trimmedReason : nil,
            dateOfBirth: formattedDateOfBirth(dateOfBirth),
            agreement: agreedToRules,
            locale: preferredLocale
        )

        Task {
            do {
                let result = try await authService.registerAccount(request: request)
                await MainActor.run {
                    isSubmitting = false
                    switch result {
                    case .authenticated:
                        // Open registration returns a token, but the account still needs email
                        // confirmation before it's usable — show the success screen and let the
                        // user log in afterwards rather than auto-entering an unconfirmed account.
                        self.pendingEmail = trimmedEmail
                        self.pendingRequiresApproval = false
                        self.pendingHint = ""
                        feedbackMessage = nil
                        step = .pending
                    case .pending(let pendingEmail, let requiresApproval, let hint):
                        self.pendingEmail = pendingEmail
                        self.pendingRequiresApproval = requiresApproval
                        self.pendingHint = hint ?? ""
                        feedbackMessage = nil
                        step = .pending
                    }
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    feedbackKind = .error
                    feedbackMessage = userFriendlyRegistrationError(error)
                }
            }
        }
    }

    private var preferredLocale: String {
        if let locale = Locale.preferredLanguages.first, !locale.isEmpty {
            return locale
        }
        return "en"
    }

    private var isAgeRequirementSatisfied: Bool {
        guard let dateOfBirth else { return false }
        guard let minAge = minAgeRequirement else { return true }
        guard
            let maxBirthday = Calendar.current.date(byAdding: .year, value: -minAge, to: Date())
        else {
            return true
        }
        return dateOfBirth <= maxBirthday
    }

    private var usernameError: String? {
        if trimmedUsername.isEmpty {
            return hasAttemptedSubmit ? requiredMessage(MoroL10n.Registration.fieldUsername) : nil
        }
        return isUsernameFormatValid ? nil : MoroL10n.Registration.validationUsernameInvalid
    }

    private var emailError: String? {
        if trimmedEmail.isEmpty {
            return hasAttemptedSubmit ? requiredMessage(MoroL10n.Registration.fieldEmail) : nil
        }
        return isEmailFormatValid ? nil : MoroL10n.Registration.validationEmailInvalid
    }

    private var passwordError: String? {
        if password.isEmpty {
            return hasAttemptedSubmit ? requiredMessage(MoroL10n.Registration.fieldPassword) : nil
        }
        return isPasswordLengthValid ? nil : MoroL10n.Registration.hintPasswordShort
    }

    private var passwordConfirmationError: String? {
        if passwordConfirmation.isEmpty {
            return hasAttemptedSubmit ? MoroL10n.Registration.hintConfirmEmpty : nil
        }
        return isPasswordConfirmed ? nil : MoroL10n.Registration.hintConfirmMismatch
    }

    private var birthdayError: String? {
        if dateOfBirth == nil {
            return hasAttemptedSubmit ? requiredMessage(MoroL10n.Registration.fieldBirthday) : nil
        }
        if !isAgeRequirementSatisfied, let minAge = minAgeRequirement {
            return MoroL10n.Registration.hintAgeNotMet(minAge)
        }
        return nil
    }

    private var reasonError: String? {
        guard requiresReason, hasAttemptedSubmit, trimmedReason.isEmpty else { return nil }
        return MoroL10n.Registration.hintReasonEmpty
    }

    private var agreementError: String? {
        guard hasAttemptedSubmit, !agreedToRules else { return nil }
        return MoroL10n.Registration.validationAgreementRequired
    }

    private var firstValidationError: String? {
        usernameError
            ?? emailError
            ?? passwordError
            ?? passwordConfirmationError
            ?? birthdayError
            ?? reasonError
            ?? agreementError
    }

    private func requiredMessage(_ field: String) -> String {
        MoroL10n.Registration.validationRequired(field)
    }

    private func sanitizedUsername(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("@") {
            cleaned.removeFirst()
        }
        if let atIndex = cleaned.firstIndex(of: "@") {
            cleaned = String(cleaned[..<atIndex])
        }
        return cleaned.replacingOccurrences(of: " ", with: "")
    }

    private func formattedDateOfBirth(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private func userFriendlyRegistrationError(_ error: Error) -> String {
        if let apiError = error as? APIError {
            if case .serverError(let serverError) = apiError {
                let raw = (serverError.serverDescription ?? serverError.error).lowercased()
                if raw.contains("username") && raw.contains("taken") {
                    return MoroL10n.Registration.errorUsernameTaken
                }
                if raw.contains("email") && raw.contains("taken") {
                    return MoroL10n.Registration.errorEmailTaken
                }
                if raw.contains("password") {
                    return MoroL10n.Registration.errorPasswordInvalid
                }
                if raw.contains("registration") && raw.contains("closed") {
                    return MoroL10n.Registration.closedForbidden
                }
                if raw.contains("confirm your email") || raw.contains("confirmation") {
                    return MoroL10n.Registration.errorConfirmEmail
                }
            }
            return apiError.localizedDescription
        }
        return MoroL10n.AppError.unknown
    }
}

#Preview {
    NavigationStack {
        RegistrationFlowView(
            authService: AuthService(),
            instanceDomain: RecommendedServers.primary
        ) { _, _, _ in }
    }
    .moroTheme(MoroTheme())
}
