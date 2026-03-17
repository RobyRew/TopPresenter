//
//  ZefaniaBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for Zefania XML format Bibles.
/// Zefania XML is a popular open Bible format used in many Bible software applications.
final class ZefaniaBibleImporter: BibleImporter {
    let format: SupportedBibleFormat = .zefaniaXML

    func parse(fileURL: URL) async throws -> BibleImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BibleImportError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw BibleImportError.emptyFile }

        let delegate = ZefaniaParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let errorDesc = parser.parserError?.localizedDescription ?? "Unknown error"
            throw BibleImportError.parsingFailed(errorDesc)
        }

        guard !delegate.books.isEmpty else {
            throw BibleImportError.invalidFormat("No books found in Zefania file")
        }

        return BibleImportResult(
            moduleName: delegate.bibleName.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : delegate.bibleName,
            abbreviation: delegate.abbreviation,
            language: delegate.language.isEmpty ? "en" : delegate.language,
            description: delegate.bibleDescription,
            books: delegate.books
        )
    }
}

// MARK: - Zefania XML Parser Delegate
private final class ZefaniaParserDelegate: NSObject, XMLParserDelegate {
    var bibleName = ""
    var abbreviation = ""
    var language = ""
    var bibleDescription = ""
    var books: [BibleImportBook] = []

    private var currentElement = ""
    private var currentText = ""
    private var currentBookNumber = 0
    private var currentChapterNumber = 0
    private var currentVerseNumber = 0

    private var chapters: [BibleImportChapter] = []
    private var verses: [BibleImportVerse] = []

    private var isInInformation = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "XMLBIBLE", "xmlbible":
            bibleName = attributeDict["biblename"] ?? attributeDict["BIBLENAME"] ?? ""

        case "INFORMATION", "information":
            isInInformation = true

        case "BIBLEBOOK", "biblebook":
            if let bnr = attributeDict["bnumber"] ?? attributeDict["BNUMBER"] {
                currentBookNumber = Int(bnr) ?? 0
            }
            chapters = []

        case "CHAPTER", "chapter":
            if let cnr = attributeDict["cnumber"] ?? attributeDict["CNUMBER"] {
                currentChapterNumber = Int(cnr) ?? 0
            }
            verses = []

        case "VERS", "vers":
            if let vnr = attributeDict["vnumber"] ?? attributeDict["VNUMBER"] {
                currentVerseNumber = Int(vnr) ?? 0
            }
            currentText = ""

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmedText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "INFORMATION", "information":
            isInInformation = false

        case "title", "TITLE":
            if isInInformation && !trimmedText.isEmpty {
                bibleName = trimmedText
            }

        case "language", "LANGUAGE":
            if isInInformation {
                language = trimmedText
            }

        case "description", "DESCRIPTION":
            if isInInformation {
                bibleDescription = trimmedText
            }

        case "identifier", "IDENTIFIER":
            if isInInformation && !trimmedText.isEmpty {
                abbreviation = trimmedText
            }

        case "VERS", "vers":
            let cleanText = trimmedText
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            if !cleanText.isEmpty {
                verses.append(BibleImportVerse(
                    verseNumber: currentVerseNumber,
                    text: cleanText
                ))
            }

        case "CHAPTER", "chapter":
            if !verses.isEmpty {
                chapters.append(BibleImportChapter(
                    chapterNumber: currentChapterNumber,
                    verses: verses
                ))
                verses = []
            }

        case "BIBLEBOOK", "biblebook":
            if !chapters.isEmpty {
                let testament = currentBookNumber <= 39 ? "OT" : "NT"
                let bookName = bookNameForNumber(currentBookNumber)
                books.append(BibleImportBook(
                    name: bookName,
                    bookNumber: currentBookNumber,
                    testament: testament,
                    chapters: chapters
                ))
                chapters = []
            }

        default:
            break
        }
    }

    private func bookNameForNumber(_ number: Int) -> String {
        let allBooks = BibleBookNames.all
        if number >= 1 && number <= allBooks.count {
            return allBooks[number - 1]
        }
        return "Book \(number)"
    }
}
