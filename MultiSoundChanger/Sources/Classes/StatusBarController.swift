//
//  StatusBarController.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 15.11.2020.
//  Copyright © 2020 Dmitry Medyuho. All rights reserved.
//

import AudioToolbox
import Cocoa

// MARK: - Protocols

protocol StatusBarController: AnyObject {
    func createMenu()
    func changeStatusItemImage(value: Float)
    func updateVolume(value: Float)
    func refreshAfterExternalChange()
}

// MARK: - Extensions

extension StatusBarControllerImpl {
    enum MenuItem {
        case volume
        case slider
        case output
        case outputHint
        case deviceList
        case separator
        case soundPreferences
        case audioSetup
        case hideSystemIcon
        case launchAtLogin
        case language
        case iconTintHeader
        case iconTint
        case quit
    }
}

// MARK: - Implementation

final class StatusBarControllerImpl: NSObject, StatusBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let volumeController: VolumeViewController
    private let audioManager: AudioManager
    private let systemVolumeIconController: SystemVolumeIconController
    private let launchAtLoginController: LaunchAtLoginController

    private let deviceListView = DeviceListView(frame: .zero)
    private let iconTintView = IconTintPickerView()
    private var outputItem: NSMenuItem?
    private var hideSystemIconItem: NSMenuItem?
    private var launchAtLoginItem: NSMenuItem?

    /// The untinted glyph currently matching the volume level; the tint is layered on top of it, so
    /// switching tints re-renders from this base rather than losing the level.
    private var currentBaseImage: NSImage? = Images.volumeImage1

    init(
        audioManager: AudioManager,
        systemVolumeIconController: SystemVolumeIconController,
        launchAtLoginController: LaunchAtLoginController
    ) {
        self.audioManager = audioManager
        self.systemVolumeIconController = systemVolumeIconController
        self.launchAtLoginController = launchAtLoginController
        self.volumeController = Stories.volume.controller(VolumeViewController.self)

        super.init()

        self.volumeController.audioManager = audioManager
        self.volumeController.statusBarController = self
    }

    func createMenu() {
        applyStatusItemImage()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let volumeItem = getMenuItem(by: .volume)
        let sliderItem = getMenuItem(by: .slider)
        let outputItem = getMenuItem(by: .output)
        let outputHintItem = getMenuItem(by: .outputHint)
        let deviceListItem = getMenuItem(by: .deviceList)
        let firstSeparatorItem = getMenuItem(by: .separator)
        let soundPreferencesItem = getMenuItem(by: .soundPreferences)
        let audioSetupItem = getMenuItem(by: .audioSetup)
        let hideSystemIconItem = getMenuItem(by: .hideSystemIcon)
        let secondSeparatorItem = getMenuItem(by: .separator)
        let iconTintHeaderItem = getMenuItem(by: .iconTintHeader)
        let iconTintItem = getMenuItem(by: .iconTint)
        let thirdSeparatorItem = getMenuItem(by: .separator)
        let quitItem = getMenuItem(by: .quit)

        self.outputItem = outputItem
        self.hideSystemIconItem = hideSystemIconItem

        menu.addItem(volumeItem)
        menu.addItem(sliderItem)
        menu.addItem(outputItem)
        menu.addItem(outputHintItem)
        menu.addItem(deviceListItem)
        menu.addItem(firstSeparatorItem)
        menu.addItem(soundPreferencesItem)
        menu.addItem(audioSetupItem)
        menu.addItem(hideSystemIconItem)

        // Login-item control only exists on macOS 13+ (SMAppService); below that the feature is
        // impossible, so the row is omitted rather than shown disabled (ADR A-11).
        if launchAtLoginController.isAvailable {
            let launchAtLoginItem = getMenuItem(by: .launchAtLogin)
            self.launchAtLoginItem = launchAtLoginItem
            menu.addItem(launchAtLoginItem)
        }

        menu.addItem(getMenuItem(by: .language))
        menu.addItem(secondSeparatorItem)
        menu.addItem(iconTintHeaderItem)
        menu.addItem(iconTintItem)
        menu.addItem(thirdSeparatorItem)
        menu.addItem(quitItem)

        statusItem.menu = menu

        refreshDeviceList()
        refreshIconTintPicker()
        // Sync the status-bar icon (and slider) with the selected device's real volume at launch.
        // Without this the icon stays on its initial `volumeImage1` — the "muted/lowest" glyph —
        // until the first volume event, so a login-launched app shows "muted" over live audio.
        refreshVolumeDisplay()
    }

    func changeStatusItemImage(value: Float) {
        currentBaseImage = baseImage(for: value)
        applyStatusItemImage()
    }

    private func baseImage(for value: Float) -> NSImage? {
        if value < 1 {
            return Images.volumeImage1
        } else if value <= 100 / 3 {
            return Images.volumeImage2
        } else if value <= 100 / 3 * 2 {
            return Images.volumeImage3
        } else {
            return Images.volumeImage4
        }
    }

    /// The single place the status-bar image is set — it layers the current tint over the current
    /// base glyph, so the tint survives every volume-level image swap (R6).
    private func applyStatusItemImage() {
        statusItem.button?.image = currentIconTint().statusBarImage(base: currentBaseImage)
    }

    func updateVolume(value: Float) {
        volumeController.updateSliderVolume(volume: value)
        changeStatusItemImage(value: value)
    }

    /// Called after `AudioManager.reconcileWithSystemDefault()` has moved the selection to follow an
    /// external system-default change (A-10). Pulls the menu's checkmarks onto the new `selection`
    /// and the slider/status-bar icon onto the new device's volume, even while the menu is closed.
    func refreshAfterExternalChange() {
        refreshDeviceList()
        refreshVolumeDisplay()
    }

    private func getMenuItem(by type: MenuItem) -> NSMenuItem {
        switch type {
        case .volume:
            let item = NSMenuItem(title: Strings.volume, action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            item.isEnabled = false
            return item

        case .slider:
            let item = NSMenuItem(title: String(), action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            // Stretch the slider view to the full menu width (governed by the widest item) so it
            // never leaves a gap on the right — same mechanism as the device list.
            volumeController.view.autoresizingMask = [.width]
            item.view = volumeController.view
            return item

        case .output:
            let item = NSMenuItem(title: Strings.output, action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            item.isEnabled = false
            return item

        case .outputHint:
            // A persistent, always-visible hint line explaining click vs shift-click. Small
            // secondary-coloured text so it reads as a caption, not a command.
            let item = NSMenuItem(title: String(), action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            item.isEnabled = false
            item.attributedTitle = NSAttributedString(
                string: Strings.outputHint,
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]
            )
            return item

        case .deviceList:
            let item = NSMenuItem(title: String(), action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            item.view = deviceListView
            return item

        case .separator:
            return NSMenuItem.separator()

        case .soundPreferences:
            let item = NSMenuItem(
                title: Strings.soundPreferences,
                action: #selector(menuSoundPreferencesAction),
                keyEquivalent: Constants.Keys.empty.rawValue
            )
            item.target = self
            return item

        case .audioSetup:
            let item = NSMenuItem(title: Strings.audioDevices, action: #selector(menuAudioSetupAction), keyEquivalent: Constants.Keys.empty.rawValue)
            item.target = self
            return item

        case .hideSystemIcon:
            let item = NSMenuItem(
                title: Strings.hideSystemVolumeIcon,
                action: #selector(menuToggleHideSystemIconAction),
                keyEquivalent: Constants.Keys.empty.rawValue
            )
            item.target = self
            item.state = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.hideSystemVolumeIcon) ? .on : .off
            return item

        case .launchAtLogin:
            let item = NSMenuItem(
                title: Strings.launchAtLogin,
                action: #selector(menuToggleLaunchAtLoginAction),
                keyEquivalent: Constants.Keys.empty.rawValue
            )
            item.target = self
            // Real system status, not a UserDefaults cache — see ADR A-11.
            item.state = launchAtLoginController.isEnabled ? .on : .off
            return item

        case .language:
            let item = NSMenuItem(title: Strings.language, action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            item.submenu = buildLanguageSubmenu()
            return item

        case .iconTintHeader:
            let item = NSMenuItem(title: Strings.iconTintHeader, action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            item.isEnabled = false
            return item

        case .iconTint:
            let item = NSMenuItem(title: String(), action: nil, keyEquivalent: Constants.Keys.empty.rawValue)
            item.view = iconTintView
            return item

        case .quit:
            let item = NSMenuItem(title: Strings.quit, action: #selector(menuQuitAction), keyEquivalent: Constants.Keys.q.rawValue)
            item.target = self
            return item
        }
    }

    // MARK: Multi-output device list (A4)

    private func refreshDeviceList() {
        let rows = audioManager.currentDeviceRows()

        deviceListView.configure(rows: rows) { [weak self] uid, isShiftClick in
            self?.handleDeviceRowSelected(uid: uid, isShiftClick: isShiftClick)
        }

        updateOutputTitle(selectedCount: rows.filter { $0.isSelected }.count)
    }

    private func handleDeviceRowSelected(uid: String, isShiftClick: Bool) {
        if isShiftClick {
            audioManager.toggleSelection(uid: uid)
            refreshDeviceList()
        } else {
            audioManager.selectSingle(uid: uid)
            refreshDeviceList()
            statusItem.menu?.cancelTracking()
        }
        refreshVolumeDisplay()
    }

    private func updateOutputTitle(selectedCount: Int) {
        guard let outputItem = outputItem else {
            return
        }

        // Compact header — the wording never widens the menu; the always-on hint line carries the
        // "click vs ⇧-click" explanation, and the "(N)" count carries the single-vs-multi cue.
        if selectedCount >= 2 {
            outputItem.title = String(format: Strings.outputMultiple, selectedCount)
        } else {
            outputItem.title = Strings.output
        }
    }

    private func refreshVolumeDisplay() {
        guard let volume = audioManager.getSelectedDeviceVolume() else {
            return
        }
        let correctedVolume = audioManager.isMuted ? 0 : volume * 100
        volumeController.updateSliderVolume(volume: correctedVolume)
        changeStatusItemImage(value: correctedVolume)
    }

    // MARK: Icon tint (C)

    private func currentIconTint() -> IconTint {
        return IconTint(rawValue: UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.menuBarIconTint) ?? String()) ?? .default
    }

    /// Rebuilds the swatch row, previewing every tint on the icon that currently matches the volume
    /// level, with the active tint marked selected.
    private func refreshIconTintPicker() {
        iconTintView.configure(selected: currentIconTint(), baseImage: currentBaseImage) { [weak self] tint in
            self?.applyIconTint(tint)
            self?.statusItem.menu?.cancelTracking()
        }
    }

    private func applyIconTint(_ tint: IconTint) {
        UserDefaults.standard.set(tint.rawValue, forKey: Constants.UserDefaultsKeys.menuBarIconTint)
        applyStatusItemImage()
        refreshIconTintPicker()
    }

    // MARK: Language (A-13)

    /// `System` (follow macOS) first, then a separator, then the pinned languages sorted
    /// alphabetically by their own name (endonym) — the name the user actually reads — with Latin,
    /// Cyrillic and CJK falling into locale order. A checkmark marks the active language.
    private func buildLanguageSubmenu() -> NSMenu {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let current = LanguageManager.current

        submenu.addItem(languageMenuItem(for: .system, current: current))
        submenu.addItem(.separator())
        let sorted = AppLanguage.allCases
            .filter { $0 != .system }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        for language in sorted {
            submenu.addItem(languageMenuItem(for: language, current: current))
        }
        return submenu
    }

    private func languageMenuItem(for language: AppLanguage, current: AppLanguage) -> NSMenuItem {
        let item = NSMenuItem(
            title: language.displayName,
            action: #selector(menuSelectLanguage(_:)),
            keyEquivalent: Constants.Keys.empty.rawValue
        )
        item.target = self
        item.representedObject = language
        item.state = language == current ? .on : .off
        return item
    }

    @objc
    private func menuSelectLanguage(_ sender: NSMenuItem) {
        guard let language = sender.representedObject as? AppLanguage, language != LanguageManager.current else {
            return
        }
        LanguageManager.setCurrent(language)
        rebuildMenuAfterLanguageChange()
    }

    /// Language strings are baked into menu items at build time, so switching language rebuilds the
    /// whole menu. The custom view items (slider, device list, tint swatches) are reused instances —
    /// an `NSView` lives in exactly one menu item at a time, so they must be detached from the old
    /// menu *before* the new menu claims them, or they render blank (the device list and tint
    /// swatches vanish while the translated text stays). Null out the old items' views and drop the
    /// old menu first, then rebuild.
    private func rebuildMenuAfterLanguageChange() {
        statusItem.menu?.cancelTracking()
        statusItem.menu?.items.forEach { $0.view = nil }
        statusItem.menu = nil
        createMenu()
    }

    // MARK: Actions

    @objc
    private func menuSoundPreferencesAction() {
        Runner.shell("open -b \(Constants.AppBundleIdentifier.systemPreferences) \(Constants.SystemPreferencesPane.sound)")
    }

    @objc
    private func menuAudioSetupAction() {
        Runner.launchApplication(bundleIdentifier: Constants.AppBundleIdentifier.audioDevices)
    }

    @objc
    private func menuToggleHideSystemIconAction(sender: NSMenuItem) {
        let newValue = sender.state != .on
        sender.state = newValue ? .on : .off
        UserDefaults.standard.set(newValue, forKey: Constants.UserDefaultsKeys.hideSystemVolumeIcon)

        if newValue {
            systemVolumeIconController.hide()
        } else {
            systemVolumeIconController.restore()
        }
    }

    @objc
    private func menuToggleLaunchAtLoginAction(sender: NSMenuItem) {
        let newValue = sender.state != .on
        launchAtLoginController.setEnabled(newValue)
        // Re-read the real status instead of trusting the toggle: on `.requiresApproval` or a failed
        // `register()` the checkmark must not lie about what the system actually did (ADR A-11).
        sender.state = launchAtLoginController.isEnabled ? .on : .off
    }

    @objc
    private func menuQuitAction() {
        NSApplication.shared.terminate(self)
    }
}

// MARK: - NSMenuDelegate

extension StatusBarControllerImpl: NSMenuDelegate {
    /// Rebuilds the device rows from the live HAL device list on every menu opening — catches
    /// devices plugged in or unplugged since the last time the menu was shown, without a listener.
    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshDeviceList()
        refreshIconTintPicker()
        // Catch a volume change made outside the app between menu openings, in case the HAL
        // listener missed it — keeps the status-bar icon honest even without a volume event.
        refreshVolumeDisplay()
        // Reflect a login-item change made in System Settings while our menu was closed.
        launchAtLoginItem?.state = launchAtLoginController.isEnabled ? .on : .off
    }
}
