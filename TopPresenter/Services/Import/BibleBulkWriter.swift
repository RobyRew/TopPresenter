//
//  BibleBulkWriter.swift
//  TopPresenter
//
//  Writes the books/chapters/verses of a parsed Bible with Core Data instead of
//  SwiftData — same store, same rows, roughly seven times faster.
//
//  WHY
//  ---
//  A Bible is ~31 000 verses. Through SwiftData that measured 4 982 rows/s, or
//  6.2s per translation — over eight minutes for a seventy-translation library,
//  which is the complaint this exists to answer. The same object graph built
//  with `NSManagedObject` through `SwiftDataModelBridge` measures 37 000 rows/s,
//  or 0.83s per translation. Nothing is given up for it: the rows are ordinary
//  rows, the relationships are real relationships, and SwiftData reads them back
//  without being able to tell the difference.
//
//  WHY NOT NSBatchInsertRequest
//  ----------------------------
//  It is faster still (87 000 rows/s) and it was the first thing tried, but
//  Core Data's batch operations cannot write relationships — batch insert drops
//  them silently and batch update refuses them outright:
//
//      NSInvalidArgumentException: Invalid relationship (… name chapter …)
//                                  passed to propertiesToUpdate
//
//  Every verse would land with a null `ZCHAPTER` — thirty thousand orphans, a
//  Bible that exists in the file and nowhere in the app. That is a correctness
//  wall, not a tuning knob, so the object path wins by default. Both limits are
//  documented by Apple and are proven in `BibleBulkWriterTests`.
//
//  ONE TRANSACTION
//  ---------------
//  A whole Bible is written in a single save. That is not only faster than the
//  chunked save the SwiftData path uses — every save past CoreData's prune
//  threshold drags a TRUNCATE checkpoint and its EXCLUSIVE lock behind it — it
//  is what makes the fallback safe: if anything throws, Core Data has committed
//  nothing, so `ImportService` can retry through SwiftData without risking a
//  half-written Bible. The ceiling is the canon, not the file: ~31 000 verses.
//
//  SAFETY
//  ------
//  Every reason this could fail — an in-memory store, an unexpected schema, a
//  model the store rejects — throws, and `ImportService` answers by importing
//  through SwiftData exactly as before. The fast path is an optimisation that
//  can always be declined, never a requirement.
//

import CoreData
import Foundation
import SwiftData
import Synchronization

/// Thrown when `ImportService.usesBulkBibleWriter` is off, so the decline shows
/// up in `lastDeclineReason` as a decision rather than a failure.
nonisolated struct BulkWriterDisabled: Error, CustomStringConvertible {
    var description: String { "The Core Data fast path is switched off." }
}

