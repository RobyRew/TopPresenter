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
nonisolated final class MySwordBibleImporter: BibleImporter {
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

        var result = BibleImportResult(
            moduleName: details.name.isEmpty ? fileURL.deletingPathExtension().deletingPathExtension().lastPathComponent : details.name,
            abbreviation: details.abbreviation,
            language: details.language.isEmpty ? "en" : details.language,
            description: details.description,
            books: books
        )
        result.copyright = details.rights
        result.hasWordsOfChrist = anyWoc
        result.hasStrongs = anyStrong
        return result
    }

    /// Aggregated across every verse — feeds the module-level flags.
    private var anyWoc = false
    private var anyStrong = false

    // MARK: - Read Details

    private struct ModuleDetails {
        var name: String = ""
        var abbreviation: String = ""
        var language: String = ""
        var description: String = ""
        var rights: String = ""
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
                case "rights", "copyright":
                    details.rights = value
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

        // Group into books > chapters > verses, parsing GBF rich markup per verse.
        var bookDict: [Int: [Int: [BibleImportVerse]]] = [:]
        var headingDict: [Int: [Int: [BibleHeading]]] = [:]   // book > chapter > headings
        while sqlite3_step(stmt) == SQLITE_ROW {
            let bookNum = Int(sqlite3_column_int(stmt, 0))
            let chapter = Int(sqlite3_column_int(stmt, 1))
            let verse = Int(sqlite3_column_int(stmt, 2))
            let rawText = columnText(stmt, index: 3)

            let parsed = MySwordGBF.parse(rawText)
            guard !parsed.text.isEmpty else { continue }
            if parsed.woc { anyWoc = true }
            if parsed.runs?.contains(where: { $0.strong != nil }) == true { anyStrong = true }

            bookDict[bookNum, default: [:]][chapter, default: []].append(
                BibleImportVerse(
                    verseNumber: verse,
                    text: parsed.text,
                    runs: parsed.runs,
                    footnotes: parsed.footnotes.isEmpty ? nil : parsed.footnotes,
                    crossReferences: parsed.crossRefs.isEmpty ? nil : parsed.crossRefs,
                    hasWordsOfChrist: parsed.woc
                )
            )
            for h in parsed.headings where !h.isEmpty {
                headingDict[bookNum, default: [:]][chapter, default: []]
                    .append(BibleHeading(beforeVerse: verse, level: 1, text: h))
            }
        }

        var books: [BibleImportBook] = []
        for bookNum in bookDict.keys.sorted() {
            let chaptersDict = bookDict[bookNum]!
            let chapters = chaptersDict.keys.sorted().map { chapterNum -> BibleImportChapter in
                let headings = headingDict[bookNum]?[chapterNum]
                return BibleImportChapter(
                    chapterNumber: chapterNum,
                    verses: chaptersDict[chapterNum]!.sorted { $0.verseNumber < $1.verseNumber },
                    headings: (headings?.isEmpty ?? true) ? nil : headings
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

    // MARK: - Helpers

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }
}

// MARK: - MySword GBF rich parser

/// Walks MySword's GBF/HTML markup and maps the full feature set into the GOAT model:
/// `<TS>…<Ts>`→headings, `<RF>…<Rf>`→footnotes, `<RX>…<Rx>`→cross-references,
/// red `<FR>…<Fr>`→words-of-Christ runs, `<FI>…<Fi>`→added-words runs,
/// `<WG####>`/`<WH####>`→Strong's (attached to the preceding word), `<WT…>`→morphology.
nonisolated enum MySwordGBF {
    struct Result {
        var text: String = ""
        var runs: [VerseRun]? = nil
        var footnotes: [BibleFootnote] = []
        var crossRefs: [BibleCrossRef] = []
        var headings: [String] = []
        var woc: Bool = false
    }

    static func parse(_ raw: String) -> Result {
        var result = Result()
        var runs: [VerseRun] = []
        var buf = ""
        var kindStack: [String] = []          // "woc" (FR) / "add" (FI)
        var lastRunIndex: Int? = nil
        var hasStrong = false

        // Sub-region capture (notes / cross-refs / headings).
        enum Region { case body, note, xref, heading }
        var region: Region = .body
        var noteBuf = ""
        var xrefAttr = ""    // attributes on the opening <RX …>
        var xrefBuf = ""
        var headingBuf = ""

        func curKind() -> String { kindStack.last ?? "plain" }

        func flush() {
            let cleaned = collapse(buf)
            if !cleaned.trimmingCharacters(in: .whitespaces).isEmpty {
                runs.append(VerseRun(text: cleaned, kind: curKind()))
                lastRunIndex = runs.count - 1
            }
            buf = ""
        }

        func attachStrong(_ code: String) {
            hasStrong = true
            if buf.trimmingCharacters(in: .whitespaces).isEmpty {
                if let idx = lastRunIndex, runs[idx].strong == nil { runs[idx].strong = code }
                return
            }
            // The Strong's number annotates the last word currently in the buffer.
            if let spaceIdx = buf.lastIndex(of: " ") {
                let prefix = String(buf[...spaceIdx])
                let lastWord = String(buf[buf.index(after: spaceIdx)...])
                let cleanedPrefix = collapse(prefix)
                if cleanedPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
                    // Whitespace-only prefix: keep the boundary space on the word run.
                    runs.append(VerseRun(text: cleanedPrefix + lastWord, kind: curKind(), strong: code))
                } else {
                    runs.append(VerseRun(text: cleanedPrefix, kind: curKind()))
                    runs.append(VerseRun(text: lastWord, kind: curKind(), strong: code))
                }
            } else {
                runs.append(VerseRun(text: buf, kind: curKind(), strong: code))
            }
            lastRunIndex = runs.count - 1
            buf = ""
        }

        func attachMorph(_ code: String) {
            if let idx = lastRunIndex, runs[idx].morph == nil { runs[idx].morph = code }
        }

        func append(_ s: String) {
            switch region {
            case .body: buf += s
            case .note: noteBuf += s
            case .xref: xrefBuf += s
            case .heading: headingBuf += s
            }
        }

        // Nested so it can mutate the parse-local state directly.
        func handleTag(_ tag: String) {
            let up = tag.uppercased()

            // Close tags — only meaningful inside their sub-region.
            if tag == "Ts" {
                if region == .heading {
                    let t = headingBuf.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { result.headings.append(decodeEntities(t)) }
                    region = .body; headingBuf = ""
                }
                return
            }
            if tag == "Rf" {
                if region == .note {
                    let t = stripTags(noteBuf).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { result.footnotes.append(BibleFootnote(text: decodeEntities(t))) }
                    region = .body; noteBuf = ""
                }
                return
            }
            if tag == "Rx" {
                if region == .xref {
                    let inner = xrefBuf.trimmingCharacters(in: .whitespacesAndNewlines)
                    let source = inner.isEmpty ? xrefAttr : inner
                    let targets = source.split(whereSeparator: { $0 == ";" || $0 == "," })
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if !targets.isEmpty { result.crossRefs.append(BibleCrossRef(targets: targets)) }
                    region = .body; xrefBuf = ""; xrefAttr = ""
                }
                return
            }

            // Inside a sub-region, ignore every other tag.
            guard region == .body else { return }

            if tag.hasPrefix("TS") {                       // section heading open
                flush(); region = .heading; headingBuf = ""
            } else if tag.hasPrefix("RF") {                // footnote open
                flush(); region = .note; noteBuf = ""
            } else if tag.hasPrefix("RX") {                // cross-reference open
                flush(); region = .xref; xrefBuf = ""
                xrefAttr = tag.count > 2 ? String(tag.dropFirst(2)).trimmingCharacters(in: .whitespaces) : ""
            } else if tag == "FR" {                        // red-letter (words of Christ) open
                flush(); kindStack.append("woc"); result.woc = true
            } else if tag == "Fr" {
                flush(); if kindStack.last == "woc" { kindStack.removeLast() }
            } else if tag == "FI" {                        // italic / supplied (added) words open
                flush(); kindStack.append("add")
            } else if tag == "Fi" {
                flush(); if kindStack.last == "add" { kindStack.removeLast() }
            } else if up.hasPrefix("WG") || up.hasPrefix("WH") {   // Strong's number
                let letter = up.hasPrefix("WG") ? "G" : "H"
                let num = tag.dropFirst(2).filter { $0.isNumber }
                if !num.isEmpty { attachStrong(letter + num) }
            } else if up.hasPrefix("WT") {                 // morphology
                let code = String(tag.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !code.isEmpty { attachMorph(code) }
            } else if up == "CM" || up == "CL" || up == "CI" || up == "CG"
                        || up.hasPrefix("PF") || up.hasPrefix("PI") {
                append(" ")                                // paragraph / poetry break → whitespace
            }
            // else: drop any other GBF/HTML tag
        }

        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "<" {
                // Read the tag up to '>'.
                var j = i + 1
                var tag = ""
                while j < chars.count, chars[j] != ">" { tag.append(chars[j]); j += 1 }
                i = (j < chars.count) ? j + 1 : j
                handleTag(tag)
            } else {
                append(String(ch))
                i += 1
            }
        }
        flush()

        // Plain text = concatenation of all run texts (scripture words only).
        let plain = decodeEntities(collapse(runs.map { $0.text }.joined()))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        result.text = plain

        // Decode entities inside runs too.
        for k in runs.indices { runs[k].text = decodeEntities(runs[k].text) }
        let meaningful = runs.contains { $0.kind != "plain" || $0.strong != nil }
        result.runs = meaningful
            ? runs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
            : nil
        _ = hasStrong
        return result
    }

    private static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
    }

    private static func stripTags(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "<[^>]+>") else { return s }
        return re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    private static func decodeEntities(_ s: String) -> String {
        var r = s
        for (e, c) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                       ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            r = r.replacingOccurrences(of: e, with: c)
        }
        return r
    }
}
