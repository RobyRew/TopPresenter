//
//  KeyboardShortcutsSheet.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import SwiftUI

/// A sheet displaying all available keyboard shortcuts.
struct KeyboardShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(appAccent)
                Text(String(localized: "Keyboard Shortcuts", comment: "Sheet title"))
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // File shortcuts
                    ShortcutSection(
                        title: String(localized: "File", comment: "Shortcut section"),
                        icon: "doc",
                        shortcuts: [
                            ShortcutItem(keys: "⌘ T", description: String(localized: "Filă nouă (tab nou de prezentare)", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ I", description: String(localized: "Import Bible Module", comment: "Shortcut")),
                            ShortcutItem(keys: "⇧ ⌘ I", description: String(localized: "Import Songs", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ E", description: String(localized: "Export Bible Module", comment: "Shortcut")),
                            ShortcutItem(keys: "⇧ ⌘ E", description: String(localized: "Batch Export", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ ,", description: String(localized: "Settings", comment: "Shortcut")),
                            ShortcutItem(keys: "Drag & Drop", description: String(localized: "Drop files onto the window to batch import", comment: "Shortcut")),
                        ]
                    )

                    // Navigation shortcuts
                    ShortcutSection(
                        title: String(localized: "Navigation", comment: "Shortcut section"),
                        icon: "sidebar.left",
                        shortcuts: [
                            ShortcutItem(keys: "⌘ 1", description: String(localized: "Bible", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ 2", description: String(localized: "Songs", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ 3", description: String(localized: "Media", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ 4", description: String(localized: "Schedule", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ 5", description: String(localized: "Custom Slides", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ L", description: String(localized: "Focus Search Field", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ K", description: String(localized: "Quick Search (everything)", comment: "Shortcut")),
                        ]
                    )

                    // Presentation shortcuts
                    ShortcutSection(
                        title: String(localized: "Presentation", comment: "Shortcut section"),
                        icon: "play.rectangle",
                        shortcuts: [
                            ShortcutItem(keys: "⇧ ⌘ P", description: String(localized: "Start / Show Presentation", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ B", description: String(localized: "Toggle Black Screen", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ F", description: String(localized: "Toggle Freeze", comment: "Shortcut")),
                            ShortcutItem(keys: "Esc", description: String(localized: "Clear Output", comment: "Shortcut")),
                        ]
                    )

                    // Verse/Slide navigation shortcuts
                    ShortcutSection(
                        title: String(localized: "Verse & Slide Navigation", comment: "Shortcut section"),
                        icon: "arrow.left.arrow.right",
                        shortcuts: [
                            ShortcutItem(keys: "←", description: String(localized: "Previous Verse / Song Section", comment: "Shortcut")),
                            ShortcutItem(keys: "→", description: String(localized: "Next Verse / Song Section", comment: "Shortcut")),
                            ShortcutItem(keys: "↵ Return", description: String(localized: "Show Selected on Screen", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ Click", description: String(localized: "Select Multiple Verses", comment: "Shortcut")),
                            ShortcutItem(keys: "Double Click", description: String(localized: "Show Verse on Screen", comment: "Shortcut")),
                        ]
                    )

                    // Text & Display shortcuts
                    ShortcutSection(
                        title: String(localized: "Text & Display", comment: "Shortcut section"),
                        icon: "textformat.size",
                        shortcuts: [
                            ShortcutItem(keys: "⌘ +", description: String(localized: "Increase Font Size", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ −", description: String(localized: "Decrease Font Size", comment: "Shortcut")),
                            ShortcutItem(keys: "⌘ 0", description: String(localized: "Reset Font Size", comment: "Shortcut")),
                        ]
                    )

                    // Help shortcuts
                    ShortcutSection(
                        title: String(localized: "Help", comment: "Shortcut section"),
                        icon: "questionmark.circle",
                        shortcuts: [
                            ShortcutItem(keys: "⇧ ⌘ K", description: String(localized: "Show Keyboard Shortcuts", comment: "Shortcut")),
                        ]
                    )
                }
                .padding(24)
            }

            Divider()

            // Footer
            HStack {
                Text(String(localized: "Tip: Most shortcuts are also available from the menu bar.", comment: "Shortcut tip"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Done", comment: "Button")) {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding()
        }
        .frame(width: 480, height: 620)
    }
}

// MARK: - Shortcut Section
private struct ShortcutSection: View {
    let title: String
    let icon: String
    let shortcuts: [ShortcutItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(appAccent)
                    .frame(width: 20)
                Text(title)
                    .font(.headline)
            }

            // Shortcuts list
            VStack(spacing: 0) {
                ForEach(Array(shortcuts.enumerated()), id: \.offset) { index, shortcut in
                    HStack {
                        Text(shortcut.description)
                            .font(.body)
                        Spacer()
                        ShortcutKeysView(keys: shortcut.keys)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Shortcut Keys Display
private struct ShortcutKeysView: View {
    let keys: String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys.split(separator: " ").map(String.init), id: \.self) { key in
                Text(key)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    )
            }
        }
    }
}

// MARK: - Data Model
private struct ShortcutItem {
    let keys: String
    let description: String
}
