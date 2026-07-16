//
//  Constants.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 16.11.2020.
//  Copyright © 2020 Dmitry Medyuho. All rights reserved.
//

import Foundation

enum Constants {
    static let chicletsCount = 16
    static let optionMaxLength = 25
    static let muteVolumeLowerbound: Float = 0.001
    static let logFilename = "app.log"
    
    enum AppBundleIdentifier {
        static let systemPreferences = "com.apple.systempreferences"
        static let audioDevices = "com.apple.audio.AudioMIDISetup"
    }

    enum SystemPreferencesPane {
        static let sound = "/System/Library/PreferencePanes/Sound.prefPane"
    }

    enum Paths {
        static let shell = "/bin/sh"
        static let hidutil = "/usr/bin/hidutil"
        static let defaults = "/usr/bin/defaults"
        static let killall = "/usr/bin/killall"
    }

    /// Fixed identity of the managed Multi-Output device (v1.2.0) — looked up by UID at every
    /// launch so a crash-orphaned device is reused instead of duplicated. See `docs/coreaudio.md`.
    enum Aggregate {
        static let uid = "io.github.emaslenkov.multisoundchanger2.output"
        static let name = "MultiSoundChanger2 Output"
    }

    /// `com.apple.controlcenter` `Sound` key values observed on this machine — see
    /// `docs/system-integration.md` §3. Not exhaustive across Control Center configurations.
    enum ControlCenter {
        static let domain = "com.apple.controlcenter"
        static let soundKey = "Sound"
        static let hiddenValue = 2
        static let processName = "ControlCenter"
    }

    enum UserDefaultsKeys {
        static let selectedDeviceUIDs = "selectedDeviceUIDs"
        static let deviceNamesByUID = "deviceNamesByUID"
        static let hideSystemVolumeIcon = "hideSystemVolumeIcon"
        static let savedSystemVolumeIconValue = "savedSystemVolumeIconValue"
        static let menuBarIconTint = "menuBarIconTint"
    }

    enum Notifications {
        static let accessibility = "com.apple.accessibility.api"
    }
    
    enum Keys: String {
        case empty = ""
        case q
    }
    
    enum InnerMessages {
        static let accessEnabled = "Access enabled"
        static let accessDenied = "Access denied"
        static let getDisplayError = "Error getting display under cursor"
        static let outputDevices = "Output devices"
        static let bundleIdentifierError = "Can't get bundle identifier"
        static let controllerIdentifierError = "Wrong controller identifier"
        static let keyMappingApplied = "Media key remapping applied"
        static let keyMappingReverted = "Media key remapping reverted"
        static let keyMappingStaleFound = "Found stale media key remapping from a previous session, clearing it"
        static let keyMappingParseError = "Can't parse current UserKeyMapping, skipping remap to avoid clobbering user mappings"
        static let remapSkippedNoAccess = "No accessibility access: volume keys left to the system rather than remapped into keys nothing can handle"

        static func shellLaunchError(command: String, error: String) -> String {
            return "Can't run shell command '\(command)': \(error)"
        }

        static func applicationNotFound(bundleIdentifier: String) -> String {
            return "Can't find application with bundle identifier: \(bundleIdentifier)"
        }

        static func applicationLaunchError(bundleIdentifier: String, error: String) -> String {
            return "Can't launch application \(bundleIdentifier): \(error)"
        }

        static func deviceNameError(deviceID: String) -> String {
            return "Can't read name of device id: \(deviceID)"
        }

        static func debugDevice(deviceID: String, deviceName: String) -> String {
            return "id: \(deviceID) | name: \(deviceName)"
        }
        
        static func selectDevice(deviceID: String) -> String {
            return "Select device id: \(deviceID)"
        }
        
        static func selectedDeviceVolume(volume: String) -> String {
            return "Selected device volume: \(volume)"
        }

        static func aggregateOrphanFound(deviceID: String) -> String {
            return "Reusing orphaned aggregate device id: \(deviceID)"
        }

        static func aggregateCreated(deviceID: String) -> String {
            return "Created aggregate device id: \(deviceID)"
        }

        static let aggregateCreateError = "Failed to create aggregate device"

        static func aggregateUpdated(uids: [String]) -> String {
            return "Aggregate device sub-devices updated: \(uids.joined(separator: ", "))"
        }

        static let aggregateUpdateError = "Failed to update aggregate device sub-device list"

        static func aggregateDestroyed(deviceID: String) -> String {
            return "Destroyed aggregate device id: \(deviceID)"
        }

        static let emptySelectionRejected = "Rejected selection change that would leave zero output devices"

        static func systemVolumeIconValue(value: String) -> String {
            return "System volume icon Control Center value: \(value)"
        }

        static let systemVolumeIconHidden = "System volume icon hidden"
        static let systemVolumeIconRestored = "System volume icon restored"
        static let systemVolumeIconWriteError = "Failed to write com.apple.controlcenter Sound value, leaving icon as-is"
        static let systemVolumeIconExternallyChanged = "System volume icon value was changed outside the app, not overwriting"
    }
}
