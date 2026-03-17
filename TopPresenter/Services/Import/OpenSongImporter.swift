//
//  OpenSongImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for OpenSong XML format songs.
/// OpenSong uses one file per song, typically without a file extension.
/// Each song file contains lyrics with verse markers.
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
        let verses = parseLyrics(delegate.lyrics, presentation: delegate.presentation)

        return SongImportResult(
            title: title,
            author: delegate.author,
            copyright: delegate.copyright,
            ccliNumber: delegate.ccli,
            key: delegate.key,
            tempo: delegate.tempo,
            songNumber: delegate.hymn_number,
            tags: delegate.theme,
            verses: verses
        )
    }

    /// Parse OpenSong lyrics format.
    /// Lines starting with [ mark verse sections (e.g., [V1], [C], [B])
    /// Lines starting with . are chord lines (ignored for presentation)
    /// Lines starting with a space are lyric lines
    private func parseLyrics(_ lyrics: String, presentation: String) -> [SongImportVerse] {
        let lines = lyrics.components(separatedBy: .newlines)
        var verses: [SongImportVerse] = []
        var currentLabel = "Verse 1"
        var currentType = "verse"
        var currentLines: [String] = []
        var order = 0

        for line in lines {
            if line.hasPrefix("[") {
                // Save previous verse
                if !currentLines.isEmpty {
                    let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        verses.append(SongImportVerse(
                            label: currentLabel,
                            verseType: currentType,
                            text: text,
                            order: order
                        ))
                        order += 1
                    }
                    currentLines = []
                }

                // Parse section header
                let sectionTag = line
                    .replacingOccurrences(of: "[", with: "")
                    .replacingOccurrences(of: "]", with: "")
                    .trimmingCharacters(in: .whitespaces)

                let (label, type) = classifySection(sectionTag)
                currentLabel = label
                currentType = type

            } else if line.hasPrefix(".") {
                // Chord line - skip for lyrics
                continue
            } else if line.hasPrefix(" ") || line.hasPrefix(";") {
                // Lyric line (remove leading space) or comment
                let lyricLine: String
                if line.hasPrefix(";") {
                    continue  // Skip comments
                } else {
                    lyricLine = String(line.dropFirst())
                }
                currentLines.append(lyricLine)
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Some OpenSong files have lyrics without leading space
                currentLines.append(line)
            }
        }

        // Save last verse
        if !currentLines.isEmpty {
            let text = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                verses.append(SongImportVerse(
                    label: currentLabel,
                    verseType: currentType,
                    text: text,
                    order: order
                ))
            }
        }

        // If presentation order is specified, reorder
        if !presentation.isEmpty {
            return applyPresentationOrder(verses: verses, presentation: presentation)
        }

        return verses
    }

    private func classifySection(_ tag: String) -> (label: String, type: String) {
        let upper = tag.uppercased()

        if upper.hasPrefix("V") || upper.hasPrefix("VERSE") {
            let num = tag.filter { $0.isNumber }
            return ("Verse \(num.isEmpty ? "1" : num)", "verse")
        } else if upper.hasPrefix("C") || upper.hasPrefix("CHORUS") {
            let num = tag.filter { $0.isNumber }
            return ("Chorus\(num.isEmpty ? "" : " \(num)")", "chorus")
        } else if upper.hasPrefix("B") || upper.hasPrefix("BRIDGE") {
            let num = tag.filter { $0.isNumber }
            return ("Bridge\(num.isEmpty ? "" : " \(num)")", "bridge")
        } else if upper.hasPrefix("P") || upper.hasPrefix("PRE") {
            return ("Pre-Chorus", "pre-chorus")
        } else if upper.hasPrefix("T") || upper.hasPrefix("TAG") {
            return ("Tag", "tag")
        } else if upper.hasPrefix("E") || upper.hasPrefix("END") {
            return ("Ending", "ending")
        } else {
            return (tag, "other")
        }
    }

    private func applyPresentationOrder(verses: [SongImportVerse], presentation: String) -> [SongImportVerse] {
        let sections = presentation.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var ordered: [SongImportVerse] = []
        var orderIndex = 0

        for section in sections {
            // Find matching verse by tag
            if let match = verses.first(where: { matchesTag($0, sectionTag: section) }) {
                ordered.append(SongImportVerse(
                    label: match.label,
                    verseType: match.verseType,
                    text: match.text,
                    order: orderIndex
                ))
                orderIndex += 1
            }
        }

        return ordered.isEmpty ? verses : ordered
    }

    private func matchesTag(_ verse: SongImportVerse, sectionTag: String) -> Bool {
        let tag = sectionTag.uppercased()
        let label = verse.label.uppercased()

        if tag.hasPrefix("V") {
            let num = tag.filter { $0.isNumber }
            return label.contains("VERSE") && (num.isEmpty || label.contains(num))
        } else if tag.hasPrefix("C") {
            return label.contains("CHORUS")
        } else if tag.hasPrefix("B") {
            return label.contains("BRIDGE")
        }
        return false
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
        default: break
        }

        currentText = ""
    }
}
