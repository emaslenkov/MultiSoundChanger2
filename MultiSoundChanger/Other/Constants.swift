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
    }
}
