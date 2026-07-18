//
//  FakeAudio.swift
//  MultiSoundChangerTests
//
//  In-memory stand-in for the CoreAudio HAL layer (`Audio`). Lets the tests exercise
//  AudioManager / AggregateDeviceManager logic without touching real devices. Records a call log
//  so tests can assert ordering ("without stutter": list -> master -> drift; switch default before
//  destroy). No real HAL, no system side-effects.
//

import AudioToolbox
@testable import MultiSoundChanger2

final class FakeAudio: Audio {
    struct Device {
        var uid: String
        var name: String
        var isOutput: Bool
        var transportType: AudioDevicePropertyID
        var volume: [Float] // [master, left, right]
        var muted: Bool
    }

    // MARK: State

    var devices: [AudioDeviceID: Device] = [:]
    var defaultOutputDeviceID: AudioDeviceID = 0

    // Aggregate bookkeeping, keyed by the aggregate's own deviceID.
    var aggregateFullSubDeviceUIDs: [AudioDeviceID: [String]] = [:]
    var aggregateMasterUID: [AudioDeviceID: String] = [:]
    var driftCompensation: [AudioDeviceID: Bool] = [:]

    // Test knobs for negative branches.
    var outputDevicesReturnsNil = false
    var failCreateAggregate = false
    var failSetFullSubDeviceList = false

    private(set) var calls: [String] = []
    private var listener: (() -> Void)?
    private var nextCreatedID: AudioDeviceID = 900

    private let aggregateTransportType = AudioDevicePropertyID(kAudioDeviceTransportTypeAggregate)
    private let builtInTransportType = AudioDevicePropertyID(kAudioDeviceTransportTypeBuiltIn)

    // MARK: Test helpers

    /// Registers a plain (non-aggregate) output device. Returns its deviceID.
    @discardableResult
    func addOutputDevice(id: AudioDeviceID, uid: String, name: String, volume: Float = 0.5, muted: Bool = false) -> AudioDeviceID {
        devices[id] = Device(
            uid: uid,
            name: name,
            isOutput: true,
            transportType: builtInTransportType,
            volume: [volume, volume, volume],
            muted: muted
        )
        return id
    }

    /// Fires the registered default-output listener, as CoreAudio would on an external change.
    func triggerDefaultOutputChange() {
        listener?()
    }

    var hasListener: Bool {
        return listener != nil
    }

    func clearCalls() {
        calls.removeAll()
    }

    /// Index of the first recorded call matching `predicate` — used to assert call ordering.
    func callIndex(_ predicate: (String) -> Bool) -> Int? {
        return calls.firstIndex(where: predicate)
    }

    /// Simulates unplugging a device (e.g. an interceptor like AirPods dropping out).
    func removeDevice(id: AudioDeviceID) {
        devices[id] = nil
    }

    private func deviceID(forUID uid: String) -> AudioDeviceID? {
        return devices.first { $0.value.uid == uid }?.key
    }

    /// The aggregate's active sub-device list is its full list filtered to UIDs that resolve to a
    /// live device — mirrors how the HAL only reports currently-connected sub-devices.
    private func activeSubDevices(of aggregateID: AudioDeviceID) -> [AudioDeviceID] {
        return (aggregateFullSubDeviceUIDs[aggregateID] ?? []).compactMap { deviceID(forUID: $0) }
    }

    // MARK: Audio — queries

    func getOutputDevices() -> [AudioDeviceID: String]? {
        if outputDevicesReturnsNil {
            return nil
        }
        var result: [AudioDeviceID: String] = [:]
        for (id, device) in devices where device.isOutput {
            result[id] = device.name
        }
        return result
    }

