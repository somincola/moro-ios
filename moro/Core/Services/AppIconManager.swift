//
//  AppIconManager.swift
//  moro
//
//  Handles app icon switching via UIApplication alternate icons API.
//

import UIKit

enum AppIconManagerError: LocalizedError {
    case alternateIconsUnsupported
    case resourceBusy

    var errorDescription: String? {
        switch self {
        case .alternateIconsUnsupported:
            return MoroL10n.AppIcon.notSupported
        case .resourceBusy:
            return MoroL10n.AppIcon.resourceUnavailable
        }
    }
}

@MainActor
final class AppIconManager {
    static let shared = AppIconManager()

    private var lastSwitchAt: Date = .distantPast

    private init() {}

    var supportsAlternateIcons: Bool {
        UIApplication.shared.supportsAlternateIcons
    }

    var currentChoice: AppSettings.AppIconChoice {
        switch UIApplication.shared.alternateIconName {
        case "AppIconClassic":
            return .classic
        case "AppIconLineElephant":
            return .lineElephant
        case "AppIconRainbow":
            return .rainbow
        case "AppIconLiquidGlass":
            return .liquidGlass
        case "AppIconPaintChaos":
            return .paintChaos
        case "AppIconRisoGlitch":
            return .risoGlitch
        case "AppIconTornCollage":
            return .tornCollage
        default:
            return .default
        }
    }

    func apply(_ icon: AppSettings.AppIconChoice) async throws {
        guard supportsAlternateIcons else {
            if icon == .default { return }
            throw AppIconManagerError.alternateIconsUnsupported
        }

        let targetName = icon.alternateIconName
        guard UIApplication.shared.alternateIconName != targetName else { return }

        await enforceSwitchCooldown()

        // The completion handler is the source of truth: no error means
        // SpringBoard accepted the change. The `alternateIconName` getter can
        // lag behind for a moment, so it must not be polled to judge success.
        // EAGAIN means SpringBoard is still busy with the previous change —
        // retry briefly, then surface a "try again later".
        let maxAttempts = 3
        for attempt in 1...maxAttempts {
            do {
                try await requestIconChange(to: targetName)
                lastSwitchAt = Date()
                return
            } catch {
                guard attempt < maxAttempts, isTransientResourceError(error) else {
                    if isTransientResourceError(error) {
                        throw AppIconManagerError.resourceBusy
                    }
                    throw error
                }
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private func enforceSwitchCooldown() async {
        let minimumInterval: TimeInterval = 1.5
        let elapsed = Date().timeIntervalSince(lastSwitchAt)
        guard elapsed < minimumInterval else { return }

        let wait = minimumInterval - elapsed
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        }
    }

    private func requestIconChange(to targetName: String?) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            UIApplication.shared.setAlternateIconName(targetName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private func isTransientResourceError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain {
            // EAGAIN: SpringBoard busy with a previous change.
            // EIO: icon staging not settled yet (first switch right after
            // an install/update) — clears on retry.
            switch POSIXErrorCode(rawValue: Int32(nsError.code)) {
            case .EAGAIN, .EIO:
                return true
            default:
                break
            }
        }

        let message = nsError.localizedDescription.lowercased()
        if message.contains("resource temporarily unavailable")
            || message.contains("资源暂时不可用")
            || message.contains("input/output error")
        {
            return true
        }

        return false
    }
}
