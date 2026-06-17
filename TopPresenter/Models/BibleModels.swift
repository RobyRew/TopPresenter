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
        extensionsJSON: String? = nil
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
    var extensionsJSON: String?

    var chapter: BibleChapter?

    init(verseNumber: Int, text: String, runsJSON: String? = nil,
         footnotesJSON: String? = nil, crossRefsJSON: String? = nil,
         hasWordsOfChrist: Bool = false, gloss: String = "", extensionsJSON: String? = nil) {
        self.id = UUID()
        self.verseNumber = verseNumber
        self.text = text
        self.runsJSON = runsJSON
        self.footnotesJSON = footnotesJSON
        self.crossRefsJSON = crossRefsJSON
        self.hasWordsOfChrist = hasWordsOfChrist
        self.gloss = gloss
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

    /// Full reference string e.g. "Genesis 1:1"
    var fullReference: String {
        guard let chapter = chapter, let book = chapter.book else {
            return "\(verseNumber)"
        }
        return "\(book.name) \(chapter.chapterNumber):\(verseNumber)"
    }
}

/// Shared JSON encode helper for stashing rich arrays into the model.
enum BibleRichData {
    static func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value, let data = try? JSONEncoder().encode(value),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }
}

// MARK: - Bible Search Result (non-persisted)
struct BibleSearchResult: Identifiable, Hashable {
    let id = UUID()
    let bookName: String
    let chapterNumber: Int
    let verseNumber: Int
    let text: String
    let reference: String
    let verseID: UUID

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: BibleSearchResult, rhs: BibleSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}
