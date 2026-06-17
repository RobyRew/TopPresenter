//
//  BibleImportProtocol.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation
import SwiftData

/// Protocol that all Bible format importers must conform to.
/// Implement this protocol to add support for a new Bible file format.
protocol BibleImporter {
    /// The format this importer handles
    var format: SupportedBibleFormat { get }

    /// Parse a Bible file and return a structured result
    func parse(fileURL: URL) async throws -> BibleImportResult
}

// MARK: - Rich verse data (the "GOAT" superset shared by every importer/exporter)

/// One styled segment of a verse. `runs` reconstruct rich text losslessly:
/// red-letter (`woc`), translator-added/italic (`add`), divine name, quotes —
/// each optionally carrying a Strong's number + morphology code.
struct VerseRun: Codable, Equatable {
    var text: String
    /// "plain" | "woc" (words of Christ) | "add" | "divineName" | "quote"
    var kind: String = "plain"
    var strong: String? = nil   // e.g. "G3056" / "H0430"
    var morph: String? = nil    // e.g. "N-NSF"
    var gloss: String? = nil    // interlinear per-word gloss

    init(text: String, kind: String = "plain", strong: String? = nil, morph: String? = nil, gloss: String? = nil) {
        self.text = text; self.kind = kind; self.strong = strong; self.morph = morph; self.gloss = gloss
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "plain"
        strong = try c.decodeIfPresent(String.self, forKey: .strong)
        morph = try c.decodeIfPresent(String.self, forKey: .morph)
        gloss = try c.decodeIfPresent(String.self, forKey: .gloss)
    }
}

/// A pericope/section heading shown before a verse.
struct BibleHeading: Codable, Equatable {
    var beforeVerse: Int
    var level: Int = 1
    var text: String
}

struct BibleFootnote: Codable, Equatable {
    var marker: String = ""
    var text: String
}

struct BibleCrossRef: Codable, Equatable {
    var label: String? = nil
    var targets: [String] = []
}

/// Result of a Bible import operation
struct BibleImportResult {
    let moduleName: String
    let abbreviation: String
    let language: String
    let description: String
    let books: [BibleImportBook]
    var versification: String? = nil   // "kjv" | "lxx" | "vulgate" …
    var canon: String? = nil           // "protestant" | "catholic" | "orthodox"
    // Lossless metadata (any source may populate these; empty/nil when absent).
    var nameLocal: String = ""
    var languageName: String = ""
    var copyright: String = ""
    var about: String = ""             // foreword / introduction essays
    var textSource: String = ""
    var year: Int? = nil
    var direction: String = "ltr"
    var hasWordsOfChrist: Bool = false
    var hasStrongs: Bool = false
    var incomplete: Bool = false
    var extensionsJSON: String? = nil
}

struct BibleImportBook {
    let name: String
    let bookNumber: Int
    let testament: String // "OT" | "NT" | "DC"
    let chapters: [BibleImportChapter]
    var introduction: String? = nil
    var nameEnglish: String = ""
    var abbreviation: String = ""
    var abbreviationEnglish: String = ""
    var expectedChapters: Int = 0
    var extensionsJSON: String? = nil
}

struct BibleImportChapter {
    let chapterNumber: Int
    let verses: [BibleImportVerse]
    var headings: [BibleHeading]? = nil
    var extensionsJSON: String? = nil
}

struct BibleImportVerse {
    let verseNumber: Int
    let text: String
    /// Rich segments (red-letter / italic / Strong's). nil = plain verse.
    var runs: [VerseRun]? = nil
    var footnotes: [BibleFootnote]? = nil
    var crossReferences: [BibleCrossRef]? = nil
    var hasWordsOfChrist: Bool = false
    var poetryIndent: Int? = nil
    var gloss: String = ""
    var extensionsJSON: String? = nil

    init(verseNumber: Int, text: String, runs: [VerseRun]? = nil,
         footnotes: [BibleFootnote]? = nil, crossReferences: [BibleCrossRef]? = nil,
         hasWordsOfChrist: Bool = false, poetryIndent: Int? = nil,
         gloss: String = "", extensionsJSON: String? = nil) {
        self.verseNumber = verseNumber
        self.text = text
        self.runs = runs
        self.footnotes = footnotes
        self.crossReferences = crossReferences
        self.hasWordsOfChrist = hasWordsOfChrist
        self.poetryIndent = poetryIndent
        self.gloss = gloss
        self.extensionsJSON = extensionsJSON
    }
}

/// Errors that can occur during Bible import
enum BibleImportError: LocalizedError {
    case fileNotFound
    case invalidFormat(String)
    case parsingFailed(String)
    case unsupportedFormat(String)
    case emptyFile

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return String(localized: "File not found.", comment: "Import error")
        case .invalidFormat(let detail):
            return String(localized: "Invalid file format: \(detail)", comment: "Import error")
        case .parsingFailed(let detail):
            return String(localized: "Parsing failed: \(detail)", comment: "Import error")
        case .unsupportedFormat(let format):
            return String(localized: "Unsupported format: \(format)", comment: "Import error")
        case .emptyFile:
            return String(localized: "The file is empty.", comment: "Import error")
        }
    }
}
