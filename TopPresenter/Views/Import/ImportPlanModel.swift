//
//  ImportPlanModel.swift
//  TopPresenter
//
//  Everything the import sheet knows, with no view attached — so the rules
//  about what gets selected, what counts as a duplicate and when the advanced
//  mode is warranted can be tested without driving a UI.
//

import Foundation
import SwiftData

@MainActor
@Observable
final class ImportPlanModel {

    // MARK: - Rows

    struct Row: Identifiable {
        let id: UUID
        let url: URL
        let category: DroppedFileCategory
        var isSelected = true
        var status: ImportFileStatus = .pending
        /// Set when this file duplicates an EARLIER file in the same batch.
        /// The row says which one, because "deselected, no reason given" is
        /// indistinguishable from a bug.
        var duplicateOf: String?

        var kind: ImportKind? { category.kind }
        var fileName: String { url.lastPathComponent }
    }

    struct Unsupported: Identifiable {
        let id = UUID()
        let url: URL
        let reason: String
        var fileName: String { url.lastPathComponent }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case simple, advanced
        var id: String { rawValue }
        var displayName: String {
            switch self {
            case .simple: return String(localized: "Simple", comment: "Import mode")
            case .advanced: return String(localized: "Advanced", comment: "Import mode")
            }
        }
    }

    enum Stage: Equatable {
        case empty, scanning, planning, running, finished
    }

    // MARK: - State

    var rows: [Row] = []
    var unsupported: [Unsupported] = []
    var truncations: [ImportScanner.Truncation] = []
    var policies: [ImportKind: DuplicatePolicy] = [:]
    var songCollectionName = String(localized: "Imported Songs", comment: "Default song collection")
    var stage: Stage = .empty
    var summary: ImportCoordinator.Summary?
    var filterText = ""
    /// nil until the operator overrides it; `mode` falls back to `autoMode`.
    var modeOverride: Mode?
    /// Preselect a kind when the sheet is opened from a specific library.
    var preselectedKinds: Set<ImportKind> = []

    var mode: Mode { modeOverride ?? autoMode }

    /// Advanced pays for itself only when there is something to decide: several
    /// kinds at once, a lot of files, duplicates to look at, or files that were
    /// not recognised. A three-photo drop should not open a control panel.
    var autoMode: Mode {
        let kinds = Set(rows.compactMap(\.kind))
        if rows.count > 3 || kinds.count > 1 { return .advanced }
        if rows.contains(where: { $0.duplicateOf != nil }) || !unsupported.isEmpty { return .advanced }
        return .simple
    }

    var selectedRows: [Row] { rows.filter(\.isSelected) }
    var kindsPresent: [ImportKind] { ImportCoordinator.kindOrder.filter { kind in rows.contains { $0.kind == kind } } }

    func rows(for kind: ImportKind) -> [Row] {
        let matching = rows.filter { $0.kind == kind }
        guard !filterText.isEmpty else { return matching }
        let needle = filterText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return matching.filter {
            $0.fileName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(needle)
        }
    }

    var canImport: Bool { stage == .planning && !selectedRows.isEmpty }

    // MARK: - Building the plan

    /// Expand and classify a selection. Runs the walk off the main actor: a
    /// Documents-sized tree would otherwise block the UI while it is scanned.
    func load(_ urls: [URL]) async {
        stage = .scanning
        let scan = await Task.detached(priority: .userInitiated) {
            ImportScanner.scan(urls)
        }.value
        let classified = await Task.detached(priority: .userInitiated) { [files = scan.files] in
            DragDropImportHandler.classify(files)
        }.value

        truncations = scan.truncations
        // Two sources: files the scanner refused to open (it knows the
        // extension is not ours) and files it collected but the classifier
        // could not identify (the extension looked plausible, the contents
        // were not). Both are the operator's question to have answered.
        unsupported = scan.rejected.map { Unsupported(url: $0, reason: Self.reason(unsupported: $0)) }
            + classified.compactMap { file in
                guard file.category.kind == nil else { return nil }
                return Unsupported(url: file.url, reason: Self.reason(unsupported: file.url))
            }
        rows = classified.compactMap { file in
            guard file.category.kind != nil else { return nil }
            return Row(id: file.id, url: file.url, category: file.category)
        }
        markDuplicatesWithinBatch()
        applyPreselection()
        stage = rows.isEmpty && unsupported.isEmpty ? .empty : .planning
    }

