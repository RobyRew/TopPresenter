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

/// Result of a Bible import operation
struct BibleImportResult {
    let moduleName: String
    let abbreviation: String
    let language: String
    let description: String
    let books: [BibleImportBook]
}

struct BibleImportBook {
    let name: String
    let bookNumber: Int
    let testament: String // "OT" or "NT"
    let chapters: [BibleImportChapter]
}

struct BibleImportChapter {
    let chapterNumber: Int
    let verses: [BibleImportVerse]
}

struct BibleImportVerse {
    let verseNumber: Int
    let text: String
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
