//
//  BibleNavigator.swift
//  TopPresenter
//
//  Resolving a passage by COORDINATES, without walking the module's object graph.
//

import Foundation
import SwiftData
import Observation

/// Answers "where is <translation> <book> <chapter>?" with targeted fetches and
/// caches the answer by coordinate.
///
/// The live stepping path used to answer that question by fetching EVERY module,
/// then reading `module.books` — a to-many fault that materialises all 66 books —
/// then `book.chapters.sorted` (every chapter of the book), then
/// `chapter.verses.sorted`. It did all of that on every ←/→ press, so each press
/// paid for a whole translation in order to move by one verse. On a library with
/// 29 modules / 31 201 chapters / 820 733 verses that is seconds per press.
///
/// Three changes here:
///  * a passage is fetched by predicate with `verses` prefetched, so one query
///    returns the chapter AND its verses instead of a fault per row;
///  * resolved passages are cached by `(module, book, chapter)`, so stepping
///    inside a chapter touches the store zero times;
///  * the *spine* — which book numbers a module has, which chapter numbers a book
///    has — is cached separately, because crossing a boundary needs only those
///    integers, never the objects.
///
/// Cached values are `@Model` references, which stop being valid when their rows
/// are deleted. `invalidate()` runs on every `.libraryDidChange` naming Bibles;
/// bulk deletes go through `LibraryTaskRunner`, which posts exactly that.
@MainActor
@Observable
final class BibleNavigator {
    /// App-global, like `PinStore`: the cache is about the STORE, not a window,
    /// and two windows browsing the same translation should share the work.
    static let shared = BibleNavigator()

    /// One resolved chapter: the objects a caller needs, already ordered.
    struct Passage {
        let module: BibleModule
        let book: BibleBook
        let chapter: BibleChapter
        /// Sorted by verse number. Relationship arrays are unordered, so this is
        /// the only ordering callers may rely on.
        let verses: [BibleVerse]
    }

    private struct Key: Hashable {
        let moduleID: UUID
        let bookNumber: Int
        let chapter: Int
    }

    private struct BookKey: Hashable {
        let moduleID: UUID
        let bookNumber: Int
    }

    @ObservationIgnored private var passages: [Key: Passage] = [:]
    /// Insertion order for `passages` — oldest first, so the cache can be trimmed.
    @ObservationIgnored private var passageOrder: [Key] = []
    @ObservationIgnored private var bookCache: [BookKey: BibleBook] = [:]
    @ObservationIgnored private var chapterNumbers: [UUID: [Int: [Int]]] = [:]  // module → book → chapters
    @ObservationIgnored private var chapterCounts: [UUID: [Int: Int]] = [:]     // module → book → count
    @ObservationIgnored private var bookNumbers: [UUID: [Int]] = [:]
    @ObservationIgnored private var modulesByAbbreviation: [String: BibleModule] = [:]
    @ObservationIgnored private var observer: (any NSObjectProtocol)?

    /// Chapters kept resolved. Generous enough to cover a reading that walks a
    /// few chapters back and forth, small enough that the objects it pins are a
    /// rounding error against the store.
    private static let passageCap = 24

