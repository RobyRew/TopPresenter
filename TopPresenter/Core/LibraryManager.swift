//
//  LibraryManager.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import Observation

@Observable
final class LibraryManager {
    // MARK: - Bible State
    var selectedBibleModule: BibleModule?
    var selectedBook: BibleBook?
    var selectedChapter: BibleChapter? {
        didSet { refreshCachedVerses() }
    }
    var selectedVerses: [BibleVerse] = []
    var bibleSearchQuery: String = ""
    var bibleSearchResults: [BibleSearchResult] = []
    var isBibleSearching: Bool = false
    /// When true, verse selection auto-updates when presentation settings change.
    var isAutoFillActive: Bool = false

    /// Cached sorted verses for the current chapter — avoids re-sorting on every access.
    private(set) var cachedSortedVerses: [BibleVerse] = []

    private func refreshCachedVerses() {
        cachedSortedVerses = selectedChapter?.verses.sorted { $0.verseNumber < $1.verseNumber } ?? []
    }

    // MARK: - Song State
    var selectedSongCollection: SongCollection?
    var selectedSong: Song?
    var selectedSongVersion: SongVersion?
    var selectedSongVerse: SongVerse?
    var songSearchQuery: String = ""
    var songSearchResults: [SongSearchResult] = []
    var isSongSearching: Bool = false
    /// The song-LIBRARY browser's live filter text (distinct from the Quick Search
    /// overlay above). Shared so clickable chips in the detail can search by tag/source.
    var songLibraryQuery: String = ""

    /// When set, the Songs view presents the visual song editor for this song.
    var songToEdit: Song?
    /// When opening the editor from a specific slide, open this version and focus this section.
    var songEditVersionID: UUID?
    var songEditSectionKey: String?

    // Selected slide (version-aware; drives the sidebar preview + projection from the filmstrip).
    var songSlideText: String = ""
    var songSlideLabel: String = ""
    var songSlideIndex: Int = 0
    var songSlideCount: Int = 1

    // MARK: - Media State
    /// The media item highlighted in the Media view — drives the tab title.
    var selectedMediaItem: MediaItem?

    // MARK: - Bible Navigation
    /// Switch translation while staying on the same passage where possible.
    /// Fallback chain: same book+chapter+verse → same book, first verse →
    /// first book, first verse. Missing pieces in the new module are dropped.
    func selectModule(_ module: BibleModule) {
        let wantBook = selectedBook?.bookNumber
        let wantChapter = selectedChapter?.chapterNumber
        let wantVerses = selectedVerses.map { $0.verseNumber }

        selectedBibleModule = module
        isAutoFillActive = false

        let books = module.books.sorted { $0.bookNumber < $1.bookNumber }
        guard !books.isEmpty else {
            selectedBook = nil; selectedChapter = nil; selectedVerses = []
            return
        }
        // Same book number if present, else the first book.
        let book = books.first { $0.bookNumber == wantBook } ?? books[0]
        let keptBook = (book.bookNumber == wantBook)
        selectedBook = book

        let chapters = book.sortedChapters
        guard !chapters.isEmpty else {
            selectedChapter = nil; selectedVerses = []
            return
        }
        // Same chapter only if we kept the same book, else first chapter.
        let chapter = (keptBook ? chapters.first { $0.chapterNumber == wantChapter } : nil) ?? chapters[0]
        let keptChapter = keptBook && (chapter.chapterNumber == wantChapter)
        selectedChapter = chapter

        let verses = chapter.sortedVerses
        if keptChapter, !wantVerses.isEmpty {
            let kept = verses.filter { wantVerses.contains($0.verseNumber) }
            selectedVerses = kept.isEmpty ? Array(verses.prefix(1)) : kept
        } else {
            // Different book/chapter → land on the first available verse.
            selectedVerses = Array(verses.prefix(1))
        }
    }

    func selectBook(_ book: BibleBook) {
        selectedBook = book
        selectedChapter = nil
        selectedVerses = []
        isAutoFillActive = false
    }

    func selectChapter(_ chapter: BibleChapter) {
        selectedChapter = chapter
        selectedVerses = []
        isAutoFillActive = false
    }

