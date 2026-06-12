//
//  SongsPreviewPanel.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftUI

/// Right-side panel for Songs: preview card, verse section navigation, presentation controls, style settings.
struct SongsPreviewPanel: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AudioPlayerManager.self) private var audioPlayerManager

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .songs)

            Divider()

            // Preview display — previews the selected song verse before it goes live
            PresentationPreviewCard(formatHint: "song", pendingContent: .init(
                text: libraryManager.selectedSongVerse?.text ?? "",
                reference: libraryManager.selectedSong?.title ?? "",
                subtitle: libraryManager.selectedSongVerse?.label ?? ""
            ))
            .padding()

            Divider()

            // Song verse navigation
            SongVerseControlsBar()
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

            Spacer()

            Divider()

            // Theme switcher + Layout Editor access
            PanelFooter(format: "song")
        }
        .background(.background)
    }
}

// MARK: - Song Verse Controls Bar
/// Navigation for song verse sections (chorus, verse 1, verse 2, etc.)
struct SongVerseControlsBar: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager

    private var isLive: Bool {
        pm.liveContent.isLive && !pm.isBlackScreen
    }

    private var currentSong: Song? { libraryManager.selectedSong }
    private var currentVerse: SongVerse? { libraryManager.selectedSongVerse }

    private var sortedVerses: [SongVerse] {
        currentSong?.sortedVerses ?? []
    }

    private var currentIndex: Int? {
        guard let verse = currentVerse else { return nil }
        return sortedVerses.firstIndex(where: { $0.id == verse.id })
    }

    var body: some View {
        VStack(spacing: 6) {
            // Current song + verse info
            if let song = currentSong {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)

                    Text(song.title)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)

                    Spacer()

                    if let verse = currentVerse {
                        Text(verse.label)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
            }

            // Main controls row
            HStack(spacing: 8) {
                // ← Previous verse section
                Button {
                    navigateVerse(direction: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigate(direction: -1))
                .keyboardShortcut(.leftArrow, modifiers: [])

                // Show / Hide toggle
                Button {
                    if isLive {
                        pm.clearOutput()
                    } else if let verse = currentVerse, let song = currentSong {
                        pm.showSongVerse(
                            text: verse.text,
                            title: song.title,
                            verseLabel: verse.label,
                            slideIndex: currentIndex ?? 0,
                            slideCount: sortedVerses.count
                        )
                    }
                } label: {
                    Label(
                        isLive
                            ? String(localized: "Hide", comment: "Control button")
                            : String(localized: "Show", comment: "Control button"),
                        systemImage: isLive ? "eye.slash.fill" : "play.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(isLive ? .orange : .accentColor)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!isLive && currentVerse == nil)

                // → Next verse section
                Button {
                    navigateVerse(direction: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigate(direction: 1))
                .keyboardShortcut(.rightArrow, modifiers: [])
            }

            // Verse section quick-jump tabs
            if sortedVerses.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(sortedVerses) { verse in
                            Button {
                                libraryManager.selectSongVerse(verse)
                                if isLive, let song = currentSong {
                                    pm.showSongVerse(
                                        text: verse.text,
                                        title: song.title,
                                        verseLabel: verse.label,
                                        slideIndex: sortedVerses.firstIndex(where: { $0.id == verse.id }) ?? 0,
                                        slideCount: sortedVerses.count
                                    )
                                }
                            } label: {
                                Text(verse.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        currentVerse?.id == verse.id
                                            ? Color.accentColor
                                            : Color.secondary.opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 5)
                                    )
                                    .foregroundStyle(
                                        currentVerse?.id == verse.id ? .white : .primary
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func canNavigate(direction: Int) -> Bool {
        guard let idx = currentIndex else { return false }
        let newIdx = idx + direction
        return newIdx >= 0 && newIdx < sortedVerses.count
    }

    private func navigateVerse(direction: Int) {
        let wasLive = isLive
        guard let idx = currentIndex else { return }
        let newIdx = idx + direction
        guard newIdx >= 0, newIdx < sortedVerses.count else { return }
        let verse = sortedVerses[newIdx]
        libraryManager.selectSongVerse(verse)
        if wasLive, let song = currentSong {
            pm.showSongVerse(
                text: verse.text, title: song.title, verseLabel: verse.label,
                slideIndex: newIdx, slideCount: sortedVerses.count
            )
        }
    }
}
