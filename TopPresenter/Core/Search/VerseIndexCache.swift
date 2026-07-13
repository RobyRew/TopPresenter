//
//  VerseIndexCache.swift
//  TopPresenter
//
//  On-disk cache of ONE translation's built verse index (books + verses +
//  token index). Built once — right after import, the first time the module
//  is selected — then every later version switch decodes this file OFF-main
//  with ZERO SwiftData traffic.
//
//  Why it exists: the old per-switch rebuild walked ~31k rows through the
//  @ModelActor builder while the main thread faulted the newly selected
//  module's books/chapters/verses for display. Both share one persistent-store
//  coordinator, so the main thread queued behind the rebuild storm = the
//  version-switch rainbow cursor. A pure file read can't contend with anything.
//

import Foundation

nonisolated struct VerseIndexCache: Codable, Sendable {
    /// Bump when BookIndexEntry / VerseIndexEntry / TokenIndex change shape —
    /// stale files are silently ignored and rebuilt, never migrated.
    static let currentFormat = 1

    var format: Int = VerseIndexCache.currentFormat
    let moduleID: UUID
    let books: [BookIndexEntry]
    let verses: [VerseIndexEntry]
    let tokens: TokenIndex

    // MARK: Disk locations

    static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TopPresenter/VerseIndex", isDirectory: true)
    }

    static func fileURL(moduleID: UUID) -> URL {
        directory.appendingPathComponent("\(moduleID.uuidString).plist")
    }

    // MARK: IO — pure file + Codable, safe from any executor

    static func load(moduleID: UUID) -> VerseIndexCache? {
        guard let data = try? Data(contentsOf: fileURL(moduleID: moduleID)),
              let cache = try? PropertyListDecoder().decode(VerseIndexCache.self, from: data),
              cache.format == currentFormat,
              cache.moduleID == moduleID,
              !cache.verses.isEmpty
        else { return nil }
        return cache
    }

    func save() {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(self) else { return }
        try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL(moduleID: moduleID), options: .atomic)
    }

    static func delete(moduleID: UUID) {
        try? FileManager.default.removeItem(at: fileURL(moduleID: moduleID))
    }

    /// Advanced settings ▸ reindex / delete-all-bibles: wipe every cached index.
    static func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}
