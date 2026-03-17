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
        // Add new Song importers here:
        // let myFormatImporter = MyFormatSongImporter()
        // importers[myFormatImporter.format] = myFormatImporter
        return importers
    }()

    // MARK: - Bible Import

    /// Import a Bible file in the specified format
    static func importBible(
        fileURL: URL,
        format: SupportedBibleFormat,
        modelContext: ModelContext,
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

        progressHandler?(0.5, String(localized: "Importing books...", comment: "Import progress"))

        // Create SwiftData models
        let module = BibleModule(
            name: result.moduleName,
            abbreviation: result.abbreviation,
            language: result.language,
            sourceFormat: format.rawValue,
            moduleDescription: result.description
        )
        modelContext.insert(module)

        let totalBooks = result.books.count

        for (index, importBook) in result.books.enumerated() {
            let book = BibleBook(
                name: importBook.name,
                bookNumber: importBook.bookNumber,
                testament: importBook.testament
            )
            book.module = module

            for importChapter in importBook.chapters {
                let chapter = BibleChapter(chapterNumber: importChapter.chapterNumber)
                chapter.book = book

                for importVerse in importChapter.verses {
                    let verse = BibleVerse(
                        verseNumber: importVerse.verseNumber,
                        text: importVerse.text
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

    /// Auto-detect song format from file content
    static func detectSongFormat(fileURL: URL) -> SupportedSongFormat? {
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