    func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
        return devices[deviceID]?.isOutput ?? false
    }

    func getAggregateDeviceSubDeviceList(deviceID: AudioDeviceID) -> [AudioDeviceID] {
        return activeSubDevices(of: deviceID)
    }

    func isAggregateDevice(deviceID: AudioDeviceID) -> Bool {
        return devices[deviceID]?.transportType == aggregateTransportType
    }

    func isDeviceMuted(deviceID: AudioDeviceID) -> Bool {
        return devices[deviceID]?.muted ?? false
    }

    func getDeviceVolume(deviceID: AudioDeviceID) -> [Float] {
        return devices[deviceID]?.volume ?? [0, 0, 0]
    }

    func getDefaultOutputDevice() -> AudioDeviceID {
        return defaultOutputDeviceID
    }

    func getDeviceTransportType(deviceID: AudioDeviceID) -> AudioDevicePropertyID {
        return devices[deviceID]?.transportType ?? 0
    }

    func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        return devices[deviceID]?.uid
    }

    func getDeviceID(byUID uid: String) -> AudioDeviceID? {
        return deviceID(forUID: uid)
    }

    func getAggregateFullSubDeviceList(deviceID: AudioDeviceID) -> [String] {
        return aggregateFullSubDeviceUIDs[deviceID] ?? []
    }

    // MARK: Audio — mutations

    func setDeviceVolume(deviceID: AudioDeviceID, masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float) {
        calls.append("setDeviceVolume(\(deviceID), \(masterChannelLevel))")
        devices[deviceID]?.volume = [masterChannelLevel, leftChannelLevel, rightChannelLevel]
    }

    func setDeviceMute(deviceID: AudioDeviceID, isMute: Bool) {
        calls.append("setDeviceMute(\(deviceID), \(isMute))")
        devices[deviceID]?.muted = isMute
    }

    func setOutputDevice(newDeviceID: AudioDeviceID) {
        calls.append("setOutputDevice(\(newDeviceID))")
        defaultOutputDeviceID = newDeviceID
    }

    func createAggregateDevice(name: String, uid: String, subDeviceUIDs: [String], masterUID: String) -> AudioDeviceID? {
        calls.append("createAggregateDevice(\(uid), master: \(masterUID))")
        guard !failCreateAggregate else {
            return nil
        }
        let id = nextCreatedID
        nextCreatedID += 1
        devices[id] = Device(
            uid: uid,
            name: name,
            isOutput: true,
            transportType: aggregateTransportType,
            volume: [0.5, 0.5, 0.5],
            muted: false
        )
        aggregateFullSubDeviceUIDs[id] = subDeviceUIDs
        aggregateMasterUID[id] = masterUID
        return id
    }

    @discardableResult
    func destroyAggregateDevice(deviceID: AudioDeviceID) -> Bool {
        calls.append("destroyAggregateDevice(\(deviceID))")
        devices[deviceID] = nil
        aggregateFullSubDeviceUIDs[deviceID] = nil
        aggregateMasterUID[deviceID] = nil
        return true
    }

    func setAggregateFullSubDeviceList(deviceID: AudioDeviceID, subDeviceUIDs: [String]) -> Bool {
        calls.append("setAggregateFullSubDeviceList(\(deviceID), \(subDeviceUIDs.joined(separator: "+")))")
        guard !failSetFullSubDeviceList else {
            return false
        }
        aggregateFullSubDeviceUIDs[deviceID] = subDeviceUIDs
        return true
    }

    func setAggregateMasterSubDevice(deviceID: AudioDeviceID, masterUID: String) -> Bool {
        calls.append("setAggregateMasterSubDevice(\(deviceID), \(masterUID))")
        aggregateMasterUID[deviceID] = masterUID
        return true
    }

    @discardableResult
    func setSubDeviceDriftCompensation(subDeviceID: AudioDeviceID, enabled: Bool) -> Bool {
        calls.append("setSubDeviceDriftCompensation(\(subDeviceID), \(enabled))")
        driftCompensation[subDeviceID] = enabled
        return true
    }

    func addDefaultOutputDeviceListener(handler: @escaping () -> Void) {
        listener = handler
    }

    func removeDefaultOutputDeviceListener() {
        listener = nil
    }
}
