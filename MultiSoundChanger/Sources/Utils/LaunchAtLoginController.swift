//
//  LaunchAtLoginController.swift
//  MultiSoundChanger
//
//  Registers the app itself as a macOS login item so it starts at boot (opt-in, off by default —
//  see PLAN-launch-at-login.md, ADR A-11). Unlike the system-volume-icon hide (A-8), this is *not*
//  a system side-effect that needs teardown: a login item is meant to survive quit/crash/reboot —
//  that persistence *is* the feature. Same category as the icon tint (A-9): a plain opt-in flag with
//  no idempotent-apply / orphan-repair / teardown.
//
//  Source of truth is the live system status (`SMAppService.mainApp.status`), never a UserDefaults
//  cache: a cached bool would only drift from what the user set in System Settings > Login Items.
//
//  `SMAppService` exists only on macOS 13+. On 11/12 the whole feature is unavailable and the menu
//  item is simply not shown — deployment target stays 11.0.
//

import Foundation
import ServiceManagement

// MARK: - Protocols

protocol LaunchAtLoginController: AnyObject {
    /// `true` on macOS 13+, where `SMAppService` exists; `false` below that.
    var isAvailable: Bool { get }
    /// The real system registration status, re-read on every access.
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool)
}

// MARK: - Implementation

final class LaunchAtLoginControllerImpl: LaunchAtLoginController {
    var isAvailable: Bool {
        if #available(macOS 13.0, *) {
            return true
        } else {
            return false
        }
    }

    var isEnabled: Bool {
        guard #available(macOS 13.0, *) else {
            return false
        }
        return SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else {
            Logger.warning(Constants.InnerMessages.launchAtLoginUnavailable)
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.error(Constants.InnerMessages.launchAtLoginError(error: error.localizedDescription))
        }

        logResolvedStatus()
    }

    // MARK: Private

    /// Re-reads the status after a register/unregister attempt and logs the real outcome, so a
    /// silent `.requiresApproval` (user disabled us in System Settings) or a failed `register()` is
    /// visible rather than assumed successful.
    @available(macOS 13.0, *)
    private func logResolvedStatus() {
        switch SMAppService.mainApp.status {
        case .enabled:
            Logger.debug(Constants.InnerMessages.launchAtLoginEnabled)
        case .requiresApproval:
            Logger.warning(Constants.InnerMessages.launchAtLoginRequiresApproval)
        case .notRegistered:
            Logger.debug(Constants.InnerMessages.launchAtLoginDisabled)
        case .notFound:
            Logger.warning(Constants.InnerMessages.launchAtLoginNotFound)
        @unknown default:
            break
        }
    }
}
