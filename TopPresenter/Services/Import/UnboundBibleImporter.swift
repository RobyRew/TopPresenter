//
//  UnboundBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for Unbound Bible format (tab-delimited text files).
/// Unbound Bible files from Biola University use a simple tab-separated format:
/// Lines beginning with # are comments/metadata.
/// Data lines have columns: book_number \t chapter \t verse \t subverse \t order \t text
/// Some variants use fewer columns: book_number \t chapter \t verse \t text
nonisolated final class UnboundBibleImporter: BibleImporter {
    let format: SupportedBibleFormat = .unboundBible

    func parse(fileURL: URL) async throws -> BibleImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BibleImportError.fileNotFound
        }

        // Try UTF-8 first, then Latin-1
        var content: String
        if let utf8 = try? String(contentsOf: fileURL, encoding: .utf8) {
            content = utf8
        } else if let latin1 = try? String(contentsOf: fileURL, encoding: .isoLatin1) {
            content = latin1
        } else {
            throw BibleImportError.parsingFailed("Unable to read file encoding")
        }

        guard !content.isEmpty else { throw BibleImportError.emptyFile }

        let lines = content.components(separatedBy: .newlines)

        // Parse metadata from comment lines
        var moduleName = fileURL.deletingPathExtension().lastPathComponent
        var language = "en"
        var description = ""

        var rawVerses: [RawVerse] = []
        var columnMapping: ColumnMapping?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("#") {
                // Metadata comment line
                let metaLine = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)

                if metaLine.lowercased().hasPrefix("name\t") || metaLine.lowercased().hasPrefix("name:") {
                    let value = extractMetaValue(metaLine)
                    if !value.isEmpty { moduleName = value }
                } else if metaLine.lowercased().hasPrefix("language\t") || metaLine.lowercased().hasPrefix("language:") {
                    let value = extractMetaValue(metaLine)
                    if !value.isEmpty { language = value }
                } else if metaLine.lowercased().hasPrefix("note\t") || metaLine.lowercased().hasPrefix("note:") {
                    let value = extractMetaValue(metaLine)
                    if !value.isEmpty { description = value }
                } else if metaLine.lowercased().hasPrefix("columns\t") || metaLine.lowercased().hasPrefix("columns:") {
                    // Header that defines column order
                    columnMapping = parseColumnHeader(metaLine)
                }

                continue
            }

            // Data line — tab separated
            let columns = trimmed.split(separator: "\t", omittingEmptySubsequences: false).map { String($0) }

            if let mapping = columnMapping {
                // Use column mapping from header
                guard columns.count > max(mapping.bookIndex, mapping.chapterIndex, mapping.verseIndex, mapping.textIndex) else { continue }

                let bookNum = Int(columns[mapping.bookIndex].trimmingCharacters(in: .whitespaces)) ?? 0
                let chapter = Int(columns[mapping.chapterIndex].trimmingCharacters(in: .whitespaces)) ?? 0
                let verse = Int(columns[mapping.verseIndex].trimmingCharacters(in: .whitespaces)) ?? 0
                let text = columns[mapping.textIndex].trimmingCharacters(in: .whitespacesAndNewlines)

                if bookNum > 0 && chapter > 0 && verse > 0 && !text.isEmpty {
                    rawVerses.append(RawVerse(bookNum: bookNum, chapter: chapter, verse: verse, text: stripHTMLTags(text)))
                }
            } else {
                // Try common column layouts
                if let rv = parseDataLine(columns) {
                    rawVerses.append(rv)
                }
            }
        }

        guard !rawVerses.isEmpty else {
            throw BibleImportError.invalidFormat("No verses found in Unbound Bible file")
        }

        // Group into books
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

        let abbreviation = deriveAbbreviation(from: moduleName)

        return BibleImportResult(
            moduleName: moduleName,
            abbreviation: abbreviation,
            language: language,
            description: description,
            books: books
        )
    }

    // MARK: - Column Mapping

    private struct ColumnMapping {
        let bookIndex: Int
        let chapterIndex: Int
        let verseIndex: Int
        let textIndex: Int
    }

    private func parseColumnHeader(_ header: String) -> ColumnMapping? {
        let parts = header.split(separator: "\t").map { String($0).lowercased().trimmingCharacters(in: .whitespaces) }
        // Skip the "columns" label
        let columns: [String]
        if parts.first == "columns" || parts.first == "columns:" {
            columns = Array(parts.dropFirst())
        } else {
            columns = parts
        }

        var bookIdx = -1, chapIdx = -1, verseIdx = -1, textIdx = -1

        for (i, col) in columns.enumerated() {
            switch col {
            case "orig_book_index", "book", "book_number", "booknum":
                bookIdx = i
            case "orig_chapter", "chapter", "chap":
                chapIdx = i
            case "orig_verse", "verse":
                verseIdx = i
            case "text", "scripture":
                textIdx = i
            default:
                break
            }
        }

        guard bookIdx >= 0, chapIdx >= 0, verseIdx >= 0, textIdx >= 0 else { return nil }
        return ColumnMapping(bookIndex: bookIdx, chapterIndex: chapIdx, verseIndex: verseIdx, textIndex: textIdx)
    }

    // MARK: - Data Line Parsing

    private struct RawVerse {
        let bookNum: Int
        let chapter: Int
        let verse: Int
        let text: String
    }

    private func parseDataLine(_ columns: [String]) -> RawVerse? {
        // Common layouts:
        // 6 columns: book chapter verse subverse order text
        // 4 columns: book chapter verse text
        // 3 columns: book chapter:verse text (less common)

        if columns.count >= 6 {
            let bookNum = Int(columns[0].trimmingCharacters(in: .whitespaces)) ?? 0
            let chapter = Int(columns[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let verse = Int(columns[2].trimmingCharacters(in: .whitespaces)) ?? 0
            let text = columns[5].trimmingCharacters(in: .whitespacesAndNewlines)

            if bookNum > 0 && chapter > 0 && verse > 0 && !text.isEmpty {
                return RawVerse(bookNum: bookNum, chapter: chapter, verse: verse, text: stripHTMLTags(text))
            }
        }

        if columns.count >= 4 && columns.count < 6 {
            let bookNum = Int(columns[0].trimmingCharacters(in: .whitespaces)) ?? 0
            let chapter = Int(columns[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let verse = Int(columns[2].trimmingCharacters(in: .whitespaces)) ?? 0
            let text = columns[3].trimmingCharacters(in: .whitespacesAndNewlines)

            if bookNum > 0 && chapter > 0 && verse > 0 && !text.isEmpty {
                return RawVerse(bookNum: bookNum, chapter: chapter, verse: verse, text: stripHTMLTags(text))
            }
        }

        if columns.count == 5 {
            // 5 columns: book chapter verse subverse text
            let bookNum = Int(columns[0].trimmingCharacters(in: .whitespaces)) ?? 0
            let chapter = Int(columns[1].trimmingCharacters(in: .whitespaces)) ?? 0
            let verse = Int(columns[2].trimmingCharacters(in: .whitespaces)) ?? 0
            let text = columns[4].trimmingCharacters(in: .whitespacesAndNewlines)

            if bookNum > 0 && chapter > 0 && verse > 0 && !text.isEmpty {
                return RawVerse(bookNum: bookNum, chapter: chapter, verse: verse, text: stripHTMLTags(text))
            }
        }

        return nil
    }

    // MARK: - Helpers

    private func extractMetaValue(_ line: String) -> String {
        // Split on tab or colon
        if let tabIndex = line.firstIndex(of: "\t") {
            return String(line[line.index(after: tabIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let colonIndex = line.firstIndex(of: ":") {
            return String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func stripHTMLTags(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deriveAbbreviation(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count == 1 {
            return String(name.prefix(6)).uppercased()
        }
        return words.map { String($0.prefix(1)) }.joined().uppercased()
    }
}
