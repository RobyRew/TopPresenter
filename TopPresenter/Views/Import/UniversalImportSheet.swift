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
    @State private var showingFormats = false

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
        case .scanning: ProgressView().controlSize(.large)
        case .planning, .running, .finished: planList
        }
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Button { browse() } label: {
                VStack(spacing: 10) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "square.and.arrow.down")
                        .font(.system(size: 38, weight: .light))
                        .foregroundStyle(isDropTargeted ? appAccent : .secondary)
                    Text(String(localized: "Drop files or folders here", comment: "Drop zone title"))
                        .font(.callout.weight(.medium))
                    Text(String(localized: "or click to browse — subfolders are scanned", comment: "Drop zone subtitle"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).frame(height: 180)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isDropTargeted ? appAccent.opacity(0.08) : Color.secondary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isDropTargeted ? appAccent : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
            }
            .buttonStyle(.plain)

            DisclosureGroup(isExpanded: $showingFormats) {
                supportedFormats
            } label: {
                Label(String(localized: "What can I import?", comment: "Disclosure"), systemImage: "questionmark.circle")
                    .font(.callout)
            }
        }
        .padding(16)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadDropped(providers)
            return true
        }
    }

    /// Rendered from `ImportCatalog`, so it cannot drift from what the
    /// classifier actually accepts.
    private var supportedFormats: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ImportKind.allCases) { kind in
                let formats = ImportCatalog.importable.filter { $0.kind == kind }
                if !formats.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(kind.displayName, systemImage: kind.systemImage)
                            .font(.caption.weight(.semibold))
                        ForEach(formats) { format in
                            Text("\(format.displayName) — " + format.fileExtensions.map { ".\($0)" }.joined(separator: " "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 6)
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
            default:
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

    private func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = ImportCatalog.contentTypes()
        panel.message = String(localized: "Select files or folders to import", comment: "Open panel message")
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
