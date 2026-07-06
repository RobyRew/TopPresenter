//
//  SearchIndexService.swift
//  TopPresenter
//
//  THE search/browse backbone for large libraries (30–60k songs, whole Bibles).
//  Native only: a @ModelActor builder walks SwiftData OFF the main actor and
//  produces immutable, Sendable PROJECTIONS + a token inverted index; the
//  MainActor `SearchIndex` publishes snapshots that the library browser and the
//  ⌘K palette render from — zero SwiftData faulting per keystroke/cell, no
//  fetch-alls on the main thread. Rebuilds are debounced and incremental-ish
//  (full background rebuild ~O(n) once, then only on library changes).
//

import Foundation
import SwiftData
import Observation

// MARK: - Projections (Sendable value rows — what lists render)

nonisolated struct SongIndexEntry: Sendable, Identifiable, Equatable {
    let id: UUID                 // Song.id
    let title: String
    let author: String
    let language: String
    let songNumber: String
    let songbookName: String
    let collectionID: UUID?
    let collectionName: String
    let versionCount: Int
    let hasMedia: Bool
    let verified: Bool
    let modifiedDate: Date
    /// First lyric line — grid card preview without faulting the model graph.
    let firstLine: String
    /// Folded (lowercased, diacritic-insensitive) searchable text.
    let blob: String
}

nonisolated struct MediaIndexEntry: Sendable, Identifiable {
    let id: UUID
    let name: String
    let mediaType: String
    let folded: String
}

nonisolated struct SessionIndexEntry: Sendable, Identifiable {
    let id: UUID
    let name: String
    let date: Date
    let folded: String
}

nonisolated struct BookIndexEntry: Sendable {
    let moduleID: UUID
    let bookNumber: Int
    let name: String
    let folded: String
    let abbreviationFolded: String
    let chapterCount: Int
}

nonisolated struct VerseIndexEntry: Sendable {
    let moduleID: UUID
    let bookNumber: Int
    let bookName: String
    let chapter: Int
    let verse: Int
    let text: String
    let folded: String
}

// MARK: - Token inverted index (prefix search over 60k songs in <1ms)

/// Sorted unique tokens + postings lists (indices into the entries array).
/// Query tokens match by PREFIX (binary search over the sorted token table),
/// posting lists are unioned per query token and intersected across tokens.
nonisolated struct SongTokenIndex: Sendable {
    let tokens: [String]
    let postings: [[Int32]]

    static let empty = SongTokenIndex(tokens: [], postings: [])

    static func build(blobs: [String]) -> SongTokenIndex {
        var map: [String: [Int32]] = [:]
        map.reserveCapacity(blobs.count * 8)
        for (i, blob) in blobs.enumerated() {
            var seen = Set<Substring>()
            for tok in blob.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
                if tok.count < 2 { continue }
                if seen.insert(tok).inserted {
                    map[String(tok), default: []].append(Int32(i))
                }
            }
        }
        let sorted = map.keys.sorted()
        return SongTokenIndex(tokens: sorted, postings: sorted.map { map[$0]! })
    }

    /// Entry indices whose blob contains a token starting with `prefix`.
    func candidates(prefix: String) -> Set<Int32> {
        guard !tokens.isEmpty, !prefix.isEmpty else { return [] }
        // Binary search for the first token >= prefix.
        var lo = 0, hi = tokens.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tokens[mid] < prefix { lo = mid + 1 } else { hi = mid }
        }
        var out = Set<Int32>()
        var i = lo
        while i < tokens.count, tokens[i].hasPrefix(prefix) {
            out.formUnion(postings[i])
            i += 1
        }
        return out
    }

    /// AND across query tokens (each by prefix). Empty query → nil (no filter).
    func match(queryTokens: [String]) -> Set<Int32>? {
        guard !queryTokens.isEmpty else { return nil }
        var result: Set<Int32>? = nil
        for tok in queryTokens {
            let c = candidates(prefix: tok)
            result = result.map { $0.intersection(c) } ?? c
            if result?.isEmpty == true { return result }
        }
        return result
    }
}

// MARK: - Folding

nonisolated func searchFold(_ s: String) -> String {
    s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
}

nonisolated func searchTokens(_ query: String) -> [String] {
    searchFold(query)
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .filter { !$0.isEmpty }
        .map(String.init)
}

// MARK: - Off-main builder

