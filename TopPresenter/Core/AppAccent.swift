//
//  AppAccent.swift
//  TopPresenter
//
//  App-wide ACCENT + HIGHLIGHT colors (Settings ▸ Interfață ▸ Aspect).
//  Accent default = the LIVE macOS system accent (NSColor.controlAccentColor,
//  dynamic — follows System Settings ▸ Appearance instantly); presets and a
//  fully custom ColorPicker color override it. HIGHLIGHT (selection visuals:
//  selected verses/chapters/cards/palette rows) follows the accent by
//  default, or gets its own preset/custom color.
//
//  Usage rules:
//  - View code uses the globals `appAccent` / `appHighlight` — NEVER
//    `Color.accentColor` (that reads the asset catalog and ignores the
//    in-app choice). Selection visuals use `appHighlight`.
//  - Reading them inside `body` registers Observation on AccentStore, so a
//    settings change re-renders every dependent view.
//  - Native controls (pickers, toggles, list selection) follow the `.tint`
//    applied once at MainWindowRoot.
//

import SwiftUI
import Observation

enum AppAccentOption: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, mint, teal, indigo, brown
    /// Fully custom color (the ColorPicker well) — resolved by AccentStore.
    case custom

    var id: String { rawValue }

    /// The preset swatch row (custom is the ColorPicker, not a swatch).
    static var presets: [AppAccentOption] { allCases.filter { $0 != .custom } }

    var color: Color {
        switch self {
        case .system, .custom: return Color(nsColor: .controlAccentColor)
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .mint: return .mint
        case .teal: return .teal
        case .indigo: return .indigo
        case .brown: return .brown
        }
    }

    var localizedName: String {
        switch self {
        case .system: return String(localized: "Sistem", comment: "Accent option")
        case .blue: return String(localized: "Albastru", comment: "Accent option")
        case .purple: return String(localized: "Mov", comment: "Accent option")
        case .pink: return String(localized: "Roz", comment: "Accent option")
        case .red: return String(localized: "Roșu", comment: "Accent option")
        case .orange: return String(localized: "Portocaliu", comment: "Accent option")
        case .yellow: return String(localized: "Galben", comment: "Accent option")
        case .green: return String(localized: "Verde", comment: "Accent option")
        case .mint: return String(localized: "Mentă", comment: "Accent option")
        case .teal: return String(localized: "Turcoaz", comment: "Accent option")
        case .indigo: return String(localized: "Indigo", comment: "Accent option")
        case .brown: return String(localized: "Maro", comment: "Accent option")
        case .custom: return String(localized: "Personalizat", comment: "Accent option")
        }
    }
}

@MainActor
@Observable
final class AccentStore {
    static let shared = AccentStore()

    // MARK: Accent

    var option: AppAccentOption {
        didSet { UserDefaults.standard.set(option.rawValue, forKey: "appAccentColor") }
    }
    /// The ColorPicker color — used when `option == .custom`.
    var customAccent: Color {
        didSet { Self.store(customAccent, key: "appAccentCustom") }
    }

    // MARK: Highlight (selection visuals)

    /// Default ON: selections tint with the accent, one knob for everything.
    var highlightFollowsAccent: Bool {
        didSet { UserDefaults.standard.set(highlightFollowsAccent, forKey: "appHighlightFollows") }
    }
    var highlightOption: AppAccentOption {
        didSet { UserDefaults.standard.set(highlightOption.rawValue, forKey: "appHighlightOption") }
    }
    var customHighlight: Color {
        didSet { Self.store(customHighlight, key: "appHighlightCustom") }
    }

    // MARK: Resolved colors

    var accent: Color { option == .custom ? customAccent : option.color }

    var highlight: Color {
        if highlightFollowsAccent { return accent }
        return highlightOption == .custom ? customHighlight : highlightOption.color
    }

    init() {
        option = AppAccentOption(rawValue: UserDefaults.standard.string(forKey: "appAccentColor") ?? "") ?? .system
        customAccent = Self.load(key: "appAccentCustom") ?? Color(nsColor: .controlAccentColor)
        highlightFollowsAccent = UserDefaults.standard.object(forKey: "appHighlightFollows") as? Bool ?? true
        highlightOption = AppAccentOption(rawValue: UserDefaults.standard.string(forKey: "appHighlightOption") ?? "") ?? .system
        customHighlight = Self.load(key: "appHighlightCustom") ?? Color(nsColor: .controlAccentColor)
    }

    // MARK: Color persistence (sRGB components)

    private static func store(_ color: Color, key: String) {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return }
        UserDefaults.standard.set(
            [ns.redComponent, ns.greenComponent, ns.blueComponent, ns.alphaComponent].map(Double.init),
            forKey: key
        )
    }

    private static func load(key: String) -> Color? {
        guard let c = UserDefaults.standard.array(forKey: key) as? [Double], c.count == 4 else { return nil }
        return Color(.sRGB, red: c[0], green: c[1], blue: c[2], opacity: c[3])
    }
}

/// THE accent — use this everywhere view code needs the accent as a Color.
@MainActor var appAccent: Color { AccentStore.shared.accent }

/// THE selection-highlight color — selected verses/chapters/cards/rows.
@MainActor var appHighlight: Color { AccentStore.shared.highlight }
