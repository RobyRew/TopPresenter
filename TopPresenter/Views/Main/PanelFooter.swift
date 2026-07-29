//
//  PanelFooter.swift
//  TopPresenter
//
//  Shared chrome for the preview panels. Lived inside TextBoxLayout.swift (the
//  layout-editor file) even though ALL FIVE panels depend on it, so anyone
//  grepping the panel layer for shared pieces never found it.
//

import SwiftUI

// MARK: - Panel Footer (right bar: theme gallery + Theme Editor button)

/// Footer of every preview panel: a visual THEME GALLERY (thumbnail cards,
/// filtered by the panel's format) and the Theme Editor button.
struct PanelFooter: View {
    /// Presenter format of the hosting panel ("bible"/"song"/"text") — the
    /// gallery shows that format's themes plus universal ("all") themes.
    var format: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            ThemeGalleryView(format: format)
            LayoutEditorButton()
        }
        .padding(.top, 6)
    }
}

/// The Theme Editor button — the one place for boxes, text, backgrounds, output.
struct LayoutEditorButton: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openLayoutEditor, object: nil)
        } label: {
            Label(
                String(localized: "Editor de Teme", comment: "Open theme editor button"),
                systemImage: "paintbrush.pointed.fill"
            )
            .font(.callout.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .help(String(localized: "Deschide Editorul de Teme — casete, text, fundal, ieșire", comment: "Tooltip"))
    }
}