@ModelActor
actor SearchIndexBuilder {
    struct SongsPayload: Sendable {
        let entries: [SongIndexEntry]
        let tokens: SongTokenIndex
        let languages: [String]
    }

    /// Builds the whole song projection in FOUR set-based queries (no per-song
    /// relationship faulting): songs, first verses, version counts, collections.
    func buildSongs() -> SongsPayload {
        // First lyric line per song — ONE query instead of 60k faults.
        var firstLines: [UUID: String] = [:]
        let verseDescriptor = FetchDescriptor<SongVerse>(predicate: #Predicate { $0.order == 0 })
        for v in (try? modelContext.fetch(verseDescriptor)) ?? [] {
            guard let songID = v.song?.id else { continue }
            firstLines[songID] = String(v.text.prefix(120))
        }

        // Version counts per song — one pass over versions.
        var versionCounts: [UUID: Int] = [:]
        for ver in (try? modelContext.fetch(FetchDescriptor<SongVersion>())) ?? [] {
            guard let songID = ver.song?.id else { continue }
            versionCounts[songID, default: 0] += 1
        }

        var entries: [SongIndexEntry] = []
        var languages = Set<String>()
        let songs = (try? modelContext.fetch(FetchDescriptor<Song>())) ?? []
        entries.reserveCapacity(songs.count)
        for song in songs {
            autoreleasepool {
                let blobSource = song.searchText.isEmpty ? song.title : song.searchText
                if !song.language.isEmpty { languages.insert(song.language) }
                entries.append(SongIndexEntry(
                    id: song.id,
                    title: song.title,
                    author: song.author,
                    language: song.language,
                    songNumber: song.songNumber,
                    songbookName: song.songbook?.name ?? "",
                    collectionID: song.collection?.id,
                    collectionName: song.collection?.name ?? "",
                    versionCount: versionCounts[song.id] ?? 0,
                    hasMedia: song.mediaJSON != "[]" && !song.mediaJSON.isEmpty,
                    verified: song.verified,
                    modifiedDate: song.modifiedDate,
                    firstLine: firstLines[song.id] ?? "",
                    blob: searchFold(blobSource)
                ))
            }
        }
        let tokenIndex = SongTokenIndex.build(blobs: entries.map(\.blob))
        return SongsPayload(entries: entries, tokens: tokenIndex,
                            languages: languages.sorted())
    }

    func buildMediaAndSessions() -> (media: [MediaIndexEntry], sessions: [SessionIndexEntry]) {
        let media = ((try? modelContext.fetch(FetchDescriptor<MediaItem>())) ?? []).map {
            MediaIndexEntry(id: $0.id, name: $0.name, mediaType: $0.mediaType,
                            folded: searchFold($0.name))
        }
        let sessions = ((try? modelContext.fetch(FetchDescriptor<ServiceSchedule>())) ?? []).map {
            SessionIndexEntry(id: $0.id, name: $0.name, date: $0.date,
                              folded: searchFold($0.name))
        }
        return (media, sessions)
    }

    /// Verse full-text index for ONE translation (the active one) — ~31k rows,
    /// built once per module switch, off-main.
    func buildVerses(moduleID: UUID) -> (books: [BookIndexEntry], verses: [VerseIndexEntry]) {
        var d = FetchDescriptor<BibleModule>(predicate: #Predicate { $0.id == moduleID })
        d.fetchLimit = 1
        guard let module = (try? modelContext.fetch(d))?.first else { return ([], []) }

        var books: [BookIndexEntry] = []
        var verses: [VerseIndexEntry] = []
        for book in module.books.sorted(by: { $0.bookNumber < $1.bookNumber }) {
            books.append(BookIndexEntry(
                moduleID: moduleID, bookNumber: book.bookNumber, name: book.name,
                folded: searchFold(book.name),
                abbreviationFolded: searchFold(book.abbreviation),
                chapterCount: book.chapters.count
            ))
            autoreleasepool {
                for chapter in book.chapters {
                    for verse in chapter.verses {
                        verses.append(VerseIndexEntry(
                            moduleID: moduleID, bookNumber: book.bookNumber,
                            bookName: book.name, chapter: chapter.chapterNumber,
                            verse: verse.verseNumber, text: verse.text,
                            folded: searchFold(verse.text)
                        ))
                    }
                }
            }
        }
        return (books, verses)
    }
}

// MARK: - MainActor façade (what views read)

@Observable
final class SearchIndex {
    private(set) var songs: [SongIndexEntry] = []
    private(set) var songTokens: SongTokenIndex = .empty
    private(set) var availableLanguages: [String] = []
    private(set) var media: [MediaIndexEntry] = []
    private(set) var sessions: [SessionIndexEntry] = []
    private(set) var books: [BookIndexEntry] = []
    private(set) var verses: [VerseIndexEntry] = []
    private(set) var activeVerseModuleID: UUID?
    private(set) var isBuilding = false
    /// Bumps on every publish — cheap invalidation key for cached sort orders.
    private(set) var generation = 0

    @ObservationIgnored private var builder: SearchIndexBuilder?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var verseTask: Task<Void, Never>?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// Per-sort-key cached orderings of `songs` (indices) — computed lazily once
    /// per generation, so keystrokes never re-sort 60k rows.
    @ObservationIgnored private var sortCache: [SongSortKey: [Int32]] = [:]

    // MARK: Lifecycle

    /// Idempotent — call once from the app root.
    func configure(container: ModelContainer) {
        guard builder == nil else { return }
        builder = SearchIndexBuilder(modelContainer: container)
        observer = NotificationCenter.default.addObserver(
            forName: .libraryDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }
        scheduleRebuild(after: .zero)
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Debounced full background rebuild (imports fire many change events).
    func scheduleRebuild(after delay: Duration = .seconds(1)) {
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.rebuildNow()
        }
    }

    func rebuildNow() async {
        guard let builder else { return }
        isBuilding = true
        let songsPayload = await builder.buildSongs()
        let extra = await builder.buildMediaAndSessions()
        songs = songsPayload.entries
        songTokens = songsPayload.tokens
        availableLanguages = songsPayload.languages
        media = extra.media
        sessions = extra.sessions
        sortCache.removeAll()
        generation += 1
        isBuilding = false
        // The verse index follows the active module across rebuilds.
        if let moduleID = activeVerseModuleID { indexVerses(moduleID: moduleID, force: true) }
    }

    /// Build (or reuse) the full-text verse index for the active translation.
    func indexVerses(moduleID: UUID, force: Bool = false) {
        guard force || moduleID != activeVerseModuleID else { return }
        activeVerseModuleID = moduleID
        verseTask?.cancel()
        verseTask = Task { [weak self] in
            guard let builder = self?.builder else { return }
            let payload = await builder.buildVerses(moduleID: moduleID)
            guard !Task.isCancelled, self?.activeVerseModuleID == moduleID else { return }
            self?.books = payload.books
            self?.verses = payload.verses
            self?.generation += 1
        }
    }

    // MARK: Queries (fast, MainActor, no SwiftData)

    /// Ranked song search: title-prefix hits first, then title contains, then
    /// blob (lyrics/author) matches. `limit: 0` = unlimited (library browser).
    func searchSongs(_ query: String, limit: Int = 0) -> [SongIndexEntry] {
        let toks = searchTokens(query)
        guard !toks.isEmpty else { return limit > 0 ? Array(songs.prefix(limit)) : songs }
        guard let hits = songTokens.match(queryTokens: toks) else { return [] }
        let folded = toks.joined(separator: " ")
        var prefix: [SongIndexEntry] = [], titleHit: [SongIndexEntry] = [], rest: [SongIndexEntry] = []
        for i in hits {
            let e = songs[Int(i)]
            let t = searchFold(e.title)
            if t.hasPrefix(folded) { prefix.append(e) }
            else if toks.allSatisfy({ t.contains($0) }) { titleHit.append(e) }
            else { rest.append(e) }
        }
        prefix.sort { $0.title < $1.title }
        titleHit.sort { $0.title < $1.title }
        rest.sort { $0.title < $1.title }
        let ranked = prefix + titleHit + rest
        return limit > 0 ? Array(ranked.prefix(limit)) : ranked
    }

    /// The library browser's ordering for a sort key — cached per generation.
    func sortedOrder(for key: SongSortKey) -> [Int32] {
        if let cached = sortCache[key] { return cached }
        let idx = Array(Int32(0) ..< Int32(songs.count))
        let order: [Int32]
        switch key {
        case .title:
            order = idx.sorted { songs[Int($0)].title.localizedStandardCompare(songs[Int($1)].title) == .orderedAscending }
        case .author:
            order = idx.sorted { songs[Int($0)].author.localizedStandardCompare(songs[Int($1)].author) == .orderedAscending }
        case .songbook:
            order = idx.sorted {
                let a = songs[Int($0)].songbookName.isEmpty ? "\u{10FFFF}" : songs[Int($0)].songbookName
                let b = songs[Int($1)].songbookName.isEmpty ? "\u{10FFFF}" : songs[Int($1)].songbookName
                return a.localizedStandardCompare(b) == .orderedAscending
            }
        case .language:
            order = idx.sorted {
                let c = songs[Int($0)].language.localizedStandardCompare(songs[Int($1)].language)
                return c == .orderedSame
                    ? songs[Int($0)].title.localizedStandardCompare(songs[Int($1)].title) == .orderedAscending
                    : c == .orderedAscending
            }
        case .recent:
            order = idx.sorted { songs[Int($0)].modifiedDate > songs[Int($1)].modifiedDate }
        }
        sortCache[key] = order
        return order
    }

    func searchVerses(_ query: String, limit: Int = 12) -> [VerseIndexEntry] {
        let folded = searchFold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard folded.count >= 3 else { return [] }
        var out: [VerseIndexEntry] = []
        for v in verses where v.folded.contains(folded) {
            out.append(v)
            if out.count >= limit { break }
        }
        return out
    }

    func searchMedia(_ query: String, limit: Int = 6) -> [MediaIndexEntry] {
        let folded = searchFold(query)
        guard !folded.isEmpty else { return [] }
        return Array(media.filter { $0.folded.contains(folded) }.prefix(limit))
    }

    func searchSessions(_ query: String, limit: Int = 6) -> [SessionIndexEntry] {
        let folded = searchFold(query)
        guard !folded.isEmpty else { return [] }
        return Array(sessions.filter { $0.folded.contains(folded) }.prefix(limit))
    }
}
