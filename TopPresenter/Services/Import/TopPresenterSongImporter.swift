//
//  TopPresenterSongImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/06/2026.
//
//  ─────────────────────────────────────────────────────────────────────────────
//  TopPresenter Song JSON — the "GOAT" song format (authoritative spec)
//  ─────────────────────────────────────────────────────────────────────────────
//  A SINGLE-SONG document: one JSON file = one song (carrying all its versions).
//  The ResurseCrestine userscript emits one file per song; TopPresenter imports AND
//  exports this exact format. Bulk = a folder of these files. schemaVersion "2.0.0".
//
//  {
//    "schemaVersion": "2.0.0",
//    "format": "TopPresenter Song",
//    "exportInfo": { "source", "exportDate", "exporterVersion" },
//    "song": {
//      "title": "...",
//      "titles": ["alias", ...],
//      "language": "ro",
//      "themes": ["worship", ...],
//      "style": "imn|coral|contemporan|...",
//      "songbook": { "name", "publisher", "language", "year", "number" } | null,
//      "authorWords", "authorMusic", "authorTranslation", "copyright", "ccliNumber", "notes",
//      "media": [ { "role", "kind", "filename", "bookmark"? } ],
//      "versions": [{
//        "name", "language", "key", "capo", "tempo", "timeSignature",
//        "copyright"?, "ccliNumber"?, "source"?,
//        "arrangement": ["v1","c","v2","c","b","c"],
//        "sections": [{
//          "id": "v1", "type": "verse|chorus|bridge|prechorus|intro|ending|tag|interlude",
//          "label": "Strofa 1", "order": 0,
//          "lines": [{ "text", "chords": [{"sym","pos"}], "translations": {"es":"...","en":"..."} }],
//          "_extensions": {}
//        }],
//        "_extensions": {}
//      }],
//      "_extensions": {}
//    }
//  }
//
//  Back-compat: legacy v1 "TopPresenter Songs" bundle files (root `songs` array of
//  flat {title, verses:[{label,verseType,text,order}]} objects) are also accepted.
//  ─────────────────────────────────────────────────────────────────────────────

import Foundation

/// Importer for the native TopPresenter Song JSON format (single song per file).
final class TopPresenterSongImporter: SongImporter {
    let format: SupportedSongFormat = .topPresenterJSON

