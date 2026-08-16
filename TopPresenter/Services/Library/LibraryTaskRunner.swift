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

    /// Delete Bible modules off the main thread.
    ///
    /// The ids are read on the main context BEFORE the job starts, because that
    /// is the only thread allowed to touch those objects; everything after is
    /// the actor's.
    ///
    /// Pass `libraryManager` whenever one is in scope. The delete runs as SQL
    /// and never marks the objects deleted, so a selection pointing into a
    /// module that is about to vanish would survive as a reference to a row
    /// that does not exist. Clearing it is done HERE, up front and while the
    /// objects are still valid, so that no call site has to remember the rule.
    func deleteBibleModules(_ modules: [BibleModule],
                            searchIndex: SearchIndex?,
                            clearing libraryManager: LibraryManager? = nil) {
        guard !isBusy, !modules.isEmpty else { return }
        let ids = modules.map(\.id)
        for id in ids { searchIndex?.moduleDeleted(id) }

        if let libraryManager,
           let open = libraryManager.selectedBibleModule,
           ids.contains(open.id) {
            libraryManager.clearBibleSelection()
        }

        progress.begin(.deleting, total: ids.count)
        current = Task { [weak self] in
            guard let self else { return }
            let outcome = await makeMaintenance().deleteBibleModules(
                ids: ids,
                onProgress: { [weak self] name, _ in self?.progress.startItem(name) },
                isCancelled: { [weak self] in self?.progress.isCancelled ?? false }
            )
            lastNote = outcome.failures.isEmpty
                ? String(localized: "\(outcome.deleted) deleted.", comment: "Delete result")
                : String(localized: "\(outcome.deleted) deleted, \(outcome.failures.count) failed.",
                         comment: "Delete result")
            progress.end()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
    }

    func deleteSongCollections(_ collections: [SongCollection],
                               clearing libraryManager: LibraryManager? = nil) {
        guard !isBusy, !collections.isEmpty else { return }
        let ids = collections.map(\.id)

        if let libraryManager,
           let open = libraryManager.selectedSongCollection,
           ids.contains(open.id) {
            libraryManager.clearSongSelection()
        }

        progress.begin(.deleting, total: ids.count)
        current = Task { [weak self] in
            guard let self else { return }
            let outcome = await makeMaintenance().deleteSongCollections(
                ids: ids,
                onProgress: { [weak self] name, _ in self?.progress.startItem(name) },
                isCancelled: { [weak self] in self?.progress.isCancelled ?? false }
            )
            lastNote = String(localized: "\(outcome.deleted) deleted.", comment: "Delete result")
            progress.end()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
        }
    }

    /// Wipe the song library. Same treatment as the Bibles: SQL, off the main
    /// thread, reported in the strip.
    func deleteAllSongs(clearing libraryManager: LibraryManager? = nil,
                        onFinish: @escaping @MainActor (Bool) -> Void = { _ in }) {
        guard !isBusy else { return }
        libraryManager?.clearSongSelection()
        progress.begin(.deleting, total: 3)
        current = Task { [weak self] in
            guard let self else { return }
            let outcome = await makeMaintenance().deleteAllSongs(
                onProgress: { [weak self] name, _ in self?.progress.startItem(name) }
            )
            lastNote = outcome.failures.isEmpty
                ? String(localized: "All songs deleted.", comment: "Delete result")
                : outcome.failures.joined(separator: "\n")
            progress.end()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            onFinish(outcome.failures.isEmpty)
        }
    }

    // MARK: - Export

    /// Export Bible modules to a folder. Same deal as import: off the main
    /// thread, reported in the strip, cancellable, and the sheet may close.
    func exportBibleModules(_ modules: [BibleModule], to folder: URL) {
        guard !isBusy, !modules.isEmpty else { return }
        let ids = modules.map(\.id)
        progress.begin(.exporting, total: ids.count)
        current = Task { [weak self] in
            guard let self else { return }
            let outcome = await makeMaintenance().exportBibleModules(
                ids: ids, toFolder: folder,
                onProgress: { [weak self] name, _ in self?.progress.startItem(name) },
                onItemProgress: { [weak self] in self?.progress.setItemFraction($0) },
                isCancelled: { [weak self] in self?.progress.isCancelled ?? false }
            )
            lastNote = outcome.failures.isEmpty
                ? String(localized: "\(outcome.exported) exported.", comment: "Export result")
                : String(localized: "\(outcome.exported) exported, \(outcome.failures.count) failed.",
                         comment: "Export result")
            progress.end()
        }
    }

    func cancel() { progress.cancel() }
}
