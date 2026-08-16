//
//  LibraryMaintenanceActor.swift
//  TopPresenter
//
//  Bulk deletes, off the main thread, one module at a time.
//
//  WHAT WAS WRONG
//
//  Deleting Bibles ran `modelContext.delete(module)` on the MAIN context, in a
//  loop, followed by a single `save()`. A Bible is ~31 000 verses; seventy of
//  them is over two million rows cascade-deleted inside one transaction, on the
//  thread that draws the window. That is the six-minute beach ball — and the
//  CoreData log said so plainly: a 301 MB store, a 73 000-page freelist, and a
//  vacuum afterwards that had to walk all of it.
//
//  WHAT THIS DOES INSTEAD
//
//  A @ModelActor, so the work happens on its own context and its own thread,
//  and one save PER MODULE rather than one at the end.
//
//  THAT WAS NOT ENOUGH, and the second CoreData log said why: a
//  `wal_checkpoint(TRUNCATE)` and an `incremental_vacuum` after every save. The
//  work had moved off the main thread but had not got smaller — and a checkpoint
//  takes an EXCLUSIVE store lock, so the main thread still stalled on its next
//  read. Off-thread is not the same as out of the way.
//
//  The real cost was never the save. It was building two million Swift objects
//  in order to throw them away: `modelContext.delete(module)` faults in every
//  book, chapter and verse so it can walk the cascade in memory.
//
//  `delete(model:where:)` is an NSBatchDeleteRequest — it runs as SQL and never
//  builds the objects at all. Measured on a real-sized Bible: **7.97 s → 0.17 s**,
//  and it still honours the four-level `.cascade` down to the verses (verified
//  in `BulkDeleteSpike`, because a cascade that quietly stopped short would
//  orphan 31 000 rows per module — a worse bug than being slow).
//
//  Reaching UP from the leaves instead — deleting verses by
//  `$0.chapter?.book?.module?.id` — is not an available fallback: that predicate
//  compiles and then aborts the process. Also in the spike, so nobody tries it.
//

import Foundation
import SwiftData

