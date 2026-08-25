//
//  BibleModels.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation
import SwiftData

// MARK: - Bible Module
@Model
final class BibleModule {
    @Attribute(.unique) var id: UUID
    var name: String
    var abbreviation: String
    var language: String
    var sourceFormat: String
    var importDate: Date
    var moduleDescription: String
    /// Versification scheme ("kjv"/"lxx"/"vulgate"…) — optional, additive.
    var versification: String?
    /// Canon ("protestant"/"catholic"/"orthodox") — optional, additive.
    var canon: String?

    // MARK: Lossless metadata (additive, all defaulted for lightweight migration)
    /// Name in the translation's own language.
    var nameLocal: String = ""
    /// Human language name ("Română", "English"…).
    var languageName: String = ""
    /// Copyright / rights notice.
    var copyright: String = ""
    /// Full foreword / introduction essays (CUVÂNT ÎNAINTE, prefață…). Can be long.
    var aboutText: String = ""
    /// Provenance of the text ("Ediția tipărită", a society, a URL…).
    var textSource: String = ""
    /// Publication year, when known.
    var year: Int?
    /// Writing direction: "ltr" | "rtl".
    var direction: String = "ltr"
    /// Fast flags promoted from the verses (styling / filtering / UI badges).
    var hasWordsOfChrist: Bool = false
    var hasStrongs: Bool = false
    /// The source marks this edition as not-yet-complete (partial books).
    var incomplete: Bool = false
    /// JSON-encoded `_extensions` object — any future/unknown fields survive round-trip.
    var extensionsJSON: String?
    /// Stable identity ACROSS libraries, carried in the exported header.
    ///
    /// Assigned once when the module enters a library and never regenerated, so
    /// exporting it and importing it somewhere else lands on the same module
    /// rather than a second copy of it. Empty for modules imported before this
    /// existed — `DuplicateResolver`'s ladder has two more rungs for them.
    var contentID: String = ""

    @Relationship(deleteRule: .cascade, inverse: \BibleBook.module)
    var books: [BibleBook] = []

    init(
        name: String,
        abbreviation: String = "",
        language: String = "en",
        sourceFormat: String,
        moduleDescription: String = "",
        versification: String? = nil,
        canon: String? = nil,
        nameLocal: String = "",
        languageName: String = "",
        copyright: String = "",
        aboutText: String = "",
        textSource: String = "",
        year: Int? = nil,
        direction: String = "ltr",
        hasWordsOfChrist: Bool = false,
        hasStrongs: Bool = false,
        incomplete: Bool = false,
        extensionsJSON: String? = nil,
        contentID: String = UUID().uuidString
    ) {
        self.id = UUID()
        self.name = name
        self.abbreviation = abbreviation
        self.language = language
        self.sourceFormat = sourceFormat
        self.importDate = Date()
        self.moduleDescription = moduleDescription
        self.versification = versification
        self.canon = canon
        self.nameLocal = nameLocal
        self.languageName = languageName
        self.copyright = copyright
        self.aboutText = aboutText
        self.textSource = textSource
        self.year = year
        self.direction = direction
        self.hasWordsOfChrist = hasWordsOfChrist
        self.hasStrongs = hasStrongs
        self.incomplete = incomplete
        self.extensionsJSON = extensionsJSON
        self.contentID = contentID
    }
}

// MARK: - Bible Book
@Model
final class BibleBook {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookNumber: Int
    var testament: String // "OT" | "NT" | "DC"
    /// English name + abbreviations + per-book introduction (additive).
    var nameEnglish: String = ""
    var abbreviation: String = ""
    var abbreviationEnglish: String = ""
    var expectedChapters: Int = 0
    var introduction: String = ""
    var extensionsJSON: String?

    var module: BibleModule?

    @Relationship(deleteRule: .cascade, inverse: \BibleChapter.book)
    var chapters: [BibleChapter] = []

    init(name: String, bookNumber: Int, testament: String,
         nameEnglish: String = "", abbreviation: String = "",
         abbreviationEnglish: String = "", expectedChapters: Int = 0,
         introduction: String = "", extensionsJSON: String? = nil) {
        self.id = UUID()
        self.name = name
        self.bookNumber = bookNumber
        self.testament = testament
        self.nameEnglish = nameEnglish
        self.abbreviation = abbreviation
        self.abbreviationEnglish = abbreviationEnglish
        self.expectedChapters = expectedChapters
        self.introduction = introduction
        self.extensionsJSON = extensionsJSON
    }

    var sortedChapters: [BibleChapter] {
        chapters.sorted { $0.chapterNumber < $1.chapterNumber }
    }

