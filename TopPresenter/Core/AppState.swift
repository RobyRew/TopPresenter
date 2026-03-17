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
    var selectedSidebarItem: SidebarItem = .bible
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

        var id: String { rawValue }

        var localizedName: String {
            switch self {
            case .bible: return String(localized: "Bible", comment: "Sidebar item")
            case .songs: return String(localized: "Songs", comment: "Sidebar item")
            case .media: return String(localized: "Media", comment: "Sidebar item")
            case .schedule: return String(localized: "Schedule", comment: "Sidebar item")
            case .customSlides: return String(localized: "Custom Slides", comment: "Sidebar item")
            }
        }

        var systemImage: String {
            switch self {
            case .bible: return "book.fill"
            case .songs: return "music.note.list"
            case .media: return "photo.on.rectangle"
            case .schedule: return "list.bullet.rectangle"
            case .customSlides: return "rectangle.stack.fill"
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
