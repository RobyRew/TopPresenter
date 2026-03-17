//
//  BatchExportSheet.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sheet for exporting multiple Bible modules at once.
struct BatchExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    @Query(sort: \BibleModule.name) private var modules: [BibleModule]

    @State private var selectedModuleIDs: Set<UUID> = []
    @State private var selectedFormat: SupportedExportFormat = .topPresenter
    @State private var isExporting = false
    @State private var exportedCount = 0

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.up.on.square")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text(String(localized: "Batch Export", comment: "Sheet title"))
                        .font(.title2.bold())
                    Text(String(localized: "Export multiple modules at once", comment: "Sheet subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Module selection
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(String(localized: "Select modules:", comment: "Label"))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Button(String(localized: "Select All", comment: "Button")) {
                        selectedModuleIDs = Set(modules.map(\.id))
                    }
                    .font(.caption)
                    .disabled(selectedModuleIDs.count == modules.count)

                    Button(String(localized: "Deselect All", comment: "Button")) {
                        selectedModuleIDs.removeAll()
                    }
                    .font(.caption)
                    .disabled(selectedModuleIDs.isEmpty)
                }

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(modules) { module in
                            moduleRow(module)
                        }
                    }
                }
                .frame(maxHeight: 200)
            }

            Divider()

            // Format selector
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Export format:", comment: "Label"))
                    .font(.subheadline.weight(.medium))

                Picker(String(localized: "Format:", comment: "Picker"), selection: $selectedFormat) {
                    ForEach(SupportedExportFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Progress
            if isExporting {
                ProgressView(
                    value: Double(exportedCount),
                    total: Double(max(selectedModuleIDs.count, 1))
                ) {
                    Text(String(localized: "Exporting \(exportedCount) of \(selectedModuleIDs.count)...", comment: "Export progress"))
                        .font(.caption)
                }
                .progressViewStyle(.linear)
            }

            // Actions
            HStack {
                Button(String(localized: "Cancel", comment: "Button")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    performBatchExport()
                } label: {
                    Label(
                        String(localized: "Export (\(selectedModuleIDs.count))", comment: "Button"),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedModuleIDs.isEmpty || isExporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
        .frame(minHeight: 420)
    }

    private func moduleRow(_ module: BibleModule) -> some View {
        let isSelected = selectedModuleIDs.contains(module.id)
        return HStack(spacing: 10) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(module.abbreviation.isEmpty ? module.name : "\(module.abbreviation) — \(module.name)")
                    .font(.body)
                    .lineLimit(1)
                Text("\(module.books.count) books • \(module.language)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(8)
        .background(
            isSelected ? Color.accentColor.opacity(0.08) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedModuleIDs.remove(module.id)
            } else {
                selectedModuleIDs.insert(module.id)
            }
        }
    }

    private func performBatchExport() {
        // Pick output folder
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a folder to save exported modules", comment: "Panel message")
        panel.prompt = String(localized: "Export Here", comment: "Panel button")

        guard panel.runModal() == .OK, let folder = panel.url else { return }

        let selectedModules = modules.filter { selectedModuleIDs.contains($0.id) }
        isExporting = true
        exportedCount = 0

        Task {
            var succeeded = 0
            var failed = 0

            for module in selectedModules {
                let fileName = "\(module.abbreviation.isEmpty ? module.name : module.abbreviation).\(selectedFormat.fileExtension)"
                let fileURL = folder.appendingPathComponent(fileName)

                do {
                    try await ExportService.exportBible(
                        module: module,
                        format: selectedFormat,
                        to: fileURL
                    )
                    succeeded += 1
                } catch {
                    failed += 1
                }

                await MainActor.run {
                    exportedCount += 1
                }
            }

            await MainActor.run {
                isExporting = false
                if failed == 0 {
                    appState.showSuccess(
                        String(localized: "Batch Export Complete", comment: "Alert"),
                        message: String(localized: "Successfully exported \(succeeded) module(s) to \(folder.lastPathComponent)/", comment: "Alert")
                    )
                } else {
                    appState.showError(
                        String(localized: "Batch Export Finished", comment: "Alert"),
                        message: String(localized: "\(succeeded) succeeded, \(failed) failed.", comment: "Alert")
                    )
                }
                dismiss()
            }
        }
    }
}
