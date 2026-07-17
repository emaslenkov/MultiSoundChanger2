//
//  Audio.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 03.04.17.
//  Copyright © 2017 Dmitry Medyuho. All rights reserved.
//

import AudioToolbox
import Cocoa
import Foundation

// MARK: - Protocols

protocol Audio {
    func getOutputDevices() -> [AudioDeviceID: String]?
    func isOutputDevice(deviceID: AudioDeviceID) -> Bool
    func getAggregateDeviceSubDeviceList(deviceID: AudioDeviceID) -> [AudioDeviceID]
    func isAggregateDevice(deviceID: AudioDeviceID) -> Bool
    func setDeviceVolume(deviceID: AudioDeviceID, masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float)
    func setDeviceMute(deviceID: AudioDeviceID, isMute: Bool)
    func setOutputDevice(newDeviceID: AudioDeviceID)
    func isDeviceMuted(deviceID: AudioDeviceID) -> Bool
    func getDeviceVolume(deviceID: AudioDeviceID) -> [Float]
    func getDefaultOutputDevice() -> AudioDeviceID
    func getDeviceTransportType(deviceID: AudioDeviceID) -> AudioDevicePropertyID
    func getDeviceUID(deviceID: AudioDeviceID) -> String?
    func getDeviceID(byUID uid: String) -> AudioDeviceID?
    func createAggregateDevice(name: String, uid: String, subDeviceUIDs: [String], masterUID: String) -> AudioDeviceID?
    @discardableResult
    func destroyAggregateDevice(deviceID: AudioDeviceID) -> Bool
    func setAggregateFullSubDeviceList(deviceID: AudioDeviceID, subDeviceUIDs: [String]) -> Bool
    func getAggregateFullSubDeviceList(deviceID: AudioDeviceID) -> [String]
    func setAggregateMasterSubDevice(deviceID: AudioDeviceID, masterUID: String) -> Bool
    @discardableResult
    func setSubDeviceDriftCompensation(subDeviceID: AudioDeviceID, enabled: Bool) -> Bool
    func addDefaultOutputDeviceListener(handler: @escaping () -> Void)
    func removeDefaultOutputDeviceListener()
}

// MARK: - Implementation

final class AudioImpl: Audio {
    /// Retained so the matching `AudioObjectRemovePropertyListenerBlock` can be issued at teardown —
    /// the block identity must be the same object passed to `Add`, otherwise removal is a no-op.
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?

    func getOutputDevices() -> [AudioDeviceID: String]? {
        var result: [AudioDeviceID: String] = [:]
        let devices = getAllDevices()
        
        for device in devices where isOutputDevice(deviceID: device) {
            result[device] = getDeviceName(deviceID: device)
        }
        
        return result
    }
    
