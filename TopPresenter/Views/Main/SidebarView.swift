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

    /// Easter-egg unlock for Settings ▸ Avansat: 10 quick clicks on the
    /// Settings row (≤2s apart). Persisted — the tab stays until hidden
    /// again from inside the advanced tab.
    @AppStorage("advancedSettingsUnlocked") private var advancedUnlocked = false
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
                        // simultaneousGesture: the tap COUNTS without stealing
                        // the row's native selection handling.
                        Label(item.localizedName, systemImage: item.systemImage)
                            .tag(item)
                            .simultaneousGesture(TapGesture().onEnded { registerSettingsClick() })
                    } else {
                        Label(item.localizedName, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
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
            advancedUnlocked = true
        }
    }
}
