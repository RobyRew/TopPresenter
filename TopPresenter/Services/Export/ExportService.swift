//
//  ExportService.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import Foundation
import SwiftData

/// Service for exporting Bible modules and Song collections to various file formats.
final class ExportService {

    // MARK: - Public API — Bible

    /// Export a Bible module to the specified format at the given URL.
    static func exportBible(
        module: BibleModule,
        format: SupportedExportFormat,
        to fileURL: URL,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        progressHandler?(0.05, String(localized: "Preparing export...", comment: "Export progress"))

        let content: String

        switch format {
        case .topPresenter:
            content = try await exportToTopPresenterJSON(module: module, progressHandler: progressHandler)
        case .plainText:
            content = try await exportToPlainText(module: module, progressHandler: progressHandler)
        case .csv:
            content = try await exportToCSV(module: module, progressHandler: progressHandler)
        }

        progressHandler?(0.95, String(localized: "Writing file...", comment: "Export progress"))
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        progressHandler?(1.0, String(localized: "Complete!", comment: "Export progress"))
    }

    // MARK: - TopPresenter JSON Export

    private static func exportToTopPresenterJSON(
        module: BibleModule,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> String {
        let sortedBooks = module.books.sorted { $0.bookNumber < $1.bookNumber }
        let totalBooks = sortedBooks.count

        var booksArray: [[String: Any]] = []

        for (index, book) in sortedBooks.enumerated() {
            let sortedChapters = book.sortedChapters

            var chaptersArray: [[String: Any]] = []
            for chapter in sortedChapters {
                let sortedVerses = chapter.sortedVerses

                var versesArray: [[String: Any]] = []
                for verse in sortedVerses {
                    // GOAT v2: always-present text + optional rich fields.
                    var v: [String: Any] = [
                        "number": verse.verseNumber,
                        "text": verse.text
                    ]
                    let runs = verse.runs
                    if !runs.isEmpty {
                        v["runs"] = runs.map { run -> [String: Any] in
                            var r: [String: Any] = ["text": run.text, "kind": run.kind]
                            if let s = run.strong { r["strong"] = s }
                            if let m = run.morph { r["morph"] = m }
                            if let g = run.gloss { r["gloss"] = g }
                            return r
                        }
                    }
                    if verse.hasWordsOfChrist { v["hasWordsOfChrist"] = true }
                    if !verse.gloss.isEmpty { v["gloss"] = verse.gloss }
                    let footnotes = verse.footnotes
                    if !footnotes.isEmpty {
                        v["footnotes"] = footnotes.map { ["marker": $0.marker, "text": $0.text] }
                    }
                    let xrefs = verse.crossReferences
                    if !xrefs.isEmpty {
                        v["crossReferences"] = xrefs.map { ref -> [String: Any] in
                            var r: [String: Any] = ["targets": ref.targets]
                            if let l = ref.label { r["label"] = l }
                            return r
                        }
                    }
                    if let ext = decodeExt(verse.extensionsJSON) { v["_extensions"] = ext }
                    versesArray.append(v)
                }

                var chapterDict: [String: Any] = [
                    "number": chapter.chapterNumber,
                    "verses": versesArray
                ]
                let headings = chapter.headings
                if !headings.isEmpty {
                    chapterDict["headings"] = headings.map {
                        ["beforeVerse": $0.beforeVerse, "level": $0.level, "text": $0.text]
                    }
                }
                if let ext = decodeExt(chapter.extensionsJSON) { chapterDict["_extensions"] = ext }
                chaptersArray.append(chapterDict)
            }

            var bookDict: [String: Any] = [
                "number": book.bookNumber,
                "name": book.name,
                "testament": book.testament,
                "category": BibleBookCategory.from(bookNumber: book.bookNumber).englishName,
                "chapters": chaptersArray
            ]
            if !book.nameEnglish.isEmpty { bookDict["nameEnglish"] = book.nameEnglish }
            if !book.abbreviation.isEmpty { bookDict["abbreviation"] = book.abbreviation }
            if !book.abbreviationEnglish.isEmpty { bookDict["abbreviationEnglish"] = book.abbreviationEnglish }
            if book.expectedChapters > 0 { bookDict["expectedChapters"] = book.expectedChapters }
            if !book.introduction.isEmpty { bookDict["introduction"] = book.introduction }
            if let ext = decodeExt(book.extensionsJSON) { bookDict["_extensions"] = ext }
            booksArray.append(bookDict)

            let progress = 0.1 + (Double(index + 1) / Double(totalBooks)) * 0.8
            progressHandler?(progress, String(localized: "Exporting \(book.name)...", comment: "Export progress"))
        }

        // Count totals
        var totalChapters = 0
        var totalVerses = 0
        for book in sortedBooks {
            totalChapters += book.chapters.count
            for chapter in book.chapters {
                totalVerses += chapter.verses.count
            }
        }

        var translationDict: [String: Any] = [
            "code": module.abbreviation,
            "name": module.name,
            "language": module.language,
            "description": module.moduleDescription
        ]
        if let v = module.versification { translationDict["versification"] = v }
        if let c = module.canon { translationDict["canon"] = c }
        if !module.nameLocal.isEmpty { translationDict["nameLocal"] = module.nameLocal }
        if !module.languageName.isEmpty { translationDict["languageName"] = module.languageName }
        if !module.copyright.isEmpty { translationDict["copyright"] = module.copyright }
        if !module.aboutText.isEmpty { translationDict["about"] = module.aboutText }
        if !module.textSource.isEmpty { translationDict["source"] = module.textSource }
        if let y = module.year { translationDict["year"] = y }
        if module.direction != "ltr" { translationDict["direction"] = module.direction }
        if module.hasWordsOfChrist { translationDict["hasWordsOfChrist"] = true }
        if module.hasStrongs { translationDict["hasStrongs"] = true }
        if module.incomplete { translationDict["incomplete"] = true }
        if let ext = decodeExt(module.extensionsJSON) { translationDict["_extensions"] = ext }

        let result: [String: Any] = [
            "schemaVersion": "1.0.0",
            "format": "TopPresenter Bible",
            "translation": translationDict,
            "exportInfo": [
                "source": "TopPresenter",
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "exporterVersion": "1.0.0",
                "totalBooks": sortedBooks.count,
                "totalChapters": totalChapters,
                "totalVerses": totalVerses
            ],
            "books": booksArray
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }
        return jsonString
    }

    /// Decode a stored `_extensions` JSON string back into an object for export.
    private static func decodeExt(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !obj.isEmpty else { return nil }
        return obj
    }

    // MARK: - Plain Text Export

    private static func exportToPlainText(
        module: BibleModule,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> String {
        let sortedBooks = module.books.sorted { $0.bookNumber < $1.bookNumber }
        let totalBooks = sortedBooks.count
        var lines: [String] = []

        lines.append("# \(module.name)")
        if !module.moduleDescription.isEmpty {
            lines.append("# \(module.moduleDescription)")
        }
        lines.append("")

        for (index, book) in sortedBooks.enumerated() {
            lines.append("=== \(book.name) ===")
            lines.append("")

            for chapter in book.sortedChapters {
                lines.append("--- Chapter \(chapter.chapterNumber) ---")
                for verse in chapter.sortedVerses {
                    lines.append("\(verse.verseNumber)\t\(verse.text)")
                }
                lines.append("")
            }

            let progress = 0.1 + (Double(index + 1) / Double(totalBooks)) * 0.8
            progressHandler?(progress, String(localized: "Exporting \(book.name)...", comment: "Export progress"))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - CSV Export

    private static func exportToCSV(
        module: BibleModule,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> String {
        let sortedBooks = module.books.sorted { $0.bookNumber < $1.bookNumber }
        let totalBooks = sortedBooks.count
        var lines: [String] = []

        lines.append("\"Book\",\"Chapter\",\"Verse\",\"Text\"")

        for (index, book) in sortedBooks.enumerated() {
            for chapter in book.sortedChapters {
                for verse in chapter.sortedVerses {
                    let escapedText = verse.text
                        .replacingOccurrences(of: "\"", with: "\"\"")
                    lines.append("\"\(book.name)\",\(chapter.chapterNumber),\(verse.verseNumber),\"\(escapedText)\"")
                }
            }

            let progress = 0.1 + (Double(index + 1) / Double(totalBooks)) * 0.8
            progressHandler?(progress, String(localized: "Exporting \(book.name)...", comment: "Export progress"))
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Public API — Songs

    /// Export a song collection to the specified format at the given URL.
    static func exportSongs(
        collection: SongCollection,
        format: SupportedSongExportFormat,
        to fileURL: URL,
        progressHandler: ((Double, String) -> Void)? = nil
    ) async throws {
        progressHandler?(0.05, String(localized: "Preparing export...", comment: "Export progress"))

        let content: String

        switch format {
        case .topPresenter:
            content = try await exportSongsToTopPresenterJSON(collection: collection, progressHandler: progressHandler)
        case .openLyricsXML:
            content = try await exportSongsToOpenLyrics(collection: collection, progressHandler: progressHandler)
        case .plainText:
            content = try await exportSongsToPlainText(collection: collection, progressHandler: progressHandler)
        }

        progressHandler?(0.95, String(localized: "Writing file...", comment: "Export progress"))
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        progressHandler?(1.0, String(localized: "Complete!", comment: "Export progress"))
    }

    // MARK: - TopPresenter Song JSON Export (GOAT v2.0.0 — one song per file)

    static let songExporterVersion = "1.0.0"

    /// Serialize a single song to the canonical single-song GOAT document.
    static func exportSongToTopPresenterJSON(_ song: Song) throws -> String {
        let result: [String: Any] = [
            "schemaVersion": songExporterVersion,
            "format": "TopPresenter Song",
            "exportInfo": [
                "source": "TopPresenter",
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "exporterVersion": songExporterVersion
            ],
            "song": songDictV2(song)
        ]
        return try jsonString(from: result)
    }

    /// Bulk export: write one GOAT file per song into a directory.
    static func exportSongsToFolder(
        _ songs: [Song],
        directory: URL,
        progressHandler: ((Double, String) -> Void)? = nil
    ) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = max(songs.count, 1)
        for (index, song) in songs.enumerated() {
            let json = try exportSongToTopPresenterJSON(song)
            let name = sanitizeFilename(song.title.isEmpty ? "song-\(index + 1)" : song.title)
            let url = directory.appendingPathComponent("\(name).json")
            try json.write(to: url, atomically: true, encoding: .utf8)
            progressHandler?(Double(index + 1) / Double(total), String(localized: "Exporting \(song.title)...", comment: "Export progress"))
        }
    }

    /// Bundle several songs into a single file (array of GOAT song objects).
    private static func exportSongsToTopPresenterJSON(
        collection: SongCollection,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> String {
        let sortedSongs = collection.sortedSongs
        let total = max(sortedSongs.count, 1)
        var songsArray: [[String: Any]] = []
        for (index, song) in sortedSongs.enumerated() {
            songsArray.append(songDictV2(song))
            progressHandler?(0.1 + (Double(index + 1) / Double(total)) * 0.8,
                             String(localized: "Exporting \(song.title)...", comment: "Export progress"))
        }
        let result: [String: Any] = [
            "schemaVersion": songExporterVersion,
            "format": "TopPresenter Songs",
            "collection": [
                "name": collection.name,
                "description": collection.collectionDescription,
                "sourceFormat": collection.sourceFormat
            ],
            "exportInfo": [
                "source": "TopPresenter",
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "exporterVersion": songExporterVersion,
                "totalSongs": sortedSongs.count
            ],
            "songs": songsArray
        ]
        return try jsonString(from: result)
    }

    // MARK: GOAT dictionary builders

    static func songDictV2(_ song: Song) -> [String: Any] {
        var dict: [String: Any] = [
            "title": song.title,
            "language": song.language,
            "style": song.style,
            "copyright": song.copyright,
            "ccliNumber": song.ccliNumber,
            "notes": song.notes
        ]
        if !song.titles.isEmpty { dict["titles"] = song.titles }
        if !song.themes.isEmpty { dict["themes"] = song.themes }
        if !song.author.isEmpty { dict["author"] = song.author }
        if !song.authorWords.isEmpty { dict["authorWords"] = song.authorWords }
        if !song.authorMusic.isEmpty { dict["authorMusic"] = song.authorMusic }
        if !song.authorTranslation.isEmpty { dict["authorTranslation"] = song.authorTranslation }
        if let sb = song.songbook {
            dict["songbook"] = [
                "name": sb.name, "publisher": sb.publisher,
                "language": sb.language, "year": sb.year, "number": song.songbookNumber
            ]
        } else if !song.songNumber.isEmpty {
            dict["songNumber"] = song.songNumber
        }
        let media = song.media.map { m -> [String: Any] in
            var d: [String: Any] = ["role": m.role, "kind": m.kind, "filename": m.filename]
            if let b = m.bookmark { d["bookmark"] = b }
            return d
        }
        if !media.isEmpty { dict["media"] = media }
        if song.verified { dict["verified"] = true }
        dict["versions"] = song.sortedVersions.map { versionDictV2($0) }
        if let ext = decodeExt(song.extensionsJSON) { dict["_extensions"] = ext }
        return dict
    }

    private static func versionDictV2(_ version: SongVersion) -> [String: Any] {
        var dict: [String: Any] = [
            "name": version.name,
            "language": version.language,
            "key": version.key,
            "capo": version.capo,
            "tempo": version.tempo,
            "timeSignature": version.timeSignature,
            "copyright": version.copyright,
            "ccliNumber": version.ccliNumber,
            "source": version.source
        ]
        if !version.displayTitle.isEmpty { dict["displayTitle"] = version.displayTitle }
        if !version.author.isEmpty { dict["author"] = version.author }
        if !version.authorWords.isEmpty { dict["authorWords"] = version.authorWords }
        if !version.authorMusic.isEmpty { dict["authorMusic"] = version.authorMusic }
        if !version.authorTranslation.isEmpty { dict["authorTranslation"] = version.authorTranslation }
        if !version.style.isEmpty { dict["style"] = version.style }
        if !version.songbookNumber.isEmpty { dict["songbookNumber"] = version.songbookNumber }
        if !version.songbookName.isEmpty { dict["songbook"] = ["name": version.songbookName] }
        if !version.themes.isEmpty { dict["themes"] = version.themes }
        if !version.notes.isEmpty { dict["notes"] = version.notes }
        if !version.repeatStyle.isEmpty { dict["repeatStyle"] = version.repeatStyle }
        if version.overridesMetadata { dict["overridesMetadata"] = true }
        if version.song?.originalVersionID == version.id.uuidString { dict["original"] = true }
        if !version.arrangement.isEmpty { dict["arrangement"] = version.arrangement }
        dict["sections"] = version.sortedSections.map { sectionDictV2($0) }
        return dict
    }

    private static func sectionDictV2(_ section: SongSection) -> [String: Any] {
        let lines = section.lines.map { line -> [String: Any] in
            var l: [String: Any] = ["text": line.text]
            if !line.chords.isEmpty { l["chords"] = line.chords.map { ["sym": $0.sym, "pos": $0.pos] } }
            if !line.translations.isEmpty { l["translations"] = line.translations }
            return l
        }
        var dict: [String: Any] = [
            "id": section.sectionKey,
            "type": section.type,
            "label": section.label,
            "order": section.order,
            "lines": lines
        ]
        if section.repeatCount > 1 { dict["repeat"] = section.repeatCount }
        return dict
    }

    private static func jsonString(from object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw ExportError.encodingFailed }
        return string
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return String(cleaned.prefix(120)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - OpenLyrics XML Export

    private static func exportSongsToOpenLyrics(
        collection: SongCollection,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> String {
        let sortedSongs = collection.sortedSongs
        var xmlParts: [String] = []

        xmlParts.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        xmlParts.append("<!-- format: TopPresenter Songs (OpenLyrics) -->")
        xmlParts.append("<!-- collection: \(escapeXML(collection.name)) -->")
        xmlParts.append("")

        for (index, song) in sortedSongs.enumerated() {
            xmlParts.append("<song xmlns=\"http://openlyrics.info/namespace/2009/song\" version=\"0.9\">")
            xmlParts.append("  <properties>")
            xmlParts.append("    <titles><title>\(escapeXML(song.title))</title></titles>")
            if !song.author.isEmpty {
                xmlParts.append("    <authors><author>\(escapeXML(song.author))</author></authors>")
            }
            if !song.copyright.isEmpty {
                xmlParts.append("    <copyright>\(escapeXML(song.copyright))</copyright>")
            }
            if !song.ccliNumber.isEmpty {
                xmlParts.append("    <ccliNo>\(escapeXML(song.ccliNumber))</ccliNo>")
            }
            if !song.key.isEmpty {
                xmlParts.append("    <key>\(escapeXML(song.key))</key>")
            }
            if !song.tempo.isEmpty {
                xmlParts.append("    <tempo>\(escapeXML(song.tempo))</tempo>")
            }
            xmlParts.append("  </properties>")
            xmlParts.append("  <lyrics>")

            for verse in song.sortedVerses {
                let name = verse.verseType == "chorus" ? "c" : "v\(verse.order + 1)"
                xmlParts.append("    <verse name=\"\(name)\">")
                let lines = verse.text.components(separatedBy: "\n")
                for line in lines {
                    xmlParts.append("      <lines>\(escapeXML(line))</lines>")
                }
                xmlParts.append("    </verse>")
            }

            xmlParts.append("  </lyrics>")
            xmlParts.append("</song>")
            xmlParts.append("")

            let progress = 0.1 + (Double(index + 1) / Double(sortedSongs.count)) * 0.8
            progressHandler?(progress, String(localized: "Exporting \(song.title)...", comment: "Export progress"))
        }

        return xmlParts.joined(separator: "\n")
    }

    // MARK: - Songs Plain Text Export

    private static func exportSongsToPlainText(
        collection: SongCollection,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> String {
        let sortedSongs = collection.sortedSongs
        var lines: [String] = []

        lines.append("# TopPresenter Songs — \(collection.name)")
        lines.append("")

        for (index, song) in sortedSongs.enumerated() {
            lines.append("=== \(song.title) ===")
            if !song.author.isEmpty { lines.append("Author: \(song.author)") }
            if !song.copyright.isEmpty { lines.append("Copyright: \(song.copyright)") }
            lines.append("")

            for verse in song.sortedVerses {
                lines.append("[\(verse.label)]")
                lines.append(verse.text)
                lines.append("")
            }

            lines.append("---")
            lines.append("")

            let progress = 0.1 + (Double(index + 1) / Double(sortedSongs.count)) * 0.8
            progressHandler?(progress, String(localized: "Exporting \(song.title)...", comment: "Export progress"))
        }

        return lines.joined(separator: "\n")
    }

    /// Escape special XML characters
    private static func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - Export Errors
enum ExportError: LocalizedError {
    case encodingFailed
    case noModuleSelected
    case writeError(String)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return String(localized: "Failed to encode data.", comment: "Export error")
        case .noModuleSelected:
            return String(localized: "No Bible module selected for export.", comment: "Export error")
        case .writeError(let detail):
            return String(localized: "Failed to write file: \(detail)", comment: "Export error")
        }
    }
}
