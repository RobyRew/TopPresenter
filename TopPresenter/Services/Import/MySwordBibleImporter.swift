//
//  MySwordBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation
import SQLite3

/// Importer for MySword Bible format (.bbl.mybible).
/// MySword uses SQLite databases with a `Bible` table containing columns:
/// Book (int), Chapter (int), Verse (int), Scripture (text with GBF tags).
/// A `Details` table holds module metadata.
final class MySwordBibleImporter: BibleImporter {
    let format: SupportedBibleFormat = .mySword

    func parse(fileURL: URL) async throws -> BibleImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BibleImportError.fileNotFound
        }

        var db: OpaquePointer?
        let openResult = sqlite3_open_v2(fileURL.path, &db, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database = db else {
            let errMsg = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            throw BibleImportError.parsingFailed("Cannot open SQLite database: \(errMsg)")
        }
        defer { sqlite3_close(database) }

        // Read metadata from Details table
        let details = readDetails(database)

        // Read all verses from Bible table
        let books = try readVerses(database)

        guard !books.isEmpty else {
            throw BibleImportError.invalidFormat("No books found in MySword database")
        }

        return BibleImportResult(
            moduleName: details.name.isEmpty ? fileURL.deletingPathExtension().deletingPathExtension().lastPathComponent : details.name,
            abbreviation: details.abbreviation,
            language: details.language.isEmpty ? "en" : details.language,
            description: details.description,
            books: books
        )
    }

    // MARK: - Read Details

    private struct ModuleDetails {
        var name: String = ""
        var abbreviation: String = ""
        var language: String = ""
        var description: String = ""
    }

    private func readDetails(_ db: OpaquePointer) -> ModuleDetails {
        var details = ModuleDetails()

        // Check if Details table exists
        var stmt: OpaquePointer?
        let query = "SELECT * FROM Details LIMIT 1"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            // Try alternate table name
            return readDetailsAlternate(db)
        }
        defer { sqlite3_finalize(stmt) }

        if sqlite3_step(stmt) == SQLITE_ROW {
            let colCount = sqlite3_column_count(stmt)
            for i in 0..<colCount {
                guard let colNameRaw = sqlite3_column_name(stmt, i) else { continue }
                let colName = String(cString: colNameRaw).lowercased()
                let value = columnText(stmt, index: i)

                switch colName {
                case "title", "description":
                    if details.name.isEmpty { details.name = value }
                    else { details.description = value }
                case "abbreviation":
                    details.abbreviation = value
                case "language":
                    details.language = value
                case "info", "information":
                    details.description = value
                default:
                    break
                }
            }
        }

        return details
    }

    private func readDetailsAlternate(_ db: OpaquePointer) -> ModuleDetails {
        var details = ModuleDetails()

        // Try 'info' table (used by some modules)
        var stmt: OpaquePointer?
        let query = "SELECT name, value FROM info"
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            return details
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = columnText(stmt, index: 0).lowercased()
            let value = columnText(stmt, index: 1)
            switch name {
            case "description", "title": details.name = value
            case "abbreviation": details.abbreviation = value
            case "language": details.language = value
            default: break
            }
        }

        return details
    }

    // MARK: - Read Verses

    private func readVerses(_ db: OpaquePointer) throws -> [BibleImportBook] {
        var stmt: OpaquePointer?

        // MySword uses: Book, Chapter, Verse, Scripture
        // Some modules use: book_number, chapter, verse, text
        let queries = [
            "SELECT Book, Chapter, Verse, Scripture FROM Bible ORDER BY Book, Chapter, Verse",
            "SELECT book_number, chapter, verse, text FROM verses ORDER BY book_number, chapter, verse",
            "SELECT book, chapter, verse, text FROM bible ORDER BY book, chapter, verse"
        ]

        var selectedQuery: String?
        for q in queries {
            if sqlite3_prepare_v2(db, q, -1, &stmt, nil) == SQLITE_OK {
                selectedQuery = q
                sqlite3_finalize(stmt)
                stmt = nil
                break
            }
            sqlite3_finalize(stmt)
            stmt = nil
        }

        guard let query = selectedQuery else {
            throw BibleImportError.invalidFormat("Could not find Bible/verses table in database")
        }

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw BibleImportError.parsingFailed("Failed to prepare SQL query")
        }
        defer { sqlite3_finalize(stmt) }

        // Collect raw verse data
        struct RawVerse {
            let bookNum: Int
            let chapter: Int
            let verse: Int
            let text: String
        }

        var rawVerses: [RawVerse] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bookNum = Int(sqlite3_column_int(stmt, 0))
            let chapter = Int(sqlite3_column_int(stmt, 1))
            let verse = Int(sqlite3_column_int(stmt, 2))
            let rawText = columnText(stmt, index: 3)
            let cleanText = stripMySwordTags(rawText)

            if !cleanText.isEmpty {
                rawVerses.append(RawVerse(bookNum: bookNum, chapter: chapter, verse: verse, text: cleanText))
            }
        }

        // Group into books > chapters > verses
        var bookDict: [Int: [Int: [BibleImportVerse]]] = [:]
        for rv in rawVerses {
            bookDict[rv.bookNum, default: [:]][rv.chapter, default: []].append(
                BibleImportVerse(verseNumber: rv.verse, text: rv.text)
            )
        }

        var books: [BibleImportBook] = []
        for bookNum in bookDict.keys.sorted() {
            let chaptersDict = bookDict[bookNum]!
            let chapters = chaptersDict.keys.sorted().map { chapterNum in
                BibleImportChapter(
                    chapterNumber: chapterNum,
                    verses: chaptersDict[chapterNum]!.sorted { $0.verseNumber < $1.verseNumber }
                )
            }

            let bookInfo = BibleBookNumbers.mapping[bookNum]
            let name = bookInfo?.name ?? "Book \(bookNum)"
            let testament = bookInfo?.testament ?? (bookNum <= 39 ? "OT" : "NT")

            books.append(BibleImportBook(
                name: name,
                bookNumber: bookNum,
                testament: testament,
                chapters: chapters
            ))
        }

        return books
    }

    // MARK: - Tag Stripping

    /// Remove MySword GBF tags and HTML tags from verse text, leaving plain text.
    private func stripMySwordTags(_ text: String) -> String {
        var result = text

        // Remove GBF tags like <CM>, <FI>...<Fi>, <FR>...<Fr>, <RF>...<Rf>, etc.
        // Keep the content between formatting tags, remove note content
        let notePattern = "<RF[^>]*>.*?<Rf>"
        if let regex = try? NSRegularExpression(pattern: notePattern, options: .dotMatchesLineSeparators) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove Strong's numbers <WG1234>, <WH1234>
        let strongPattern = "<W[GH]\\d+>"
        if let regex = try? NSRegularExpression(pattern: strongPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove morphological tags <WTxxx>
        let morphPattern = "<WT[^>]*>"
        if let regex = try? NSRegularExpression(pattern: morphPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove title tags but keep content
        let titlePattern = "<TS\\d*>(.*?)<Ts>"
        if let regex = try? NSRegularExpression(pattern: titlePattern, options: .dotMatchesLineSeparators) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove cross-reference tags
        let xrefPattern = "<RX[^>]*>"
        if let regex = try? NSRegularExpression(pattern: xrefPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove remaining GBF paired tags (keep content between them)
        let gbfPairPattern = "<(FI|Fi|FO|Fo|FR|Fr|FU|Fu|CM|CI)>"
        if let regex = try? NSRegularExpression(pattern: gbfPairPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove indent/poetry tags
        let indentPattern = "<P[IF]\\d?>"
        if let regex = try? NSRegularExpression(pattern: indentPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove interlinear tags
        let interlinearPattern = "<[QqEeTtXxDdHhGg]>"
        if let regex = try? NSRegularExpression(pattern: interlinearPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        let wordMarkerPattern = "<w[hgt]>"
        if let regex = try? NSRegularExpression(pattern: wordMarkerPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove HTML tags
        let htmlPattern = "<[^>]+>"
        if let regex = try? NSRegularExpression(pattern: htmlPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Decode HTML entities
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")

        // Clean up whitespace
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }
}
