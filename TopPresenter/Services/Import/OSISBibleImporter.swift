//
//  OSISBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for OSIS XML format Bibles.
/// OSIS (Open Scripture Information Standard) is a widely used XML schema for Bible texts.
/// Maps the full OSIS feature set into the GOAT model: `<title>`→headings,
/// `<note type=crossReference>`→cross-references, other `<note>`→footnotes,
/// `<q who="Jesus">`→words-of-Christ runs, `<w lemma="strong:…" morph="…">`→Strong's +
/// morphology, `<transChange>`→added-words runs, `<divineName>`→divine-name runs, and
/// the header `<work>` (title/identifier/language/rights)→module metadata.
nonisolated final class OSISBibleImporter: BibleImporter {
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

        var result = BibleImportResult(
            moduleName: delegate.workTitle.isEmpty ? fileURL.deletingPathExtension().lastPathComponent : delegate.workTitle,
            abbreviation: delegate.workAbbreviation,
            language: delegate.language.isEmpty ? "en" : delegate.language,
            description: delegate.workDescription,
            books: delegate.books
        )
        result.copyright = delegate.workRights
        result.hasWordsOfChrist = delegate.hasAnyWoc
        result.hasStrongs = delegate.hasAnyStrong
        return result
    }
}

// MARK: - OSIS XML Parser Delegate
private final class OSISParserDelegate: NSObject, XMLParserDelegate {
    var workTitle = ""
    var workAbbreviation = ""
    var workDescription = ""
    var workRights = ""
    var language = ""
    var hasAnyWoc = false
    var hasAnyStrong = false
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

    // Section headings
    private var isInSectionTitle = false
    private var sectionTitleText = ""
    private var pendingHeadings: [BibleHeading] = []

    // Rich runs — red-letter (woc), added words, divine name, Strong's + morph.
    private struct RunStyle { var kind: String; var strong: String?; var morph: String? }
    private var styleStack: [RunStyle] = []        // transChange / divineName / w
    private var styledElements: [String] = []      // element names matching styleStack frames
    private var wocDepth = 0                        // `<q who="Jesus">` overlay
    private var qStack: [Bool] = []                 // true = container q that bumped wocDepth
    private var runBuf = ""
    private var currentRuns: [VerseRun] = []
    private var hasWoc = false

    // Footnotes + cross-references
    private var isInNote = false
    private var noteDepth = 0
    private var noteIsCrossRef = false
    private var noteText = ""
    private var inReference = false
    private var referenceText = ""
    private var referenceOsisRef = ""
    private var crossRefTargets: [String] = []
    private var footnotes: [BibleFootnote] = []
    private var crossRefs: [BibleCrossRef] = []

    private var bookCounter = 0

    private func currentStyle() -> RunStyle {
        var kind = styleStack.last?.kind ?? "plain"
        let strong = styleStack.last?.strong
        let morph = styleStack.last?.morph
        if wocDepth > 0 && kind == "plain" { kind = "woc" }
        return RunStyle(kind: kind, strong: strong, morph: morph)
    }

    /// Flush the active run buffer into `currentRuns` with the current style.
    private func flushRun() {
        let t = runBuf.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        if !t.trimmingCharacters(in: .whitespaces).isEmpty {
            let st = currentStyle()
            currentRuns.append(VerseRun(text: t, kind: st.kind, strong: st.strong, morph: st.morph))
            if st.kind == "woc" { hasWoc = true; hasAnyWoc = true }
            if st.strong != nil { hasAnyStrong = true }
        }
        runBuf = ""
    }

    /// Extract a Strong's number from an OSIS `lemma` attribute
    /// (`"strong:G3056"`, `"strong:H0430 strong:H0853"`, or bare `"G3056"`).
    private func parseStrong(_ lemma: String?) -> String? {
        guard let lemma = lemma, !lemma.isEmpty else { return nil }
        for token in lemma.split(separator: " ") {
            let s = String(token)
            if s.lowercased().hasPrefix("strong:") {
                let v = String(s.dropFirst(7))
                if !v.isEmpty { return v.uppercased() }
            }
            if let f = s.uppercased().first, (f == "G" || f == "H"),
               s.dropFirst().allSatisfy({ $0.isNumber }), s.count > 1 {
                return s.uppercased()
            }
        }
        return nil
    }

    /// Extract a morphology code from an OSIS `morph` attribute
    /// (`"strongMorph:TH8804"`, `"robinson:N-NSM"`, or bare `"N-NSM"`).
    private func parseMorph(_ morph: String?) -> String? {
        guard let morph = morph, !morph.isEmpty else { return nil }
        let first = morph.split(separator: " ").first.map(String.init) ?? morph
        if let colon = first.firstIndex(of: ":") {
            let v = String(first[first.index(after: colon)...])
            return v.isEmpty ? nil : v
        }
        return first
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
            if let osisWork = attributeDict["osisWork"], workAbbreviation.isEmpty {
                workAbbreviation = osisWork
            }

        case "title":
            if isInHeader {
                isInTitle = true
                currentText = ""
            } else if !isInNote {
                isInSectionTitle = true
                sectionTitleText = ""
            }

        case "header":
            isInHeader = true

        case "language":
            currentText = ""

        case "description", "rights", "identifier":
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
                let parts = osisID.split(separator: ".")
                if parts.count >= 3, let num = Int(parts.last ?? "0") {
                    currentVerseNumber = num
                }
                startVerse()
            } else if let sID = attributeDict["sID"] {
                let parts = sID.split(separator: ".")
                if parts.count >= 3, let num = Int(parts.last ?? "0") {
                    currentVerseNumber = num
                }
                startVerse()
            } else if attributeDict["eID"] != nil {
                finishCurrentVerse()
            }

