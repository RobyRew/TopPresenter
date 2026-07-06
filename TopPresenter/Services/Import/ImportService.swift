//
//  ImportService.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation
import SwiftData

/// Central service that coordinates all import operations.
/// Uses the importer registry pattern to support multiple formats modularly.
final class ImportService {
    // MARK: - Importer Registries

    /// Fresh importer per import (nonisolated factory). The XML importers carry
    /// mutable parser state, so SHARED instances were a latent data race —
    /// a new instance per call is correct and lets imports run off-main.
    /// Add new importers here to support additional formats.
    nonisolated private static func makeBibleImporter(for format: SupportedBibleFormat) -> (any BibleImporter)? {
        switch format {
        case .topPresenter: return TopPresenterBibleImporter()
        case .osisXML: return OSISBibleImporter()
        case .zefaniaXML: return ZefaniaBibleImporter()
        case .mySword: return MySwordBibleImporter()
        case .usfm: return USFMBibleImporter()
        case .unboundBible: return UnboundBibleImporter()
        }
    }

    /// Registered Song importers. Add new importers here to support additional formats.
    private static let songImporters: [SupportedSongFormat: SongImporter] = {
        var importers: [SupportedSongFormat: SongImporter] = [:]
        let topPresenterImporter = TopPresenterSongImporter()
        importers[topPresenterImporter.format] = topPresenterImporter
        let openSongImporter = OpenSongImporter()
        importers[openSongImporter.format] = openSongImporter
        let openLyricsImporter = OpenLyricsImporter()
        importers[openLyricsImporter.format] = openLyricsImporter
        let chordProImporter = ChordProImporter()
        importers[chordProImporter.format] = chordProImporter
        let plainTextImporter = PlainTextSongImporter()
        importers[plainTextImporter.format] = plainTextImporter
        let powerPointImporter = PowerPointSongImporter()
        importers[powerPointImporter.format] = powerPointImporter
        return importers
    }()

    // MARK: - Bible Import

    /// Import a Bible file in the specified format
    /// What to do when a Bible with the same code is already in the library.
    enum BibleConflictResolution {
        case ask          // surface a BibleConflict for the UI to resolve
        case replace      // delete existing, import fresh
        case merge        // fill in missing books/chapters/verses
        case keepBoth     // import as a separate module (disambiguated name)
        case cancel       // skip
    }

    /// Thrown by `importBible(resolution: .ask)` when a same-code module exists,
    /// so the UI can present the Replace/Merge/Keep-both/Cancel dialog.
    struct BibleConflict: Error, Sendable {
        let code: String
        let existingName: String
        let existingVerses: Int
        let incomingName: String
        let incomingVerses: Int
    }

    /// Cancelled by the user — callers should ignore silently.
    struct BibleImportCancelled: Error, Sendable {}

    /// Finds an already-imported module by code (case-insensitive abbreviation).
    nonisolated static func existingBibleModule(code: String, modelContext: ModelContext) -> BibleModule? {
        let needle = code.lowercased()
        guard !needle.isEmpty else { return nil }
        let all = (try? modelContext.fetch(FetchDescriptor<BibleModule>())) ?? []
        return all.first { $0.abbreviation.lowercased() == needle }
    }

