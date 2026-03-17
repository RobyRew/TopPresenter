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

    @Relationship(deleteRule: .cascade, inverse: \BibleBook.module)
    var books: [BibleBook] = []

    init(
        name: String,
        abbreviation: String = "",
        language: String = "en",
        sourceFormat: String,
        moduleDescription: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.abbreviation = abbreviation
        self.language = language
        self.sourceFormat = sourceFormat
        self.importDate = Date()
        self.moduleDescription = moduleDescription
    }
}

// MARK: - Bible Book
@Model
final class BibleBook {
    @Attribute(.unique) var id: UUID
    var name: String
    var bookNumber: Int
    var testament: String // "OT" or "NT"

    var module: BibleModule?

    @Relationship(deleteRule: .cascade, inverse: \BibleChapter.book)
    var chapters: [BibleChapter] = []

    init(name: String, bookNumber: Int, testament: String) {
        self.id = UUID()
        self.name = name
        self.bookNumber = bookNumber
        self.testament = testament
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

    var book: BibleBook?

    @Relationship(deleteRule: .cascade, inverse: \BibleVerse.chapter)
    var verses: [BibleVerse] = []

    init(chapterNumber: Int) {
        self.id = UUID()
        self.chapterNumber = chapterNumber
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

    var chapter: BibleChapter?

    init(verseNumber: Int, text: String) {
        self.id = UUID()
        self.verseNumber = verseNumber
        self.text = text
    }

    /// Full reference string e.g. "Genesis 1:1"
    var fullReference: String {
        guard let chapter = chapter, let book = chapter.book else {
            return "\(verseNumber)"
        }
        return "\(book.name) \(chapter.chapterNumber):\(verseNumber)"
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
