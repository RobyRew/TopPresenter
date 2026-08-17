//
//  BibleReferenceParser.swift
//  TopPresenter
//
//  Pure, testable parser for Bible reference queries against the ACTIVE
//  translation's book list: "ioan 3:16", "1 cor 13 4-7", "ps 23", "geneza 1",
//  plus BARE book names ("apocalipsa" → open the book).
//  Diacritic/case-insensitive, matches book-name prefixes AND abbreviations,
//  tolerates ":" or space between chapter and verse, "-" ranges, and clamps
//  impossible verse numbers against the indexed per-chapter counts.
//

import Foundation

nonisolated struct BibleReferenceMatch: Sendable, Equatable {
    let bookNumber: Int
    /// The module's OWN name for the book — what goes to the live output, where
    /// the audience is reading this translation.
    let bookName: String
    let chapter: Int
    let verseStart: Int?
    let verseEnd: Int?
    /// The query was JUST a book name ("apocalipsa") — chapter defaults to 1;
    /// the palette renders it as „Deschide cartea".
    var isBookOnly: Bool = false

    /// `bookName` in the app's language — for the palette row the OPERATOR
    /// reads. Falls back to `bookName` for a book we cannot identify.
    var bookDisplayName: String { BibleBookLocalization.localizedName(for: bookName) }
}

nonisolated enum BibleReferenceParser {
    /// Parse a query against a book list. Returns nil when the query doesn't
    /// look like a reference (and isn't a bare book name).
    static func parse(_ query: String, books: [BookIndexEntry]) -> BibleReferenceMatch? {
        let folded = searchFold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !folded.isEmpty, !books.isEmpty else { return nil }

        // "1 cor 13:4-7" → book part may START with a digit ("1 cor", "2 imp"),
        // then chapter, optional verse (":" or space), optional "-end".
        // The `\.?` after the leading digit is for German ordinals — "1. Mose 1",
        // "2. Korinther 5:17" — which otherwise fell through to the bare-book
        // path and matched nothing.
        let pattern = #"^(\d?\s*\.?\s*[\p{L}][\p{L}\s.]*?)\s+(\d+)(?:[:\s]+(\d+)(?:\s*-\s*(\d+))?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: folded, range: NSRange(folded.startIndex..., in: folded)),
              let bookRange = Range(match.range(at: 1), in: folded),
              let chapterRange = Range(match.range(at: 2), in: folded)
        else {
            // No trailing numbers → maybe the query IS a book name ("apocalipsa").
            return bareBook(folded, books: books)
        }

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

        // Verse sanity against the indexed counts: "Apocalipsa 22:420" must not
        // offer a verse that doesn't exist — an impossible START drops to a
        // chapter reference; an impossible END clamps to the last verse.
        if let vs = verseStart, let maxVerse = book.verseCounts[chapter], maxVerse > 0 {
            if vs > maxVerse {
                verseStart = nil
                verseEnd = nil
            } else if let ve = verseEnd, ve > maxVerse {
                verseEnd = maxVerse
            }
        }

        return BibleReferenceMatch(bookNumber: book.bookNumber, bookName: book.name,
                                   chapter: chapter, verseStart: verseStart, verseEnd: verseEnd)
    }

    /// A query that is ONLY a book name (or a ≥3-char prefix / exact abbrev):
    /// "apocal", "apocalipsa", "1 ioan", "fa". STRICT matching — never the
    /// fuzzy word fallback (a lyric word must not hijack the reference slot).
    private static func bareBook(_ folded: String, books: [BookIndexEntry]) -> BibleReferenceMatch? {
        var matches = books.filter {
            $0.folded == folded || (!$0.abbreviationFolded.isEmpty && $0.abbreviationFolded == folded)
        }
        if matches.isEmpty, folded.count >= 3 {
            matches = books.filter { $0.folded.hasPrefix(folded) }
        }
        var book = matches.min(by: { $0.folded.count < $1.folded.count })
        // Nothing under the module's own wording — try every other language's
        // name for the same books. ≥3 characters, because with no chapter number
        // to anchor it a two-letter alias would turn ordinary words typed in the
        // palette into Bible references.
        if book == nil { book = aliasBook(folded, in: books, minLength: 3) }
        guard let book else { return nil }
        return BibleReferenceMatch(bookNumber: book.bookNumber, bookName: book.name,
                                   chapter: 1, verseStart: nil, verseEnd: nil, isBookOnly: true)
    }

    /// The book a query names in SOME language, matched through
    /// `BibleBookLocalization`.
    ///
    /// Each entry is identified by its NAME, never by `bookNumber` — an OSIS
    /// file numbers books with a running counter, so an NT-only module has
    /// Matthew at 1 and matching "genesis" against the number would open it.
    /// Shortest matching key wins, the same tie-break the name paths use.
    static func aliasBook(_ foldedQuery: String, in books: [BookIndexEntry],
                          minLength: Int) -> BookIndexEntry? {
        let q = BibleBookLocalization.matchKey(foldedQuery)
        guard q.count >= minLength, !q.isEmpty else { return nil }
        var best: (book: BookIndexEntry, keyLength: Int)?
        for book in books {
            guard let number = BibleBookLocalization.canonicalNumber(forName: book.name) else { continue }
            for key in BibleBookLocalization.searchKeys(number: number) {
                guard key == q || (q.count >= 3 && key.hasPrefix(q)) else { continue }
                if best == nil || key.count < best!.keyLength { best = (book, key.count) }
            }
        }
        return best?.book
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
        // The module's own wording has had its turn — now the same book under
        // any other language's name or a standard abbreviation, so "genesis 1"
        // and "gen 1" reach a Cornilescu module and "geneza 1" an English one.
        // A chapter number follows, so even a two-letter shortcut is unambiguous
        // here; the bare-book path is the one that has to stay strict.
        if let alias = aliasBook(q, in: books, minLength: 1) { return alias }
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
