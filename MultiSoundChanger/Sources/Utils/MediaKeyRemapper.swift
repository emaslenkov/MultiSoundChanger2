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

    private struct Mapping {
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

    private static var signalSources: [DispatchSourceSignal] = []

    // MARK: Public

    /// Installs our remapping while preserving any mapping the user set up themselves.
    ///
    /// Idempotent by construction: our own entries are dropped before ours are appended, so a
    /// stale mapping left behind by a crashed session is replaced rather than duplicated.
    static func apply() {
        let currentMappings = readMappings()
        let foreignMappings = currentMappings.filter { !ownSources.contains($0.src) }

        if currentMappings.count != foreignMappings.count {
            Logger.warning(Constants.InnerMessages.keyMappingStaleFound)
        }

        writeMappings(foreignMappings + ownMappings)
        Logger.debug(Constants.InnerMessages.keyMappingApplied)
    }

    /// Removes only our entries — the user's own remappings survive.
    static func revert() {
        let foreignMappings = readMappings().filter { !ownSources.contains($0.src) }
        writeMappings(foreignMappings)
        Logger.debug(Constants.InnerMessages.keyMappingReverted)
    }

    /// Reverts the remapping on SIGTERM/SIGINT too, not just on a clean quit.
    ///
    /// Nothing can be done about SIGKILL — the mapping outlives the process and the user is left
    /// with dead volume keys until the app is launched again (see `apply`) or they run
    /// `hidutil property --set '{"UserKeyMapping":[]}'` by hand. Documented in README.
    static func installSignalHandlers() {
        for signalNumber in [SIGTERM, SIGINT] {
            // Suppress the default disposition, otherwise the process dies before the handler runs.
            signal(signalNumber, SIG_IGN)

            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                revert()
                exit(EXIT_SUCCESS)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: Private

    private static func readMappings() -> [Mapping] {
        guard let output = Runner.shell("\(Constants.Paths.hidutil) property --get \"\(propertyName)\""),
            let data = output.data(using: .utf8) else {
            Logger.warning(Constants.InnerMessages.keyMappingParseError)
            return []
        }

        // hidutil prints an old-style (OpenStep) plist, while --set expects JSON.
        var format = PropertyListSerialization.PropertyListFormat.openStep

        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format),
            let entries = plist as? [Any] else {
            Logger.warning(Constants.InnerMessages.keyMappingParseError)
            return []
        }

        // An absent mapping prints as "(null)", which parses into a bare string, not a dictionary.
        return entries.compactMap { entry in
            guard let dictionary = entry as? [String: Any],
                let source = integer(from: dictionary[sourceKey]),
                let destination = integer(from: dictionary[destinationKey]) else {
                return nil
            }
            return Mapping(src: source, dst: destination)
        }
    }

    private static func writeMappings(_ mappings: [Mapping]) {
        let entries = mappings
            .map { "{\"\(sourceKey)\":\($0.src),\"\(destinationKey)\":\($0.dst)}" }
            .joined(separator: ",")

        Runner.shell("\(Constants.Paths.hidutil) property --set '{\"\(propertyName)\":[\(entries)]}'")
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