    func isOutputDevice(deviceID: AudioDeviceID) -> Bool {
        var propertySize: UInt32 = 256
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreams),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        
        return propertySize > 0
    }
    
    func getAggregateDeviceSubDeviceList(deviceID: AudioDeviceID) -> [AudioDeviceID] {
        let subDevicesCount = getNumberOfSubDevices(deviceID: deviceID)
        var subDevices = [AudioDeviceID](repeating: 0, count: Int(subDevicesCount))
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioAggregateDevicePropertyActiveSubDeviceList),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        var subDevicesSize = subDevicesCount * UInt32(MemoryLayout<UInt32>.size)
        
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &subDevicesSize, &subDevices)
        
        return subDevices
    }
    
    func isAggregateDevice(deviceID: AudioDeviceID) -> Bool {
        let deviceType = getDeviceTransportType(deviceID: deviceID)
        return deviceType == kAudioDeviceTransportTypeAggregate
    }
    
    func isDeviceMuted(deviceID: AudioDeviceID) -> Bool {
        var mutedValue: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &mutedValue)
        
        if status != noErr {
            return false
        }
        
        return mutedValue == 1
    }
    
    func setDeviceVolume(deviceID: AudioDeviceID, masterChannelLevel: Float, leftChannelLevel: Float, rightChannelLevel: Float) {
        var leftLevel = leftChannelLevel
        var rigthLevel = rightChannelLevel
        var masterLevel = masterChannelLevel
        
        var masterLevelPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(0)
        )
        
        var leftLevelPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(1)
        )
        
        var rightLevelPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(2)
        )
        
        var size = UInt32(0)
        
        AudioObjectGetPropertyDataSize(deviceID, &masterLevelPropertyAddress, 0, nil, &size)
        AudioObjectSetPropertyData(deviceID, &masterLevelPropertyAddress, 0, nil, size, &masterLevel)
        
        AudioObjectGetPropertyDataSize(deviceID, &leftLevelPropertyAddress, 0, nil, &size)
        AudioObjectSetPropertyData(deviceID, &leftLevelPropertyAddress, 0, nil, size, &leftLevel)
        
        AudioObjectGetPropertyDataSize(deviceID, &rightLevelPropertyAddress, 0, nil, &size)
        AudioObjectSetPropertyData(deviceID, &rightLevelPropertyAddress, 0, nil, size, &rigthLevel)
    }
    
    func setDeviceMute(deviceID: AudioDeviceID, isMute: Bool) {
        var mutedValue: UInt32 = isMute ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyMute),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, &mutedValue)
    }
    
    func setOutputDevice(newDeviceID: AudioDeviceID) {
        let propertySize = UInt32(MemoryLayout<UInt32>.size)
        var deviceID = newDeviceID
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, propertySize, &deviceID)
    }
    
    func getDeviceVolume(deviceID: AudioDeviceID) -> [Float] {
        var leftLevel = Float32(0)
        var rigthLevel = Float32(0)
        var masterLevel = Float32(0)
        
        var masterLevelPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(0)
        )
        
        var leftLevelPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(1)
        )
        
        var rightLevelPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyVolumeScalar),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: AudioObjectPropertyElement(2)
        )
        
        var size = UInt32(0)
        
        AudioObjectGetPropertyDataSize(deviceID, &masterLevelPropertyAddress, 0, nil, &size)
        AudioObjectGetPropertyData(deviceID, &masterLevelPropertyAddress, 0, nil, &size, &masterLevel)
        
        AudioObjectGetPropertyDataSize(deviceID, &leftLevelPropertyAddress, 0, nil, &size)
        AudioObjectGetPropertyData(deviceID, &leftLevelPropertyAddress, 0, nil, &size, &leftLevel)
        
        AudioObjectGetPropertyDataSize(deviceID, &rightLevelPropertyAddress, 0, nil, &size)
        AudioObjectGetPropertyData(deviceID, &rightLevelPropertyAddress, 0, nil, &size, &rigthLevel)
        
        return [masterLevel, leftLevel, rigthLevel]
    }
    
    func getDefaultOutputDevice() -> AudioDeviceID {
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var deviceID = kAudioDeviceUnknown
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize, &deviceID)
        
        return deviceID
    }
    
    func getDeviceTransportType(deviceID: AudioDeviceID) -> AudioDevicePropertyID {
        var deviceTransportType = AudioDevicePropertyID()
        var propertySize = UInt32(MemoryLayout<AudioDevicePropertyID>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyTransportType),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &deviceTransportType)

        return deviceTransportType
    }

    /// Same `Unmanaged<CFString>?` ownership pattern as `getDeviceName` — CoreAudio hands back a
    /// +1 retained reference.
    func getDeviceUID(deviceID: AudioDeviceID) -> String? {
        var propertySize = UInt32(MemoryLayout<CFString?>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceUID),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        var result: Unmanaged<CFString>?

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &result)

        guard status == noErr, let uid = result?.takeRetainedValue() else {
            return nil
        }

        return uid as String
    }

    /// Returns `nil` both on HAL error and when the UID is unknown to the system
    /// (`kAudioObjectUnknown`) — callers must not assume a non-nil result belongs to an aggregate
    /// they created themselves; that verification happens one layer up.
    func getDeviceID(byUID uid: String) -> AudioDeviceID? {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyTranslateUIDToDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        var deviceID = kAudioObjectUnknown
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var uidCF = uid as CFString

        let status = withUnsafeMutablePointer(to: &uidCF) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &propertyAddress,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &propertySize,
                &deviceID
            )
        }

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        return deviceID
    }

    /// Builds a Multi-Output device (`stacked: 1` — sound duplicated to every sub-device, as opposed
    /// to `0` which sums channels into an Aggregate). `private: 0` is required for the device to be
    /// visible to every app on the system, not just this process — see `docs/coreaudio.md`.
    /// Drift compensation is set on every non-master sub-device right in the creation description.
    func createAggregateDevice(name: String, uid: String, subDeviceUIDs: [String], masterUID: String) -> AudioDeviceID? {
        let subDevices: [[String: Any]] = subDeviceUIDs.map { subDeviceUID in
            var subDevice: [String: Any] = [kAudioSubDeviceUIDKey: subDeviceUID]
            if subDeviceUID != masterUID {
                subDevice[kAudioSubDeviceDriftCompensationKey] = 1
            }
            return subDevice
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMainSubDeviceKey: masterUID,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceIsStackedKey: 1
        ]

        var deviceID = kAudioObjectUnknown
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &deviceID)

        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }

        return deviceID
    }

    @discardableResult
    func destroyAggregateDevice(deviceID: AudioDeviceID) -> Bool {
        return AudioHardwareDestroyAggregateDevice(deviceID) == noErr
    }

    /// `FullSubDeviceList` carries neither drift compensation nor a master designation — callers
    /// must follow up with `setAggregateMasterSubDevice`/`setSubDeviceDriftCompensation` as needed.
    ///
    /// Passes the CFArray through `withUnsafePointer(to:)` rather than a bare `&subDevicesArray`:
    /// the latter compiles but warns ("forming UnsafeRawPointer to a variable that may contain an
    /// object reference") because the implicit inout-to-raw-pointer conversion isn't scoped the way
    /// an explicit `withUnsafePointer` closure is.
    func setAggregateFullSubDeviceList(deviceID: AudioDeviceID, subDeviceUIDs: [String]) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioAggregateDevicePropertyFullSubDeviceList),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        let subDevicesArray = subDeviceUIDs as CFArray
        let propertySize = UInt32(MemoryLayout<CFArray>.size)

        let status = withUnsafePointer(to: subDevicesArray) { pointer in
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, pointer)
        }

        return status == noErr
    }

    func getAggregateFullSubDeviceList(deviceID: AudioDeviceID) -> [String] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioAggregateDevicePropertyFullSubDeviceList),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        var propertySize = UInt32(MemoryLayout<CFArray?>.size)
        var result: Unmanaged<CFArray>?

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &result)

        guard status == noErr, let array = result?.takeRetainedValue() else {
            return []
        }

        return (array as? [String]) ?? []
    }

    /// Changing the master on a currently playing stream causes an audible glitch — callers should
    /// only call this when the previous master has dropped out, not on every composition change.
    func setAggregateMasterSubDevice(deviceID: AudioDeviceID, masterUID: String) -> Bool {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioAggregateDevicePropertyMainSubDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        let masterUIDCF = masterUID as CFString
        let propertySize = UInt32(MemoryLayout<CFString>.size)

        let status = withUnsafePointer(to: masterUIDCF) { pointer in
            AudioObjectSetPropertyData(deviceID, &propertyAddress, 0, nil, propertySize, pointer)
        }

        return status == noErr
    }

    @discardableResult
    func setSubDeviceDriftCompensation(subDeviceID: AudioDeviceID, enabled: Bool) -> Bool {
        var value: UInt32 = enabled ? 1 : 0
        let propertySize = UInt32(MemoryLayout<UInt32>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioSubDevicePropertyDriftCompensation),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        let status = AudioObjectSetPropertyData(subDeviceID, &propertyAddress, 0, nil, propertySize, &value)

        return status == noErr
    }

    /// Fires `handler` on the main queue whenever the system default output device changes — headphones
    /// auto-switch, a Control Center pick, or another app taking over. Same property address as
    /// `getDefaultOutputDevice`. Idempotent: a previous registration is removed first so we never stack
    /// two blocks on the same object.
    func addDefaultOutputDeviceListener(handler: @escaping () -> Void) {
        removeDefaultOutputDeviceListener()

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        let block: AudioObjectPropertyListenerBlock = { _, _ in
            handler()
        }

        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )

        if status == noErr {
            defaultOutputListenerBlock = block
        }
    }

    func removeDefaultOutputDeviceListener() {
        guard let block = defaultOutputListenerBlock else {
            return
        }

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            DispatchQueue.main,
            block
        )

        defaultOutputListenerBlock = nil
    }

    private func getNumberOfDevices() -> UInt32 {
        var propertySize: UInt32 = 0
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &propertySize)
        
        return propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
    }
    
    private func getNumberOfSubDevices(deviceID: AudioDeviceID) -> UInt32 {
        var propertySize: UInt32 = 0
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioAggregateDevicePropertyActiveSubDeviceList),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &propertySize)
        
        return propertySize / UInt32(MemoryLayout<AudioDeviceID>.size)
    }
    
    /// Reads the device name as an `Unmanaged<CFString>` rather than writing straight into a
    /// `CFString` variable: CoreAudio hands back a +1 retained reference, and letting it write over
    /// an ARC-managed variable bypasses ownership entirely.
    private func getDeviceName(deviceID: AudioDeviceID) -> String {
        var propertySize = UInt32(MemoryLayout<CFString?>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceNameCFString),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))

        var result: Unmanaged<CFString>?

        let status = AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &propertySize, &result)

        guard status == noErr, let name = result?.takeRetainedValue() else {
            Logger.warning(Constants.InnerMessages.deviceNameError(deviceID: String(deviceID)))
            return String()
        }

        return name as String
    }
    
    private func getAllDevices() -> [AudioDeviceID] {
        let devicesCount = getNumberOfDevices()
        var devices = [AudioDeviceID](repeating: 0, count: Int(devicesCount))
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        var devicesSize = devicesCount * UInt32(MemoryLayout<UInt32>.size)
        
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &propertyAddress, 0, nil, &devicesSize, &devices)
        
        return devices
    }
}
