//
//  OSISBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for OSIS XML format Bibles.
/// OSIS (Open Scripture Information Standard) is a widely used XML schema for Bible texts.
final class OSISBibleImporter: BibleImporter {
    let format: SupportedBibleFormat = .osisXML

    func parse(fileURL: URL) async throws -> BibleImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BibleImportError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw BibleImportError.emptyFile }

        let delegate = OSISParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true

        guard parser.parse() else {
            let errorDesc = parser.parserError?.localizedDescription ?? "Unknown error"
            throw BibleImportError.parsingFailed(errorDesc)
        }

        guard !delegate.books.isEmpty else {
            throw BibleImportError.invalidFormat("No books found in OSIS file")
        }

        return BibleImportResult(
            moduleName: delegate.workTitle.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : delegate.workTitle,
            abbreviation: delegate.workAbbreviation,
            language: delegate.language.isEmpty ? "en" : delegate.language,
            description: delegate.workDescription,
            books: delegate.books
        )
    }
}

// MARK: - OSIS XML Parser Delegate
private final class OSISParserDelegate: NSObject, XMLParserDelegate {
    var workTitle = ""
    var workAbbreviation = ""
    var workDescription = ""
    var language = ""
    var books: [BibleImportBook] = []

    private var currentElement = ""
    private var currentBookOSISID = ""
    private var currentBookName = ""
    private var currentChapterNumber = 0
    private var currentVerseNumber = 0
    private var currentText = ""

    private var chapters: [BibleImportChapter] = []
    private var verses: [BibleImportVerse] = []

    private var isInVerse = false
    private var isInTitle = false
    private var isInHeader = false
    private var isInNote = false
    private var noteDepth = 0

    // GOAT v2: red-letter + section headings
    private var wocDepth = 0
    private var runBuf = ""
    private var currentRuns: [VerseRun] = []
    private var hasWoc = false
    private var isInSectionTitle = false
    private var sectionTitleText = ""
    private var pendingHeadings: [BibleHeading] = []

    private var bookCounter = 0

    /// Flush the active run buffer into `currentRuns` with the current kind.
    private func flushRun() {
        let t = runBuf.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if !t.trimmingCharacters(in: .whitespaces).isEmpty {
            currentRuns.append(VerseRun(text: t, kind: wocDepth > 0 ? "woc" : "plain"))
        }
        runBuf = ""
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName

        switch elementName {
        case "work":
            break

        case "title":
            if isInHeader {
                isInTitle = true
                currentText = ""
            } else {
                isInSectionTitle = true
                sectionTitleText = ""
            }

        case "header":
            isInHeader = true

        case "language":
            currentText = ""

        case "description":
            currentText = ""

        case "div":
            if let type = attributeDict["type"], type == "book" {
                if let osisID = attributeDict["osisID"] {
                    currentBookOSISID = osisID
                    currentBookName = OSISBookIDs.mapping[osisID] ?? osisID
                    bookCounter += 1
                    chapters = []
                }
            }

        case "chapter":
            if let osisID = attributeDict["osisID"] {
                // Format: "Gen.1"
                let parts = osisID.split(separator: ".")
                if parts.count >= 2, let num = Int(parts.last ?? "0") {
                    currentChapterNumber = num
                } else {
                    currentChapterNumber += 1
                }
                verses = []
            } else if let sID = attributeDict["sID"] {
                let parts = sID.split(separator: ".")
                if parts.count >= 2, let num = Int(parts.last ?? "0") {
                    currentChapterNumber = num
                }
                verses = []
            }

        case "verse":
            if let osisID = attributeDict["osisID"] {
                // Format: "Gen.1.1"
                let parts = osisID.split(separator: ".")
                if parts.count >= 3, let num = Int(parts.last ?? "0") {
                    currentVerseNumber = num
                }
                isInVerse = true
                currentText = ""
            } else if let sID = attributeDict["sID"] {
                let parts = sID.split(separator: ".")
                if parts.count >= 3, let num = Int(parts.last ?? "0") {
                    currentVerseNumber = num
                }
                isInVerse = true
                currentText = ""
            } else if attributeDict["eID"] != nil {
                // End of verse milestone
                finishCurrentVerse()
            }

        case "q":
            if let who = attributeDict["who"], who.lowercased().contains("jesus") {
                if isInVerse { flushRun() }
                wocDepth += 1
                hasWoc = true
            }

        case "note":
            isInNote = true
            noteDepth += 1

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInNote { return }

        if isInSectionTitle {
            sectionTitleText += string
            return
        }
        if isInVerse {
            currentText += string
            runBuf += string
        } else if isInTitle && isInHeader {
            currentText += string
        } else if currentElement == "language" {
            currentText += string
        } else if currentElement == "description" && isInHeader {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "header":
            isInHeader = false

        case "title":
            if isInTitle && isInHeader {
                workTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                isInTitle = false
            }

        case "language":
            if isInHeader {
                language = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentText = ""

        case "description":
            if isInHeader {
                workDescription = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentText = ""

        case "div":
            // End of book
            if !chapters.isEmpty || !verses.isEmpty {
                finishCurrentChapter()
                let testament = bookCounter <= 39 ? "OT" : "NT"
                let book = BibleImportBook(
                    name: currentBookName,
                    bookNumber: bookCounter,
                    testament: testament,
                    chapters: chapters
                )
                books.append(book)
                chapters = []
            }

        case "chapter":
            finishCurrentChapter()

        case "verse":
            finishCurrentVerse()

        case "title":
            if isInSectionTitle {
                let t = sectionTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    pendingHeadings.append(BibleHeading(beforeVerse: currentVerseNumber + 1, level: 1, text: t))
                }
                isInSectionTitle = false
                sectionTitleText = ""
            }

        case "q":
            if wocDepth > 0 {
                flushRun()
                wocDepth -= 1
            }

        case "note":
            noteDepth -= 1
            if noteDepth <= 0 {
                isInNote = false
                noteDepth = 0
            }

        default:
            break
        }

        if currentElement == elementName {
            currentElement = ""
        }
    }

    private func finishCurrentVerse() {
        if isInVerse {
            flushRun()
            let cleanText = currentText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

            if !cleanText.isEmpty {
                let runs = hasWoc ? currentRuns.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty } : nil
                verses.append(BibleImportVerse(
                    verseNumber: currentVerseNumber,
                    text: cleanText,
                    runs: runs,
                    hasWordsOfChrist: hasWoc
                ))
            }
            isInVerse = false
            currentText = ""
            currentRuns = []
            runBuf = ""
            hasWoc = false
            wocDepth = 0
        }
    }

    private func finishCurrentChapter() {
        if !verses.isEmpty {
            chapters.append(BibleImportChapter(
                chapterNumber: currentChapterNumber,
                verses: verses,
                headings: pendingHeadings.isEmpty ? nil : pendingHeadings
            ))
            verses = []
            pendingHeadings = []
        }
    }
}
