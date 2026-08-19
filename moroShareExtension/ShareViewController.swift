//
//  ShareViewController.swift
//  moroShareExtension
//
//  Minimal Share Extension that stages URL/text/image content for Moro Compose import.
//

import UIKit

/// Lookup helper for Localizable.xcstrings strings shipped with the extension.
/// Bundle.main inside an app extension is the extension's own bundle.
private func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

private func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L(key), arguments: args)
}

final class ShareViewController: UIViewController {
    private enum ViewState {
        case loading(String)
        case ready(String)
        case importing(String)
        case error(String)
    }

    private let sessionReader = MoroShareExtensionSessionBootstrapReader()
    private let stagingStore = MoroShareExtensionDraftStagingStore()

    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let importButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var loadedContent: MoroShareExtensionLoadedContent?
    private var activeAccountID: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()

        Task { @MainActor [weak self] in
            await self?.loadSharedContent()
        }
    }

    private func configureView() {
        view.backgroundColor = .systemBackground

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.text = L("share.title")
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center

        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.font = .systemFont(ofSize: 15)
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0

        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        activityIndicator.hidesWhenStopped = true

        importButton.translatesAutoresizingMaskIntoConstraints = false
        importButton.configuration = .filled()
        importButton.configuration?.cornerStyle = .large
        importButton.setTitle(L("share.action.import"), for: .normal)
        importButton.addTarget(self, action: #selector(importButtonTapped), for: .touchUpInside)

        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.configuration = .plain()
        cancelButton.setTitle(L("share.action.cancel"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelButtonTapped), for: .touchUpInside)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            activityIndicator,
            messageLabel,
            importButton,
            cancelButton,
        ])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 18

        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    @MainActor
    private func loadSharedContent() async {
        apply(state: .loading(L("share.state.loading")))

        guard let activeAccountID = sessionReader.loadActiveAccountID() else {
            apply(state: .error(L("share.error.notLoggedIn")))
            return
        }

        let content = await MoroShareExtensionInputLoader.load(
            from: extensionContext?.inputItems ?? []
        )
        guard content.hasSubstantivePayload else {
            apply(state: .error(L("share.error.noContent")))
            return
        }

        self.activeAccountID = activeAccountID
        self.loadedContent = content
        apply(state: .ready(L("share.state.ready", content.summaryText)))
    }

    @objc
    private func importButtonTapped() {
        Task { @MainActor [weak self] in
            await self?.stageSharedDraft()
        }
    }

    @objc
    private func cancelButtonTapped() {
        extensionContext?.cancelRequest(
            withError: NSError(
                domain: "com.somincola.moro.ShareExtension",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "User cancelled share import"]
            )
        )
    }

    @MainActor
    private func stageSharedDraft() async {
        guard let activeAccountID, let loadedContent else {
            apply(state: .error(L("share.error.notReady")))
            return
        }

        apply(state: .importing(L("share.state.importing")))

        do {
            try stagingStore.stage(
                accountID: activeAccountID,
                sourceApplication: "ShareExtension",
                content: loadedContent
            )
            apply(state: .importing(L("share.state.importComplete")))
            try? await Task.sleep(nanoseconds: 450_000_000)
            extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            apply(state: .error(L("share.error.importFailed")))
        }
    }

    private func apply(state: ViewState) {
        switch state {
        case .loading(let message):
            activityIndicator.startAnimating()
            messageLabel.text = message
            importButton.isHidden = true
            importButton.isEnabled = false
            cancelButton.isEnabled = true
        case .ready(let message):
            activityIndicator.stopAnimating()
            messageLabel.text = message
            importButton.isHidden = false
            importButton.isEnabled = true
            cancelButton.isEnabled = true
        case .importing(let message):
            activityIndicator.startAnimating()
            messageLabel.text = message
            importButton.isHidden = false
            importButton.isEnabled = false
            cancelButton.isEnabled = false
        case .error(let message):
            activityIndicator.stopAnimating()
            messageLabel.text = message
            importButton.isHidden = true
            importButton.isEnabled = false
            cancelButton.isEnabled = true
        }
    }
}
