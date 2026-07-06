//
//  USFMBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Importer for USFM (Unified Standard Format Markers) format Bibles.
/// USFM is a widely-used format for Bible translations, developed by United Bible Societies.
/// Files use backslash markers like \c (chapter), \v (verse), \id (book identifier).
/// This importer handles a directory of .usfm/.sfm files (one per book) or a single concatenated file.
nonisolated final class USFMBibleImporter: BibleImporter {
    let format: SupportedBibleFormat = .usfm

    func parse(fileURL: URL) async throws -> BibleImportResult {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw BibleImportError.fileNotFound
        }

        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)

        var allBooks: [BibleImportBook] = []
        var moduleName = fileURL.deletingPathExtension().lastPathComponent
        var language = "en"

        if isDirectory.boolValue {
            // Parse all USFM files in the directory
            let fileManager = FileManager.default
            let contents = try fileManager.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil)
            let usfmFiles = contents.filter { url in
                let ext = url.pathExtension.lowercased()
                return ext == "usfm" || ext == "sfm" || ext == "txt"
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }

            guard !usfmFiles.isEmpty else {
                throw BibleImportError.invalidFormat("No USFM files found in directory")
            }

            moduleName = fileURL.lastPathComponent

            for file in usfmFiles {
                let content = try String(contentsOf: file, encoding: .utf8)
                let parsed = parseUSFMContent(content)
                allBooks.append(contentsOf: parsed.books)
                if !parsed.language.isEmpty { language = parsed.language }
                if !parsed.name.isEmpty && moduleName == fileURL.lastPathComponent {
                    moduleName = parsed.name
                }
            }
        } else {
            // Single file — may contain one or multiple books
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            guard !content.isEmpty else { throw BibleImportError.emptyFile }

            let parsed = parseUSFMContent(content)
            allBooks = parsed.books
            if !parsed.name.isEmpty { moduleName = parsed.name }
            if !parsed.language.isEmpty { language = parsed.language }
        }

        guard !allBooks.isEmpty else {
            throw BibleImportError.invalidFormat("No books found in USFM content")
        }

        // Sort books by book number
        allBooks.sort { $0.bookNumber < $1.bookNumber }

        // Derive abbreviation from module name
        let abbreviation = deriveAbbreviation(from: moduleName)

        var result = BibleImportResult(
            moduleName: moduleName,
            abbreviation: abbreviation,
            language: language,
            description: "",
            books: allBooks
        )
        result.hasWordsOfChrist = anyWoc
        result.hasStrongs = anyStrong
        return result
    }

    // MARK: - USFM Parsing

    /// Aggregated across every parsed file/book — feeds the module-level flags.
    private var anyWoc = false
    private var anyStrong = false

    private struct ParsedUSFM {
        var name: String = ""
        var language: String = ""
        var books: [BibleImportBook] = []
    }

    private func parseUSFMContent(_ content: String) -> ParsedUSFM {
        var result = ParsedUSFM()

        let lines = content.components(separatedBy: .newlines)

        var currentBookID = ""
        var currentBookName = ""
        var currentBookNumber = 0
        var currentChapter = 0
        var currentVerseNum = 0
        var currentVerseText = ""
        var currentVerseRaw = ""        // unstripped, for rich-run extraction
        var pendingHeadings: [BibleHeading] = []

        var chapters: [BibleImportChapter] = []
        var verses: [BibleImportVerse] = []

        func finishVerse() {
            let text = currentVerseText.trimmingCharacters(in: .whitespacesAndNewlines)
            if currentVerseNum > 0 && !text.isEmpty {
                // GOAT v2: extract red-letter / Strong's / added-words runs + notes.
                let rich = USFMRich.parse(currentVerseRaw, plain: text)
                let footnotes = USFMNotes.footnotes(currentVerseRaw)
                let crossRefs = USFMNotes.crossRefs(currentVerseRaw)
                if rich.woc { anyWoc = true }
                if rich.runs?.contains(where: { $0.strong != nil }) == true { anyStrong = true }
                verses.append(BibleImportVerse(
                    verseNumber: currentVerseNum, text: text,
                    runs: rich.runs,
                    footnotes: footnotes.isEmpty ? nil : footnotes,
                    crossReferences: crossRefs.isEmpty ? nil : crossRefs,
                    hasWordsOfChrist: rich.woc
                ))
            }
            currentVerseText = ""
            currentVerseRaw = ""
            currentVerseNum = 0
        }

        func finishChapter() {
            finishVerse()
            if currentChapter > 0 && !verses.isEmpty {
                chapters.append(BibleImportChapter(
                    chapterNumber: currentChapter, verses: verses,
                    headings: pendingHeadings.isEmpty ? nil : pendingHeadings
                ))
            }
            verses = []
            pendingHeadings = []
        }

        func finishBook() {
            finishChapter()
            if !currentBookID.isEmpty && !chapters.isEmpty {
                let testament = currentBookNumber <= 39 ? "OT" : "NT"
                result.books.append(BibleImportBook(
                    name: currentBookName,
                    bookNumber: currentBookNumber,
                    testament: testament,
                    chapters: chapters
                ))
            }
            chapters = []
            currentBookID = ""
            currentBookName = ""
            currentBookNumber = 0
            currentChapter = 0
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("\\id ") {
                // Start of a new book — finish previous if any
                finishBook()

                let rest = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                let parts = rest.split(separator: " ", maxSplits: 1)
                let bookCode = String(parts[0]).uppercased()
                currentBookID = bookCode

                if let info = USFMBookIDs.mapping[bookCode] {
                    currentBookName = info.name
                    currentBookNumber = info.number
                } else {
                    currentBookName = bookCode
                    currentBookNumber = result.books.count + 1
                }

                // Sometimes the rest contains the translation name
                if parts.count > 1 && result.name.isEmpty {
                    let possibleName = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !possibleName.isEmpty {
                        result.name = possibleName
                    }
                }

            } else if trimmed.hasPrefix("\\h ") || trimmed.hasPrefix("\\toc1 ") {
                // Book heading / long table of contents name
                let value = extractMarkerValue(trimmed)
                if !value.isEmpty {
                    currentBookName = value
                }

            } else if trimmed.hasPrefix("\\mt") || trimmed.hasPrefix("\\mt1 ") {
                // Main title — could be translation name
                let value = extractMarkerValue(trimmed)
                if !value.isEmpty && result.name.isEmpty {
                    result.name = value
                }

            } else if trimmed.hasPrefix("\\s ") || trimmed.hasPrefix("\\s1 ") || trimmed.hasPrefix("\\s2 ") {
                // Section heading — shown before the verse that follows it.
                let value = stripUSFMInlineMarkers(extractMarkerValue(trimmed))
                if !value.isEmpty {
                    pendingHeadings.append(BibleHeading(beforeVerse: currentVerseNum + 1, level: 1, text: value))
                }

            } else if trimmed.hasPrefix("\\c ") {
                finishChapter()
                let value = extractMarkerValue(trimmed)
                currentChapter = Int(value) ?? (currentChapter + 1)

            } else if trimmed.hasPrefix("\\v ") {
                finishVerse()
                let rest = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)

                // Verse number may be a single number or a range like "1-2"
                let parts = rest.split(separator: " ", maxSplits: 1)
                if let firstPart = parts.first {
                    let verseNumStr = String(firstPart).replacingOccurrences(of: "-.*", with: "", options: .regularExpression)
                    currentVerseNum = Int(verseNumStr) ?? 0
                }

                // Text after the verse number
                if parts.count > 1 {
                    let verseContent = String(parts[1])
                    currentVerseText = stripUSFMInlineMarkers(verseContent)
                    currentVerseRaw = verseContent
                }

            } else if trimmed.hasPrefix("\\") {
                // Other markers — some carry text content that belongs to current verse
                let marker = extractMarker(trimmed)

                // Skip non-content markers
                let skipMarkers = ["id", "ide", "sts", "rem", "toc1", "toc2", "toc3",
                                   "h", "mt", "mt1", "mt2", "mt3", "ms", "ms1", "ms2",
                                   "mr", "r", "s", "s1", "s2", "s3", "sr", "sp",
                                   "d", "cl", "cp", "cd", "ca", "va", "vp",
                                   "f", "fe", "x", "fig", "nb", "b", "ie", "imt",
                                   "is", "ip", "ipi", "im", "imi", "ili", "iot",
                                   "io", "io1", "io2", "ior", "iex"]
                if skipMarkers.contains(marker) { continue }

                // Paragraph markers that may have text — treat as continuation
                let contentMarkers = ["p", "m", "pi", "pi1", "pi2", "mi",
                                      "q", "q1", "q2", "q3", "qr", "qc",
                                      "li", "li1", "li2", "pc", "pr", "cls",
                                      "pmo", "pm", "pmc", "pmr", "nb"]
                if contentMarkers.contains(marker) {
                    let value = extractMarkerValue(trimmed)
                    if !value.isEmpty && currentVerseNum > 0 {
                        currentVerseText += " " + stripUSFMInlineMarkers(value)
                        currentVerseRaw += " " + value
                    }
                    continue
                }

            } else {
                // Plain text line — continuation of current verse
                if currentVerseNum > 0 {
                    currentVerseText += " " + stripUSFMInlineMarkers(trimmed)
                    currentVerseRaw += " " + trimmed
                }
            }
        }

        // Finish last book
        finishBook()

        return result
    }

    // MARK: - Helpers

    /// Extract the marker name from a line like "\p text..." → "p"
    private func extractMarker(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\\") else { return "" }
        let rest = String(trimmed.dropFirst())
        // Marker ends at space or asterisk or end of string
        var marker = ""
        for ch in rest {
            if ch == " " || ch == "*" { break }
            marker.append(ch)
        }
        return marker
    }

    /// Extract the text value after a marker, e.g. "\c 5" → "5", "\h Genesis" → "Genesis"
    private func extractMarkerValue(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // Find first space after the marker
        guard let spaceIndex = trimmed.firstIndex(of: " ") else { return "" }
        return String(trimmed[trimmed.index(after: spaceIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    /// Strip inline USFM character markers from verse text.
    /// Keeps the text content, removes markup like \add ...\add*, \wj ...\wj*, \+w ...\+w*, etc.
    private func stripUSFMInlineMarkers(_ text: String) -> String {
        var result = text

        // Remove character markers and their closing counterparts: \add ...\add*  → content kept
        // Pattern: \marker text\marker* — remove the markers, keep text
        let closingPattern = "\\\\\\+?[a-z]+\\d?\\*"
        if let regex = try? NSRegularExpression(pattern: closingPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove opening character markers: \add, \wj, \nd, \w, etc.
        // But NOT \v or \c which are structural
        let openingPattern = "\\\\\\+?(?:add|wj|nd|w|qt|sig|sls|it|bd|bdit|em|sc|no|sup|k|ior|rq|qs|qac|tl|litl|lik|liv|ord|pn|png|rb|pro|fqa|fq|fk|fl|fw|fp|fv|ft|fr|fe|xo|xk|xt|xq|xta|fig|jmp|ref)\\d?\\s?"
        if let regex = try? NSRegularExpression(pattern: openingPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove footnote content entirely: \f ... \f*
        let footnotePattern = "\\\\f\\s.*?\\\\f\\*"
        if let regex = try? NSRegularExpression(pattern: footnotePattern, options: .dotMatchesLineSeparators) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove cross-reference content: \x ... \x*
        let xrefPattern = "\\\\x\\s.*?\\\\x\\*"
        if let regex = try? NSRegularExpression(pattern: xrefPattern, options: .dotMatchesLineSeparators) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove remaining backslash markers that weren't caught
        let remainingPattern = "\\\\[a-z]+\\d?\\*?"
        if let regex = try? NSRegularExpression(pattern: remainingPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove pipe attributes (word-level): |attr="value"
        let attrPattern = "\\|[^\\s]*"
        if let regex = try? NSRegularExpression(pattern: attrPattern) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Clean up whitespace
        result = result.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        return result
    }

    private func deriveAbbreviation(from name: String) -> String {
        let words = name.split(separator: " ")
        if words.count == 1 {
            return String(name.prefix(6)).uppercased()
        }
        return words.map { String($0.prefix(1)) }.joined().uppercased()
    }
}

// MARK: - USFM rich-run extraction (red-letter / Strong's / added words)

/// Turns raw USFM verse markup into GOAT `runs[]`: `\wj…\wj*` → woc,
/// `\add…\add*` → add, `\nd…\nd*` → divineName, `\w word|strong="…"\w*` → Strong's.
/// Footnotes/cross-refs are dropped from the run text (they're not verse words).
nonisolated enum USFMRich {
    static func parse(_ raw: String, plain: String) -> (runs: [VerseRun]?, woc: Bool) {
        guard raw.contains("\\wj") || raw.contains("\\nd") || raw.contains("\\add") || raw.contains("\\w ") || raw.contains("\\+w ") else {
            return (nil, false)
        }
        // Strip footnotes/cross-refs first — their inner text isn't scripture.
        var s = raw
        for pat in ["\\\\f\\s.*?\\\\f\\*", "\\\\x\\s.*?\\\\x\\*"] {
            if let re = try? NSRegularExpression(pattern: pat, options: .dotMatchesLineSeparators) {
                s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
            }
        }

        // Walk character markers, tracking the active "kind".
        var runs: [VerseRun] = []
        var woc = false
        var buf = ""
        var kindStack: [String] = []

        // `\w word|strong="…" x-morph="…"\w*` word-level annotation state.
        var inW = false
        var wWord = ""
        var wAttr = ""
        var inWAttr = false

        func flush() {
            // Keep boundary spaces so runs concatenate back to the full verse;
            // only skip purely-empty segments.
            let cleaned = clean(buf)
            if !cleaned.trimmingCharacters(in: .whitespaces).isEmpty {
                runs.append(VerseRun(text: cleaned, kind: kindStack.last ?? "plain"))
            }
            buf = ""
        }
        func flushWord() {
            let cleaned = clean(wWord)
            if !cleaned.trimmingCharacters(in: .whitespaces).isEmpty {
                let (strong, morph) = parseWordAttrs(wAttr)
                runs.append(VerseRun(text: cleaned, kind: kindStack.last ?? "plain", strong: strong, morph: morph))
            }
            wWord = ""; wAttr = ""; inWAttr = false; inW = false
        }
        let markerKind: [String: String] = ["wj": "woc", "nd": "divineName", "add": "add"]
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\\" {
                // read marker name (drop a leading "+" for nested markers)
                var j = s.index(after: i)
                if j < s.endIndex, s[j] == "+" { j = s.index(after: j) }
                var name = ""
                while j < s.endIndex, s[j].isLetter || s[j].isNumber { name.append(s[j]); j = s.index(after: j) }
                let closing = (j < s.endIndex && s[j] == "*")
                if closing { j = s.index(after: j) }
                let base = name.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789"))
                if base == "w" {
                    if closing {
                        flushWord()
                    } else {
                        flush(); inW = true; wWord = ""; wAttr = ""; inWAttr = false
                    }
                } else if let kind = markerKind[base] {
                    if inW { flushWord() }
                    flush()
                    if closing {
                        if kindStack.last == kind { kindStack.removeLast() }
                    } else {
                        kindStack.append(kind); if kind == "woc" { woc = true }
                    }
                }
                // skip a single following space that USFM puts after a marker
                if j < s.endIndex, s[j] == " " {
                    if inW { wWord.append(" ") } else { buf.append(" ") }
                    j = s.index(after: j)
                }
                i = j
            } else if inW {
                if s[i] == "|" { inWAttr = true }
                else if inWAttr { wAttr.append(s[i]) }
                else { wWord.append(s[i]) }
                i = s.index(after: i)
            } else {
                buf.append(s[i]); i = s.index(after: i)
            }
        }
        if inW { flushWord() }
        flush()

        // Collapse to nil unless there's a genuinely non-plain or annotated run.
        let meaningful = runs.contains { $0.kind != "plain" || $0.strong != nil } && runs.count > 0
        return (meaningful ? runs : nil, woc)
    }

    /// Pull a Strong's number + morphology from a `\w` word's pipe attributes:
    /// `strong="G3056"`, `lemma="…"`, `x-strong="…"`, `x-morph="…"`, or a bare `H1234`.
    private static func parseWordAttrs(_ attr: String) -> (String?, String?) {
        func capture(_ key: String) -> String? {
            let pattern = "\(key)=\"([^\"]+)\""
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let m = re.firstMatch(in: attr, range: NSRange(attr.startIndex..., in: attr)),
                  m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: attr) else { return nil }
            return String(attr[r])
        }
        var strong = capture("strong") ?? capture("x-strong") ?? capture("lemma")
        let morph = capture("x-morph") ?? capture("morph")
        if strong == nil {
            let bare = attr.trimmingCharacters(in: .whitespaces)
            if let f = bare.uppercased().first, (f == "G" || f == "H"),
               bare.count > 1, bare.dropFirst().allSatisfy({ $0.isNumber }) {
                strong = bare.uppercased()
            }
        }
        if let s = strong, let first = s.split(separator: " ").first { strong = String(first).uppercased() }
        return (strong, morph)
    }

    /// Remove leftover pipe attributes and stray markers from a run's text.
    /// Preserves boundary spaces so runs concatenate back to the full verse.
    private static func clean(_ t: String) -> String {
        var r = t
        for pat in ["\\|[^\\\\]*?(?=\\\\|$)", "\\\\[+a-z]+\\d?\\*?"] {
            if let re = try? NSRegularExpression(pattern: pat) {
                r = re.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..., in: r), withTemplate: "")
            }
        }
        return r.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
    }
}

// MARK: - USFM footnote / cross-reference extraction

/// Pulls `\f …\f*` / `\fe …\fe*` footnotes and `\x …\x*` cross-references out of a
/// raw USFM verse, mapping them to the GOAT `BibleFootnote` / `BibleCrossRef` types.
nonisolated enum USFMNotes {
    static func footnotes(_ raw: String) -> [BibleFootnote] {
        var notes: [BibleFootnote] = []
        for marker in ["f", "fe"] {
            for body in spans(raw, marker: marker) {
                // First token is the caller (`+`, `-`, or a letter); the rest is the note.
                var caller = ""
                var rest = body.trimmingCharacters(in: .whitespaces)
                if let first = rest.first, first == "+" || first == "-" || (first.isLetter && rest.dropFirst().first == " ") {
                    caller = String(first)
                    rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                let text = stripInner(rest)
                if !text.isEmpty { notes.append(BibleFootnote(marker: caller, text: text)) }
            }
        }
        return notes
    }

    static func crossRefs(_ raw: String) -> [BibleCrossRef] {
        var refs: [BibleCrossRef] = []
        for body in spans(raw, marker: "x") {
            // Targets live in `\xt …` segments; split each on ; and ,
            var targets: [String] = []
            if let re = try? NSRegularExpression(pattern: "\\\\xt\\s(.*?)(?=\\\\x|$)", options: .dotMatchesLineSeparators) {
                let ns = body as NSString
                re.enumerateMatches(in: body, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
                    guard let m = m, m.numberOfRanges > 1 else { return }
                    let seg = stripInner(ns.substring(with: m.range(at: 1)))
                    targets.append(contentsOf: seg.split(whereSeparator: { $0 == ";" || $0 == "," })
                        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                }
            }
            if targets.isEmpty {
                let fallback = stripInner(body)
                targets = fallback.split(whereSeparator: { $0 == ";" || $0 == "," })
                    .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            }
            if !targets.isEmpty { refs.append(BibleCrossRef(targets: targets)) }
        }
        return refs
    }

    /// Inner bodies of every `\marker …\marker*` span in `raw`.
    private static func spans(_ raw: String, marker: String) -> [String] {
        let pattern = "\\\\\(marker)\\s(.*?)\\\\\(marker)\\*"
        guard let re = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) else { return [] }
        let ns = raw as NSString
        var out: [String] = []
        re.enumerateMatches(in: raw, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m = m, m.numberOfRanges > 1 else { return }
            out.append(ns.substring(with: m.range(at: 1)))
        }
        return out
    }

    /// Strip inner USFM markers (`\fr`, `\ft`, `\xo`, `\xt`, …) and pipe attributes,
    /// keeping the human-readable text.
    private static func stripInner(_ t: String) -> String {
        var r = t
        for pat in ["\\\\\\+?[a-z]+\\d?\\*?", "\\|[^\\s]*"] {
            if let re = try? NSRegularExpression(pattern: pat) {
                r = re.stringByReplacingMatches(in: r, range: NSRange(r.startIndex..., in: r), withTemplate: "")
            }
        }
        return r.replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
