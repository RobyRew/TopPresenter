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
    case session
    case theme
    case slides
    case unknown

    var displayName: String {
        switch self {
        case .bible(let fmt): return "Bible (\(fmt.displayName))"
        case .song(let fmt): return "Song (\(fmt.displayName))"
        case .media(let type): return "Media (\(type))"
        case .session: return "Session"
        case .theme: return "Theme"
        case .slides: return "Slides"
        case .unknown: return "Unknown"
        }
    }

    /// Which library this lands in — the bridge between the drop classifier and
    /// `ImportCatalog`, so a caller can ask for one kind without re-deriving
    /// what "a Bible file" means.
    ///
    /// nonisolated because the classification chain runs off-main; the enum's
    /// other members are UI-facing and stay on the main actor.
    nonisolated var kind: ImportKind? {
        switch self {
        case .bible: return .bible
        case .song: return .song
        case .media: return .media
        case .session: return .session
        case .theme: return .theme
        case .slides: return .slides
        case .unknown: return nil
        }
    }
}

/// A pending file identified by drag & drop, ready for batch import.
struct PendingImportFile: Identifiable, Sendable {
    /// Settable so a caller can keep its OWN row identity across the hand-off.
    /// The coordinator reports progress by this id, and a freshly minted one
    /// would arrive matching nothing.
    let id: UUID
    let url: URL
    let category: DroppedFileCategory
    var status: ImportFileStatus = .pending

    nonisolated init(url: URL, category: DroppedFileCategory, status: ImportFileStatus = .pending, id: UUID = UUID()) {
        self.id = id
        self.url = url
        self.category = category
        self.status = status
    }

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

/// Service that classifies dropped files and performs batch imports.
final class DragDropImportHandler {

    /// UTTypes for an import panel, so it greys out what we cannot read.
    /// Folders stay selectable (`canChooseDirectories`), so a USFM folder or a
    /// tree of Bibles can still be picked.
    ///
    /// Derived from `ImportCatalog` — this used to be a third hand-rolled copy
    /// of the extension list, next to the folder walk's and the classifier's.
    static var bibleSongContentTypes: [UTType] { ImportCatalog.contentTypes(for: [.bible, .song]) }

    /// Classify a single file URL into a category.
    nonisolated static func classify(_ url: URL) -> DroppedFileCategory {
        let ext = url.pathExtension.lowercased()

        // The native document types, by extension. Checked first: a .tptheme is
        // a PACKAGE, so anything that inspects it as a file would guess wrong.
        if ext == SessionArchiveService.fileExtension { return .session }
        if ext == "tptheme" { return .theme }

        // Check PowerPoint first (these are songs)
        if ext == "pptx" || ext == "ppt" {
            return .song(.powerPoint)
        }

        // Media, from the ONE media list.
        if let kind = MediaKind.classify(extension: ext) {
            return .media(kind.rawValue)
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
        case TopPresenterFormat.bible.fileExtension:
            return .bible(.topPresenter)
        case TopPresenterFormat.song.fileExtension, TopPresenterFormat.songCollection.fileExtension:
            return .song(.topPresenterJSON)
        case TopPresenterFormat.slides.fileExtension:
            return .slides
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

    /// Expand + classify a mixed file/folder selection, keeping only the ones we
    /// can actually import (drops `.unknown`).
    ///
    /// The expansion itself lives in `ImportScanner` now: it sees every kind we
    /// support rather than Bibles and songs only, probes extensionless files,
    /// and reports when it stopped early instead of going quiet.
    /// `keeping` narrows the result to the kinds the CALLER can act on. The
    /// scan itself always sees everything — that is the fix — but the Bible
    /// tab's picker still hands back Bibles and songs, not the photos that
    /// happened to be sitting in the same folder.
    nonisolated static func classifyExpanded(
        _ urls: [URL],
        keeping kinds: Set<ImportKind> = Set(ImportKind.allCases)
    ) -> [PendingImportFile] {
        classify(ImportScanner.scan(urls).files).filter {
            guard let kind = $0.category.kind else { return false }
            return kinds.contains(kind)
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
}
