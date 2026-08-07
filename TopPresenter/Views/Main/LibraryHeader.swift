//
//  LibraryHeader.swift
//  TopPresenter
//
//  THE top section of every library list — Songs, Media, Schedule, Custom
//  Slides. Same anatomy, same paddings, same controls, in the same places.
//
//  They had drifted into four different headers: Songs led with a search field
//  then a stock `Picker` (the only unstyled AppKit control left in a row of
//  custom chips, which is exactly why it looked pasted in), Media led with
//  search + Add then its own chip row, and Schedule and Custom Slides led with a
//  title and a bare "+". Only Songs offered a grid; only three of the four had
//  search at all. Every module reinvented the spacing.
//
//  One component fixes the shape for all of them and makes a fifth module cheap.
//

import SwiftUI

// MARK: - View mode

/// List or grid, per module. Raw values are persisted in `@AppStorage`.
enum LibraryViewMode: String, CaseIterable, Identifiable {
    case list, grid

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }

    var label: String {
        switch self {
        case .list: return String(localized: "Listă", comment: "View mode")
        case .grid: return String(localized: "Grilă", comment: "View mode")
        }
    }
}

// MARK: - Chip

/// The one chip look: filters, sort keys, kind pickers, dropdown menus.
///
/// Songs drew its sort chips with `appAccent.opacity(0.2)` behind accent text
/// while Media drew its kind chips with a solid `appHighlight` behind white —
/// two answers to "which chip is on?" in adjacent modules. This is the answer.
struct LibraryChipLabel: View {
    var label: String
    var icon: String? = nil
    var count: Int? = nil
    var isActive: Bool = false
    /// Menus get a disclosure caret so they read as openable, not as a toggle.
    var showsChevron: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(label)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            if let count {
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium).monospacedDigit())
                    .opacity(0.65)
            }
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .opacity(0.7)
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            isActive ? AnyShapeStyle(appHighlight) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: Capsule()
        )
        .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
        .contentShape(Capsule())
    }
}

struct LibraryChip: View {
    var label: String
    var icon: String? = nil
    var count: Int? = nil
    var isActive: Bool = false
    /// Dimmed but still clickable — how you confirm a kind has nothing in it.
    var isEmpty: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LibraryChipLabel(label: label, icon: icon, count: count, isActive: isActive)
        }
        .buttonStyle(.plain)
        .opacity(isEmpty && !isActive ? 0.45 : 1)
    }
}

// MARK: - View-mode toggle

struct LibraryViewModeToggle: View {
    @Binding var mode: LibraryViewMode

    var body: some View {
        HStack(spacing: 1) {
            ForEach(LibraryViewMode.allCases) { m in
                Button { mode = m } label: {
                    Image(systemName: m.systemImage)
                        .font(.system(size: 10, weight: .medium))
                        .frame(width: 22, height: 18)
                        .background(
                            mode == m ? AnyShapeStyle(appHighlight) : AnyShapeStyle(Color.clear),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                        .foregroundStyle(mode == m ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(m.label)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// MARK: - Header

/// Row 1: search, then the module's own actions (Add, Import…).
/// Row 2: the module's filter chips, then the count, then list/grid.
///
/// Both rows are optional in content but fixed in position, so the eye finds
/// the same control in the same place in every module.
struct LibraryHeader<Filters: View, Actions: View>: View {
    @Binding var query: String
    var placeholder: String
    @Binding var viewMode: LibraryViewMode
    /// e.g. "11 cântece". Nil hides the label rather than showing "0".
    var count: String? = nil
    var showsViewToggle: Bool = true
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var filters: () -> Filters

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                LibrarySearchField(text: $query, placeholder: placeholder)
                actions()
            }

            HStack(spacing: 8) {
                // Chips scroll rather than wrap: a header that changes height as
                // filters appear makes the list below jump.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) { filters() }
                        .padding(.vertical, 1)
                }

                Spacer(minLength: 0)

                if let count {
                    Text(count)
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                }

                if showsViewToggle {
                    LibraryViewModeToggle(mode: $viewMode)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

extension LibraryHeader where Filters == EmptyView {
    init(query: Binding<String>, placeholder: String, viewMode: Binding<LibraryViewMode>,
         count: String? = nil, showsViewToggle: Bool = true,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.init(query: query, placeholder: placeholder, viewMode: viewMode,
                  count: count, showsViewToggle: showsViewToggle,
                  actions: actions, filters: { EmptyView() })
    }
}

extension LibraryHeader where Actions == EmptyView, Filters == EmptyView {
    init(query: Binding<String>, placeholder: String, viewMode: Binding<LibraryViewMode>,
         count: String? = nil, showsViewToggle: Bool = true) {
        self.init(query: query, placeholder: placeholder, viewMode: viewMode,
                  count: count, showsViewToggle: showsViewToggle,
                  actions: { EmptyView() }, filters: { EmptyView() })
    }
}

/// The small circular icon button the headers use for Add / Import.
///
/// `.controlSize(.small)` on a bordered Button gave each module a slightly
/// different height depending on its label, which is what made the rows fail to
/// line up between tabs.
struct LibraryHeaderButton: View {
    var systemImage: String
    var help: String
    var prominent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(
                    prominent ? AnyShapeStyle(appHighlight) : AnyShapeStyle(.quaternary.opacity(0.5)),
                    in: Circle()
                )
                .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