    /// Not private so tests can hold an instance of their own — the cache is
    /// keyed by module id, and a shared one would leak state between them.
    init() {
        observer = NotificationCenter.default.addObserver(
            forName: .libraryDidChange, object: nil, queue: .main
        ) { [weak self] note in
            let kinds = note.userInfo?[Notification.Name.changedKindsKey] as? [String]
            // An un-annotated post means "something changed" — the safe reading
            // is everything, since a stale @Model reference is worse than a
            // re-fetch.
            guard kinds == nil || kinds!.contains(ImportKind.bible.rawValue) else { return }
            MainActor.assumeIsolated { self?.invalidate() }
        }
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Drop every cached object and spine. Called whenever Bibles change.
    func invalidate() {
        passages.removeAll()
        passageOrder.removeAll()
        bookCache.removeAll()
        chapterNumbers.removeAll()
        chapterCounts.removeAll()
        bookNumbers.removeAll()
        modulesByAbbreviation.removeAll()
    }

    // MARK: - Module lookup

    /// The module whose abbreviation matches, case-insensitively.
    ///
    /// Abbreviations are matched in Swift rather than in a `#Predicate` because
    /// the comparison is case-insensitive and predicate-side case folding is not
    /// portable across stores. The fetch itself is ~30 rows of scalars and the
    /// result is cached, so it runs once per abbreviation per library change.
    func module(abbreviation: String, in context: ModelContext) -> BibleModule? {
        let wanted = abbreviation.lowercased()
        if let hit = modulesByAbbreviation[wanted] { return hit }
        let all = (try? context.fetch(FetchDescriptor<BibleModule>())) ?? []
        guard let found = all.first(where: { $0.abbreviation.lowercased() == wanted }) else { return nil }
        modulesByAbbreviation[wanted] = found
        return found
    }

    // MARK: - Spine (the integers, never the objects)

    /// Book numbers present in a module, ascending.
    func bookNumbers(moduleID: UUID, in context: ModelContext) -> [Int] {
        if let hit = bookNumbers[moduleID] { return hit }
        var d = FetchDescriptor<BibleBook>(
            predicate: #Predicate { $0.module?.id == moduleID },
            sortBy: [SortDescriptor(\.bookNumber)])
        // Only the number is read — asking for nothing else keeps the row small.
        d.propertiesToFetch = [\.bookNumber]
        let numbers = ((try? context.fetch(d)) ?? []).map(\.bookNumber)
        bookNumbers[moduleID] = numbers
        return numbers
    }

    /// How many chapters each book of a module has, keyed by book number.
    ///
    /// The book list shows this count per row, and `book.chapters.count` is a
    /// to-many fault: one query per book, per render, and `ViewThatFits` asks
    /// three times per row. Here it is two queries for the whole module — the
    /// books, then their chapters in one batch — cached until Bibles change.
    func chapterCounts(moduleID: UUID, in context: ModelContext) -> [Int: Int] {
        if let hit = chapterCounts[moduleID] { return hit }
        var d = FetchDescriptor<BibleBook>(predicate: #Predicate { $0.module?.id == moduleID })
        d.relationshipKeyPathsForPrefetching = [\.chapters]
        var counts: [Int: Int] = [:]
        for book in (try? context.fetch(d)) ?? [] { counts[book.bookNumber] = book.chapters.count }
        chapterCounts[moduleID] = counts
        return counts
    }

    /// One book, by module and number.
    ///
    /// Resolved in its OWN fetch, and every chapter query then keys off the
    /// book's id, because a `#Predicate` may traverse exactly ONE optional
    /// relationship. `$0.book?.module?.id == moduleID` compiles happily, but
    /// `#Predicate` lowers it to `TERNARY(book != nil, book.module, nil).id`
    /// and Core Data's SQL generator cannot apply a keypath to a ternary — it
    /// raises `NSInvalidArgumentException` from inside the fetch, which is an
    /// uncatchable crash rather than a thrown error.
    func book(moduleID: UUID, bookNumber: Int, in context: ModelContext) -> BibleBook? {
        let key = BookKey(moduleID: moduleID, bookNumber: bookNumber)
        if let hit = bookCache[key] { return hit }
        var d = FetchDescriptor<BibleBook>(predicate: #Predicate {
            $0.bookNumber == bookNumber && $0.module?.id == moduleID
        })
        d.fetchLimit = 1
        guard let found = (try? context.fetch(d))?.first else { return nil }
        bookCache[key] = found
        return found
    }

    /// Chapter numbers present in one book, ascending.
    func chapterNumbers(moduleID: UUID, bookNumber: Int, in context: ModelContext) -> [Int] {
        if let hit = chapterNumbers[moduleID]?[bookNumber] { return hit }
        guard let bookID = book(moduleID: moduleID, bookNumber: bookNumber, in: context)?.id else {
            chapterNumbers[moduleID, default: [:]][bookNumber] = []
            return []
        }
        var d = FetchDescriptor<BibleChapter>(
            predicate: #Predicate { $0.book?.id == bookID },
            sortBy: [SortDescriptor(\.chapterNumber)])
        d.propertiesToFetch = [\.chapterNumber]
        let numbers = ((try? context.fetch(d)) ?? []).map(\.chapterNumber)
        chapterNumbers[moduleID, default: [:]][bookNumber] = numbers
        return numbers
    }

    // MARK: - Passages

    /// One chapter with its verses, ordered — cached by coordinate.
    func passage(moduleID: UUID, bookNumber: Int, chapter: Int,
                 in context: ModelContext) -> Passage? {
        let key = Key(moduleID: moduleID, bookNumber: bookNumber, chapter: chapter)
        if let hit = passages[key] { return hit }

        guard let book = book(moduleID: moduleID, bookNumber: bookNumber, in: context),
              let module = book.module else { return nil }
        let bookID = book.id
        var d = FetchDescriptor<BibleChapter>(predicate: #Predicate {
            $0.chapterNumber == chapter && $0.book?.id == bookID
        })
        d.fetchLimit = 1
        // The whole point: the verses arrive WITH the chapter, in one query,
        // instead of one fault per verse when the caller reads them.
        d.relationshipKeyPathsForPrefetching = [\.verses]
        guard let found = (try? context.fetch(d))?.first else { return nil }

        let resolved = Passage(
            module: module, book: book, chapter: found,
            verses: found.verses.sorted { $0.verseNumber < $1.verseNumber })
        store(resolved, at: key)
        return resolved
    }

