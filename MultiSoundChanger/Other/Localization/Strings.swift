//
//  Strings.swift
//  MultiSoundChanger
//
//  Created by Dmitry Medyuho on 22.11.2020.
//  Copyright © 2020 Dmitry Medyuho. All rights reserved.
//

import Foundation

/// The single funnel for every user-facing string. Each entry is a *computed* property routed
/// through `LanguageManager`, not a one-time `NSLocalizedString` constant — that's what lets an
/// in-app language switch re-localize the UI at runtime once the menu is rebuilt (ADR A-13).
enum Strings {
    static var volume: String { LanguageManager.localized("volume") }
    static var output: String { LanguageManager.localized("output") }
    static var outputMultiple: String { LanguageManager.localized("output.multiple") }
    static var outputHint: String { LanguageManager.localized("output.hint") }
    static var quit: String { LanguageManager.localized("quit") }
    static var soundPreferences: String { LanguageManager.localized("sound.preferences") }
    static var audioDevices: String { LanguageManager.localized("audio.devices") }
    static var muted: String { LanguageManager.localized("muted") }
    static var hideSystemVolumeIcon: String { LanguageManager.localized("hide.system.icon") }
    static var launchAtLogin: String { LanguageManager.localized("launch.at.login") }
    static var iconTintHeader: String { LanguageManager.localized("icon.tint.header") }
    static var iconTintDefault: String { LanguageManager.localized("icon.tint.default") }
    static var iconTintBlue: String { LanguageManager.localized("icon.tint.blue") }
    static var iconTintOrange: String { LanguageManager.localized("icon.tint.orange") }
    static var iconTintGreen: String { LanguageManager.localized("icon.tint.green") }
    static var iconTintPurple: String { LanguageManager.localized("icon.tint.purple") }
    static var iconTintPink: String { LanguageManager.localized("icon.tint.pink") }
    static var language: String { LanguageManager.localized("language") }
    static var languageSystem: String { LanguageManager.localized("language.system") }
}
