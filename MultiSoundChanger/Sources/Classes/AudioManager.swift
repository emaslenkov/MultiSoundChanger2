//
//  AudioManager.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 15.11.2020.
//  Copyright © 2020 Dmitry Medyuho. All rights reserved.
//

import AudioToolbox
import Foundation

// MARK: - Model

/// A row in the menu's device list. `isAvailable == false` means the UID is part of the persisted
/// selection but the HAL doesn't currently report a matching device (unplugged) — drawn greyed out,
/// still checked (see PLAN-multi-output.md, decision 5).
struct DeviceRow {
    let uid: String
    let name: String
    let isSelected: Bool
    let isAvailable: Bool
}

// MARK: - Protocols

protocol AudioManager: AnyObject {
    func getDefaultOutputDevice() -> AudioDeviceID
    func getOutputDevices() -> [AudioDeviceID: String]?
    func selectDevice(deviceID: AudioDeviceID)
    func getSelectedDeviceVolume() -> Float?
    func setSelectedDeviceVolume(masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float)
    func isSelectedDeviceMuted() -> Bool
    func toggleMute()

    var isMuted: Bool { get }

    // Multi-output selection (v1.2.0) — see PLAN-multi-output.md
    func currentDeviceRows() -> [DeviceRow]
    @discardableResult
    func toggleSelection(uid: String) -> Bool
    func selectSingle(uid: String)
    func restoreSelectionAtLaunch()

    /// Reconciles our selection with an externally-changed system default output (v1.3.0, A-10).
    /// Returns `true` when state changed so the caller refreshes the UI.
    func reconcileWithSystemDefault() -> Bool
}

// MARK: - Implementation

final class AudioManagerImpl: AudioManager {
    private let audio: Audio
    private let aggregateDeviceManager: AggregateDeviceManager
    private let defaults: UserDefaults

    private var selectedDevice: AudioDeviceID?

    /// SSOT for multi-output: ordered UIDs of the devices the user checked. Order matters — index 0
    /// is the master candidate when the aggregate is (re)built. Size 0 is never persisted past
    /// `applySelection` — the UI refuses to uncheck the last box (decision 4).
    private var selection: [String] = []
    private var lastKnownNames: [String: String] = [:]

    /// Multi-output we auto-left when the system pulled the default onto a single interceptor device
    /// (e.g. AirPods). Memory-only, never persisted. Set when the follow branch abandons a ≥2 set,
    /// consumed by the restore branch when the interceptor drops out, and cleared by any manual pick —
    /// an explicit user choice cancels "put the old set back". See A-10.
    private var rememberedMultiSelection: [String]?

    /// Refreshed on every `currentDeviceRows()`/launch call — never cached across menu openings, so
    /// newly attached/removed devices show up without a restart.
    private var realDevices: [AudioDeviceID: String] = [:]
    private var deviceIDByUID: [String: AudioDeviceID] = [:]

    init(audio: Audio, aggregateDeviceManager: AggregateDeviceManager, defaults: UserDefaults = .standard) {
        self.audio = audio
        self.aggregateDeviceManager = aggregateDeviceManager
        self.defaults = defaults
        self.lastKnownNames = defaults.dictionary(forKey: Constants.UserDefaultsKeys.deviceNamesByUID) as? [String: String] ?? [:]
        printDevices()
    }

    func getDefaultOutputDevice() -> AudioDeviceID {
        return audio.getDefaultOutputDevice()
    }

    /// Filters out our own managed aggregate — it is an implementation detail, never a pickable
    /// output device (PLAN-multi-output.md, A3).
    func getOutputDevices() -> [AudioDeviceID: String]? {
        guard let rawDevices = audio.getOutputDevices() else {
            return nil
        }

        var filtered: [AudioDeviceID: String] = [:]
        for device in rawDevices where audio.getDeviceUID(deviceID: device.key) != Constants.Aggregate.uid {
            filtered[device.key] = device.value
        }
        return filtered
    }

    func isAggregateDevice(deviceID: AudioDeviceID) -> Bool {
        return audio.isAggregateDevice(deviceID: deviceID)
    }

