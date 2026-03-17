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
            // Top bar: collection selector + search
            SongsTopBar(
                showImportSheet: $showImportSheet,
                showDeleteConfirmation: $showDeleteConfirmation,
                collectionToDelete: $collectionToDelete
            )

            Divider()

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
        }
    }

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

// MARK: - Songs Top Bar
struct SongsTopBar: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Query(sort: \SongCollection.name) private var collections: [SongCollection]

    @Binding var showImportSheet: Bool
    @Binding var showDeleteConfirmation: Bool
    @Binding var collectionToDelete: SongCollection?

    var body: some View {
        @Bindable var library = libraryManager

        HStack(spacing: 12) {
            // Collection selector
            if !collections.isEmpty {
                Picker(
                    String(localized: "Collection:", comment: "Picker label"),
                    selection: Binding(
                        get: { libraryManager.selectedSongCollection?.id },
                        set: { newID in
                            if let id = newID, let coll = collections.first(where: { $0.id == id }) {
                                libraryManager.selectCollection(coll)
                            }
                        }
                    )
                ) {
                    Text(String(localized: "All Collections", comment: "Picker option"))
                        .tag(nil as UUID?)
                    ForEach(collections) { coll in
                        Text(coll.name).tag(coll.id as UUID?)
                    }
                }
                .frame(maxWidth: 250)
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(
                    String(localized: "Search songs by title or lyrics...", comment: "Search placeholder"),
                    text: $library.songSearchQuery
                )
                .textFieldStyle(.plain)
                .onSubmit {
                    libraryManager.searchSongs(
                        query: libraryManager.songSearchQuery,
                        in: collections
                    )
                }

                if !libraryManager.songSearchQuery.isEmpty {
                    Button {
                        libraryManager.songSearchQuery = ""
                        libraryManager.songSearchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            Button {
                showImportSheet = true
            } label: {
                Label(String(localized: "Import", comment: "Button"), systemImage: "square.and.arrow.down")
            }
            .controlSize(.small)

            if libraryManager.selectedSongCollection != nil {
                Button {
                    collectionToDelete = libraryManager.selectedSongCollection
                    showDeleteConfirmation = true
                } label: {
                    Label(String(localized: "Delete", comment: "Button"), systemImage: "trash")
                }
                .controlSize(.small)
                .foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                    presentationManager.showSongVerse(
                        text: verse.text,
                        title: songTitle,
                        verseLabel: verse.label
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

    @State private var selectedFormat: SupportedSongFormat = .openSongXML
    @State private var importMode: SongImportMode = .directory
    @State private var collectionName: String = ""
    @State private var selectedURL: URL?
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importStatusText = ""

    enum SongImportMode: String, CaseIterable {
        case singleFile = "Single File"
        case directory = "Directory (Multiple Songs)"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "Import Songs", comment: "Sheet title"))
                .font(.title2.bold())

            // Format picker
            Picker(String(localized: "Format:", comment: "Picker label"), selection: $selectedFormat) {
                ForEach(SupportedSongFormat.allCases) { format in
                    Text(format.displayName).tag(format)
                }
            }
            .pickerStyle(.segmented)

            // Import mode
            Picker(String(localized: "Import:", comment: "Picker label"), selection: $importMode) {
                ForEach(SongImportMode.allCases, id: \.rawValue) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            // Collection name
            TextField(
                String(localized: "Collection Name", comment: "Text field placeholder"),
                text: $collectionName
            )
            .textFieldStyle(.roundedBorder)

            // File/Directory selector
            HStack {
                if let url = selectedURL {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(importMode == .directory
                         ? String(localized: "No directory selected", comment: "Placeholder")
                         : String(localized: "No file selected", comment: "Placeholder"))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(importMode == .directory
                       ? String(localized: "Choose Directory...", comment: "Button")
                       : String(localized: "Choose File...", comment: "Button")
                ) {
                    chooseLocation()
                }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

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
                    .disabled(selectedURL == nil || collectionName.isEmpty || isImporting)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        if importMode == .directory {
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
        } else {
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.allowedContentTypes = [UTType(filenameExtension: "xml") ?? .xml]
        }
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            selectedURL = panel.url
            if collectionName.isEmpty, let url = panel.url {
                collectionName = url.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func performImport() {
        guard let url = selectedURL else { return }
        isImporting = true

        Task {
            do {
                let collection: SongCollection
                if importMode == .directory {
                    collection = try await ImportService.importSongsFromDirectory(
                        directoryURL: url,
                        format: selectedFormat,
                        collectionName: collectionName,
                        modelContext: modelContext
                    ) { progress, status in
                        Task { @MainActor in
                            importProgress = progress
                            importStatusText = status
                        }
                    }
                } else {
                    collection = try await ImportService.importSingleSongFile(
                        fileURL: url,
                        format: selectedFormat,
                        collectionName: collectionName,
                        modelContext: modelContext
                    )
                }

                await MainActor.run {
                    isImporting = false
                    appState.showSuccess(
                        String(localized: "Import Successful", comment: "Alert title"),
                        message: String(localized: "Imported \(collection.songs.count) songs into \"\(collection.name)\".", comment: "Alert message")
                    )
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isImporting = false
                    appState.showError(
                        String(localized: "Import Failed", comment: "Alert title"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }
}
