//
//  SidebarView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI

/// Native sidebar in two stacked Lists sharing ONE selection: content
/// modules on top, the utility cluster (History · Settings · Account)
/// PINNED TO THE BOTTOM (its List is scroll-disabled and hugs three rows).
/// Rows are plain Labels — selection highlight, spacing and typography are
/// the system's and follow the window `.tint`.
struct SidebarView: View {
    @Environment(AppState.self) private var appState

    /// Sidebar icon/row size: "system" follows macOS Settings ▸ Appearance ▸
    /// Sidebar icon size; small/medium/large use the native row sizes;
    /// "custom" applies the slider's font size (clamped 11…20).
    @AppStorage("sidebarRowSizeOption") private var sidebarRowSizeRaw = "system"
    @AppStorage("sidebarCustomIconSize") private var sidebarCustomSize = 14.0

    /// Easter-egg unlock for Settings ▸ Avansat: 10 quick clicks (≤2s apart)
    /// on the Settings row. Session-scoped — AppState re-locks it when the
    /// user leaves the Settings section.
    @State private var settingsClickCount = 0
    @State private var lastSettingsClick = Date.distantPast

    private var clampedCustomSize: Double { min(max(sidebarCustomSize, 11), 20) }

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            List(selection: $state.selectedSidebarItem) {
                Section(String(localized: "Bibliotecă", comment: "Sidebar section")) {
                    ForEach(AppState.SidebarItem.contentItems) { item in
                        Label(item.localizedName, systemImage: item.systemImage)
                            .tag(item)
                    }
                }
            }

            Divider()

            // Bottom-pinned utility cluster — same selection binding, so the
            // native highlight moves between the two lists seamlessly.
            List(selection: $state.selectedSidebarItem) {
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
            .scrollDisabled(true)
            .frame(height: utilityListHeight)
        }
        .listStyle(.sidebar)
        // "system" inherits the macOS sidebar icon size; presets override the
        // native row size; "custom" additionally drives the row font (icons
        // scale with the Label font).
        .transformEnvironment(\.sidebarRowSize) { size in
            switch sidebarRowSizeRaw {
            case "small": size = .small
            case "medium": size = .medium
            case "large", "custom": size = .large
            default: break
            }
        }
        .font(sidebarRowSizeRaw == "custom" ? .system(size: clampedCustomSize) : nil)
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 250)
        .frame(minHeight: 300)
    }

    /// Three rows + list insets — generous enough for every row size so the
    /// scroll-disabled bottom list never clips.
    private var utilityListHeight: CGFloat {
        let row: CGFloat
        switch sidebarRowSizeRaw {
        case "small": row = 28
        case "medium": row = 32
        case "large": row = 38
        case "custom": row = max(28, clampedCustomSize + 18)
        default: row = 36   // system: unknown macOS setting — size for large
        }
        return row * CGFloat(AppState.SidebarItem.utilityItems.count) + 18
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
