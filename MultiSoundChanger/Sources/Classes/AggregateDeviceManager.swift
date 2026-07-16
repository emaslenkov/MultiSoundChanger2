//
//  AggregateDeviceManager.swift
//  MultiSoundChanger
//
//  Owns exactly one managed Multi-Output device (fixed UID, see `Constants.Aggregate`) used to
//  send sound to several real output devices at once — the alternative to the user manually
//  building an aggregate in Audio MIDI Setup. See `PLAN-multi-output.md` and `docs/coreaudio.md`
//  for the full design and CoreAudio API rationale.
//
//  The device is `private: 0` (visible system-wide, otherwise other apps' sound would never reach
//  it) and therefore survives a crash of this process — same nature as the hidutil remap and the
//  Control Center icon toggle (`.claude/rules/system-side-effects.md`). `findOwnDevice` is how a
//  crash-orphaned device gets reused instead of duplicated.
//

import AudioToolbox
import Foundation

// MARK: - Protocols

protocol AggregateDeviceManager: AnyObject {
    var deviceID: AudioDeviceID? { get }

    @discardableResult
    func findOwnDevice() -> AudioDeviceID?

    @discardableResult
    func ensureDevice(subDeviceUIDs: [String]) -> AudioDeviceID?

    func update(subDeviceUIDs: [String])
    func destroy()
}

// MARK: - Implementation

final class AggregateDeviceManagerImpl: AggregateDeviceManager {
    private let audio: Audio

    private(set) var deviceID: AudioDeviceID?
    private var currentMasterUID: String?

    init(audio: Audio) {
        self.audio = audio
    }

    /// Looks up our device by its fixed UID, then round-trips it: the UID must resolve back to
    /// itself and the object must actually be an aggregate. Only a verified match is cached — this
    /// is what keeps the manager from ever adopting some unrelated device.
    @discardableResult
    func findOwnDevice() -> AudioDeviceID? {
        guard let candidate = audio.getDeviceID(byUID: Constants.Aggregate.uid),
            audio.getDeviceUID(deviceID: candidate) == Constants.Aggregate.uid,
            audio.isAggregateDevice(deviceID: candidate) else {
            deviceID = nil
            return nil
        }

        if deviceID != candidate {
            Logger.debug(Constants.InnerMessages.aggregateOrphanFound(deviceID: String(candidate)))
        }
        deviceID = candidate
        return candidate
    }

    /// Idempotent: reuses a live device, reuses a crash-orphaned one, creates only as a last resort.
    /// `subDeviceUIDs` order matters — the first entry is the intended master (see `update`).
    @discardableResult
    func ensureDevice(subDeviceUIDs: [String]) -> AudioDeviceID? {
        let uids = ownUIDRemoved(subDeviceUIDs)
        guard let masterCandidate = uids.first else {
            return nil
        }

        if deviceID != nil || findOwnDevice() != nil {
            update(subDeviceUIDs: uids)
            return deviceID
        }

        guard let created = audio.createAggregateDevice(
            name: Constants.Aggregate.name,
            uid: Constants.Aggregate.uid,
            subDeviceUIDs: uids,
            masterUID: masterCandidate
        ) else {
            Logger.error(Constants.InnerMessages.aggregateCreateError)
            return nil
        }

        deviceID = created
        currentMasterUID = masterCandidate
        Logger.debug(Constants.InnerMessages.aggregateCreated(deviceID: String(created)))
        return created
    }

    /// Order: (1) full sub-device list, (2) master switch — only if the previous master dropped out
    /// of the set, since switching master on a live stream glitches, (3) drift compensation on every
    /// non-master active sub-device.
    func update(subDeviceUIDs: [String]) {
        guard let deviceID = deviceID else {
            return
        }

        let uids = ownUIDRemoved(subDeviceUIDs)
        guard !uids.isEmpty else {
            return
        }

        guard audio.setAggregateFullSubDeviceList(deviceID: deviceID, subDeviceUIDs: uids) else {
            Logger.error(Constants.InnerMessages.aggregateUpdateError)
            return
        }

        if currentMasterUID == nil || !uids.contains(currentMasterUID!) {
            if let newMaster = uids.first, audio.setAggregateMasterSubDevice(deviceID: deviceID, masterUID: newMaster) {
                currentMasterUID = newMaster
            }
        }

        applyDriftCompensation(deviceID: deviceID)
        Logger.debug(Constants.InnerMessages.aggregateUpdated(uids: uids))
    }

    func destroy() {
        guard let deviceID = deviceID else {
            return
        }

        audio.destroyAggregateDevice(deviceID: deviceID)
        Logger.debug(Constants.InnerMessages.aggregateDestroyed(deviceID: String(deviceID)))
        self.deviceID = nil
        currentMasterUID = nil
    }

    // MARK: Private

    /// Defensive anti-recursion filter: our own aggregate must never end up in its own sub-device
    /// list, even if a caller's device list forgot to exclude it.
    private func ownUIDRemoved(_ uids: [String]) -> [String] {
        return uids.filter { $0 != Constants.Aggregate.uid }
    }

    private func applyDriftCompensation(deviceID: AudioDeviceID) {
        let activeSubDevices = audio.getAggregateDeviceSubDeviceList(deviceID: deviceID)
        for subDevice in activeSubDevices {
            let isMaster = audio.getDeviceUID(deviceID: subDevice) == currentMasterUID
            audio.setSubDeviceDriftCompensation(subDeviceID: subDevice, enabled: !isMaster)
        }
    }
}
