//
//  SidebarView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI

/// Native sidebar list (content modules) + a SELF-SIZING utility cluster
/// (History · Settings · Account) pinned flush to the bottom. The cluster is
/// NOT a second List — a scroll-disabled List needs a guessed fixed height,
/// which left dead space under the last row. Its rows are hand-styled to
/// match the native ones: accent-tinted icon, quaternary rounded selection,
/// sizes tracking the same row-size option.
struct SidebarView: View {
    @Environment(AppState.self) private var appState
    /// The RESOLVED system row size — on "system" this is what macOS
    /// Appearance actually uses, so the bottom cluster matches the native
    /// rows instead of guessing.
    @Environment(\.sidebarRowSize) private var systemRowSize

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

    /// (text, icon, row) metrics per row-size option — keyed off the RESOLVED
    /// sidebarRowSize so the custom cluster renders the SAME sizes as the
    /// native rows above it ("system" included).
    private var metrics: (text: Double, icon: Double, row: Double) {
        let resolved: SidebarRowSize
        switch sidebarRowSizeRaw {
        case "small": resolved = .small
        case "medium": resolved = .medium
        case "large": resolved = .large
        case "custom": return (clampedCustomSize, clampedCustomSize, clampedCustomSize + 14)
        default: resolved = systemRowSize
        }
        switch resolved {
        case .small: return (11, 11, 24)
        case .large: return (15, 15, 34)
        default: return (13, 13, 28)
        }
    }

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
            .listStyle(.sidebar)
            .transformEnvironment(\.sidebarRowSize) { size in
                switch sidebarRowSizeRaw {
                case "small": size = .small
                case "medium": size = .medium
                case "large", "custom": size = .large
                default: break
                }
            }
            .font(sidebarRowSizeRaw == "custom" ? .system(size: clampedCustomSize) : nil)

            Divider()

            // Bottom-pinned utility cluster — hugs its rows, zero dead space.
            VStack(spacing: 2) {
                ForEach(AppState.SidebarItem.utilityItems) { item in
                    utilityRow(item, isSelected: state.selectedSidebarItem == item)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 250)
        .frame(minHeight: 300)
    }

    /// Styled to read as a native sidebar row: accent icon, primary text,
    /// quaternary rounded-rect selection.
    private func utilityRow(_ item: AppState.SidebarItem, isSelected: Bool) -> some View {
        Button {
            if item == .settings { registerSettingsClick() }
            appState.selectedSidebarItem = item
        } label: {
            HStack(spacing: 7) {
                Image(systemName: item.systemImage)
                    .font(.system(size: metrics.icon))
                    .foregroundStyle(appAccent)
                    .frame(width: metrics.icon + 8)
                Text(item.localizedName)
                    .font(.system(size: metrics.text))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 7)
            .frame(height: metrics.row)
            .background(
                isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