    private func store(_ passage: Passage, at key: Key) {
        if passages[key] == nil { passageOrder.append(key) }
        passages[key] = passage
        while passageOrder.count > Self.passageCap {
            passages.removeValue(forKey: passageOrder.removeFirst())
        }
    }

    // MARK: - Stepping the spine

    /// The chapter before or after this one, crossing into the neighbouring book
    /// when the current one runs out. nil at the ends of the module.
    func adjacentChapter(moduleID: UUID, bookNumber: Int, chapter: Int, direction: Int,
                         in context: ModelContext) -> (bookNumber: Int, chapter: Int)? {
        guard direction != 0 else { return (bookNumber, chapter) }
        let chapters = chapterNumbers(moduleID: moduleID, bookNumber: bookNumber, in: context)
        if let idx = chapters.firstIndex(of: chapter) {
            let next = idx + (direction > 0 ? 1 : -1)
            if next >= 0, next < chapters.count { return (bookNumber, chapters[next]) }
        }
        // Off the end of this book — walk to the neighbouring book that has any
        // chapters at all (a partial module can carry an empty book).
        let books = bookNumbers(moduleID: moduleID, in: context)
        guard var idx = books.firstIndex(of: bookNumber) else { return nil }
        while true {
            idx += direction > 0 ? 1 : -1
            guard idx >= 0, idx < books.count else { return nil }
            let candidate = books[idx]
            let theirs = chapterNumbers(moduleID: moduleID, bookNumber: candidate, in: context)
            if let landing = direction > 0 ? theirs.first : theirs.last {
                return (candidate, landing)
            }
        }
    }

    // MARK: - Prefetch

    /// Warm the chapters on either side of this one, off the critical path.
    ///
    /// Presenting walks forwards, and a listener who asks to see the previous
    /// verse again should not wait for a query either. This runs at low priority
    /// AFTER the current chapter is on screen, so the neighbours are already
    /// resolved by the time ←/→ reaches them; it is pure cache-filling and
    /// dropping it changes only the timing.
    func prefetchNeighbours(moduleID: UUID, bookNumber: Int, chapter: Int,
                            in context: ModelContext) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Yield first: the present that triggered this still owns the frame.
            await Task.yield()
            for direction in [1, -1] {
                guard let next = self.adjacentChapter(
                    moduleID: moduleID, bookNumber: bookNumber,
                    chapter: chapter, direction: direction, in: context) else { continue }
                _ = self.passage(moduleID: moduleID, bookNumber: next.bookNumber,
                                 chapter: next.chapter, in: context)
                await Task.yield()
            }
        }
    }
}
