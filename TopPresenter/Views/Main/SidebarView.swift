//
//  SidebarView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI

/// ONE native sidebar List — content modules on top, the utility
/// destinations (History · Settings · Account) as a second section of the
/// SAME list, so selection highlight, spacing and typography are the
/// system's (and follow the window `.tint`). No custom row chrome.
struct SidebarView: View {
    @Environment(AppState.self) private var appState

    /// Sidebar icon/row size: "system" follows macOS Settings ▸ Appearance ▸
    /// Sidebar icon size; the rest override it in-app.
    @AppStorage("sidebarRowSizeOption") private var sidebarRowSizeRaw = "system"

    /// Easter-egg unlock for Settings ▸ Avansat: 10 quick clicks (≤2s apart)
    /// on the Settings row. Session-scoped — AppState re-locks it when the
    /// user leaves the Settings section.
    @State private var settingsClickCount = 0
    @State private var lastSettingsClick = Date.distantPast

    var body: some View {
        @Bindable var state = appState

        List(selection: $state.selectedSidebarItem) {
            Section(String(localized: "Bibliotecă", comment: "Sidebar section")) {
                ForEach(AppState.SidebarItem.contentItems) { item in
                    Label(item.localizedName, systemImage: item.systemImage)
                        .tag(item)
                }
            }

            Section(String(localized: "Instrumente", comment: "Sidebar section")) {
                ForEach(AppState.SidebarItem.utilityItems) { item in
                    if item == .settings {
                        // A Button row (NOT a gesture on a selectable row —
                        // that fought the list's native click handling and
                        // made the row feel dead). The button both selects
                        // and counts; the .tag keeps the native highlight.
                        Button {
                            registerSettingsClick()
                            state.selectedSidebarItem = .settings
                        } label: {
                            Label(item.localizedName, systemImage: item.systemImage)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .tag(item)
                    } else {
                        Label(item.localizedName, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // "system" inherits the macOS sidebar icon size; overrides only set.
        .transformEnvironment(\.sidebarRowSize) { size in
            switch sidebarRowSizeRaw {
            case "small": size = .small
            case "medium": size = .medium
            case "large": size = .large
            default: break
            }
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 250)
        .frame(minHeight: 300)
    }

    private func registerSettingsClick() {
        let now = Date.now
        if now.timeIntervalSince(lastSettingsClick) > 2 { settingsClickCount = 0 }
        lastSettingsClick = now
        settingsClickCount += 1
        if settingsClickCount >= 10 {
            settingsClickCount = 0
            appState.advancedSettingsUnlocked = true
            // The 10th click jumps straight into the unlocked tab.
            appState.settingsTabRequest = "advanced"
        }
    }
}
