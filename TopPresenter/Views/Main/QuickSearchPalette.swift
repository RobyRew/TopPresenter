//
//  QuickSearchPalette.swift
//  TopPresenter
//
//  ⌘K — Spotlight-style command palette. The search itself (PaletteSearch.run)
//  executes ONCE per keystroke in a DETACHED task over an immutable snapshot —
//  body only renders `hits` state, so typing stays instant on 60k songs +
//  whole Bibles. Typo-tolerant (fuzzy token fallback), highlighted matches,
//  recents on empty query. Enter opens/navigates; ⌘Enter presents LIVE.
//

import SwiftUI
import SwiftData

// MARK: - Recents (last opened/presented items, persisted)

struct PaletteRecent: Codable, Equatable, Identifiable {
    var kind: String              // "song" | "media" | "session" | "verse" | "reference"
    var uuid: UUID?               // song / media / session
    var bookNumber: Int = 0       // verse / reference
    var chapter: Int = 0
    var verseStart: Int = 0
    var verseEnd: Int = 0
    var title: String
    var subtitle: String

    var id: String { "\(kind):\(uuid?.uuidString ?? "\(bookNumber):\(chapter):\(verseStart)-\(verseEnd)")" }
}

/// Last 10 items opened/presented from the palette — shown on empty query.
@Observable
final class PaletteRecentsStore {
    static let shared = PaletteRecentsStore()
    private static let key = "palette_recents_v1"

