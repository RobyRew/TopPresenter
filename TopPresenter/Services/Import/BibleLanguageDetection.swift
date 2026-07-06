//
//  BibleLanguageDetection.swift
//  TopPresenter
//
//  Shared language-code utilities: the canonical code→display-name map (used by the
//  Bible picker, import-side correction, and export) plus a defensive correction
//  that fixes a wrongly-declared language from the actual verse-text script.
//

import Foundation

/// Canonical code→display-name map. The app uses custom codes (e.g. "gr" for
/// Greek, "ebr" for Hebrew), not ISO. One source of truth.
nonisolated enum BibleLanguageNames {
    static let map: [String: String] = [
        "ro": "Română", "en": "English", "de": "Deutsch", "fr": "Français",
        "es": "Español", "it": "Italiano", "hu": "Magyar", "ru": "Русский",
        "gr": "Ελληνικά", "ebr": "עברית", "lat": "Latina", "ukr": "Українська",
        "nl": "Nederlands", "pg": "Português", "arab": "العربية",
        "sb": "Srpski", "roma": "Romani",
    ]

    static func name(for code: String) -> String { map[code] ?? code.uppercased() }
}

/// Many sources declare a wrong `language` (e.g. a Greek interlinear tagged "ro").
/// When the verse text is in a non-Latin script that contradicts the declared code,
/// trust the script. Latin scripts are left untouched — letters alone can't tell
/// ro/en/de apart, so we never override there.
nonisolated enum BibleLanguageDetection {
    /// Dominant script of a verse-text sample: "gr" | "ebr" | "cyrillic" | "latin" | nil.
    static func script(of sample: String) -> String? {
        var greek = 0, hebrew = 0, cyrillic = 0, latin = 0
        for scalar in sample.unicodeScalars {
            let c = scalar.value
            if (c >= 0x0370 && c <= 0x03FF) || (c >= 0x1F00 && c <= 0x1FFF) { greek += 1 }
            else if c >= 0x0590 && c <= 0x05FF { hebrew += 1 }
            else if c >= 0x0400 && c <= 0x04FF { cyrillic += 1 }
            else if (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) { latin += 1 }
        }
        if greek > 10 { return "gr" }
        if hebrew > 10 { return "ebr" }
        if cyrillic > 10 { return "cyrillic" }
        if latin > 10 { return "latin" }
        return nil
    }

    /// The corrected language code, given the declared code + a verse-text sample.
    static func refine(declared: String, sample: String) -> String {
        switch script(of: sample) {
        case "gr": return "gr"
        case "ebr": return "ebr"
        case "cyrillic": return ["ru", "ukr", "sb"].contains(declared) ? declared : "ru"
        default: return declared    // latin / unknown → trust the declared code
        }
    }
}
