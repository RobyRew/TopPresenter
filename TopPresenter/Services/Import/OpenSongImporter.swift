//
//  OpenSongImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for OpenSong XML format songs.
/// OpenSong uses one file per song, typically without a file extension.
///
/// Rich mapping: `.`-prefixed chord lines become positioned `SongChord`s on the following
/// lyric line, and the `<presentation>` order becomes the version `arrangement`.
final class OpenSongImporter: SongImporter {
    let format: SupportedSongFormat = .openSongXML

    func parse(fileURL: URL) async throws -> SongImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SongImportError.fileNotFound
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw SongImportError.emptyFile }

        let delegate = OpenSongParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let errorDesc = parser.parserError?.localizedDescription ?? "Unknown error"
            throw SongImportError.parsingFailed(errorDesc)
        }

        let title = delegate.title.isEmpty ? fileURL.lastPathComponent : delegate.title
        let sections = parseSections(delegate.lyrics)
        let arrangement = mapPresentation(delegate.presentation, sections: sections)

        let aliases = delegate.aka
            .components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let notes = [delegate.user1, delegate.user2, delegate.user3]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        let version = SongImportVersion(
            name: "Original",
            titles: aliases,
            notes: notes,
            key: delegate.key,
            capo: Int(delegate.capo) ?? 0,
            tempo: delegate.tempo,
            timeSignature: delegate.timeSignature,
            arrangement: arrangement,
            sections: sections
        )

        // Flat verses follow the arrangement when present (legacy presentation order).
        let orderedSections: [SongImportSection]
        if arrangement.isEmpty {
            orderedSections = sections
        } else {
            let byKey = Dictionary(sections.map { ($0.sectionKey, $0) }, uniquingKeysWith: { a, _ in a })
            orderedSections = arrangement.compactMap { byKey[$0] }
        }
        let flatVerses = orderedSections.enumerated().map { idx, sec in
            SongImportVerse(label: sec.label, verseType: sec.type,
                            text: sec.lines.map { $0.text }.joined(separator: "\n"), order: idx)
        }

        let themes = delegate.theme
            .components(separatedBy: CharacterSet(charactersIn: ";,/"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return SongImportResult(
            title: title,
            author: delegate.author,
            copyright: delegate.copyright,
            ccliNumber: delegate.ccli,
            key: delegate.key,
            tempo: delegate.tempo,
            songNumber: delegate.hymn_number,
            tags: delegate.theme,
            verses: flatVerses,
            titles: aliases,
            themes: themes,
            notes: notes,
            versions: [version]
        )
    }

    /// Parse OpenSong lyrics into rich sections (chords kept as positions).
    private func parseSections(_ lyrics: String) -> [SongImportSection] {
        let rawLines = lyrics.components(separatedBy: .newlines)
        var sections: [SongImportSection] = []
        var counters: [String: Int] = [:]

        var curType = "verse"
        var curLabel = "Verse 1"
        var curKey = "v1"
        var curLines: [SongLine] = []
        var pendingChords: [SongChord] = []
        var started = false

        func flush() {
            guard !curLines.isEmpty else { return }
            sections.append(SongImportSection(sectionKey: curKey, type: curType, label: curLabel, order: sections.count, lines: curLines))
            curLines = []
        }

        for line in rawLines {
            if line.hasPrefix("[") {
                flush()
                let tag = line.replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let classified = classifySection(tag, counters: &counters)
                curType = classified.type
                curLabel = classified.label
                curKey = classified.key
                pendingChords = []
                started = true
            } else if line.hasPrefix(".") {
                pendingChords = parseChordLine(line)
            } else if line.hasPrefix(";") {
                continue  // comment
            } else if line.hasPrefix(" ") {
                let text = String(line.dropFirst())
                curLines.append(makeLine(text: text, chords: pendingChords))
                pendingChords = []
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                curLines.append(makeLine(text: line, chords: pendingChords))
                pendingChords = []
            }
        }
        flush()

        // Some files have no section markers at all — keep one verse.
        if sections.isEmpty && started == false && !curLines.isEmpty {
            sections.append(SongImportSection(sectionKey: "v1", type: "verse", label: "Verse 1", order: 0, lines: curLines))
        }
        return sections
    }

    private func makeLine(text: String, chords: [SongChord]) -> SongLine {
        guard !chords.isEmpty else { return SongLine(text: text) }
        let clamped = chords.map { SongChord(sym: $0.sym, pos: min(max($0.pos, 0), text.count)) }
        return SongLine(text: text, chords: clamped)
    }

    /// Parse a `.`-prefixed chord line into chords at column positions (column 0 == after the dot).
    private func parseChordLine(_ line: String) -> [SongChord] {
        let chars = Array(line)
        var chords: [SongChord] = []
        var i = 1  // skip leading "."
        while i < chars.count {
            if chars[i] == " " { i += 1; continue }
            var sym = ""
            let start = i
            while i < chars.count, chars[i] != " " {
                sym.append(chars[i]); i += 1
            }
            if !sym.isEmpty { chords.append(SongChord(sym: sym, pos: max(start - 1, 0))) }
        }
        return chords
    }

    private func classifySection(_ tag: String, counters: inout [String: Int]) -> (key: String, label: String, type: String) {
        let upper = tag.uppercased()
        let num = tag.filter { $0.isNumber }

        func nextKey(_ prefix: String) -> Int {
            let n = (counters[prefix] ?? 0) + 1
            counters[prefix] = n
            return n
        }

        if upper.hasPrefix("V") {
            let n = num.isEmpty ? "\(nextKey("v"))" : num
            return ("v\(n)", "Verse \(n)", "verse")
        } else if upper.hasPrefix("C") {
            let n = num.isEmpty ? nextKey("c") : (Int(num) ?? 1)
            return (n == 1 ? "c" : "c\(n)", n == 1 ? "Chorus" : "Chorus \(n)", "chorus")
        } else if upper.hasPrefix("B") {
            let n = num.isEmpty ? nextKey("b") : (Int(num) ?? 1)
            return ("b\(n)", n == 1 ? "Bridge" : "Bridge \(n)", "bridge")
        } else if upper.hasPrefix("P") {
            return ("p\(nextKey("p"))", "Pre-Chorus", "prechorus")
        } else if upper.hasPrefix("T") {
            return ("t\(nextKey("t"))", "Tag", "tag")
        } else if upper.hasPrefix("E") {
            return ("e", "Ending", "ending")
        } else {
            return (tag.isEmpty ? "s\(counters.count)" : tag, tag, "other")
        }
    }

    /// Map an OpenSong `<presentation>` string (e.g. "V1 C V2 C B") to section keys.
    private func mapPresentation(_ presentation: String, sections: [SongImportSection]) -> [String] {
        let tokens = presentation.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        var keys: [String] = []
        for token in tokens {
            let upper = token.uppercased()
            let num = token.filter { $0.isNumber }
            let match = sections.first { sec in
                let label = sec.label.uppercased()
                if upper.hasPrefix("V") { return sec.type == "verse" && (num.isEmpty || label.contains(num)) }
                if upper.hasPrefix("C") { return sec.type == "chorus" }
                if upper.hasPrefix("B") { return sec.type == "bridge" }
                if upper.hasPrefix("P") { return sec.type == "prechorus" }
                if upper.hasPrefix("T") { return sec.type == "tag" }
                if upper.hasPrefix("E") { return sec.type == "ending" }
                return false
            }
            if let match { keys.append(match.sectionKey) }
        }
        return keys
    }
}

// MARK: - OpenSong XML Parser Delegate
private final class OpenSongParserDelegate: NSObject, XMLParserDelegate {
    var title = ""
    var author = ""
    var copyright = ""
    var ccli = ""
    var key = ""
    var tempo = ""
    var hymn_number = ""
    var theme = ""
    var lyrics = ""
    var presentation = ""
    var capo = ""
    var aka = ""
    var timeSignature = ""
    var user1 = ""
    var user2 = ""
    var user3 = ""

    private var currentElement = ""
    private var currentText = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""
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
        case "title": title = trimmed
        case "author": author = trimmed
        case "copyright": copyright = trimmed
        case "ccli": ccli = trimmed
        case "key": key = trimmed
        case "tempo": tempo = trimmed
        case "hymn_number": hymn_number = trimmed
        case "theme": theme = trimmed
        case "lyrics": lyrics = currentText  // Don't trim - whitespace matters
        case "presentation": presentation = trimmed
        case "capo": capo = trimmed
        case "aka": aka = trimmed
        case "time_sig", "timesig": timeSignature = trimmed
        case "user1": user1 = trimmed
        case "user2": user2 = trimmed
        case "user3": user3 = trimmed
        default: break
        }

        currentText = ""
    }
}
