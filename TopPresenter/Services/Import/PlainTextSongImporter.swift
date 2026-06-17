//
//  PlainTextSongImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/06/2026.
//

import Foundation

/// Importer for plain-text songs (.txt): blank-line-separated stanzas become sections.
/// A stanza whose first line is a bracketed/keyword label (e.g. "[Chorus]", "Refren:")
/// is typed accordingly; everything else is a verse.
final class PlainTextSongImporter: SongImporter {
    let format: SupportedSongFormat = .plainText

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
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var sections: [SongImportSection] = []
        var counters: [String: Int] = [:]

        for block in blocks {
            var lines = block.components(separatedBy: "\n")
            var type = "verse"
            var explicitLabel = ""

            if let first = lines.first, let detected = detectLabel(first) {
                type = detected.type
                explicitLabel = detected.label
                lines.removeFirst()
            }
            let songLines = lines
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
                .filter { !$0.isEmpty }
                .map { SongLine(text: $0) }
            guard !songLines.isEmpty else { continue }

            let n = (counters[type] ?? 0) + 1
            counters[type] = n
            let (key, label) = keyAndLabel(type: type, n: n, explicit: explicitLabel)
            sections.append(SongImportSection(sectionKey: key, type: type, label: label, order: sections.count, lines: songLines))
        }

        let version = SongImportVersion(name: "Original", source: "Plain Text", sections: sections)
        let title = fallbackTitle.isEmpty ? "Untitled" : fallbackTitle

        return SongImportResult(
            title: title, author: "", copyright: "", ccliNumber: "", key: "", tempo: "",
            songNumber: "", tags: "", verses: [], versions: [version]
        )
    }

    private static func detectLabel(_ raw: String) -> (type: String, label: String)? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        // Strip [ ] or trailing :
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        let lower = s.lowercased()
        // Only treat short tokens as labels (avoid eating a real lyric line).
        guard s.count <= 24 else { return nil }
        if lower.hasPrefix("refren") || lower.hasPrefix("chorus") || lower.hasPrefix("cor") { return ("chorus", "Chorus") }
        if lower.hasPrefix("punte") || lower.hasPrefix("bridge") { return ("bridge", "Bridge") }
        if lower.hasPrefix("pre") { return ("prechorus", "Pre-Chorus") }
        if lower.hasPrefix("strofa") || lower.hasPrefix("verse") || lower.hasPrefix("v.") { return ("verse", s) }
        if lower.hasPrefix("final") || lower.hasPrefix("ending") { return ("ending", "Ending") }
        return nil
    }

    private static func keyAndLabel(type: String, n: Int, explicit: String) -> (String, String) {
        switch type {
        case "chorus": return (n == 1 ? "c" : "c\(n)", explicit.isEmpty ? (n == 1 ? "Chorus" : "Chorus \(n)") : explicit)
        case "bridge": return ("b\(n)", explicit.isEmpty ? "Bridge" : explicit)
        case "prechorus": return ("p\(n)", "Pre-Chorus")
        case "ending": return ("e", "Ending")
        default: return ("v\(n)", explicit.isEmpty ? "Verse \(n)" : explicit)
        }
    }
}
