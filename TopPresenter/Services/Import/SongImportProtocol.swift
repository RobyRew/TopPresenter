//
//  SongImportProtocol.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Protocol that all Song format importers must conform to.
/// Implement this protocol to add support for a new song file format.
protocol SongImporter {
    /// The format this importer handles
    var format: SupportedSongFormat { get }

    /// Parse a single song file and return a structured result
    func parse(fileURL: URL) async throws -> SongImportResult

    /// Parse EVERY song contained in a single file. For most formats this is one
    /// song, but a TopPresenter Song JSON *bundle* (`{ "songs": [ … ] }`) holds many —
    /// the scraper userscript emits one bundle per letter. Default = `[parse()]`.
    func parseAll(fileURL: URL) async throws -> [SongImportResult]

    /// Parse a directory of song files (for formats that use one file per song)
    func parseDirectory(directoryURL: URL) async throws -> [SongImportResult]
}

/// Default implementations
extension SongImporter {
    func parseAll(fileURL: URL) async throws -> [SongImportResult] {
        [try await parse(fileURL: fileURL)]
    }

    func parseDirectory(directoryURL: URL) async throws -> [SongImportResult] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var results: [SongImportResult] = []
        for fileURL in contents {
            if format.fileExtensions.contains(fileURL.pathExtension.lowercased()) ||
               fileURL.pathExtension.isEmpty {
                do {
                    let result = try await parse(fileURL: fileURL)
                    results.append(result)
                } catch {
                    // Skip files that can't be parsed
                    continue
                }
            }
        }
        return results
    }
}

/// Result of a song import operation.
///
/// Back-compatible: the legacy flat fields + `verses` are still the minimum an importer
/// must produce. Richer importers (v2 JSON, OpenLyrics, ChordPro…) additionally populate
/// `versions` and the metadata fields; when `versions` is empty, `ImportService` synthesizes
/// a single "Original" version from `verses`.
struct SongImportResult {
    let title: String
    let author: String
    let copyright: String
    let ccliNumber: String
    let key: String
    let tempo: String
    let songNumber: String
    let tags: String
    let verses: [SongImportVerse]

    // v2 additive (all defaulted so existing importers compile unchanged)
    var titles: [String] = []
    var language: String = ""
    var themes: [String] = []
    var style: String = ""
    var songbook: SongImportSongbook? = nil
    var authorWords: String = ""
    var authorMusic: String = ""
    var authorTranslation: String = ""
    var notes: String = ""
    var media: [SongImportMedia] = []
    var versions: [SongImportVersion] = []
    /// Source-specific extras preserved verbatim (`song._extensions` in the JSON):
    /// e.g. melodia.ro's Anatomia Evangheliei, composed year, capo charts. "{}" = none.
    var extensionsJSON: String = "{}"
    /// User-confirmed "checked & good" flag (GOAT `verified`).
    var verified: Bool = false
}

struct SongImportVerse {
    let label: String
    let verseType: String  // "verse", "chorus", "bridge", etc.
    let text: String
    let order: Int
}

// MARK: - v2 rich import structures

// Reference type on purpose: as a value type with this many fields, copying
// `Optional<SongImportVersion>` hit a miscompiled outlined value-witness (segfault).
final class SongImportVersion {
    var name: String
    var displayTitle: String
    var author: String
    var titles: [String]
    var authorWords: String
    var authorMusic: String
    var authorTranslation: String
    var style: String
    var songbookNumber: String
    var songbookName: String
    var themes: [String]
    var notes: String
    var language: String
    var key: String
    var capo: Int
    var tempo: String
    var timeSignature: String
    var copyright: String
    var ccliNumber: String
    var source: String
    var repeatStyle: String
    var overridesMetadata: Bool
    var arrangement: [String]
    var sections: [SongImportSection]

    init(
        name: String = "",
        displayTitle: String = "",
        author: String = "",
        titles: [String] = [],
        authorWords: String = "",
        authorMusic: String = "",
        authorTranslation: String = "",
        style: String = "",
        songbookNumber: String = "",
        songbookName: String = "",
        themes: [String] = [],
        notes: String = "",
        language: String = "",
        key: String = "",
        capo: Int = 0,
        tempo: String = "",
        timeSignature: String = "",
        copyright: String = "",
        ccliNumber: String = "",
        source: String = "",
        repeatStyle: String = "",
        overridesMetadata: Bool = false,
        arrangement: [String] = [],
        sections: [SongImportSection] = []
    ) {
        self.name = name
        self.displayTitle = displayTitle
        self.author = author
        self.titles = titles
        self.authorWords = authorWords
        self.authorMusic = authorMusic
        self.authorTranslation = authorTranslation
        self.style = style
        self.songbookNumber = songbookNumber
        self.songbookName = songbookName
        self.themes = themes
        self.notes = notes
        self.language = language
        self.key = key
        self.capo = capo
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.copyright = copyright
        self.ccliNumber = ccliNumber
        self.source = source
        self.repeatStyle = repeatStyle
        self.overridesMetadata = overridesMetadata
        self.arrangement = arrangement
        self.sections = sections
    }
}

struct SongImportSection {
    var sectionKey: String
    var type: String
    var label: String
    var order: Int
    var repeatCount: Int = 1
    var lines: [SongLine] = []   // SongLine carries chords + bilingual translations
}

struct SongImportSongbook {
    var name: String
    var publisher: String = ""
    var language: String = ""
    var year: String = ""
    var number: String = ""
}

struct SongImportMedia {
    var role: String
    var kind: String
    var filename: String
    var bookmark: String? = nil
}

/// Errors that can occur during song import
enum SongImportError: LocalizedError {
    case fileNotFound
    case invalidFormat(String)
    case parsingFailed(String)
    case emptyFile
    case noSongsFound

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return String(localized: "File not found.", comment: "Import error")
        case .invalidFormat(let detail):
            return String(localized: "Invalid file format: \(detail)", comment: "Import error")
        case .parsingFailed(let detail):
            return String(localized: "Parsing failed: \(detail)", comment: "Import error")
        case .emptyFile:
            return String(localized: "The file is empty.", comment: "Import error")
        case .noSongsFound:
            return String(localized: "No songs were found in the selected location.", comment: "Import error")
        }
    }
}
