import Foundation

struct NavigationTabLayout: Equatable {
    static let minimumCount = 2
    static let maximumCount = 5
    static let requiredTabs: [MainTab] = [.home]
    static let defaultTabs: [MainTab] = [.home, .explore, .inbox, .me]

    private(set) var tabs: [MainTab]

    init(tabs: [MainTab] = Self.defaultTabs) {
        let optionalLimit = Self.maximumCount - Self.requiredTabs.count
        var optionalCount = 0
        var result: [MainTab] = []
        let savedTabs = tabs.isEmpty ? Self.defaultTabs : tabs
        for tab in savedTabs + Self.requiredTabs {
            guard !result.contains(tab) else { continue }
            if !tab.isRequired {
                guard optionalCount < optionalLimit else { continue }
                optionalCount += 1
            }
            result.append(tab)
        }
        for tab in Self.defaultTabs where result.count < Self.minimumCount && !result.contains(tab) {
            result.append(tab)
        }
        self.tabs = result
    }

    func canToggle(_ tab: MainTab) -> Bool {
        guard !tab.isRequired else { return false }
        return tabs.contains(tab) ? tabs.count > Self.minimumCount : tabs.count < Self.maximumCount
    }

    mutating func toggle(_ tab: MainTab) {
        guard canToggle(tab) else { return }
        if let index = tabs.firstIndex(of: tab) {
            tabs.remove(at: index)
        } else {
            tabs.append(tab)
        }
    }

    func moving(_ tab: MainTab, to index: Int) -> NavigationTabLayout {
        guard let previousIndex = tabs.firstIndex(of: tab),
              tabs.indices.contains(index), index != previousIndex else { return self }
        var layout = self
        layout.tabs.remove(at: previousIndex)
        layout.tabs.insert(tab, at: index)
        return layout
    }
}

struct NavigationTabPreferences {
    private let key: String
    private let defaults: UserDefaults

    init?(session: StoredAccountSession?, defaults: UserDefaults = .standard) {
        // A new sign-in can get a new session ID. The instance and its local account ID
        // still identify the same Mastodon account.
        guard let session, let url = session.instanceURL,
              let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased()
        else { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        let port = url.port.flatMap { $0 == defaultPort ? nil : ":\($0)" } ?? ""
        key = "navigationTabLayout.\(scheme)://\(host)\(port)/\(session.account.id)"
        self.defaults = defaults
    }

    func load() -> NavigationTabLayout {
        guard let rawTabs = defaults.stringArray(forKey: key) else { return NavigationTabLayout() }
        return NavigationTabLayout(tabs: rawTabs.compactMap(MainTab.init(rawValue:)))
    }

    func save(_ layout: NavigationTabLayout) {
        defaults.set(layout.tabs.map(\.rawValue), forKey: key)
    }
}
