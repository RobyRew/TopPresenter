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
    /// Items whose library reference no longer resolves — greyed + warning icon.
    @State private var missingItemIDs: Set<UUID> = []
    /// Import/export outcome shown to the user (count + any unresolved media).
    @State private var archiveResultMessage: String?

    var body: some View {
        ResizableSplit(storageKey: "split_schedule", minLeading: 240, maxFraction: 0.45) {
            // Schedule list (left third)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(schedule.name)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(schedule.date, style: .date)
                            Text(verbatim: "\u{00B7}")
                            Text(String(localized: "\(schedule.items.count) elemente", comment: "Session row item count"))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
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
        } trailing: {
            // Session detail (right two-thirds): running order + composer
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
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Divider()

                    let items = schedule.sortedItems
                    if items.isEmpty {
                        ContentUnavailableView {
                            Label(String(localized: "Sesiune goal\u{0103}", comment: "Empty session"),
                                  systemImage: "list.bullet.rectangle")
                        } description: {
                            Text(String(localized: "Adaug\u{0103} c\u{00E2}ntece, versete, media sau text din compozitorul de mai jos \u{2014} totul direct din bibliotec\u{0103}.", comment: "Empty session hint"))
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
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

                    Divider()
                    ScheduleContentPicker(schedule: schedule) {
                        refreshMissing(in: schedule)
                    }
                }
                .task(id: missingRefreshKey(schedule)) {
                    refreshMissing(in: schedule)
                }
            } else {
                ContentUnavailableView {
                    Label(String(localized: "Nicio sesiune selectat\u{0103}", comment: "Placeholder"),
                          systemImage: "list.bullet.rectangle")
                } description: {
                    Text(String(localized: "Alege o sesiune din st\u{00E2}nga sau creeaz\u{0103} una nou\u{0103}.", comment: "Placeholder message"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showNewScheduleSheet) {
            NewScheduleSheet()
        }
        .onKeyWindowNotification(.addScheduleItem) { _ in
            // The inline composer replaced the old Add Item sheet.
            if selectedSchedule != nil {
                UserDefaults.standard.set(true, forKey: "scheduleComposerOpen")
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

// MARK: - Schedule Content Picker (the composer)

/// The session COMPOSER — pinned under the running order. Everything is
/// pulled straight from the library: songs and media come from the
/// SearchIndex projections (instant on huge libraries, zero SwiftData
/// faulting per keystroke), Bible passages resolve through the SAME
/// reference parser ⌘K uses, over the active translation's verse index.
/// Adds go through SessionService drafts, so every item carries the stable
/// library-linked payload (nothing free-text unless you choose Text).
struct ScheduleContentPicker: View {
    let schedule: ServiceSchedule
    var onAdded: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @Environment(SearchIndex.self) private var index
    @Environment(LibraryManager.self) private var libraryManager

    @AppStorage("scheduleComposerOpen") private var isOpen = true
    @State private var kind = "song"
    @State private var query = ""
    @State private var textTitle = ""
    @State private var textContent = ""
    @State private var addedNote = ""
    @State private var noteClearTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Label(String(localized: "Adaugă conținut", comment: "Composer title"),
                          systemImage: "plus.circle.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(appAccent)
                    if !addedNote.isEmpty {
                        Text(addedNote)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                    Spacer()
                    Image(systemName: isOpen ? "chevron.down" : "chevron.up")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if isOpen {
                VStack(spacing: 9) {
                    Picker("", selection: $kind) {
                        Text(String(localized: "Cântece", comment: "Composer kind")).tag("song")
                        Text(String(localized: "Biblie", comment: "Composer kind")).tag("bible")
                        Text(String(localized: "Media", comment: "Composer kind")).tag("media")
                        Text(String(localized: "Text", comment: "Composer kind")).tag("text")
                        Text(String(localized: "Negru", comment: "Composer kind")).tag("blank")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    switch kind {
                    case "bible": bibleComposer
                    case "text": textComposer
                    case "blank": blankComposer
                    case "media": listComposer(mediaRows)
                    default: listComposer(songRows)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .frame(height: 236, alignment: .top)
            }
        }
        .background(.quaternary.opacity(0.25))
        .onChange(of: kind) { _, _ in query = "" }
        .onAppear {
            // Make sure the active translation's verse index is (being) built.
            if let id = libraryManager.selectedBibleModule?.id {
                index.indexVerses(moduleID: id)
            }
        }
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: kind == "bible" ? "book.fill" : "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                kind == "bible"
                    ? String(localized: "Referință: Ioan 3:16-18, Psalmi 23…", comment: "Composer bible placeholder")
                    : String(localized: "Caută în bibliotecă…", comment: "Composer search placeholder"),
                text: $query
            )
            .textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private struct PickerEntry: Identifiable {
        let id: String
        let icon: String
        let tint: Color
        let title: String
        let subtitle: String
        let add: () -> Void
    }

    @ViewBuilder
    private func listComposer(_ rows: [PickerEntry]) -> some View {
        searchField
        if rows.isEmpty {
            Text(String(localized: "Niciun rezultat.", comment: "Composer empty"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(rows) { row in
                        HStack(spacing: 8) {
                            Image(systemName: row.icon)
                                .font(.caption)
                                .foregroundStyle(row.tint)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.title).font(.callout).lineLimit(1)
                                if !row.subtitle.isEmpty {
                                    Text(row.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer(minLength: 4)
                            Button(action: row.add) {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(appAccent)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Adaugă la sesiune", comment: "Tooltip"))
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                    }
                }
            }
        }
    }

    private var songRows: [PickerEntry] {
        index.searchSongs(query, limit: 30).map { entry in
            PickerEntry(id: "song:\(entry.id)", icon: "music.note", tint: appAccent,
                        title: entry.title,
                        subtitle: entry.author.isEmpty ? entry.collectionName : entry.author) {
                addSong(entry.id, title: entry.title)
            }
        }
    }

    private var mediaRows: [PickerEntry] {
        let entries = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? Array(index.media.prefix(30))
            : index.searchMedia(query, limit: 30)
        return entries.map { entry in
            PickerEntry(id: "media:\(entry.id)",
                        icon: (MediaKind(rawValue: entry.mediaType) ?? .image).systemImage,
                        tint: appAccent, title: entry.name, subtitle: entry.mediaType.capitalized) {
                addMedia(entry.id, name: entry.name)
            }
        }
    }

    // MARK: Bible

    private var referenceMatch: BibleReferenceMatch? {
        BibleReferenceParser.parse(query, books: index.books)
    }

    private var referenceVerses: [VerseIndexEntry] {
        guard let r = referenceMatch else { return [] }
        return index.verses.filter {
            $0.bookNumber == r.bookNumber && $0.chapter == r.chapter
                && (r.verseStart == nil || ($0.verse >= r.verseStart! && $0.verse <= (r.verseEnd ?? r.verseStart!)))
        }
    }

    @ViewBuilder
    private var bibleComposer: some View {
        searchField
        let verses = referenceVerses
        if let first = verses.first, let last = verses.last {
            let reference = first.verse == last.verse
                ? "\(first.bookName) \(first.chapter):\(first.verse)"
                : "\(first.bookName) \(first.chapter):\(first.verse)-\(last.verse)"
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(reference).font(.callout.weight(.semibold))
                    Text(String(localized: "\(verses.count) versete", comment: "Composer verse count"))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        addBible(verses: verses, reference: reference)
                    } label: {
                        Label(String(localized: "Adaugă", comment: "Button"), systemImage: "plus")
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                }
                Text(verses.prefix(4).map { "(\($0.verse)) \($0.text)" }.joined(separator: " "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer(minLength: 0)
        } else {
            Text(query.trimmingCharacters(in: .whitespaces).isEmpty
                 ? String(localized: "Scrie o referință — pasajul se leagă de traducerea activă (\(libraryManager.selectedBibleModule?.abbreviation ?? "–")).", comment: "Composer bible hint")
                 : String(localized: "Referință nerecunoscută.", comment: "Composer bible no match"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Text / blank

    @ViewBuilder
    private var textComposer: some View {
        TextField(String(localized: "Titlu", comment: "Composer text title"), text: $textTitle)
            .textFieldStyle(.roundedBorder)
        TextField(String(localized: "Conținut…", comment: "Composer text content"),
                  text: $textContent, axis: .vertical)
            .textFieldStyle(.roundedBorder)
            .lineLimit(3...5)
        HStack {
            Spacer()
            Button {
                SessionService.append(.text(title: textTitle, content: textContent),
                                      to: schedule, context: modelContext)
                noteAdded(textTitle.isEmpty ? String(localized: "Text", comment: "Composer note") : textTitle)
                textTitle = ""; textContent = ""
            } label: {
                Label(String(localized: "Adaugă", comment: "Button"), systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(textTitle.trimmingCharacters(in: .whitespaces).isEmpty
                      && textContent.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private var blankComposer: some View {
        VStack(spacing: 10) {
            Text(String(localized: "Un moment de ecran negru în sesiune (rugăciune, tranziție).", comment: "Composer blank hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                SessionService.append(.blank, to: schedule, context: modelContext)
                noteAdded(String(localized: "Ecran negru", comment: "Composer note"))
            } label: {
                Label(String(localized: "Adaugă ecran negru", comment: "Button"), systemImage: "rectangle.fill")
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Adds (predicate + fetchLimit 1 — never fetch-all)

    private func addSong(_ id: UUID, title: String) {
        var d = FetchDescriptor<Song>(predicate: Song.predicate(forID: id))
        d.fetchLimit = 1
        guard let song = (try? modelContext.fetch(d))?.first else { return }
        SessionService.append(.song(song, version: nil), to: schedule, context: modelContext)
        noteAdded(title)
    }

    private func addMedia(_ id: UUID, name: String) {
        var d = FetchDescriptor<MediaItem>(predicate: MediaItem.predicate(forID: id))
        d.fetchLimit = 1
        guard let media = (try? modelContext.fetch(d))?.first else { return }
        SessionService.append(.media(media), to: schedule, context: modelContext)
        noteAdded(name)
    }

    private func addBible(verses: [VerseIndexEntry], reference: String) {
        guard let first = verses.first, let last = verses.last else { return }
        let snapshot = verses.map { "(\($0.verse)) \($0.text)" }.joined(separator: " ")
        SessionService.append(
            .bible(translation: libraryManager.selectedBibleModule?.abbreviation ?? "",
                   bookNumber: first.bookNumber, bookName: first.bookName,
                   chapter: first.chapter, verseStart: first.verse, verseEnd: last.verse,
                   displayReference: reference, snapshotText: snapshot),
            to: schedule, context: modelContext
        )
        noteAdded(reference)
    }

    private func noteAdded(_ what: String) {
        onAdded()
        withAnimation(.easeOut(duration: 0.15)) {
            addedNote = String(localized: "„\(what)” adăugat ✓", comment: "Composer added note")
        }
        noteClearTask?.cancel()
        noteClearTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { addedNote = "" }
        }
    }
}
