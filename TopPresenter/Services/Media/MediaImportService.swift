//
//  MediaImportService.swift
//  TopPresenter
//
//  The one way media enters the library.
//
//  There were two, and they disagreed about what importing media means. The
//  drop handler made a bitmap thumbnail for images and nothing for video or
//  audio, and never read a duration. The Media tab's own picker used the async
//  thumbnail factory (which handles all three) and backfilled durations. So a
//  clip dragged in and the same clip picked from the panel produced different
//  library rows.
//
//  Neither checked whether the file was already there. Media was the only kind
//  with no duplicate check at all, so the same photo could be imported without
//  limit — and each copy carried its own thumbnail, so the grid filled with
//  identical tiles.
//
//  Files are REFERENCED, never copied: a security-scoped bookmark plus the
//  path. That is why "Reveal in Finder" is the export story for media, and why
//  identity is (path, name, size) rather than a content hash — hashing multi-GB
//  video on import would beach-ball the app.
//

import Foundation
import SwiftData

@MainActor
enum MediaImportService {

    struct SkippedItem: Sendable {
        let url: URL
        let matchedOn: String
    }

    struct Outcome {
        var imported: [MediaItem] = []
        var skipped: [SkippedItem] = []
        /// Files whose extension is not media at all. Never silently swallowed.
        var unsupported: [URL] = []

        var isEmpty: Bool { imported.isEmpty && skipped.isEmpty && unsupported.isEmpty }
    }

    /// Import media files, skipping ones already in the library.
    ///
    /// `policy` accepts only `.skip` and `.keepBoth` (`DuplicatePolicy.allowed(for: .media)`):
    /// asking per photo would make a 200-file import unusable, and replacing a
    /// reference to a file that has not moved would mean nothing.
    @discardableResult
    static func importMedia(
        urls: [URL],
        modelContext: ModelContext,
        policy: DuplicatePolicy = .skip,
        onUpdate: (URL, ImportFileStatus) -> Void = { _, _ in }
    ) -> Outcome {
        var outcome = Outcome()
        // Built once: the library's identities do not change while we import,
        // except for what we add, which is appended as we go.
        var existing = (try? modelContext.fetch(FetchDescriptor<MediaItem>()))?.map(identity(of:)) ?? []

        for url in urls {
            guard let kind = MediaKind.classify(extension: url.pathExtension) else {
                outcome.unsupported.append(url)
                continue
            }
            onUpdate(url, .importing)

            let incoming = identity(of: url)
            if policy != .keepBoth {
                let verdict = DuplicateResolver.verdict(for: incoming, against: existing)
                if case .identical(let match) = verdict {
                    outcome.skipped.append(SkippedItem(url: url, matchedOn: match.matchedOn))
                    onUpdate(url, .success(String(localized: "\(url.lastPathComponent) — already in the library",
                                                  comment: "Media import status")))
                    continue
                }
            }

            let item = MediaItem(name: url.lastPathComponent, filePath: url.path, mediaType: kind.rawValue)
            modelContext.insert(item)
            item.createBookmark(from: url)

            // Thumbnail and duration are probed asynchronously so a big import
            // never blocks the UI; the grid fills in as they land.
            Task { @MainActor in
                item.thumbnailData = await MediaThumbnailFactory.thumbnailData(for: url, kind: kind)
                try? modelContext.save()
            }
            MediaPresenter.backfillDurationIfNeeded(item, url: url)

            existing.append(incoming)
            outcome.imported.append(item)
            onUpdate(url, .success(url.lastPathComponent))
        }

        if !outcome.imported.isEmpty {
            try? modelContext.save()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
        return outcome
    }

    // MARK: - Identity

    static func identity(of item: MediaItem) -> MediaIdentity {
        MediaIdentity(resolvedPath: item.filePath,
                      filename: item.name,
                      byteSize: byteSize(atPath: item.filePath))
    }

    static func identity(of url: URL) -> MediaIdentity {
        MediaIdentity(resolvedPath: url.path,
                      filename: url.lastPathComponent,
                      byteSize: byteSize(atPath: url.path))
    }

    /// 0 when the file is gone. The path rule still matches on it; the
    /// name+size rule deliberately will not, since two missing files would
    /// otherwise look like the same one.
    private static func byteSize(atPath path: String) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) as? Int ?? 0
    }
}
