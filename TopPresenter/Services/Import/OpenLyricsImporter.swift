//
//  OpenLyricsImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for OpenLyrics XML format songs.
/// OpenLyrics is an open standard for exchanging song lyrics between applications.
/// Specification: http://openlyrics.org
final class OpenLyricsImporter: SongImporter {
    let format: SupportedSongFormat = .openLyricsXML

    func parse(fileURL: URL) async throws -> SongImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SongImportError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw SongImportError.emptyFile }

        let delegate = OpenLyricsParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false

        guard parser.parse() else {
            let errorDesc = parser.parserError?.localizedDescription ?? "Unknown error"
            throw SongImportError.parsingFailed(errorDesc)
        }

        let title = delegate.titles.first ?? fileURL.deletingPathExtension().lastPathComponent

        return SongImportResult(
            title: title,
            author: delegate.authors.joined(separator: ", "),
            copyright: delegate.copyright,
            ccliNumber: delegate.ccliNumber,
            key: delegate.key,
            tempo: delegate.tempo,
            songNumber: delegate.songNumber,
            tags: delegate.themes.joined(separator: ", "),
            verses: delegate.verses
        )
    }
}

// MARK: - OpenLyrics XML Parser Delegate
private final class OpenLyricsParserDelegate: NSObject, XMLParserDelegate {
    var titles: [String] = []
    var authors: [String] = []
    var copyright = ""
    var ccliNumber = ""
    var key = ""
    var tempo = ""
    var songNumber = ""
    var themes: [String] = []
    var verses: [SongImportVerse] = []

    private var currentElement = ""
    private var currentText = ""
    private var elementStack: [String] = []

    // Verse parsing state
    private var currentVerseName = ""
    private var currentVerseLines: [String] = []
    private var isInVerse = false
    private var isInLines = false
    private var verseOrder = 0

    // Properties parsing
    private var isInProperties = false
    private var isInTitles = false
    private var isInAuthors = false
    private var isInThemes = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "properties":
            isInProperties = true

        case "titles":
            isInTitles = true

        case "authors":
            isInAuthors = true

        case "themes":
            isInThemes = true

        case "title":
            currentText = ""

        case "author":
            currentText = ""

        case "theme":
            currentText = ""

        case "song":
            // Root element
            break

        case "verse":
            isInVerse = true
            currentVerseName = attributeDict["name"] ?? "v\(verseOrder + 1)"
            currentVerseLines = []

        case "lines":
            isInLines = true
            currentText = ""

        case "br":
            if isInLines {
                currentText += "\n"
            }

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
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "properties":
            isInProperties = false

        case "titles":
            isInTitles = false

        case "authors":
            isInAuthors = false

        case "themes":
            isInThemes = false

        case "title":
            if isInTitles && !trimmed.isEmpty {
                titles.append(trimmed)
            }

        case "author":
            if isInAuthors && !trimmed.isEmpty {
                authors.append(trimmed)
            }

        case "theme":
            if isInThemes && !trimmed.isEmpty {
                themes.append(trimmed)
            }

        case "copyright":
            copyright = trimmed

        case "ccliNo":
            ccliNumber = trimmed

        case "key":
            key = trimmed

        case "tempo":
            tempo = trimmed

        case "songNumber", "number":
            songNumber = trimmed

        case "lines":
            if isInLines {
                let lineText = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !lineText.isEmpty {
                    currentVerseLines.append(lineText)
                }
                isInLines = false
            }

        case "verse":
            if isInVerse {
                let fullText = currentVerseLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !fullText.isEmpty {
                    let (label, type) = classifyVerseName(currentVerseName)
                    verses.append(SongImportVerse(
                        label: label,
                        verseType: type,
                        text: fullText,
                        order: verseOrder
                    ))
                    verseOrder += 1
                }
                isInVerse = false
            }

        default:
            break
        }

        if !elementStack.isEmpty {
            elementStack.removeLast()
        }
        currentElement = elementStack.last ?? ""
    }

    private func classifyVerseName(_ name: String) -> (label: String, type: String) {
        let lower = name.lowercased()

        if lower.hasPrefix("v") {
            let num = name.filter { $0.isNumber }
            return ("Verse \(num.isEmpty ? "1" : num)", "verse")
        } else if lower.hasPrefix("c") {
            let num = name.filter { $0.isNumber }
            return ("Chorus\(num.isEmpty ? "" : " \(num)")", "chorus")
        } else if lower.hasPrefix("b") {
            let num = name.filter { $0.isNumber }
            return ("Bridge\(num.isEmpty ? "" : " \(num)")", "bridge")
        } else if lower.hasPrefix("p") {
            return ("Pre-Chorus", "pre-chorus")
        } else if lower.hasPrefix("e") {
            return ("Ending", "ending")
        } else {
            return (name, "other")
        }
    }
}
