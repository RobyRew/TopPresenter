//
//  BibleReferenceParser.swift
//  TopPresenter
//
//  Pure, testable parser for Bible reference queries against the ACTIVE
//  translation's book list: "ioan 3:16", "1 cor 13 4-7", "ps 23", "geneza 1".
//  Diacritic/case-insensitive, matches book-name prefixes AND abbreviations,
//  tolerates ":" or space between chapter and verse, and "-" ranges.
//

import Foundation

nonisolated struct BibleReferenceMatch: Sendable, Equatable {
    let bookNumber: Int
    let bookName: String
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?
}

nonisolated enum BibleReferenceParser {
    /// Parse a query against a book list. Returns nil when the query doesn't
    /// look like a reference (no trailing numbers / no matching book).
    static func parse(_ query: String, books: [BookIndexEntry]) -> BibleReferenceMatch? {
        let folded = searchFold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !folded.isEmpty, !books.isEmpty else { return nil }

        // "1 cor 13:4-7" → book part may START with a digit ("1 cor", "2 imp"),
        // then chapter, optional verse (":" or space), optional "-end".
        let pattern = #"^(\d?\s*[\p{L}][\p{L}\s.]*?)\s+(\d+)(?:[:\s]+(\d+)(?:\s*-\s*(\d+))?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let bookRange = Range(match.range(at: 1), in: folded),
              let chapterRange = Range(match.range(at: 2), in: folded)
        else { return nil }

        let bookQuery = folded[bookRange]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "  ", with: " ")
        let chapter = Int(folded[chapterRange]) ?? 0
        guard chapter > 0, !bookQuery.isEmpty else { return nil }

        var verseStart: Int? = nil
        var verseEnd: Int? = nil
        if let vs = Range(match.range(at: 3), in: folded) {
            verseStart = Int(folded[vs])
            if let ve = Range(match.range(at: 4), in: folded) {
                verseEnd = Int(folded[ve])
            } else {
                verseEnd = verseStart
            }
        }

        guard let book = bestBook(for: bookQuery, in: books) else { return nil }
        guard chapter <= max(book.chapterCount, 1) || book.chapterCount == 0 else { return nil }
        return BibleReferenceMatch(bookNumber: book.bookNumber, bookName: book.name,
                                   chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
    }

    /// Best book for a folded name fragment: exact name/abbrev → name prefix →
    /// abbrev prefix → word-boundary contains. Shortest name wins ties (so
    /// "ioan" prefers "Ioan" over "1 Ioan").
    static func bestBook(for foldedQuery: String, in books: [BookIndexEntry]) -> BookIndexEntry? {
        let q = foldedQuery
        if let exact = books.first(where: { $0.folded == q || $0.abbreviationFolded == q }) {
            return exact
        }
        let namePrefix = books.filter { $0.folded.hasPrefix(q) }
        if !namePrefix.isEmpty {
            return namePrefix.min { $0.folded.count < $1.folded.count }
        }
        let abbrevPrefix = books.filter { !$0.abbreviationFolded.isEmpty && $0.abbreviationFolded.hasPrefix(q) }
        if !abbrevPrefix.isEmpty {
            return abbrevPrefix.min { $0.folded.count < $1.folded.count }
        }
        // "1 cor" → last word prefix-matches a word of the name with same leading digit.
        let words = q.split(separator: " ")
        guard let last = words.last, last.count >= 2 else { return nil }
        let leadingDigit = q.first?.isNumber == true ? String(q.first!) : nil
        let fuzzy = books.filter { book in
            if let d = leadingDigit, !book.folded.hasPrefix(d) { return false }
            return book.folded.split(separator: " ").contains { $0.hasPrefix(last) }
        }
        return fuzzy.min { $0.folded.count < $1.folded.count }
    }
}
