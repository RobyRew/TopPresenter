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
import CoreData
import Observation
import Synchronization

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
    /// Stable history key (HistoryStore.songKey) — palette popularity ranking.
    let songKey: String
    /// The collection's `sourceFormat` — how this song got here ("manual" for
    /// one written in the app, an importer's name otherwise). Carried on the
    /// projection so ranking never has to fault the collection per row.
    let sourceFormat: String
    /// Host of the page this song was scraped from, "" when it has none.
    /// Distinguishes "from a website" from "typed in here" for ranking.
    let webHost: String
    /// `searchFold(title)`, computed once here rather than per hit per
    /// keystroke in the ranker.
    let foldedTitle: String
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

nonisolated struct BookIndexEntry: Sendable, Codable {
    let moduleID: UUID
    let bookNumber: Int
    let name: String
    let folded: String
    let abbreviationFolded: String
    let chapterCount: Int
    /// chapterNumber → highest verse number — lets the reference parser reject
    /// or clamp impossible verses ("Apocalipsa 22:420").
    var verseCounts: [Int: Int] = [:]
}

nonisolated struct VerseIndexEntry: Sendable, Codable {
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
nonisolated struct TokenIndex: Sendable, Codable {
    let tokens: [String]
    let postings: [[Int32]]

    static let empty = TokenIndex(tokens: [], postings: [])

    static func build(blobs: [String]) -> TokenIndex {
        // Chunked across cores. The work is a pure function of each blob, so
        // each chunk builds its own token → postings map; chunks are contiguous
        // ranges in order, so concatenating a token's postings chunk by chunk
        // keeps them ascending, which `match` relies on. Single-threaded this
        // measured 8.3 s for 40k songs (27 MB of lyrics) after the tokeniser
        // fix, 13.4 s before it.
        let cores = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
        let chunkCount = blobs.count < 2_000 ? 1 : cores
        let chunkSize = (blobs.count + chunkCount - 1) / max(chunkCount, 1)
        let slots = Mutex<[[String: [Int32]]]>(Array(repeating: [:], count: chunkCount))
        DispatchQueue.concurrentPerform(iterations: chunkCount) { c in
            let start = c * chunkSize
            let end = min(start + chunkSize, blobs.count)
            guard start < end else { return }
            var map: [String: [Int32]] = [:]
            map.reserveCapacity((end - start) * 8)
            for i in start..<end {
                for tok in tokens(in: blobs[i]) { map[tok, default: []].append(Int32(i)) }
            }
            slots.withLock { $0[c] = map }
        }
        let partials = slots.withLock { $0 }
        var merged = partials[0]
        for c in 1..<partials.count {
            for (tok, ids) in partials[c] { merged[tok, default: []].append(contentsOf: ids) }
        }
        let sorted = merged.keys.sorted()
        return TokenIndex(tokens: sorted, postings: sorted.map { merged[$0]! })
    }

    /// The tokens one blob contributes — the ONE tokeniser, used by `build`,
    /// by the incremental swap and by `searchTokens`, so an edit and a
    /// rebuild cannot disagree about what a word is.
    ///
    /// Walks UNICODE SCALARS, not `Character`s. Blobs are already folded
    /// (lowercased, diacritics stripped), so grapheme clusters are single
    /// scalars and the `Character` walk bought nothing — but it cost grapheme
    /// segmentation and a Unicode property lookup per glyph. Building the index
    /// over 27 MB of lyrics measured 13.4 s that way.
    ///
    /// Single letters are noise, but single DIGITS are real content (songbook
    /// numbers, "Cântarea 5") — those are kept.
    static func tokens(in blob: String) -> Set<String> {
        var out = Set<String>()
        var current: [UInt8] = []
        current.reserveCapacity(24)
        @inline(__always) func flush() {
            defer { current.removeAll(keepingCapacity: true) }
            guard !current.isEmpty else { return }
            if current.count == 1, !(current[0] >= 48 && current[0] <= 57) { return }
            out.insert(String(decoding: current, as: UTF8.self))
        }
        for scalar in blob.unicodeScalars {
            let v = scalar.value
            // ASCII fast path covers folded text almost entirely.
            let isWord: Bool
            if v < 128 {
                isWord = (v >= 48 && v <= 57) || (v >= 97 && v <= 122) || (v >= 65 && v <= 90)
            } else {
                isWord = scalar.properties.isAlphabetic || scalar.properties.numericType != nil
            }
            if isWord {
                current.append(contentsOf: scalar.utf8)
            } else {
                flush()
            }
        }
        flush()
        return out
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

    /// Entry indices whose blob contains EXACTLY `token`.
    func candidates(exact token: String) -> Set<Int32> {
        guard !tokens.isEmpty, !token.isEmpty else { return [] }
        var lo = 0, hi = tokens.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if tokens[mid] < token { lo = mid + 1 } else { hi = mid }
        }
        guard lo < tokens.count, tokens[lo] == token else { return [] }
        return Set(postings[lo])
    }

    /// This index with ONE entry's tokens swapped: whatever `oldBlob` put in
    /// the postings for `entry` comes out, whatever `newBlob` produces goes in.
    ///
    /// Editing a song used to rebuild the whole index — every song row, every
    /// version, every first verse, and a full `build` over the entire library —
    /// measured at 11.7 s for 6 000 songs, and it contended the store with
    /// whatever the operator did next. Swapping one entry touches only the
    /// tokens that actually changed; the rest of the table is shared
    /// copy-on-write.
    ///
    /// Postings stay sorted ascending, as `build` leaves them. An `entry` equal
    /// to `postings`' entry count is an APPEND (a new song); `oldBlob` is then
    /// "". Deleting is not expressed here — indices are positional, and
    /// removing one would shift every posting after it — so a delete takes the
    /// full rebuild.
    func replacing(entry: Int32, oldBlob: String, newBlob: String) -> TokenIndex {
        let before = Self.tokens(in: oldBlob)
        let after = Self.tokens(in: newBlob)
        guard before != after else { return self }
        var tokens = self.tokens
        var postings = self.postings

        for tok in before.subtracting(after) {
            // Always the LOCAL table: each removal shifts what follows it.
            guard let j = Self.find(tok, in: tokens) else { continue }
            postings[j].removeAll { $0 == entry }
            if postings[j].isEmpty {
                tokens.remove(at: j)
                postings.remove(at: j)
            }
        }
        for tok in after.subtracting(before) {
            if let j = Self.find(tok, in: tokens) {
                let at = postings[j].firstIndex { $0 >= entry } ?? postings[j].count
                if at < postings[j].count, postings[j][at] == entry { continue }
                postings[j].insert(entry, at: at)
            } else {
                var lo = 0, hi = tokens.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if tokens[mid] < tok { lo = mid + 1 } else { hi = mid }
                }
                tokens.insert(tok, at: lo)
                postings.insert([entry], at: lo)
            }
        }
        return TokenIndex(tokens: tokens, postings: postings)
    }

    private static func find(_ tok: String, in table: [String]) -> Int? {
        var lo = 0, hi = table.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if table[mid] < tok { lo = mid + 1 } else { hi = mid }
        }
        return lo < table.count && table[lo] == tok ? lo : nil
    }

    /// Query semantics per token: NUMBERS match exactly ("matei 1 2" must not
    /// pull every song quoting "Matei 28:19" because 1⊂19, 2⊂28), words match
    /// by prefix.
    func candidates(for token: String) -> Set<Int32> {
        token.allSatisfy(\.isNumber) ? candidates(exact: token) : candidates(prefix: token)
    }

    /// AND across query tokens. Empty query → nil (no filter).
    func match(queryTokens: [String]) -> Set<Int32>? {
        guard !queryTokens.isEmpty else { return nil }
        var result: Set<Int32>? = nil
        for tok in queryTokens {
            let c = candidates(for: tok)
            result = result.map { $0.intersection(c) } ?? c
            if result?.isEmpty == true { return result }
        }
        return result
    }

    /// Typo tolerance: entry indices with a token whose PREFIX is within
    /// `maxDistance` edits of `token` ("amaizng" → "amazing", "grce" → "grace").
    /// Linear vocabulary scan with a banded early-exit DP — run OFF-main only.
    func fuzzyCandidates(token: String, maxDistance: Int) -> Set<Int32> {
        guard maxDistance > 0, !tokens.isEmpty else { return [] }
        let q = token.unicodeScalars.map(\.value)
        guard q.count > maxDistance else { return [] }
        var out = Set<Int32>()
        for (ti, t) in tokens.enumerated() {
            // Prefix semantics: only the first count+maxDistance scalars matter.
            guard t.count >= q.count - maxDistance else { continue }
            let tScalars = t.unicodeScalars.prefix(q.count + maxDistance).map(\.value)
            if Self.prefixDistanceWithin(q, tScalars, maxDistance) {
                out.formUnion(postings[ti])
            }
        }
        return out
    }

    /// True when SOME prefix of `t` is within `d` edits of `q` (Levenshtein DP
    /// over dp[q-consumed][t-consumed]; answer = min of the last row).
    static func prefixDistanceWithin(_ q: [UInt32], _ t: [UInt32], _ d: Int) -> Bool {
        let m = q.count, n = t.count
        guard n > 0 else { return m <= d }
        var prev = Array(0...n)
        var cur = [Int](repeating: 0, count: n + 1)
        for i in 1...m {
            cur[0] = i
            var rowMin = i
            for j in 1...n {
                let cost = q[i - 1] == t[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > d { return false }
            swap(&prev, &cur)
        }
        return prev.min().map { $0 <= d } ?? false
    }

    /// Allowed edit distance per query-token length (short tokens never fuzz).
    static func fuzzyDistance(for token: String) -> Int {
        switch token.count {
        case ..<4: return 0
        case 4...6: return 1
        default: return 2
        }
    }
}

// MARK: - Folding

nonisolated func searchFold(_ s: String) -> String {
    // `folding(options:)` is Foundation: the String it returns is backed by an
    // NSString, and every later comparison, prefix test or `contains` on it
    // crosses the bridge. Folded titles and blobs are compared hundreds of
    // thousands of times per keystroke, so they are made native here, once.
    var out = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    out.makeContiguousUTF8()
    return out
}

/// Query tokens, in the order typed. Same word rule as the index (letters and
/// digits, on unicode scalars) — a query must split exactly the way the blobs
/// it is matched against did, or a hyphenated title becomes unfindable.
///
/// Unlike the index, single letters are KEPT: the palette treats a typed "a"
/// as a prefix, and `TokenIndex.candidates(prefix:)` handles it.
nonisolated func searchTokens(_ query: String) -> [String] {
    var out: [String] = []
    var current: [UInt8] = []
    func flush() {
        if !current.isEmpty { out.append(String(decoding: current, as: UTF8.self)) }
        current.removeAll(keepingCapacity: true)
    }
    for scalar in searchFold(query).unicodeScalars {
        let v = scalar.value
        let isWord = v < 128
            ? (v >= 48 && v <= 57) || (v >= 97 && v <= 122) || (v >= 65 && v <= 90)
            : (scalar.properties.isAlphabetic || scalar.properties.numericType != nil)
        if isWord { current.append(contentsOf: scalar.utf8) } else { flush() }
    }
    flush()
    return out
}

// MARK: - Palette search (pure + Sendable — runs in a detached task)

/// Immutable capture of everything the ⌘K palette searches. Arrays are CoW —
/// taking a snapshot is O(1); the detached query never touches the MainActor.
nonisolated struct PaletteSnapshot: Sendable {
    let songs: [SongIndexEntry]
    let songTokens: TokenIndex
    let verses: [VerseIndexEntry]
    let verseTokens: TokenIndex
    let media: [MediaIndexEntry]
    let sessions: [SessionIndexEntry]
    let books: [BookIndexEntry]
    /// songKey → distinct presentation sessions (HistoryStore) — church
    /// staples rank above never-presented songs at equal match quality.
    let presentCounts: [String: Int]
    /// The operator's band order (Settings ▸ Cântece ▸ Prioritate).
    let priority: SongPriorityRules
    /// `priority.rank` for every song, packed (`band << 16 | position`),
    /// parallel to `songs`. Computed once per index generation — see
    /// `SearchIndex.rankTable`.
    let ranks: [Int32]
}

/// One query's results, pre-ranked and capped — the palette renders this state
/// verbatim (no recomputation in `body`). Display priority: reference →
/// song TITLE matches → verse full-text → songs matched only in lyrics/author
/// → media → sessions.
nonisolated struct PaletteHits: Sendable {
    let query: String
    /// Folded query tokens — used for match highlighting in rows.
    let tokens: [String]
    let reference: BibleReferenceMatch?
    /// Songs whose TITLE matches the query (prefix hits first).
    let songsByTitle: [SongIndexEntry]
    let songsByTitleTotal: Int
    /// Songs matched only in lyrics/author — ranked BELOW verses.
    let songsByContent: [SongIndexEntry]
    let songsByContentTotal: Int
    let verses: [VerseIndexEntry]
    let versesTotal: Int
    let media: [MediaIndexEntry]
    let mediaTotal: Int
    let sessions: [SessionIndexEntry]
    let sessionsTotal: Int

    static let none = PaletteHits(query: "", tokens: [], reference: nil,
                                  songsByTitle: [], songsByTitleTotal: 0,
                                  songsByContent: [], songsByContentTotal: 0,
                                  verses: [], versesTotal: 0,
                                  media: [], mediaTotal: 0,
                                  sessions: [], sessionsTotal: 0)
    var isEmpty: Bool {
        reference == nil && songsByTitle.isEmpty && songsByContent.isEmpty
            && verses.isEmpty && media.isEmpty && sessions.isEmpty
    }
}

/// Display order of the ⌘K sections for the module the palette was opened
/// from (AppState.SidebarItem rawValue; AppState is per-window ⇒ per-tab
/// behavior for free). In the Bible module verses outrank songs; Media and
/// Schedule float their own kind. The reference row stays pinned FIRST
/// everywhere — it only exists when the query parses as a reference, and then
/// it's always the best answer. DISPLAY order only; ranking inside each
/// section is untouched.
nonisolated func paletteSectionOrder(context: String) -> [String] {
    switch context {
    case "Bible":    return ["ref", "verses", "songs", "songContent", "media", "sessions"]
    case "Media":    return ["ref", "media", "songs", "verses", "songContent", "sessions"]
    case "Schedule": return ["ref", "sessions", "songs", "verses", "songContent", "media"]
    default:         return ["ref", "songs", "verses", "songContent", "media", "sessions"]
    }
}

nonisolated enum PaletteSearch {
    /// Full palette query: reference parse + ranked songs (typo-tolerant,
    /// popularity-boosted) + verse full-text (book-aware, typo-tolerant) +
    /// media + sessions. `carry` results per category travel to the UI (the
    /// palette shows a collapsed slice + „Arată mai multe"); each category
    /// also reports its TOTAL match count.
    static func run(_ rawQuery: String, in s: PaletteSnapshot, carry: Int = 50) -> PaletteHits {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .none }
        let toks = searchTokens(trimmed)
        let folded = searchFold(trimmed)
        let songs = rankedSongs(toks, in: s, carry: carry)
        let verses = verseHits(folded, tokens: toks, in: s, carry: carry)
        let mediaAll = s.media.filter { $0.folded.contains(folded) }
        let sessionsAll = s.sessions.filter { $0.folded.contains(folded) }
        return PaletteHits(
            query: trimmed,
            tokens: toks,
            reference: BibleReferenceParser.parse(trimmed, books: s.books),
            songsByTitle: songs.title, songsByTitleTotal: songs.titleTotal,
            songsByContent: songs.content, songsByContentTotal: songs.contentTotal,
            verses: verses.picked, versesTotal: verses.total,
            media: Array(mediaAll.prefix(carry)), mediaTotal: mediaAll.count,
            sessions: Array(sessionsAll.prefix(carry)), sessionsTotal: sessionsAll.count
        )
    }

    /// AND across query tokens; a WORD token with zero exact-prefix hits falls
    /// back to its fuzzy candidates so one typo doesn't blank the whole search.
    /// Numeric tokens never fuzz — "12" must not drift to "13".
    static func matchTokens(_ toks: [String], index: TokenIndex) -> Set<Int32>? {
        guard !toks.isEmpty else { return nil }
        var result: Set<Int32>? = nil
        for tok in toks {
            var c = index.candidates(for: tok)
            if c.isEmpty, !tok.allSatisfy(\.isNumber) {
                c = index.fuzzyCandidates(token: tok, maxDistance: TokenIndex.fuzzyDistance(for: tok))
            }
            result = result.map { $0.intersection(c) } ?? c
            if result?.isEmpty == true { return result }
        }
        return result
    }

    /// Song hits in three relevance buckets: title-PREFIX, title-contains, and
    /// matched only in lyrics/author. Inside each bucket: most-often presented
    /// first (HistoryStore counts), then alphabetical.
    ///
    /// Shared with the Songs library browser, whose own search used to be a bare
    /// AND-match rendered in alphabetical order — no typo tolerance, no
    /// relevance, no popularity — so the same query ranked differently depending
    /// on which search box it was typed into.
    static func songBuckets(
        _ toks: [String], songs: [SongIndexEntry], tokens: TokenIndex,
        presentCounts: [String: Int], priority: SongPriorityRules = SongPriorityRules(isEnabled: false),
        ranks: [Int32]? = nil
    ) -> (prefix: [SongIndexEntry], titleHit: [SongIndexEntry], rest: [SongIndexEntry]) {
        guard !toks.isEmpty, let hits = matchTokens(toks, index: tokens) else { return ([], [], []) }
        let folded = toks.joined(separator: " ")

        // Everything the sort compares on is computed ONCE per hit, up front,
        // and the rank not even then: it is a function of the entry and the
        // rules, not of the query, so `ranks` carries it precomputed per index
        // generation. The first version called `priority.rank` inside the
        // comparator (≈140 000 folds per keystroke at 6k songs); the second
        // called it once per hit, which still folded twice per hit for every
        // song outside a songbook — 700 ms for a 22 000-hit query at 40k.
        // What gets SORTED is deliberately small: an index, two integers and
        // the one string the tie-break needs. Sorting the entries themselves —
        // seventeen fields, ten of them refcounted — meant every swap in a
        // 22 000-element sort retained and released ten Strings, which was
        // most of the 600 ms a common query cost at 40k songs. The entries
        // are looked up once, at the end, in final order.
        struct Keyed {
            let index: Int32
            let rank: Int32
            let popularity: Int32
            let foldedTitle: String
        }
        let table = ranks?.count == songs.count ? ranks : nil
        var prefix: [Keyed] = [], titleHit: [Keyed] = [], rest: [Keyed] = []
        for i in hits {
            let e = songs[Int(i)]
            let rank = table?[Int(i)] ?? SongPriorityRules.pack(priority.rank(e))
            let t = e.foldedTitle
            let k = Keyed(index: i, rank: rank,
                          popularity: Int32(clamping: presentCounts[e.songKey] ?? 0),
                          foldedTitle: t)
            if t.hasPrefix(folded) { prefix.append(k) }
            else if toks.allSatisfy({ t.contains($0) }) { titleHit.append(k) }
            else { rest.append(k) }
        }
        // Inside a relevance bucket: the operator's explicit band order first,
        // then how often the church has actually presented it, then the title.
        // Priority outranks popularity because one is configured and the other
        // is inferred — an operator who says "hymnal songs first" means it.
        // The final tie-break compares the FOLDED title: already lowercased and
        // stripped to (mostly) ASCII, so the comparison takes String's fast
        // path instead of Unicode collation. With no presentation history and
        // most hits in one band, nearly every comparison reaches this line —
        // ~330 000 of them for a 22 000-hit query.
        let order: (Keyed, Keyed) -> Bool = { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            if a.popularity != b.popularity { return a.popularity > b.popularity }
            return a.foldedTitle < b.foldedTitle
        }
        prefix.sort(by: order)
        titleHit.sort(by: order)
        rest.sort(by: order)
        return (prefix.map { songs[Int($0.index)] },
                titleHit.map { songs[Int($0.index)] },
                rest.map { songs[Int($0.index)] })
    }

    /// The same ranking as one ordered list — what a single-kind result list
    /// (the Songs tab) renders.
    static func rankedSongList(_ toks: [String], songs: [SongIndexEntry], tokens: TokenIndex,
                               presentCounts: [String: Int],
                               priority: SongPriorityRules = SongPriorityRules(isEnabled: false),
                               ranks: [Int32]? = nil
    ) -> [SongIndexEntry] {
        let b = songBuckets(toks, songs: songs, tokens: tokens,
                            presentCounts: presentCounts, priority: priority, ranks: ranks)
        return b.prefix + b.titleHit + b.rest
    }

    /// Splits song hits by WHERE they matched: title (prefix hits first, then
    /// title-contains) vs. lyrics/author only.
    private static func rankedSongs(
        _ toks: [String], in s: PaletteSnapshot, carry: Int
    ) -> (title: [SongIndexEntry], titleTotal: Int, content: [SongIndexEntry], contentTotal: Int) {
        let b = songBuckets(toks, songs: s.songs, tokens: s.songTokens,
                            presentCounts: s.presentCounts, priority: s.priority, ranks: s.ranks)
        let title = b.prefix + b.titleHit
        return (Array(title.prefix(carry)), title.count,
                Array(b.rest.prefix(carry)), b.rest.count)
    }

    /// A query token naming a Bible book → scope hint ("isus fapte" = Isus in
    /// Faptele Apostolilor), ANY token position. STRICT matching only (exact
    /// name/abbrev → name/abbrev prefix, shortest name wins) — never the
    /// reference parser's fuzzy fallback ("isus cant" must not hint Cântarea).
    /// All-numeric remainders are references — the parser owns those.
    static func bookHint(tokens: [String], books: [BookIndexEntry])
        -> (book: BookIndexEntry, remaining: [String])? {
        guard tokens.count >= 2, !books.isEmpty else { return nil }
        for (idx, tok) in tokens.enumerated() where !tok.allSatisfy(\.isNumber) {
            var matches = books.filter { $0.folded == tok || (!$0.abbreviationFolded.isEmpty && $0.abbreviationFolded == tok) }
            if matches.isEmpty, tok.count >= 3 {
                matches = books.filter { $0.folded.hasPrefix(tok) || $0.abbreviationFolded.hasPrefix(tok) }
            }
            guard let book = matches.min(by: { $0.folded.count < $1.folded.count }) else { continue }
            var remaining = tokens
            remaining.remove(at: idx)
            guard !remaining.isEmpty, !remaining.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
            return (book, remaining)
        }
        return nil
    }

    /// Verse full-text via the token index — two passes:
    ///  1. BOOK-SCOPED: a token naming a book scopes the remaining tokens to
    ///     that book; those verses rank FIRST.
    ///  2. GLOBAL: all tokens as text, phrase hits first, canonical order,
    ///     capped at 2 per book while filling (spread across books), then
    ///     relaxed so „Arată mai multe" still reaches everything carried.
    private static func verseHits(_ folded: String, tokens: [String],
                                  in s: PaletteSnapshot, carry: Int)
        -> (picked: [VerseIndexEntry], total: Int) {
        guard folded.count >= 3 else { return ([], 0) }

        var picked: [Int32] = []
        var pickedSet = Set<Int32>()
        var matchedUnion = Set<Int32>()

        func fill(_ ordered: [Int32], perBookCap: Int?) {
            var perBook: [Int: Int] = [:]
            for i in ordered {
                guard picked.count < carry else { return }
                guard !pickedSet.contains(i) else { continue }
                if let cap = perBookCap {
                    let book = s.verses[Int(i)].bookNumber
                    if perBook[book, default: 0] >= cap { continue }
                    perBook[book, default: 0] += 1
                }
                pickedSet.insert(i)
                picked.append(i)
            }
        }

        /// Phrase-containing hits first, then the rest — both in index
        /// (= canonical Bible) order.
        func phraseRanked(_ hits: Set<Int32>, phrase: String) -> [Int32] {
            var withPhrase: [Int32] = [], rest: [Int32] = []
            for i in hits.sorted() {
                if s.verses[Int(i)].folded.contains(phrase) { withPhrase.append(i) }
                else { rest.append(i) }
            }
            return withPhrase + rest
        }

        // Pass 1 — book-scoped.
        if let (book, remaining) = bookHint(tokens: tokens, books: s.books),
           let scoped = matchTokens(remaining, index: s.verseTokens) {
            let inBook = Set(scoped.filter { s.verses[Int($0)].bookNumber == book.bookNumber })
            matchedUnion.formUnion(inBook)
            fill(phraseRanked(inBook, phrase: remaining.joined(separator: " ")), perBookCap: nil)
        }

        // Pass 2 — global full-text.
        if let hits = matchTokens(tokens, index: s.verseTokens), !hits.isEmpty {
            matchedUnion.formUnion(hits)
            let ordered = phraseRanked(hits, phrase: folded)
            fill(ordered, perBookCap: 2)
            fill(ordered, perBookCap: nil)
        }

        return (picked.map { s.verses[Int($0)] }, matchedUnion.count)
    }
}

