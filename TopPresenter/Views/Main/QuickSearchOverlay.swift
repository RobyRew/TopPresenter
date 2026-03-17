//
//  QuickSearchOverlay.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import SwiftUI
import SwiftData

/// Unified search result type for the quick search overlay.
enum QuickSearchResultType: String {
    case bibleVerse = "Bible Verse"
    case song = "Song"
    case book = "Book"
    case module = "Module"
    case collection = "Collection"
}

struct QuickSearchResult: Identifiable, Hashable {
    let id = UUID()
    let type: QuickSearchResultType
    let title: String
    let subtitle: String
    let detail: String
    let icon: String
    let iconColor: Color

    // For navigation
    let moduleID: UUID?
    let bookID: UUID?
    let chapterID: UUID?
    let verseID: UUID?
    let songID: UUID?
    let collectionID: UUID?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: QuickSearchResult, rhs: QuickSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

/// ⌘K Quick Search — a Spotlight-like overlay for searching everything.
struct QuickSearchOverlay: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AppState.self) private var appState

    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var results: [QuickSearchResult] = []
    @State private var selectedIndex: Int = 0
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool

    private let debounceDelay: Duration = .milliseconds(150)
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dismiss()
                }

            // Search panel
            VStack(spacing: 0) {
                searchField
                Divider()
                resultsList
            }
            .frame(width: 600)
            .frame(maxHeight: 460)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            .padding(.top, 80)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            isSearchFieldFocused = true
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(.downArrow) {
            if !results.isEmpty {
                selectedIndex = min(selectedIndex + 1, results.count - 1)
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(.return) {
            if !results.isEmpty, selectedIndex < results.count {
                activateResult(results[selectedIndex])
            }
            return .handled
        }
    }

    // MARK: - Search Field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)

            TextField(
                String(localized: "Search Bible verses, songs, books...", comment: "Quick search placeholder"),
                text: $query
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($isSearchFieldFocused)
            .onChange(of: query) { _, newValue in
                performSearch(newValue)
            }

            if isSearching {
                ProgressView()
                    .controlSize(.small)
            }

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Shortcut hint
            Text("esc")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(16)
    }

    // MARK: - Results List

    private var resultsList: some View {
        Group {
            if query.isEmpty {
                emptyHint
            } else if results.isEmpty && !isSearching {
                noResults
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                                QuickSearchRow(
                                    result: result,
                                    isSelected: index == selectedIndex
                                )
                                .id(index)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = index
                                    activateResult(result)
                                }
                                .onHover { hovering in
                                    if hovering {
                                        selectedIndex = index
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .onChange(of: selectedIndex) { _, newIndex in
                        withAnimation(.easeInOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var emptyHint: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                hintTag(icon: "book.fill", text: String(localized: "Bible", comment: "Search hint"))
                hintTag(icon: "music.note", text: String(localized: "Songs", comment: "Search hint"))
                hintTag(icon: "text.magnifyingglass", text: String(localized: "Verses", comment: "Search hint"))
            }
            Text(String(localized: "Type to search across all your content", comment: "Quick search hint"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    private func hintTag(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: Capsule())
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title)
                .foregroundStyle(.tertiary)
            Text(String(localized: "No results for \"\(query)\"", comment: "No search results"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }

    // MARK: - Search Logic

    private func performSearch(_ text: String) {
        searchTask?.cancel()
        selectedIndex = 0

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            // Small debounce
            try? await Task.sleep(for: debounceDelay)
            guard !Task.isCancelled else { return }

            let searchResults = search(query: text)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                results = searchResults
                isSearching = false
                selectedIndex = 0
            }
        }
    }

    @MainActor
    private func search(query: String) -> [QuickSearchResult] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var allResults: [QuickSearchResult] = []

        // 0. Try reference search first (e.g. "Matei 23", "Geneza 1:3", "John 3:16-18")
        let moduleDescriptor = FetchDescriptor<BibleModule>()
        if let modules = try? modelContext.fetch(moduleDescriptor) {
            let refResults = searchByReference(q, in: modules)
            allResults.append(contentsOf: refResults)

            // 1. Search Bible Modules by name
            for module in modules where module.name.lowercased().contains(q) || module.abbreviation.lowercased().contains(q) {
                allResults.append(QuickSearchResult(
                    type: .module,
                    title: module.name,
                    subtitle: module.abbreviation,
                    detail: "\(module.books.count) books • \(module.language)",
                    icon: "book.closed.fill",
                    iconColor: .blue,
                    moduleID: module.id,
                    bookID: nil, chapterID: nil, verseID: nil, songID: nil, collectionID: nil
                ))
            }

            // 2. Search Books by name
            for module in modules {
                for book in module.books where book.name.lowercased().contains(q) {
                    allResults.append(QuickSearchResult(
                        type: .book,
                        title: book.name,
                        subtitle: module.abbreviation.isEmpty ? module.name : module.abbreviation,
                        detail: "\(book.chapters.count) chapters • \(book.testament)",
                        icon: "text.book.closed",
                        iconColor: book.testament == "OT" ? .brown : .indigo,
                        moduleID: module.id,
                        bookID: book.id, chapterID: nil, verseID: nil, songID: nil, collectionID: nil
                    ))
                }
            }

            // 3. Search Verses by text (limit to keep it fast) — only if no reference results
            if refResults.isEmpty {
                let verseDescriptor = FetchDescriptor<BibleVerse>()
                if let verses = try? modelContext.fetch(verseDescriptor) {
                    var verseCount = 0
                    for verse in verses {
                        guard verseCount < 30 else { break }
                        if verse.text.lowercased().contains(q) {
                            allResults.append(QuickSearchResult(
                                type: .bibleVerse,
                                title: verse.fullReference,
                                subtitle: String(verse.text.prefix(120)),
                                detail: "",
                                icon: "text.quote",
                                iconColor: .green,
                                moduleID: nil,
                                bookID: verse.chapter?.book?.id,
                                chapterID: verse.chapter?.id,
                                verseID: verse.id,
                                songID: nil, collectionID: nil
                            ))
                            verseCount += 1
                        }
                    }
                }
            }
        }

        // 4. Search Song Collections
        let collectionDescriptor = FetchDescriptor<SongCollection>()
        if let collections = try? modelContext.fetch(collectionDescriptor) {
            for collection in collections where collection.name.lowercased().contains(q) {
                allResults.append(QuickSearchResult(
                    type: .collection,
                    title: collection.name,
                    subtitle: "\(collection.songs.count) songs",
                    detail: "",
                    icon: "folder.fill",
                    iconColor: .orange,
                    moduleID: nil, bookID: nil, chapterID: nil, verseID: nil,
                    songID: nil, collectionID: collection.id
                ))
            }
        }

        // 5. Search Songs by title and author
        let songDescriptor = FetchDescriptor<Song>()
        if let songs = try? modelContext.fetch(songDescriptor) {
            var songCount = 0
            for song in songs {
                guard songCount < 30 else { break }
                if song.title.lowercased().contains(q) || song.author.lowercased().contains(q) {
                    allResults.append(QuickSearchResult(
                        type: .song,
                        title: song.title,
                        subtitle: song.author.isEmpty ? (song.collection?.name ?? "") : song.author,
                        detail: song.collection?.name ?? "",
                        icon: "music.note",
                        iconColor: .purple,
                        moduleID: nil, bookID: nil, chapterID: nil, verseID: nil,
                        songID: song.id, collectionID: song.collection?.id
                    ))
                    songCount += 1
                }
            }

            // 6. Search Song Verses by text
            var songVerseCount = 0
            for song in songs {
                guard songVerseCount < 20 else { break }
                for verse in song.verses where verse.text.lowercased().contains(q) {
                    allResults.append(QuickSearchResult(
                        type: .song,
                        title: "\(song.title) — \(verse.label)",
                        subtitle: String(verse.text.prefix(100)),
                        detail: song.collection?.name ?? "",
                        icon: "music.note.list",
                        iconColor: .purple,
                        moduleID: nil, bookID: nil, chapterID: nil, verseID: nil,
                        songID: song.id, collectionID: song.collection?.id
                    ))
                    songVerseCount += 1
                }
            }
        }

        return allResults
    }

    /// Parses Bible reference queries like "Matei 23", "Geneza 1:3", "John 3:16-18"
    /// and returns matching results from all modules.
    private func searchByReference(_ query: String, in modules: [BibleModule]) -> [QuickSearchResult] {
        var results: [QuickSearchResult] = []

        // Pattern 1: "BookName Chapter:VerseStart-VerseEnd"
        // Pattern 2: "BookName Chapter:Verse"
        // Pattern 3: "BookName Chapter" (no verse — show all verses in chapter)
        let fullPattern = #"^(\d?\s?[A-Za-zÀ-ÿ\s]+?)\s+(\d+)(?::(\d+)(?:-(\d+))?)?$"#
        guard let regex = try? NSRegularExpression(pattern: fullPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) else {
            return results
        }

        guard let bookRange = Range(match.range(at: 1), in: query),
              let chapterRange = Range(match.range(at: 2), in: query) else {
            return results
        }

        let bookName = String(query[bookRange]).trimmingCharacters(in: .whitespaces).lowercased()
        let chapterNum = Int(query[chapterRange]) ?? 0

        var verseStart: Int? = nil
        var verseEnd: Int? = nil

        if let verseStartRange = Range(match.range(at: 3), in: query) {
            verseStart = Int(query[verseStartRange])
            if let verseEndRange = Range(match.range(at: 4), in: query) {
                verseEnd = Int(query[verseEndRange])
            } else {
                verseEnd = verseStart
            }
        }

        for module in modules {
            for book in module.books where book.name.lowercased().hasPrefix(bookName) {
                for chapter in book.chapters where chapter.chapterNumber == chapterNum {
                    if let vStart = verseStart, let vEnd = verseEnd {
                        // Specific verse(s)
                        for verse in chapter.sortedVerses where verse.verseNumber >= vStart && verse.verseNumber <= vEnd {
                            results.append(QuickSearchResult(
                                type: .bibleVerse,
                                title: "\(book.name) \(chapter.chapterNumber):\(verse.verseNumber)",
                                subtitle: String(verse.text.prefix(120)),
                                detail: module.abbreviation.isEmpty ? module.name : module.abbreviation,
                                icon: "text.quote",
                                iconColor: .green,
                                moduleID: module.id,
                                bookID: book.id,
                                chapterID: chapter.id,
                                verseID: verse.id,
                                songID: nil, collectionID: nil
                            ))
                        }
                    } else {
                        // No verse specified — show chapter as a result, then first few verses
                        results.append(QuickSearchResult(
                            type: .book,
                            title: "\(book.name) \(chapter.chapterNumber)",
                            subtitle: "\(chapter.verses.count) verses",
                            detail: module.abbreviation.isEmpty ? module.name : module.abbreviation,
                            icon: "text.book.closed",
                            iconColor: book.testament == "OT" ? .brown : .indigo,
                            moduleID: module.id,
                            bookID: book.id,
                            chapterID: chapter.id,
                            verseID: nil, songID: nil, collectionID: nil
                        ))

                        // Also show first 10 verses as quick results
                        for verse in chapter.sortedVerses.prefix(10) {
                            results.append(QuickSearchResult(
                                type: .bibleVerse,
                                title: "\(book.name) \(chapter.chapterNumber):\(verse.verseNumber)",
                                subtitle: String(verse.text.prefix(100)),
                                detail: module.abbreviation.isEmpty ? module.name : module.abbreviation,
                                icon: "text.quote",
                                iconColor: .green,
                                moduleID: module.id,
                                bookID: book.id,
                                chapterID: chapter.id,
                                verseID: verse.id,
                                songID: nil, collectionID: nil
                            ))
                        }
                    }
                }
            }
        }

        return results
    }

    // MARK: - Actions

    private func activateResult(_ result: QuickSearchResult) {
        switch result.type {
        case .module:
            appState.selectedSidebarItem = .bible
            if let moduleID = result.moduleID {
                let descriptor = FetchDescriptor<BibleModule>()
                if let modules = try? modelContext.fetch(descriptor),
                   let module = modules.first(where: { $0.id == moduleID }) {
                    libraryManager.selectModule(module)
                }
            }

        case .book:
            appState.selectedSidebarItem = .bible
            if let moduleID = result.moduleID {
                let descriptor = FetchDescriptor<BibleModule>()
                if let modules = try? modelContext.fetch(descriptor),
                   let module = modules.first(where: { $0.id == moduleID }) {
                    libraryManager.selectModule(module)
                    if let bookID = result.bookID,
                       let book = module.books.first(where: { $0.id == bookID }) {
                        libraryManager.selectBook(book)
                        // Also navigate to chapter if provided
                        if let chapterID = result.chapterID,
                           let chapter = book.chapters.first(where: { $0.id == chapterID }) {
                            libraryManager.selectChapter(chapter)
                        }
                    }
                }
            }

        case .bibleVerse:
            appState.selectedSidebarItem = .bible
            // Navigate to the verse's book/chapter
            if let verseID = result.verseID {
                let descriptor = FetchDescriptor<BibleVerse>()
                if let verses = try? modelContext.fetch(descriptor),
                   let verse = verses.first(where: { $0.id == verseID }),
                   let chapter = verse.chapter,
                   let book = chapter.book,
                   let module = book.module {
                    libraryManager.selectModule(module)
                    libraryManager.selectBook(book)
                    libraryManager.selectChapter(chapter)
                    libraryManager.selectVerse(verse)
                }
            }

        case .collection:
            appState.selectedSidebarItem = .songs
            if let collectionID = result.collectionID {
                let descriptor = FetchDescriptor<SongCollection>()
                if let collections = try? modelContext.fetch(descriptor),
                   let collection = collections.first(where: { $0.id == collectionID }) {
                    libraryManager.selectCollection(collection)
                }
            }

        case .song:
            appState.selectedSidebarItem = .songs
            if let songID = result.songID {
                let descriptor = FetchDescriptor<Song>()
                if let songs = try? modelContext.fetch(descriptor),
                   let song = songs.first(where: { $0.id == songID }) {
                    if let collection = song.collection {
                        libraryManager.selectCollection(collection)
                    }
                    libraryManager.selectSong(song)
                }
            }
        }

        dismiss()
    }

    private func dismiss() {
        isPresented = false
        query = ""
        results = []
        selectedIndex = 0
    }
}

// MARK: - Quick Search Row
private struct QuickSearchRow: View {
    let result: QuickSearchResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: result.icon)
                .font(.body)
                .foregroundStyle(result.iconColor)
                .frame(width: 28, height: 28)
                .background(result.iconColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(result.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !result.detail.isEmpty {
                Text(result.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Text(result.type.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
    }
}
