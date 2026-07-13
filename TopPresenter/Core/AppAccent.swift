//
//  AppAccent.swift
//  TopPresenter
//
//  App-wide accent color (Settings ▸ Interfață ▸ Culoare accent).
//  Default = the LIVE macOS system accent (NSColor.controlAccentColor, a
//  dynamic color — follows System Settings ▸ Appearance changes instantly);
//  or one of the preset overrides.
//
//  Usage rules:
//  - View code uses the global `appAccent` — NEVER `appAccent`
//    (that reads the asset catalog and ignores the in-app choice).
//  - Reading `appAccent` inside `body` registers Observation on AccentStore,
//    so a settings change re-renders every dependent view.
//  - Native controls (pickers, toggles, list selection) follow the `.tint`
//    applied once at MainWindowRoot.
//

import SwiftUI
import Observation

enum AppAccentOption: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, mint, teal, indigo, brown

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
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
        }
    }
}

@MainActor
@Observable
final class AccentStore {
    static let shared = AccentStore()
    private static let key = "appAccentColor"

    var option: AppAccentOption {
        didSet { UserDefaults.standard.set(option.rawValue, forKey: Self.key) }
    }

    init() {
        option = AppAccentOption(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
    }
}

/// THE accent — use this everywhere view code needs the accent as a Color.
@MainActor var appAccent: Color { AccentStore.shared.option.color }
