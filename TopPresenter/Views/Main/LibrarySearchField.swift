//
//  LibrarySearchField.swift
//  TopPresenter
//

import SwiftUI

/// THE search field for a library list — Media, Songs, Schedule, Custom Slides.
///
/// Each module had grown its own: a capsule in Media, a corner-radius-8
/// `.quaternary` box in Songs, a corner-radius-7 `.quaternary.opacity(0.5)` box
/// in the Schedule composer, and nothing at all in Custom Slides. Same control,
/// four shapes, four paddings — the kind of drift nobody decides on, and it made
/// the modules look like separate apps stitched together.
///
/// One component instead, so a change to the search affordance lands everywhere
/// at once and a new module cannot invent a fifth variant.
struct LibrarySearchField: View {
    @Binding var text: String
    var placeholder: String
    /// Swapped for a book glyph where the field takes a Bible reference rather
    /// than a search term — the Schedule composer does this.
    var icon: String = "magnifyingglass"

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                // Escape clears rather than only unfocusing: with a filter
                // applied, an empty-looking list is otherwise a puzzle.
                .onExitCommand { if text.isEmpty { isFocused = false } else { text = "" } }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help(String(localized: "Golește căutarea", comment: "Tooltip"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .overlay {
            // The focus ring is drawn here, on the capsule, because the plain
            // text field inside has none of its own — without it there is no way
            // to tell the field has the keyboard.
            Capsule().strokeBorder(isFocused ? appHighlight.opacity(0.85) : .clear, lineWidth: 1.5)
        }
        .animation(.easeOut(duration: 0.12), value: isFocused)
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}