    /// nonisolated(nonsending): runs on the CALLER's isolation and operates only
    /// on the passed context — call it from the main actor with the main context
    /// (single-file UI imports) or from BackgroundImportActor with ITS context
    /// (batch imports, fully off-main). Never mix contexts across isolations.
    nonisolated static func importBible(
        fileURL: URL,
        format: SupportedBibleFormat,
        modelContext: ModelContext,
        resolution: BibleConflictResolution = .keepBoth,
        progressHandler: (@MainActor @Sendable (Double, String) -> Void)? = nil
    ) async throws -> BibleModule {
        guard let importer = makeBibleImporter(for: format) else {
            throw BibleImportError.unsupportedFormat(format.displayName)
        }

        await progressHandler?(0.1, String(localized: "Reading file...", comment: "Import progress"))

        // Start accessing security-scoped resource
        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let result = try await importer.parse(fileURL: fileURL)

        // ── Duplicate handling (code already in the DB) ──
        var resolvedName = result.moduleName
        if let existing = existingBibleModule(code: result.abbreviation, modelContext: modelContext) {
            switch resolution {
            case .ask:
                throw BibleConflict(
                    code: result.abbreviation,
                    existingName: existing.name,
                    existingVerses: verseCount(of: existing),
                    incomingName: result.moduleName,
                    incomingVerses: verseCount(of: result)
                )
            case .cancel:
                throw BibleImportCancelled()
            case .merge:
                await progressHandler?(0.5, String(localized: "Merging...", comment: "Import progress"))
                mergeBible(result, into: existing, modelContext: modelContext)
                try modelContext.save()
                await progressHandler?(1.0, String(localized: "Complete!", comment: "Import progress"))
                return existing
            case .replace:
                modelContext.delete(existing)
            case .keepBoth:
                resolvedName = uniqueModuleName(result.moduleName, modelContext: modelContext)
            }
        }

        await progressHandler?(0.5, String(localized: "Importing books...", comment: "Import progress"))

        // Correct an obviously-wrong declared language from the verse-text script
        // (e.g. a Greek/Hebrew module mistakenly tagged "ro"). Latin scripts are
        // left untouched. Heals mislabeled files on (re-)import.
        let langSample = result.books.first?.chapters.first?.verses.prefix(8)
            .map(\.text).joined(separator: " ") ?? ""
        let correctedLanguage = BibleLanguageDetection.refine(declared: result.language, sample: langSample)
        let correctedLanguageName = correctedLanguage == result.language
            ? result.languageName
            : BibleLanguageNames.name(for: correctedLanguage)

        // Create SwiftData models
        let module = BibleModule(
            name: resolvedName,
            abbreviation: result.abbreviation,
            language: correctedLanguage,
            sourceFormat: format.rawValue,
            moduleDescription: result.description,
            versification: result.versification,
            canon: result.canon,
            nameLocal: result.nameLocal,
            languageName: correctedLanguageName,
            copyright: result.copyright,
            aboutText: result.about,
            textSource: result.textSource,
            year: result.year,
            direction: result.direction,
            hasWordsOfChrist: result.hasWordsOfChrist,
            hasStrongs: result.hasStrongs,
            incomplete: result.incomplete,
            extensionsJSON: result.extensionsJSON
        )
        modelContext.insert(module)

        let totalBooks = result.books.count

        for (index, importBook) in result.books.enumerated() {
            // autoreleasepool: the chapter/verse loops churn thousands of
            // transient Foundation objects — drain them per book so a whole-Bible
            // import can't balloon the heap (the malloc-corruption crash class).
            autoreleasepool {
                let book = BibleBook(
                    name: importBook.name,
                    bookNumber: importBook.bookNumber,
                    testament: importBook.testament,
                    nameEnglish: importBook.nameEnglish,
                    abbreviation: importBook.abbreviation,
                    abbreviationEnglish: importBook.abbreviationEnglish,
                    expectedChapters: importBook.expectedChapters,
                    introduction: importBook.introduction ?? "",
                    extensionsJSON: importBook.extensionsJSON
                )
                book.module = module

                for importChapter in importBook.chapters {
                    let chapter = BibleChapter(
                        chapterNumber: importChapter.chapterNumber,
                        headingsJSON: BibleRichData.encode(importChapter.headings),
                        extensionsJSON: importChapter.extensionsJSON
                    )
                    chapter.book = book

                    for importVerse in importChapter.verses {
                        let verse = BibleVerse(
                            verseNumber: importVerse.verseNumber,
                            text: importVerse.text,
                            runsJSON: BibleRichData.encode(importVerse.runs),
                            footnotesJSON: BibleRichData.encode(importVerse.footnotes),
                            crossRefsJSON: BibleRichData.encode(importVerse.crossReferences),
                            hasWordsOfChrist: importVerse.hasWordsOfChrist,
                            gloss: importVerse.gloss,
                            extensionsJSON: importVerse.extensionsJSON
                        )
                        verse.chapter = chapter
                    }
                }
            }

            // Chunked persistence: one save per book keeps the context's pending
            // object graph small instead of one massive end-of-import save.
            try modelContext.save()

            let progress = 0.5 + (Double(index + 1) / Double(totalBooks)) * 0.4
            await progressHandler?(progress, String(localized: "Importing \(importBook.name)...", comment: "Import progress"))
        }

        await progressHandler?(0.95, String(localized: "Saving...", comment: "Import progress"))
        try modelContext.save()
        await progressHandler?(1.0, String(localized: "Complete!", comment: "Import progress"))

        return module
    }

    /// Total verse count of a parsed result (for the conflict dialog stats).
    nonisolated static func verseCount(of result: BibleImportResult) -> Int {
        result.books.reduce(0) { $0 + $1.chapters.reduce(0) { $0 + $1.verses.count } }
    }

    nonisolated static func verseCount(of module: BibleModule) -> Int {
        module.books.reduce(0) { $0 + $1.chapters.reduce(0) { $0 + $1.verses.count } }
    }

    /// Disambiguated name when keeping both ("Name", "Name (2)", "Name (3)"…).
    nonisolated private static func uniqueModuleName(_ base: String, modelContext: ModelContext) -> String {
        let all = (try? modelContext.fetch(FetchDescriptor<BibleModule>())) ?? []
        let names = Set(all.map { $0.name })
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }

