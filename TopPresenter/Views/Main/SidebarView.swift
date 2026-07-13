//
//  SidebarView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI

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

        VStack(spacing: 0) {
            // Content sections — the main navigation.
            List(AppState.SidebarItem.contentItems, selection: $state.selectedSidebarItem) { item in
                Label(item.localizedName, systemImage: item.systemImage)
                    .tag(item)
            }
            .listStyle(.sidebar)

            Spacer(minLength: 0)

            Divider()

            // Pinned utility group at the bottom: History · Settings · Account —
            // all in-app destinations (Settings included, no separate window).
            VStack(spacing: 2) {
                ForEach(AppState.SidebarItem.utilityItems) { item in
                    utilityRow(item.localizedName, systemImage: item.systemImage,
                               isSelected: state.selectedSidebarItem == item) {
                        if item == .settings { registerSettingsClick() }
                        state.selectedSidebarItem = item
                    }
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
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
            advancedUnlocked = true
        }
    }

    private func utilityRow(_ title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
    }
}