// MARK: - Off-main builder

@ModelActor
actor SearchIndexBuilder {
    struct SongsPayload: Sendable {
        let entries: [SongIndexEntry]
        let tokens: TokenIndex
        let languages: [String]
    }

    /// Builds the whole song projection.
    ///
    /// Two paths. The Core Data one is what runs against a real library: it
    /// asks the store for COLUMNS — dictionary-result fetches with the
    /// relationships grouped or projected as object ids — so nothing is
    /// instantiated and nothing faults. The SwiftData walk below it is the
    /// fallback for in-memory stores (tests, previews), which have no file for
    /// a second coordinator to open.
    ///
    /// Why it had to change: the SwiftData walk read `v.song?.id` per verse,
    /// `ver.song?.id` per version and `song.songbook`/`song.collection` per
    /// song — a fault each, tens of thousands of queries hidden behind four
    /// fetches. On a 40 000-song library that measured **73 s**, on every
    /// launch, every import, and (until the incremental path) every edit.
    /// `relationshipKeyPathsForPrefetching` made it SLOWER (19 s → 25 s):
    /// SwiftData materialises the full related object per row.
    func buildSongs() -> SongsPayload {
        if let payload = try? buildSongsFromColumns() { return payload }
        return buildSongsByWalking()
    }

    /// Lazily opened; the bridge stack is reused across rebuilds.
    private var columnContext: NSManagedObjectContext?

    func buildSongsFromColumns() throws -> SongsPayload {
        let context: NSManagedObjectContext
        if let existing = columnContext {
            context = existing
        } else {
            let coordinator = try SwiftDataModelBridge.coordinator(for: modelContainer)
            let fresh = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            fresh.persistentStoreCoordinator = coordinator
            columnContext = fresh
            context = fresh
        }

        /// A dictionary fetch of `properties` (attribute names or to-one
        /// relationship names) plus the row's own object id under "oid".
        func rows(_ entity: String, _ properties: [String], predicate: NSPredicate? = nil,
                  groupBy: [String]? = nil, extra: [NSExpressionDescription] = []) throws -> [NSDictionary] {
            let request = NSFetchRequest<NSDictionary>(entityName: entity)
            request.resultType = .dictionaryResultType
            request.predicate = predicate
            request.includesPendingChanges = false
            var fetch: [Any] = properties
            if groupBy == nil {
                let oid = NSExpressionDescription()
                oid.name = "oid"
                oid.expression = NSExpression.expressionForEvaluatedObject()
                oid.expressionResultType = .objectIDAttributeType
                fetch.append(oid)
            }
            fetch.append(contentsOf: extra)
            request.propertiesToFetch = fetch
            request.propertiesToGroupBy = groupBy
            return try context.fetch(request)
        }

        var payload: SongsPayload?
        var failure: Error?
        context.performAndWait {
            do {
                // Small lookups first.
                var songbookNames: [NSManagedObjectID: String] = [:]
                for r in try rows("Songbook", ["name"]) {
                    if let oid = r["oid"] as? NSManagedObjectID { songbookNames[oid] = r["name"] as? String ?? "" }
                }
                struct Col { let id: UUID?; let name: String; let source: String }
                var collections: [NSManagedObjectID: Col] = [:]
                for r in try rows("SongCollection", ["id", "name", "sourceFormat"]) {
                    if let oid = r["oid"] as? NSManagedObjectID {
                        collections[oid] = Col(id: r["id"] as? UUID, name: r["name"] as? String ?? "",
                                               source: r["sourceFormat"] as? String ?? "")
                    }
                }

                // Version counts: ONE grouped query instead of a fault per version.
                let count = NSExpressionDescription()
                count.name = "n"
                count.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "song")])
                count.expressionResultType = .integer64AttributeType
                var versionCounts: [NSManagedObjectID: Int] = [:]
                for r in try rows("SongVersion", ["song"], groupBy: ["song"], extra: [count]) {
                    if let oid = r["song"] as? NSManagedObjectID { versionCounts[oid] = (r["n"] as? Int) ?? 0 }
                }

                // First lines: the verse rows at order 0, with the song's id projected.
                var firstLines: [NSManagedObjectID: String] = [:]
                for r in try rows("SongVerse", ["song", "text"], predicate: NSPredicate(format: "order == 0")) {
                    if let oid = r["song"] as? NSManagedObjectID {
                        firstLines[oid] = String((r["text"] as? String ?? "").prefix(120))
                    }
                }

                // The songs themselves: every column the projection reads, plus
                // the two to-one relationships as object ids.
                let songRows = try rows("Song", [
                    "id", "title", "author", "language", "songNumber", "mediaJSON", "verified",
                    "modifiedDate", "searchText", "ccliNumber", "extensionsJSON", "songbook", "collection",
                ])
                var entries: [SongIndexEntry] = []
                entries.reserveCapacity(songRows.count)
                var languages = Set<String>()
                for r in songRows {
                    guard let id = r["id"] as? UUID, let oid = r["oid"] as? NSManagedObjectID else { continue }
                    let title = r["title"] as? String ?? ""
                    let language = r["language"] as? String ?? ""
                    if !language.isEmpty { languages.insert(language) }
                    let searchText = r["searchText"] as? String ?? ""
                    let mediaJSON = r["mediaJSON"] as? String ?? "[]"
                    let col = (r["collection"] as? NSManagedObjectID).flatMap { collections[$0] }
                    let source = col?.source ?? ""
                    entries.append(SongIndexEntry(
                        id: id,
                        title: title,
                        author: r["author"] as? String ?? "",
                        language: language,
                        songNumber: r["songNumber"] as? String ?? "",
                        songbookName: (r["songbook"] as? NSManagedObjectID).flatMap { songbookNames[$0] } ?? "",
                        collectionID: col?.id,
                        collectionName: col?.name ?? "",
                        versionCount: versionCounts[oid] ?? 0,
                        hasMedia: mediaJSON != "[]" && !mediaJSON.isEmpty,
                        verified: r["verified"] as? Bool ?? false,
                        modifiedDate: r["modifiedDate"] as? Date ?? .distantPast,
                        firstLine: firstLines[oid] ?? "",
                        blob: searchFold(searchText.isEmpty ? title : searchText),
                        songKey: HistoryStore.songKey(ccli: r["ccliNumber"] as? String ?? "",
                                                      title: title, source: source),
                        sourceFormat: source,
                        webHost: Song.webURL(inExtensionsJSON: r["extensionsJSON"] as? String ?? "")?.host() ?? "",
                        foldedTitle: searchFold(title)
                    ))
                }
                payload = SongsPayload(entries: entries,
                                       tokens: TokenIndex.build(blobs: entries.map(\.blob)),
                                       languages: languages.sorted())
            } catch {
                failure = error
            }
        }
        if let failure { throw failure }
        return payload!
    }

    /// The original walk — kept for stores the bridge cannot open.
    func buildSongsByWalking() -> SongsPayload {
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
        // NO relationshipKeyPathsForPrefetching here: measured on a 40k-song
        // library it made every phase SLOWER (19 s → 25 s, 24 s → 34 s) —
        // SwiftData materialises the full related object per row. The faults
        // are the cheaper of the two bad options; the real fix is below.
        let songs = (try? modelContext.fetch(FetchDescriptor<Song>())) ?? []
        entries.reserveCapacity(songs.count)
        for song in songs {
            autoreleasepool {
                if !song.language.isEmpty { languages.insert(song.language) }
                entries.append(Self.project(song, firstLine: firstLines[song.id] ?? "",
                                            versionCount: versionCounts[song.id] ?? 0))
            }
        }
        let tokenIndex = TokenIndex.build(blobs: entries.map(\.blob))
        return SongsPayload(entries: entries, tokens: tokenIndex,
                            languages: languages.sorted())
    }

    /// ONE song's projection — for the incremental path, so an edit updates one
    /// entry instead of rebuilding the library. nil when the song is gone.
    ///
    /// Reads the song's own relationships directly (a handful of faults for one
    /// row), which is exactly the cost `buildSongs` avoids by batching.
    func buildSong(id: UUID) -> SongIndexEntry? {
        var d = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        guard let song = (try? modelContext.fetch(d))?.first else { return nil }
        let firstLine = song.sortedVerses.first.map { String($0.text.prefix(120)) } ?? ""
        return Self.project(song, firstLine: firstLine, versionCount: song.versions.count)
    }

    /// The one place a `Song` becomes a `SongIndexEntry`. Both the full build
    /// and the single-song update go through here, so they cannot drift.
    nonisolated static func project(_ song: Song, firstLine: String, versionCount: Int) -> SongIndexEntry {
        let blobSource = song.searchText.isEmpty ? song.title : song.searchText
        let source = song.collection?.sourceFormat ?? ""
        return SongIndexEntry(
            id: song.id,
            title: song.title,
            author: song.author,
            language: song.language,
            songNumber: song.songNumber,
            songbookName: song.songbook?.name ?? "",
            collectionID: song.collection?.id,
            collectionName: song.collection?.name ?? "",
            versionCount: versionCount,
            hasMedia: song.mediaJSON != "[]" && !song.mediaJSON.isEmpty,
            verified: song.verified,
            modifiedDate: song.modifiedDate,
            firstLine: firstLine,
            blob: searchFold(blobSource),
            songKey: HistoryStore.songKey(ccli: song.ccliNumber, title: song.title, source: source),
            sourceFormat: source,
            webHost: song.webURL?.host() ?? "",
            foldedTitle: searchFold(song.title)
        )
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
    /// built once per module switch.
    ///
    /// `buildVerses` says "off-main" and was not: a sample of a cold module
    /// switch put 10 714 of 12 944 MAIN-THREAD samples in here, 9 758 of them
    /// sorting verses. Being on a `@ModelActor` does not put a `nonisolated`
    /// callee anywhere in particular — the caller's executor does, and the
    /// chain starts on `@MainActor`. `detachedBuildVerses` is the one that
    /// actually runs elsewhere; this stays for callers already on the actor.
    func buildVerses(moduleID: UUID) -> (books: [BookIndexEntry], verses: [VerseIndexEntry], tokens: TokenIndex) {
        Self.buildVerses(moduleID: moduleID, in: modelContext)
    }

    /// The same walk on a context of its own, off every actor.
    ///
    /// Everything it returns is already `Sendable` — `BookIndexEntry`,
    /// `VerseIndexEntry` and `TokenIndex` are plain `Codable` values, which is
    /// why this needed no new types, only a place to run.
    nonisolated static func detachedBuildVerses(
        moduleID: UUID, container: ModelContainer
    ) async -> (books: [BookIndexEntry], verses: [VerseIndexEntry], tokens: TokenIndex) {
        await Task.detached(priority: .userInitiated) {
            buildVerses(moduleID: moduleID, in: ModelContext(container))
        }.value
    }

    nonisolated static func buildVerses(
        moduleID: UUID, in modelContext: ModelContext
    ) -> (books: [BookIndexEntry], verses: [VerseIndexEntry], tokens: TokenIndex) {
        var d = FetchDescriptor<BibleModule>(predicate: #Predicate { $0.id == moduleID })
        d.fetchLimit = 1
        guard let module = (try? modelContext.fetch(d))?.first else { return ([], [], .empty) }

        var books: [BookIndexEntry] = []
        var verses: [VerseIndexEntry] = []
        for book in module.books.sorted(by: { $0.bookNumber < $1.bookNumber }) {
            var verseCounts: [Int: Int] = [:]
            autoreleasepool {
                // Relationship arrays are UNORDERED — sort, so index position
                // IS canonical Bible order (ranking tie-breaks depend on it).
                for chapter in book.chapters.sorted(by: { $0.chapterNumber < $1.chapterNumber }) {
                    let sortedVerses = chapter.verses.sorted(by: { $0.verseNumber < $1.verseNumber })
                    verseCounts[chapter.chapterNumber] = sortedVerses.last?.verseNumber ?? 0
                    for verse in sortedVerses {
                        verses.append(VerseIndexEntry(
                            moduleID: moduleID, bookNumber: book.bookNumber,
                            bookName: book.name, chapter: chapter.chapterNumber,
                            verse: verse.verseNumber, text: verse.text,
                            folded: searchFold(verse.text)
                        ))
                    }
                }
            }
            books.append(BookIndexEntry(
                moduleID: moduleID, bookNumber: book.bookNumber, name: book.name,
                folded: searchFold(book.name),
                abbreviationFolded: searchFold(book.abbreviation),
                chapterCount: book.chapters.count,
                verseCounts: verseCounts
            ))
        }
        return (books, verses, TokenIndex.build(blobs: verses.map(\.folded)))
    }
}

// MARK: - MainActor façade (what views read)

@Observable
final class SearchIndex {
    private(set) var songs: [SongIndexEntry] = []
    private(set) var songTokens: TokenIndex = .empty
    private(set) var availableLanguages: [String] = []
    private(set) var media: [MediaIndexEntry] = []
    private(set) var sessions: [SessionIndexEntry] = []
    private(set) var books: [BookIndexEntry] = []
    private(set) var verses: [VerseIndexEntry] = []
    private(set) var verseTokens: TokenIndex = .empty
    private(set) var activeVerseModuleID: UUID?
    private(set) var isBuilding = false
    private(set) var isIndexingVerses = false
    /// songKey → distinct presentation sessions — palette popularity ranking.
    private(set) var presentCounts: [String: Int] = [:]
    /// Bumps on every publish — cheap invalidation key for cached sort orders.
    private(set) var generation = 0

    @ObservationIgnored private var builder: SearchIndexBuilder?
    /// Kept so the verse walk can be handed a context of its own, off any actor.
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private weak var historyStore: HistoryStore?
    @ObservationIgnored private var rebuildTask: Task<Void, Never>?
    @ObservationIgnored private var verseTask: Task<Void, Never>?
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    /// Per-sort-key cached orderings of `songs` (indices) — computed lazily once
    /// per generation, so keystrokes never re-sort 60k rows.
    @ObservationIgnored private var sortCache: [SongSortKey: [Int32]] = [:]
    /// In-memory LRU of built verse indexes (newest first) — switching back to
    /// a recently used translation publishes instantly, no disk, no SwiftData.
    @ObservationIgnored private var versePayloadLRU: [VerseIndexCache] = []
    private static let versePayloadLRUCap = 3

    // MARK: Lifecycle

    /// Idempotent — call once from the app root.
    func configure(container: ModelContainer, history: HistoryStore? = nil) {
        guard builder == nil else { return }
        builder = SearchIndexBuilder(modelContainer: container)
        self.container = container
        historyStore = history
        observer = NotificationCenter.default.addObserver(
            forName: .libraryDidChange, object: nil, queue: .main
        ) { [weak self] note in
            let kinds = note.userInfo?[Notification.Name.changedKindsKey] as? [String]
            let ids = note.userInfo?[Notification.Name.changedSongIDsKey] as? [UUID]
            MainActor.assumeIsolated {
                self?.scheduleRebuild(changed: kinds.map(Set.init), songIDs: ids.map(Set.init))
            }
        }
        scheduleRebuild(after: .zero)
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Kinds whose change has not been folded into the index yet.
    ///
    /// Coalesced across a debounce window: five notifications naming different
    /// kinds must rebuild the union of them, not just the last one's.
    @ObservationIgnored private var pendingKinds: Set<String>?
    /// Song ids named by the posts since the last rebuild, when EVERY song
    /// post named its ids. nil means at least one did not (an import batch, a
    /// bulk delete) and the songs need a full rebuild.
    @ObservationIgnored private var pendingSongIDs: Set<UUID>? = []
    /// Above this many named songs a full rebuild is cheaper than N single
    /// fetches — and a batch that size is an import, not an edit.
    private static let incrementalCap = 64

    /// Debounced background rebuild (imports fire many change events).
    ///
    /// `changed` is the kinds that actually changed; nil means "everything",
    /// which is what an un-annotated poster gets. Importing thirty Bibles used
    /// to re-walk all 9 643 SONGS afterwards, every time — the work was
    /// unconditional and had nothing to do with what was imported.
    ///
    /// `songIDs` names the songs a `.song` change touched. When every song
    /// post in the window names its ids, the rebuild is INCREMENTAL: those
    /// entries are re-projected and swapped in place. Editing one song used to
    /// re-walk the whole library (11.7 s at 6 000 songs) and contend the store
    /// with whatever the operator did next — that is what made a Bible verse
    /// step take fifteen seconds on a Sunday.
    func scheduleRebuild(after delay: Duration = .seconds(1), changed: Set<String>? = nil,
                         songIDs: Set<UUID>? = nil) {
        if let changed, pendingKinds != nil {
            pendingKinds?.formUnion(changed)
        } else {
            pendingKinds = changed
        }
        let touchesSongs = changed == nil || changed!.contains(ImportKind.song.rawValue)
        if touchesSongs {
            if let songIDs, pendingSongIDs != nil {
                pendingSongIDs!.formUnion(songIDs)
            } else {
                pendingSongIDs = nil   // an un-named song change: full rebuild
            }
        }
        rebuildTask?.cancel()
        rebuildTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.rebuildNow()
        }
    }

    func rebuildNow() async {
        guard let builder else { return }
        let changed = pendingKinds
        let namedSongs = pendingSongIDs
        pendingKinds = nil
        pendingSongIDs = []
        // Songs are the expensive projection; media and sessions are small.
        let songsChanged = changed == nil || changed!.contains(ImportKind.song.rawValue)
        let extrasChanged = changed == nil
            || !changed!.isDisjoint(with: [ImportKind.media.rawValue, ImportKind.session.rawValue])

        isBuilding = true
        var songsRebuiltFully = false
        if songsChanged {
            // Incremental only when the index already exists, every post named
            // its songs, and there are few enough of them to be edits.
            if !songs.isEmpty, let ids = namedSongs, !ids.isEmpty, ids.count <= Self.incrementalCap,
               await applyIncrementally(ids, using: builder) {
                // done in place
            } else {
                let songsPayload = await builder.buildSongs()
                songs = songsPayload.entries
                songTokens = songsPayload.tokens
                availableLanguages = songsPayload.languages
                songsRebuiltFully = true
            }
        }
        if extrasChanged {
            let extra = await builder.buildMediaAndSessions()
            media = extra.media
            sessions = extra.sessions
        }
        if let historyStore {
            presentCounts = Dictionary(uniqueKeysWithValues:
                historyStore.songSummaries().map { ($0.songKey, $0.timesPresented) })
        }
        sortCache.removeAll()
        generation += 1
        isBuilding = false
        // Spotlight mirrors the same projections — only worth re-pushing when
        // one of them actually moved. An incremental song update skips it: the
        // next full rebuild catches Spotlight up, and re-pushing 40k items for
        // one edit is the kind of work this path exists to avoid.
        if songsRebuiltFully || extrasChanged {
            SpotlightIndexer.reindex(songs: songs, sessions: sessions)
        }
        // NO verse re-index here: verses only change via bible import/delete
        // (import re-selects its module, delete goes through moduleDeleted).
        // Song edits fire .libraryDidChange constantly — re-walking 31k verse
        // rows on each one contended the store with the main thread (beachball).
    }

    /// Re-project the named songs and swap them into the published index.
    ///
    /// Returns false when something needs the full path instead — a song that
    /// was deleted (positional postings cannot lose an entry), or a song the
    /// index has never seen that is not simply new.
    private func applyIncrementally(_ ids: Set<UUID>, using builder: SearchIndexBuilder) async -> Bool {
        var position: [UUID: Int] = [:]
        for (i, e) in songs.enumerated() { position[e.id] = i }

        var updated = songs
        var tokens = songTokens
        var languages = Set(availableLanguages)
        for id in ids {
            guard let fresh = await builder.buildSong(id: id) else {
                // Deleted. The full rebuild is the honest answer.
                return false
            }
            if !fresh.language.isEmpty { languages.insert(fresh.language) }
            if let i = position[id] {
                tokens = tokens.replacing(entry: Int32(i), oldBlob: updated[i].blob, newBlob: fresh.blob)
                updated[i] = fresh
            } else {
                // A song created since the last build: append.
                tokens = tokens.replacing(entry: Int32(updated.count), oldBlob: "", newBlob: fresh.blob)
                updated.append(fresh)
            }
        }
        songs = updated
        songTokens = tokens
        availableLanguages = languages.sorted()
        return true
    }

    /// O(1) capture for the palette's detached query.
    func snapshot() -> PaletteSnapshot {
        let rules = SongPriorityStore.shared.rules
        return PaletteSnapshot(songs: songs, songTokens: songTokens,
                               verses: verses, verseTokens: verseTokens,
                               media: media, sessions: sessions, books: books,
                               presentCounts: presentCounts,
                               priority: rules, ranks: rankTable(for: rules))
    }

    @ObservationIgnored private var rankCache: (generation: Int, rules: SongPriorityRules, table: [Int32])?

    /// Every song's priority rank under `rules`, packed, parallel to `songs`.
    /// Cached until the index or the rules change — folding facet values is
    /// the expensive part of ranking, and it does not depend on the query.
    func rankTable(for rules: SongPriorityRules) -> [Int32] {
        if let c = rankCache, c.generation == generation, c.rules == rules { return c.table }
        let table = songs.map { SongPriorityRules.pack(rules.rank($0)) }
        rankCache = (generation, rules, table)
        return table
    }

    /// Point the verse index at a translation. Resolution order:
    /// in-memory LRU (instant) → disk cache (fast decode off-main, zero
    /// SwiftData) → ONE SwiftData build, then persisted to disk. The store is
    /// only ever walked once per module — the old per-switch rebuild contended
    /// with the main thread's display faults on the store coordinator, which
    /// was the version-switch beachball.
    func indexVerses(moduleID: UUID, force: Bool = false) {
        guard force || moduleID != activeVerseModuleID else { return }
        activeVerseModuleID = moduleID
        verseTask?.cancel()

        if force {
            versePayloadLRU.removeAll { $0.moduleID == moduleID }
            VerseIndexCache.delete(moduleID: moduleID)
        }
        if let hit = versePayloadLRU.first(where: { $0.moduleID == moduleID }) {
            publishVerses(hit)
            return
        }

        isIndexingVerses = true
        verseTask = Task { [weak self] in
            // 1. Disk cache — decoded detached: pure file IO, can't contend.
            let cached = await Task.detached(priority: .userInitiated) {
                VerseIndexCache.load(moduleID: moduleID)
            }.value
            guard !Task.isCancelled, self?.activeVerseModuleID == moduleID else { return }
            if let cached {
                self?.publishVerses(cached)
                return
            }
            // 2. First time for this module: build from SwiftData, persist.
            //    Detached, on a context of its own — going through the actor ran
            //    the whole walk on the main thread (see `detachedBuildVerses`).
            guard let container = self?.container else { return }
            let payload = await SearchIndexBuilder.detachedBuildVerses(
                moduleID: moduleID, container: container)
            guard !Task.isCancelled, self?.activeVerseModuleID == moduleID else { return }
            let cache = VerseIndexCache(moduleID: moduleID, books: payload.books,
                                        verses: payload.verses, tokens: payload.tokens)
            self?.publishVerses(cache)
            Task.detached(priority: .utility) { cache.save() }
        }
    }

    private func publishVerses(_ cache: VerseIndexCache) {
        books = cache.books
        verses = cache.verses
        verseTokens = cache.tokens
        isIndexingVerses = false
        generation += 1
        versePayloadLRU.removeAll { $0.moduleID == cache.moduleID }
        versePayloadLRU.insert(cache, at: 0)
        if versePayloadLRU.count > Self.versePayloadLRUCap {
            versePayloadLRU.removeLast(versePayloadLRU.count - Self.versePayloadLRUCap)
        }
    }

    /// A bible module was deleted: drop its caches; clear the published index
    /// if it was the active one (a re-import gets a NEW module UUID).
    func moduleDeleted(_ moduleID: UUID) {
        versePayloadLRU.removeAll { $0.moduleID == moduleID }
        VerseIndexCache.delete(moduleID: moduleID)
        if activeVerseModuleID == moduleID {
            verseTask?.cancel()
            activeVerseModuleID = nil
            books = []
            verses = []
            verseTokens = .empty
            isIndexingVerses = false
            generation += 1
        }
    }

    /// Advanced settings ▸ „Reindexează tot": wipe every cache (memory + disk
    /// + Spotlight via rebuild) and rebuild from the store.
    func reindexEverything(activeModuleID: UUID?) async {
        versePayloadLRU.removeAll()
        VerseIndexCache.deleteAll()
        await rebuildNow()
        if let activeModuleID { indexVerses(moduleID: activeModuleID, force: true) }
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
            let t = e.foldedTitle
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
