//
//  ImportRun.swift
//  TopPresenter
//
//  Per-batch caches for an import, shared by every importer.
//
//  WHY
//  ---
//  Every importer answers "is this already in the library?" the same way: fetch
//  what is there, map it to identities, compare. Done once that is nothing. Done
//  once per FILE, inside a loop over files, it is O(n²) — and it was, in all
//  five importers, invisibly, because the cost only appears at scale:
//
//      slides    16.6 ms/deck at 50 decks  →  125.7 ms at 400   (50s for 400)
//      sessions  25.0 ms/file at 50 files  →  111.3 ms at 400   (45s for 400)
//      themes    10.4 ms/file at 25 files  →   70.7 ms at 200   (14s for 200)
//      songs      5.3 ms/song at 250       →   25.8 ms at 2 000 (4m48s for 5 000)
//
//  The work that has to happen once per run lives here instead: the library's
//  identities, built on first use and then MAINTAINED as the run adds to them,
//  so nothing has to go back and ask.
//
//  Two rules for anything added here:
//
//  1. Every cache must be updated when the run inserts something, or the second
//     file in a batch will not see what the first one imported and duplicates
//     sail through. That is the failure mode this class invites, so each
//     importer's tests assert it directly.
//  2. `nil` means "not primed yet", and every importer must behave identically
//     without a run — a single import passes none and fetches, exactly as before.
//     That is what keeps the fast path an optimisation rather than a second
//     implementation of the rules.
//

import Foundation
import SwiftData

nonisolated final class ImportRun: @unchecked Sendable {

    /// Unchecked because it holds model objects belonging to ONE `ModelContext`
    /// and is used only on that context's thread, for the length of one import.
    /// It is never shared between runs and never escapes one.
    init() {}

    // MARK: Songs — owned by ImportService

    /// Name → `Songbook`, from one fetch. `upsertSongbook` fetched per song, and
    /// a fetch has to merge the context's pending inserts before it can answer.
    var songbooksByName: [String: Songbook]?

    /// Songs to attach to the collection in one assignment at the end. Setting
    /// `song.collection` per song grows the to-many one element at a time.
    var pendingCollectionMembers: [Song] = []

    // MARK: Slides — owned by SlideDeckArchiveService

    /// Content digests of every slide in the library. `importDeck` recomputed
    /// one per existing slide on every deck.
    var slideDigests: Set<String>?

    /// Where the next imported slide goes. Was `max(order) + 1` over a fresh
    /// fetch each time.
    var nextSlideOrder: Int = 0

    // MARK: Sessions — owned by SessionArchiveService

    /// The library's sessions and their identities, kept in step. Parallel
    /// arrays because `DuplicateResolver.verdict` answers with an INDEX, and
    /// that index has to lead back to the schedule it matched.
    var knownSessions: [ServiceSchedule]?
    var knownSessionIdentities: [SessionIdentity] = []

    /// The media a session re-links its items against. `importSession` fetched
    /// the entire media library per session file.
    var localMedia: [MediaItem]?

    // MARK: Themes — owned by PresentationManager

    /// Theme id → payload digest. Building a `ThemeIdentity` JSON-encodes and
    /// hashes the whole payload, and `importTheme` did that for every theme in
    /// the gallery on every package.
    ///
    /// Keyed by id and dropped when a theme is replaced, because a replacement
    /// keeps the id and changes the payload — a stale digest there would let a
    /// genuinely different theme look identical.
    var themeDigests: [UUID: String] = [:]

    // MARK: Media — owned by MediaImportService

    /// The library's media identities, in the order `DuplicateResolver` scans.
    var mediaIdentities: [MediaIdentity]?

    /// A superset test for "could anything match?", so the usual answer — no —
    /// costs a hash lookup instead of a walk over everything imported so far.
    ///
    /// Deliberately a SUPERSET rather than a replacement: `MediaIdentity`
    /// matches on path, or on filename + byte size, and both are exact
    /// equalities, so an identity absent from both sets cannot match anything.
    /// When either set hits, the real linear scan runs and decides — which keeps
    /// the resolver the single source of truth for what counts as a duplicate,
    /// including the order it resolves ties in.
    var mediaPaths: Set<String> = []
    var mediaNameSizes: Set<MediaNameSize> = []

    func noteMedia(_ identity: MediaIdentity) {
        mediaIdentities?.append(identity)
        if !identity.resolvedPath.isEmpty { mediaPaths.insert(identity.resolvedPath) }
        if !identity.filename.isEmpty, identity.byteSize > 0 {
            mediaNameSizes.insert(MediaNameSize(filename: identity.filename, byteSize: identity.byteSize))
        }
    }

    /// True when no existing item can possibly match, so the scan can be skipped.
    func mediaCannotMatch(_ identity: MediaIdentity) -> Bool {
        if !identity.resolvedPath.isEmpty, mediaPaths.contains(identity.resolvedPath) { return false }
        if !identity.filename.isEmpty, identity.byteSize > 0,
           mediaNameSizes.contains(MediaNameSize(filename: identity.filename, byteSize: identity.byteSize)) {
            return false
        }
        return true
    }
}

nonisolated struct MediaNameSize: Hashable {
    var filename: String
    var byteSize: Int
}