    /// What the LIBRARY shows, honouring the Bible ▸ „Numele cărților" setting.
    ///
    /// Defaults to the translation's own language, so the book list matches the
    /// text beside it and the reference on the projector. Set to the app's
    /// language for an operator who does not read the translation.
    var displayName: String {
        switch BibleBookLocalization.nameMode {
        case .translation: return presentationName
        case .app: return displayName(language: BibleBookLocalization.uiLanguage)
        }
    }

    /// This book named in a GIVEN language.
    ///
    /// `name` is whatever the source file said. Three tries, most trustworthy
    /// first, and every one goes through the NAME rather than `bookNumber`:
    /// OSIS files number books with a running counter, so an NT-only module has
    /// Matthew at 1. The number is consulted last and only when `testament`
    /// agrees with it, which is exactly the case that counter cannot produce.
    ///
    /// The language is explicit so tests do not depend on the machine's locale.
    func displayName(language: String) -> String {
        if !nameEnglish.isEmpty,
           let number = BibleBookLocalization.canonicalNumber(forName: nameEnglish),
           let localized = BibleBookLocalization.name(number: number, language: language) {
            return localized
        }
        if let number = BibleBookLocalization.canonicalNumber(forName: name) {
            // A name that resolves to a different book than the file placed it at,
            // in a file whose numbering we DO trust, means an edition that names
            // books differently — Douay-Rheims calls 1 Samuel "1 Kings". Renaming
            // it would put the wrong book on screen, so leave it as written.
            if bookNumberIsCanonical && number != bookNumber { return name }
            if let localized = BibleBookLocalization.name(number: number, language: language) {
                return localized
            }
        }
        // Last resort, for a file whose names we cannot read at all.
        if bookNumberIsCanonical,
           let localized = BibleBookLocalization.name(number: bookNumber, language: language) {
            return localized
        }
        return name
    }

    /// This book named in the TRANSLATION's language — the reference the LIVE
    /// OUTPUT shows, because the congregation is reading this edition.
    ///
    /// Not the same as `name`, and the difference is not academic: the published
    /// English KJV module carries Romanian book names, so it projected
    /// „Geneza 1:6" over English verses. The module declares its language, so
    /// that is what the reference follows — and for a language with no table
    /// (Dutch, Hungarian, Greek…) the file's own wording stands.
    /// `displayName` already returns `name` untouched for a language it has no
    /// table for, so an unrecognised code needs no special case here.
    var presentationName: String { displayName(language: module?.language ?? "") }

    /// Whether `bookNumber` is a canonical position rather than a running import
    /// counter: inside 1…66 and on the side of the canon `testament` claims.
    ///
    /// This is the whole trust model. `OSISBibleImporter` numbers books as it
    /// meets them, so an NT-only file has Matthew at 1 — a number that says OT
    /// about a book that says NT, which is exactly what this catches.
    private var bookNumberIsCanonical: Bool {
        switch testament {
        case "OT": return (1...39).contains(bookNumber)
        case "NT": return (40...66).contains(bookNumber)
        default: return false
        }
    }

    /// A short label for this book, for grids and columns too narrow for the
    /// full name.
    ///
    /// Modules carry `abbreviation` only when their source format had one, and
    /// most imports do not, so it cannot be relied on — a derived form keeps the
    /// compact views usable on every module rather than only on well-tagged ones.
    /// Ordinal prefixes are kept ("1 Împărați" → "1Împ", not "Împ"), because
    /// dropping them would collide 1/2 Samuel, 1/2/3 Ioan and the rest.
    ///
    /// The file's own abbreviation is kept while it still reads as a short form of
    /// what is on screen: "Gen" beside "Genesis" is fine, „Cânt.C" beside
    /// "Song of Solomon" is a puzzle.
    var displayAbbreviation: String {
        displayAbbreviation(language: BibleBookLocalization.uiLanguage)
    }

    func displayAbbreviation(language: String) -> String {
        let localized = displayName(language: language)
        let trimmed = abbreviation.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, localized == name || Self.abbreviationFits(trimmed, localized) {
            return trimmed
        }
        return Self.deriveAbbreviation(from: localized)
    }

    /// Whether a file-supplied short form still belongs beside `name`.
    ///
    /// Prefix match after folding case, diacritics, dots and spaces away, so
    /// "1Sam" fits "1 Samuel" and "Gen" fits "Genesis", while „Fac" (Facerea)
    /// does not fit "Genesis".
    nonisolated static func abbreviationFits(_ abbreviation: String, _ name: String) -> Bool {
        let compact = { (s: String) in
            BibleBookLocalization.matchKey(s).replacingOccurrences(of: " ", with: "")
        }
        let short = compact(abbreviation)
        return !short.isEmpty && compact(name).hasPrefix(short)
    }

