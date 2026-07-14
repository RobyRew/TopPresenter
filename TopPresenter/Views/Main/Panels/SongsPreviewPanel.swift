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
    @AppStorage("song_repeatBracket") private var repeatBracket = "none"
    @AppStorage("song_repeatCount") private var repeatCount = "times"

    /// Pending preview content: a filmstrip slide already carries markers; a bare
    /// verse from the cache is decorated here so the preview matches the output.
    private var pendingPreview: PresentationPreviewCard.PendingContent {
        let title = libraryManager.selectedSong?.title ?? ""
        if !libraryManager.songSlideText.isEmpty {
            let t = libraryManager.songSlideText
            return .init(text: t, reference: title, subtitle: libraryManager.songSlideLabel,
                         lines: richLines(forSlideText: t, in: libraryManager.selectedSongVersion))
        }
        if let v = libraryManager.selectedSongVerse {
            let d = decoratedVerse(v, version: libraryManager.selectedSongVersion, bracket: repeatBracket, countStyle: repeatCount)
            return .init(text: d.text, reference: title, subtitle: v.label, lines: d.lines)
        }
        return .init(text: "", reference: title, subtitle: "")
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .songs)

            Divider()

            // Rendered preview of the slide selected in the filmstrip (falls back to the verse).
            PresentationPreviewCard(formatHint: "song", pendingContent: pendingPreview)
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

            // Song + output quick settings (parity with the Bible presenter sidebar)
            StyleQuickSettings(sections: [.songOptions, .output])

            Spacer(minLength: 0)

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
    @AppStorage("song_repeatBracket") private var repeatBracket = "none"
    @AppStorage("song_repeatCount") private var repeatCount = "times"

    private var isLive: Bool {
        pm.liveContent.isLive && !pm.isBlackScreen
    }

    /// A verse projected with repeat markers (text + chords) for the live path.
    private func decorated(_ verse: SongVerse) -> (text: String, lines: [SongLine]) {
        decoratedVerse(verse, version: libraryManager.selectedSongVersion, bracket: repeatBracket, countStyle: repeatCount)
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
                        .foregroundStyle(appAccent)

                    Text(song.title)
                        .font(.caption.bold())
                        .foregroundStyle(appAccent)
                        .lineLimit(1)

                    Spacer()

                    if let verse = currentVerse {
                        Text(verse.label)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appAccent, in: Capsule())
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

                // Show (explicit) — projects the selected slide/verse
                Button {
                    showCurrent()
                } label: {
                    Label(String(localized: "Show", comment: "Control button"), systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(appAccent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(currentVerse == nil && libraryManager.songSlideText.isEmpty)

                // Hide (explicit) — blanks the output
                Button {
                    pm.clearOutput()
                } label: {
                    Label(String(localized: "Hide", comment: "Control button"), systemImage: "eye.slash.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .disabled(!isLive)

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
                                    let d = decorated(verse)
                                    pm.showSongVerse(
                                        text: d.text,
                                        title: song.title,
                                        verseLabel: verse.label,
                                        slideIndex: sortedVerses.firstIndex(where: { $0.id == verse.id }) ?? 0,
                                        slideCount: sortedVerses.count,
                                        song: song, version: libraryManager.selectedSongVersion,
                                        lines: d.lines
                                    )
                                }
                            } label: {
                                Text(verse.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        currentVerse?.id == verse.id
                                            ? appAccent
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

    private func showCurrent() {
        guard let song = currentSong else { return }
        if !libraryManager.songSlideText.isEmpty {
            pm.showSongVerse(
                text: libraryManager.songSlideText, title: song.title,
                verseLabel: libraryManager.songSlideLabel,
                slideIndex: libraryManager.songSlideIndex, slideCount: libraryManager.songSlideCount,
                song: song, version: libraryManager.selectedSongVersion,
                lines: richLines(forSlideText: libraryManager.songSlideText, in: libraryManager.selectedSongVersion)
            )
        } else if let verse = currentVerse {
            let d = decorated(verse)
            pm.showSongVerse(
                text: d.text, title: song.title, verseLabel: verse.label,
                slideIndex: currentIndex ?? 0, slideCount: sortedVerses.count,
                song: song, version: libraryManager.selectedSongVersion,
                lines: d.lines
            )
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
            let d = decorated(verse)
            pm.showSongVerse(
                text: d.text, title: song.title, verseLabel: verse.label,
                slideIndex: newIdx, slideCount: sortedVerses.count,
                song: song, version: libraryManager.selectedSongVersion,
                lines: d.lines
            )
        }
    }
}
