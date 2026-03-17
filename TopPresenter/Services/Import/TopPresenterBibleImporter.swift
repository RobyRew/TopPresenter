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
final class TopPresenterBibleImporter: BibleImporter {
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

                    importVerses.append(BibleImportVerse(
                        verseNumber: verseNumber,
                        text: cleanText
                    ))
                }

                if !importVerses.isEmpty {
                    importChapters.append(BibleImportChapter(
                        chapterNumber: chapterNumber,
                        verses: importVerses
                    ))
                }
            }

            if !importChapters.isEmpty {
                importBooks.append(BibleImportBook(
                    name: bookName,
                    bookNumber: bookNumber,
                    testament: testament,
                    chapters: importChapters
                ))
            }
        }

        guard !importBooks.isEmpty else {
            throw BibleImportError.parsingFailed("No books could be parsed from the JSON")
        }

        return BibleImportResult(
            moduleName: moduleName,
            abbreviation: abbreviation,
            language: language,
            description: description,
            books: importBooks
        )
    }
}
