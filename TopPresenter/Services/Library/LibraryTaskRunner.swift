//
//  LibraryTaskRunner.swift
//  TopPresenter
//
//  The one owner of long library jobs: imports and bulk deletes.
//
//  It exists so those jobs OUTLIVE the sheet that started them. Importing
//  seventy Bibles used to hold a modal sheet open for the whole run, on the
//  main thread, with a beach ball where the app should be. Now the sheet starts
//  the job and can be closed; the job keeps going on a background actor and
//  reports into `progress`, which the main window shows in a strip at the
//  bottom with a cancel button.
//
//  One job at a time, deliberately. Two bulk writers on the same store
//  contend on the coordinator and each make the other slower — and "why is it
//  taking so long" is exactly the problem being fixed.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class LibraryTaskRunner {

    let progress = LibraryTaskProgress()

    /// The last finished import, so the sheet can still show its summary after
    /// the job outlived the sheet that started it.
    private(set) var lastSummary: ImportCoordinator.Summary?
    private(set) var lastNote = ""

    private let container: ModelContainer
    private var background: BackgroundImportActor?
    private var maintenance: LibraryMaintenanceActor?
    private var current: Task<Void, Never>?

    var isBusy: Bool { progress.isRunning }

    init(container: ModelContainer) {
        self.container = container
    }

    private func makeBackground() -> BackgroundImportActor {
        if let background { return background }
        let actor = BackgroundImportActor(modelContainer: container)
        background = actor
        return actor
    }

    private func makeMaintenance() -> LibraryMaintenanceActor {
        if let maintenance { return maintenance }
        let actor = LibraryMaintenanceActor(modelContainer: container)
        maintenance = actor
        return actor
    }

    // MARK: - Import

    /// Start an import. Returns immediately; watch `progress`.
    func startImport(
        files: [PendingImportFile],
        collectionName: String,
        policies: [ImportKind: DuplicatePolicy],
        presentationManager: PresentationManager?,
        onUpdate: @escaping @MainActor @Sendable (UUID, ImportFileStatus) -> Void = { _, _ in }
    ) {
        guard !isBusy else { return }
        lastSummary = nil
        progress.begin(.importing, total: files.count)

        current = Task { [weak self] in
            guard let self else { return }
            let coordinator = ImportCoordinator(
                modelContext: container.mainContext,
                presentationManager: presentationManager,
                background: makeBackground(),
                progress: progress
            )
            coordinator.policies = policies
            let summary = await coordinator.run(files, songCollectionName: collectionName, onUpdate: onUpdate)
            lastSummary = summary
            lastNote = summary.headline
            progress.end()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
    }

    // MARK: - Delete

    /// Delete Bible modules off the main thread, one save per module.
    ///
    /// The ids are read on the main context BEFORE the job starts, because that
    /// is the only thread allowed to touch those objects; everything after is
    /// the actor's.
    func deleteBibleModules(_ modules: [BibleModule], searchIndex: SearchIndex?) {
        guard !isBusy, !modules.isEmpty else { return }
        let ids = modules.map(\.id)
        let names = modules.map(\.name)
        for id in ids { searchIndex?.moduleDeleted(id) }

        progress.begin(.deleting, total: ids.count)
        current = Task { [weak self] in
            guard let self else { return }
            let outcome = await makeMaintenance().deleteBibleModules(
                ids: ids,
                onProgress: { [weak self] name, _ in self?.progress.startItem(name) },
                isCancelled: { [weak self] in self?.progress.isCancelled ?? false }
            )
            // The actor deleted on its own context; the main one still holds
            // faults for rows that no longer exist.
            container.mainContext.rollback()
            lastNote = outcome.failures.isEmpty
                ? String(localized: "\(outcome.deleted) deleted.", comment: "Delete result")
                : String(localized: "\(outcome.deleted) deleted, \(outcome.failures.count) failed.",
                         comment: "Delete result")
            _ = names
            progress.end()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
    }

    func deleteSongCollections(_ collections: [SongCollection]) {
        guard !isBusy, !collections.isEmpty else { return }
        let ids = collections.map(\.id)
        progress.begin(.deleting, total: ids.count)
        current = Task { [weak self] in
            guard let self else { return }
            let outcome = await makeMaintenance().deleteSongCollections(
                ids: ids,
                onProgress: { [weak self] name, _ in self?.progress.startItem(name) },
                isCancelled: { [weak self] in self?.progress.isCancelled ?? false }
            )
            container.mainContext.rollback()
            lastNote = String(localized: "\(outcome.deleted) deleted.", comment: "Delete result")
            progress.end()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
    }

    func cancel() { progress.cancel() }
}
