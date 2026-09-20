//
//  RealLibraryPerformanceTests.swift
//  TopPresenterTests
//
//  Timings against a COPY of a real library — the only test that answers
//  "did Sunday actually get better".
//

import Testing
import Foundation
import SwiftData
@testable import TopPresenter

/// Measures the paths a service actually exercises, on a real store.
///
/// Every other test in this target runs on a fixture of a few rows, which is the
/// right thing for correctness and useless for performance: the bugs this suite
/// exists to catch are the ones that only appear at 40k songs and 800k verses.
/// It opens the store named by `TP_REAL_STORE` — ALWAYS a copy, never the
/// library in the app container — and is skipped entirely when that variable is
/// unset, so CI and a plain `xcodebuild test` never see it.
///
/// Where the old code is measured, it is re-implemented INLINE, so the old and
/// new paths run against the same data in the same process. Checking out the
/// old commit would measure a different binary against a different row cache.
///
/// Run:
///   TEST_RUNNER_TP_REAL_STORE=/path/to/copy/default.store \
///   TEST_RUNNER_TP_PERF_OUT=/path/to/results.md \
///   xcodebuild test … -only-testing:TopPresenterTests/RealLibraryPerformanceTests
@Suite("Real library performance", .serialized)
@MainActor
struct RealLibraryPerformanceTests {

    nonisolated static var storeURL: URL? {
        ProcessInfo.processInfo.environment["TP_REAL_STORE"].map { URL(fileURLWithPath: $0) }
    }
    nonisolated static var outputURL: URL? {
        ProcessInfo.processInfo.environment["TP_PERF_OUT"].map { URL(fileURLWithPath: $0) }
    }

    // MARK: - Harness

    /// One timed measurement: several runs, the MEDIAN reported. A single run
    /// measures whatever the OS happened to be doing; the median does not.
    private struct Row {
        let name: String
        let median: Duration
        let runs: Int
        let note: String
    }

    private final class Report {
        var rows: [Row] = []
        var facts: [(String, String)] = []

        func add(_ name: String, runs: Int = 5, note: String = "",
                 _ body: () throws -> Void) rethrows {
            var samples: [Duration] = []
            for _ in 0..<runs {
                let clock = ContinuousClock()
                let elapsed = try clock.measure { try body() }
                samples.append(elapsed)
            }
            samples.sort()
            rows.append(Row(name: name, median: samples[samples.count / 2], runs: runs, note: note))
        }

        func addAsync(_ name: String, runs: Int = 3, note: String = "",
                      _ body: () async throws -> Void) async rethrows {
            var samples: [Duration] = []
            for _ in 0..<runs {
                let clock = ContinuousClock()
                let elapsed = try await clock.measure { try await body() }
                samples.append(elapsed)
            }
            samples.sort()
            rows.append(Row(name: name, median: samples[samples.count / 2], runs: runs, note: note))
        }

        func fact(_ k: String, _ v: String) { facts.append((k, v)) }

        var markdown: String {
            var out = "## Real library — measured\n\n"
            for (k, v) in facts { out += "- **\(k):** \(v)\n" }
            out += "\n| Path | median | runs | |\n|---|---:|---:|---|\n"
            for r in rows {
                out += "| \(r.name) | \(Self.format(r.median)) | \(r.runs) | \(r.note) |\n"
            }
            return out
        }

        static func format(_ d: Duration) -> String {
            let ms = Double(d.components.seconds) * 1000
                + Double(d.components.attoseconds) / 1e15
            if ms >= 1000 { return String(format: "%.2f s", ms / 1000) }
            if ms >= 10 { return String(format: "%.0f ms", ms) }
            if ms >= 1 { return String(format: "%.1f ms", ms) }
            return String(format: "%.0f µs", ms * 1000)
        }
    }

