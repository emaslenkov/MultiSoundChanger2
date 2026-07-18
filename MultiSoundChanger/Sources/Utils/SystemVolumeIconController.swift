//
//  SystemVolumeIconController.swift
//  MultiSoundChanger
//
//  Hides the system's own volume icon in Control Center so it stops being confused with this app's
//  menu-bar icon (opt-in, off by default — see PLAN-hide-system-icon.md, ADR A-8). Same nature as
//  the hidutil remap: this changes the *system*, survives a crash, and `SIGKILL` can't be caught —
//  see `.claude/rules/system-side-effects.md`.
//
//  The `com.apple.controlcenter` `Sound` key is undocumented, so every write is verified by reading
//  it back; a mismatch is logged and left alone rather than assumed to have taken effect.
//

import Foundation

// MARK: - Protocols

protocol SystemVolumeIconController: AnyObject {
    func currentValue() -> Int?
    func hide()
    func restore()
    func repairIfNeeded()
}

// MARK: - Implementation

final class SystemVolumeIconControllerImpl: SystemVolumeIconController {
    private let defaults: UserDefaults
    private let shell: (String) -> String?

    /// Both dependencies default to the real thing — production call sites stay unchanged. The
    /// seams exist because this state machine has no substance outside its side effects: without
    /// them the A-8 invariants (save-before-write, verify-by-reading-back, external change wins)
    /// would be untestable.
    init(defaults: UserDefaults = .standard, shell: @escaping (String) -> String? = Runner.shell) {
        self.defaults = defaults
        self.shell = shell
    }

    func currentValue() -> Int? {
        guard let output = shell(
            "\(Constants.Paths.defaults) -currentHost read \(Constants.ControlCenter.domain) \(Constants.ControlCenter.soundKey)"
        ) else {
            return nil
        }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Saves whatever value is live *before* touching anything, so `restore()` can put back the
    /// user's actual setting rather than a hardcoded guess (ADR A-8, decision Р2). Idempotent: a
    /// value already equal to `hiddenValue` — e.g. left behind by our own previous run — is a no-op,
    /// which also means it never overwrites a saved value with our own hidden marker.
    func hide() {
        guard let current = currentValue() else {
            Logger.warning(Constants.InnerMessages.systemVolumeIconWriteError)
            return
        }

        guard current != Constants.ControlCenter.hiddenValue else {
            return
        }

        defaults.set(current, forKey: Constants.UserDefaultsKeys.savedSystemVolumeIconValue)
        writeControlCenterValue(Constants.ControlCenter.hiddenValue)

        guard currentValue() == Constants.ControlCenter.hiddenValue else {
            Logger.warning(Constants.InnerMessages.systemVolumeIconWriteError)
            return
        }

        killControlCenter()
        Logger.debug(Constants.InnerMessages.systemVolumeIconHidden)
    }

    /// If the value has been changed away from our hidden marker by something other than us (the
    /// user, another app), that change wins — we drop our bookkeeping instead of clobbering it.
    func restore() {
        guard let saved = defaults.object(forKey: Constants.UserDefaultsKeys.savedSystemVolumeIconValue) as? Int else {
            return
        }

        guard currentValue() == Constants.ControlCenter.hiddenValue else {
            Logger.debug(Constants.InnerMessages.systemVolumeIconExternallyChanged)
            defaults.removeObject(forKey: Constants.UserDefaultsKeys.savedSystemVolumeIconValue)
            return
        }

        writeControlCenterValue(saved)
        defaults.removeObject(forKey: Constants.UserDefaultsKeys.savedSystemVolumeIconValue)

        guard currentValue() == saved else {
            Logger.warning(Constants.InnerMessages.systemVolumeIconWriteError)
            return
        }

        killControlCenter()
        Logger.debug(Constants.InnerMessages.systemVolumeIconRestored)
    }

    /// Crash recovery for the "hide" flag being off at launch but a saved value still present —
    /// meaning a previous session died (SIGKILL) while the icon was hidden. Mirrors the orphan
    /// handling of `MediaKeyRemapper`/`AggregateDeviceManager`.
    func repairIfNeeded() {
        guard defaults.object(forKey: Constants.UserDefaultsKeys.savedSystemVolumeIconValue) != nil,
            !defaults.bool(forKey: Constants.UserDefaultsKeys.hideSystemVolumeIcon) else {
            return
        }
        restore()
    }

    // MARK: Private

    private func writeControlCenterValue(_ value: Int) {
        _ = shell(
            "\(Constants.Paths.defaults) -currentHost write \(Constants.ControlCenter.domain) \(Constants.ControlCenter.soundKey) -int \(value)"
        )
    }

    private func killControlCenter() {
        _ = shell("\(Constants.Paths.killall) \(Constants.ControlCenter.processName)")
    }
}
