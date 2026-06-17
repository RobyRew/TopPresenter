//
//  PowerPointSongImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 05/04/2026.
//

import Foundation

/// Imports songs from PowerPoint files (.pptx, .ppt).
/// Each slide becomes a song verse/section.
/// The first slide's title (or first text) becomes the song title.
final class PowerPointSongImporter: SongImporter {
    var format: SupportedSongFormat { .powerPoint }

    func parse(fileURL: URL) async throws -> SongImportResult {
        let ext = fileURL.pathExtension.lowercased()

        if ext == "pptx" {
            return try await parsePPTX(fileURL: fileURL)
        } else if ext == "ppt" {
            return try await parsePPT(fileURL: fileURL)
        } else {
            throw SongImportError.invalidFormat("Not a PowerPoint file")
        }
    }

    // MARK: - PPTX Parsing (ZIP + XML)

    /// PPTX files are ZIP archives containing XML — slides live in
    /// ppt/slides/slide1.xml, slide2.xml, …
    /// Read ENTIRELY in-process via ZipArchiveReader: spawning /usr/bin/ditto
    /// fails in the sandbox because child processes don't inherit the user's
    /// file-access grant for the selected file.
    private func parsePPTX(fileURL: URL) async throws -> SongImportResult {
        let archiveData = try Data(contentsOf: fileURL)
        let zip: ZipArchiveReader
        do {
            zip = try ZipArchiveReader(data: archiveData)
        } catch {
            throw SongImportError.parsingFailed("Failed to read PPTX archive: \(error.localizedDescription)")
        }

        // Find and sort the slide XML entries (ppt/slides/slideN.xml, not _rels)
        let slideEntries = zip.entries
            .filter {
                $0.name.hasPrefix("ppt/slides/slide")
                    && $0.name.hasSuffix(".xml")
                    && !$0.name.contains("_rels")
            }
            .sorted { entry1, entry2 in
                extractSlideNumber(from: entry1.name) < extractSlideNumber(from: entry2.name)
            }

        guard !slideEntries.isEmpty else {
            throw SongImportError.parsingFailed("No slides found in PPTX")
        }

        // Extract metadata (title) from docProps/core.xml
        var presentationTitle = ""
        if let coreEntry = zip.entry(named: "docProps/core.xml"),
           let coreData = try? zip.extract(coreEntry),
           let coreString = String(data: coreData, encoding: .utf8) {
            presentationTitle = extractXMLValue(from: coreString, tag: "dc:title")
                ?? extractXMLValue(from: coreString, tag: "title")
                ?? ""
        }

        // Parse each slide
        var slideTexts: [(title: String, body: String)] = []
        for entry in slideEntries {
            let slideData = try zip.extract(entry)
            let slideContent = try parsePPTXSlideXML(data: slideData)
            if !slideContent.title.isEmpty || !slideContent.body.isEmpty {
                slideTexts.append(slideContent)
            }
        }

        guard !slideTexts.isEmpty else {
            throw SongImportError.noSongsFound
        }

        return buildSongResult(
            fileName: fileURL.deletingPathExtension().lastPathComponent,
            presentationTitle: presentationTitle,
            slides: slideTexts
        )
    }

    /// Parse a single PPTX slide XML and extract title + body text.
    private func parsePPTXSlideXML(data: Data) throws -> (title: String, body: String) {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            return ("", "")
        }

