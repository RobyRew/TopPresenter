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
//  and one save PER MODULE rather than one at the end. The store never holds a
//  two-million-row transaction, the freelist never grows to the point where the
//  vacuum dominates, and — the part that matters to whoever is waiting — the
//  job can report which module it is on and be cancelled between them.
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
            let descriptor = FetchDescriptor<BibleModule>(predicate: #Predicate { $0.id == id })
            guard let module = try? modelContext.fetch(descriptor).first else { continue }
            let name = module.name
            await onProgress(name, index)

            // No autoreleasepool around this: under Swift 6 the closure would
            // be "sending" a non-Sendable model out of its region. The per-module
            // SAVE below is what actually bounds memory anyway — it is the
            // transaction size, not the pool, that made the old code hurt.
            modelContext.delete(module)
            do {
                try modelContext.save()
                outcome.deleted += 1
            } catch {
                outcome.failures.append("\(name) — \(error.localizedDescription)")
            }
        }
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
            guard let collection = try? modelContext.fetch(descriptor).first else { continue }
            let name = collection.name
            await onProgress(name, index)
            modelContext.delete(collection)
            do {
                try modelContext.save()
                outcome.deleted += 1
            } catch {
                outcome.failures.append("\(name) — \(error.localizedDescription)")
            }
        }
        return outcome
    }
}
