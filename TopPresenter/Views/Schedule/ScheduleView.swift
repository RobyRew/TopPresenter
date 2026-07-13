//
//  ScheduleView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Service schedule / playlist management view.
struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(SessionRunner.self) private var runner

    @Query(sort: \ServiceSchedule.date, order: .reverse) private var schedules: [ServiceSchedule]

    @State private var selectedSchedule: ServiceSchedule?
    @State private var selectedItemID: UUID?
    @State private var showNewScheduleSheet = false
    @State private var showAddItemSheet = false
    /// Items whose library reference no longer resolves — greyed + warning icon.
    @State private var missingItemIDs: Set<UUID> = []
    /// Import/export outcome shown to the user (count + any unresolved media).
    @State private var archiveResultMessage: String?

    var body: some View {
        HSplitView {
            // Schedule list
            VStack(spacing: 0) {
                HStack {
                    Text(String(localized: "Schedules", comment: "Section title"))
                        .font(.headline)
                    Spacer()
                    Button {
                        importSessions()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .controlSize(.small)
                    .help(String(localized: "Importă sesiuni (.tpschedule)", comment: "Tooltip"))
                    Button {
                        showNewScheduleSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                Divider()

                List(schedules, selection: Binding(
                    get: { selectedSchedule?.id },
                    set: { newID in
                        if let id = newID {
                            selectedSchedule = schedules.first { $0.id == id }
                            // Mirror into the per-window manager — drives the tab
                            // title and the right panel (no notification round-trip).
                            libraryManager.selectedSchedule = selectedSchedule
                        }
                    }
                )) { schedule in
                    VStack(alignment: .leading) {
                        Text(schedule.name)
                            .font(.body)
                        Text(schedule.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(schedule.id)
                    .contextMenu {
                        Button {
                            exportSession(schedule)
                        } label: {
                            Label(String(localized: "Exportă sesiunea…", comment: "Context menu"),
                                  systemImage: "square.and.arrow.up")
                        }
                        Divider()
                        Button(String(localized: "Delete", comment: "Context menu"), role: .destructive) {
                            deleteSchedule(schedule)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 200, maxWidth: 280)

            // Schedule items
            if let schedule = selectedSchedule {
                VStack(spacing: 0) {
                    HStack {
                        Text(schedule.name)
                            .font(.headline)
                        Spacer()
                        if runner.isRunning, runner.activeScheduleID == schedule.id {
                            Button {
                                runner.stop()
                            } label: {
                                Label(String(localized: "Oprește", comment: "Button — stop session"),
                                      systemImage: "stop.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                        } else {
                            Button {
                                runner.start(schedule, context: modelContext)
                            } label: {
                                Label(String(localized: "Pornește sesiunea", comment: "Button — start session runner"),
                                      systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(schedule.sortedItems.isEmpty)
                            .help(String(localized: "Rulează sesiunea element cu element (înainte/înapoi în panoul din dreapta).", comment: "Tooltip"))
                        }
                        Button {
                            showAddItemSheet = true
                        } label: {
                            Label(
                                String(localized: "Add Item", comment: "Button"),
                                systemImage: "plus"
                            )
                        }
                        .controlSize(.small)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    let items = schedule.sortedItems
                    List(Array(items.enumerated()), id: \.element.id) { index, item in
                        ScheduleItemRow(
                            item: item,
                            isSelected: selectedItemID == item.id,
                            isMissing: missingItemIDs.contains(item.id),
                            isCurrent: runner.isRunning
                                && runner.activeScheduleID == schedule.id
                                && runner.itemIndex == index
                        )
                        .onTapGesture(count: 2) {
                            presentItem(item, at: index, in: schedule)
                        }
                        .onTapGesture {
                            selectedItemID = item.id
                            // While running, clicking an item JUMPS the session to it.
                            if runner.isRunning, runner.activeScheduleID == schedule.id {
                                runner.jump(toItem: index, context: modelContext)
                            }
                        }
                        .contextMenu {
                            Button(String(localized: "Show", comment: "Context menu")) {
                                presentItem(item, at: index, in: schedule)
                            }
                            Divider()
                            Button {
                                moveItem(item, direction: -1, in: schedule)
                            } label: {
                                Label(String(localized: "Mută sus", comment: "Context menu"), systemImage: "arrow.up")
                            }
                            .disabled(index == 0)
                            Button {
                                moveItem(item, direction: +1, in: schedule)
                            } label: {
                                Label(String(localized: "Mută jos", comment: "Context menu"), systemImage: "arrow.down")
                            }
                            .disabled(index == items.count - 1)
                            Divider()
                            Button(String(localized: "Delete", comment: "Context menu"), role: .destructive) {
                                modelContext.delete(item)
                                try? modelContext.save()
                                refreshMissing(in: schedule)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
                .task(id: missingRefreshKey(schedule)) {
                    refreshMissing(in: schedule)
                }
            } else {
                VStack {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Select or create a schedule", comment: "Placeholder"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showNewScheduleSheet) {
            NewScheduleSheet()
        }
        .sheet(isPresented: $showAddItemSheet) {
            if let schedule = selectedSchedule {
                AddScheduleItemSheet(schedule: schedule)
            }
        }
        .onKeyWindowNotification(.addScheduleItem) { _ in
            if selectedSchedule != nil {
                showAddItemSheet = true
            }
        }
        .onKeyWindowNotification(.newSchedule) { _ in
            showNewScheduleSheet = true
        }
        .alert(
            archiveResultMessage ?? "",
            isPresented: Binding(get: { archiveResultMessage != nil },
                                 set: { if !$0 { archiveResultMessage = nil } })
        ) {
            Button(String(localized: "OK", comment: "Alert button")) { archiveResultMessage = nil }
        }
    }

    // MARK: - Import / Export (.tpschedule)

    private func exportSession(_ schedule: ServiceSchedule) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(exportedAs: "com.robyrew.toppresenter.schedule")]
        panel.nameFieldStringValue = "\(schedule.name).\(SessionArchiveService.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try SessionArchiveService.export(schedule).write(to: url)
        } catch {
            archiveResultMessage = String(localized: "Exportul a eșuat: \(error.localizedDescription)", comment: "Export error")
        }
    }

    private func importSessions() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [UTType(exportedAs: "com.robyrew.toppresenter.schedule"), .json]
        guard panel.runModal() == .OK else { return }

        // Expand folders → .tpschedule files inside (mirrors theme import).
        var files: [URL] = []
        let fm = FileManager.default
        for url in panel.urls {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                files.append(contentsOf: children.filter { $0.pathExtension == SessionArchiveService.fileExtension })
            } else {
                files.append(url)
            }
        }

        var imported = 0
        var unresolved: [String] = []
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            if let result = try? SessionArchiveService.importSession(data, context: modelContext) {
                imported += 1
                unresolved.append(contentsOf: result.unresolvedMedia)
            }
        }

        var message = String(localized: "\(imported) sesiuni importate.", comment: "Import result")
        if !unresolved.isEmpty {
            message += "\n" + String(localized: "Media lipsă din bibliotecă: \(unresolved.joined(separator: ", ")). Importă fișierele în modulul Media pentru rezolvare automată.", comment: "Import result — missing media")
        }
        archiveResultMessage = message
    }

    private func deleteSchedule(_ schedule: ServiceSchedule) {
        if selectedSchedule?.id == schedule.id {
            selectedSchedule = nil
        }
        modelContext.delete(schedule)
        try? modelContext.save()
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }

    /// Present via THE one presenter (SessionRunner): jump when this schedule is
    /// running, one-shot resolution otherwise.
    private func presentItem(_ item: ScheduleItem, at index: Int, in schedule: ServiceSchedule) {
        selectedItemID = item.id
        if runner.isRunning, runner.activeScheduleID == schedule.id {
            runner.jump(toItem: index, context: modelContext)
        } else {
            runner.presentOnce(item, context: modelContext)
        }
    }

    private func moveItem(_ item: ScheduleItem, direction: Int, in schedule: ServiceSchedule) {
        let items = schedule.sortedItems
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let target = idx + direction
        guard target >= 0, target < items.count else { return }
        let other = items[target]
        let tmp = item.order
        item.order = other.order
        other.order = tmp
        try? modelContext.save()
    }

    /// Cheap identity for when the missing-check must re-run.
    private func missingRefreshKey(_ schedule: ServiceSchedule) -> String {
        "\(schedule.id.uuidString)-\(schedule.items.count)"
    }

    private func refreshMissing(in schedule: ServiceSchedule) {
        missingItemIDs = Set(schedule.sortedItems
            .filter { SessionService.resolve($0, context: modelContext).isMissing }
            .map(\.id))
    }
}

// MARK: - Schedule Item Row
struct ScheduleItemRow: View {
    let item: ScheduleItem
    let isSelected: Bool
    /// Library reference no longer resolves — greyed out + warning icon.
    var isMissing: Bool = false
    /// The running session is ON this item right now.
    var isCurrent: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconForType(item.itemType))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.body)
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isMissing {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .help(String(localized: "Element lipsă din bibliotecă", comment: "Missing session item badge"))
            }
            if isCurrent {
                Image(systemName: "play.circle.fill")
                    .font(.caption)
                    .foregroundStyle(appAccent)
                    .help(String(localized: "Elementul curent al sesiunii", comment: "Current session item badge"))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .opacity(isMissing ? 0.5 : 1)
        .background(
            isCurrent ? appAccent.opacity(0.22)
                : isSelected ? appHighlight.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 4)
        )
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "bible": return "book.fill"
        case "song": return "music.note"
        case "text": return "text.alignleft"
        case "media": return "photo"
        case "blank": return "rectangle"
        default: return "doc"
        }
    }
}

// MARK: - New Schedule Sheet
struct NewScheduleSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var notes = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "New Schedule", comment: "Sheet title"))
                .font(.title2.bold())

            Form {
                TextField(
                    String(localized: "Name", comment: "Form label"),
                    text: $name
                )
                DatePicker(
                    String(localized: "Date", comment: "Form label"),
                    selection: $date,
                    displayedComponents: .date
                )
                TextField(
                    String(localized: "Notes", comment: "Form label"),
                    text: $notes,
                    axis: .vertical
                )
                .lineLimit(3...6)
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel", comment: "Button")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "Create", comment: "Button")) {
                    let schedule = ServiceSchedule(
                        name: name.isEmpty
                            ? String(localized: "Untitled Schedule", comment: "Default name")
                            : name,
                        date: date,
                        notes: notes
                    )
                    modelContext.insert(schedule)
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Add Schedule Item Sheet
struct AddScheduleItemSheet: View {
    let schedule: ServiceSchedule

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MediaItem.importDate, order: .reverse) private var mediaItems: [MediaItem]

    @State private var itemType = "text"
    @State private var title = ""
    @State private var content = ""
    @State private var subtitle = ""
    @State private var selectedMediaID: UUID?

    private let itemTypes = [
        ("bible", String(localized: "Bible Verse", comment: "Item type")),
        ("song", String(localized: "Song", comment: "Item type")),
        ("media", String(localized: "Media", comment: "Item type")),
        ("text", String(localized: "Custom Text", comment: "Item type")),
        ("blank", String(localized: "Blank / Black Screen", comment: "Item type")),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "Add Item", comment: "Sheet title"))
                .font(.title2.bold())

            Form {
                Picker(String(localized: "Type", comment: "Form label"), selection: $itemType) {
                    ForEach(itemTypes, id: \.0) { type in
                        Text(type.1).tag(type.0)
                    }
                }

                if itemType == "media" {
                    // Real library reference — resolved at present time.
                    Picker(String(localized: "Fișier media", comment: "Form label"), selection: $selectedMediaID) {
                        Text(String(localized: "Alege…", comment: "Picker placeholder")).tag(nil as UUID?)
                        ForEach(mediaItems) { media in
                            Text(verbatim: "\(media.name) (\(media.mediaType))").tag(media.id as UUID?)
                        }
                    }
                    if mediaItems.isEmpty {
                        Text(String(localized: "Nu ai media importată — adaugă întâi în modulul Media.", comment: "Form hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if itemType != "blank" {
                    TextField(
                        String(localized: "Title", comment: "Form label"),
                        text: $title
                    )

                    TextField(
                        itemType == "bible"
                            ? String(localized: "Reference (e.g., John 3:16)", comment: "Form label")
                            : String(localized: "Subtitle", comment: "Form label"),
                        text: $subtitle
                    )

                    TextField(
                        String(localized: "Content", comment: "Form label"),
                        text: $content,
                        axis: .vertical
                    )
                    .lineLimit(4...10)

                    if itemType == "bible" || itemType == "song" {
                        // The library-linked path is right-click from Bible/Songs.
                        Text(String(localized: "Sfat: click-dreapta pe un verset sau cântec → „Adaugă la sesiune” îl leagă de bibliotecă (se actualizează automat).", comment: "Form hint"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "Cancel", comment: "Button")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(String(localized: "Add", comment: "Button")) {
                    addItem()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var canAdd: Bool {
        switch itemType {
        case "blank": return true
        case "media": return selectedMediaID != nil
        default: return !title.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func addItem() {
        switch itemType {
        case "media":
            guard let media = mediaItems.first(where: { $0.id == selectedMediaID }) else { return }
            SessionService.append(.media(media), to: schedule, context: modelContext)
        case "text":
            SessionService.append(.text(title: title, content: content), to: schedule, context: modelContext)
        case "blank":
            SessionService.append(.blank, to: schedule, context: modelContext)
        default:
            // Free-form bible/song entry — a display snapshot without a library
            // link (the linked path is right-click from Bible/Songs).
            let nextOrder = (schedule.items.map(\.order).max() ?? -1) + 1
            let item = ScheduleItem(title: title, itemType: itemType,
                                    content: content, subtitle: subtitle, order: nextOrder)
            item.schedule = schedule
            modelContext.insert(item)
            try? modelContext.save()
        }
    }
}
