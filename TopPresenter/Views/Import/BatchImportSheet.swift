//
//  BatchImportSheet.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import SwiftUI
import SwiftData

/// Sheet for importing multiple files at once (drag & drop or file picker).
struct BatchImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(LibraryManager.self) private var libraryManager

    @State var pendingFiles: [PendingImportFile]
    @State private var isImporting = false
    @State private var completedCount = 0

    private var bibleFiles: [PendingImportFile] {
        pendingFiles.filter { if case .bible = $0.category { return true }; return false }
    }

    private var songFiles: [PendingImportFile] {
        pendingFiles.filter { if case .song = $0.category { return true }; return false }
    }

    private var mediaFiles: [PendingImportFile] {
        pendingFiles.filter { if case .media = $0.category { return true }; return false }
    }

    private var unknownFiles: [PendingImportFile] {
        pendingFiles.filter { if case .unknown = $0.category { return true }; return false }
    }

    private var totalKnown: Int {
        bibleFiles.count + songFiles.count + mediaFiles.count
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading) {
                    Text(String(localized: "Batch Import", comment: "Sheet title"))
                        .font(.title2.bold())
                    Text(String(localized: "\(pendingFiles.count) files detected", comment: "Batch import subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // File list
            ScrollView {
                VStack(spacing: 12) {
                    if !bibleFiles.isEmpty {
                        fileSection(
                            title: String(localized: "Bible Modules", comment: "Section"),
                            icon: "book.fill",
                            color: .blue,
                            files: bibleFiles
                        )
                    }

                    if !songFiles.isEmpty {
                        fileSection(
                            title: String(localized: "Songs", comment: "Section"),
                            icon: "music.note",
                            color: .purple,
                            files: songFiles
                        )
                    }

                    if !mediaFiles.isEmpty {
                        fileSection(
                            title: String(localized: "Media", comment: "Section"),
                            icon: "photo.on.rectangle",
                            color: .green,
                            files: mediaFiles
                        )
                    }

                    if !unknownFiles.isEmpty {
                        fileSection(
                            title: String(localized: "Unrecognized Files", comment: "Section"),
                            icon: "questionmark.circle",
                            color: .orange,
                            files: unknownFiles
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: 320)

            // Progress
            if isImporting {
                VStack(spacing: 4) {
                    ProgressView(
                        value: Double(completedCount),
                        total: Double(max(totalKnown, 1))
                    ) {
                        Text(String(localized: "Importing \(completedCount) of \(totalKnown)...", comment: "Import progress"))
                            .font(.caption)
                    }
                    .progressViewStyle(.linear)
                }
            }

            // Actions
            HStack {
                Button(String(localized: "Cancel", comment: "Button")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                if !unknownFiles.isEmpty {
                    Text(String(localized: "\(unknownFiles.count) file(s) will be skipped", comment: "Warning"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Spacer()

                Button {
                    startBatchImport()
                } label: {
                    Label(
                        String(localized: "Import All (\(totalKnown))", comment: "Button"),
                        systemImage: "square.and.arrow.down"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(totalKnown == 0 || isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .frame(minHeight: 400)
    }

    private func fileSection(title: String, icon: String, color: Color, files: [PendingImportFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("(\(files.count))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(files) { file in
                fileRow(file)
            }
        }
    }

    private func fileRow(_ file: PendingImportFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: file.status.icon)
                .foregroundStyle(file.status.color)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.fileName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.category.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            switch file.status {
            case .success(let name):
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .lineLimit(1)
            case .failed(let error):
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
            case .importing:
                ProgressView()
                    .controlSize(.small)
            case .pending:
                EmptyView()
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
    }

    private func startBatchImport() {
        guard !isImporting else { return }   // re-entry guard (double-click, reopen)
        isImporting = true
        completedCount = 0
        // Fresh run: forget outcomes of a previous invocation of this sheet.
        for idx in pendingFiles.indices { pendingFiles[idx].status = .pending }

        Task {
            // Import Bibles OFF the main actor — BackgroundImportActor owns its
            // own serialized ModelContext on the shared container (crash fix:
            // the view's context must never do heavy work across thread hops).
            let importer = BackgroundImportActor(modelContainer: modelContext.container)
            await importer.importBibles(files: bibleFiles) { fileID, status in
                if let idx = pendingFiles.firstIndex(where: { $0.id == fileID }) {
                    pendingFiles[idx].status = status
                }
                if case .success = status { completedCount += 1 }
                if case .failed = status { completedCount += 1 }
            }

            // Import Songs
            _ = await DragDropImportHandler.importSongs(
                files: songFiles,
                collectionName: "Imported Songs",
                modelContext: modelContext
            ) { fileID, status in
                Task { @MainActor in
                    if let idx = pendingFiles.firstIndex(where: { $0.id == fileID }) {
                        pendingFiles[idx].status = status
                    }
                    if case .success = status { completedCount += 1 }
                    if case .failed = status { completedCount += 1 }
                }
            }

            // Import Media
            await MainActor.run {
                let _ = DragDropImportHandler.importMedia(
                    files: mediaFiles,
                    modelContext: modelContext
                ) { fileID, status in
                    if let idx = pendingFiles.firstIndex(where: { $0.id == fileID }) {
                        pendingFiles[idx].status = status
                    }
                    if case .success = status { completedCount += 1 }
                    if case .failed = status { completedCount += 1 }
                }
            }

            await MainActor.run {
                isImporting = false
                let succeeded = pendingFiles.filter {
                    if case .success = $0.status { return true }; return false
                }.count
                let failed = pendingFiles.filter {
                    if case .failed = $0.status { return true }; return false
                }.count

                if failed == 0 {
                    appState.showSuccess(
                        String(localized: "Batch Import Complete", comment: "Alert"),
                        message: String(localized: "Successfully imported \(succeeded) file(s).", comment: "Alert")
                    )
                } else {
                    appState.showError(
                        String(localized: "Batch Import Finished", comment: "Alert"),
                        message: String(localized: "\(succeeded) succeeded, \(failed) failed.", comment: "Alert")
                    )
                }
                dismiss()
            }
        }
    }
}
