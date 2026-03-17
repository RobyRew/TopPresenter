//
//  DragDropImportHandler.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Identifies what kind of content a dropped file is.
enum DroppedFileCategory {
    case bible(SupportedBibleFormat)
    case song(SupportedSongFormat)
    case unknown

    var displayName: String {
        switch self {
        case .bible(let fmt): return "Bible (\(fmt.displayName))"
        case .song(let fmt): return "Song (\(fmt.displayName))"
        case .unknown: return "Unknown"
        }
    }
}

/// A pending file identified by drag & drop, ready for batch import.
struct PendingImportFile: Identifiable {
    let id = UUID()
    let url: URL
    let category: DroppedFileCategory
    var status: ImportFileStatus = .pending

    var fileName: String { url.lastPathComponent }
}

enum ImportFileStatus: Equatable {
    case pending
    case importing
    case success(String)
    case failed(String)

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .importing: return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .importing: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }
}

/// Service that classifies dropped files and performs batch imports.
final class DragDropImportHandler {

    /// Classify a single file URL into a category.
    static func classify(_ url: URL) -> DroppedFileCategory {
        // Try Bible format detection first
        if let format = ImportService.detectBibleFormat(fileURL: url) {
            return .bible(format)
        }

        // Try Song format detection
        if let format = ImportService.detectSongFormat(fileURL: url) {
            return .song(format)
        }

        // Fallback: guess by extension
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "json":
            return .bible(.topPresenter)
        case "mybible":
            return .bible(.mySword)
        case "usfm", "sfm":
            return .bible(.usfm)
        case "osis":
            return .bible(.osisXML)
        case "zef":
            return .bible(.zefaniaXML)
        default:
            return .unknown
        }
    }

    /// Classify multiple URLs.
    static func classify(_ urls: [URL]) -> [PendingImportFile] {
        urls.map { PendingImportFile(url: $0, category: classify($0)) }
    }

    /// Import all pending Bible files sequentially.
    static func importBibles(
        files: [PendingImportFile],
        modelContext: ModelContext,
        onUpdate: @escaping (UUID, ImportFileStatus) -> Void
    ) async -> [BibleModule] {
        var imported: [BibleModule] = []

        for file in files {
            guard case .bible(let format) = file.category else { continue }

            onUpdate(file.id, .importing)

            do {
                let module = try await ImportService.importBible(
                    fileURL: file.url,
                    format: format,
                    modelContext: modelContext
                )
                imported.append(module)
                onUpdate(file.id, .success(module.name))
            } catch {
                onUpdate(file.id, .failed(error.localizedDescription))
            }
        }

        return imported
    }

    /// Import all pending Song files sequentially.
    static func importSongs(
        files: [PendingImportFile],
        collectionName: String,
        modelContext: ModelContext,
        onUpdate: @escaping (UUID, ImportFileStatus) -> Void
    ) async -> [SongCollection] {
        var collections: [SongCollection] = []

        for file in files {
            guard case .song(let format) = file.category else { continue }

            onUpdate(file.id, .importing)

            do {
                let collection = try await ImportService.importSingleSongFile(
                    fileURL: file.url,
                    format: format,
                    collectionName: collectionName,
                    modelContext: modelContext
                )
                if !collections.contains(where: { $0.id == collection.id }) {
                    collections.append(collection)
                }
                onUpdate(file.id, .success(file.fileName))
            } catch {
                onUpdate(file.id, .failed(error.localizedDescription))
            }
        }

        return collections
    }
}