    /// nonisolated: called from @Model accessors, which are nonisolated under
    /// Swift 6, and it is pure string math.
    nonisolated static func deriveAbbreviation(from name: String) -> String {
        let words = name.split(separator: " ", omittingEmptySubsequences: true)
        guard let last = words.last else { return name }
        // A leading ordinal ("1", "2", "III", German "1.") stays glued to the
        // stem — without it 1.–5. Mose would all abbreviate to "Mose".
        let head = words[0].hasSuffix(".") ? words[0].dropLast() : words[0]
        let ordinal = words.count > 1 && !head.isEmpty
            && head.allSatisfy({ $0.isNumber || $0 == "I" || $0 == "V" })
            ? String(head)
            : ""
        let stem = last.prefix(ordinal.isEmpty ? 4 : 3)
        return ordinal + stem
    }
}

// MARK: - Bible Chapter
@Model
final class BibleChapter {
    @Attribute(.unique) var id: UUID
    var chapterNumber: Int
    /// JSON-encoded [BibleHeading] — pericope/section titles. nil = none.
    var headingsJSON: String?
    var extensionsJSON: String?

    var book: BibleBook?

    @Relationship(deleteRule: .cascade, inverse: \BibleVerse.chapter)
    var verses: [BibleVerse] = []

    init(chapterNumber: Int, headingsJSON: String? = nil, extensionsJSON: String? = nil) {
        self.id = UUID()
        self.chapterNumber = chapterNumber
        self.headingsJSON = headingsJSON
        self.extensionsJSON = extensionsJSON
    }

    /// Decoded section headings (empty when none).
    var headings: [BibleHeading] {
        guard let headingsJSON, let data = headingsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BibleHeading].self, from: data) else { return [] }
        return decoded
    }

    var sortedVerses: [BibleVerse] {
        verses.sorted { $0.verseNumber < $1.verseNumber }
    }
}

// MARK: - Bible Verse
@Model
final class BibleVerse {
    @Attribute(.unique) var id: UUID
    var verseNumber: Int
    var text: String
    /// JSON-encoded [VerseRun] — rich segments (red-letter / italic / Strong's).
    /// nil = render plain `text`. Additive, optional.
    var runsJSON: String?
    /// JSON-encoded [BibleFootnote] / [BibleCrossRef]. nil = none.
    var footnotesJSON: String?
    var crossRefsJSON: String?
    /// Fast flag (no decode) for styling/filtering verses with Jesus's words.
    var hasWordsOfChrist: Bool = false
    /// Interlinear reading gloss (e.g. English under a Hebrew/Greek verse). "" = none.
    var gloss: String = ""
    /// Poetic line indentation level (Psalms, Proverbs, the prophets). nil = prose.
    ///
    /// Every TopPresenter Bible has carried this since the format existed and
    /// `TopPresenterBibleImporter` has always parsed it — into a struct field
    /// that nothing then read, because no model had anywhere to put it.
    /// Additive optional, like `versification` and `canon`, so V2 keeps
    /// migrating lightly.
    var poetryIndent: Int?
    var extensionsJSON: String?

    var chapter: BibleChapter?

    init(verseNumber: Int, text: String, runsJSON: String? = nil,
         footnotesJSON: String? = nil, crossRefsJSON: String? = nil,
         hasWordsOfChrist: Bool = false, gloss: String = "",
         poetryIndent: Int? = nil, extensionsJSON: String? = nil) {
        self.id = UUID()
        self.verseNumber = verseNumber
        self.text = text
        self.runsJSON = runsJSON
        self.footnotesJSON = footnotesJSON
        self.crossRefsJSON = crossRefsJSON
        self.hasWordsOfChrist = hasWordsOfChrist
        self.gloss = gloss
        self.poetryIndent = poetryIndent
        self.extensionsJSON = extensionsJSON
    }

    /// Decoded rich runs — empty when the verse is plain.
    var runs: [VerseRun] {
        guard let runsJSON, let data = runsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([VerseRun].self, from: data) else { return [] }
        return decoded
    }
    var footnotes: [BibleFootnote] {
        guard let footnotesJSON, let data = footnotesJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BibleFootnote].self, from: data) else { return [] }
        return decoded
    }
    var crossReferences: [BibleCrossRef] {
        guard let crossRefsJSON, let data = crossRefsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([BibleCrossRef].self, from: data) else { return [] }
        return decoded
    }

    /// Full reference string e.g. "Genesis 1:1" — in the TRANSLATION's language,
    /// since this is what goes on the screen the congregation reads.
    var fullReference: String {
        guard let chapter = chapter, let book = chapter.book else {
            return "\(verseNumber)"
        }
        return "\(book.presentationName) \(chapter.chapterNumber):\(verseNumber)"
    }
}

/// Shared JSON encode helper for stashing rich arrays into the model.
nonisolated enum BibleRichData {
    static func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? JSONEncoder().encode(value),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}

