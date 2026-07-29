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

    /// The localization the bundle ACTUALLY resolved at launch — not what we
    /// stored. Asking the bundle is the only honest answer: the stored preference
    /// can disagree with reality (it did, in the build that shipped the bug).
    @MainActor private static var effectiveAtLaunch: String?

    /// Call once, as early as possible — `AppleLanguages` is consumed at startup.
    @MainActor static func captureLaunchState() {
        if effectiveAtLaunch == nil {
            effectiveAtLaunch = Bundle.main.preferredLocalizations.first ?? "en"
        }
        reconcile()
    }

    /// Whether the app must restart before `language` becomes visible.
    @MainActor static func restartPending(for language: AppLanguage) -> Bool {
        guard let running = effectiveAtLaunch else { return false }
        if language == .system {
            // Following macOS again: a restart is owed only if we were overriding.
            return UserDefaults.standard.array(forKey: overrideKey) != nil
        }
        return !running.hasPrefix(language.rawValue)
    }

    /// Re-asserts a stored choice that never reached macOS.
    ///
    /// The shipped bug left people with a saved preference and no `AppleLanguages`
    /// entry. Re-picking the same language in the picker fires no change event, so
    /// without this they would be stuck: the only way out would be selecting a
    /// different language and coming back. This heals it on the next launch.
    @MainActor private static func reconcile() {
        let stored = current
        guard stored != .system else { return }
        let preferred = UserDefaults.standard.array(forKey: overrideKey) as? [String]
        if preferred?.first?.hasPrefix(stored.rawValue) != true {
            apply(stored)
        }
    }

    /// Writes the choice through to macOS.
    ///
    /// This ALWAYS writes, deliberately. The Settings picker is bound to
    /// `settingKey` via `@AppStorage`, which updates it before `.onChange` runs —
    /// so a `guard language != current` here silently matched every time and the
    /// `AppleLanguages` write never happened. The setting appeared to change and
    /// nothing did, restart or not.
    static func apply(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: settingKey)
        if language == .system {
            defaults.removeObject(forKey: overrideKey)
        } else {
            defaults.set([language.rawValue], forKey: overrideKey)
        }
    }
}