@ModelActor
actor LibraryMaintenanceActor {

    struct DeleteOutcome: Sendable {
        var deleted = 0
        var failures: [String] = []
        var wasCancelled = false
    }

    /// Delete Bible modules by id, saving after each one.
    ///
    /// By ID, not by object: a `BibleModule` belongs to the context it was
    /// fetched in, and this actor has its own. Passing ids is what keeps the
    /// hand-off honest instead of relying on a model crossing isolation.
    func deleteBibleModules(
        ids: [UUID],
        onProgress: @escaping @MainActor @Sendable (String, Int) -> Void,
        isCancelled: @escaping @MainActor @Sendable () -> Bool
    ) async -> DeleteOutcome {
        var outcome = DeleteOutcome()

        for (index, id) in ids.enumerated() {
            if await isCancelled() {
                outcome.wasCancelled = true
                break
            }
            // The name is read through a fetch that pulls ONE row. Reading it is
            // the only reason this module is ever faulted; the delete below never
            // touches the object.
            let descriptor = FetchDescriptor<BibleModule>(predicate: #Predicate { $0.id == id })
            guard let name = try? modelContext.fetch(descriptor).first?.name else { continue }
            await onProgress(name, index)

            do {
                try modelContext.delete(model: BibleModule.self, where: #Predicate { $0.id == id })
                try modelContext.save()
                outcome.deleted += 1
            } catch {
                outcome.failures.append("\(name) — \(error.localizedDescription)")
            }
        }
        // A batch delete deliberately does NOT update in-memory state, so this
        // actor's own context is still holding rows that no longer exist. The
        // main context is rolled back by the caller for the same reason.
        modelContext.rollback()
        return outcome
    }

    /// Delete every song collection (and its songs) the same way.
    func deleteSongCollections(
        ids: [UUID],
        onProgress: @escaping @MainActor @Sendable (String, Int) -> Void,
        isCancelled: @escaping @MainActor @Sendable () -> Bool
    ) async -> DeleteOutcome {
        var outcome = DeleteOutcome()
        for (index, id) in ids.enumerated() {
            if await isCancelled() {
                outcome.wasCancelled = true
                break
            }
            let descriptor = FetchDescriptor<SongCollection>(predicate: #Predicate { $0.id == id })
            guard let name = try? modelContext.fetch(descriptor).first?.name else { continue }
            await onProgress(name, index)
            do {
                try modelContext.delete(model: SongCollection.self, where: #Predicate { $0.id == id })
                try modelContext.save()
                outcome.deleted += 1
            } catch {
                outcome.failures.append("\(name) — \(error.localizedDescription)")
            }
        }
        modelContext.rollback()
        return outcome
    }

    /// Wipe the whole song library — collections, orphan songs, songbooks.
    ///
    /// The old version of this did it on the MAIN context: three fetch-all
    /// loops calling `delete(_:)` object by object, then one save. A library of
    /// any size makes that the same beach ball the Bibles had, which is exactly
    /// what "I can't imagine for songs how it would be" was pointing at.
    ///
    /// Three batch deletes in dependency order instead. Collections cascade
    /// their songs; whatever is left is genuinely orphaned and swept after;
    /// songbooks go last because `Song.songbook` nullifies rather than
    /// cascades, and nullifying into rows that are already gone is wasted work.
    func deleteAllSongs(
        onProgress: @escaping @MainActor @Sendable (String, Int) -> Void
    ) async -> DeleteOutcome {
        var outcome = DeleteOutcome()
        let steps: [(String, () throws -> Void)] = [
            (String(localized: "Collections", comment: "Delete progress"),
             { try self.modelContext.delete(model: SongCollection.self) }),
            (String(localized: "Songs", comment: "Delete progress"),
             { try self.modelContext.delete(model: Song.self) }),
            (String(localized: "Songbooks", comment: "Delete progress"),
             { try self.modelContext.delete(model: Songbook.self) }),
        ]
        for (index, step) in steps.enumerated() {
            await onProgress(step.0, index)
            do {
                try step.1()
                try modelContext.save()
                outcome.deleted += 1
            } catch {
                outcome.failures.append("\(step.0) — \(error.localizedDescription)")
            }
        }
        return outcome
    }

    struct ExportOutcome: Sendable {
        var exported = 0
        var failures: [String] = []
        var wasCancelled = false
    }

    /// Export Bible modules to a folder, off the main thread.
    ///
    /// Serializing a Bible is the same order of work as importing one — 31 000
    /// verses into JSON — so doing seventy of them on the context that draws
    /// the window beach-balls exactly like the delete did.
    func exportBibleModules(
        ids: [UUID],
        toFolder folder: URL,
        onProgress: @escaping @MainActor @Sendable (String, Int) -> Void,
        onItemProgress: @escaping @MainActor @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @MainActor @Sendable () -> Bool
    ) async -> ExportOutcome {
        var outcome = ExportOutcome()
        for (index, id) in ids.enumerated() {
            if await isCancelled() {
                outcome.wasCancelled = true
                break
            }
            let descriptor = FetchDescriptor<BibleModule>(predicate: #Predicate { $0.id == id })
            guard let module = try? modelContext.fetch(descriptor).first else { continue }
            let name = module.name
            await onProgress(name, index)

            let fileName = ExportNaming.filename(
                module.abbreviation.isEmpty ? module.name : module.abbreviation,
                qualifier: module.language.uppercased(), format: .bible)
            do {
                try await ExportService.exportBible(
                    module: module, format: .topPresenter,
                    to: folder.appendingPathComponent(fileName)
                ) { fraction, _ in
                    MainActor.assumeIsolated { onItemProgress(fraction) }
                }
                outcome.exported += 1
            } catch {
                outcome.failures.append("\(name) — \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
