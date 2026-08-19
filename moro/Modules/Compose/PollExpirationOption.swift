//
//  PollExpirationOption.swift
//  moro
//
//  Poll expiration time options.
//

import Foundation

enum PollExpirationOption: CaseIterable {
    case fiveMinutes
    case thirtyMinutes
    case oneHour
    case sixHours
    case twelveHours
    case oneDay
    case threeDays
    case fiveDays
    case sevenDays
    
    var seconds: Int {
        switch self {
        case .fiveMinutes:
            return 300
        case .thirtyMinutes:
            return 1800
        case .oneHour:
            return 3600
        case .sixHours:
            return 21600
        case .twelveHours:
            return 43200
        case .oneDay:
            return 86400
        case .threeDays:
            return 259200
        case .fiveDays:
            return 432000
        case .sevenDays:
            return 604800
        }
    }
    
    var displayName: String {
        switch self {
        case .fiveMinutes:
            return MoroL10n.PollExpiration.fiveMinutes
        case .thirtyMinutes:
            return MoroL10n.PollExpiration.thirtyMinutes
        case .oneHour:
            return MoroL10n.PollExpiration.oneHour
        case .sixHours:
            return MoroL10n.PollExpiration.sixHours
        case .twelveHours:
            return MoroL10n.PollExpiration.twelveHours
        case .oneDay:
            return MoroL10n.PollExpiration.oneDay
        case .threeDays:
            return MoroL10n.PollExpiration.threeDays
        case .fiveDays:
            return MoroL10n.PollExpiration.fiveDays
        case .sevenDays:
            return MoroL10n.PollExpiration.sevenDays
        }
    }
    
    init?(seconds: Int) {
        if let option = PollExpirationOption.allCases.first(where: { $0.seconds == seconds }) {
            self = option
        } else {
            return nil
        }
    }
}