    func parse(fileURL: URL) async throws -> SongImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw SongImportError.fileNotFound
        }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { throw SongImportError.emptyFile }

        let results = try Self.allResults(from: data, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
        guard let first = results.first else { throw SongImportError.noSongsFound }
        return first
    }

    /// Every song in a file: 1 for a single-song doc, N for a legacy bundle.
    static func allResults(from data: Data, fallbackTitle: String = "") throws -> [SongImportResult] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw SongImportError.invalidFormat("Not valid JSON")
        }

        // Single-song v2 document
        if let songObj = root["song"] as? [String: Any] {
            return [parseSong(songObj, fallbackTitle: fallbackTitle)]
        }
        // Bundle / legacy v1 collection
        if let songs = root["songs"] as? [[String: Any]] {
            return songs.map { parseSong($0, fallbackTitle: fallbackTitle) }
        }
        // A bare song object (no envelope)
        if root["title"] != nil || root["versions"] != nil {
            return [parseSong(root, fallbackTitle: fallbackTitle)]
        }
        throw SongImportError.invalidFormat("No song or songs key")
    }

    // MARK: - Song parsing

    private static func parseSong(_ obj: [String: Any], fallbackTitle: String) -> SongImportResult {
        let titles = (obj["titles"] as? [String]) ?? []
        let title = (obj["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? titles.first
            ?? (fallbackTitle.isEmpty ? "Untitled" : fallbackTitle)

        let themes = (obj["themes"] as? [String]) ?? []
        let tags = (obj["tags"] as? String) ?? themes.joined(separator: ", ")

        // Authors: prefer split fields, fall back to a combined "author".
        let authorWords = (obj["authorWords"] as? String) ?? ""
        let authorMusic = (obj["authorMusic"] as? String) ?? ""
        let authorTranslation = (obj["authorTranslation"] as? String) ?? ""
        let combinedAuthor = (obj["author"] as? String)
            ?? [authorWords, authorMusic, authorTranslation].filter { !$0.isEmpty }.joined(separator: ", ")

        var songbook: SongImportSongbook?
        if let sb = obj["songbook"] as? [String: Any], let name = sb["name"] as? String, !name.isEmpty {
            songbook = SongImportSongbook(
                name: name,
                publisher: (sb["publisher"] as? String) ?? "",
                language: (sb["language"] as? String) ?? "",
                year: stringValue(sb["year"]),
                number: stringValue(sb["number"])
            )
        }

        let media: [SongImportMedia] = (obj["media"] as? [[String: Any]] ?? []).compactMap { m in
            guard let filename = m["filename"] as? String, !filename.isEmpty else { return nil }
            return SongImportMedia(
                role: (m["role"] as? String) ?? "audio",
                kind: (m["kind"] as? String) ?? "audio",
                filename: filename,
                bookmark: m["bookmark"] as? String
            )
        }

        // Versions (v2). If absent, synthesize one from legacy flat `verses`.
        var versions: [SongImportVersion] = []
        if let versionsArr = obj["versions"] as? [[String: Any]] {
            versions = versionsArr.enumerated().map { parseVersion($0.element, fallbackOrder: $0.offset) }
        }

        var flatVerses: [SongImportVerse] = []
        if versions.isEmpty {
            flatVerses = parseFlatVerses(obj["verses"])
        } else if let firstSections = versions.first?.sections {
            // Provide a flat-verse view of the active version for legacy consumers.
            flatVerses = firstSections.enumerated().map { idx, sec in
                SongImportVerse(label: sec.label, verseType: sec.type,
                                text: sec.lines.map { $0.text }.joined(separator: "\n"), order: idx)
            }
        }

        let songNumber = stringValue(obj["songNumber"]) .isEmpty ? (songbook?.number ?? "") : stringValue(obj["songNumber"])

        return SongImportResult(
            title: title,
            author: combinedAuthor,
            copyright: (obj["copyright"] as? String) ?? "",
            ccliNumber: stringValue(obj["ccliNumber"]),
            key: (obj["key"] as? String) ?? versions.first?.key ?? "",
            tempo: stringValue(obj["tempo"]),
            songNumber: songNumber,
            tags: tags,
            verses: flatVerses,
            titles: titles,
            language: (obj["language"] as? String) ?? "",
            themes: themes,
            style: (obj["style"] as? String) ?? "",
            songbook: songbook,
            authorWords: authorWords,
            authorMusic: authorMusic,
            authorTranslation: authorTranslation,
            notes: (obj["notes"] as? String) ?? "",
            media: media,
            versions: versions
        )
    }

    private static func parseVersion(_ obj: [String: Any], fallbackOrder: Int) -> SongImportVersion {
        let sectionsArr = obj["sections"] as? [[String: Any]] ?? []
        let sections: [SongImportSection] = sectionsArr.enumerated().map { idx, s in
            let key = (s["id"] as? String) ?? (s["sectionKey"] as? String) ?? "s\(idx)"
            return SongImportSection(
                sectionKey: key,
                type: (s["type"] as? String) ?? "verse",
                label: (s["label"] as? String) ?? key,
                order: (s["order"] as? Int) ?? idx,
                repeatCount: (s["repeat"] as? Int) ?? (s["repeatCount"] as? Int) ?? 1,
                lines: parseLines(s["lines"])
            )
        }
        return SongImportVersion(
            name: (obj["name"] as? String) ?? "",
            displayTitle: (obj["displayTitle"] as? String) ?? (obj["title"] as? String) ?? "",
            author: (obj["author"] as? String) ?? "",
            titles: (obj["titles"] as? [String]) ?? [],
            authorWords: (obj["authorWords"] as? String) ?? "",
            authorMusic: (obj["authorMusic"] as? String) ?? "",
            authorTranslation: (obj["authorTranslation"] as? String) ?? "",
            style: (obj["style"] as? String) ?? "",
            songbookNumber: stringValue(obj["songbookNumber"]),
            songbookName: ((obj["songbook"] as? [String: Any])?["name"] as? String) ?? (obj["songbook"] as? String) ?? "",
            themes: (obj["themes"] as? [String]) ?? [],
            notes: (obj["notes"] as? String) ?? "",
            language: (obj["language"] as? String) ?? "",
            key: (obj["key"] as? String) ?? "",
            capo: (obj["capo"] as? Int) ?? 0,
            tempo: stringValue(obj["tempo"]),
            timeSignature: (obj["timeSignature"] as? String) ?? "",
            copyright: (obj["copyright"] as? String) ?? "",
            ccliNumber: stringValue(obj["ccliNumber"]),
            source: (obj["source"] as? String) ?? "",
            repeatStyle: (obj["repeatStyle"] as? String) ?? "",
            overridesMetadata: (obj["overridesMetadata"] as? Bool) ?? false,
            arrangement: (obj["arrangement"] as? [String]) ?? [],
            sections: sections
        )
    }

    private static func parseLines(_ raw: Any?) -> [SongLine] {
        // Rich line objects
        if let arr = raw as? [[String: Any]] {
            return arr.map { lo in
                let chords: [SongChord] = (lo["chords"] as? [[String: Any]] ?? []).compactMap { c in
                    guard let sym = c["sym"] as? String else { return nil }
                    return SongChord(sym: sym, pos: (c["pos"] as? Int) ?? 0)
                }
                let translations = (lo["translations"] as? [String: String]) ?? [:]
                return SongLine(text: (lo["text"] as? String) ?? "", chords: chords, translations: translations)
            }
        }
        // Plain string lines
        if let arr = raw as? [String] {
            return arr.map { SongLine(text: $0) }
        }
        return []
    }

    private static func parseFlatVerses(_ raw: Any?) -> [SongImportVerse] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.enumerated().map { idx, v in
            SongImportVerse(
                label: (v["label"] as? String) ?? "Slide \(idx + 1)",
                verseType: (v["verseType"] as? String) ?? "verse",
                text: (v["text"] as? String) ?? "",
                order: (v["order"] as? Int) ?? idx
            )
        }
    }

    /// Coerce numbers/strings to String (JSON may carry year/ccli/tempo as either).
    private static func stringValue(_ any: Any?) -> String {
        switch any {
        case let s as String: return s
        case let i as Int: return String(i)
        case let d as Double: return d == d.rounded() ? String(Int(d)) : String(d)
        default: return ""
        }
    }
}
