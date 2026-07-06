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
    func importBibles(
        files: [PendingImportFile],
        onUpdate: @escaping @MainActor @Sendable (UUID, ImportFileStatus) -> Void
    ) async -> Int {
        var imported = 0
        for file in files {
            guard case .bible(let format) = file.category else { continue }

            await onUpdate(file.id, .importing)
            do {
                let module = try await ImportService.importBible(
                    fileURL: file.url,
                    format: format,
                    modelContext: modelContext,
                    resolution: .keepBoth
                )
                imported += 1
                await onUpdate(file.id, .success(module.name))
            } catch {
                await onUpdate(file.id, .failed(error.localizedDescription))
            }
        }
        return imported
    }
}