    /// Fills in only what the existing module is MISSING: new books, new
    /// chapters in existing books, and new verses in existing chapters. Verses
    /// already present are left untouched (the existing copy wins).
    nonisolated private static func mergeBible(_ result: BibleImportResult, into module: BibleModule, modelContext: ModelContext) {
        // Fill in module-level metadata the existing copy is missing.
        if module.aboutText.isEmpty { module.aboutText = result.about }
        if module.copyright.isEmpty { module.copyright = result.copyright }
        if module.textSource.isEmpty { module.textSource = result.textSource }
        if module.nameLocal.isEmpty { module.nameLocal = result.nameLocal }
        if module.languageName.isEmpty { module.languageName = result.languageName }
        if module.year == nil { module.year = result.year }
        if module.versification == nil { module.versification = result.versification }
        if module.canon == nil { module.canon = result.canon }
        if result.hasWordsOfChrist { module.hasWordsOfChrist = true }
        if result.hasStrongs { module.hasStrongs = true }
        if module.extensionsJSON == nil { module.extensionsJSON = result.extensionsJSON }

        var booksByNumber = Dictionary(module.books.map { ($0.bookNumber, $0) }, uniquingKeysWith: { a, _ in a })

        for ib in result.books {
            let book: BibleBook
            if let existing = booksByNumber[ib.bookNumber] {
                book = existing
                if book.introduction.isEmpty, let intro = ib.introduction { book.introduction = intro }
                if book.nameEnglish.isEmpty { book.nameEnglish = ib.nameEnglish }
                if book.abbreviation.isEmpty { book.abbreviation = ib.abbreviation }
            } else {
                book = BibleBook(name: ib.name, bookNumber: ib.bookNumber, testament: ib.testament,
                                 nameEnglish: ib.nameEnglish, abbreviation: ib.abbreviation,
                                 abbreviationEnglish: ib.abbreviationEnglish, expectedChapters: ib.expectedChapters,
                                 introduction: ib.introduction ?? "", extensionsJSON: ib.extensionsJSON)
                book.module = module
                booksByNumber[ib.bookNumber] = book
            }
            var chaptersByNumber = Dictionary(book.chapters.map { ($0.chapterNumber, $0) }, uniquingKeysWith: { a, _ in a })

            for ic in ib.chapters {
                let chapter: BibleChapter
                if let existing = chaptersByNumber[ic.chapterNumber] {
                    chapter = existing
                    if chapter.headingsJSON == nil, let h = ic.headings {
                        chapter.headingsJSON = BibleRichData.encode(h)
                    }
                } else {
                    chapter = BibleChapter(chapterNumber: ic.chapterNumber,
                                           headingsJSON: BibleRichData.encode(ic.headings),
                                           extensionsJSON: ic.extensionsJSON)
                    chapter.book = book
                    chaptersByNumber[ic.chapterNumber] = chapter
                }
                let presentVerses = Set(chapter.verses.map { $0.verseNumber })
                for iv in ic.verses where !presentVerses.contains(iv.verseNumber) {
                    let verse = BibleVerse(
                        verseNumber: iv.verseNumber, text: iv.text,
                        runsJSON: BibleRichData.encode(iv.runs),
                        footnotesJSON: BibleRichData.encode(iv.footnotes),
                        crossRefsJSON: BibleRichData.encode(iv.crossReferences),
                        hasWordsOfChrist: iv.hasWordsOfChrist,
                        gloss: iv.gloss,
                        extensionsJSON: iv.extensionsJSON
                    )
                    verse.chapter = chapter
                }
            }
        }
    }