    func selectDevice(deviceID: AudioDeviceID) {
        selectedDevice = deviceID
        audio.setOutputDevice(newDeviceID: deviceID)
        Logger.debug(Constants.InnerMessages.selectDevice(deviceID: String(deviceID)))
    }

    func getSelectedDeviceVolume() -> Float? {
        guard let selectedDevice = selectedDevice else {
            return nil
        }

        if audio.isAggregateDevice(deviceID: selectedDevice) {
            let aggregatedDevices = audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice)

            for device in aggregatedDevices {
                if audio.isOutputDevice(deviceID: device) {
                    return audio.getDeviceVolume(deviceID: device).max()
                }
            }
        } else {
            return audio.getDeviceVolume(deviceID: selectedDevice).max()
        }

        return nil
    }

    func setSelectedDeviceVolume(masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float) {
        guard let selectedDevice = selectedDevice else {
            return
        }

        let isMute = masterChannelLevel < Constants.muteVolumeLowerbound
            && leftChannelLevel < Constants.muteVolumeLowerbound
            && rightChannelLevel < Constants.muteVolumeLowerbound

        if audio.isAggregateDevice(deviceID: selectedDevice) {
            let aggregatedDevices = audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice)

            for device in aggregatedDevices {
                audio.setDeviceVolume(
                    deviceID: device,
                    masterChannelLevel: masterChannelLevel,
                    leftChannelLevel: leftChannelLevel,
                    rightChannelLevel: rightChannelLevel
                )
                audio.setDeviceMute(deviceID: device, isMute: isMute)
            }
        } else {
            audio.setDeviceVolume(
                deviceID: selectedDevice,
                masterChannelLevel: masterChannelLevel,
                leftChannelLevel: leftChannelLevel,
                rightChannelLevel: rightChannelLevel
            )
            audio.setDeviceMute(deviceID: selectedDevice, isMute: isMute)
        }
    }

    func setSelectedDeviceMute(isMute: Bool) {
        guard let selectedDevice = selectedDevice else {
            return
        }

        if audio.isAggregateDevice(deviceID: selectedDevice) {
            let aggregatedDevices = audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice)

            for device in aggregatedDevices {
                audio.setDeviceMute(deviceID: device, isMute: isMute)
            }
        } else {
            audio.setDeviceMute(deviceID: selectedDevice, isMute: isMute)
        }
    }

    func isSelectedDeviceMuted() -> Bool {
        guard let selectedDevice = selectedDevice else {
            return false
        }

        if audio.isAggregateDevice(deviceID: selectedDevice) {
            let aggregatedDevices = audio.getAggregateDeviceSubDeviceList(deviceID: selectedDevice)

            guard let device = aggregatedDevices.first else {
                return false
            }

            return audio.isDeviceMuted(deviceID: device)
        } else {
            return audio.isDeviceMuted(deviceID: selectedDevice)
        }
    }

    func toggleMute() {
        if isSelectedDeviceMuted() {
            setSelectedDeviceMute(isMute: false)
            let volume = getSelectedDeviceVolume() ?? 0
            setSelectedDeviceVolume(masterChannelLevel: volume, leftChannelLevel: volume, rightChannelLevel: volume)
        } else {
            setSelectedDeviceMute(isMute: true)
        }
    }

    var isMuted: Bool {
        return isSelectedDeviceMuted()
    }

    // MARK: Multi-output selection

    func currentDeviceRows() -> [DeviceRow] {
        refreshDevices()

        var seenUIDs = Set<String>()
        var rows: [DeviceRow] = []

        for (uid, deviceID) in deviceIDByUID {
            let name = realDevices[deviceID] ?? uid
            lastKnownNames[uid] = name
            rows.append(DeviceRow(uid: uid, name: name, isSelected: selection.contains(uid), isAvailable: true))
            seenUIDs.insert(uid)
        }

        for uid in selection where !seenUIDs.contains(uid) {
            let name = lastKnownNames[uid] ?? uid
            rows.append(DeviceRow(uid: uid, name: name, isSelected: true, isAvailable: false))
        }

        persistNames()

        return rows.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Shift-click: toggles membership without ever allowing the set to go empty (decision 4).
    /// Returns `false` (no-op) when the caller tried to uncheck the last remaining device.
    @discardableResult
    func toggleSelection(uid: String) -> Bool {
        var newSelection = selection

        if let index = newSelection.firstIndex(of: uid) {
            guard newSelection.count > 1 else {
                Logger.warning(Constants.InnerMessages.emptySelectionRejected)
                return false
            }
            newSelection.remove(at: index)
        } else {
            newSelection.append(uid)
        }

        rememberedMultiSelection = nil
        applySelection(newSelection)
        return true
    }

    /// Plain click: collapses the selection down to exactly this one device.
    func selectSingle(uid: String) {
        rememberedMultiSelection = nil
        applySelection([uid])
    }

    /// Restores the persisted selection at launch, falling back (in order) to: the surviving
    /// aggregate's own composition (persistence lost but the device is still alive), then the
    /// system's current default device (fresh install) — so volume control is never left dead.
    func restoreSelectionAtLaunch() {
        refreshDevices()
        let orphanID = aggregateDeviceManager.findOwnDevice()

        var storedSelection = loadPersistedSelection()

        if storedSelection.isEmpty, let orphanID = orphanID {
            storedSelection = audio.getAggregateFullSubDeviceList(deviceID: orphanID)
        }

        if storedSelection.isEmpty {
            guard let defaultUID = audio.getDeviceUID(deviceID: audio.getDefaultOutputDevice()) else {
                selectedDevice = audio.getDefaultOutputDevice()
                return
            }
            storedSelection = [defaultUID]
        }

        commitSelectionRoutingAvailable(storedSelection)
    }

    /// Reacts to the system default output being changed from outside the app (headphones
    /// auto-switch, Control Center, another app). Called on the main queue from the HAL listener;
    /// returns `true` when it mutated state so the caller refreshes the menu. See A-10.
    func reconcileWithSystemDefault() -> Bool {
        let defaultID = audio.getDefaultOutputDevice()

        // Our own aggregate is default because *we* just routed to it — following it would loop.
        // Belt-and-braces: match both by cached deviceID and by the fixed UID.
        if let aggregateID = aggregateDeviceManager.deviceID, defaultID == aggregateID {
            return false
        }
        guard let defaultUID = audio.getDeviceUID(deviceID: defaultID) else {
            return false
        }
        if defaultUID == Constants.Aggregate.uid {
            return false
        }

        refreshDevices()
        let liveUIDs = Set(deviceIDByUID.keys)

        // Already in sync — our own write echoing back, or a duplicate event. Refresh the routed
        // device (so volume reads hit the right target) but report no change.
        if selection == [defaultUID] {
            selectedDevice = defaultID
            return false
        }

        // Restore branch: we followed the system onto a single interceptor (AirPods), it has now
        // dropped out of the live set, and we still remember the multi-output it displaced —
        // rebuild it.
        if let remembered = rememberedMultiSelection,
            selection.count == 1,
            let current = selection.first,
            !liveUIDs.contains(current) {
            rememberedMultiSelection = nil
            commitSelectionRoutingAvailable(remembered)
            return true
        }

        // Follow branch: adopt the system default as a single selection. If we are leaving a live
        // multi-output, remember it first so unplugging the interceptor can bring it back.
        if selection.count >= 2 {
            rememberedMultiSelection = selection
        }
        applySelection([defaultUID])
        return true
    }

    // MARK: Private

    /// Commits `uids` as the SSOT selection (persisted; unplugged UIDs stay as greyed-out rows,
    /// decision 5) and routes audio to whichever subset is currently plugged in — ≥2 rebuilds the
    /// aggregate, exactly 1 switches straight to it, 0 falls back to the system default so volume
    /// control is never left dead. Shared by launch restore and the A-10 multi-output restore.
    private func commitSelectionRoutingAvailable(_ uids: [String]) {
        selection = uids
        persistSelection()

        let availableUIDs = uids.filter { deviceIDByUID[$0] != nil }

        if availableUIDs.count >= 2 {
            routeSelection(availableUIDs)
        } else if let single = availableUIDs.first, let deviceID = deviceIDByUID[single] {
            selectDevice(deviceID: deviceID)
        } else {
            selectedDevice = audio.getDefaultOutputDevice()
        }
    }

    private func applySelection(_ uids: [String]) {
        selection = uids
        persistSelection()
        routeSelection(uids)
    }

    /// Order matters here (`docs/coreaudio.md` §"без заикания"): configure/create before switching
    /// default, switch default before destroying, never switch default and destroy in the same step.
    ///
    /// The single-device branch resolves UID -> deviceID through `deviceIDByUID`, which is only
    /// populated by `refreshDevices()` (i.e. by the menu opening). That precondition is structural,
    /// not accidental: a row click is impossible without the menu being open, and opening it always
    /// refreshes. Deliberately NOT guarded with an extra HAL refresh here — there is no programmatic
    /// selection path bypassing the menu, and burning HAL property reads on every pick to defend
    /// against a nonexistent caller isn't worth it (owner decision, 2026-07-18).
    private func routeSelection(_ uids: [String]) {
        if uids.count >= 2 {
            let alreadyOnAggregate = aggregateDeviceManager.deviceID != nil && selectedDevice == aggregateDeviceManager.deviceID

            if alreadyOnAggregate {
                aggregateDeviceManager.update(subDeviceUIDs: uids)
                reapplyCurrentVolumeState()
            } else {
                let previousVolume = getSelectedDeviceVolume()
                let wasMuted = isSelectedDeviceMuted()

                guard let aggregateID = aggregateDeviceManager.ensureDevice(subDeviceUIDs: uids) else {
                    return
                }

                selectedDevice = aggregateID
                audio.setOutputDevice(newDeviceID: aggregateID)

                if let previousVolume = previousVolume {
                    setSelectedDeviceVolume(masterChannelLevel: previousVolume, leftChannelLevel: previousVolume, rightChannelLevel: previousVolume)
                }
                if wasMuted {
                    setSelectedDeviceMute(isMute: true)
                }
            }
        } else if let single = uids.first, let deviceID = deviceIDByUID[single] {
            let wasMultiOutput = aggregateDeviceManager.deviceID != nil && selectedDevice == aggregateDeviceManager.deviceID

            selectDevice(deviceID: deviceID)

            // Hybrid lifecycle (decision 3): the aggregate is torn down the moment the selection
            // collapses to a single device, not deferred to app exit — where a live ≥2 selection is
            // deliberately left standing (see ApplicationController.stop()).
            if wasMultiOutput {
                aggregateDeviceManager.destroy()
            }
        }
    }

    private func reapplyCurrentVolumeState() {
        guard let volume = getSelectedDeviceVolume() else {
            return
        }
        let muted = isSelectedDeviceMuted()
        setSelectedDeviceVolume(masterChannelLevel: volume, leftChannelLevel: volume, rightChannelLevel: volume)
        if muted {
            setSelectedDeviceMute(isMute: true)
        }
    }

    private func refreshDevices() {
        let devices = getOutputDevices() ?? [:]
        realDevices = devices
        deviceIDByUID = [:]

        for device in devices {
            if let uid = audio.getDeviceUID(deviceID: device.key) {
                deviceIDByUID[uid] = device.key
            }
        }
    }

    private func loadPersistedSelection() -> [String] {
        return defaults.stringArray(forKey: Constants.UserDefaultsKeys.selectedDeviceUIDs) ?? []
    }

    private func persistSelection() {
        defaults.set(selection, forKey: Constants.UserDefaultsKeys.selectedDeviceUIDs)
    }

    private func persistNames() {
        defaults.set(lastKnownNames, forKey: Constants.UserDefaultsKeys.deviceNamesByUID)
    }

    private func printDevices() {
        guard let devices = getOutputDevices() else {
            return
        }
        Logger.debug(Constants.InnerMessages.outputDevices)
        for device in devices {
            Logger.debug(Constants.InnerMessages.debugDevice(deviceID: String(device.key), deviceName: device.value))
        }
    }
}
