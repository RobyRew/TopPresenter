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
///
/// Rich mapping: multiple `<title>`s → aliases, `<theme>`s → themes, inline `<chord>` →
/// SongChord positions, and same-named verses in different `lang`s → bilingual translations.
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
        let aliases = Array(delegate.titles.dropFirst())

        // Build rich sections, merging translation languages into each line.
        var sections: [SongImportSection] = []
        var nameToKey: [String: String] = [:]   // original verse name → section key (for verseOrder)
        for (idx, group) in delegate.orderedVerses.enumerated() {
            let (key, label, type) = classify(group.name, index: idx)
            nameToKey[group.name.lowercased()] = key
            let primary = group.primaryLang
            var lines = group.lines[primary] ?? []
            for (lang, transLines) in group.lines where lang != primary {
                for (i, tline) in transLines.enumerated() where i < lines.count {
                    if !tline.text.isEmpty { lines[i].translations[lang] = tline.text }
                }
            }
            guard !lines.isEmpty else { continue }
            sections.append(SongImportSection(sectionKey: key, type: type, label: label, order: idx, lines: lines))
        }

        // <verseOrder> → arrangement of section keys.
        let arrangement = delegate.verseOrder
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map { nameToKey[$0.lowercased()] ?? String($0) }

        let songbookNumber = delegate.songbookEntry
        let notes = delegate.comments.joined(separator: "\n")

        let version = SongImportVersion(
            name: "Original",
            authorWords: delegate.authorWords,
            authorMusic: delegate.authorMusic,
            authorTranslation: delegate.authorTranslation,
            songbookNumber: songbookNumber,
            songbookName: delegate.songbookName,
            notes: notes,
            language: delegate.songLang,
            key: delegate.key,
            tempo: delegate.tempo,
            arrangement: arrangement,
            sections: sections
        )

        let flatVerses = sections.enumerated().map { idx, sec in
            SongImportVerse(label: sec.label, verseType: sec.type,
                            text: sec.lines.map { $0.text }.joined(separator: "\n"), order: idx)
        }

        var songbook: SongImportSongbook?
        if !delegate.songbookName.isEmpty {
            songbook = SongImportSongbook(name: delegate.songbookName, number: songbookNumber)
        }

        return SongImportResult(
            title: title,
            author: delegate.authors.joined(separator: ", "),
            copyright: delegate.copyright,
            ccliNumber: delegate.ccliNumber,
            key: delegate.key,
            tempo: delegate.tempo,
            songNumber: delegate.songNumber.isEmpty ? songbookNumber : delegate.songNumber,
            tags: delegate.themes.joined(separator: ", "),
            verses: flatVerses,
            titles: aliases,
            language: delegate.songLang,
            themes: delegate.themes,
            songbook: songbook,
            authorWords: delegate.authorWords,
            authorMusic: delegate.authorMusic,
            authorTranslation: delegate.authorTranslation,
            notes: notes,
            versions: [version]
        )
    }

    private func classify(_ name: String, index: Int) -> (key: String, label: String, type: String) {
        let lower = name.lowercased()
        let num = name.filter { $0.isNumber }
        if lower.hasPrefix("c") {
            return (num.isEmpty ? "c" : "c\(num)", "Chorus\(num.isEmpty ? "" : " \(num)")", "chorus")
        } else if lower.hasPrefix("b") {
            return ("b\(num.isEmpty ? "1" : num)", "Bridge\(num.isEmpty ? "" : " \(num)")", "bridge")
        } else if lower.hasPrefix("p") {
            return ("p\(num.isEmpty ? "1" : num)", "Pre-Chorus", "prechorus")
        } else if lower.hasPrefix("e") {
            return ("e", "Ending", "ending")
        } else if lower.hasPrefix("v") {
            return ("v\(num.isEmpty ? "1" : num)", "Verse \(num.isEmpty ? "1" : num)", "verse")
        } else {
            return (name.isEmpty ? "s\(index)" : name, name.isEmpty ? "Verse \(index + 1)" : name, "other")
        }
    }
}

// MARK: - OpenLyrics XML Parser Delegate

/// A verse keyed by name, holding lines per language.
private struct VerseGroup {
    var name: String
    var primaryLang: String = ""
    var lines: [String: [SongLine]] = [:]   // lang -> ordered lines
}