    private func openContainer(_ url: URL) throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                           configurations: [ModelConfiguration(url: url)])
    }

    // MARK: - The measurement

    @Test(.enabled(if: RealLibraryPerformanceTests.storeURL != nil))
    func measureEverythingASundayTouches() async throws {
        let url = try #require(Self.storeURL)
        let report = Report()

        // ---------------------------------------------------------------- open
        var container: ModelContainer!
        try report.add("Open the store", runs: 3) { container = try openContainer(url) }
        let context = ModelContext(container)

        let songCount = try context.fetchCount(FetchDescriptor<Song>())
        let verseCount = try context.fetchCount(FetchDescriptor<BibleVerse>())
        let moduleCount = try context.fetchCount(FetchDescriptor<BibleModule>())
        report.fact("Songs", "\(songCount)")
        report.fact("Bible modules / verses", "\(moduleCount) / \(verseCount)")

        // ------------------------------------------------------ song index build
        // What every un-annotated `.libraryDidChange` used to trigger — and what
        // the browser cannot show anything without.
        let builder = SearchIndexBuilder(modelContainer: container)
        var payload: SearchIndexBuilder.SongsPayload!
        await report.addAsync("Song index build (all songs)", runs: 3,
                              note: "was re-run after ANY library edit") {
            payload = await builder.buildSongs()
        }
        let entries = payload.entries
        let tokens = payload.tokens
        report.fact("Indexed songs", "\(entries.count)")

        // --------------------------------------------------------- list sweeps
        // The browser's ordering, as the index caches it per generation.
        let byTitle = Array(Int32(0) ..< Int32(entries.count)).sorted {
            entries[Int($0)].title.localizedStandardCompare(entries[Int($1)].title) == .orderedAscending
        }
        func sweep() -> [SongIndexEntry] {
            var out: [SongIndexEntry] = []
            out.reserveCapacity(entries.count)
            for i in byTitle { out.append(entries[Int(i)]) }
            return out
        }
        func group(_ list: [SongIndexEntry]) -> Int {
            var order: [String] = []
            var map: [String: [SongIndexEntry]] = [:]
            for e in list {
                let k = String(e.title.prefix(1)).uppercased()
                if map[k] == nil { order.append(k); map[k] = [] }
                map[k]?.append(e)
            }
            return order.count
        }
        report.add("Browser render — OLD (3 sweeps + group, per render)", runs: 5,
                   note: "ran on EVERY re-render, incl. selecting or pinning") {
            _ = sweep().isEmpty          // body:    filtered.isEmpty
            _ = sweep().count            // toolbar: filtered.count
            _ = group(sweep())           // list:    grouped → filtered
        }
        report.add("Browser render — NEW (1 sweep + group, per input change)", runs: 5,
                   note: "runs only when query/sort/filter/pins change") {
            _ = group(sweep())
        }

        // -------------------------------------------------------------- search
        let presentCounts: [String: Int] = [:]
        let priority = SongPriorityRules.standard
        // OLD ranker, inline: rank + fold computed INSIDE the comparator, so
        // every comparison re-folded strings. Same buckets, same order.
        func legacyRanked(_ toks: [String]) -> [SongIndexEntry] {
            guard let hits = PaletteSearch.matchTokens(toks, index: tokens) else { return [] }
            let folded = toks.joined(separator: " ")
            var prefix: [SongIndexEntry] = [], titleHit: [SongIndexEntry] = [], rest: [SongIndexEntry] = []
            for i in hits {
                let e = entries[Int(i)]
                let t = searchFold(e.title)
                if t.hasPrefix(folded) { prefix.append(e) }
                else if toks.allSatisfy({ t.contains($0) }) { titleHit.append(e) }
                else { rest.append(e) }
            }
            let order: (SongIndexEntry, SongIndexEntry) -> Bool = { a, b in
                let ra = priority.rank(a), rb = priority.rank(b)
                if ra.band != rb.band { return ra.band < rb.band }
                if ra.position != rb.position { return ra.position < rb.position }
                let pa = presentCounts[a.songKey] ?? 0, pb = presentCounts[b.songKey] ?? 0
                if pa != pb { return pa > pb }
                return a.title < b.title
            }
            prefix.sort(by: order); titleHit.sort(by: order); rest.sort(by: order)
            return prefix + titleHit + rest
        }
        // The rank table: once per index generation, what the app does.
        var ranks: [Int32] = []
        report.add("Rank table (once per index generation)", runs: 3) {
            ranks = entries.map { SongPriorityRules.pack(priority.rank($0)) }
        }
        for q in ["mare", "isus", "domnul"] {
            let toks = searchTokens(q)
            let hitCount = PaletteSearch.matchTokens(toks, index: tokens)?.count ?? 0
            report.add("Search „\(q)” — OLD (rank inside the sort)", runs: 5,
                       note: "\(hitCount) hits") {
                _ = legacyRanked(toks)
            }
            report.add("Search „\(q)” — NEW (rank table + folded keys)", runs: 5,
                       note: "\(hitCount) hits") {
                _ = PaletteSearch.rankedSongList(toks, songs: entries, tokens: tokens,
                                                 presentCounts: presentCounts, priority: priority,
                                                 ranks: ranks)
            }
        }

        // -------------------------------------------------------- song select
        // What clicking a row does: fetch the model by id, resolve the version,
        // build its slides.
        let sample = Array(entries.shuffled().prefix(20))
        try report.add("Select a song (fetch + version + slides) ×20", runs: 3,
                   note: "median over 20 different songs") {
            for e in sample {
                let id = e.id
                var d = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
                d.fetchLimit = 1
                guard let song = try context.fetch(d).first else { continue }
                let version = song.activeVersion
                _ = buildSongSlides(song: song, version: version, maxLines: 6,
                                    bilingual: false, language: nil)
            }
        }

        // ------------------------------------------------------- song edit save
        // Toggle verified and save — the write itself, without the index rebuild
        // it triggers (that is the "Song index build" row above).
        if let e = sample.first {
            let id = e.id
            var d = FetchDescriptor<Song>(predicate: #Predicate { $0.id == id })
            d.fetchLimit = 1
            if let song = try context.fetch(d).first {
                let original = song.verified
                try report.add("Edit a song and save (verified toggle)", runs: 5) {
                    song.verified.toggle()
                    song.modifiedDate = .now
                    try context.save()
                }
                song.verified = original
                try context.save()
            }
        }

        // ================================================================ BIBLE
        guard let anyModule = try context.fetch(FetchDescriptor<BibleModule>()).first(where: {
            !$0.abbreviation.isEmpty
        }) else {
            report.fact("Bible", "no module with an abbreviation — Bible rows skipped")
            try finish(report)
            return
        }
        let abbr = anyModule.abbreviation
        let moduleID = anyModule.id
        report.fact("Bible module used", "\(anyModule.name) (\(abbr))")

        // Three passages far apart, so the row cache cannot carry one to the next.
        let passages: [(book: Int, chapter: Int)] = [(1, 1), (19, 23), (43, 3)]

        // ----------------------------------------- Bible step — OLD (inline)
        // stepBibleAnchor as it was: every module, then the module's books
        // faulted, then every chapter of the book sorted, then its verses.
        // A FRESH container per run: the point is what a cold press cost.
        try report.add("Bible ← / → — OLD (fetch all modules, walk the graph)", runs: 3,
                   note: "per press; cold container each run") {
            let c = ModelContext(try openContainer(url))
            for p in passages {
                let modules = try c.fetch(FetchDescriptor<BibleModule>())
                guard let module = modules.first(where: { $0.abbreviation.lowercased() == abbr.lowercased() }),
                      let book = module.books.first(where: { $0.bookNumber == p.book }) else { continue }
                let chapters = book.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
                guard let ci = chapters.firstIndex(where: { $0.chapterNumber == p.chapter }) else { continue }
                _ = chapters[ci].verses.sorted { $0.verseNumber < $1.verseNumber }
            }
        }

        // ----------------------------------------- Bible step — NEW, cold
        try report.add("Bible ← / → — NEW, cold (targeted fetch, prefetched verses)", runs: 3,
                   note: "first press on a chapter; cold container each run") {
            let c = ModelContext(try openContainer(url))
            let nav = BibleNavigator()
            for p in passages {
                _ = nav.passage(moduleID: moduleID, bookNumber: p.book, chapter: p.chapter, in: c)
            }
        }

        // ----------------------------------------- Bible step — NEW, warm
        let warmContext = ModelContext(container)
        let warmNav = BibleNavigator()
        for p in passages {
            _ = warmNav.passage(moduleID: moduleID, bookNumber: p.book, chapter: p.chapter, in: warmContext)
        }
        report.add("Bible ← / → — NEW, warm (cache hit)", runs: 20,
                   note: "every press after the first inside a chapter") {
            for p in passages {
                _ = warmNav.passage(moduleID: moduleID, bookNumber: p.book, chapter: p.chapter, in: warmContext)
            }
        }
        report.add("Bible cross a chapter boundary — NEW", runs: 5,
                   note: "adjacentChapter + passage, spine cached") {
            for p in passages {
                if let next = warmNav.adjacentChapter(moduleID: moduleID, bookNumber: p.book,
                                                      chapter: p.chapter, direction: 1, in: warmContext) {
                    _ = warmNav.passage(moduleID: moduleID, bookNumber: next.bookNumber,
                                        chapter: next.chapter, in: warmContext)
                }
            }
        }

        // ------------------------------------------- Book list — chapter counts
        // OLD: `book.chapters.count` per row, ×3 for ViewThatFits, every render.
        try report.add("Book list render — OLD (chapters.count ×3 per book)", runs: 3,
                   note: "per render; cold container each run") {
            let c = ModelContext(try openContainer(url))
            var d = FetchDescriptor<BibleModule>(predicate: #Predicate { $0.id == moduleID })
            d.fetchLimit = 1
            guard let m = try c.fetch(d).first else { return }
            for book in m.books { for _ in 0..<3 { _ = book.chapters.count } }
        }
        try report.add("Book list render — NEW, cold (one cached query)", runs: 3,
                   note: "first render; cold container each run") {
            let c = ModelContext(try openContainer(url))
            _ = BibleNavigator().chapterCounts(moduleID: moduleID, in: c)
        }
        report.add("Book list render — NEW, warm", runs: 20) {
            _ = warmNav.chapterCounts(moduleID: moduleID, in: warmContext)
        }

        // --------------------------------- Chapter-boundary checks (per render)
        // OLD: canAdvanceToNextChapter walked module.books + sortedChapters, and
        // the preview panel read it FOUR times per render.
        do {
            var d = FetchDescriptor<BibleModule>(predicate: #Predicate { $0.id == moduleID })
            d.fetchLimit = 1
            if let m = try warmContext.fetch(d).first,
               let book = m.books.first(where: { $0.bookNumber == 19 }),
               let chapter = book.sortedChapters.first(where: { $0.chapterNumber == 23 }) {
                report.add("Preview-panel render — OLD (boundary check ×4)", runs: 5,
                           note: "faulted the module spine on every frame") {
                    for _ in 0..<4 {
                        let chapters = book.sortedChapters
                        if let idx = chapters.firstIndex(where: { $0.id == chapter.id }), idx + 1 < chapters.count { continue }
                        let books = m.books.sorted { $0.bookNumber < $1.bookNumber }
                        if let bi = books.firstIndex(where: { $0.id == book.id }), bi + 1 < books.count {
                            _ = books[bi + 1].sortedChapters.isEmpty
                        }
                    }
                }
                // NEW: the walk happens ONCE, when the chapter changes
                // (refreshCachedVerses: sort the verses + both boundary checks);
                // the four per-render reads are then a stored Bool.
                let lm = LibraryManager()
                lm.selectedBibleModule = m
                lm.selectedBook = book
                report.add("Chapter change — NEW (recompute once, then ×4 reads are free)", runs: 5,
                           note: "paid once per chapter, not per frame") {
                    lm.selectedChapter = nil
                    lm.selectedChapter = chapter
                    for _ in 0..<4 { _ = lm.canAdvanceToNextChapter }
                }
            }
        }

        try finish(report)
    }

    private func finish(_ report: Report) throws {
        let md = report.markdown
        print("\n\(md)\n")
        if let out = Self.outputURL {
            try md.write(to: out, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Scaling the copy up to Sunday's size

/// Imports `.tpsong` files into the store COPY until it holds `TP_SCALE_TARGET`
/// songs, so the measurements above can be repeated at the size that broke.
///
/// Uses the app's own importer, so the rows are shaped exactly as a real import
/// shapes them — a SQL-level clone would skip versions and sections and measure
/// a library that does not exist. Skipped unless both variables are set.
@Suite("Real library scale-up", .serialized)
@MainActor
struct RealLibraryScaleUp {
    nonisolated static var target: Int? {
        ProcessInfo.processInfo.environment["TP_SCALE_TARGET"].flatMap(Int.init)
    }
    nonisolated static var source: URL? {
        ProcessInfo.processInfo.environment["TP_SCALE_SOURCE"].map { URL(fileURLWithPath: $0) }
    }

    nonisolated private static func tpsongFiles(under root: URL) -> [URL] {
        var out: [URL] = []
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return out }
        while let next = e.nextObject() as? URL {
            if next.pathExtension == "tpsong" { out.append(next) }
        }
        return out
    }

    @Test(.enabled(if: RealLibraryPerformanceTests.storeURL != nil
                       && RealLibraryScaleUp.target != nil
                       && RealLibraryScaleUp.source != nil))
    func importUntilTheTargetIsReached() async throws {
        let storeURL = try #require(RealLibraryPerformanceTests.storeURL)
        let target = try #require(Self.target)
        let source = try #require(Self.source)

        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                           configurations: [ModelConfiguration(url: storeURL)])
        let context = ModelContext(container)
        let have = try context.fetchCount(FetchDescriptor<Song>())
        let need = target - have
        print("scale-up: have \(have), target \(target), need \(max(need, 0))")
        guard need > 0 else { return }

        // Walk the source tree for .tpsong files, deterministic order.
        // NSEnumerator cannot be iterated from an async context; drain it in a
        // synchronous helper.
        var files = Self.tpsongFiles(under: source)
        files.sort { $0.path < $1.path }
        print("scale-up: \(files.count) .tpsong files available")
        let batch = Array(files.prefix(need))

        let clock = ContinuousClock()
        let elapsed = await clock.measure {
            _ = await ImportService.importSongItems(
                urls: batch, collectionName: "Scale-up",
                modelContext: context, duplicateResolution: .keepBoth)
        }
        let now = try context.fetchCount(FetchDescriptor<Song>())
        print("scale-up: imported \(now - have) in \(elapsed) → \(now) songs")
        #expect(now >= min(target, have + files.count))
    }
}

// MARK: - Where the index build spends its time

@Suite("Real library index phases", .serialized)
@MainActor
struct RealLibraryIndexPhases {
    @Test(.enabled(if: RealLibraryPerformanceTests.storeURL != nil))
    func phases() async throws {
        let url = try #require(RealLibraryPerformanceTests.storeURL)
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                           configurations: [ModelConfiguration(url: url)])
        let ctx = ModelContext(container)
        let clock = ContinuousClock()
        var out = "## Index build — phases\n\n| phase | time |\n|---|---:|\n"
        func row(_ n: String, _ d: Duration) { out += "| \(n) | \(d) |\n" }

        // 1. first lines: fetch + per-verse song fault
        var firstLines: [UUID: String] = [:]
        var t = clock.measure {
            let d = FetchDescriptor<SongVerse>(predicate: #Predicate { $0.order == 0 })
            for v in (try? ctx.fetch(d)) ?? [] {
                guard let id = v.song?.id else { continue }
                firstLines[id] = String(v.text.prefix(120))
            }
        }
        row("1a first lines — fetch verses + fault song per verse (\(firstLines.count))", t)

        var firstLines2: [UUID: String] = [:]
        t = clock.measure {
            var d = FetchDescriptor<SongVerse>(predicate: #Predicate { $0.order == 0 })
            d.relationshipKeyPathsForPrefetching = [\.song]
            for v in (try? ctx.fetch(d)) ?? [] {
                guard let id = v.song?.id else { continue }
                firstLines2[id] = String(v.text.prefix(120))
            }
        }
        row("1b first lines — same with song PREFETCHED", t)

        // 2. version counts
        var counts: [UUID: Int] = [:]
        t = clock.measure {
            for ver in (try? ctx.fetch(FetchDescriptor<SongVersion>())) ?? [] {
                guard let id = ver.song?.id else { continue }
                counts[id, default: 0] += 1
            }
        }
        row("2a version counts — fault song per version (\(counts.values.reduce(0,+)))", t)
        var counts2: [UUID: Int] = [:]
        t = clock.measure {
            var d = FetchDescriptor<SongVersion>()
            d.relationshipKeyPathsForPrefetching = [\.song]
            for ver in (try? ctx.fetch(d)) ?? [] {
                guard let id = ver.song?.id else { continue }
                counts2[id, default: 0] += 1
            }
        }
        row("2b version counts — song PREFETCHED", t)

        // 3. songs: fetch, then the per-song reads
        var songs: [Song] = []
        t = clock.measure { songs = (try? ctx.fetch(FetchDescriptor<Song>())) ?? [] }
        row("3a fetch all songs (\(songs.count))", t)
        t = clock.measure { for s in songs { _ = s.songbook?.name; _ = s.collection?.name } }
        row("3b songbook + collection reads (faults)", t)
        t = clock.measure { for s in songs { _ = s.webURL } }
        row("3c webURL (JSON parse per song)", t)
        var blobs: [String] = []
        t = clock.measure { blobs = songs.map { searchFold($0.searchText.isEmpty ? $0.title : $0.searchText) } }
        row("3d searchFold every blob (\(blobs.reduce(0) { $0 + $1.utf8.count } / 1024) KB)", t)

        // 4. token index
        var idx = TokenIndex.empty
        t = clock.measure { idx = TokenIndex.build(blobs: blobs) }
        row("4 TokenIndex.build (\(idx.tokens.count) tokens)", t)

        // 5. the two whole builds, and their equivalence
        let builder = SearchIndexBuilder(modelContainer: container)
        var walked: SearchIndexBuilder.SongsPayload!
        var columned: SearchIndexBuilder.SongsPayload!
        let tw = await clock.measure { walked = await builder.buildSongsByWalking() }
        row("5a buildSongs — SwiftData walk (old)", tw)
        let tc = try await clock.measure { columned = try await builder.buildSongsFromColumns() }
        row("5b buildSongs — Core Data columns (new)", tc)
        let a = Dictionary(uniqueKeysWithValues: walked.entries.map { ($0.id, $0) })
        let b = Dictionary(uniqueKeysWithValues: columned.entries.map { ($0.id, $0) })
        #expect(a.count == b.count, "the two builds see different song counts")
        var mismatches: [String] = []
        for (id, x) in a {
            guard let y = b[id] else { mismatches.append("missing \(id)"); continue }
            if x != y {
                var diffs: [String] = []
                if x.title != y.title { diffs.append("title") }
                if x.author != y.author { diffs.append("author") }
                if x.songbookName != y.songbookName { diffs.append("songbookName") }
                if x.collectionID != y.collectionID { diffs.append("collectionID") }
                if x.collectionName != y.collectionName { diffs.append("collectionName") }
                if x.versionCount != y.versionCount { diffs.append("versionCount \(x.versionCount) vs \(y.versionCount)") }
                if x.hasMedia != y.hasMedia { diffs.append("hasMedia") }
                if x.verified != y.verified { diffs.append("verified") }
                if x.modifiedDate != y.modifiedDate { diffs.append("modifiedDate") }
                if x.firstLine != y.firstLine { diffs.append("firstLine") }
                if x.blob != y.blob { diffs.append("blob") }
                if x.songKey != y.songKey { diffs.append("songKey") }
                if x.sourceFormat != y.sourceFormat { diffs.append("sourceFormat") }
                if x.webHost != y.webHost { diffs.append("webHost") }
                if x.foldedTitle != y.foldedTitle { diffs.append("foldedTitle") }
                if x.language != y.language { diffs.append("language") }
                if x.songNumber != y.songNumber { diffs.append("songNumber") }
                mismatches.append("\(x.title): \(diffs.joined(separator: ", "))")
            }
        }
        #expect(mismatches.isEmpty, "column build differs from walk for \(mismatches.count) songs, e.g. \(mismatches.prefix(3))")
        row("5c equivalence: \(mismatches.isEmpty ? "IDENTICAL" : "\(mismatches.count) differ")", .zero)
        #expect(walked.tokens.tokens == columned.tokens.tokens)
        #expect(walked.languages == columned.languages)

        print("\n\(out)\n")
        if let o = RealLibraryPerformanceTests.outputURL {
            try out.write(to: o.deletingLastPathComponent().appendingPathComponent("phases.md"),
                          atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Where a search spends its time

@Suite("Real library search phases", .serialized)
@MainActor
struct RealLibrarySearchPhases {
    @Test(.enabled(if: RealLibraryPerformanceTests.storeURL != nil))
    func phases() async throws {
        let url = try #require(RealLibraryPerformanceTests.storeURL)
        let container = try ModelContainer(for: Schema(versionedSchema: SchemaV2.self),
                                           configurations: [ModelConfiguration(url: url)])
        let payload = await SearchIndexBuilder(modelContainer: container).buildSongs()
        let songs = payload.entries, tokens = payload.tokens
        let rules = SongPriorityRules.standard
        let ranks = songs.map { SongPriorityRules.pack(rules.rank($0)) }
        let clock = ContinuousClock()
        var out = "## Search „isus” — phases (\(songs.count) songs)\n\n| phase | time |\n|---|---:|\n"
        func row(_ n: String, _ d: Duration) { out += "| \(n) | \(d) |\n" }

        let toks = searchTokens("isus")
        var hits = Set<Int32>()
        var t = clock.measure { hits = PaletteSearch.matchTokens(toks, index: tokens) ?? [] }
        row("1 matchTokens → \(hits.count) hits (Set union of postings)", t)

        let folded = toks.joined(separator: " ")
        var prefix = 0, titleHit = 0, rest = 0
        t = clock.measure {
            for i in hits {
                let e = songs[Int(i)]
                let tt = e.foldedTitle
                if tt.hasPrefix(folded) { prefix += 1 }
                else if toks.allSatisfy({ tt.contains($0) }) { titleHit += 1 }
                else { rest += 1 }
            }
        }
        row("2 classify (hasPrefix / contains) → \(prefix)/\(titleHit)/\(rest)", t)

        t = clock.measure { for i in hits { _ = ranks[Int(i)] } }
        row("3 rank lookups", t)

        let presentCounts: [String: Int] = [:]
        t = clock.measure { for i in hits { _ = presentCounts[songs[Int(i)].songKey] } }
        row("4 popularity lookups (dictionary by songKey)", t)

        struct K { let i: Int32; let rank: Int32; let f: String }
        var keyed: [K] = []
        t = clock.measure {
            keyed = hits.map { K(i: $0, rank: ranks[Int($0)], f: songs[Int($0)].foldedTitle) }
        }
        row("5 build keyed array (\(keyed.count))", t)

        var sorted = keyed
        t = clock.measure { sorted.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.f < $1.f } }
        row("6 sort by (rank, foldedTitle <)", t)

        var sorted2 = keyed
        t = clock.measure { sorted2.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.f.utf8.lexicographicallyPrecedes($1.f.utf8) } }
        row("6b sort by (rank, utf8 bytes)", t)

        var outEntries: [SongIndexEntry] = []
        t = clock.measure { outEntries = sorted.map { songs[Int($0.i)] } }
        row("7 materialise result entries (\(outEntries.count))", t)

        t = clock.measure {
            _ = PaletteSearch.rankedSongList(toks, songs: songs, tokens: tokens,
                                             presentCounts: presentCounts, priority: rules, ranks: ranks)
        }
        row("= whole rankedSongList", t)

        print("\n\(out)\n")
        if let o = RealLibraryPerformanceTests.outputURL {
            try out.write(to: o.deletingLastPathComponent().appendingPathComponent("search-phases.md"),
                          atomically: true, encoding: .utf8)
        }
    }
}
