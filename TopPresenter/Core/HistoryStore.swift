//
//  HistoryStore.swift
//  TopPresenter
//
//  Advanced presentation history — a record of everything shown to the audience
//  (song verses/slides + Bible verses), aggregatable to songs and to bible
//  verse/chapter/book/translation. Also keeps the ⌘K search log (SearchEvent).
//
//  Stored in its OWN SwiftData container (a separate `History.store` file), kept
//  completely apart from the song/bible library: it is never part of the
//  `TopPresenter Bible`/`TopPresenter Song` JSON import/export, it survives
//  library re-imports/deletions (events key on STABLE identifiers, not UUIDs),
//  and it has its own export (see HistoryExportService).
//

import Foundation
import SwiftData

// MARK: - The single history entity

/// One "shown live" event. Denormalized + keyed on stable identifiers so a
/// re-imported song (new UUID, same CCLI/title) still attributes to the same row.
@Model
final class PresentationEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var sessionID: UUID
    var dwellSeconds: Double
    var contentType: String        // "song" | "bible" | "custom"

    // Song fields (empty for non-song)
    var songKey: String            // stable: "ccli:<n>" or "title:<norm>|<source>"
    var songTitle: String
    var versionName: String
    var verseLabel: String
    var slideIndex: Int

    // Bible fields (zero/empty for non-bible)
    var translation: String        // module abbreviation, e.g. "EDC100"
    var translationName: String
    var bookNumber: Int
    var bookName: String
    var chapter: Int
    var verseStart: Int
    var verseEnd: Int
    var reference: String

    init(
        timestamp: Date, sessionID: UUID, dwellSeconds: Double, contentType: String,
        songKey: String = "", songTitle: String = "", versionName: String = "",
        verseLabel: String = "", slideIndex: Int = 0,
        translation: String = "", translationName: String = "", bookNumber: Int = 0,
        bookName: String = "", chapter: Int = 0, verseStart: Int = 0, verseEnd: Int = 0,
        reference: String = ""
    ) {
        self.id = UUID()
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.dwellSeconds = dwellSeconds
        self.contentType = contentType
        self.songKey = songKey
        self.songTitle = songTitle
        self.versionName = versionName
        self.verseLabel = verseLabel
        self.slideIndex = slideIndex
        self.translation = translation
        self.translationName = translationName
        self.bookNumber = bookNumber
        self.bookName = bookName
        self.chapter = chapter
        self.verseStart = verseStart
        self.verseEnd = verseEnd
        self.reference = reference
    }
}

/// One ⌘K palette search — recorded when the operator COMMITS a result
/// (Enter/⌘Enter/click) or abandons a non-empty query on dismiss. Never
/// per-keystroke.
@Model
final class SearchEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var query: String
    /// What the search led to: "song" | "verse" | "reference" | "media" |
    /// "session" | "abandoned" (closed without opening anything).
    var resultKind: String
    var resultTitle: String
    /// Sidebar module the palette was opened from (AppState.SidebarItem rawValue).
    var module: String

    init(timestamp: Date = .now, query: String, resultKind: String,
         resultTitle: String, module: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.query = query
        self.resultKind = resultKind
        self.resultTitle = resultTitle
        self.module = module
    }
}

// MARK: - Non-persisted aggregates (for the History viewer + export)

struct SongHistorySummary: Identifiable, Hashable {
    var id: String { songKey }
    let songKey: String
    let title: String
    let timesPresented: Int        // distinct sessions
    let verseShows: Int            // total verse/slide events
    let firstPresented: Date
    let lastPresented: Date
}

/// One verse/slide tally inside a song's drill-down.
struct VerseTally: Identifiable, Hashable {
    var id: String { label }
    let label: String
    let count: Int
    let lastShown: Date
}

struct BibleHistorySummary: Identifiable, Hashable {
    var id: String { translation + "|" + String(bookNumber) + "|" + String(chapter) + "|" + String(verseStart) }
    let translation: String
    let translationName: String
    let bookNumber: Int
    let bookName: String
    let chapter: Int
    let verseStart: Int
    let verseEnd: Int
    let reference: String
    let timesPresented: Int        // distinct sessions
    let shows: Int
    let firstPresented: Date
    let lastPresented: Date
}

/// One ⌘K query's aggregate (grouped by folded text) — the History ▸ Căutări tab.
struct SearchHistorySummary: Identifiable, Hashable {
    var id: String { key }
    /// Folded (lowercased, diacritic-insensitive) grouping key.
    let key: String
    /// Most recent raw spelling of the query.
    let query: String
    let count: Int
    let lastUsed: Date
    let lastResultKind: String
    let lastResultTitle: String
}

// MARK: - The store

@Observable
final class HistoryStore {
    let container: ModelContainer
    /// Our own context (NOT `container.mainContext`, which is `@MainActor`-isolated
    /// and can't be reached from this non-isolated class). Used on the main thread.
    let context: ModelContext

    init(inMemory: Bool = false) {
        let schema = Schema([PresentationEvent.self, SearchEvent.self])
        let config = ModelConfiguration("History", schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create History ModelContainer: \(error)")
        }
        context = ModelContext(container)
    }

    // MARK: Recording

    func record(_ event: PresentationEvent) {
        context.insert(event)
        try? context.save()
    }

    // MARK: Stable keys

    /// Stable song identity: CCLI if present, else normalized title + source.
    /// nonisolated: pure string logic — the SearchIndexBuilder actor stamps it
    /// on every SongIndexEntry off-main.
    nonisolated static func songKey(ccli: String, title: String, source: String) -> String {
        let c = ccli.trimmingCharacters(in: .whitespacesAndNewlines)
        if !c.isEmpty { return "ccli:" + c }
        let t = title.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return "title:" + t + "|" + source.lowercased()
    }

