//
//  BibleExportSheet.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Sheet for exporting a Bible module to various formats.
struct BibleExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AppState.self) private var appState

    @Query(sort: \BibleModule.name) private var modules: [BibleModule]

    @State private var selectedModuleID: UUID?
    @State private var selectedFormat: SupportedExportFormat = .topPresenter
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportStatusText = ""

    private var selectedModule: BibleModule? {
        guard let id = selectedModuleID else { return nil }
        return modules.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Title
            HStack {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(appAccent)
                Text(String(localized: "Export Bible Module", comment: "Sheet title"))
                    .font(.title2.bold())
            }

            // Module selector
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Select module to export:", comment: "Export label"))
                    .font(.subheadline.weight(.medium))

                if modules.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(String(localized: "No Bible modules available. Import a module first.", comment: "Export warning"))
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Picker(String(localized: "Module:", comment: "Picker label"), selection: $selectedModuleID) {
                        Text(String(localized: "Choose a module...", comment: "Picker placeholder"))
                            .tag(nil as UUID?)
                        ForEach(modules) { module in
                            HStack {
                                Text(module.abbreviation.isEmpty ? module.name : "\(module.abbreviation) — \(module.name)")
                            }
                            .tag(module.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)

                    // Module info
                    if let module = selectedModule {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(module.name)
                                    .font(.caption.bold())
                                if !module.moduleDescription.isEmpty {
                                    Text(module.moduleDescription)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(String(localized: "\(module.books.count) books", comment: "Module stats"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                let totalVerses = module.books.flatMap { $0.chapters }.flatMap { $0.verses }.count
                                Text(String(localized: "\(totalVerses) verses", comment: "Module stats"))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(10)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }

            Divider()

            // Format selector
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Export format:", comment: "Export label"))
                    .font(.subheadline.weight(.medium))

                ForEach(SupportedExportFormat.allCases) { format in
                    ExportFormatRow(
                        format: format,
                        isSelected: selectedFormat == format
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedFormat = format
                    }
                }
            }

            // Progress
            if isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: exportProgress) {
                        Text(exportStatusText)
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)
                }
                .transition(.opacity)
            }

            Spacer(minLength: 4)

            // Actions
            HStack {
                Button(String(localized: "Cancel", comment: "Button")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    performExport()
                } label: {
                    Label(
                        String(localized: "Export", comment: "Button"),
                        systemImage: "square.and.arrow.up"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedModule == nil || isExporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .frame(minHeight: 480)
        .onAppear {
            // Pre-select the currently selected module
            selectedModuleID = libraryManager.selectedBibleModule?.id
        }
    }

    private func performExport() {
        guard let module = selectedModule else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [
            UTType(filenameExtension: selectedFormat.fileExtension) ?? .data
        ]
        panel.nameFieldStringValue = "\(module.abbreviation.isEmpty ? module.name : module.abbreviation).\(selectedFormat.fileExtension)"
        panel.message = String(localized: "Choose where to save the exported Bible module", comment: "Save panel message")
        panel.prompt = String(localized: "Export", comment: "Save panel button")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExporting = true
        exportProgress = 0
        exportStatusText = String(localized: "Starting export...", comment: "Export progress")

        Task {
            do {
                try await ExportService.exportBible(
                    module: module,
                    format: selectedFormat,
                    to: url
                ) { progress, status in
                    Task { @MainActor in
                        exportProgress = progress
                        exportStatusText = status
                    }
                }

                await MainActor.run {
                    isExporting = false
                    appState.showSuccess(
                        String(localized: "Export Successful", comment: "Alert title"),
                        message: String(localized: "Successfully exported \"\(module.name)\" as \(selectedFormat.displayName).", comment: "Alert message")
                    )
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    appState.showError(
                        String(localized: "Export Failed", comment: "Alert title"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }
}

// MARK: - Export Format Row
private struct ExportFormatRow: View {
    let format: SupportedExportFormat
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? appAccent : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(format.displayName)
                        .font(.body.weight(.medium))
                    Text("(.\(format.fileExtension))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if format == .topPresenter {
                        Text(String(localized: "Recommended", comment: "Format badge"))
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(appAccent, in: Capsule())
                    }
                }
                Text(format.formatDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(10)
        .background(
            isSelected ? appAccent.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? appAccent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
}
