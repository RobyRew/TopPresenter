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
    case media(String)  // "image", "audio", "video"
    case unknown

    var displayName: String {
        switch self {
        case .bible(let fmt): return "Bible (\(fmt.displayName))"
        case .song(let fmt): return "Song (\(fmt.displayName))"
        case .media(let type): return "Media (\(type))"
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

/// Known media file extensions
private enum MediaExtensions {
    static let image = Set(["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg", "ico"])
    static let audio = Set(["mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "ogg", "wma", "opus"])
    static let video = Set(["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm", "mpg", "mpeg", "flv"])
    static let all = image.union(audio).union(video)
}

/// Service that classifies dropped files and performs batch imports.
final class DragDropImportHandler {

    /// Classify a single file URL into a category.
    static func classify(_ url: URL) -> DroppedFileCategory {
        let ext = url.pathExtension.lowercased()

        // Check PowerPoint first (these are songs)
        if ext == "pptx" || ext == "ppt" {
            return .song(.powerPoint)
        }

        // Check media files by extension
        if MediaExtensions.image.contains(ext) {
            return .media("image")
        }
        if MediaExtensions.audio.contains(ext) {
            return .media("audio")
        }
        if MediaExtensions.video.contains(ext) {
            return .media("video")
        }

        // Try Bible format detection (reads file content)
        if let format = ImportService.detectBibleFormat(fileURL: url) {
            return .bible(format)
        }

        // Try Song format detection (reads file content)
        if let format = ImportService.detectSongFormat(fileURL: url) {
            return .song(format)
        }

        // Fallback: guess by extension
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

    /// Import all pending Media files.
    static func importMedia(
        files: [PendingImportFile],
        modelContext: ModelContext,
        onUpdate: @escaping (UUID, ImportFileStatus) -> Void
    ) -> [MediaItem] {
        var imported: [MediaItem] = []

        for file in files {
            guard case .media(let mediaType) = file.category else { continue }

            onUpdate(file.id, .importing)

            let item = MediaItem(
                name: file.url.lastPathComponent,
                filePath: file.url.path,
                mediaType: mediaType
            )

            // Generate thumbnail for images
            if mediaType == "image", let image = NSImage(contentsOf: file.url) {
                let thumbnailSize = NSSize(width: 200, height: 200)
                if let resized = image.resized(to: thumbnailSize) {
                    item.thumbnailData = resized.tiffRepresentation
                }
            }

            modelContext.insert(item)
            item.createBookmark(from: file.url)
            imported.append(item)
            onUpdate(file.id, .success(file.fileName))
        }

        try? modelContext.save()
        return imported
    }
}
