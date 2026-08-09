//
//  ImportCoordinator.swift
//  TopPresenter
//
//  Runs one import — whatever kinds it contains — and reports what happened.
//
//  The order the kinds run in is not arbitrary and not cosmetic. Media goes
//  FIRST because `SessionArchiveService.importSession` re-links each media item
//  against the library as it stands at that moment: a session and the clips it
//  references, imported together in the wrong order, would arrive with every
//  media item reported missing. Sessions therefore go last, once everything
//  they can point at exists.
//
//  The summary is the other half of the job. The old batch sheet dismissed to
//  an alert carrying a single count, which cannot distinguish "12 imported"
//  from "2 imported and 10 already there" — which is exactly how a silent
//  double-import goes unnoticed.
//

import Foundation
import SwiftData

@MainActor
final class ImportCoordinator {

    /// What happened to one file.
    enum Result: Sendable, Equatable {
        case imported(String)
        case skippedDuplicate(name: String, matchedOn: String)
        case replaced(String)
        case merged(String)
        case failed(name: String, reason: String)
        case unsupported(name: String)
    }

    struct Summary {
        var results: [Result] = []

        var imported: Int { results.filter { if case .imported = $0 { return true }; return false }.count }
        var skipped: Int { results.filter { if case .skippedDuplicate = $0 { return true }; return false }.count }
        var replaced: Int { results.filter { if case .replaced = $0 { return true }; return false }.count }
        var merged: Int { results.filter { if case .merged = $0 { return true }; return false }.count }
        var failed: Int { results.filter { if case .failed = $0 { return true }; return false }.count }
        var unsupported: Int { results.filter { if case .unsupported = $0 { return true }; return false }.count }

        var isEmpty: Bool { results.isEmpty }

        /// One line for an alert. Only mentions what actually happened, so a
        /// clean import does not read like a report of four zeroes.
        var headline: String {
            var parts: [String] = []
            if imported > 0 { parts.append(String(localized: "\(imported) imported", comment: "Import summary")) }
            if skipped > 0 { parts.append(String(localized: "\(skipped) already in the library", comment: "Import summary")) }
            if replaced > 0 { parts.append(String(localized: "\(replaced) replaced", comment: "Import summary")) }
            if merged > 0 { parts.append(String(localized: "\(merged) merged", comment: "Import summary")) }
            if failed > 0 { parts.append(String(localized: "\(failed) failed", comment: "Import summary")) }
            if unsupported > 0 { parts.append(String(localized: "\(unsupported) not recognised", comment: "Import summary")) }
            return parts.isEmpty
                ? String(localized: "Nothing to import", comment: "Import summary")
                : parts.joined(separator: ", ")
        }

        /// The per-file detail, for "Copy report". A summary line is enough to
        /// notice something happened; this is what makes it actionable.
        var report: String {
            results.map { result in
                switch result {
                case .imported(let name): return "✓ \(name)"
                case .skippedDuplicate(let name, let matchedOn): return "= \(name) — \(matchedOn)"
                case .replaced(let name): return "⟳ \(name)"
                case .merged(let name): return "+ \(name)"
                case .failed(let name, let reason): return "✗ \(name) — \(reason)"
                case .unsupported(let name): return "? \(name)"
                }
            }.joined(separator: "\n")
        }
    }

    /// Per-kind duplicate policy. Kinds absent take `DuplicatePolicy.suggested`.
    var policies: [ImportKind: DuplicatePolicy] = [:]

    /// Media before sessions, always — see the note at the top of the file.
    static let kindOrder: [ImportKind] = [.media, .bible, .song, .theme, .slides, .session]

    private let modelContext: ModelContext
    /// Themes live in the manager, not the store, so importing one needs it.
    private let presentationManager: PresentationManager?

    init(modelContext: ModelContext, presentationManager: PresentationManager? = nil) {
        self.modelContext = modelContext
        self.presentationManager = presentationManager
    }

