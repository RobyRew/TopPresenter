//
//  SongsView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main Songs view with collection management, song navigation, search, and verse display.
struct SongsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AppState.self) private var appState

    @Query(sort: \SongCollection.name) private var collections: [SongCollection]

    @State private var showImportSheet = false
    @State private var showDeleteConfirmation = false
    @State private var collectionToDelete: SongCollection?

    var body: some View {
        VStack(spacing: 0) {
            if collections.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    // Left: Song list
                    SongListPanel()
                        .frame(minWidth: 250, maxWidth: 350)

                    // Right: Song verses
                    SongDetailPanel()
                        .frame(minWidth: 400)
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            SongImportSheet()
        }
        .onChange(of: appState.triggerSongImport) { _, newValue in
            if newValue {
                showImportSheet = true
                appState.triggerSongImport = false
            }
        }
        .alert(
            String(localized: "Delete Collection", comment: "Alert title"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "Cancel", comment: "Alert button"), role: .cancel) { }
            Button(String(localized: "Delete", comment: "Alert button"), role: .destructive) {
                if let collection = collectionToDelete {
                    deleteCollection(collection)
                }
            }
        } message: {
            Text(String(localized: "Are you sure you want to delete \"\(collectionToDelete?.name ?? "")\"? This cannot be undone.", comment: "Alert message"))
        }        .onKeyWindowNotification(.deleteSongCollection) { _ in
            collectionToDelete = libraryManager.selectedSongCollection
            showDeleteConfirmation = true
        }    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(String(localized: "No Song Collections", comment: "Empty state title"))
                .font(.title2)

            Text(String(localized: "Import songs to get started.\nSupported formats: OpenSong XML, OpenLyrics XML", comment: "Empty state message"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showImportSheet = true
            } label: {
                Label(
                    String(localized: "Import Songs", comment: "Button"),
                    systemImage: "plus.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func deleteCollection(_ collection: SongCollection) {
        if libraryManager.selectedSongCollection?.id == collection.id {
            libraryManager.selectedSongCollection = nil
            libraryManager.selectedSong = nil
            libraryManager.selectedSongVerse = nil
        }
        modelContext.delete(collection)
        try? modelContext.save()
    }
}

// MARK: - Song List Panel
struct SongListPanel: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Query(sort: \SongCollection.name) private var collections: [SongCollection]

    private var displayedSongs: [Song] {
        if !libraryManager.songSearchResults.isEmpty {
            // Filter songs from search results
            let songIDs = Set(libraryManager.songSearchResults.map { $0.songID })
            return collections.flatMap { $0.songs }.filter { songIDs.contains($0.id) }
        }

        if let collection = libraryManager.selectedSongCollection {
            return collection.sortedSongs
        }

        return collections.flatMap { $0.sortedSongs }
    }

    var body: some View {
        List(displayedSongs, selection: Binding(
            get: { libraryManager.selectedSong?.id },
            set: { newID in
                if let id = newID,
                   let song = displayedSongs.first(where: { $0.id == id }) {
                    libraryManager.selectSong(song)
                }
            }
        )) { song in
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.body)
                    .lineLimit(1)

                HStack {
                    if !song.author.isEmpty {
                        Text(song.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !song.songNumber.isEmpty {
                        Text("#\(song.songNumber)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .tag(song.id)
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }
}

// MARK: - Song Detail Panel
struct SongDetailPanel: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager

    var body: some View {
        if let song = libraryManager.selectedSong {
            VStack(spacing: 0) {
                // Song header
                HStack {
                    VStack(alignment: .leading) {
                        Text(song.title)
                            .font(.title3.bold())
                        if !song.author.isEmpty {
                            Text(song.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    if !song.key.isEmpty {
                        Text(String(localized: "Key: \(song.key)", comment: "Song info"))
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                // Verse navigation tabs
                SongVerseTabBar(song: song)

                Divider()

                // Current verse display
                if let verse = libraryManager.selectedSongVerse {
                    SongVerseDisplay(verse: verse, songTitle: song.title)
                } else {
                    VStack {
                        Text(String(localized: "Select a verse section", comment: "Placeholder"))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        } else {
            VStack {
                Image(systemName: "music.note")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Select a song to view lyrics", comment: "Placeholder"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Song Verse Tab Bar
struct SongVerseTabBar: View {
    let song: Song

    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(song.sortedVerses) { verse in
                    Button {
                        libraryManager.selectSongVerse(verse)
                    } label: {
                        Text(verse.label)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                libraryManager.selectedSongVerse?.id == verse.id
                                    ? Color.accentColor
                                    : Color.secondary.opacity(0.15),
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .foregroundStyle(
                                libraryManager.selectedSongVerse?.id == verse.id
                                    ? .white
                                    : .primary
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Song Verse Display
struct SongVerseDisplay: View {
    let verse: SongVerse
    let songTitle: String

    @Environment(PresentationManager.self) private var presentationManager
    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(verse.text)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            }

            Divider()

            // Action bar
            HStack {
                Text(verse.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Previous verse
                Button {
                    navigateVerse(direction: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(!canNavigate(direction: -1))

                // Show on screen
                Button {
                    let sorted = libraryManager.selectedSong?.sortedVerses ?? []
                    presentationManager.showSongVerse(
                        text: verse.text,
                        title: songTitle,
                        verseLabel: verse.label,
                        slideIndex: sorted.firstIndex(where: { $0.id == verse.id }) ?? 0,
                        slideCount: max(sorted.count, 1)
                    )
                } label: {
                    Label(
                        String(localized: "Show", comment: "Button"),
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.return, modifiers: [])

                // Next verse
                Button {
                    navigateVerse(direction: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(!canNavigate(direction: 1))
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func canNavigate(direction: Int) -> Bool {
        guard let song = libraryManager.selectedSong else { return false }
        let sorted = song.sortedVerses
        guard let currentIndex = sorted.firstIndex(where: { $0.id == verse.id }) else { return false }
        let newIndex = currentIndex + direction
        return newIndex >= 0 && newIndex < sorted.count
    }

    private func navigateVerse(direction: Int) {
        guard let song = libraryManager.selectedSong else { return }
        let sorted = song.sortedVerses
        guard let currentIndex = sorted.firstIndex(where: { $0.id == verse.id }) else { return }
        let newIndex = currentIndex + direction
        if newIndex >= 0 && newIndex < sorted.count {
            libraryManager.selectSongVerse(sorted[newIndex])
        }
    }
}

// MARK: - Song Import Sheet
struct SongImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var collectionName: String = ""
    @State private var selectedURLs: [URL] = []
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importStatusText = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "Import Songs", comment: "Sheet title"))
                .font(.title2.bold())

            Text(String(localized: "Alege fișiere individuale și/sau directoare — formatul fiecărui fișier este detectat automat (OpenSong, OpenLyrics, PPTX, PPT).", comment: "Import sheet hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Collection name
            TextField(
                String(localized: "Collection Name", comment: "Text field placeholder"),
                text: $collectionName
            )
            .textFieldStyle(.roundedBorder)

            // Selection summary + chooser
            HStack {
                if selectedURLs.isEmpty {
                    Text(String(localized: "Nimic selectat", comment: "Placeholder"))
                        .foregroundStyle(.secondary)
                } else if selectedURLs.count == 1 {
                    Text(selectedURLs[0].lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(String(localized: "\(selectedURLs.count) elemente selectate", comment: "Selection summary"))
                }

                Spacer()

                Button(String(localized: "Alege…", comment: "Button")) {
                    chooseLocation()
                }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if selectedURLs.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(selectedURLs, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
            }

            if isImporting {
                ProgressView(value: importProgress) {
                    Text(importStatusText).font(.caption)
                }
                .progressViewStyle(.linear)
            }

            HStack {
                Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Import", comment: "Button")) { performImport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedURLs.isEmpty || collectionName.isEmpty || isImporting)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        // Files AND directories, multi-select, ANY type — auto-detection
        // decides how each file is parsed.
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Alege cântece (fișiere sau directoare)", comment: "Open panel message")

        if panel.runModal() == .OK {
            selectedURLs = panel.urls
            if collectionName.isEmpty, let first = panel.urls.first {
                collectionName = first.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func performImport() {
        guard !selectedURLs.isEmpty else { return }
        isImporting = true

        Task {
            let result = await ImportService.importSongItems(
                urls: selectedURLs,
                collectionName: collectionName,
                modelContext: modelContext
            ) { progress, status in
                Task { @MainActor in
                    importProgress = progress
                    importStatusText = status
                }
            }

            await MainActor.run {
                isImporting = false
                if result.failures.isEmpty, !result.importedTitles.isEmpty {
                    appState.showSuccess(
                        String(localized: "Import Successful", comment: "Alert title"),
                        message: String(localized: "Au fost importate \(result.importedTitles.count) cântece în \"\(collectionName)\".", comment: "Alert message")
                    )
                    dismiss()
                } else if result.importedTitles.isEmpty {
                    let details = result.failures
                        .prefix(5)
                        .map { "\($0.file): \($0.reason)" }
                        .joined(separator: "\n")
                    appState.showError(
                        String(localized: "Import Failed", comment: "Alert title"),
                        message: details.isEmpty
                            ? String(localized: "Nu a fost găsit niciun cântec.", comment: "Alert message")
                            : details
                    )
                } else {
                    let details = result.failures
                        .prefix(5)
                        .map { "\($0.file): \($0.reason)" }
                        .joined(separator: "\n")
                    appState.showSuccess(
                        String(localized: "Import Parțial", comment: "Alert title"),
                        message: String(localized: "Importate: \(result.importedTitles.count). Eșuate: \(result.failures.count).\n\(details)", comment: "Alert message")
                    )
                    dismiss()
                }
            }
        }
    }
}
