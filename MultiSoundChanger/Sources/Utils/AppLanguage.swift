//
//  AppLanguage.swift
//  MultiSoundChanger
//
//  In-app language selection (ADR A-13). `.system` follows macOS (reads `Bundle.main` as usual);
//  every other case pins a specific `.lproj` bundle at runtime, no relaunch. `rawValue` is what gets
//  persisted in `UserDefaults` and, for the pinned languages, is exactly the `.lproj` folder code.
//

import Foundation

enum AppLanguage: String, CaseIterable {
    case system
    case english = "en"
    case russian = "ru"
    case spanish = "es"
    case french = "fr"
    case chineseSimplified = "zh-Hans"
    case german = "de"
    case italian = "it"
    case portugueseBrazil = "pt-BR"
    case japanese = "ja"
    case korean = "ko"

    /// `nil` for `.system` — the app defers to `Bundle.main`/macOS. Otherwise the `.lproj` folder
    /// code to load a pinned localization from.
    var lprojCode: String? {
        self == .system ? nil : rawValue
    }

    /// The language's own name, shown in the menu (endonym) — so a user who wants Español sees
    /// "Español", not a translation into whatever language is currently active. `.system` is the
    /// only entry using a localized string, since "follow the system" has no endonym.
    var displayName: String {
        switch self {
        case .system:
            return Strings.languageSystem
        case .english:
            return "English"
        case .russian:
            return "Русский"
        case .spanish:
            return "Español"
        case .french:
            return "Français"
        case .chineseSimplified:
            return "中文"
        case .german:
            return "Deutsch"
        case .italian:
            return "Italiano"
        case .portugueseBrazil:
            return "Português (Brasil)"
        case .japanese:
            return "日本語"
        case .korean:
            return "한국어"
        }
    }
}