    /// Import a classified selection, one kind at a time, in `kindOrder`.
    func run(
        _ files: [PendingImportFile],
        songCollectionName: String,
        onUpdate: @MainActor (UUID, ImportFileStatus) -> Void = { _, _ in }
    ) async -> Summary {
        var summary = Summary()
        let byKind = Dictionary(grouping: files) { $0.category.kind }

        for kind in Self.kindOrder {
            guard let group = byKind[kind], !group.isEmpty else { continue }
            switch kind {
            case .media:
                let outcome = MediaImportService.importMedia(
                    urls: group.map(\.url),
                    modelContext: modelContext,
                    policy: policies[.media] ?? .skip
                ) { url, status in
                    guard let file = group.first(where: { $0.url == url }) else { return }
                    onUpdate(file.id, status)
                }
                summary.results += outcome.imported.map { .imported($0.name) }
                summary.results += outcome.skipped.map {
                    .skippedDuplicate(name: $0.url.lastPathComponent, matchedOn: $0.matchedOn)
                }
                summary.results += outcome.unsupported.map { .unsupported(name: $0.lastPathComponent) }

            case .bible:
                for file in group {
                    guard case .bible(let format) = file.category else { continue }
                    onUpdate(file.id, .importing)
                    do {
                        let outcome = try await ImportService.importBible(
                            fileURL: file.url, format: format, modelContext: modelContext,
                            resolution: resolution(for: policies[.bible] ?? .keepBoth))
                        switch outcome.action {
                        case .imported:
                            summary.results.append(.imported(outcome.module.name))
                            onUpdate(file.id, .success(outcome.module.name))
                        case .skippedDuplicate(let matchedOn):
                            summary.results.append(.skippedDuplicate(name: outcome.module.name, matchedOn: matchedOn))
                            onUpdate(file.id, .success(String(localized: "\(outcome.module.name) — already in the library",
                                                              comment: "Batch import status")))
                        case .replaced:
                            summary.results.append(.replaced(outcome.module.name))
                            onUpdate(file.id, .success(outcome.module.name))
                        case .merged:
                            summary.results.append(.merged(outcome.module.name))
                            onUpdate(file.id, .success(outcome.module.name))
                        }
                    } catch {
                        summary.results.append(.failed(name: file.fileName, reason: error.localizedDescription))
                        onUpdate(file.id, .failed(error.localizedDescription))
                    }
                }

            case .song:
                let batch = await ImportService.importSongItems(
                    urls: group.map(\.url),
                    collectionName: songCollectionName,
                    modelContext: modelContext,
                    duplicateResolution: songResolution(for: policies[.song] ?? .addAsVersion)
                )
                summary.results += batch.importedTitles.map { .imported($0) }
                summary.results += batch.failures.map { .failed(name: $0.file, reason: $0.reason) }
                for file in group { onUpdate(file.id, .success(file.fileName)) }

            case .theme:
                for file in group {
                    onUpdate(file.id, .importing)
                    do {
                        let before = presentationManager?.themes.count ?? 0
                        guard let theme = try presentationManager?.importTheme(from: file.url) else {
                            summary.results.append(.failed(name: file.fileName,
                                                           reason: String(localized: "No presentation manager available.",
                                                                          comment: "Import error")))
                            continue
                        }
                        // The gallery not growing means the package was already
                        // here, or replaced the theme it came from.
                        let after = presentationManager?.themes.count ?? 0
                        if after == before {
                            summary.results.append(.skippedDuplicate(
                                name: theme.name,
                                matchedOn: String(localized: "the same theme", comment: "Duplicate match reason")))
                        } else {
                            summary.results.append(.imported(theme.name))
                        }
                        onUpdate(file.id, .success(theme.name))
                    } catch {
                        summary.results.append(.failed(name: file.fileName, reason: error.localizedDescription))
                        onUpdate(file.id, .failed(error.localizedDescription))
                    }
                }

            case .session:
                for file in group {
                    onUpdate(file.id, .importing)
                    do {
                        let before = (try? modelContext.fetch(FetchDescriptor<ServiceSchedule>()))?.count ?? 0
                        let data = try Data(contentsOf: file.url)
                        let result = try SessionArchiveService.importSession(data, context: modelContext)
                        let after = (try? modelContext.fetch(FetchDescriptor<ServiceSchedule>()))?.count ?? 0
                        if after == before {
                            summary.results.append(.skippedDuplicate(
                                name: result.schedule.name,
                                matchedOn: String(localized: "the same session", comment: "Duplicate match reason")))
                        } else {
                            summary.results.append(.imported(result.schedule.name))
                        }
                        // Media that did not resolve is named, not swallowed:
                        // a session that silently loses its clips is worse than
                        // one that says which are missing.
                        onUpdate(file.id, .success(result.unresolvedMedia.isEmpty
                            ? result.schedule.name
                            : String(localized: "\(result.schedule.name) — \(result.unresolvedMedia.count) media not found",
                                     comment: "Session import status")))
                    } catch {
                        summary.results.append(.failed(name: file.fileName, reason: error.localizedDescription))
                        onUpdate(file.id, .failed(error.localizedDescription))
                    }
                }

            case .slides:
                for file in group {
                    onUpdate(file.id, .importing)
                    do {
                        let data = try Data(contentsOf: file.url)
                        let result = try SlideDeckArchiveService.importDeck(data, context: modelContext)
                        summary.results += result.imported.map { .imported($0.title) }
                        // A deck is a loose collection someone adds to over
                        // months, so identity is per SLIDE: re-importing a deck
                        // you extended elsewhere brings in what is new.
                        summary.results += result.skipped.map {
                            .skippedDuplicate(name: $0,
                                              matchedOn: String(localized: "the same slide",
                                                                comment: "Duplicate match reason"))
                        }
                        onUpdate(file.id, .success(String(localized: "\(result.imported.count) slides",
                                                          comment: "Slide import status")))
                    } catch {
                        summary.results.append(.failed(name: file.fileName, reason: error.localizedDescription))
                        onUpdate(file.id, .failed(error.localizedDescription))
                    }
                }
            }
        }
        return summary
    }

    private func resolution(for policy: DuplicatePolicy) -> ImportService.BibleConflictResolution {
        switch policy {
        case .ask: return .ask
        case .replace: return .replace
        case .merge: return .merge
        case .skip: return .cancel
        case .keepBoth, .addAsVersion: return .keepBoth
        }
    }

    private func songResolution(for policy: DuplicatePolicy) -> SongDuplicateResolution {
        switch policy {
        case .replace: return .replace
        case .skip, .ask: return .skip
        case .keepBoth: return .keepBoth
        case .merge, .addAsVersion: return .addAsVersion
        }
    }
}
