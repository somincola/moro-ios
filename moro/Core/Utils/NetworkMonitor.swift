//
//  NetworkMonitor.swift
//  moro
//
//  Network monitoring utility to detect Wi-Fi and cellular connection status.
//

import Foundation
import Network
import Combine

/// Network connection type
enum NetworkType {
    case wifi
    case cellular
    case none
    case unknown
}

/// Network monitoring service
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    @Published var isConnected: Bool = false
    @Published var networkType: NetworkType = .unknown
    /// False until the system reports the first path, while `isConnected` is still its
    /// default; only then can "not connected" be trusted.
    @Published private(set) var hasPathReport = false

    /// Known to be offline. Automatic refreshes pause and catch up once back online; before
    /// the first path report this is false, so a cold start never skips its first load.
    var isOffline: Bool { hasPathReport && !isConnected }
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    private init() {
        startMonitoring()
    }
    
    /// Start monitoring network status
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                let connected = path.status == .satisfied
                let type: NetworkType
                if path.usesInterfaceType(.wifi) {
                    type = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    type = .cellular
                } else if connected {
                    type = .unknown // Connected but type unknown
                } else {
                    type = .none
                }
                // NWPathMonitor reports every path update (interface churn, cost changes);
                // publish only real changes so observers don't re-render for nothing.
                if self.isConnected != connected { self.isConnected = connected }
                if self.networkType != type { self.networkType = type }
                if !self.hasPathReport { self.hasPathReport = true }
            }
        }
        
        monitor.start(queue: queue)
    }
    
    /// Check if video autoplay should be allowed based on current network and settings
    func shouldAutoplayVideo(autoplayMode: AppSettings.VideoAutoplayMode) -> Bool {
        guard isConnected else { return false }
        
        switch autoplayMode {
        case .never:
            return false
        case .wifi:
            return networkType == .wifi
        case .always:
            return true
        }
    }
}

