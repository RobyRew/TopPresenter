//
//  UniversalImportSheet.swift
//  TopPresenter
//
//  The one import interface.
//
//  There were five, with arbitrarily different capabilities: a Bible sheet with
//  a format override, a song sheet without one, a batch sheet that showed a
//  file list, a window drop overlay, and seven bare NSOpenPanels. Which one you
//  reached decided whether folders were scanned, whether duplicates were
//  checked, and whether anything was said about files that were skipped.
//
//  One file, many files, folders, folders of folders, any mix of kinds — the
//  same sheet, and it says what it is going to do before it does it.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

struct UniversalImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(LibraryTaskRunner.self) private var libraryTasks

    @State private var plan = ImportPlanModel()
    @State private var isDropTargeted = false

    /// Files the sheet was opened with (a drop, or a picked selection).
    var initialURLs: [URL] = []
    /// Preselect one library's kinds when opened from that tab.
    var preselectedKinds: Set<ImportKind> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 460, idealHeight: 560)
        .task {
            plan.preselectedKinds = preselectedKinds
            if !initialURLs.isEmpty { await plan.load(initialURLs) }
        }
        .onChange(of: libraryTasks.progress.isRunning) { wasRunning, isRunning in
            if wasRunning, !isRunning, let summary = libraryTasks.lastSummary {
                plan.adopt(summary)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(appAccent.gradient)
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "Import", comment: "Sheet title"))
                        .font(.title3.bold())
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if plan.stage == .planning, !plan.rows.isEmpty {
                    Picker("", selection: Binding(
                        get: { plan.mode },
                        set: { plan.modeOverride = $0 }
                    )) {
                        ForEach(ImportPlanModel.Mode.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 176)
                }
            }
            // What was found, at a glance, before reading a single row.
            if plan.stage != .empty, !plan.kindsPresent.isEmpty {
                HStack(spacing: 7) {
                    ForEach(plan.kindsPresent) { kind in
                        let count = plan.rows.filter { $0.kind == kind }.count
                        Label("\(count)", systemImage: kind.systemImage)
                            .font(.caption.weight(.medium))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(appAccent.opacity(0.12)))
                            .help(kind.displayName)
                    }
                    if !plan.unsupported.isEmpty {
                        Label("\(plan.unsupported.count)", systemImage: "questionmark")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                            .help(String(localized: "Not recognised", comment: "Chip tooltip"))
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var subtitle: String {
        switch plan.stage {
        case .empty: return String(localized: "Bibles, songs, media, sessions and themes", comment: "Import subtitle")
        case .scanning: return String(localized: "Looking through the selection…", comment: "Import subtitle")
        case .planning, .running:
            return String(localized: "\(plan.selectedRows.count) of \(plan.rows.count) selected", comment: "Import subtitle")
        case .finished: return plan.summary?.headline ?? ""
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch plan.stage {
        case .empty: dropZone
        case .scanning:
            // A folder of folders can take a moment, and a bare unlabelled
            // spinner in the middle of an empty panel is indistinguishable from
            // a hang.
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(String(localized: "Looking through the selection…", comment: "Scanning state"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .planning, .running, .finished: planList
        }
    }

    /// The empty state.
    ///
    /// It used to be a fixed 180pt dashed box stranded in the middle of a 460pt
    /// panel, with a lone disclosure triangle underneath and a permanently
    /// disabled Import button in the footer — three unrelated things floating in
    /// a lot of nothing. The drop target now OWNS the panel: it fills the space,
    /// so the whole sheet is the thing you can drop onto, which is also what a
    /// window-sized drop target should look like. Underneath it, the six kinds
    /// are shown as a real row rather than hidden behind a disclosure, because
    /// "what can I even put here?" is the actual question at this moment.
    private var dropZone: some View {
        VStack(spacing: 14) {
            Button { browse() } label: {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isDropTargeted ? appAccent.opacity(0.16) : Color.secondary.opacity(0.09))
                            .frame(width: 72, height: 72)
                        Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(isDropTargeted ? appAccent : .secondary)
                            .symbolEffect(.bounce, value: isDropTargeted)
                    }
                    VStack(spacing: 4) {
                        Text(isDropTargeted
                             ? String(localized: "Release to add", comment: "Drop zone title, hovering")
                             : String(localized: "Drop files or folders here", comment: "Drop zone title"))
                            .font(.title3.weight(.medium))
                        Text(String(localized: "Subfolders are scanned, and nothing is added until you confirm.",
                                    comment: "Drop zone subtitle"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isDropTargeted ? appAccent.opacity(0.07) : Color.secondary.opacity(0.045)))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(isDropTargeted ? appAccent : Color.secondary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1.5, dash: [7, 5])))
                .animation(.easeOut(duration: 0.15), value: isDropTargeted)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Click to browse, or drop files anywhere in this window",
                         comment: "Drop zone tooltip"))

            kindStrip
        }
        .padding(16)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDropped(providers)
            return true
        }
    }

    /// The six kinds, always visible, each listing its formats on hover.
    ///
    /// Rendered from `ImportCatalog`, so it cannot drift from what the
    /// classifier actually accepts.
    private var kindStrip: some View {
        HStack(spacing: 6) {
            ForEach(ImportKind.allCases) { kind in
                let formats = ImportCatalog.importable.filter { $0.kind == kind }
                if !formats.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: kind.systemImage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(appAccent)
                        Text(kind.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.secondary.opacity(0.06)))
                    // The extension list is the genuinely useful part, but it is
                    // long and only wanted when someone is unsure — so it lives
                    // in the tooltip rather than costing six lines on screen.
                    .help(formats
                        .map { "\($0.displayName) — " + $0.fileExtensions.map { ".\($0)" }.joined(separator: " ") }
                        .joined(separator: "\n"))
                }
            }
        }
    }

    private var planList: some View {
        VStack(spacing: 0) {
            if !plan.truncations.isEmpty { truncationBanner }
            List {
                ForEach(plan.kindsPresent) { kind in
                    Section {
                        ForEach(plan.rows(for: kind)) { row in
                            fileRow(row)
                        }
                    } header: {
                        kindHeader(kind)
                    }
                }
                if !plan.unsupported.isEmpty { unsupportedSection }
            }
            .listStyle(.inset)
            if plan.mode == .advanced, plan.stage == .planning, plan.rows.count > 8 {
                LibrarySearchField(text: $plan.filterText,
                                   placeholder: String(localized: "Filter files", comment: "Filter prompt"))
                    .padding(.horizontal, 12).padding(.vertical, 8)
            }
        }
    }

    private var truncationBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(plan.truncations.enumerated()), id: \.offset) { _, truncation in
                Label(truncation.message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.12))
    }

    private func kindHeader(_ kind: ImportKind) -> some View {
        HStack {
            Label(kind.displayName, systemImage: kind.systemImage)
            Spacer()
            if plan.mode == .advanced, plan.stage == .planning {
                if DuplicatePolicy.allowed(for: kind).count > 1 {
                    Picker("", selection: policyBinding(for: kind)) {
                        ForEach(DuplicatePolicy.allowed(for: kind)) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
                Button(plan.allSelected(in: kind)
                       ? String(localized: "None", comment: "Bulk select")
                       : String(localized: "All", comment: "Bulk select")) {
                    plan.setSelected(!plan.allSelected(in: kind), forKind: kind)
                }
                .buttonStyle(.link)
            }
        }
    }

    private func policyBinding(for kind: ImportKind) -> Binding<DuplicatePolicy> {
        Binding(
            get: { plan.policies[kind] ?? DuplicatePolicy.allowed(for: kind).first ?? .skip },
            set: { plan.policies[kind] = $0 }
        )
    }

    /// One control per row on purpose: a `Toggle` costs 4-6 ms each, which a
    /// 200-file plan feels immediately.
    private func fileRow(_ row: ImportPlanModel.Row) -> some View {
        HStack(spacing: 11) {
            if plan.stage == .planning {
                Button {
                    plan.setSelected(!row.isSelected, for: row.id)
                } label: {
                    Image(systemName: row.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(row.isSelected ? appAccent : Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: row.status.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(row.status.color)
                    .symbolEffect(.pulse, isActive: row.status == .importing)
            }

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(appAccent.opacity(0.13))
                .frame(width: 26, height: 26)
                .overlay {
                    Image(systemName: row.kind?.systemImage ?? "doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(appAccent)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(row.fileName)
                    .font(.callout)
                    .lineLimit(1).truncationMode(.middle)
                if let detail = rowDetail(row) {
                    Text(detail.text)
                        .font(.caption2)
                        .foregroundStyle(detail.isError ? Color.red : .secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, 3)
        .opacity(row.isSelected ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture {
            guard plan.stage == .planning else { return }
            plan.setSelected(!row.isSelected, for: row.id)
        }
    }

    /// The one line under a filename — whichever of duplicate / status / error
    /// is worth the space right now.
    private func rowDetail(_ row: ImportPlanModel.Row) -> (text: String, isError: Bool)? {
        if let duplicateOf = row.duplicateOf {
            return (String(localized: "identical to \(duplicateOf)", comment: "Duplicate row note"), false)
        }
        if case .failed(let reason) = row.status { return (reason, true) }
        if case .success(let message) = row.status, message != row.fileName { return (message, false) }
        return nil
    }

    private var unsupportedSection: some View {
        Section {
            ForEach(plan.unsupported) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.fileName).lineLimit(1).truncationMode(.middle)
                    Text(item.reason).font(.caption2).foregroundStyle(.secondary)
                }
            }
        } header: {
            // Never silently swallowed: every file that was passed over is
            // listed, with the reason it was.
            Label(String(localized: "Not recognised (\(plan.unsupported.count))", comment: "Section"),
                  systemImage: "questionmark.folder")
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if plan.stage == .finished {
                Button(String(localized: "Copy report", comment: "Button")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(plan.summary?.report ?? "", forType: .string)
                }
            } else if plan.stage == .planning, plan.rows.contains(where: { $0.kind == .song }) {
                TextField(String(localized: "Collection", comment: "Field label"),
                          text: $plan.songCollectionName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            Spacer()
            switch plan.stage {
            case .finished:
                Button(String(localized: "Done", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .running:
                ProgressView(value: libraryTasks.progress.fraction)
                    .frame(width: 130)
                Button(String(localized: "Stop", comment: "Button")) { libraryTasks.cancel() }
                // Closing is FINE now — the job belongs to the runner, and the
                // main window keeps showing it.
                Button(String(localized: "Close", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            case .empty:
                // An Import button with nothing to import is dead weight, and a
                // disabled default button is the clearest possible sign that a
                // screen was never finished. Offer the two things that actually
                // work from here instead.
                Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Choose Folder…", comment: "Button")) { browse(directories: true) }
                Button(String(localized: "Choose Files…", comment: "Button")) { browse(directories: false) }
                    .keyboardShortcut(.defaultAction)
            default:
                if let estimate = plan.preflightEstimate {
                    Label(String(localized: "about \(LibraryTaskProgress.formatted(estimate))",
                                 comment: "Pre-flight estimate"),
                          systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(String(localized: "A rough estimate from the total size — the real time depends on the files.",
                                     comment: "Pre-flight estimate tooltip"))
                }
                Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Import", comment: "Button")) {
                    plan.run(using: libraryTasks, presentationManager: presentationManager)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!plan.canImport)
            }
        }
        .padding(16)
    }

    // MARK: - Picking

    /// `directories: true` picks folders only.
    ///
    /// A panel that accepts both makes picking a folder needlessly fiddly —
    /// macOS treats a highlighted folder as "navigate into me" rather than
    /// "choose me" — so the two buttons open two panels rather than one that
    /// half-does both. Clicking the drop zone itself still allows either.
    private func browse(directories: Bool? = nil) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = directories != true
        panel.canChooseDirectories = directories != false
        if panel.canChooseFiles {
            panel.allowedContentTypes = ImportCatalog.contentTypes()
        }
        panel.message = directories == true
            ? String(localized: "Select folders to scan for importable files", comment: "Open panel message")
            : String(localized: "Select files or folders to import", comment: "Open panel message")
        panel.prompt = String(localized: "Add", comment: "Open panel button")
        guard panel.runModal() == .OK else { return }
        Task { await plan.load(panel.urls) }
    }

    /// Provider callbacks arrive on arbitrary threads, so they are collected
    /// behind a lock and handed over once, on the main actor.
    private func loadDropped(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let collected = OSAllocatedUnfairLock(initialState: [URL]())
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.withLock { $0.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            let urls = collected.withLock { $0 }
            Task { await plan.load(urls) }
        }
    }
}
