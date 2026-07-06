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
enum DroppedFileCategory: Sendable {
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
struct PendingImportFile: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let category: DroppedFileCategory
    var status: ImportFileStatus = .pending

    var fileName: String { url.lastPathComponent }
}

enum ImportFileStatus: Equatable, Sendable {
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

/// Known media file extensions — nonisolated: immutable Sendable constants read by
/// the background classification chain (the default MainActor isolation would
/// otherwise actor-bind them).
private enum MediaExtensions {
    nonisolated static let image = Set(["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp", "svg", "ico"])
    nonisolated static let audio = Set(["mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "ogg", "wma", "opus"])
    nonisolated static let video = Set(["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm", "mpg", "mpeg", "flv"])
    nonisolated static let all = image.union(audio).union(video)
}

/// Service that classifies dropped files and performs batch imports.
final class DragDropImportHandler {

    /// Bible + Song file extensions, lowercased. Used to pre-filter the folder
    /// walk so we never open/read files we can't use here — e.g. multi-GB `.LRF`
    /// drone footage (or any video/image) sitting in a Documents tree, which
    /// would otherwise beach-ball the app and spam AppleFSCompression. Media is
    /// intentionally excluded: this walk feeds the Bible/Song import flow.
    nonisolated static let bibleSongExtensions: Set<String> = {
        var exts = Set<String>()
        for fmt in SupportedBibleFormat.allCases { exts.formUnion(fmt.fileExtensions.map { $0.lowercased() }) }
        for fmt in SupportedSongFormat.allCases { exts.formUnion(fmt.fileExtensions.map { $0.lowercased() }) }
        return exts
    }()

    /// True when a file's extension is a Bible/Song type we can import. Folders
    /// are handled separately (recursed / treated as a USFM Bible).
    /// The whole classification chain below is `nonisolated`: pure file inspection
    /// that runs on a background task (Task.detached) so a big folder walk never
    /// blocks the UI — with the project's default MainActor isolation it would
    /// otherwise be actor-bound (Swift 6 error).
    nonisolated static func isImportableFile(_ url: URL) -> Bool {
        bibleSongExtensions.contains(url.pathExtension.lowercased())
    }

    /// UTTypes for the Bible + Song import panels, so the open panel greys out
    /// everything else. Folders stay selectable (`canChooseDirectories`), so a
    /// USFM folder or a tree of `.json` Bibles can still be picked.
    static var bibleSongContentTypes: [UTType] {
        var exts = Set<String>()
        for fmt in SupportedBibleFormat.allCases { exts.formUnion(fmt.fileExtensions.map { $0.lowercased() }) }
        for fmt in SupportedSongFormat.allCases { exts.formUnion(fmt.fileExtensions.map { $0.lowercased() }) }
        return exts.compactMap { UTType(filenameExtension: $0) }
    }

    /// Classify a single file URL into a category.
    nonisolated static func classify(_ url: URL) -> DroppedFileCategory {
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
    nonisolated static func classify(_ urls: [URL]) -> [PendingImportFile] {
        urls.map { PendingImportFile(url: $0, category: classify($0)) }
    }

    /// Expand a mixed selection of files and folders into individual importable
    /// sources, recursing through subfolders. Semantics:
    ///   • a file → itself
    ///   • a folder of per-book `.usfm`/`.sfm` files → kept whole (that IS one
    ///     USFM Bible), not split
    ///   • any other folder (e.g. a language folder of `.json` Bibles, or a tree
    ///     of them) → recursed; every contained file/USFM-folder is collected
    /// Hidden files and macOS junk (.DS_Store) are skipped. Deduplicated, sorted.
    nonisolated static func expandToImportableFiles(_ urls: [URL]) -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        var seen = Set<String>()
        func add(_ u: URL) { let p = u.standardizedFileURL.path; if seen.insert(p).inserted { out.append(u) } }
        func walk(_ url: URL, depth: Int) {
            guard depth < 8 else { return }   // guard against pathological trees
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return }
            if !isDir.boolValue {
                if url.lastPathComponent.hasPrefix(".") { return }
                // Only collect files we can actually import. This is what keeps a
                // huge Documents tree (drone footage, archives, …) from being read.
                guard isImportableFile(url) else { return }
                add(url); return
            }
            // A USFM Bible is a folder of per-book files → one source, kept whole.
            if ImportService.detectBibleFormat(fileURL: url) == .usfm { add(url); return }
            // Otherwise recurse into the folder's children.
            let children = (try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
                walk(child, depth: depth + 1)
            }
        }
        for u in urls { walk(u, depth: 0) }
        return out
    }

    /// Expand + classify a mixed file/folder selection, keeping only the ones we
    /// can actually import (drops `.unknown`).
    nonisolated static func classifyExpanded(_ urls: [URL]) -> [PendingImportFile] {
        classify(expandToImportableFiles(urls)).filter {
            if case .unknown = $0.category { return false }
            return true
        }
    }

    // Batch Bible imports route through BackgroundImportActor (own ModelContext,
    // off-main) — see Services/Import/BackgroundImportActor.swift.

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
