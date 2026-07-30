import SwiftUI

/// One row of the Theme Editor's casete list.
///
/// This was inline in `LayoutEditorSheet`, so its per-box reads — visibility,
/// label, source tooltip — were part of the sheet's body. That subscribed the
/// entire editor to EVERY box: moving one box invalidated the whole sheet, and
/// rebuilt every row's localized label and tooltip along with it.
///
/// The context menu and the reorder drop target stay on the caller. Their
/// closures are actions rather than reads, so they cost nothing per render, and
/// leaving them alone keeps the drag-to-reorder and right-click behaviour
/// exactly where it was.
struct EditorBoxListRow: View {
    @Environment(PresentationManager.self) private var pm

    let identity: BoxIdentity
    let isSelected: Bool
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let isVisible = pm.isBoxVisible(identity)

        // The LEADING area selects + drags; the eye/trash buttons live outside
        // the drag/tap surface so their clicks are never swallowed.
        let leading = HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .help(String(localized: "Trage pentru a reordona (primul = deasupra pe ecran)", comment: "Tooltip"))
            BoxColorSwatch(identity: identity)
            Text(boxLabel(for: identity, pm: pm))
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .draggable(boxToken(for: identity))

        return HStack(spacing: 6) {
            leading

            Button {
                pm.toggleBoxVisibility(identity)
            } label: {
                // The glyph already switched to eye.slash when hidden, but the row
                // dims to 0.55 and washed it out — the state read as "grey", not as
                // "crossed out". So the crossed eye is drawn bold, tinted, and at
                // full strength, immune to the row's dimming.
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.caption2.weight(isVisible ? .regular : .bold))
                    .foregroundStyle(isVisible ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                    .opacity(isVisible ? 1.0 : 1.0 / 0.55)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(isVisible
                  ? String(localized: "Ascunde caseta", comment: "Tooltip")
                  : String(localized: "Caseta este ascunsă — apasă pentru a o afișa", comment: "Tooltip"))

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help({
                if case .section = identity {
                    return String(localized: "Elimină caseta (o poți reactiva cu ochiul)", comment: "Tooltip")
                }
                return String(localized: "Șterge caseta", comment: "Tooltip")
            }())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? appHighlight.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .help(boxSourceDescription(for: identity, pm: pm))
        .opacity(isVisible ? 1.0 : 0.55)
    }
}
