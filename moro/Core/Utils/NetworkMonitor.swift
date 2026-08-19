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
                
                self.isConnected = path.status == .satisfied
                
                if path.usesInterfaceType(.wifi) {
                    self.networkType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self.networkType = .cellular
                } else if path.status == .satisfied {
                    self.networkType = .unknown // Connected but type unknown
                } else {
                    self.networkType = .none
                }
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

