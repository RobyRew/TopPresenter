//
//  ChordProImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/06/2026.
//

import Foundation

/// Importer for ChordPro / Chord chart files (.cho, .crd, .chordpro, .chopro).
/// Parses `{directive: value}` metadata, `{start_of_*}` section blocks, and inline
/// `[Chord]` markers (kept as `SongChord` positions so the GOAT format preserves chords).
final class ChordProImporter: SongImporter {
    let format: SupportedSongFormat = .chordPro

    func parse(fileURL: URL) async throws -> SongImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SongImportError.fileNotFound
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw SongImportError.emptyFile }
        guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw SongImportError.parsingFailed("Unreadable text encoding")
        }
        return Self.parse(content: content, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
    }

    static func parse(content: String, fallbackTitle: String) -> SongImportResult {
        var title = ""
        var subtitle = ""
        var artist = ""
        var composer = ""
        var lyricist = ""
        var key = ""
        var tempo = ""
        var ccli = ""
        var copyright = ""
        var capo = 0
        var themes: [String] = []

        var sections: [SongImportSection] = []
        var curLines: [SongLine] = []
        var curType = "verse"
        var curLabel = ""
        var inExplicitSection = false
        var counters: [String: Int] = [:]

        func nextKey(_ type: String) -> (key: String, label: String, order: Int) {
            let n = (counters[type] ?? 0) + 1
            counters[type] = n
            let order = sections.count
            switch type {
            case "chorus": return (n == 1 ? "c" : "c\(n)", n == 1 ? "Chorus" : "Chorus \(n)", order)
            case "bridge": return ("b\(n)", n == 1 ? "Bridge" : "Bridge \(n)", order)
            case "prechorus": return ("p\(n)", "Pre-Chorus", order)
            case "intro": return ("i", "Intro", order)
            case "ending": return ("e", "Ending", order)
            case "tag": return ("t\(n)", "Tag", order)
            case "interlude": return ("int\(n)", "Interlude", order)
            default: return ("v\(n)", "Verse \(n)", order)
            }
        }

        func flush() {
            guard !curLines.isEmpty else { return }
            let meta = nextKey(curType)
            let label = curLabel.isEmpty ? meta.label : curLabel
            sections.append(SongImportSection(sectionKey: meta.key, type: curType, label: label, order: meta.order, lines: curLines))
            curLines = []
            curLabel = ""
        }

        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let dir = directive(trimmed) {
                switch dir.key {
                case "title", "t": title = dir.value
                case "subtitle", "st": subtitle = dir.value
                case "artist": artist = dir.value
                case "composer": composer = dir.value
                case "lyricist", "author": lyricist = dir.value
                case "key": key = dir.value
                case "tempo", "bpm": tempo = dir.value
                case "ccli": ccli = dir.value
                case "copyright": copyright = dir.value
                case "capo": capo = Int(dir.value) ?? 0
                case "tag": if !dir.value.isEmpty { themes.append(dir.value) }
                case "comment", "c", "highlight": break  // not lyrics
                case "start_of_verse", "sov":
                    flush(); curType = "verse"; curLabel = dir.value; inExplicitSection = true
                case "start_of_chorus", "soc":
                    flush(); curType = "chorus"; curLabel = dir.value; inExplicitSection = true
                case "start_of_bridge", "sob":
                    flush(); curType = "bridge"; curLabel = dir.value; inExplicitSection = true
                case "start_of_part", "sop":
                    flush(); curType = "other"; curLabel = dir.value; inExplicitSection = true
                case "end_of_verse", "eov", "end_of_chorus", "eoc", "end_of_bridge", "eob", "end_of_part", "eop":
                    flush(); curType = "verse"; inExplicitSection = false
                default:
                    break
                }
                continue
            }

            if trimmed.isEmpty {
                // Blank line ends an implicit stanza (when no explicit section markers).
                if !inExplicitSection { flush(); curType = "verse" }
                continue
            }

            let parsed = extractChords(line)
            curLines.append(SongLine(text: parsed.text, chords: parsed.chords))
        }
        flush()

        let resolvedTitle = !title.isEmpty ? title : (fallbackTitle.isEmpty ? "Untitled" : fallbackTitle)
        let author = [lyricist, composer, artist].first(where: { !$0.isEmpty }) ?? ""
        var titles: [String] = []
        if !subtitle.isEmpty { titles.append(subtitle) }

        let version = SongImportVersion(
            name: "Original", key: key, capo: capo, tempo: tempo, source: "ChordPro", sections: sections
        )

        // If parsing produced nothing usable, keep a single empty verse so the song still imports.
        let usableVersion = sections.isEmpty
            ? SongImportVersion(name: "Original", sections: [SongImportSection(sectionKey: "v1", type: "verse", label: "Verse 1", order: 0, lines: [])])
            : version

        return SongImportResult(
            title: resolvedTitle,
            author: author,
            copyright: copyright,
            ccliNumber: ccli,
            key: key,
            tempo: tempo,
            songNumber: "",
            tags: themes.joined(separator: ", "),
            verses: [],
            titles: titles,
            themes: themes,
            authorWords: lyricist,
            authorMusic: composer,
            versions: [usableVersion]
        )
    }

    // MARK: - Helpers

    /// Parse a `{key: value}` or `{key}` directive.
    private static func directive(_ line: String) -> (key: String, value: String)? {
        guard line.hasPrefix("{"), line.hasSuffix("}") else { return nil }
        let inner = String(line.dropFirst().dropLast())
        if let colon = inner.firstIndex(of: ":") {
            let k = String(inner[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let v = String(inner[inner.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            return (k, v)
        }
        return (inner.trimmingCharacters(in: .whitespaces).lowercased(), "")
    }

    /// Strip inline `[Chord]` markers, recording each chord's character offset in the plain text.
    private static func extractChords(_ line: String) -> (text: String, chords: [SongChord]) {
        var text = ""
        var chords: [SongChord] = []
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if ch == "[" , let close = line[i...].firstIndex(of: "]") {
                let sym = String(line[line.index(after: i)..<close])
                if !sym.isEmpty { chords.append(SongChord(sym: sym, pos: text.count)) }
                i = line.index(after: close)
                continue
            }
            text.append(ch)
            i = line.index(after: i)
        }
        return (text, chords)
    }
}