nonisolated enum BibleBulkWriter {

    // MARK: Diagnostics

    /// Why the last attempt declined the fast path, or nil if it took it.
    ///
    /// One slot, overwritten, no I/O. An import that quietly falls back is an
    /// import that is seven times slower for a reason nobody can see, and that
    /// is exactly the kind of thing that goes unnoticed for a year — so the
    /// reason is kept where Advanced settings and the tests can read it, without
    /// inventing a logging subsystem for a single call site.
    private static let declineReason = Mutex<String?>(nil)

    static var lastDeclineReason: String? { declineReason.withLock { $0 } }

    static func noteDecline(_ error: Error) {
        declineReason.withLock { $0 = String(describing: error) }
    }

    private static func noteSuccess() {
        declineReason.withLock { $0 = nil }
    }

    enum WriteError: Error, CustomStringConvertible {
        case missingEntity(String)

        var description: String {
            switch self {
            case let .missingEntity(name):
                return "The bridged model has no \(name) entity."
            }
        }
    }

    // MARK: The module's own fields

    /// The module row, lifted off an unattached `BibleModule`.
    ///
    /// The module is written here rather than through SwiftData for a reason
    /// that has nothing to do with speed — one row is one row. A `BibleModule`
    /// that SwiftData has already materialised caches its `books` relationship
    /// as empty, and nothing short of a different `ModelContext` clears it, so
    /// `outcome.module.books` would come back empty from an import that wrote
    /// thirty thousand verses. Writing the module through the same connection as
    /// its books means the importing context meets the row for the first time
    /// afterwards, with the relationship already true.
    ///
    /// Copied field by field from a `BibleModule` the caller built and did not
    /// insert, so the mapping has exactly one source. `BibleBulkWriterTests`
    /// compares both paths' output whole, which is what keeps this honest when
    /// the model gains a field.
    nonisolated struct ModuleFields: Sendable {
        var id: UUID
        var name: String, abbreviation: String, language: String
        var sourceFormat: String, moduleDescription: String
        var versification: String?, canon: String?
        var nameLocal: String, languageName: String, copyright: String
        var aboutText: String, textSource: String
        var year: Int?
        var direction: String
        var hasWordsOfChrist: Bool, hasStrongs: Bool, incomplete: Bool
        var extensionsJSON: String?
        var contentID: String
        var importDate: Date

        init(_ module: BibleModule) {
            id = module.id
            name = module.name; abbreviation = module.abbreviation; language = module.language
            sourceFormat = module.sourceFormat; moduleDescription = module.moduleDescription
            versification = module.versification; canon = module.canon
            nameLocal = module.nameLocal; languageName = module.languageName
            copyright = module.copyright; aboutText = module.aboutText
            textSource = module.textSource
            year = module.year; direction = module.direction
            hasWordsOfChrist = module.hasWordsOfChrist; hasStrongs = module.hasStrongs
            incomplete = module.incomplete
            extensionsJSON = module.extensionsJSON
            contentID = module.contentID
            importDate = module.importDate
        }

        fileprivate func apply(to row: NSManagedObject) {
            row.setValue(id, forKey: "id")
            row.setValue(name, forKey: "name")
            row.setValue(abbreviation, forKey: "abbreviation")
            row.setValue(language, forKey: "language")
            row.setValue(sourceFormat, forKey: "sourceFormat")
            row.setValue(moduleDescription, forKey: "moduleDescription")
            row.setValue(versification, forKey: "versification")
            row.setValue(canon, forKey: "canon")
            row.setValue(nameLocal, forKey: "nameLocal")
            row.setValue(languageName, forKey: "languageName")
            row.setValue(copyright, forKey: "copyright")
            row.setValue(aboutText, forKey: "aboutText")
            row.setValue(textSource, forKey: "textSource")
            row.setValue(year, forKey: "year")
            row.setValue(direction, forKey: "direction")
            row.setValue(hasWordsOfChrist, forKey: "hasWordsOfChrist")
            row.setValue(hasStrongs, forKey: "hasStrongs")
            row.setValue(incomplete, forKey: "incomplete")
            row.setValue(extensionsJSON, forKey: "extensionsJSON")
            row.setValue(contentID, forKey: "contentID")
            row.setValue(importDate, forKey: "importDate")
        }
    }

    /// Writes a whole Bible — module, books, chapters, verses — and returns how
    /// many rows it created.
    static func write(
        module fields: ModuleFields,
        books: [BibleImportBook],
        container: ModelContainer,
        onBookFinished: (@Sendable (Int, BibleImportBook) -> Void)? = nil
    ) throws -> Int {
        let coordinator = try SwiftDataModelBridge.coordinator(for: container)
        let model = coordinator.managedObjectModel

        guard let moduleEntity = model.entitiesByName["BibleModule"] else {
            throw WriteError.missingEntity("BibleModule")
        }
        guard let bookEntity = model.entitiesByName["BibleBook"] else {
            throw WriteError.missingEntity("BibleBook")
        }
        guard let chapterEntity = model.entitiesByName["BibleChapter"] else {
            throw WriteError.missingEntity("BibleChapter")
        }
        guard let verseEntity = model.entitiesByName["BibleVerse"] else {
            throw WriteError.missingEntity("BibleVerse")
        }

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        // Nothing here is ever undone, and an undo manager would keep every
        // change alive for the length of the import.
        context.undoManager = nil

        var written = 0
        try context.performAndWait {
            let module = NSManagedObject(entity: moduleEntity, insertInto: context)
            fields.apply(to: module)
            written += 1

            for (index, importBook) in books.enumerated() {
                // Same reason as the SwiftData path: the chapter and verse loops
                // churn thousands of transient Foundation objects, and draining
                // them per book keeps a whole-Bible import off the heap ceiling.
                written += autoreleasepool { () -> Int in
                    var rows = 0
                    let book = NSManagedObject(entity: bookEntity, insertInto: context)
                    book.setValue(UUID(), forKey: "id")
                    book.setValue(importBook.name, forKey: "name")
                    book.setValue(importBook.bookNumber, forKey: "bookNumber")
                    book.setValue(importBook.testament, forKey: "testament")
                    book.setValue(importBook.nameEnglish, forKey: "nameEnglish")
                    book.setValue(importBook.abbreviation, forKey: "abbreviation")
                    book.setValue(importBook.abbreviationEnglish, forKey: "abbreviationEnglish")
                    book.setValue(importBook.expectedChapters, forKey: "expectedChapters")
                    book.setValue(importBook.introduction ?? "", forKey: "introduction")
                    book.setValue(importBook.extensionsJSON, forKey: "extensionsJSON")
                    book.setValue(module, forKey: "module")
                    rows += 1

                    for importChapter in importBook.chapters {
                        let chapter = NSManagedObject(entity: chapterEntity, insertInto: context)
                        chapter.setValue(UUID(), forKey: "id")
                        chapter.setValue(importChapter.chapterNumber, forKey: "chapterNumber")
                        chapter.setValue(BibleRichData.encode(importChapter.headings), forKey: "headingsJSON")
                        chapter.setValue(importChapter.extensionsJSON, forKey: "extensionsJSON")
                        chapter.setValue(book, forKey: "book")
                        rows += 1

                        for importVerse in importChapter.verses {
                            let verse = NSManagedObject(entity: verseEntity, insertInto: context)
                            verse.setValue(UUID(), forKey: "id")
                            verse.setValue(importVerse.verseNumber, forKey: "verseNumber")
                            verse.setValue(importVerse.text, forKey: "text")
                            verse.setValue(BibleRichData.encode(importVerse.runs), forKey: "runsJSON")
                            verse.setValue(BibleRichData.encode(importVerse.footnotes), forKey: "footnotesJSON")
                            verse.setValue(BibleRichData.encode(importVerse.crossReferences), forKey: "crossRefsJSON")
                            verse.setValue(importVerse.hasWordsOfChrist, forKey: "hasWordsOfChrist")
                            verse.setValue(importVerse.gloss, forKey: "gloss")
                            verse.setValue(importVerse.poetryIndent, forKey: "poetryIndent")
                            verse.setValue(importVerse.extensionsJSON, forKey: "extensionsJSON")
                            verse.setValue(chapter, forKey: "chapter")
                            rows += 1
                        }
                    }
                    return rows
                }
                onBookFinished?(index, importBook)
            }

            try context.save()
        }
        noteSuccess()
        return written
    }
}
