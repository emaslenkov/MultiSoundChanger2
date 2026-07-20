//
//  LanguageManager.swift
//  MultiSoundChanger
//
//  Single source of localized strings and of the current language (ADR A-13). Every `Strings.*`
//  read goes through `localized(_:)`, so switching language and rebuilding the menu re-localizes the
//  whole UI at runtime without a relaunch. `.system` reads `Bundle.main` (macOS picks the language);
//  a pinned language reads its own `.lproj` bundle.
//

import Foundation

enum LanguageManager {
    private static let defaults = UserDefaults.standard

    /// Cached bundle for the current language. `nil` until first resolved; invalidated on every
    /// `setCurrent` so the next read rebuilds it. For `.system` this is `Bundle.main`.
    private static var cachedBundle: Bundle?

    static var current: AppLanguage {
        guard let raw = defaults.string(forKey: Constants.UserDefaultsKeys.appLanguage),
            let language = AppLanguage(rawValue: raw) else {
            return .system
        }
        return language
    }

    /// Persists the choice and drops the bundle cache. The caller is responsible for rebuilding any
    /// already-rendered UI (the menu) — this type only owns "which strings come out of `localized`".
    static func setCurrent(_ language: AppLanguage) {
        defaults.set(language.rawValue, forKey: Constants.UserDefaultsKeys.appLanguage)
        cachedBundle = nil
    }

    static func localized(_ key: String) -> String {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private static var bundle: Bundle {
        if let cachedBundle = cachedBundle {
            return cachedBundle
        }
        let resolved = resolveBundle(for: current)
        cachedBundle = resolved
        return resolved
    }

    /// Falls back to `Bundle.main` whenever the pinned `.lproj` can't be resolved (missing folder,
    /// stray persisted code) — a missing translation must never leave the UI without strings.
    private static func resolveBundle(for language: AppLanguage) -> Bundle {
        guard let code = language.lprojCode,
            let path = Bundle.main.path(forResource: code, ofType: "lproj"),
            let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }
}
