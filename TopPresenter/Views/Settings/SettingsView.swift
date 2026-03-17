//
//  SettingsView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Application settings window.
/// Non-import/export settings are available inline in the Preview Panel.
struct SettingsView: View {
    @Environment(PresentationManager.self) private var presentationManager

    var body: some View {
        ImportExportSettingsTab()
            .frame(width: 500, height: 400)
    }
}

// MARK: - Import / Export Settings
struct ImportExportSettingsTab: View {
    @AppStorage("defaultExportFormat") private var defaultExportFormat: String = SupportedExportFormat.topPresenter.rawValue
    @AppStorage("autoDetectFormat") private var autoDetectFormat: Bool = true
    @AppStorage("includeMetadataOnExport") private var includeMetadata: Bool = true
    @AppStorage("exportPrettyPrint") private var prettyPrint: Bool = true

    var body: some View {
        Form {
            Section(String(localized: "Import", comment: "Settings section")) {
                Toggle(String(localized: "Auto-detect file format on import", comment: "Setting label"), isOn: $autoDetectFormat)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Supported import formats:", comment: "Settings info"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(SupportedBibleFormat.allCases) { format in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(format.displayName)
                                .font(.caption)
                            Spacer()
                            Text(format.fileExtensions.map { ".\($0)" }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section(String(localized: "Export", comment: "Settings section")) {
                Picker(String(localized: "Default export format:", comment: "Setting label"), selection: $defaultExportFormat) {
                    ForEach(SupportedExportFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }

                Toggle(String(localized: "Include metadata in exports", comment: "Setting label"), isOn: $includeMetadata)
                Toggle(String(localized: "Pretty-print JSON output", comment: "Setting label"), isOn: $prettyPrint)
            }

            Section(String(localized: "About Formats", comment: "Settings section")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(localized: "TopPresenter JSON is the recommended format for full fidelity, including cross-references, footnotes, and section headings.", comment: "Settings info"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