    private(set) var items: [PaletteRecent] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PaletteRecent].self, from: data) {
            items = decoded
        }
    }

    func record(_ recent: PaletteRecent) {
        items.removeAll { $0.id == recent.id }
        items.insert(recent, at: 0)
        if items.count > 10 { items.removeLast(items.count - 10) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

// MARK: - Results

private enum PaletteResult {
    case reference(BibleReferenceMatch)
    case song(SongIndexEntry)
    case verse(VerseIndexEntry)
    case media(MediaIndexEntry)
    case session(SessionIndexEntry)
    case recent(PaletteRecent)

    var id: String {
        switch self {
        case .reference(let r): return "ref:\(r.bookNumber):\(r.chapter):\(r.verseStart ?? 0)-\(r.verseEnd ?? 0)"
        case .song(let e): return "song:\(e.id.uuidString)"
        case .verse(let v): return "verse:\(v.bookNumber):\(v.chapter):\(v.verse)"
        case .media(let m): return "media:\(m.id.uuidString)"
        case .session(let s): return "session:\(s.id.uuidString)"
        case .recent(let r): return "recent:\(r.id)"
        }
    }
}

private struct PaletteRowItem: Identifiable {
    let flatIndex: Int
    let result: PaletteResult
    var id: String { result.id }
}

private struct PaletteSection: Identifiable {
    let id: String
    let title: String
    let rows: [PaletteRowItem]
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
    @State private var hits = PaletteHits.none
    @State private var selectedIndex = 0
    @FocusState private var fieldFocused: Bool

    @AppStorage("song_maxLinesPerSlide") private var maxLines: Int = 6
    @AppStorage("song_repeatBracket") private var repeatBracket = "none"
    @AppStorage("song_repeatCount") private var repeatCount = "times"

    private let recents = PaletteRecentsStore.shared

    // MARK: Display model (cheap mapping over `hits` state — NO searching here)

    private var isQueryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var sections: [PaletteSection] {
        var out: [PaletteSection] = []
        var idx = 0
        func add(_ id: String, _ title: String, _ results: [PaletteResult]) {
            guard !results.isEmpty else { return }
            let rows = results.map { r -> PaletteRowItem in
                defer { idx += 1 }
                return PaletteRowItem(flatIndex: idx, result: r)
            }
            out.append(PaletteSection(id: id, title: title, rows: rows))
        }

        if isQueryEmpty {
            add("recents", String(localized: "Recente", comment: "Palette section"),
                recents.items.map { .recent($0) })
            return out
        }
        if let ref = hits.reference {
            add("ref", String(localized: "Referință biblică", comment: "Palette section"), [.reference(ref)])
        }
        add("songs", String(localized: "Cântece", comment: "Palette section"),
            hits.songs.map { .song($0) })
        add("verses",
            String(localized: "Versete (\(libraryManager.selectedBibleModule?.abbreviation ?? ""))", comment: "Palette section"),
            hits.verses.map { .verse($0) })
        add("media", String(localized: "Media", comment: "Palette section"),
            hits.media.map { .media($0) })
        add("sessions", String(localized: "Sesiuni", comment: "Palette section"),
            hits.sessions.map { .session($0) })
        return out
    }

    private var flatResults: [PaletteResult] {
        sections.flatMap { $0.rows.map(\.result) }
    }

    private var selectedResult: PaletteResult? {
        let flat = flatResults
        guard !flat.isEmpty else { return nil }
        return flat[min(selectedIndex, flat.count - 1)]
    }

    /// Search results are stale while `hits.query` lags the typed query.
    private var isSearching: Bool {
        !isQueryEmpty && hits.query != query.trimmingCharacters(in: .whitespacesAndNewlines)
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
                if isQueryEmpty && recents.items.isEmpty {
                    idleHint
                } else if flatResults.isEmpty {
                    if isSearching {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 140)
                    } else {
                        noResults
                    }
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
        // THE search executor: one detached run per (debounced) keystroke or
        // index generation bump. body never computes results itself.
        .task(id: "\(query)#\(index.generation)") {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                hits = .none
                selectedIndex = 0
                return
            }
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            let snapshot = index.snapshot()
            let result = await Task.detached(priority: .userInitiated) {
                PaletteSearch.run(trimmed, in: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            hits = result
            selectedIndex = 0
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

            if index.isBuilding || isSearching {
                ProgressView().controlSize(.small)
                    .help(String(localized: "Se caută…", comment: "Tooltip"))
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
                    ForEach(sections) { section in
                        Text(section.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        ForEach(section.rows) { row in
                            PaletteRow(result: row.result,
                                       isSelected: row.flatIndex == selectedIndex,
                                       highlightTokens: hits.tokens)
                                .id(row.flatIndex)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedIndex = row.flatIndex; open(row.result) }
                                .onHover { inside in
                                    if inside { selectedIndex = row.flatIndex }
                                }
                        }
                    }
                    if index.isIndexingVerses, !isQueryEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(String(localized: "Se indexează versetele…", comment: "Palette note"))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 6)
            }
            .onChange(of: selectedIndex) { _, newIndex in
                proxy.scrollTo(newIndex, anchor: .center)
            }
        }
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
                Text(paletteHighlight(v.text, tokens: hits.tokens, highlightFont: .callout.weight(.semibold)))
                    .font(.callout).foregroundStyle(.secondary).lineLimit(10).padding(.top, 4)
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
            case .recent(let r):
                Label(r.title, systemImage: PaletteRow.icon(forKind: r.kind)).font(.headline).lineLimit(2)
                if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(.secondary) }
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
            Text(String(localized: "Am căutat și cu toleranță la greșeli de scriere", comment: "Palette empty note"))
                .font(.caption2).foregroundStyle(.tertiary)
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
        case .recent(let r):
            openRecent(r)
            return
        }
        recents.record(makeRecent(result))
        dismiss()
    }

    /// ⌘Enter — PRESENT the item live, right from the palette.
    private func present(_ result: PaletteResult) {
        switch result {
        case .song(let e):
            presentSong(id: e.id)
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
        case .recent(let r):
            presentRecent(r)
            return
        }
        recents.record(makeRecent(result))
        dismiss()
    }

    private func presentSong(id: UUID) {
        withModel(Song.self, id: id) { song in
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

    // MARK: Recents plumbing

    private func makeRecent(_ result: PaletteResult) -> PaletteRecent {
        switch result {
        case .song(let e):
            return PaletteRecent(kind: "song", uuid: e.id, title: e.title,
                                 subtitle: e.author.isEmpty ? e.collectionName : e.author)
        case .verse(let v):
            return PaletteRecent(kind: "verse", uuid: nil, bookNumber: v.bookNumber,
                                 chapter: v.chapter, verseStart: v.verse, verseEnd: v.verse,
                                 title: "\(v.bookName) \(v.chapter):\(v.verse)",
                                 subtitle: String(v.text.prefix(90)))
        case .reference(let r):
            return PaletteRecent(kind: "reference", uuid: nil, bookNumber: r.bookNumber,
                                 chapter: r.chapter, verseStart: r.verseStart ?? 0,
                                 verseEnd: r.verseEnd ?? r.verseStart ?? 0,
                                 title: referenceLabel(r),
                                 subtitle: String(localized: "Sari la pasaj", comment: "Palette row subtitle"))
        case .media(let m):
            return PaletteRecent(kind: "media", uuid: m.id, title: m.name,
                                 subtitle: m.mediaType.capitalized)
        case .session(let s):
            return PaletteRecent(kind: "session", uuid: s.id, title: s.name,
                                 subtitle: s.date.formatted(date: .abbreviated, time: .omitted))
        case .recent(let r):
            return r
        }
    }

    private func openRecent(_ r: PaletteRecent) {
        switch r.kind {
        case "song":
            guard let id = r.uuid else { return }
            appState.selectedSidebarItem = .songs
            withModel(Song.self, id: id) { song in
                if let col = song.collection { libraryManager.selectCollection(col) }
                libraryManager.selectSong(song)
            }
        case "media":
            guard let id = r.uuid else { return }
            appState.selectedSidebarItem = .media
            withModel(MediaItem.self, id: id) { libraryManager.selectedMediaItem = $0 }
        case "session":
            guard let id = r.uuid else { return }
            appState.selectedSidebarItem = .schedule
            withModel(ServiceSchedule.self, id: id) { libraryManager.selectedSchedule = $0 }
        case "verse", "reference":
            navigateBible(bookNumber: r.bookNumber, chapter: r.chapter,
                          verse: r.verseStart > 0 ? r.verseStart : nil)
        default:
            return
        }
        recents.record(r)
        dismiss()
    }

    private func presentRecent(_ r: PaletteRecent) {
        switch r.kind {
        case "song":
            guard let id = r.uuid else { return }
            presentSong(id: id)
        case "media":
            guard let id = r.uuid else { return }
            withModel(MediaItem.self, id: id) { item in
                MediaPresenter.present(item, pm: pm, video: videoPlayerService, audio: audioPlayerManager)
            }
        case "session":
            openRecent(r)
            return
        case "verse", "reference":
            // Resolve coordinates against the ACTIVE module's verse index.
            let verses = index.verses.filter {
                $0.bookNumber == r.bookNumber && $0.chapter == r.chapter
                    && (r.verseStart == 0 || ($0.verse >= r.verseStart && $0.verse <= max(r.verseEnd, r.verseStart)))
            }
            guard let first = verses.first else { return }
            presentVerses(verses, bookName: first.bookName, chapter: first.chapter)
        default:
            return
        }
        recents.record(r)
        dismiss()
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
        hits = .none
        selectedIndex = 0
    }
}

// MARK: - Match highlighting

/// Accent + heavier weight on every (folded) occurrence of the query tokens.
/// `range(of:options:)` handles diacritics natively („marire” finds „Mărire”).
func paletteHighlight(_ text: String, tokens: [String], highlightFont: Font) -> AttributedString {
    var attr = AttributedString(text)
    for tok in tokens where tok.count >= 2 {
        var start = text.startIndex
        while start < text.endIndex,
              let r = text.range(of: tok, options: [.caseInsensitive, .diacriticInsensitive],
                                 range: start..<text.endIndex) {
            if let ar = Range(r, in: attr) {
                attr[ar].foregroundColor = .accentColor
                attr[ar].font = highlightFont
            }
            start = r.upperBound
        }
    }
    return attr
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
    let highlightTokens: [String]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(paletteHighlight(title, tokens: highlightTokens,
                                      highlightFont: .callout.weight(.bold)))
                    .font(.callout.weight(.medium)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(paletteHighlight(subtitle, tokens: highlightTokens,
                                          highlightFont: .caption.weight(.bold)))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

    static func icon(forKind kind: String) -> String {
        switch kind {
        case "song": return "music.note"
        case "verse": return "text.quote"
        case "reference": return "book.fill"
        case "media": return "photo.on.rectangle"
        case "session": return "list.bullet.rectangle"
        default: return "clock.arrow.circlepath"
        }
    }

    private var icon: String {
        switch result {
        case .reference: return "book.fill"
        case .song: return "music.note"
        case .verse: return "text.quote"
        case .media(let m): return (MediaKind(rawValue: m.mediaType) ?? .image).systemImage
        case .session: return "list.bullet.rectangle"
        case .recent(let r): return Self.icon(forKind: r.kind)
        }
    }

    private var color: Color {
        switch result {
        case .reference: return .blue
        case .song: return .purple
        case .verse: return .green
        case .media: return .orange
        case .session: return .teal
        case .recent: return .gray
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
        case .recent(let r): return r.title
        }
    }

    private var subtitle: String {
        switch result {
        case .reference: return String(localized: "Sari la pasaj", comment: "Palette row subtitle")
        case .song(let e): return e.author.isEmpty ? e.collectionName : e.author
        case .verse(let v): return String(v.text.prefix(90))
        case .media(let m): return m.mediaType.capitalized
        case .session(let s): return s.date.formatted(date: .abbreviated, time: .omitted)
        case .recent(let r): return r.subtitle
        }
    }
}
