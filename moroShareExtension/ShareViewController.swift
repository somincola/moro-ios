import UIKit

func L(_ key: String) -> String { NSLocalizedString(key, bundle: .main, comment: "") }
func L(_ key: String, _ args: CVarArg...) -> String { String(format: L(key), arguments: args) }

/// Receive and stage once, then hand off. Publishing and draft decisions belong to Moro.
final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .large)
    private let retryButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    private let importer = MoroShareExtensionImportService()
    private var importTask: Task<Void, Never>?
    private var stagedItemID: String?
    private var hasStarted = false
    private var isOpening = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        titleLabel.text = L("share.title")
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textAlignment = .center
        messageLabel.font = .preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .secondaryLabel
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        activityIndicator.hidesWhenStopped = true
        retryButton.configuration = .filled()
        retryButton.configuration?.cornerStyle = .large
        retryButton.setTitle(L("share.action.retry"), for: .normal)
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.accessibilityIdentifier = "share.retry"
        cancelButton.configuration = .plain()
        cancelButton.setTitle(L("share.action.cancel"), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [titleLabel, activityIndicator, messageLabel, retryButton, cancelButton])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
        ])
        showProgress(L("share.state.loading"))
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasStarted else { return }
        hasStarted = true
        startImport()
    }

    private func startImport() {
        guard importTask == nil else { return }
        showProgress(L("share.state.loading"))
        let items = extensionContext?.inputItems ?? []
        let accountID = MoroShareExtensionSessionBootstrapReader().loadActiveAccountID()
        importTask = Task { @MainActor [weak self, importer] in
            do {
                let id = try await importer.prepare(inputItems: items, accountID: accountID)
                guard let self else { await importer.cancel(itemID: id); return }
                self.stagedItemID = id
                guard !Task.isCancelled else { await importer.cancel(itemID: id); return }
                self.importTask = nil
                self.openMoro()
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.importTask = nil
                let message = (error as? MoroShareExtensionInputError)?.message ?? L("share.error.importFailed")
                self.showError(message)
            }
        }
    }

    @objc private func retryTapped() {
        if stagedItemID != nil { openMoro() } else { startImport() }
    }

    private func openMoro() {
        guard !isOpening, let id = stagedItemID,
              let url = URL(string: "moro://share/compose?item=\(id)") else { return }
        isOpening = true
        showProgress(L("share.state.opening"))
        // Share extensions have no guaranteed app-launch contract. Use a public
        // responder URL opener where available, with an explicit recoverable fallback.
        // Never use UIApplication.shared, private selectors or the Objective-C runtime.
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.open(url, options: [:]) { [weak self] success in
                    Task { @MainActor [weak self] in self?.finishOpening(success: success) }
                }
                return
            }
            responder = current.next
        }
        extensionContext?.open(url) { [weak self] success in
            Task { @MainActor [weak self] in self?.finishOpening(success: success) }
        }
    }

    private func finishOpening(success: Bool) {
        isOpening = false
        if success { extensionContext?.completeRequest(returningItems: [], completionHandler: nil) }
        else { showError(L("share.error.openFailed")) }
    }

    @objc private func cancelTapped() {
        importTask?.cancel()
        cancelButton.isEnabled = false
        Task { @MainActor [weak self, importer] in
            await importer.cancel(itemID: self?.stagedItemID)
            self?.extensionContext?.cancelRequest(withError: NSError(
                domain: "com.somincola.moro.ShareExtension", code: NSUserCancelledError,
                userInfo: [NSLocalizedDescriptionKey: L("share.action.cancel")]))
        }
    }

    private func showProgress(_ message: String) {
        activityIndicator.startAnimating()
        messageLabel.text = message
        retryButton.isHidden = true
        cancelButton.isEnabled = !isOpening
    }

    private func showError(_ message: String) {
        activityIndicator.stopAnimating()
        messageLabel.text = message
        retryButton.isHidden = false
        retryButton.setTitle(L(stagedItemID == nil ? "share.action.retry" : "share.action.open"), for: .normal)
        cancelButton.isEnabled = true
    }

    nonisolated deinit { importTask?.cancel() }
}
