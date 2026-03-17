//
//  SongImportProtocol.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

/// Protocol that all Song format importers must conform to.
/// Implement this protocol to add support for a new song file format.
protocol SongImporter {
    /// The format this importer handles
    var format: SupportedSongFormat { get }

    /// Parse a single song file and return a structured result
    func parse(fileURL: URL) async throws -> SongImportResult

    /// Parse a directory of song files (for formats that use one file per song)
    func parseDirectory(directoryURL: URL) async throws -> [SongImportResult]
}

/// Default implementation for directory parsing
extension SongImporter {
    func parseDirectory(directoryURL: URL) async throws -> [SongImportResult] {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        var results: [SongImportResult] = []
        for fileURL in contents {
            if format.fileExtensions.contains(fileURL.pathExtension.lowercased()) ||
               fileURL.pathExtension.isEmpty {
                do {
                    let result = try await parse(fileURL: fileURL)
                    results.append(result)
                } catch {
                    // Skip files that can't be parsed
                    continue
                }
            }
        }
        return results
    }
}

/// Result of a song import operation
struct SongImportResult {
    let title: String
    let author: String
    let copyright: String
    let ccliNumber: String
    let key: String
    let tempo: String
    let songNumber: String
    let tags: String
    let verses: [SongImportVerse]
}

struct SongImportVerse {
    let label: String
    let verseType: String  // "verse", "chorus", "bridge", etc.
    let text: String
    let order: Int
}

/// Errors that can occur during song import
enum SongImportError: LocalizedError {
    case fileNotFound
    case invalidFormat(String)
    case parsingFailed(String)
    case emptyFile
    case noSongsFound

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return String(localized: "File not found.", comment: "Import error")
        case .invalidFormat(let detail):
            return String(localized: "Invalid file format: \(detail)", comment: "Import error")
        case .parsingFailed(let detail):
            return String(localized: "Parsing failed: \(detail)", comment: "Import error")
        case .emptyFile:
            return String(localized: "The file is empty.", comment: "Import error")
        case .noSongsFound:
            return String(localized: "No songs were found in the selected location.", comment: "Import error")
        }
    }
}
