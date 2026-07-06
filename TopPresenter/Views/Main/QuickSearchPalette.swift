//
//  QuickSearchPalette.swift
//  TopPresenter
//
//  ⌘K — Spotlight-style command palette over the SearchIndex: songs (title/
//  author/lyrics via the token inverted index), Bible references ("ioan 3:16",
//  "1 cor 13 4-7"), full-text verse search in the ACTIVE translation, media and
//  sessions. Everything reads pre-built in-memory projections — ZERO SwiftData
//  work per keystroke. Enter opens/navigates; ⌘Enter presents LIVE.
//

import SwiftUI
import SwiftData

// MARK: - Results

private enum PaletteResult: Identifiable {
    case reference(BibleReferenceMatch)
    case song(SongIndexEntry)
    case verse(VerseIndexEntry)
    case media(MediaIndexEntry)
    case session(SessionIndexEntry)

    var id: String {
        switch self {
        case .reference(let r): return "ref:\(r.bookNumber):\(r.chapter):\(r.verseStart ?? 0)-\(r.verseEnd ?? 0)"
        case .song(let e): return "song:\(e.id.uuidString)"
        case .verse(let v): return "verse:\(v.bookNumber):\(v.chapter):\(v.verse)"
        case .media(let m): return "media:\(m.id.uuidString)"
        case .session(let s): return "session:\(s.id.uuidString)"
        }
    }
}

private struct PaletteSection: Identifiable {
    let id: String
    let title: String
    let results: [PaletteResult]
}

// MARK: - Palette