        case "q":
            let isJesus = (attributeDict["who"]?.lowercased().contains("jesus")) ?? false
            if isJesus {
                if attributeDict["sID"] != nil {
                    if isInVerse { flushRun() }
                    wocDepth += 1; hasWoc = true; hasAnyWoc = true
                    qStack.append(false)   // milestone start — its own end must not pop
                } else if attributeDict["eID"] != nil {
                    if isInVerse { flushRun() }
                    wocDepth = max(0, wocDepth - 1)
                    qStack.append(false)   // milestone end
                } else {
                    if isInVerse { flushRun() }
                    wocDepth += 1; hasWoc = true; hasAnyWoc = true
                    qStack.append(true)    // container — matching end pops
                }
            } else {
                qStack.append(false)
            }

        case "transChange":
            if isInVerse { pushStyle(RunStyle(kind: "add", strong: nil, morph: nil), for: elementName) }

        case "divineName":
            if isInVerse { pushStyle(RunStyle(kind: "divineName", strong: nil, morph: nil), for: elementName) }

        case "w":
            if isInVerse {
                let strong = parseStrong(attributeDict["lemma"])
                let morph = parseMorph(attributeDict["morph"])
                let parent = currentStyle()
                pushStyle(RunStyle(kind: parent.kind, strong: strong, morph: morph), for: elementName)
            }

        case "note":
            if isInVerse {
                if !isInNote { flushRun() }
                noteDepth += 1
                isInNote = true
                if noteDepth == 1 {
                    let type = (attributeDict["type"] ?? "").lowercased()
                    noteIsCrossRef = type.contains("cross")
                    noteText = ""
                    crossRefTargets = []
                }
            }

        case "reference":
            if isInNote {
                inReference = true
                referenceText = ""
                referenceOsisRef = attributeDict["osisRef"] ?? ""
            }

        default:
            break
        }
    }

    private func pushStyle(_ style: RunStyle, for elementName: String) {
        flushRun()
        styleStack.append(style)
        styledElements.append(elementName)
    }

    private func startVerse() {
        isInVerse = true
        currentText = ""
        runBuf = ""
        currentRuns = []
        hasWoc = false
        wocDepth = 0
        styleStack = []
        styledElements = []
        qStack = []
        footnotes = []
        crossRefs = []
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInNote {
            if inReference { referenceText += string }
            else { noteText += string }
            return
        }
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
        } else if (currentElement == "description" || currentElement == "rights" || currentElement == "identifier") && isInHeader {
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
                if workTitle.isEmpty {
                    workTitle = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                isInTitle = false
            } else if isInSectionTitle {
                let t = sectionTitleText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    pendingHeadings.append(BibleHeading(beforeVerse: currentVerseNumber + 1, level: 1, text: t))
                }
                isInSectionTitle = false
                sectionTitleText = ""
            }

        case "language":
            if isInHeader && language.isEmpty {
                language = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentText = ""

        case "description":
            if isInHeader {
                workDescription = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentText = ""

        case "rights":
            if isInHeader && workRights.isEmpty {
                workRights = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            currentText = ""

        case "identifier":
            if isInHeader && workAbbreviation.isEmpty {
                let id = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !id.isEmpty { workAbbreviation = id }
            }
            currentText = ""

        case "div":
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

        case "q":
            if let wasContainer = qStack.popLast(), wasContainer {
                if isInVerse { flushRun() }
                wocDepth = max(0, wocDepth - 1)
            }

        case "transChange", "divineName", "w":
            if styledElements.last == elementName {
                flushRun()
                styleStack.removeLast()
                styledElements.removeLast()
            }

        case "reference":
            if inReference {
                let target = referenceOsisRef.isEmpty
                    ? referenceText.trimmingCharacters(in: .whitespacesAndNewlines)
                    : referenceOsisRef
                if !target.isEmpty { crossRefTargets.append(target) }
                inReference = false
            }

        case "note":
            if isInNote {
                noteDepth -= 1
                if noteDepth <= 0 {
                    if noteIsCrossRef {
                        if !crossRefTargets.isEmpty {
                            crossRefs.append(BibleCrossRef(targets: crossRefTargets))
                        }
                    } else {
                        let t = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { footnotes.append(BibleFootnote(text: t)) }
                    }
                    isInNote = false
                    noteDepth = 0
                    noteIsCrossRef = false
                    noteText = ""
                    crossRefTargets = []
                }
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
                let meaningful = currentRuns.contains { $0.kind != "plain" || $0.strong != nil }
                let runs = meaningful
                    ? currentRuns.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
                    : nil
                verses.append(BibleImportVerse(
                    verseNumber: currentVerseNumber,
                    text: cleanText,
                    runs: runs,
                    footnotes: footnotes.isEmpty ? nil : footnotes,
                    crossReferences: crossRefs.isEmpty ? nil : crossRefs,
                    hasWordsOfChrist: hasWoc
                ))
            }
            isInVerse = false
            currentText = ""
            currentRuns = []
            runBuf = ""
            hasWoc = false
            wocDepth = 0
            styleStack = []
            styledElements = []
            qStack = []
            footnotes = []
            crossRefs = []
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
