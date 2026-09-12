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
        // Nothing picked yet: show the song's FIRST slide, split the same way
        // the projector will split it. Falling back to a raw `SongVerse` showed
        // a whole unsplit section, so the preview disagreed with the output.
        if let song = libraryManager.selectedSong,
           let first = SongSlideCache.slides(
               for: song,
               version: libraryManager.selectedSongVersion ?? song.activeVersion).first {
            return .init(text: first.text, reference: title, subtitle: first.label, lines: first.lines)
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
/// Navigation for a song's SLIDES — the same slides the filmstrip and the
/// projector use, split at `song_maxLinesPerSlide`.
///
/// This used to step `Song.sortedVerses`, one row per whole section. That is
/// what made the lines-per-slide setting look broken: it split the filmstrip
/// but not the thing the operator actually drives during a service.
struct SongVerseControlsBar: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager

    private var isLive: Bool {
        pm.liveContent.isLive && !pm.isBlackScreen
    }

    private var currentSong: Song? { libraryManager.selectedSong }

    private var slides: [SongSlide] {
        guard let song = currentSong else { return [] }
        return SongSlideCache.slides(for: song,
                                     version: libraryManager.selectedSongVersion ?? song.activeVersion)
    }

    /// Which slide is selected. Matched on content first — an edit can change
    /// how many slides a section makes, so a stored index alone can drift onto
    /// the wrong one — then falling back to the stored index, clamped.
    private var currentIndex: Int {
        let all = slides
        guard !all.isEmpty else { return -1 }
        if !libraryManager.songSlideText.isEmpty,
           let i = all.firstIndex(where: { $0.text == libraryManager.songSlideText
                                        && $0.label == libraryManager.songSlideLabel }) {
            return i
        }
        return min(max(libraryManager.songSlideIndex, 0), all.count - 1)
    }

    private var galleryItems: [SlideGalleryStrip.Item] {
        slides.map { SlideGalleryStrip.Item(id: $0.id, label: $0.label, text: $0.text) }
    }

    /// Select a slide, and follow it live when the output is already showing
    /// this song. `present` forces it live regardless.
    private func show(_ index: Int, present: Bool) {
        let all = slides
        guard all.indices.contains(index), let song = currentSong else { return }
        let slide = all[index]
        libraryManager.selectSongSlide(text: slide.text, label: slide.label,
                                       index: index, count: slide.total)
        guard present || isLive else { return }
        pm.showSongVerse(
            text: slide.text, title: song.title, verseLabel: slide.label,
            slideIndex: index, slideCount: slide.total,
            song: song, version: libraryManager.selectedSongVersion,
            sectionType: slide.type, lines: slide.lines)
    }

    var body: some View {
        VStack(spacing: 6) {
            // What the next press will put on screen. The preview card above
            // shows one slide, so without this the operator could see what is
            // live but not what comes after it.
            SlideGalleryStrip(items: galleryItems,
                              currentIndex: currentIndex,
                              onSelect: { show($0, present: false) },
                              onPresent: { show($0, present: true) })

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

                    let all = slides
                    if all.indices.contains(currentIndex) {
                        Text(all[currentIndex].label)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appAccent, in: Capsule())
                        // How far through the song this is — the operator's cue
                        // that a long verse is now two presses, not one.
                        Text("\(currentIndex + 1)/\(all.count)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Main controls row
            HStack(spacing: 8) {
                Button {
                    navigate(direction: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigate(direction: -1))
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button {
                    show(currentIndex, present: true)
                } label: {
                    Label(String(localized: "Show", comment: "Control button"), systemImage: "play.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(appAccent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(currentIndex < 0)

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

                Button {
                    navigate(direction: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!canNavigate(direction: 1))
                .keyboardShortcut(.rightArrow, modifiers: [])
            }

            // Quick-jump tabs, one per slide
            let all = slides
            if all.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(Array(all.enumerated()), id: \.element.id) { idx, slide in
                            Button { show(idx, present: isLive) } label: {
                                Text(slide.label)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(idx == currentIndex ? appAccent
                                                                    : Color.secondary.opacity(0.15),
                                                in: RoundedRectangle(cornerRadius: 5))
                                    .foregroundStyle(idx == currentIndex ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func canNavigate(direction: Int) -> Bool {
        let idx = currentIndex
        guard idx >= 0 else { return false }
        let next = idx + direction
        return next >= 0 && next < slides.count
    }

    private func navigate(direction: Int) {
        let idx = currentIndex
        guard idx >= 0 else { return }
        show(idx + direction, present: false)
    }
}
