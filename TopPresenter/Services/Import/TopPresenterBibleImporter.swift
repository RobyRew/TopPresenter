//
//  TopPresenterBibleImporter.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import Foundation

/// Importer for TopPresenter native JSON format.
/// This is the priority format, exported by the eBiblia Scraper userscript.
///
/// Schema:
/// ```json
/// {
///   "schemaVersion": "1.0.0",
///   "format": "TopPresenter Bible",
///   "translation": { "code", "name", "nameLocal", "language", ... },
///   "exportInfo": { ... },
///   "books": [{
///     "number", "name", "nameEnglish", "abbreviation", "testament",
///     "chapters": [{
///       "number",
///       "headings": [{ "beforeVerse", "level", "text" }],
///       "verses": [{
///         "number", "text", "rawHtml?", "textNormalized?",
///         "crossReferences?": [{ "references": [...] }],
///         "footnotes?": [{ "text", "html" }]
///       }]
///     }]
///   }]
/// }
/// ```
nonisolated final class TopPresenterBibleImporter: BibleImporter {
    let format: SupportedBibleFormat = .topPresenter

    func parse(fileURL: URL) async throws -> BibleImportResult {
        let data = try Data(contentsOf: fileURL)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BibleImportError.invalidFormat("Not a valid JSON object")
        }

        // Validate format — allow parsing if books array exists even without exact format marker
        if let formatStr = json["format"] as? String, formatStr != "TopPresenter Bible" {
            if json["books"] == nil {
                throw BibleImportError.invalidFormat("Not a TopPresenter Bible JSON file")
            }
        } else if json["format"] == nil && json["books"] == nil {
            throw BibleImportError.invalidFormat("Missing 'books' array — not a TopPresenter Bible JSON")
        }

        // Extract translation metadata
        let translation = json["translation"] as? [String: Any] ?? [:]
        let moduleName = translation["name"] as? String
            ?? translation["nameLocal"] as? String
            ?? translation["code"] as? String
            ?? fileURL.deletingPathExtension().lastPathComponent
        let abbreviation = translation["code"] as? String ?? ""
        let language = translation["language"] as? String ?? "en"
        let copyright = translation["copyright"] as? String ?? ""
        let description = translation["description"] as? String ?? copyright

        // Parse books
        guard let booksArray = json["books"] as? [[String: Any]] else {
            throw BibleImportError.parsingFailed("Missing or invalid 'books' array")
        }

        if booksArray.isEmpty {
            throw BibleImportError.emptyFile
        }

        var importBooks: [BibleImportBook] = []

        for bookJSON in booksArray {
            guard let bookNumber = bookJSON["number"] as? Int,
                  let bookName = bookJSON["name"] as? String ?? bookJSON["nameEnglish"] as? String,
                  let chaptersArray = bookJSON["chapters"] as? [[String: Any]] else {
                continue
            }

            let testament = (bookJSON["testament"] as? String) ?? (bookNumber <= 39 ? "OT" : "NT")
            // Category from export — used for display; falls back to computed from bookNumber
            _ = bookJSON["category"] as? String

            var importChapters: [BibleImportChapter] = []

            for chapterJSON in chaptersArray {
                guard let chapterNumber = chapterJSON["number"] as? Int,
                      let versesArray = chapterJSON["verses"] as? [[String: Any]] else {
                    continue
                }

                var importVerses: [BibleImportVerse] = []

                for verseJSON in versesArray {
                    guard let verseNumber = verseJSON["number"] as? Int,
                          let verseText = verseJSON["text"] as? String else {
                        continue
                    }

                    // Use clean text (without HTML markers)
                    let cleanText = verseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if cleanText.isEmpty { continue }

                    // GOAT v2: rich segments + footnotes + cross-references.
                    let runs = Self.decodeRuns(verseJSON["runs"])
                    let woc = (verseJSON["hasWordsOfChrist"] as? Bool ?? false)
                        || runs.contains { $0.kind == "woc" }

                    importVerses.append(BibleImportVerse(
                        verseNumber: verseNumber,
                        text: cleanText,
                        runs: runs.isEmpty ? nil : runs,
                        footnotes: Self.decodeFootnotes(verseJSON["footnotes"]),
                        crossReferences: Self.decodeCrossRefs(verseJSON["crossReferences"]),
                        hasWordsOfChrist: woc,
                        poetryIndent: verseJSON["poetryIndent"] as? Int,
                        gloss: (verseJSON["gloss"] as? String) ?? "",
                        extensionsJSON: Self.encodeExtensions(verseJSON["_extensions"])
                    ))
                }

                if !importVerses.isEmpty {
                    importChapters.append(BibleImportChapter(
                        chapterNumber: chapterNumber,
                        verses: importVerses,
                        headings: Self.decodeHeadings(chapterJSON["headings"]),
                        extensionsJSON: Self.encodeExtensions(chapterJSON["_extensions"])
                    ))
                }
            }

            if !importChapters.isEmpty {
                importBooks.append(BibleImportBook(
                    name: bookName,
                    bookNumber: bookNumber,
                    testament: testament,
                    chapters: importChapters,
                    introduction: bookJSON["introduction"] as? String,
                    nameEnglish: (bookJSON["nameEnglish"] as? String) ?? "",
                    abbreviation: (bookJSON["abbreviation"] as? String) ?? "",
                    abbreviationEnglish: (bookJSON["abbreviationEnglish"] as? String) ?? "",
                    expectedChapters: (bookJSON["expectedChapters"] as? Int) ?? 0,
                    extensionsJSON: Self.encodeExtensions(bookJSON["_extensions"])
                ))
            }
        }

        guard !importBooks.isEmpty else {
            throw BibleImportError.parsingFailed("No books could be parsed from the JSON")
        }

        // Year may arrive as Int or numeric String.
        let year = (translation["year"] as? Int) ?? Int((translation["year"] as? String) ?? "")

        var result = BibleImportResult(
            moduleName: moduleName,
            abbreviation: abbreviation,
            language: language,
            description: description,
            books: importBooks,
            versification: translation["versification"] as? String,
            canon: translation["canon"] as? String
        )
        result.nameLocal = (translation["nameLocal"] as? String) ?? ""
        result.languageName = (translation["languageName"] as? String) ?? ""
        result.copyright = copyright
        result.about = (translation["about"] as? String) ?? ""
        result.textSource = (translation["source"] as? String) ?? ""
        result.year = year
        result.direction = (translation["direction"] as? String) ?? "ltr"
        result.hasWordsOfChrist = (translation["hasWordsOfChrist"] as? Bool) ?? false
        result.hasStrongs = (translation["hasStrongs"] as? Bool) ?? false
        result.incomplete = (translation["incomplete"] as? Bool) ?? false
        result.extensionsJSON = Self.encodeExtensions(json["_extensions"])
        return result
    }

    // MARK: - Rich-field decoders (tolerant of missing/partial data)

    private static func decodeRuns(_ raw: Any?) -> [VerseRun] {
        guard let arr = raw as? [[String: Any]] else { return [] }
        return arr.compactMap { r in
            guard let t = r["text"] as? String, !t.isEmpty else { return nil }
            return VerseRun(
                text: t,
                kind: (r["kind"] as? String) ?? "plain",
                strong: r["strong"] as? String,
                morph: r["morph"] as? String,
                gloss: r["gloss"] as? String
            )
        }
    }

    /// Re-serialize an `_extensions` object to a compact JSON string (nil when empty).
    private static func encodeExtensions(_ raw: Any?) -> String? {
        guard let obj = raw as? [String: Any], !obj.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    private static func decodeFootnotes(_ raw: Any?) -> [BibleFootnote]? {
        guard let arr = raw as? [[String: Any]] else { return nil }
        let notes = arr.compactMap { n -> BibleFootnote? in
            guard let t = n["text"] as? String, !t.isEmpty else { return nil }
            return BibleFootnote(marker: (n["marker"] as? String) ?? "", text: t)
        }
        return notes.isEmpty ? nil : notes
    }

    private static func decodeCrossRefs(_ raw: Any?) -> [BibleCrossRef]? {
        guard let arr = raw as? [[String: Any]] else { return nil }
        let refs = arr.compactMap { r -> BibleCrossRef? in
            // Accept {targets:[…]} or {references:[…]} (eBiblia v1 shape).
            let targets = (r["targets"] as? [String]) ?? (r["references"] as? [String]) ?? []
            guard !targets.isEmpty else { return nil }
            return BibleCrossRef(label: r["label"] as? String, targets: targets)
        }
        return refs.isEmpty ? nil : refs
    }

    private static func decodeHeadings(_ raw: Any?) -> [BibleHeading]? {
        guard let arr = raw as? [[String: Any]] else { return nil }
        let hs = arr.compactMap { h -> BibleHeading? in
            guard let t = h["text"] as? String, !t.isEmpty else { return nil }
            return BibleHeading(
                beforeVerse: (h["beforeVerse"] as? Int) ?? 1,
                level: (h["level"] as? Int) ?? 1,
                text: t
            )
        }
        return hs.isEmpty ? nil : hs
    }
}