    /// Auto-detect Bible format from file content and extension.
    /// Returns the detected format, or nil if unknown.
    /// nonisolated: pure file inspection (Data/FileManager reads) — called from the
    /// background classification walk (Task.detached), so it must not hop to MainActor.
    nonisolated static func detectBibleFormat(fileURL: URL) -> SupportedBibleFormat? {
        let ext = fileURL.pathExtension.lowercased()

        // Check for TopPresenter JSON first (priority format)
        if ext == "json" {
            if let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
               let header = String(data: data.prefix(1000), encoding: .utf8) {
                if header.contains("\"TopPresenter Bible\"") || header.contains("\"format\"") && header.contains("\"books\"") {
                    return .topPresenter
                }
            }
        }

        // Check for MySword SQLite databases by extension
        if ext == "mybible" || fileURL.lastPathComponent.lowercased().contains(".bbl.") {
            return .mySword
        }

        // Check for USFM by extension
        if ext == "usfm" || ext == "sfm" {
            return .usfm
        }

        // Check if it's a directory (USFM folder)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            // Check if directory contains .usfm files
            if let contents = try? FileManager.default.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil) {
                let hasUSFM = contents.contains { url in
                    let e = url.pathExtension.lowercased()
                    return e == "usfm" || e == "sfm"
                }
                if hasUSFM { return .usfm }
            }
            return nil
        }

        // For SQLite files, check by trying to read the header bytes
        if let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) {
            // SQLite files start with "SQLite format 3\000"
            let sqliteHeader = "SQLite format 3"
            if data.count > 16 {
                let headerBytes = String(data: data.prefix(16), encoding: .utf8) ?? ""
                if headerBytes.hasPrefix(sqliteHeader) {
                    return .mySword
                }
            }
        }

        // Read text content for XML and text-based formats
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        guard let header = String(data: data.prefix(4000), encoding: .utf8) else { return nil }

        // OSIS XML detection
        if header.contains("<osis") || header.contains("<osisText") || header.contains("osis.xsd") {
            return .osisXML
        }

        // Zefania XML detection
        if header.contains("<XMLBIBLE") || header.contains("<xmlbible") ||
            header.contains("<BIBLEBOOK") || header.contains("zefania") {
            return .zefaniaXML
        }

        // USFM detection (single file with markers)
        if header.contains("\\id ") && (header.contains("\\c ") || header.contains("\\v ")) {
            return .usfm
        }

        // Unbound Bible detection (tab-delimited with # comments)
        let lines = header.components(separatedBy: .newlines)
        var hasComments = false
        var hasTabData = false
        for line in lines.prefix(30) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("#") {
                hasComments = true
                if trimmed.lowercased().contains("columns") { return .unboundBible }
            } else if !trimmed.isEmpty {
                let tabs = trimmed.components(separatedBy: "\t")
                if tabs.count >= 4, let _ = Int(tabs[0]), let _ = Int(tabs[1]) {
                    hasTabData = true
                }
            }
        }
        if hasComments && hasTabData { return .unboundBible }
        if hasTabData && !hasComments {
            // Might be a simple tab-separated Bible
            return .unboundBible
        }

        return nil
    }

    // MARK: - Song Import

    /// Import a single song file
    static func importSong(
        fileURL: URL,
        format: SupportedSongFormat,
        collection: SongCollection,
        modelContext: ModelContext
    ) async throws -> Song {
        guard let importer = songImporters[format] else {
            throw SongImportError.invalidFormat(format.displayName)
        }

        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        let name = fileURL.lastPathComponent
        let results = try await importer.parseAll(fileURL: fileURL).map { r -> SongImportResult in
            var r = r; if r.sourceFile.isEmpty { r.sourceFile = name }; return r
        }
        guard let first = results.first else { throw SongImportError.noSongsFound }
        // A bundle file yields many songs; return the first, create the rest too.
        let song = createSongFromResult(first, collection: collection, modelContext: modelContext)
        for extra in results.dropFirst() {
            _ = createSongFromResult(extra, collection: collection, modelContext: modelContext)
        }
        return song
    }

    /// Import all songs from a directory
    static func importSongsFromDirectory(
        directoryURL: URL,
        format: SupportedSongFormat,
        collectionName: String,
        modelContext: ModelContext,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> SongCollection {
        guard let importer = songImporters[format] else {
            throw SongImportError.invalidFormat(format.displayName)
        }

        let accessing = directoryURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        progressHandler?(0.1, String(localized: "Scanning directory...", comment: "Import progress"))

        let collection = SongCollection(
            name: collectionName,
            sourceFormat: format.rawValue
        )
        modelContext.insert(collection)

        let results = try await importer.parseDirectory(directoryURL: directoryURL)

        guard !results.isEmpty else {
            throw SongImportError.noSongsFound
        }

        for (index, result) in results.enumerated() {
            _ = createSongFromResult(result, collection: collection, modelContext: modelContext)

            let progress = 0.1 + (Double(index + 1) / Double(results.count)) * 0.8
            progressHandler?(progress, String(localized: "Importing \(result.title)...", comment: "Import progress"))
        }

        progressHandler?(0.95, String(localized: "Saving...", comment: "Import progress"))
        try modelContext.save()
        progressHandler?(1.0, String(localized: "Complete!", comment: "Import progress"))

        return collection
    }

    /// Import a single song file into a collection
    static func importSingleSongFile(
        fileURL: URL,
        format: SupportedSongFormat,
        collectionName: String,
        modelContext: ModelContext
    ) async throws -> SongCollection {
        guard let importer = songImporters[format] else {
            throw SongImportError.invalidFormat(format.displayName)
        }

        let accessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        // Check if collection already exists
        let descriptor = FetchDescriptor<SongCollection>(
            predicate: #Predicate { $0.name == collectionName }
        )
        let existing = try? modelContext.fetch(descriptor)
        let collection: SongCollection

        if let existingCollection = existing?.first {
            collection = existingCollection
        } else {
            collection = SongCollection(name: collectionName, sourceFormat: format.rawValue)
            modelContext.insert(collection)
        }

        let name = fileURL.lastPathComponent
        let results = try await importer.parseAll(fileURL: fileURL).map { r -> SongImportResult in
            var r = r; if r.sourceFile.isEmpty { r.sourceFile = name }; return r
        }
        guard !results.isEmpty else { throw SongImportError.noSongsFound }
        for result in results {
            _ = createSongFromResult(result, collection: collection, modelContext: modelContext)
        }

        try modelContext.save()
        return collection
    }

    /// Result of a multi-file song import: what worked, what didn't and why.
    struct SongBatchResult {
        var collection: SongCollection?
        var importedTitles: [String] = []
        var failures: [(file: String, reason: String)] = []
    }

    /// Imports any mix of song FILES and/or DIRECTORIES into one collection.
    /// Format is AUTO-DETECTED per file (extension + content sniffing) — no
    /// format picker traps. Per-file failures are collected, not swallowed.
    static func importSongItems(
        urls: [URL],
        collectionName: String,
        modelContext: ModelContext,
        duplicateResolution: SongDuplicateResolution = .addAsVersion,
        isCancelled: @escaping () -> Bool = { false },
        progressHandler: ((Double, String) -> Void)? = nil
    ) async -> SongBatchResult {
        var result = SongBatchResult()

        // Expand directories RECURSIVELY (subfolders included); keep the immediate parent for tagging.
        var fileURLs: [(url: URL, parent: URL?)] = []
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()  // kept open until the function ends
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                let files = recursiveSongFiles(in: url)
                if files.isEmpty {
                    result.failures.append((url.lastPathComponent, String(localized: "Directorul este gol.", comment: "Import error")))
                }
                for f in files { fileURLs.append((f, f.deletingLastPathComponent())) }
            } else {
                fileURLs.append((url, nil))
            }
        }

        guard !fileURLs.isEmpty else { return result }

        // Duplicate-detection index (normalized title → existing song), built from the collection.
        var index: [String: Song] = [:]
        var indexBuilt = false
        func collection() -> SongCollection {
            if let existing = result.collection { return existing }
            let descriptor = FetchDescriptor<SongCollection>(
                predicate: #Predicate { $0.name == collectionName }
            )
            let col: SongCollection
            if let found = (try? modelContext.fetch(descriptor))?.first {
                col = found
            } else {
                col = SongCollection(name: collectionName, sourceFormat: "mixed")
                modelContext.insert(col)
            }
            result.collection = col
            if !indexBuilt {
                for s in col.songs { index[normalizedSongKey(s.title)] = s }
                indexBuilt = true
            }
            return col
        }

        for (offset, item) in fileURLs.enumerated() {
            if isCancelled() { break }
            let name = item.url.lastPathComponent
            progressHandler?(
                Double(offset) / Double(fileURLs.count),
                String(localized: "Se importă \(name)…", comment: "Import progress")
            )

            guard let format = detectSongFormat(fileURL: item.url) else {
                result.failures.append((name, String(localized: "Format necunoscut (acceptat: TopPresenter/OpenSong/OpenLyrics, ChordPro, TXT, PPTX, PPT).", comment: "Import error")))
                continue
            }
            guard let importer = songImporters[format] else {
                result.failures.append((name, String(localized: "Niciun importator pentru acest format.", comment: "Import error")))
                continue
            }

            do {
                // One file may hold many songs (a TopPresenter Song JSON bundle, e.g. the
                // ResurseCrestine per-letter exports). Apply duplicate handling per song.
                let parsedSongs = try await importer.parseAll(fileURL: item.url)
                let col = collection()
                for parsed in parsedSongs {
                    let key = normalizedSongKey(parsed.title)

                    func makeNew(updateIndex: Bool) {
                        let song = createSongFromResult(parsed, collection: col, modelContext: modelContext)
                        applyFolderTag(item.parent, to: song)
                        if updateIndex { index[key] = song }
                        result.importedTitles.append(parsed.title)
                    }

                    if let existing = index[key] {
                        switch duplicateResolution {
                        case .addAsVersion:
                            appendVersions(from: parsed, to: existing)
                            result.importedTitles.append(parsed.title)
                        case .replace:
                            modelContext.delete(existing)
                            makeNew(updateIndex: true)
                        case .keepBoth:
                            makeNew(updateIndex: false)
                        case .skip:
                            break
                        }
                    } else {
                        makeNew(updateIndex: true)
                    }
                }
            } catch {
                result.failures.append((name, error.localizedDescription))
            }
        }

        if result.collection != nil {
            try? modelContext.save()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
        progressHandler?(1.0, String(localized: "Gata!", comment: "Import progress"))
        return result
    }

    /// Recursively list regular files under a directory (subfolders included).
    /// Lowercased extensions of every supported song format — used to skip
    /// unrelated files when scanning a folder, so we never try to parse (or read)
    /// e.g. video footage sitting in the same directory tree.
    private static let songFileExtensions: Set<String> =
        Set(SupportedSongFormat.allCases.flatMap { $0.fileExtensions.map { $0.lowercased() } })

    private static func recursiveSongFiles(in dir: URL) -> [URL] {
        var out: [URL] = []
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        if let en = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) {
            for case let f as URL in en {
                // Same rule as the Bible/Song walk: the selected folder plus at
                // most TWO subfolder levels (enumerator level 1 = direct child).
                if en.level > 3 { en.skipDescendants(); continue }
                guard songFileExtensions.contains(f.pathExtension.lowercased()) else { continue }
                if (try? f.resourceValues(forKeys: keys))?.isRegularFile == true {
                    out.append(f)
                }
            }
        }
        return out.sorted { $0.path < $1.path }
    }

    /// Tag a song with its immediate folder name (folder structure → searchable tags/themes).
    private static func applyFolderTag(_ parent: URL?, to song: Song) {
        guard let parent else { return }
        let folder = parent.lastPathComponent
        guard !folder.isEmpty else { return }
        var themes = song.themes
        if !themes.contains(folder) { themes.append(folder); song.themes = themes }
        if song.tags.isEmpty {
            song.tags = folder
        } else if !song.tags.contains(folder) {
            song.tags += ", \(folder)"
        }
    }

    /// Auto-detect song format from file content
    /// nonisolated: pure file inspection — see detectBibleFormat.
    nonisolated static func detectSongFormat(fileURL: URL) -> SupportedSongFormat? {
        let ext = fileURL.pathExtension.lowercased()

        // PowerPoint files
        if ext == "pptx" || ext == "ppt" {
            return .powerPoint
        }
        // ChordPro by extension
        if ["cho", "crd", "chordpro", "chopro"].contains(ext) {
            return .chordPro
        }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        guard let content = String(data: data.prefix(2000), encoding: .utf8) else { return nil }

        // TopPresenter Song JSON (single-song doc or legacy bundle)
        if ext == "json" || content.contains("\"format\"") {
            if content.contains("TopPresenter Song") || content.contains("\"versions\"") || content.contains("\"verses\"") {
                return .topPresenterJSON
            }
        }
        if content.contains("<song") && (content.contains("openlyrics") || content.contains("OpenLyrics")) {
            return .openLyricsXML
        } else if content.contains("<song") && (content.contains("<lyrics>") || content.contains("<title>")) {
            return .openSongXML
        }
        // ChordPro by content (directives)
        if content.contains("{title:") || content.contains("{t:") || content.contains("{start_of_") {
            return .chordPro
        }
        // Plain text fallback
        if ext == "txt" {
            return .plainText
        }

        return nil
    }

    // MARK: - Private Helpers

    private static func createSongFromResult(
        _ result: SongImportResult,
        collection: SongCollection,
        modelContext: ModelContext
    ) -> Song {
        let song = Song(
            title: result.title,
            author: result.author,
            copyright: result.copyright,
            ccliNumber: result.ccliNumber,
            key: result.key,
            tempo: result.tempo,
            songNumber: result.songNumber,
            tags: result.tags
        )
        song.collection = collection
        applyResult(result, to: song, modelContext: modelContext)
        return song
    }

    /// Apply a parsed GOAT result onto a song: set every scalar field, then CLEAR its
    /// existing version graph + verse cache and rebuild them. Used by import (on a fresh
    /// song) and by the song editor's Cancel-revert (rebuild from an open snapshot).
    static func applyResult(_ result: SongImportResult, to song: Song, modelContext: ModelContext) {
        song.title = result.title
        song.author = result.author
        song.copyright = result.copyright
        song.ccliNumber = result.ccliNumber
        song.key = result.key
        song.tempo = result.tempo
        song.songNumber = result.songNumber
        song.tags = result.tags
        song.titles = result.titles
        song.language = result.language
        song.themes = result.themes
        song.style = result.style
        song.songbookNumber = result.songbook?.number ?? ""
        song.authorWords = result.authorWords
        song.authorMusic = result.authorMusic
        song.authorTranslation = result.authorTranslation
        song.notes = result.notes
        song.verified = result.verified
        if !result.sourceFile.isEmpty { song.sourceFile = result.sourceFile }
        song.extensionsJSON = result.extensionsJSON
        song.media = result.media.map {
            SongMediaRef(role: $0.role, kind: $0.kind, filename: $0.filename, bookmark: $0.bookmark)
        }
        if let sb = result.songbook, !sb.name.isEmpty {
            song.songbook = upsertSongbook(sb, modelContext: modelContext)
        }

        // Clear the existing graph (cascade deletes sections) before rebuilding.
        for v in song.versions { modelContext.delete(v) }
        for verse in song.verses { modelContext.delete(verse) }

        let builtVersions = makeVersions(from: result)
        for v in builtVersions { v.song = song }
        // GOAT "original": true wins; else finalize picks first-with-songbook.
        if result.versions.count == builtVersions.count,
           let idx = result.versions.firstIndex(where: { $0.isOriginal }) {
            song.originalVersionID = builtVersions[idx].id.uuidString
        }
        finalizeVersionMetadata(for: song)

        // Flatten the active version into the SongVerse cache (legacy presenter / search / schedule).
        var lyrics = ""
        if let active = builtVersions.first {
            for (i, sec) in active.sortedSections.enumerated() {
                let verse = SongVerse(label: sec.label, verseType: sec.type, text: sec.plainText, order: i)
                verse.song = song
                lyrics += " " + sec.plainText
            }
        }
        song.searchText = Song.makeSearchText(
            title: song.title, titles: song.titles, author: song.author,
            authorWords: song.authorWords, songNumber: song.songNumber,
            songbookNumber: song.songbookNumber, lyrics: lyrics
        )
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }

    // MARK: - Edit-log diff (coarse, human-readable change summaries)

    /// Summarize what changed between two parsed song states — for the song editor's
    /// change log. Versions are matched by order; sections by key. Returns [] when
    /// nothing meaningful changed.
    static func summarizeChanges(old: SongImportResult, new: SongImportResult) -> [String] {
        var out: [String] = []
        if old.title != new.title { out.append(String(localized: "Titlu modificat", comment: "Edit log")) }
        if old.author != new.author { out.append(String(localized: "Autor modificat", comment: "Edit log")) }
        if old.key != new.key { out.append(String(localized: "Ton modificat", comment: "Edit log")) }
        if old.tempo != new.tempo { out.append(String(localized: "Tempo modificat", comment: "Edit log")) }
        if old.themes != new.themes { out.append(String(localized: "Teme modificate", comment: "Edit log")) }
        if old.verified != new.verified {
            out.append(new.verified ? String(localized: "Marcat verificat", comment: "Edit log")
                                     : String(localized: "Verificare eliminată", comment: "Edit log"))
        }

        func vname(_ v: SongImportVersion, _ i: Int) -> String { v.name.isEmpty ? "#\(i + 1)" : v.name }
        let multi = new.versions.count > 1
        let maxV = Swift.max(old.versions.count, new.versions.count)
        for i in 0..<maxV {
            let ov = i < old.versions.count ? old.versions[i] : nil
            let nv = i < new.versions.count ? new.versions[i] : nil
            if let nv, ov == nil {
                out.append(String(localized: "Versiune «\(vname(nv, i))» adăugată", comment: "Edit log"))
            } else if let ov, nv == nil {
                out.append(String(localized: "Versiune «\(vname(ov, i))» ștearsă", comment: "Edit log"))
            } else if let ov, let nv {
                out.append(contentsOf: summarizeSectionChanges(old: ov.sections, new: nv.sections,
                                                               versionName: vname(nv, i), multiVersion: multi))
            }
        }
        return out
    }

    private static func summarizeSectionChanges(old: [SongImportSection], new: [SongImportSection],
                                                versionName: String, multiVersion: Bool) -> [String] {
        func skey(_ s: SongImportSection) -> String { s.sectionKey.isEmpty ? s.label : s.sectionKey }
        let oldByKey = Dictionary(old.map { (skey($0), $0) }, uniquingKeysWith: { a, _ in a })
        let newByKey = Dictionary(new.map { (skey($0), $0) }, uniquingKeysWith: { a, _ in a })
        let suffix = multiVersion ? " (\(versionName))" : ""
        var out: [String] = []
        for (k, ns) in newByKey {
            if let os = oldByKey[k] {
                if os.lines != ns.lines || os.repeatCount != ns.repeatCount || os.label != ns.label {
                    out.append(String(localized: "«\(ns.label)» editat", comment: "Edit log") + suffix)
                }
            } else {
                out.append(String(localized: "«\(ns.label)» adăugat", comment: "Edit log") + suffix)
            }
        }
        for (k, os) in oldByKey where newByKey[k] == nil {
            out.append(String(localized: "«\(os.label)» șters", comment: "Edit log") + suffix)
        }
        return out.sorted()
    }

    /// Reuse an existing Songbook with the same name, or create and insert a new one.
    private static func upsertSongbook(_ sb: SongImportSongbook, modelContext: ModelContext) -> Songbook {
        let name = sb.name
        let descriptor = FetchDescriptor<Songbook>(predicate: #Predicate { $0.name == name })
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let book = Songbook(name: sb.name, publisher: sb.publisher, language: sb.language, year: sb.year)
        modelContext.insert(book)
        return book
    }

    /// Build the rich version graph from an import result (not yet attached to a song).
    /// When the importer only produced flat verses, synthesize a single "Original" version.
    private static func makeVersions(from result: SongImportResult) -> [SongVersion] {
        let importVersions: [SongImportVersion]
        if !result.versions.isEmpty {
            importVersions = result.versions
        } else {
            let sections = result.verses.map { v in
                SongImportSection(
                    sectionKey: v.label.isEmpty ? "s\(v.order)" : v.label,
                    type: v.verseType,
                    label: v.label,
                    order: v.order,
                    lines: v.text.components(separatedBy: "\n").map { SongLine(text: $0) }
                )
            }
            importVersions = [SongImportVersion(name: "Original", key: result.key, tempo: result.tempo, sections: sections)]
        }

        return importVersions.enumerated().map { vi, iv in
            let version = SongVersion(
                name: iv.name.isEmpty ? "Versiunea \(vi + 1)" : iv.name,
                order: vi,
                language: iv.language,
                key: iv.key,
                capo: iv.capo,
                tempo: iv.tempo,
                timeSignature: iv.timeSignature,
                copyright: iv.copyright,
                ccliNumber: iv.ccliNumber,
                source: iv.source
            )
            version.displayTitle = iv.displayTitle
            version.author = iv.author
            version.titles = iv.titles
            version.authorWords = iv.authorWords
            version.authorMusic = iv.authorMusic
            version.authorTranslation = iv.authorTranslation
            version.style = iv.style
            version.songbookNumber = iv.songbookNumber
            version.themes = iv.themes
            version.notes = iv.notes
            version.songbookName = iv.songbookName
            version.repeatStyle = iv.repeatStyle
            version.overridesMetadata = iv.overridesMetadata
            version.arrangement = iv.arrangement
            for sec in iv.sections.sorted(by: { $0.order < $1.order }) {
                let section = SongSection(
                    sectionKey: sec.sectionKey, type: sec.type, label: sec.label,
                    order: sec.order, repeatCount: sec.repeatCount, lines: sec.lines
                )
                section.version = version
            }
            return version
        }
    }

    /// Append an import result as additional version(s) of an existing song (the user's
    /// "a song can have 3 versions" case). The active/first version — and therefore the
    /// flattened SongVerse cache — is unchanged; only searchText grows.
    private static func appendVersions(from result: SongImportResult, to song: Song) {
        let newVersions = makeVersions(from: result)
        let base = song.versions.count
        var extraLyrics = ""
        for (i, version) in newVersions.enumerated() {
            version.order = base + i
            if version.name.isEmpty || version.name == "Original" {
                version.name = "Versiunea \(base + i + 1)"
            }
            version.song = song
            for sec in version.sortedSections { extraLyrics += " " + sec.plainText }
        }
        if !extraLyrics.isEmpty { song.searchText += " " + extraLyrics.lowercased() }
        finalizeVersionMetadata(for: song)
    }

    /// Re-flatten the ACTIVE (original) version into the SongVerse cache +
    /// searchText, and re-link Song.songbook from the original's songbookName —
    /// call after changing which version is the original.
    static func applyOriginalVersionChange(for song: Song, modelContext: ModelContext) {
        for verse in song.verses { modelContext.delete(verse) }
        var lyrics = ""
        if let active = song.activeVersion {
            for (i, sec) in active.sortedSections.enumerated() {
                let verse = SongVerse(label: sec.label, verseType: sec.type, text: sec.plainText, order: i)
                verse.song = song
                lyrics += " " + sec.plainText
            }
            if !active.songbookName.isEmpty {
                let all = (try? modelContext.fetch(FetchDescriptor<Songbook>())) ?? []
                song.songbook = all.first { $0.name == active.songbookName } ?? {
                    let book = Songbook(name: active.songbookName)
                    modelContext.insert(book)
                    return book
                }()
            }
        }
        song.searchText = Song.makeSearchText(
            title: song.title, titles: song.titles, author: song.author,
            authorWords: song.authorWords, songNumber: song.songNumber,
            songbookNumber: song.songbookNumber, lyrics: lyrics
        )
        song.modifiedDate = .now
        try? modelContext.save()
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }

    /// Auto-stamp „Date proprii pentru versiune" on versions whose imported
    /// metadata DIFFERS from the first version's (different book, key, author…),
    /// and pick the ORIGINAL (default) version: keep an explicit user choice if
    /// still valid, else the first version that references a songbook, else the
    /// first by order.
    static func finalizeVersionMetadata(for song: Song) {
        let versions = song.sortedVersions
        guard let first = versions.first else { return }

        for v in versions.dropFirst() where !v.overridesMetadata {
            let differs = v.key != first.key
                || v.language != first.language
                || v.author != first.author
                || v.songbookName != first.songbookName
                || v.songbookNumber != first.songbookNumber
                || v.copyright != first.copyright
                || v.ccliNumber != first.ccliNumber
                || v.tempo != first.tempo
                || v.style != first.style
            if differs { v.overridesMetadata = true }
        }

        // Respect an explicit still-valid choice; otherwise default the original
        // to the first version that carries a songbook.
        if versions.contains(where: { $0.id.uuidString == song.originalVersionID }) { return }
        let original = versions.first(where: { !$0.songbookName.isEmpty }) ?? first
        song.originalVersionID = original.id.uuidString
    }

    /// Normalized key for duplicate detection (diacritic- and case-insensitive, whitespace-collapsed).
    static func normalizedSongKey(_ title: String) -> String {
        title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// What to do when an imported song matches one already in the library.
enum SongDuplicateResolution {
    case addAsVersion   // append the import as a new version of the existing song
    case replace        // delete the existing song, import fresh
    case keepBoth       // import as a separate song
    case skip           // ignore the import
}
