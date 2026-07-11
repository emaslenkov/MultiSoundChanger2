//
//  MediaKeyRemapper.swift
//  MultiSoundChanger
//
//  On macOS 26+ the system handles volume keys at the HID layer, before any
//  CGEventTap can swallow them, so the useless "Multi-Output Device" HUD always
//  appears. Remapping the consumer-page volume usages to F18/F19/F20 at the
//  driver level hides the keys from the system entirely; MediaKeyTap picks the
//  F-keys up instead (see functionKeyCodeToMediaKey).
//

import Foundation

enum MediaKeyRemapper {
    // (0x0C << 32 | usage) consumer page: VolumeIncrement 0xE9, VolumeDecrement 0xEA, Mute 0xE7
    // (0x07 << 32 | usage) keyboard page: F18 0x6D, F19 0x6E, F20 0x6F
    private static let mapping = """
    {"UserKeyMapping":[\
    {"HIDKeyboardModifierMappingSrc":0xC000000E9,"HIDKeyboardModifierMappingDst":0x70000006D},\
    {"HIDKeyboardModifierMappingSrc":0xC000000EA,"HIDKeyboardModifierMappingDst":0x70000006E},\
    {"HIDKeyboardModifierMappingSrc":0xC000000E7,"HIDKeyboardModifierMappingDst":0x70000006F}]}
    """

    static func apply() {
        Runner.shell("/usr/bin/hidutil property --set '\(mapping)'")
    }

    static func revert() {
        Runner.shell("/usr/bin/hidutil property --set '{\"UserKeyMapping\":[]}'")
    }
}