    // MARK: Queries

    private func allEvents() -> [PresentationEvent] {
        (try? context.fetch(FetchDescriptor<PresentationEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? []
    }

    /// Songs presented, one summary per stable song key.
    func songSummaries() -> [SongHistorySummary] {
        let songs = allEvents().filter { $0.contentType == "song" }
        let groups = Dictionary(grouping: songs, by: \.songKey)
        return groups.map { key, evs in
            SongHistorySummary(
                songKey: key,
                title: evs.first(where: { !$0.songTitle.isEmpty })?.songTitle ?? key,
                timesPresented: Set(evs.map(\.sessionID)).count,
                verseShows: evs.count,
                firstPresented: evs.map(\.timestamp).min() ?? .now,
                lastPresented: evs.map(\.timestamp).max() ?? .now
            )
        }.sorted { $0.lastPresented > $1.lastPresented }
    }

    /// All events for one song (its drill-down feed).
    func events(forSongKey key: String) -> [PresentationEvent] {
        allEvents().filter { $0.contentType == "song" && $0.songKey == key }
    }

    /// One song's summary (nil if never presented) — for the song detail panel.
    func summary(forSongKey key: String) -> SongHistorySummary? {
        let evs = events(forSongKey: key)
        guard !evs.isEmpty else { return nil }
        return SongHistorySummary(
            songKey: key, title: evs.first(where: { !$0.songTitle.isEmpty })?.songTitle ?? key,
            timesPresented: Set(evs.map(\.sessionID)).count, verseShows: evs.count,
            firstPresented: evs.map(\.timestamp).min() ?? .now,
            lastPresented: evs.map(\.timestamp).max() ?? .now)
    }

    /// Per-verse/slide tallies for one song.
    func verseTallies(forSongKey key: String) -> [VerseTally] {
        let evs = events(forSongKey: key)
        let byLabel = Dictionary(grouping: evs) { $0.verseLabel.isEmpty ? "Slide \($0.slideIndex + 1)" : $0.verseLabel }
        return byLabel.map { label, e in
            VerseTally(label: label, count: e.count, lastShown: e.map(\.timestamp).max() ?? .now)
        }.sorted { $0.count > $1.count }
    }

    /// Distinct presentation sessions for one song, newest first (the timeline).
    func sessions(forSongKey key: String) -> [(date: Date, verses: Int)] {
        let evs = events(forSongKey: key)
        let bySession = Dictionary(grouping: evs, by: \.sessionID)
        return bySession.values.map { e in (date: e.map(\.timestamp).min() ?? .now, verses: e.count) }
            .sorted { $0.date > $1.date }
    }

    /// Bible verses presented (one summary per translation:book:chapter:verse).
    func bibleSummaries() -> [BibleHistorySummary] {
        let bible = allEvents().filter { $0.contentType == "bible" }
        let groups = Dictionary(grouping: bible) {
            "\($0.translation)|\($0.bookNumber)|\($0.chapter)|\($0.verseStart)|\($0.verseEnd)"
        }
        return groups.map { _, evs in
            let f = evs[0]
            return BibleHistorySummary(
                translation: f.translation, translationName: f.translationName,
                bookNumber: f.bookNumber, bookName: f.bookName, chapter: f.chapter,
                verseStart: f.verseStart, verseEnd: f.verseEnd, reference: f.reference,
                timesPresented: Set(evs.map(\.sessionID)).count, shows: evs.count,
                firstPresented: evs.map(\.timestamp).min() ?? .now,
                lastPresented: evs.map(\.timestamp).max() ?? .now
            )
        }.sorted { $0.lastPresented > $1.lastPresented }
    }

    /// Flat event log (newest first) — for CSV/JSON export.
    func exportEvents() -> [PresentationEvent] { allEvents() }

    func totalEvents() -> Int {
        (try? context.fetchCount(FetchDescriptor<PresentationEvent>())) ?? 0
    }

    // MARK: ⌘K search history

    func recordSearch(query: String, resultKind: String, resultTitle: String, module: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        context.insert(SearchEvent(query: q, resultKind: resultKind,
                                   resultTitle: resultTitle, module: module))
        try? context.save()
    }

    private func allSearchEvents() -> [SearchEvent] {
        (try? context.fetch(FetchDescriptor<SearchEvent>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]))) ?? []
    }

    /// ⌘K searches grouped by folded query, newest first. The "last result"
    /// is the most recent COMMITTED event of the group (abandoned-only groups
    /// show empty kind/title).
    func searchSummaries() -> [SearchHistorySummary] {
        let groups = Dictionary(grouping: allSearchEvents()) {
            $0.query.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        }
        return groups.map { key, evs in
            // Groups keep the fetch's newest-first order.
            let committed = evs.first { $0.resultKind != "abandoned" }
            return SearchHistorySummary(
                key: key,
                query: evs[0].query,
                count: evs.count,
                lastUsed: evs[0].timestamp,
                lastResultKind: committed?.resultKind ?? "",
                lastResultTitle: committed?.resultTitle ?? ""
            )
        }.sorted { $0.lastUsed > $1.lastUsed }
    }

    func totalSearches() -> Int {
        (try? context.fetchCount(FetchDescriptor<SearchEvent>())) ?? 0
    }

    func clearSearchHistory() {
        try? context.delete(model: SearchEvent.self)
        try? context.save()
    }

    /// Advanced settings: wipe EVERYTHING — presentations AND searches.
    func clearAll() {
        try? context.delete(model: PresentationEvent.self)
        try? context.delete(model: SearchEvent.self)
        try? context.save()
    }
}
