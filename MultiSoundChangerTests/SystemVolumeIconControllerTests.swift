//
//  SystemVolumeIconControllerTests.swift
//  MultiSoundChangerTests
//
//  The A-8 state machine over a scripted fake shell: save-before-write, verify-by-reading-back,
//  an external change always winning over our bookkeeping, and Control Center only being killed
//  (= visibly flashed) on a real change.
//

import Foundation
import Testing
@testable import MultiSoundChanger2

/// Minimal in-memory Control Center: answers `defaults read`, applies `defaults write`, counts
/// `killall`. `writesStick = false` simulates the undocumented key rejecting our write.
private final class FakeControlCenter {
    var soundValue: Int?
    var writesStick = true
    private(set) var killallCount = 0

    func shell(_ command: String) -> String? {
        if command.contains("killall") {
            killallCount += 1
            return ""
        }
        if command.contains(" write "), let value = Int(command.components(separatedBy: " ").last ?? "") {
            if writesStick {
                soundValue = value
            }
            return ""
        }
        if command.contains(" read ") {
            guard let soundValue = soundValue else {
                return nil
            }
            return "\(soundValue)\n"
        }
        return nil
    }
}

@Suite struct SystemVolumeIconControllerTests {

    private func makeController(
        soundValue: Int?,
        savedValue: Int? = nil,
        hideFlag: Bool = false
    ) -> (SystemVolumeIconControllerImpl, FakeControlCenter, UserDefaults, String) {
        let suiteName = "io.github.emaslenkov.multisoundchanger2.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        if let savedValue = savedValue {
            defaults.set(savedValue, forKey: Constants.UserDefaultsKeys.savedSystemVolumeIconValue)
        }
        defaults.set(hideFlag, forKey: Constants.UserDefaultsKeys.hideSystemVolumeIcon)

        let center = FakeControlCenter()
        center.soundValue = soundValue
        let controller = SystemVolumeIconControllerImpl(defaults: defaults, shell: center.shell)
        return (controller, center, defaults, suiteName)
    }

    private func savedValue(in defaults: UserDefaults) -> Int? {
        return defaults.object(forKey: Constants.UserDefaultsKeys.savedSystemVolumeIconValue) as? Int
    }

    // MARK: hide

    @Test func hideSavesCurrentValueBeforeWriting() {
        let (controller, center, defaults, suite) = makeController(soundValue: 16)
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.hide()

        #expect(savedValue(in: defaults) == 16) // the user's actual value, not a hardcoded guess
        #expect(center.soundValue == Constants.ControlCenter.hiddenValue)
        #expect(center.killallCount == 1)
    }

    @Test func hideIsNoOpWhenAlreadyHidden() {
        // Left behind by our own previous run: must not overwrite the saved value with our marker.
        let (controller, center, defaults, suite) = makeController(soundValue: Constants.ControlCenter.hiddenValue, savedValue: 16)
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.hide()

        #expect(savedValue(in: defaults) == 16) // untouched
        #expect(center.killallCount == 0) // no pointless Control Center flash
    }

    @Test func hideAbortsWhenValueIsUnreadable() {
        let (controller, center, defaults, suite) = makeController(soundValue: nil)
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.hide()

        #expect(savedValue(in: defaults) == nil)
        #expect(center.killallCount == 0)
    }

    @Test func hideDoesNotKillControlCenterWhenWriteDidNotStick() {
        // The key is undocumented: a write is only trusted after reading the same value back.
        let (controller, center, defaults, suite) = makeController(soundValue: 16)
        defer { defaults.removePersistentDomain(forName: suite) }
        center.writesStick = false

        controller.hide()

        #expect(center.killallCount == 0)
    }

    // MARK: restore

    @Test func restoreIsNoOpWithoutSavedValue() {
        let (controller, center, defaults, suite) = makeController(soundValue: Constants.ControlCenter.hiddenValue)
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.restore()

        #expect(center.soundValue == Constants.ControlCenter.hiddenValue)
        #expect(center.killallCount == 0)
    }

    @Test func restoreYieldsToExternalChange() {
        // The user (or another app) moved the value off our marker — their change wins; we only
        // drop our bookkeeping.
        let (controller, center, defaults, suite) = makeController(soundValue: 8, savedValue: 16)
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.restore()

        #expect(center.soundValue == 8) // not clobbered
        #expect(savedValue(in: defaults) == nil) // bookkeeping dropped
        #expect(center.killallCount == 0)
    }

    @Test func restorePutsTheSavedValueBack() {
        let (controller, center, defaults, suite) = makeController(soundValue: Constants.ControlCenter.hiddenValue, savedValue: 16)
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.restore()

        #expect(center.soundValue == 16)
        #expect(savedValue(in: defaults) == nil)
        #expect(center.killallCount == 1)
    }

    // MARK: repairIfNeeded

    @Test func repairRestoresAfterACrashWhileHidden() {
        // Saved value present but the hide flag is off: a previous session died (SIGKILL) with the
        // icon hidden — put it back.
        let (controller, center, defaults, suite) = makeController(
            soundValue: Constants.ControlCenter.hiddenValue,
            savedValue: 16,
            hideFlag: false
        )
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.repairIfNeeded()

        #expect(center.soundValue == 16)
        #expect(savedValue(in: defaults) == nil)
    }

    @Test func repairIsNoOpWhileHideIsIntentional() {
        let (controller, center, defaults, suite) = makeController(
            soundValue: Constants.ControlCenter.hiddenValue,
            savedValue: 16,
            hideFlag: true
        )
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.repairIfNeeded()

        #expect(center.soundValue == Constants.ControlCenter.hiddenValue)
        #expect(savedValue(in: defaults) == 16)
    }

    @Test func repairIsNoOpWithoutSavedValue() {
        let (controller, center, defaults, suite) = makeController(soundValue: 16)
        defer { defaults.removePersistentDomain(forName: suite) }

        controller.repairIfNeeded()

        #expect(center.soundValue == 16)
        #expect(center.killallCount == 0)
    }
}