    /// Two paths in one folder holding the same bytes — `Biblia.tpbible` and
    /// `Biblia copy.tpbible`. The scanner drops the same PATH twice; it cannot
    /// see this. The first is kept, the rest are deselected, and each says what
    /// it matched so the operator can disagree.
    private func markDuplicatesWithinBatch() {
        let fingerprints = rows.map { ContentFingerprint(contentsOf: $0.url) }
        for (index, original) in DuplicateResolver.duplicatesWithinBatch(fingerprints) {
            rows[index].isSelected = false
            rows[index].duplicateOf = rows[original].fileName
        }
    }

    /// Opening the sheet from the Songs tab should not silently import the
    /// Bibles that happened to be in the same folder — but it must still SHOW
    /// them, so the operator can include them deliberately.
    private func applyPreselection() {
        guard !preselectedKinds.isEmpty else { return }
        for index in rows.indices where !preselectedKinds.contains(rows[index].kind ?? .media) {
            rows[index].isSelected = false
        }
    }

    private static func reason(unsupported url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue, !ImportCatalog.directoryExtensions.contains(ext) {
            return String(localized: "Nothing in this folder is a format TopPresenter reads.",
                          comment: "Unsupported file reason")
        }
        if ext.isEmpty {
            return String(localized: "No extension, and the contents are not a format we read.",
                          comment: "Unsupported file reason")
        }
        // A TopPresenter file under the wrong extension is the one case where
        // "unrecognised" is unhelpful — there is something specific to do.
        if ext == "json" {
            return String(localized: "TopPresenter files use their own extensions now. Re-export it, or rename it.",
                          comment: "Unsupported file reason")
        }
        return String(localized: ".\(ext) is not a format TopPresenter reads.",
                      comment: "Unsupported file reason")
    }

    // MARK: - Selection

    func setSelected(_ isSelected: Bool, for id: UUID) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].isSelected = isSelected
    }

    func setSelected(_ isSelected: Bool, forKind kind: ImportKind) {
        for index in rows.indices where rows[index].kind == kind {
            rows[index].isSelected = isSelected
        }
    }

    func allSelected(in kind: ImportKind) -> Bool {
        let matching = rows.filter { $0.kind == kind }
        return !matching.isEmpty && matching.allSatisfy(\.isSelected)
    }

    // MARK: - Running

    /// Hand the job to the app-wide runner and step aside.
    ///
    /// The sheet used to own the work, which meant closing it was not an
    /// option and the app was unusable until seventy Bibles finished. The
    /// runner outlives the sheet: close it and the progress strip in the main
    /// window carries on, with the same cancel button.
    func run(using runner: LibraryTaskRunner, presentationManager: PresentationManager? = nil) {
        stage = .running
        let selected = selectedRows.map {
            PendingImportFile(url: $0.url, category: $0.category, id: $0.id)
        }
        runner.startImport(
            files: selected,
            collectionName: songCollectionName,
            policies: policies,
            presentationManager: presentationManager
        ) { [weak self] id, status in
            // Rows stay mounted while this runs and their statuses animate in
            // place, so the list never jumps out from under the operator.
            guard let self, let index = self.rows.firstIndex(where: { $0.id == id }) else { return }
            self.rows[index].status = status
        }
    }

    /// Called by the sheet when the runner reports the job finished.
    func adopt(_ summary: ImportCoordinator.Summary) {
        self.summary = summary
        stage = .finished
    }

    func reset() {
        rows = []
        unsupported = []
        truncations = []
        summary = nil
        filterText = ""
        modeOverride = nil
        stage = .empty
    }
}