    func toggleVerseSelection(_ verse: BibleVerse) {
        isAutoFillActive = false
        if let index = selectedVerses.firstIndex(where: { $0.id == verse.id }) {
            selectedVerses.remove(at: index)
        } else {
            selectedVerses.append(verse)
        }
        // Keep sorted by verse number
        selectedVerses.sort { $0.verseNumber < $1.verseNumber }
    }

    func selectVerse(_ verse: BibleVerse) {
        isAutoFillActive = false
        selectedVerses = [verse]
    }

    func clearVerseSelection() {
        isAutoFillActive = false
        selectedVerses = []
    }

    /// Formatted text for selected verses, respecting layout and prefix settings.
    /// When `customEnabled` and 2+ verses are selected, the joined verses are run
    /// through `customTemplate` (tokens: {verses} {ref} {n}); a template without
    /// {verses} gets the verses appended so they're never lost.
    func formattedSelectedVersesText(layout: String = "inline", showPrefix: Bool = false,
                                     customEnabled: Bool = false, customTemplate: String = "") -> String {
        if selectedVerses.isEmpty { return "" }
        let separator = layout == "newLine" ? "\n" : " "
        let joined = selectedVerses.map { v in
            showPrefix ? "(\(v.verseNumber)) \(v.text)" : v.text
        }.joined(separator: separator)

        guard customEnabled, selectedVerses.count > 1 else { return joined }
        let template = customTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return joined }
        var out = template
            .replacingOccurrences(of: "{verses}", with: joined)
            .replacingOccurrences(of: "{ref}", with: selectedVersesReference)
            .replacingOccurrences(of: "{n}", with: "\(selectedVerses.count)")
        if !template.contains("{verses}") { out += separator + joined }
        return out
    }

    /// Navigate to previous/next verse in the current chapter.
    /// When auto-fill is active, jumps by the full block size (number of selected verses).
    func navigateVerse(direction: Int) {
        guard selectedChapter != nil else { return }
        let sorted = cachedSortedVerses
        guard !sorted.isEmpty else { return }

        if isAutoFillActive {
            let blockSize = max(selectedVerses.count, 1)
            guard let firstVerse = selectedVerses.first,
                  let startIdx = sorted.firstIndex(where: { $0.id == firstVerse.id }) else { return }

            let newStart = startIdx + (direction > 0 ? blockSize : -blockSize)

            if newStart >= sorted.count {
                // Past end of chapter — caller should handle cross-chapter via
                // canAdvanceToNextChapter / advanceToNextChapter
                return
            }
            if newStart < 0 {
                // Before start of chapter — caller should handle via
                // canReturnToPreviousChapter / returnToPreviousChapter
                return
            }
            selectedVerses = [sorted[newStart]]
            // Don't clear isAutoFillActive — the view re-runs autoFill after this
        } else {
            let anchor = direction > 0 ? selectedVerses.last : selectedVerses.first
            guard let anchorVerse = anchor,
                  let currentIndex = sorted.firstIndex(where: { $0.id == anchorVerse.id }) else {
                if let first = sorted.first, direction > 0 {
                    selectedVerses = [first]
                } else if let last = sorted.last, direction < 0 {
                    selectedVerses = [last]
                }
                return
            }

            let newIndex = currentIndex + direction
            guard newIndex >= 0, newIndex < sorted.count else { return }
            selectedVerses = [sorted[newIndex]]
        }
    }

    func canNavigateVerse(direction: Int) -> Bool {
        guard selectedChapter != nil else { return false }
        let sorted = cachedSortedVerses
        guard !sorted.isEmpty else { return false }

        if isAutoFillActive {
            let blockSize = max(selectedVerses.count, 1)
            guard let firstVerse = selectedVerses.first,
                  let startIdx = sorted.firstIndex(where: { $0.id == firstVerse.id }) else { return false }
            let newStart = startIdx + (direction > 0 ? blockSize : -blockSize)
            return newStart >= 0 && newStart < sorted.count
        }

        let anchor = direction > 0 ? selectedVerses.last : selectedVerses.first
        guard let anchorVerse = anchor,
              let currentIndex = sorted.firstIndex(where: { $0.id == anchorVerse.id }) else {
            return true
        }
        let newIndex = currentIndex + direction
        return newIndex >= 0 && newIndex < sorted.count
    }

    // MARK: - Cross-Chapter Navigation

    /// Whether there is a next chapter available (in the same book, or the next book).
    var canAdvanceToNextChapter: Bool {
        guard let chapter = selectedChapter, let book = chapter.book else { return false }
        let chapters = book.sortedChapters
        if let idx = chapters.firstIndex(where: { $0.id == chapter.id }), idx + 1 < chapters.count {
            return true
        }
        // Check next book in the module
        if let module = book.module {
            let books = module.books.sorted { $0.bookNumber < $1.bookNumber }
            if let bookIdx = books.firstIndex(where: { $0.id == book.id }),
               bookIdx + 1 < books.count,
               !books[bookIdx + 1].sortedChapters.isEmpty {
                return true
            }
        }
        return false
    }

    /// Whether there is a previous chapter available.
    var canReturnToPreviousChapter: Bool {
        guard let chapter = selectedChapter, let book = chapter.book else { return false }
        let chapters = book.sortedChapters
        if let idx = chapters.firstIndex(where: { $0.id == chapter.id }), idx - 1 >= 0 {
            return true
        }
        // Check previous book
        if let module = book.module {
            let books = module.books.sorted { $0.bookNumber < $1.bookNumber }
            if let bookIdx = books.firstIndex(where: { $0.id == book.id }),
               bookIdx - 1 >= 0,
               !books[bookIdx - 1].sortedChapters.isEmpty {
                return true
            }
        }
        return false
    }

    /// Advance to the first verse of the next chapter (same book or next book).
    /// Keeps isAutoFillActive so the view can re-run autoFill.
    func advanceToNextChapter() {
        guard let chapter = selectedChapter, let book = chapter.book else { return }
        let chapters = book.sortedChapters

        if let idx = chapters.firstIndex(where: { $0.id == chapter.id }), idx + 1 < chapters.count {
            let next = chapters[idx + 1]
            selectedChapter = next
            selectedVerses = cachedSortedVerses.first.map { [$0] } ?? []
            // Keep isAutoFillActive — view will re-run autoFill
            return
        }
        // Next book's first chapter
        if let module = book.module {
            let books = module.books.sorted { $0.bookNumber < $1.bookNumber }
            if let bookIdx = books.firstIndex(where: { $0.id == book.id }),
               bookIdx + 1 < books.count {
                let nextBook = books[bookIdx + 1]
                selectedBook = nextBook
                if let firstChapter = nextBook.sortedChapters.first {
                    selectedChapter = firstChapter
                    selectedVerses = cachedSortedVerses.first.map { [$0] } ?? []
                }
            }
        }
    }

    /// Return to the last verse(s) of the previous chapter.
    /// Keeps isAutoFillActive so the view can re-run autoFill.
    func returnToPreviousChapter() {
        guard let chapter = selectedChapter, let book = chapter.book else { return }
        let chapters = book.sortedChapters

        if let idx = chapters.firstIndex(where: { $0.id == chapter.id }), idx - 1 >= 0 {
            let prev = chapters[idx - 1]
            selectedChapter = prev
            selectedVerses = cachedSortedVerses.last.map { [$0] } ?? []
            return
        }
        // Previous book's last chapter
        if let module = book.module {
            let books = module.books.sorted { $0.bookNumber < $1.bookNumber }
            if let bookIdx = books.firstIndex(where: { $0.id == book.id }),
               bookIdx - 1 >= 0 {
                let prevBook = books[bookIdx - 1]
                selectedBook = prevBook
                if let lastChapter = prevBook.sortedChapters.last {
                    selectedChapter = lastChapter
                    selectedVerses = cachedSortedVerses.last.map { [$0] } ?? []
                }
            }
        }
    }

    /// Automatically selects as many consecutive verses as can fit on the
    /// presentation screen, starting from the first currently selected verse
    /// (or verse 1 if none selected).
    func autoFillVerses(
        fontSize: Double,
        fontName: String,
        lineSpacing: Double,
        padding: Double,
        screenSize: CGSize,
        layout: String = "inline",
        showPrefix: Bool = false
    ) {
        guard selectedChapter != nil else { return }
        let sorted = cachedSortedVerses
        guard !sorted.isEmpty else { return }

        // Determine start index
        let startIndex: Int
        if let first = selectedVerses.first,
           let idx = sorted.firstIndex(where: { $0.id == first.id }) {
            startIndex = idx
        } else {
            startIndex = 0
        }

        let count = Self.versesCountThatFits(
            sorted: sorted,
            startIndex: startIndex,
            fontSize: fontSize,
            fontName: fontName,
            lineSpacing: lineSpacing,
            padding: padding,
            screenSize: screenSize,
            layout: layout,
            showPrefix: showPrefix
        )

        let endIndex = min(startIndex + max(count, 1), sorted.count)
        selectedVerses = Array(sorted[startIndex..<endIndex])
        isAutoFillActive = true
    }

    /// How many verses fit on screen starting from the first selected verse.
    /// Returns 0 if nothing is selected.
    func versesCountThatFits(
        fontSize: Double,
        fontName: String,
        lineSpacing: Double,
        padding: Double,
        screenSize: CGSize,
        layout: String = "inline",
        showPrefix: Bool = false
    ) -> Int {
        guard selectedChapter != nil else { return 0 }
        let sorted = cachedSortedVerses
        guard !sorted.isEmpty else { return 0 }

        let startIndex: Int
        if let first = selectedVerses.first,
           let idx = sorted.firstIndex(where: { $0.id == first.id }) {
            startIndex = idx
        } else {
            startIndex = 0
        }

        return Self.versesCountThatFits(
            sorted: sorted,
            startIndex: startIndex,
            fontSize: fontSize,
            fontName: fontName,
            lineSpacing: lineSpacing,
            padding: padding,
            screenSize: screenSize,
            layout: layout,
            showPrefix: showPrefix
        )
    }

    /// Pure calculation: how many consecutive verses from `startIndex` fit on screen.
    private static func versesCountThatFits(
        sorted: [BibleVerse],
        startIndex: Int,
        fontSize: Double,
        fontName: String,
        lineSpacing: Double,
        padding: Double,
        screenSize: CGSize,
        layout: String,
        showPrefix: Bool
    ) -> Int {
        // Resolve the NSFont
        let nsFont: NSFont
        if fontName == "System" || fontName.isEmpty {
            nsFont = NSFont.systemFont(ofSize: fontSize)
        } else {
            nsFont = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        }

        // `screenSize` is the point size of the FIXED verse text box — the reference,
        // translation, and subtitle live in their own boxes and need no reserve here.
        // Match the output layout: .padding(.horizontal, padding) inside the box,
        // .lineSpacing(lineSpacing * fontSize * 0.1).
        let availableWidth = max(screenSize.width - padding * 2, 50)
        let availableHeight = max(screenSize.height * 0.98, 50)

        // Build paragraph style matching SwiftUI's .lineSpacing() modifier
        // SwiftUI .lineSpacing adds EXTRA spacing between lines (not a multiplier)
        let extraLineSpacing = lineSpacing * fontSize * 0.1
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = extraLineSpacing
        paragraphStyle.alignment = .center

        let attributes: [NSAttributedString.Key: Any] = [
            .font: nsFont,
            .paragraphStyle: paragraphStyle
        ]

        // For "newLine" layout, verses are separated by \n which creates a full line break.
        // For "inline", verses are separated by " " (space).
        let separator = layout == "newLine" ? "\n" : " "

        // Greedily add whole verses while they fit
        var fittingCount = 0
        for i in startIndex..<sorted.count {
            let candidateVerses = Array(sorted[startIndex...i])
            let text = candidateVerses.map { v in
                showPrefix ? "(\(v.verseNumber)) \(v.text)" : v.text
            }.joined(separator: separator)

            let boundingRect = (text as NSString).boundingRect(
                with: CGSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )

            // Add a small safety margin (5%) to account for SwiftUI vs NSString rendering differences
            let measuredHeight = boundingRect.height * 1.05

            if measuredHeight > availableHeight {
                break // This verse doesn't fit — stop before adding it
            }
            fittingCount = candidateVerses.count
        }

        return fittingCount
    }

    var selectedVersesText: String {
        selectedVerses.map { $0.text }.joined(separator: " ")
    }

    /// Red-letter runs for the live verse — only when a SINGLE verse is
    /// selected and it carries rich runs (multi-verse blocks stay plain).
    var selectedVersesRuns: [VerseRun] {
        guard selectedVerses.count == 1 else { return [] }
        return selectedVerses[0].runs
    }

    // MARK: Rich casete sources for the live verse(s)
    /// Footnotes of the selected verse(s), one per line ("marker text").
    var selectedVersesFootnotes: String {
        selectedVerses.flatMap { $0.footnotes }
            .map { $0.marker.isEmpty ? $0.text : "\($0.marker) \($0.text)" }
            .joined(separator: "\n")
    }
    /// Cross-reference targets of the selected verse(s), separated by "; ".
    var selectedVersesCrossRefs: String {
        selectedVerses.flatMap { $0.crossReferences }
            .flatMap { ref in [ref.label].compactMap { $0 } + ref.targets }
            .joined(separator: "; ")
    }
    /// Section heading(s) (pericope) sitting within the selected verse range.
    var selectedVersesHeading: String {
        guard let chapter = selectedChapter else { return "" }
        let nums = Set(selectedVerses.map { $0.verseNumber })
        let lo = nums.min() ?? 0, hi = nums.max() ?? 0
        return chapter.headings
            .filter { $0.beforeVerse >= lo && $0.beforeVerse <= hi }
            .map { $0.text }.joined(separator: "\n")
    }
    /// Interlinear gloss (e.g. English under a Hebrew/Greek verse).
    var selectedVersesGloss: String {
        selectedVerses.map { $0.gloss }.filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// Strong's numbers of a single selected verse, space-separated.
    var selectedVersesStrongs: String {
        guard selectedVerses.count == 1 else { return "" }
        return selectedVerses[0].runs.compactMap { $0.strong }.joined(separator: " ")
    }

    var selectedVersesReference: String {
        guard let book = selectedBook, let chapter = selectedChapter else { return "" }
        let verseNumbers = selectedVerses.map { $0.verseNumber }
        if verseNumbers.isEmpty { return "" }

        let rangeString = formatVerseRange(verseNumbers)
        return "\(book.name) \(chapter.chapterNumber):\(rangeString)"
    }

    // MARK: - Song Navigation
    func selectCollection(_ collection: SongCollection) {
        selectedSongCollection = collection
        selectedSong = nil
        selectedSongVerse = nil
    }

    func selectSong(_ song: Song) {
        selectedSong = song
        selectedSongVersion = song.activeVersion
        selectedSongVerse = song.sortedVerses.first
        songSlideText = ""
        songSlideLabel = ""
        songSlideIndex = 0
        songSlideCount = 1
    }

    func selectSongVersion(_ version: SongVersion) {
        selectedSongVersion = version
        songSlideText = ""
        songSlideLabel = ""
    }

    /// Select a built slide (from the filmstrip) for preview/projection.
    func selectSongSlide(text: String, label: String, index: Int, count: Int) {
        songSlideText = text
        songSlideLabel = label
        songSlideIndex = index
        songSlideCount = count
    }

    func selectSongVerse(_ verse: SongVerse) {
        selectedSongVerse = verse
    }

    // MARK: - Bible Search
    func searchBible(query: String, in modules: [BibleModule]) {
        guard query.count >= 3 else {
            bibleSearchResults = []
            return
        }

        isBibleSearching = true
        bibleSearchResults = []

        let lowerQuery = query.lowercased()

        // Check if query is a reference (e.g., "John 3:16" or "Gen 1:1")
        if let refResult = parseReference(query, in: modules) {
            bibleSearchResults = refResult
            isBibleSearching = false
            return
        }

        // Full text search
        var results: [BibleSearchResult] = []
        for module in modules {
            for book in module.books {
                for chapter in book.chapters {
                    for verse in chapter.verses {
                        if verse.text.lowercased().contains(lowerQuery) {
                            let result = BibleSearchResult(
                                bookName: book.name,
                                chapterNumber: chapter.chapterNumber,
                                verseNumber: verse.verseNumber,
                                text: verse.text,
                                reference: "\(book.name) \(chapter.chapterNumber):\(verse.verseNumber)",
                                verseID: verse.id
                            )
                            results.append(result)
                            if results.count >= 200 { break }
                        }
                    }
                    if results.count >= 200 { break }
                }
                if results.count >= 200 { break }
            }
        }

        bibleSearchResults = results
        isBibleSearching = false
    }

    // MARK: - Song Search
    func searchSongs(query: String, in collections: [SongCollection]) {
        guard query.count >= 2 else {
            songSearchResults = []
            return
        }

        isSongSearching = true
        let lowerQuery = query.lowercased()
        var results: [SongSearchResult] = []

        for collection in collections {
            for song in collection.songs {
                // Match title
                if song.title.lowercased().contains(lowerQuery) {
                    results.append(SongSearchResult(
                        songID: song.id,
                        title: song.title,
                        author: song.author,
                        collectionName: collection.name,
                        matchedVerse: nil
                    ))
                    continue
                }

                // Match lyrics
                for verse in song.verses {
                    if verse.text.lowercased().contains(lowerQuery) {
                        results.append(SongSearchResult(
                            songID: song.id,
                            title: song.title,
                            author: song.author,
                            collectionName: collection.name,
                            matchedVerse: verse.text
                        ))
                        break
                    }
                }
            }
        }

        songSearchResults = results
        isSongSearching = false
    }

    // MARK: - Private Helpers

    private func parseReference(_ query: String, in modules: [BibleModule]) -> [BibleSearchResult]? {
        // Pattern: "BookName Chapter:Verse" or "BookName Chapter:Verse-Verse" or "BookName Chapter" (no verse)
        let pattern = #"^(\d?\s?[A-Za-zÀ-ÿ\s]+?)\s+(\d+)(?::(\d+)(?:-(\d+))?)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: query, range: NSRange(query.startIndex..., in: query)) else {
            return nil
        }

        guard let bookRange = Range(match.range(at: 1), in: query),
              let chapterRange = Range(match.range(at: 2), in: query) else {
            return nil
        }

        let bookName = String(query[bookRange]).trimmingCharacters(in: .whitespaces)
        let chapterNum = Int(query[chapterRange]) ?? 0

        var verseStart: Int? = nil
        var verseEnd: Int? = nil

        if let verseStartRange = Range(match.range(at: 3), in: query) {
            verseStart = Int(query[verseStartRange])
            if let verseEndRange = Range(match.range(at: 4), in: query) {
                verseEnd = Int(query[verseEndRange])
            } else {
                verseEnd = verseStart
            }
        }

        var results: [BibleSearchResult] = []
        for module in modules {
            for book in module.books {
                if book.name.lowercased().hasPrefix(bookName.lowercased()) {
                    for chapter in book.chapters where chapter.chapterNumber == chapterNum {
                        if let vStart = verseStart, let vEnd = verseEnd {
                            for verse in chapter.verses where verse.verseNumber >= vStart && verse.verseNumber <= vEnd {
                                results.append(BibleSearchResult(
                                    bookName: book.name,
                                    chapterNumber: chapter.chapterNumber,
                                    verseNumber: verse.verseNumber,
                                    text: verse.text,
                                    reference: "\(book.name) \(chapter.chapterNumber):\(verse.verseNumber)",
                                    verseID: verse.id
                                ))
                            }
                        } else {
                            // No verse specified — return all verses in the chapter
                            for verse in chapter.sortedVerses {
                                results.append(BibleSearchResult(
                                    bookName: book.name,
                                    chapterNumber: chapter.chapterNumber,
                                    verseNumber: verse.verseNumber,
                                    text: verse.text,
                                    reference: "\(book.name) \(chapter.chapterNumber):\(verse.verseNumber)",
                                    verseID: verse.id
                                ))
                            }
                        }
                    }
                }
            }
        }

        return results.isEmpty ? nil : results
    }

    private func formatVerseRange(_ numbers: [Int]) -> String {
        guard !numbers.isEmpty else { return "" }
        if numbers.count == 1 { return "\(numbers[0])" }

        var ranges: [String] = []
        var rangeStart = numbers[0]
        var rangeEnd = numbers[0]

        for i in 1..<numbers.count {
            if numbers[i] == rangeEnd + 1 {
                rangeEnd = numbers[i]
            } else {
                ranges.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")
                rangeStart = numbers[i]
                rangeEnd = numbers[i]
            }
        }
        ranges.append(rangeStart == rangeEnd ? "\(rangeStart)" : "\(rangeStart)-\(rangeEnd)")

        return ranges.joined(separator: ",")
    }
}
