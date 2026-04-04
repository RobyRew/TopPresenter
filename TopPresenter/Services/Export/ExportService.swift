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
                    versesArray.append([
                        "number": verse.verseNumber,
                        "text": verse.text
                    ])
                }

                chaptersArray.append([
                    "number": chapter.chapterNumber,
                    "verses": versesArray
                ])
            }

            let bookDict: [String: Any] = [
                "number": book.bookNumber,
                "name": book.name,
                "testament": book.testament,
                "category": BibleBookCategory.from(bookNumber: book.bookNumber).englishName,
                "chapters": chaptersArray
            ]
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

        let result: [String: Any] = [
            "schemaVersion": "1.0.0",
            "format": "TopPresenter Bible",
            "translation": [
                "code": module.abbreviation,
                "name": module.name,
                "language": module.language,
                "description": module.moduleDescription
            ],
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

    // MARK: - TopPresenter Songs JSON Export

    private static func exportSongsToTopPresenterJSON(
        collection: SongCollection,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> String {
        let sortedSongs = collection.sortedSongs
        let totalSongs = sortedSongs.count

        var songsArray: [[String: Any]] = []

        for (index, song) in sortedSongs.enumerated() {
            var versesArray: [[String: Any]] = []
            for verse in song.sortedVerses {
                versesArray.append([
                    "label": verse.label,
                    "verseType": verse.verseType,
                    "text": verse.text,
                    "order": verse.order
                ])
            }

            let songDict: [String: Any] = [
                "title": song.title,
                "author": song.author,
                "copyright": song.copyright,
                "ccliNumber": song.ccliNumber,
                "key": song.key,
                "tempo": song.tempo,
                "songNumber": song.songNumber,
                "tags": song.tags,
                "verses": versesArray
            ]
            songsArray.append(songDict)

            let progress = 0.1 + (Double(index + 1) / Double(totalSongs)) * 0.8
            progressHandler?(progress, String(localized: "Exporting \(song.title)...", comment: "Export progress"))
        }

        let result: [String: Any] = [
            "schemaVersion": "1.0.0",
            "format": "TopPresenter Songs",
            "collection": [
                "name": collection.name,
                "description": collection.collectionDescription,
                "sourceFormat": collection.sourceFormat
            ],
            "exportInfo": [
                "source": "TopPresenter",
                "exportDate": ISO8601DateFormatter().string(from: Date()),
                "exporterVersion": "1.0.0",
                "totalSongs": sortedSongs.count
            ],
            "songs": songsArray
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw ExportError.encodingFailed
        }
        return jsonString
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
