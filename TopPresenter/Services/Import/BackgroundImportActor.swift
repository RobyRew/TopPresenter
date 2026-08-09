//
//  BackgroundImportActor.swift
//  TopPresenter
//
//  Batch imports run HERE — a native SwiftData @ModelActor with its own
//  serialized ModelContext on the shared container, fully off the main actor.
//  This is the fix for the batch-import heap-corruption crash: the view's
//  main-actor ModelContext must never do heavy work across thread hops.
//  ImportService.importBible is nonisolated(nonsending), so calling it from
//  here keeps parse + insert + chunked saves ON this actor; only Sendable
//  progress updates hop back to the main actor (throttled per file/book).
//

import Foundation
import SwiftData

@ModelActor
actor BackgroundImportActor {
    /// Import every Bible file in the batch on this actor's context.
    /// Status updates hop to the main actor; returns how many succeeded.
    @discardableResult
    /// `resolution` used to be hardcoded to `.keepBoth` here, so a batch import
    /// silently bypassed the conflict dialog that the single-file path shows —
    /// two editions of the same translation both landed, renamed, with nothing
    /// asked. It is the caller's decision now. (Identical content is skipped by
    /// `importBible` itself, whatever this says: re-dropping a file you already
    /// have is not a conflict.)
    func importBibles(
        files: [PendingImportFile],
        resolution: ImportService.BibleConflictResolution = .keepBoth,
        onUpdate: @escaping @MainActor @Sendable (UUID, ImportFileStatus) -> Void,
        onItemProgress: @escaping @MainActor @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @MainActor @Sendable () -> Bool = { false }
    ) async -> [ImportCoordinator.Result] {
        var results: [ImportCoordinator.Result] = []
        for file in files {
            guard case .bible(let format) = file.category else { continue }
            if await isCancelled() { break }

            await onUpdate(file.id, .importing)
            do {
                let outcome = try await ImportService.importBible(
                    fileURL: file.url,
                    format: format,
                    modelContext: modelContext,
                    resolution: resolution
                ) { fraction, _ in
                    // A whole Bible is minutes of work on its own, so the bar
                    // has to move WITHIN a file, not only between files.
                    onItemProgress(fraction)
                }
                switch outcome.action {
                case .skippedDuplicate(let matchedOn):
                    results.append(.skippedDuplicate(name: outcome.module.name, matchedOn: matchedOn))
                    await onUpdate(file.id, .success(String(localized: "\(outcome.module.name) — already in the library",
                                                            comment: "Batch import status")))
                case .replaced:
                    results.append(.replaced(outcome.module.name))
                    await onUpdate(file.id, .success(outcome.module.name))
                case .merged:
                    results.append(.merged(outcome.module.name))
                    await onUpdate(file.id, .success(outcome.module.name))
                case .imported:
                    results.append(.imported(outcome.module.name))
                    await onUpdate(file.id, .success(outcome.module.name))
                }
            } catch {
                results.append(.failed(name: file.fileName, reason: error.localizedDescription))
                await onUpdate(file.id, .failed(error.localizedDescription))
            }
        }
        return results
    }

}