        // Use XMLParser for proper parsing
        let parser = PPTXSlideXMLParser(xmlString: xmlString)
        return parser.parse()
    }

    // MARK: - PPT Parsing (OLE/CFB Binary)

    /// PPT files are OLE Compound Documents.
    /// We read the binary, find text records, and group by slides.
    private func parsePPT(fileURL: URL) async throws -> SongImportResult {
        let data = try Data(contentsOf: fileURL)
        guard data.count > 512 else {
            throw SongImportError.parsingFailed("File too small to be a valid PPT")
        }

        // Verify it's a CFB/OLE file (magic bytes: D0 CF 11 E0 A1 B1 1A E1)
        let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
        let fileMagic = Array(data.prefix(8))
        guard fileMagic == magic else {
            throw SongImportError.invalidFormat("Not a valid PPT file (invalid OLE header)")
        }

        // Parse OLE compound document to find "PowerPoint Document" stream
        let pptStream = try extractPPTStream(from: data)

        // Parse the PowerPoint document stream for text records
        let slideTexts = parsePPTRecords(data: pptStream)

        guard !slideTexts.isEmpty else {
            throw SongImportError.noSongsFound
        }

        let slides = slideTexts.map { texts -> (title: String, body: String) in
            let title = texts.first ?? ""
            let body = texts.dropFirst().joined(separator: "\n")
            return (title, body)
        }

        return buildSongResult(
            fileName: fileURL.deletingPathExtension().lastPathComponent,
            presentationTitle: "",
            slides: slides
        )
    }

    /// Extract the "PowerPoint Document" stream from OLE/CFB data.
    private func extractPPTStream(from data: Data) throws -> Data {
        // Parse CFB header
        let bytes = [UInt8](data)
        guard bytes.count > 512 else {
            throw SongImportError.parsingFailed("Invalid OLE file")
        }

        // Read sector size (at offset 30, 2 bytes LE)
        let sectorSizePower = UInt16(bytes[30]) | (UInt16(bytes[31]) << 8)
        let sectorSize = 1 << Int(sectorSizePower)

        // Read mini sector size (at offset 32)
        let miniSectorSizePower = UInt16(bytes[32]) | (UInt16(bytes[33]) << 8)
        _ = 1 << Int(miniSectorSizePower)

        // Read FAT sector count (at offset 44)
        let fatSectorCount = readUInt32LE(bytes, offset: 44)

        // Read first directory sector (at offset 48)
        let firstDirSector = readUInt32LE(bytes, offset: 48)

        // Read first mini FAT sector (at offset 60)
        _ = readUInt32LE(bytes, offset: 60)

        // Read DIFAT entries (at offset 76, 109 entries × 4 bytes)
        var fatSectors: [UInt32] = []
        for i in 0..<min(Int(fatSectorCount), 109) {
            let offset = 76 + i * 4
            if offset + 4 <= bytes.count {
                fatSectors.append(readUInt32LE(bytes, offset: offset))
            }
        }

        // Build the FAT (File Allocation Table)
        var fat: [UInt32] = []
        for fatSector in fatSectors {
            let sectorOffset = 512 + Int(fatSector) * sectorSize
            let entriesPerSector = sectorSize / 4
            for i in 0..<entriesPerSector {
                let off = sectorOffset + i * 4
                if off + 4 <= bytes.count {
                    fat.append(readUInt32LE(bytes, offset: off))
                }
            }
        }

        // Read directory entries starting from firstDirSector
        var dirData = Data()
        var currentSector = firstDirSector
        var safetyCounter = 0
        while currentSector != 0xFFFFFFFE && currentSector != 0xFFFFFFFF && safetyCounter < 1000 {
            let sectorOffset = 512 + Int(currentSector) * sectorSize
            if sectorOffset + sectorSize <= bytes.count {
                dirData.append(contentsOf: bytes[sectorOffset..<sectorOffset + sectorSize])
            }
            if Int(currentSector) < fat.count {
                currentSector = fat[Int(currentSector)]
            } else {
                break
            }
            safetyCounter += 1
        }

        // Parse directory entries (128 bytes each) to find "PowerPoint Document"
        let dirEntrySize = 128
        let dirEntries = dirData.count / dirEntrySize
        let targetNames = ["PowerPoint Document", "Current User"]

        for i in 0..<dirEntries {
            let entryOffset = i * dirEntrySize
            guard entryOffset + dirEntrySize <= dirData.count else { break }
            let entry = dirData.subdata(in: entryOffset..<entryOffset + dirEntrySize)

            // Read name (UTF-16LE, first 64 bytes, nameSize at byte 64)
            let nameSize = Int(UInt16(entry[64]) | (UInt16(entry[65]) << 8))
            let nameLen = max(0, nameSize - 2) // subtract null terminator
            var name = ""
            if nameLen > 0 && nameLen <= 62 {
                let nameData = entry.subdata(in: 0..<nameLen)
                name = String(data: nameData, encoding: .utf16LittleEndian) ?? ""
            }

            if !targetNames.contains(name) && name != "PowerPoint Document" { continue }
            if name != "PowerPoint Document" { continue }

            // Read start sector (at byte 116) and size (at byte 120)
            let startSector = readUInt32LE([UInt8](entry), offset: 116)
            let streamSize = readUInt32LE([UInt8](entry), offset: 120)

            // Read the stream by following the FAT chain
            var streamData = Data()
            var sector = startSector
            var remaining = Int(streamSize)
            var safety = 0
            while sector != 0xFFFFFFFE && sector != 0xFFFFFFFF && remaining > 0 && safety < 100000 {
                let off = 512 + Int(sector) * sectorSize
                let toRead = min(sectorSize, remaining)
                if off + toRead <= bytes.count {
                    streamData.append(contentsOf: bytes[off..<off + toRead])
                    remaining -= toRead
                }
                if Int(sector) < fat.count {
                    sector = fat[Int(sector)]
                } else {
                    break
                }
                safety += 1
            }

            return streamData
        }

        throw SongImportError.parsingFailed("Could not find PowerPoint Document stream in PPT file")
    }

    /// Parse PPT binary records to extract slide text.
    /// Returns an array of slides, each containing an array of text strings.
    func parsePPTRecords(data: Data) -> [[String]] {
        let bytes = [UInt8](data)
        var slides: [[String]] = []
        var currentSlideTexts: [String] = []
        var offset = 0

        // PPT Record Types
        let RT_TextCharsAtom: UInt16 = 0x0FA0      // Unicode text (UTF-16LE)
        let RT_TextBytesAtom: UInt16 = 0x0FA8      // ANSI text
        let RT_Slide: UInt16 = 0x03EE

        while offset + 8 <= bytes.count {
            // Read record header: 2 bytes ver+instance, 2 bytes type, 4 bytes length
            let verInstance = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
            let recVer = verInstance & 0x000F
            let recType = UInt16(bytes[offset + 2]) | (UInt16(bytes[offset + 3]) << 8)
            let recLen = readUInt32LE(bytes, offset: offset + 4)

            let recordEnd = offset + 8 + Int(recLen)
            guard recordEnd <= bytes.count && recLen < 100_000_000 else {
                offset += 1
                continue
            }

            // CONTAINER records (recVer == 0xF) hold their children inside recLen
            // — descend into them instead of skipping, or no text is ever found.
            if recVer == 0xF {
                if recType == RT_Slide, !currentSlideTexts.isEmpty {
                    slides.append(currentSlideTexts)
                    currentSlideTexts = []
                }
                offset += 8
                continue
            }

            switch recType {
            case RT_Slide:
                // New slide — flush current texts
                if !currentSlideTexts.isEmpty {
                    slides.append(currentSlideTexts)
                    currentSlideTexts = []
                }

            case RT_TextCharsAtom:
                // UTF-16LE text
                let textData = Data(bytes[offset + 8..<recordEnd])
                if let text = String(data: textData, encoding: .utf16LittleEndian)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\r", with: "\n") {
                    let cleaned = cleanPPTText(text)
                    if !cleaned.isEmpty {
                        currentSlideTexts.append(cleaned)
                    }
                }

            case RT_TextBytesAtom:
                // ANSI/Windows-1252 text
                let textData = Data(bytes[offset + 8..<recordEnd])
                if let text = String(data: textData, encoding: .windowsCP1252)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\r", with: "\n") {
                    let cleaned = cleanPPTText(text)
                    if !cleaned.isEmpty {
                        currentSlideTexts.append(cleaned)
                    }
                }

            default:
                break
            }

            offset = recordEnd
        }

        // Flush remaining
        if !currentSlideTexts.isEmpty {
            slides.append(currentSlideTexts)
        }

        return slides
    }

    // MARK: - Helpers

    private func extractSlideNumber(from filename: String) -> Int {
        // slide1.xml, slide12.xml -> 1, 12
        let digits = filename.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return Int(digits) ?? 0
    }

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        // Simple extraction for <tag>value</tag>
        guard let startRange = xml.range(of: "<\(tag)") else { return nil }
        // Find the closing >
        guard let gtRange = xml.range(of: ">", range: startRange.upperBound..<xml.endIndex) else { return nil }
        guard let endRange = xml.range(of: "</\(tag)>", range: gtRange.upperBound..<xml.endIndex) else { return nil }
        let value = String(xml[gtRange.upperBound..<endRange.lowerBound])
        return value.isEmpty ? nil : value
    }

    private func cleanPPTText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readUInt32LE(_ bytes: [UInt8], offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    /// Build a SongImportResult from extracted slide data.
    ///
    /// PowerPoint has no real structure, so each slide becomes a section. We additionally:
    ///  - prefer the file name as the song title (slide 1 is usually a lyric, not a title);
    ///  - collapse identical repeated slides into a single section referenced multiple times
    ///    in the version `arrangement` (a slide repeated ≥2× is treated as the chorus);
    ///  - guess the language from the lyrics' diacritics.
    private func buildSongResult(
        fileName: String,
        presentationTitle: String,
        slides: [(title: String, body: String)]
    ) -> SongImportResult {
        let songTitle: String
        if !presentationTitle.isEmpty {
            songTitle = presentationTitle
        } else if !fileName.isEmpty {
            songTitle = fileName
        } else {
            songTitle = slides.first?.title ?? "Untitled"
        }

        // Collect non-empty slide units.
        struct Unit { let text: String; let normKey: String; let labeledType: String? }
        var units: [Unit] = []
        var allText = ""
        for slide in slides {
            let fullText: String
            if !slide.title.isEmpty && !slide.body.isEmpty {
                fullText = slide.title + "\n" + slide.body
            } else if !slide.title.isEmpty {
                fullText = slide.title
            } else {
                fullText = slide.body
            }
            guard !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            allText += " " + fullText
            units.append(Unit(text: fullText, normKey: normalize(fullText), labeledType: labeledType(slide.title)))
        }

        var repeatCount: [String: Int] = [:]
        for unit in units { repeatCount[unit.normKey, default: 0] += 1 }

        var sections: [SongImportSection] = []
        var keyByNorm: [String: String] = [:]
        var arrangement: [String] = []
        var counters: [String: Int] = [:]

        for unit in units {
            if let existing = keyByNorm[unit.normKey] {
                arrangement.append(existing)   // repeated slide → reuse the section
                continue
            }
            let type: String
            if let labeled = unit.labeledType {
                type = labeled
            } else if (repeatCount[unit.normKey] ?? 0) >= 2 {
                type = "chorus"                // an unlabeled slide that repeats is the chorus
            } else {
                type = "verse"
            }
            let (key, label) = nextKeyLabel(type, &counters)
            let lines = unit.text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
                .map { SongLine(text: $0) }
            sections.append(SongImportSection(sectionKey: key, type: type, label: label, order: sections.count, lines: lines))
            keyByNorm[unit.normKey] = key
            arrangement.append(key)
        }

        // Only record an arrangement when slides actually repeat (otherwise it's just section order).
        let finalArrangement = arrangement.count > sections.count ? arrangement : []
        let version = SongImportVersion(name: "Original", arrangement: finalArrangement, sections: sections)

        let flatVerses = sections.enumerated().map { idx, sec in
            SongImportVerse(label: sec.label, verseType: sec.type,
                            text: sec.lines.map { $0.text }.joined(separator: "\n"), order: idx)
        }

        return SongImportResult(
            title: songTitle,
            author: "",
            copyright: "",
            ccliNumber: "",
            key: "",
            tempo: "",
            songNumber: "",
            tags: "powerpoint",
            verses: flatVerses,
            language: guessLanguage(allText),
            versions: [version]
        )
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func labeledType(_ title: String) -> String? {
        let t = title.lowercased()
        if t.hasPrefix("chorus") || t.hasPrefix("refren") || t.hasPrefix("cor") { return "chorus" }
        if t.hasPrefix("bridge") || t.hasPrefix("punte") { return "bridge" }
        if t.hasPrefix("pre-chorus") || t.hasPrefix("pre chorus") { return "prechorus" }
        if t.hasPrefix("ending") || t.hasPrefix("final") { return "ending" }
        return nil
    }

    private func nextKeyLabel(_ type: String, _ counters: inout [String: Int]) -> (key: String, label: String) {
        let n = (counters[type] ?? 0) + 1
        counters[type] = n
        switch type {
        case "chorus": return (n == 1 ? "c" : "c\(n)", n == 1 ? "Chorus" : "Chorus \(n)")
        case "bridge": return ("b\(n)", n == 1 ? "Bridge" : "Bridge \(n)")
        case "prechorus": return ("p\(n)", "Pre-Chorus")
        case "ending": return ("e", "Ending")
        default: return ("v\(n)", "Verse \(n)")
        }
    }

    private func guessLanguage(_ text: String) -> String {
        let lower = text.lowercased()
        let roDiacritics = lower.reduce(0) { "ăâîșț".contains($1) ? $0 + 1 : $0 }
        let esMarks = lower.reduce(0) { "ñ¿¡".contains($1) ? $0 + 1 : $0 }
        if roDiacritics >= 3 { return "ro" }
        if esMarks >= 1 { return "es" }
        return ""
    }
}

// MARK: - PPTX Slide XML Parser

/// Parses a single PPTX slide XML to extract title and body text.
private class PPTXSlideXMLParser: NSObject, XMLParserDelegate {
    private let xmlString: String

    // Parsing state
    private var isInTextElement = false  // inside <a:t>
    private var isInTitleShape = false
    private var isInPlaceholder = false
    private var currentPlaceholderType = ""
    private var currentText = ""

    // Results
    private var titleTexts: [String] = []
    private var bodyTexts: [String] = []
    private var allTextsInCurrentShape: [String] = []
    private var isCollectingShape = false

    init(xmlString: String) {
        self.xmlString = xmlString
    }

    func parse() -> (title: String, body: String) {
        guard let data = xmlString.data(using: .utf8) else {
            return ("", "")
        }

        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        parser.shouldReportNamespacePrefixes = false
        parser.parse()

        let title = titleTexts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let body = bodyTexts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

        return (title, body)
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "sp":
            // Start of a shape
            isCollectingShape = true
            allTextsInCurrentShape = []
            isInTitleShape = false
            currentPlaceholderType = ""

        case "ph":
            // Placeholder type tells us if this is a title, subtitle, body, etc.
            let phType = attributeDict["type"] ?? ""
            currentPlaceholderType = phType
            if phType == "title" || phType == "ctrTitle" {
                isInTitleShape = true
            }

        case "t":
            // Text element — collect content
            isInTextElement = true
            currentText = ""

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.components(separatedBy: ":").last ?? elementName

        switch localName {
        case "t":
            isInTextElement = false
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                allTextsInCurrentShape.append(trimmed)
            }

        case "sp":
            // End of shape — decide whether it's title or body
            if isCollectingShape && !allTextsInCurrentShape.isEmpty {
                let combined = allTextsInCurrentShape.joined(separator: " ")
                if isInTitleShape {
                    titleTexts.append(combined)
                } else {
                    bodyTexts.append(combined)
                }
            }
            isCollectingShape = false
            isInTitleShape = false
            currentPlaceholderType = ""

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInTextElement {
            currentText += string
        }
    }
}