private final class OpenLyricsParserDelegate: NSObject, XMLParserDelegate {
    var titles: [String] = []
    var authors: [String] = []
    var authorWords = ""
    var authorMusic = ""
    var authorTranslation = ""
    var copyright = ""
    var ccliNumber = ""
    var key = ""
    var tempo = ""
    var songNumber = ""
    var themes: [String] = []
    var songLang = ""
    var verseOrder = ""
    var songbookName = ""
    var songbookEntry = ""
    var comments: [String] = []

    private(set) var orderedVerses: [VerseGroup] = []
    private var verseIndexByName: [String: Int] = [:]

    private var currentText = ""
    private var elementStack: [String] = []
    private var currentAuthorType = ""

    // Verse parsing state
    private var currentVerseName = ""
    private var currentVerseLang = ""
    private var currentLines: [SongLine] = []
    private var currentLineText = ""
    private var currentLineChords: [SongChord] = []
    private var isInLines = false

    private var isInTitles = false
    private var isInAuthors = false
    private var isInThemes = false
    private var isInComments = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)

        switch elementName {
        case "song":
            if songLang.isEmpty { songLang = attributeDict["lang"] ?? "" }
        case "titles": isInTitles = true
        case "authors": isInAuthors = true
        case "themes": isInThemes = true
        case "comments": isInComments = true
        case "author":
            currentAuthorType = (attributeDict["type"] ?? "").lowercased()
            currentText = ""
        case "songbook":
            if let n = attributeDict["name"], !n.isEmpty { songbookName = n }
            if let e = attributeDict["entry"], !e.isEmpty { songbookEntry = e }
        case "title", "theme", "comment", "copyright", "ccliNo", "key", "tempo", "verseOrder", "songNumber", "number":
            currentText = ""
        case "verse":
            currentVerseName = attributeDict["name"] ?? "v\(orderedVerses.count + 1)"
            currentVerseLang = attributeDict["lang"] ?? ""
        case "lines":
            isInLines = true
            currentLines = []
            currentLineText = ""
            currentLineChords = []
        case "br":
            if isInLines { finalizeLine() }
        case "chord":
            if isInLines {
                let sym = attributeDict["name"]
                    ?? [attributeDict["root"], attributeDict["structure"]].compactMap { $0 }.joined()
                if !sym.isEmpty {
                    currentLineChords.append(SongChord(sym: sym, pos: currentLineText.count))
                }
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
        if isInLines { currentLineText += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "titles": isInTitles = false
        case "authors": isInAuthors = false
        case "themes": isInThemes = false
        case "comments": isInComments = false
        case "title": if isInTitles && !trimmed.isEmpty { titles.append(trimmed) }
        case "author":
            if isInAuthors && !trimmed.isEmpty {
                authors.append(trimmed)
                switch currentAuthorType {
                case "words", "lyrics": if authorWords.isEmpty { authorWords = trimmed }
                case "music": if authorMusic.isEmpty { authorMusic = trimmed }
                case "translation": if authorTranslation.isEmpty { authorTranslation = trimmed }
                default: break
                }
            }
            currentAuthorType = ""
        case "theme": if isInThemes && !trimmed.isEmpty { themes.append(trimmed) }
        case "comment": if isInComments && !trimmed.isEmpty { comments.append(trimmed) }
        case "copyright": copyright = trimmed
        case "ccliNo": ccliNumber = trimmed
        case "key": key = trimmed
        case "tempo": tempo = trimmed
        case "verseOrder": verseOrder = trimmed
        case "songNumber", "number": songNumber = trimmed
        case "lines":
            if isInLines {
                finalizeLine()
                isInLines = false
                storeCurrentVerseLines()
            }
        default:
            break
        }

        if !elementStack.isEmpty { elementStack.removeLast() }
    }

    private func finalizeLine() {
        let text = currentLineText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty || !currentLineChords.isEmpty {
            currentLines.append(SongLine(text: text, chords: currentLineChords))
        }
        currentLineText = ""
        currentLineChords = []
    }

    private func storeCurrentVerseLines() {
        guard !currentLines.isEmpty else { return }
        let lang = currentVerseLang
        if let existing = verseIndexByName[currentVerseName] {
            if orderedVerses[existing].primaryLang.isEmpty { orderedVerses[existing].primaryLang = lang }
            orderedVerses[existing].lines[lang] = currentLines
        } else {
            var group = VerseGroup(name: currentVerseName, primaryLang: lang)
            group.lines[lang] = currentLines
            verseIndexByName[currentVerseName] = orderedVerses.count
            orderedVerses.append(group)
        }
        currentLines = []
    }
}
