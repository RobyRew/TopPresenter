//
//  AppState.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import Observation

@Observable
final class AppState {
    // MARK: - Navigation
    var selectedSidebarItem: SidebarItem = .bible {
        didSet {
            // The advanced settings unlock is PER-VISIT: leaving the Settings
            // section locks it again (10 clicks re-open it).
            if oldValue == .settings && selectedSidebarItem != .settings {
                advancedSettingsUnlocked = false
            }
        }
    }
    /// Session-scoped easter-egg unlock for Settings ▸ Avansat (10 quick
    /// clicks on the sidebar Settings row). NOT persisted on purpose.
    var advancedSettingsUnlocked: Bool = false
    /// One-shot request: SettingsContentView switches to this tab id and
    /// clears it (the 10-click unlock auto-opens „Avansat").
    var settingsTabRequest: String?
    var isImporting: Bool = false
    var importProgress: Double = 0.0
    var importStatus: String = ""

    // MARK: - Menu-triggered Actions
    var triggerBibleImport: Bool = false
    var triggerSongImport: Bool = false

    // MARK: - Alert
    var showAlert: Bool = false
    var alertTitle: String = ""
    var alertMessage: String = ""

    // MARK: - Sidebar Items
    enum SidebarItem: String, CaseIterable, Identifiable {
        case bible = "Bible"
        case songs = "Songs"
        case media = "Media"
        case schedule = "Schedule"
        case customSlides = "Custom Slides"
        case history = "History"
        case settings = "Settings"
        case account = "Account"

        var id: String { rawValue }

        /// Content sections (top of the sidebar).
        static let contentItems: [SidebarItem] = [.bible, .songs, .media, .schedule, .customSlides]
        /// Utility destinations pinned to the bottom of the sidebar.
        static let utilityItems: [SidebarItem] = [.history, .settings, .account]

        var localizedName: String {
            switch self {
            case .bible: return String(localized: "Bible", comment: "Sidebar item")
            case .songs: return String(localized: "Songs", comment: "Sidebar item")
            case .media: return String(localized: "Media", comment: "Sidebar item")
            case .schedule: return String(localized: "Schedule", comment: "Sidebar item")
            case .customSlides: return String(localized: "Custom Slides", comment: "Sidebar item")
            case .history: return String(localized: "History", comment: "Sidebar item")
            case .settings: return String(localized: "Settings", comment: "Sidebar item")
            case .account: return String(localized: "Account", comment: "Sidebar item")
            }
        }

        var systemImage: String {
            switch self {
            case .bible: return "book.fill"
            case .songs: return "music.note.list"
            case .media: return "photo.on.rectangle"
            case .schedule: return "list.bullet.rectangle"
            case .customSlides: return "rectangle.stack.fill"
            case .history: return "clock.arrow.circlepath"
            case .settings: return "gearshape"
            case .account: return "person.crop.circle"
            }
        }
    }

    func showError(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }

    func showSuccess(_ title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
