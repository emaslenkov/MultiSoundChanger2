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
//  The remapping lives in the system, not in this process: `hidutil property --set`
//  replaces the *entire* UserKeyMapping list. Writing our three entries blindly
//  would wipe any remapping the user set up themselves (Caps Lock -> Escape and
//  friends), so every write merges: read current list, drop our own entries,
//  keep everyone else's, append ours.
//

import Foundation

enum MediaKeyRemapper {
    // MARK: Types

    // Internal (not private) together with the pure helpers below: the merge semantics of A-3
    // ("preserve everyone else's mappings, replace only our own") is unit-tested directly.
    struct Mapping: Equatable {
        let src: Int64
        let dst: Int64
    }

    // (0x0C << 32 | usage) consumer page: VolumeIncrement 0xE9, VolumeDecrement 0xEA, Mute 0xE7
    // (0x07 << 32 | usage) keyboard page: F18 0x6D, F19 0x6E, F20 0x6F
    private enum Usage {
        static let volumeUp: Int64 = 0xC000000E9
        static let volumeDown: Int64 = 0xC000000EA
        static let mute: Int64 = 0xC000000E7
        static let functionKey18: Int64 = 0x70000006D
        static let functionKey19: Int64 = 0x70000006E
        static let functionKey20: Int64 = 0x70000006F
    }

    private static let sourceKey = "HIDKeyboardModifierMappingSrc"
    private static let destinationKey = "HIDKeyboardModifierMappingDst"
    private static let propertyName = "UserKeyMapping"

    private static let ownMappings: [Mapping] = [
        Mapping(src: Usage.volumeUp, dst: Usage.functionKey18),
        Mapping(src: Usage.volumeDown, dst: Usage.functionKey19),
        Mapping(src: Usage.mute, dst: Usage.functionKey20)
    ]

    private static var ownSources: Set<Int64> {
        return Set(ownMappings.map { $0.src })
    }

    // MARK: Public

    /// Installs our remapping while preserving any mapping the user set up themselves.
    ///
    /// Idempotent by construction: our own entries are dropped before ours are appended, so a
    /// stale mapping left behind by a crashed session is replaced rather than duplicated.
    static func apply() {
        let currentMappings = readMappings()

        if currentMappings != removingOwnMappings(from: currentMappings) {
            Logger.warning(Constants.InnerMessages.keyMappingStaleFound)
        }

        writeMappings(applyingOwnMappings(to: currentMappings))
        Logger.debug(Constants.InnerMessages.keyMappingApplied)
    }

    /// Removes only our entries — the user's own remappings survive.
    static func revert() {
        writeMappings(removingOwnMappings(from: readMappings()))
        Logger.debug(Constants.InnerMessages.keyMappingReverted)
    }

    // MARK: Pure transformations (unit-tested)

    /// Parses `hidutil property --get` output — an old-style (OpenStep) plist, while `--set`
    /// expects JSON. Returns `nil` when the output is not a plist array at all; note the "(null)"
    /// printed for an absent mapping IS a valid OpenStep array (holding the bare word `null`), so
    /// it parses to empty mappings rather than an error.
    static func parseMappings(from output: String) -> [Mapping]? {
        guard let data = output.data(using: .utf8) else {
            return nil
        }

        var format = PropertyListSerialization.PropertyListFormat.openStep

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
            let entries = plist as? [Any] else {
            return nil
        }

        return entries.compactMap { entry in
            guard let dictionary = entry as? [String: Any],
                let source = integer(from: dictionary[sourceKey]),
                let destination = integer(from: dictionary[destinationKey]) else {
                return nil
            }
            return Mapping(src: source, dst: destination)
        }
    }

    /// A-3 merge: everyone else's mappings survive, our own are replaced rather than duplicated —
    /// idempotent by construction, so a stale set left by a crashed session heals itself.
    static func applyingOwnMappings(to current: [Mapping]) -> [Mapping] {
        return removingOwnMappings(from: current) + ownMappings
    }

    static func removingOwnMappings(from current: [Mapping]) -> [Mapping] {
        return current.filter { !ownSources.contains($0.src) }
    }

    /// JSON payload for `hidutil property --set` (which, unlike `--get`, expects JSON).
    static func setPayload(for mappings: [Mapping]) -> String {
        let entries = mappings
            .map { "{\"\(sourceKey)\":\($0.src),\"\(destinationKey)\":\($0.dst)}" }
            .joined(separator: ",")

        return "{\"\(propertyName)\":[\(entries)]}"
    }

    // MARK: Private

    private static func readMappings() -> [Mapping] {
        guard let output = Runner.shell("\(Constants.Paths.hidutil) property --get \"\(propertyName)\""),
            let mappings = parseMappings(from: output) else {
            Logger.warning(Constants.InnerMessages.keyMappingParseError)
            return []
        }

        return mappings
    }

    private static func writeMappings(_ mappings: [Mapping]) {
        Runner.shell("\(Constants.Paths.hidutil) property --set '\(setPayload(for: mappings))'")
    }

    /// Values come back as strings in the OpenStep plist, but tolerate numbers too.
    private static func integer(from value: Any?) -> Int64? {
        if let string = value as? String {
            return Int64(string)
        }
        if let number = value as? NSNumber {
            return number.int64Value
        }
        return nil
    }
}
