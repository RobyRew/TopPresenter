//
//  SidebarView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettings

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

            // Pinned utility group at the bottom: History · Settings · Account.
            VStack(spacing: 2) {
                ForEach(AppState.SidebarItem.utilityItems) { item in
                    utilityRow(item.localizedName, systemImage: item.systemImage,
                               isSelected: state.selectedSidebarItem == item) {
                        state.selectedSidebarItem = item
                    }
                }
                utilityRow(String(localized: "Settings", comment: "Sidebar item"),
                           systemImage: "gearshape", isSelected: false) {
                    openSettings()
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
        .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 250)
        .frame(minHeight: 300)
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
