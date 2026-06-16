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

    /// Registered Bible importers. Add new importers here to support additional formats.
    private static let bibleImporters: [SupportedBibleFormat: BibleImporter] = {
        var importers: [SupportedBibleFormat: BibleImporter] = [:]
        let topPresenterImporter = TopPresenterBibleImporter()
        importers[topPresenterImporter.format] = topPresenterImporter
        let osisImporter = OSISBibleImporter()
        importers[osisImporter.format] = osisImporter
        let zefaniaImporter = ZefaniaBibleImporter()
        importers[zefaniaImporter.format] = zefaniaImporter
        let mySwordImporter = MySwordBibleImporter()
        importers[mySwordImporter.format] = mySwordImporter
        let usfmImporter = USFMBibleImporter()
        importers[usfmImporter.format] = usfmImporter
        let unboundImporter = UnboundBibleImporter()
        importers[unboundImporter.format] = unboundImporter
        return importers
    }()

    /// Registered Song importers. Add new importers here to support additional formats.
    private static let songImporters: [SupportedSongFormat: SongImporter] = {
        var importers: [SupportedSongFormat: SongImporter] = [:]
        let openSongImporter = OpenSongImporter()
        importers[openSongImporter.format] = openSongImporter
        let openLyricsImporter = OpenLyricsImporter()
        importers[openLyricsImporter.format] = openLyricsImporter
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
    struct BibleConflict: Error {
        let code: String
        let existingName: String
        let existingVerses: Int
        let incomingName: String
        let incomingVerses: Int
    }

    /// Cancelled by the user — callers should ignore silently.
    struct BibleImportCancelled: Error {}

    /// Finds an already-imported module by code (case-insensitive abbreviation).
    static func existingBibleModule(code: String, modelContext: ModelContext) -> BibleModule? {
        let needle = code.lowercased()
        guard !needle.isEmpty else { return nil }
        let all = (try? modelContext.fetch(FetchDescriptor<BibleModule>())) ?? []
        return all.first { $0.abbreviation.lowercased() == needle }
    }

    static func importBible(
        fileURL: URL,
        format: SupportedBibleFormat,
        modelContext: ModelContext,
        resolution: BibleConflictResolution = .keepBoth,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws -> BibleModule {
        guard let importer = bibleImporters[format] else {
            throw BibleImportError.unsupportedFormat(format.displayName)
        }

        progressHandler?(0.1, String(localized: "Reading file...", comment: "Import progress"))

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
                progressHandler?(0.5, String(localized: "Merging...", comment: "Import progress"))
                mergeBible(result, into: existing, modelContext: modelContext)
                try modelContext.save()
                progressHandler?(1.0, String(localized: "Complete!", comment: "Import progress"))
                return existing
            case .replace:
                modelContext.delete(existing)
            case .keepBoth:
                resolvedName = uniqueModuleName(result.moduleName, modelContext: modelContext)
            }
        }

        progressHandler?(0.5, String(localized: "Importing books...", comment: "Import progress"))

        // Create SwiftData models
        let module = BibleModule(
            name: resolvedName,
            abbreviation: result.abbreviation,
            language: result.language,
            sourceFormat: format.rawValue,
            moduleDescription: result.description,
            versification: result.versification,
            canon: result.canon,
            nameLocal: result.nameLocal,
            languageName: result.languageName,
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
            let book = BibleBook(
                name: importBook.name,
                bookNumber: importBook.bookNumber,
                testament: importBook.testament,
                nameEnglish: importBook.nameEnglish,
                abbreviation: importBook.abbreviation,
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

            let progress = 0.5 + (Double(index + 1) / Double(totalBooks)) * 0.4
            progressHandler?(progress, String(localized: "Importing \(importBook.name)...", comment: "Import progress"))
        }

        progressHandler?(0.95, String(localized: "Saving...", comment: "Import progress"))
        try modelContext.save()
        progressHandler?(1.0, String(localized: "Complete!", comment: "Import progress"))

        return module
    }

    /// Total verse count of a parsed result (for the conflict dialog stats).
    static func verseCount(of result: BibleImportResult) -> Int {
        result.books.reduce(0) { $0 + $1.chapters.reduce(0) { $0 + $1.verses.count } }
    }

    static func verseCount(of module: BibleModule) -> Int {
        module.books.reduce(0) { $0 + $1.chapters.reduce(0) { $0 + $1.verses.count } }
    }

    /// Disambiguated name when keeping both ("Name", "Name (2)", "Name (3)"…).
    private static func uniqueModuleName(_ base: String, modelContext: ModelContext) -> String {
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
    private static func mergeBible(_ result: BibleImportResult, into module: BibleModule, modelContext: ModelContext) {
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
    static func detectBibleFormat(fileURL: URL) -> SupportedBibleFormat? {
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

        let result = try await importer.parse(fileURL: fileURL)
        return createSongFromResult(result, collection: collection, modelContext: modelContext)
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

        let result = try await importer.parse(fileURL: fileURL)
        _ = createSongFromResult(result, collection: collection, modelContext: modelContext)

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
        progressHandler: ((Double, String) -> Void)? = nil
    ) async -> SongBatchResult {
        var result = SongBatchResult()

        // Expand directories into their files (flat, like before)
        var fileURLs: [(url: URL, parent: URL?)] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue {
                let contents = (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                )) ?? []
                for child in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    fileURLs.append((child, url))
                }
                if contents.isEmpty {
                    result.failures.append((url.lastPathComponent, String(localized: "Directorul este gol.", comment: "Import error")))
                }
            } else {
                fileURLs.append((url, nil))
            }
            if accessing { /* keep open until the end of this function */ }
        }

        guard !fileURLs.isEmpty else { return result }

        // Find or create the collection lazily (only once something imports)
        func collection() -> SongCollection {
            if let existing = result.collection { return existing }
            let descriptor = FetchDescriptor<SongCollection>(
                predicate: #Predicate { $0.name == collectionName }
            )
            if let found = (try? modelContext.fetch(descriptor))?.first {
                result.collection = found
                return found
            }
            let fresh = SongCollection(name: collectionName, sourceFormat: "mixed")
            modelContext.insert(fresh)
            result.collection = fresh
            return fresh
        }

        for (index, item) in fileURLs.enumerated() {
            let name = item.url.lastPathComponent
            progressHandler?(
                Double(index) / Double(fileURLs.count),
                String(localized: "Se importă \(name)…", comment: "Import progress")
            )

            guard let format = detectSongFormat(fileURL: item.url) else {
                result.failures.append((name, String(localized: "Format necunoscut (acceptat: OpenSong/OpenLyrics XML, PPTX, PPT).", comment: "Import error")))
                continue
            }
            guard let importer = songImporters[format] else {
                result.failures.append((name, String(localized: "Niciun importator pentru acest format.", comment: "Import error")))
                continue
            }

            let accessing = item.url.startAccessingSecurityScopedResource()
            defer { if accessing { item.url.stopAccessingSecurityScopedResource() } }

            do {
                let parsed = try await importer.parse(fileURL: item.url)
                _ = createSongFromResult(parsed, collection: collection(), modelContext: modelContext)
                result.importedTitles.append(parsed.title)
            } catch {
                result.failures.append((name, error.localizedDescription))
            }
        }

        if result.collection != nil {
            try? modelContext.save()
        }
        progressHandler?(1.0, String(localized: "Gata!", comment: "Import progress"))
        return result
    }

    /// Auto-detect song format from file content
    static func detectSongFormat(fileURL: URL) -> SupportedSongFormat? {
        let ext = fileURL.pathExtension.lowercased()

        // PowerPoint files
        if ext == "pptx" || ext == "ppt" {
            return .powerPoint
        }

        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { return nil }
        guard let content = String(data: data.prefix(2000), encoding: .utf8) else { return nil }

        if content.contains("<song") && (content.contains("openlyrics") || content.contains("OpenLyrics")) {
            return .openLyricsXML
        } else if content.contains("<song") && (content.contains("<lyrics>") || content.contains("<title>")) {
            return .openSongXML
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

        for importVerse in result.verses {
            let verse = SongVerse(
                label: importVerse.label,
                verseType: importVerse.verseType,
                text: importVerse.text,
                order: importVerse.order
            )
            verse.song = song
        }

        return song
    }
}
