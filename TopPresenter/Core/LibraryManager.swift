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
    var selectedSongVerse: SongVerse?
    var songSearchQuery: String = ""
    var songSearchResults: [SongSearchResult] = []
    var isSongSearching: Bool = false

    // MARK: - Bible Navigation
    func selectModule(_ module: BibleModule) {
        selectedBibleModule = module
        selectedBook = nil
        selectedChapter = nil
        selectedVerses = []
        isAutoFillActive = false
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
    func formattedSelectedVersesText(layout: String = "inline", showPrefix: Bool = false) -> String {
        if selectedVerses.isEmpty { return "" }
        let separator = layout == "newLine" ? "\n" : " "
        return selectedVerses.map { v in
            showPrefix ? "(\(v.verseNumber)) \(v.text)" : v.text
        }.joined(separator: separator)
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

        // Match PresentationOutputView layout exactly:
        // - Main text: .padding(.horizontal, padding), .lineSpacing(lineSpacing * fontSize * 0.1)
        // - Reference: .font(.system(size: fontSize * 0.55)), .padding(.top, fontSize * 0.4)
        // - Content is in VStack with Spacer() top/bottom (centered)
        // - Subtitle (optional, usually empty for Bible)

        let refFontSize = fontSize * 0.55
        let refLineHeight = refFontSize * 1.3 // approximate line height for reference
        let refTopPadding = fontSize * 0.4

        // Vertical space consumed by reference + its padding
        let referenceReserve = refLineHeight + refTopPadding

        // Horizontal padding on both sides
        let availableWidth = max(screenSize.width - padding * 2, 100)

        // Total vertical space minus reference area and some top/bottom breathing room
        // The breathing room accounts for the Spacer() centering — text shouldn't fill 100%
        let breathingRoom = fontSize * 1.5 // top + bottom margin from centering
        let availableHeight = max(screenSize.height - referenceReserve - breathingRoom, 100)

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
        selectedSongVerse = song.sortedVerses.first
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
