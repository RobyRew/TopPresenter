//
//  BiblePreviewPanel.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftUI

/// Right-side panel for Bible: preview card, verse navigation, presentation controls, style settings.
struct BiblePreviewPanel: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AudioPlayerManager.self) private var audioPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .bible)

            Divider()

            // Preview display (16:9 aspect ratio)
            PresentationPreviewCard(isBibleContent: true)
                .padding()

            Divider()

            // Verse / Slide navigation controls
            VerseSlideControlsBar()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            // Presentation controls (Black, Freeze, Open Output)
            PresentationControlsBar()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Audio player (if audio is loaded)
            if !audioPlayerManager.currentFileName.isEmpty {
                AudioControlsView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
            }

            // Operational quick settings (styling lives in the Layout Editor)
            StyleQuickSettings(sections: [.multiVerse, .general])

            Divider()

            // Theme switcher + Layout Editor access
            PanelFooter()
        }
        .background(.background)
    }
}
