//
//  AppLanguage.swift
//  TopPresenter
//
//  The in-app language override.
//
//  By default the app follows macOS: the system picks the best match from the
//  user's preferred languages against the locales in `knownRegions`, and nothing
//  here is involved. This exists for the case macOS cannot serve — an operator on
//  a Spanish Mac running a Romanian service, or a shared church machine where the
//  system language is not the operator's.
//
//  It works by writing `AppleLanguages`, which Foundation reads ONCE at launch,
//  so a change only takes effect after a restart. Anything that claimed to switch
//  live would be lying: the bundle's loaded .lproj cannot be swapped underneath a
//  running app.
//

import Foundation

nonisolated enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case en, ro, es, fr, de, ru

    var id: String { rawValue }

    /// UserDefaults key macOS itself reads for the preferred-language list.
    static let overrideKey = "AppleLanguages"
    /// Our own record of the choice — `AppleLanguages` alone cannot distinguish
    /// "follow the system" from "the system happened to pick this".
    static let settingKey = "app_languageOverride"

    /// Endonyms: a language is listed the way its own speakers write it, so it is
    /// findable by someone who does not read the current UI language.
    var displayName: String {
        switch self {
        case .system: return String(localized: "System", comment: "Language option — follow macOS")
        case .en: return "English"
        case .ro: return "Română"
        case .es: return "Español"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ru: return "Русский"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: settingKey) ?? "system") ?? .system
    }

    /// Applies the choice. Returns true when a restart is needed to see it.
    @discardableResult
    static func apply(_ language: AppLanguage) -> Bool {
        let defaults = UserDefaults.standard
        guard language != current else { return false }
        defaults.set(language.rawValue, forKey: settingKey)
        if language == .system {
            defaults.removeObject(forKey: overrideKey)
        } else {
            defaults.set([language.rawValue], forKey: overrideKey)
        }
        return true
    }
}