struct QuickSearchPalette: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SearchIndex.self) private var index
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var pm
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService
    @Environment(AppState.self) private var appState

    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var fieldFocused: Bool

    @AppStorage("song_maxLinesPerSlide") private var maxLines: Int = 6
    @AppStorage("song_repeatBracket") private var repeatBracket = "none"
    @AppStorage("song_repeatCount") private var repeatCount = "times"

    // MARK: Search (pure, instant — index only)

    private var sections: [PaletteSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var out: [PaletteSection] = []

        if let ref = BibleReferenceParser.parse(trimmed, books: index.books) {
            out.append(PaletteSection(
                id: "ref",
                title: String(localized: "Referință biblică", comment: "Palette section"),
                results: [.reference(ref)]
            ))
        }
        let songs = index.searchSongs(trimmed, limit: 10)
        if !songs.isEmpty {
            out.append(PaletteSection(
                id: "songs",
                title: String(localized: "Cântece", comment: "Palette section"),
                results: songs.map { .song($0) }
            ))
        }
        let verses = index.searchVerses(trimmed, limit: 8)
        if !verses.isEmpty {
            out.append(PaletteSection(
                id: "verses",
                title: String(localized: "Versete (\(libraryManager.selectedBibleModule?.abbreviation ?? ""))", comment: "Palette section"),
                results: verses.map { .verse($0) }
            ))
        }
        let media = index.searchMedia(trimmed, limit: 5)
        if !media.isEmpty {
            out.append(PaletteSection(
                id: "media",
                title: String(localized: "Media", comment: "Palette section"),
                results: media.map { .media($0) }
            ))
        }
        let sessions = index.searchSessions(trimmed, limit: 5)
        if !sessions.isEmpty {
            out.append(PaletteSection(
                id: "sessions",
                title: String(localized: "Sesiuni", comment: "Palette section"),
                results: sessions.map { .session($0) }
            ))
        }
        return out
    }

    private var flatResults: [PaletteResult] { sections.flatMap(\.results) }

    private var selectedResult: PaletteResult? {
        let flat = flatResults
        guard !flat.isEmpty else { return nil }
        return flat[min(selectedIndex, flat.count - 1)]
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                searchField
                Divider()
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    idleHint
                } else if flatResults.isEmpty {
                    noResults
                } else {
                    HStack(spacing: 0) {
                        resultsList
                            .frame(width: 400)
                        Divider()
                        previewPane
                            .frame(maxWidth: .infinity)
                    }
                }
                Divider()
                footerBar
            }
            .frame(width: 720)
            .frame(maxHeight: 480)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.08)))
            .shadow(color: .black.opacity(0.35), radius: 28, y: 12)
            .padding(.top, 110)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            fieldFocused = true
            // Make sure the active translation's verse index is (being) built.
            if let moduleID = libraryManager.selectedBibleModule?.id {
                index.indexVerses(moduleID: moduleID)
            }
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.downArrow) {
            selectedIndex = min(selectedIndex + 1, max(flatResults.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            selectedIndex = max(selectedIndex - 1, 0)
            return .handled
        }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard let result = selectedResult else { return .ignored }
            if press.modifiers.contains(.command) {
                present(result)
            } else {
                open(result)
            }
            return .handled
        }
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "Cântece, Ioan 3:16, versete, media, sesiuni…", comment: "Palette placeholder"),
                text: $query
            )
            .textFieldStyle(.plain)
            .font(.title3)
            .focused($fieldFocused)
            .onChange(of: query) { _, _ in selectedIndex = 0 }

            if index.isBuilding {
                ProgressView().controlSize(.small)
                    .help(String(localized: "Indexul se construiește…", comment: "Tooltip"))
            }
            if !query.isEmpty {
                Button {
                    query = ""
                    selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    var runningIndex = 0
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(Array(section.results.enumerated()), id: \.element.id) { offset, result in
                            let flatIdx = runningIndexBase(for: section) + offset
                            PaletteRow(result: result, isSelected: flatIdx == selectedIndex)
                                .id(flatIdx)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedIndex = flatIdx; open(result) }
                        }
                        .onAppear { runningIndex += section.results.count }
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                withAnimation(.easeInOut(duration: 0.1)) { proxy.scrollTo(newIndex, anchor: .center) }
            }
        }
    }

    /// Flat index where a section's results start.
    private func runningIndexBase(for section: PaletteSection) -> Int {
        var base = 0
        for s in sections {
            if s.id == section.id { return base }
            base += s.results.count
        }
        return base
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch selectedResult {
            case .song(let e):
                Label(e.title, systemImage: "music.note").font(.headline).lineLimit(2)
                if !e.author.isEmpty { Text(e.author).font(.caption).foregroundStyle(.secondary) }
                if !e.songbookName.isEmpty { Text(e.songbookName).font(.caption2).foregroundStyle(.tertiary) }
                if !e.firstLine.isEmpty {
                    Text(e.firstLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(6)
                        .padding(.top, 4)
                }
            case .verse(let v):
                Label("\(v.bookName) \(v.chapter):\(v.verse)", systemImage: "text.quote").font(.headline)
                Text(v.text).font(.callout).foregroundStyle(.secondary).lineLimit(10).padding(.top, 4)
            case .reference(let r):
                Label(referenceLabel(r), systemImage: "book.fill").font(.headline)
                Text(referencePreviewText(r))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(10).padding(.top, 4)
            case .media(let m):
                Label(m.name, systemImage: (MediaKind(rawValue: m.mediaType) ?? .image).systemImage)
                    .font(.headline).lineLimit(2)
                Text(m.mediaType.capitalized).font(.caption).foregroundStyle(.secondary)
            case .session(let s):
                Label(s.name, systemImage: "list.bullet.rectangle").font(.headline).lineLimit(2)
                Text(s.date.formatted(date: .complete, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }

    private var idleHint: some View {
        VStack(spacing: 10) {
            Text(String(localized: "Caută în toată biblioteca", comment: "Palette hint title"))
                .font(.headline).foregroundStyle(.secondary)
            Text(String(localized: "cântece · Ioan 3:16 · text din versete · media · sesiuni", comment: "Palette hint"))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.title).foregroundStyle(.tertiary)
            Text(String(localized: "Niciun rezultat pentru „\(query)”", comment: "Palette empty"))
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }

    private var footerBar: some View {
        HStack(spacing: 14) {
            keyHint("↩", String(localized: "Deschide", comment: "Palette key hint"))
            keyHint("⌘↩", String(localized: "Proiectează", comment: "Palette key hint"))
            keyHint("↑↓", String(localized: "Navighează", comment: "Palette key hint"))
            Spacer()
            keyHint("esc", String(localized: "Închide", comment: "Palette key hint"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.weight(.semibold).monospaced())
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Reference helpers (read the in-memory verse index — no SwiftData)

    private func referenceLabel(_ r: BibleReferenceMatch) -> String {
        if let vs = r.verseStart, let ve = r.verseEnd {
            return vs == ve ? "\(r.bookName) \(r.chapter):\(vs)" : "\(r.bookName) \(r.chapter):\(vs)-\(ve)"
        }
        return "\(r.bookName) \(r.chapter)"
    }

    private func referenceVerses(_ r: BibleReferenceMatch) -> [VerseIndexEntry] {
        index.verses.filter {
            $0.bookNumber == r.bookNumber && $0.chapter == r.chapter
                && (r.verseStart == nil || ($0.verse >= r.verseStart! && $0.verse <= (r.verseEnd ?? r.verseStart!)))
        }
    }

    private func referencePreviewText(_ r: BibleReferenceMatch) -> String {
        let verses = referenceVerses(r).prefix(4)
        return verses.map { "(\($0.verse)) \($0.text)" }.joined(separator: " ")
    }

    // MARK: Actions

    /// Enter — NAVIGATE to the item (safe during a service).
    private func open(_ result: PaletteResult) {
        switch result {
        case .song(let e):
            appState.selectedSidebarItem = .songs
            withModel(Song.self, id: e.id) { song in
                if let col = song.collection { libraryManager.selectCollection(col) }
                libraryManager.selectSong(song)
            }
        case .verse(let v):
            navigateBible(bookNumber: v.bookNumber, chapter: v.chapter, verse: v.verse)
        case .reference(let r):
            navigateBible(bookNumber: r.bookNumber, chapter: r.chapter, verse: r.verseStart)
        case .media(let m):
            appState.selectedSidebarItem = .media
            withModel(MediaItem.self, id: m.id) { libraryManager.selectedMediaItem = $0 }
        case .session(let s):
            appState.selectedSidebarItem = .schedule
            withModel(ServiceSchedule.self, id: s.id) { libraryManager.selectedSchedule = $0 }
        }
        dismiss()
    }

    /// ⌘Enter — PRESENT the item live, right from the palette.
    private func present(_ result: PaletteResult) {
        switch result {
        case .song(let e):
            withModel(Song.self, id: e.id) { song in
                let version = song.activeVersion
                let slides = buildSongSlides(song: song, version: version, maxLines: maxLines,
                                             bilingual: false, language: nil,
                                             bracket: repeatBracket, countStyle: repeatCount)
                guard let first = slides.first else { return }
                libraryManager.selectSong(song)
                libraryManager.selectSongSlide(text: first.text, label: first.label, index: 0, count: first.total)
                pm.showSongVerse(text: first.text, title: song.title, verseLabel: first.label,
                                 slideIndex: 0, slideCount: first.total,
                                 song: song, version: version, lines: first.lines)
            }
        case .verse(let v):
            presentVerses([v], bookName: v.bookName, chapter: v.chapter)
        case .reference(let r):
            let verses = referenceVerses(r)
            guard !verses.isEmpty else { return }
            presentVerses(verses, bookName: r.bookName, chapter: r.chapter)
        case .media(let m):
            withModel(MediaItem.self, id: m.id) { item in
                MediaPresenter.present(item, pm: pm, video: videoPlayerService, audio: audioPlayerManager)
            }
        case .session(let s):
            withModel(ServiceSchedule.self, id: s.id) { schedule in
                appState.selectedSidebarItem = .schedule
                libraryManager.selectedSchedule = schedule
            }
        }
        dismiss()
    }

    /// Push verses live with full coordinates (sets the live Bible anchor).
    private func presentVerses(_ verses: [VerseIndexEntry], bookName: String, chapter: Int) {
        guard let first = verses.first, let last = verses.last else { return }
        let mv = pm.bibleMultiVerse
        let separator = mv.layout == "newLine" ? "\n" : " "
        let text = verses
            .map { mv.showNumbers ? "(\($0.verse)) \($0.text)" : $0.text }
            .joined(separator: separator)
        let range = first.verse == last.verse ? "\(first.verse)" : "\(first.verse)-\(last.verse)"
        let abbrev = libraryManager.selectedBibleModule?.abbreviation ?? ""
        pm.showBibleVerse(text: text, reference: "\(bookName) \(chapter):\(range)",
                          translationName: abbrev,
                          bookNumber: first.bookNumber, bookName: bookName, chapter: chapter,
                          verseStart: first.verse, verseEnd: last.verse, translation: abbrev)
    }

    /// Navigate the Bible browser to a book/chapter(/verse) in the active module.
    private func navigateBible(bookNumber: Int, chapter: Int, verse: Int?) {
        appState.selectedSidebarItem = .bible
        guard let module = libraryManager.selectedBibleModule,
              let book = module.books.first(where: { $0.bookNumber == bookNumber }) else { return }
        libraryManager.selectBook(book)
        guard let chap = book.chapters.first(where: { $0.chapterNumber == chapter }) else { return }
        libraryManager.selectChapter(chap)
        if let verse, let v = chap.verses.first(where: { $0.verseNumber == verse }) {
            libraryManager.selectVerse(v)
        }
    }

    /// Predicate + fetchLimit 1 — never fetch-all to find one row.
    private func withModel<T: PersistentModel>(_ type: T.Type, id: UUID, _ action: (T) -> Void)
        where T: IdentifiableByUUID {
        var d = FetchDescriptor<T>(predicate: T.predicate(forID: id))
        d.fetchLimit = 1
        if let model = (try? modelContext.fetch(d))?.first { action(model) }
    }

    private func dismiss() {
        isPresented = false
        query = ""
        selectedIndex = 0
    }
}

// MARK: - UUID predicate helper (SwiftData #Predicate needs concrete key paths)

protocol IdentifiableByUUID: PersistentModel {
    static func predicate(forID id: UUID) -> Predicate<Self>
}

extension Song: IdentifiableByUUID {
    static func predicate(forID id: UUID) -> Predicate<Song> { #Predicate { $0.id == id } }
}
extension MediaItem: IdentifiableByUUID {
    static func predicate(forID id: UUID) -> Predicate<MediaItem> { #Predicate { $0.id == id } }
}
extension ServiceSchedule: IdentifiableByUUID {
    static func predicate(forID id: UUID) -> Predicate<ServiceSchedule> { #Predicate { $0.id == id } }
}

// MARK: - Row

private struct PaletteRow: View {
    let result: PaletteResult
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 6)
    }

    private var icon: String {
        switch result {
        case .reference: return "book.fill"
        case .song: return "music.note"
        case .verse: return "text.quote"
        case .media(let m): return (MediaKind(rawValue: m.mediaType) ?? .image).systemImage
        case .session: return "list.bullet.rectangle"
        }
    }

    private var color: Color {
        switch result {
        case .reference: return .blue
        case .song: return .purple
        case .verse: return .green
        case .media: return .orange
        case .session: return .teal
        }
    }

    private var title: String {
        switch result {
        case .reference(let r):
            if let vs = r.verseStart, let ve = r.verseEnd {
                return vs == ve ? "\(r.bookName) \(r.chapter):\(vs)" : "\(r.bookName) \(r.chapter):\(vs)-\(ve)"
            }
            return "\(r.bookName) \(r.chapter)"
        case .song(let e): return e.title
        case .verse(let v): return "\(v.bookName) \(v.chapter):\(v.verse)"
        case .media(let m): return m.name
        case .session(let s): return s.name
        }
    }

    private var subtitle: String {
        switch result {
        case .reference: return String(localized: "Sari la pasaj", comment: "Palette row subtitle")
        case .song(let e): return e.author.isEmpty ? e.collectionName : e.author
        case .verse(let v): return String(v.text.prefix(90))
        case .media(let m): return m.mediaType.capitalized
        case .session(let s): return s.date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
