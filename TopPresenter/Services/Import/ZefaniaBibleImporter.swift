//
//  ZefaniaBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for Zefania XML format Bibles.
/// Maps the full Zefania feature set into the GOAT model: `<CAPTION>`→headings,
/// `<NOTE>`→footnotes, `<XREF>`→cross-references, red `<STYLE>`→words-of-Christ runs,
/// `<gr str>`→Strong's numbers, and `<INFORMATION>`→module metadata.
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
            books: delegate.books,
            copyright: delegate.copyright,
            year: delegate.year,
            hasWordsOfChrist: delegate.hasAnyWoc,
            hasStrongs: delegate.hasAnyStrong
        )
    }
}

// MARK: - Zefania XML Parser Delegate
private final class ZefaniaParserDelegate: NSObject, XMLParserDelegate {
    var bibleName = ""
    var abbreviation = ""
    var language = ""
    var bibleDescription = ""
    var copyright = ""
    var year: Int?
    var hasAnyWoc = false
    var hasAnyStrong = false
    var books: [BibleImportBook] = []

    private var currentBookNumber = 0
    private var currentBookSname = ""
    private var currentChapterNumber = 0
    private var currentVerseNumber = 0

    private var chapters: [BibleImportChapter] = []
    private var verses: [BibleImportVerse] = []
    private var pendingHeadings: [BibleHeading] = []

    private var isInInformation = false
    private var infoBuffer = ""

    // Verse parsing state
    private var inVerse = false
    private var verseText = ""
    private var runs: [VerseRun] = []
    private var runText = ""
    private var runKind = "plain"
    private var runStrong: String?
    private var styleRedDepth = 0
    private var inNote = false
    private var noteText = ""
    private var footnotes: [BibleFootnote] = []
    private var inXref = false
    private var xrefText = ""
    private var xrefs: [BibleCrossRef] = []
    private var inCaption = false
    private var captionVref = 1
    private var captionText = ""

    private func flushRun() {
        if !runText.isEmpty {
            runs.append(VerseRun(text: runText, kind: runKind, strong: runStrong))
            if runKind == "woc" { hasAnyWoc = true }
            if runStrong != nil { hasAnyStrong = true }
            runText = ""
        }
    }

    private func isRedStyle(_ a: [String: String]) -> Bool {
        let s = ((a["css"] ?? "") + " " + (a["fs"] ?? "") + " " + (a["id"] ?? "") + " " + (a["class"] ?? "")).lowercased()
        if s.contains("wordsofjesus") || s.contains("jesus") || s.contains("words-of-christ") || s.contains("cl_wj") { return true }
        if s.contains("red") || s.contains("#ff0000") || s.contains("#f00") || s.contains("#cc0000") || s.contains("#e30") { return true }
        return false
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        func attr(_ k: String) -> String? { a[k] ?? a[k.uppercased()] ?? a[k.lowercased()] }

        switch elementName.lowercased() {
        case "xmlbible":
            bibleName = attr("biblename") ?? ""
        case "information":
            isInInformation = true
        case "biblebook":
            currentBookNumber = Int(attr("bnumber") ?? "") ?? 0
            currentBookSname = attr("bsname") ?? ""
            chapters = []
        case "chapter":
            currentChapterNumber = Int(attr("cnumber") ?? "") ?? 0
            verses = []
            pendingHeadings = []
        case "vers":
            currentVerseNumber = Int(attr("vnumber") ?? "") ?? 0
            inVerse = true
            verseText = ""; runs = []; runText = ""; runKind = "plain"; runStrong = nil; styleRedDepth = 0
            footnotes = []; xrefs = []
        case "caption":
            inCaption = true; captionText = ""
            captionVref = Int(attr("vref") ?? "") ?? (currentVerseNumber > 0 ? currentVerseNumber + 1 : 1)
        case "note":
            if inVerse { inNote = true; noteText = "" }
        case "xref":
            if inVerse {
                inXref = true; xrefText = ""
                let scope = attr("fscope") ?? attr("mscope") ?? ""
                let targets = scope.split(whereSeparator: { $0 == ";" || $0 == "," || $0 == "|" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                if !targets.isEmpty { xrefs.append(BibleCrossRef(targets: targets)) }
            }
        case "style":
            if inVerse, isRedStyle(a) { flushRun(); runKind = "woc"; styleRedDepth += 1 }
        case "gr":
            if inVerse { flushRun(); runStrong = attr("str") ?? attr("strong") }
        case "br":
            if inVerse { verseText += " "; runText += " " }
        default:
            break
        }
        infoBuffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inNote { noteText += string }
        else if inXref { xrefText += string }
        else if inCaption { captionText += string }
        else if inVerse { verseText += string; runText += string }
        else if isInInformation { infoBuffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let info = infoBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName.lowercased() {
        case "information": isInInformation = false
        case "title": if isInInformation && !info.isEmpty { bibleName = info }
        case "language": if isInInformation { language = info }
        case "description": if isInInformation { bibleDescription = info }
        case "identifier": if isInInformation && !info.isEmpty { abbreviation = info }
        case "rights": if isInInformation { copyright = info }
        case "date": if isInInformation, let y = Int(info.prefix(4)) { year = y }

        case "caption":
            inCaption = false
            let txt = captionText.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentChapterNumber > 0, !txt.isEmpty {
                pendingHeadings.append(BibleHeading(beforeVerse: captionVref, level: 1, text: txt))
            }
        case "note":
            if inNote {
                let t = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { footnotes.append(BibleFootnote(text: t)) }
                inNote = false
            }
        case "xref":
            if inXref {
                let t = xrefText.trimmingCharacters(in: .whitespacesAndNewlines)
                if xrefs.last?.targets.isEmpty != false, !t.isEmpty {
                    xrefs.append(BibleCrossRef(targets: [t]))
                }
                inXref = false
            }
        case "style":
            if styleRedDepth > 0 { flushRun(); runKind = "plain"; styleRedDepth -= 1 }
        case "gr":
            flushRun(); runStrong = nil

        case "vers":
            if inVerse {
                flushRun()
                let cleanText = verseText
                    .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanText.isEmpty {
                    let hasWoc = runs.contains { $0.kind == "woc" }
                    let rich = runs.contains { $0.kind != "plain" || $0.strong != nil }
                    verses.append(BibleImportVerse(
                        verseNumber: currentVerseNumber,
                        text: cleanText,
                        runs: rich ? runs : nil,
                        footnotes: footnotes.isEmpty ? nil : footnotes,
                        crossReferences: xrefs.isEmpty ? nil : xrefs,
                        hasWordsOfChrist: hasWoc
                    ))
                }
                inVerse = false
            }
        case "chapter":
            if !verses.isEmpty {
                chapters.append(BibleImportChapter(
                    chapterNumber: currentChapterNumber,
                    verses: verses,
                    headings: pendingHeadings.isEmpty ? nil : pendingHeadings
                ))
                verses = []; pendingHeadings = []
            }
        case "biblebook":
            if !chapters.isEmpty {
                let testament = currentBookNumber <= 39 ? "OT" : "NT"
                books.append(BibleImportBook(
                    name: bookNameForNumber(currentBookNumber),
                    bookNumber: currentBookNumber,
                    testament: testament,
                    chapters: chapters,
                    abbreviation: currentBookSname
                ))
                chapters = []
            }
        default:
            break
        }
        infoBuffer = ""
    }

    private func bookNameForNumber(_ number: Int) -> String {
        let allBooks = BibleBookNames.all
        if number >= 1 && number <= allBooks.count { return allBooks[number - 1] }
        return "Book \(number)"
    }
}
