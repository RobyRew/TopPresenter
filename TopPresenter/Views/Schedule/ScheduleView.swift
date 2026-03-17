//
//  ScheduleView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData

/// Service schedule / playlist management view.
struct ScheduleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PresentationManager.self) private var presentationManager

    @Query(sort: \ServiceSchedule.date, order: .reverse) private var schedules: [ServiceSchedule]

    @State private var selectedSchedule: ServiceSchedule?
    @State private var selectedItemID: UUID?
    @State private var showNewScheduleSheet = false
    @State private var showAddItemSheet = false

    var body: some View {
        HSplitView {
            // Schedule list
            VStack(spacing: 0) {
                HStack {
                    Text(String(localized: "Schedules", comment: "Section title"))
                        .font(.headline)
                    Spacer()
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

                    List(schedule.sortedItems) { item in
                        ScheduleItemRow(item: item, isSelected: selectedItemID == item.id)
                            .onTapGesture {
                                selectedItemID = item.id
                            }
                            .onTapGesture(count: 2) {
                                showScheduleItem(item)
                            }
                            .contextMenu {
                                Button(String(localized: "Show", comment: "Context menu")) {
                                    showScheduleItem(item)
                                }
                                Divider()
                                Button(String(localized: "Delete", comment: "Context menu"), role: .destructive) {
                                    modelContext.delete(item)
                                    try? modelContext.save()
                                }
                            }
                    }
                    .listStyle(.plain)
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
    }

    private func deleteSchedule(_ schedule: ServiceSchedule) {
        if selectedSchedule?.id == schedule.id {
            selectedSchedule = nil
        }
        modelContext.delete(schedule)
        try? modelContext.save()
    }

    private func showScheduleItem(_ item: ScheduleItem) {
        switch item.itemType {
        case "bible":
            presentationManager.showBibleVerse(text: item.content, reference: item.subtitle)
        case "song":
            presentationManager.showSongVerse(text: item.content, title: item.title, verseLabel: item.subtitle)
        case "text":
            presentationManager.showCustomText(text: item.content, title: item.title)
        case "blank":
            presentationManager.goBlack()
        default:
            presentationManager.showCustomText(text: item.content, title: item.title)
        }
    }
}

// MARK: - Schedule Item Row
struct ScheduleItemRow: View {
    let item: ScheduleItem
    let isSelected: Bool

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
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
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

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "New Schedule", comment: "Sheet title"))
                .font(.title2.bold())

            TextField(String(localized: "Schedule Name", comment: "Text field"), text: $name)
                .textFieldStyle(.roundedBorder)

            DatePicker(
                String(localized: "Date:", comment: "Date picker label"),
                selection: $date,
                displayedComponents: .date
            )

            HStack {
                Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Create", comment: "Button")) {
                    let schedule = ServiceSchedule(name: name, date: date)
                    modelContext.insert(schedule)
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty)
                .keyboardShortcut(.defaultAction)
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

    @State private var title = ""
    @State private var content = ""
    @State private var subtitle = ""
    @State private var itemType = "text"

    var body: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Add Schedule Item", comment: "Sheet title"))
                .font(.title2.bold())

            Picker(String(localized: "Type:", comment: "Picker label"), selection: $itemType) {
                Text(String(localized: "Bible", comment: "Item type")).tag("bible")
                Text(String(localized: "Song", comment: "Item type")).tag("song")
                Text(String(localized: "Text", comment: "Item type")).tag("text")
                Text(String(localized: "Blank", comment: "Item type")).tag("blank")
            }
            .pickerStyle(.segmented)

            TextField(String(localized: "Title", comment: "Text field"), text: $title)
                .textFieldStyle(.roundedBorder)

            if itemType != "blank" {
                TextField(String(localized: "Subtitle / Reference", comment: "Text field"), text: $subtitle)
                    .textFieldStyle(.roundedBorder)

                TextEditor(text: $content)
                    .frame(height: 100)
                    .border(.tertiary)
            }

            HStack {
                Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Add", comment: "Button")) {
                    let item = ScheduleItem(
                        title: title.isEmpty && itemType == "blank" ? "Blank Screen" : title,
                        itemType: itemType,
                        content: content,
                        subtitle: subtitle,
                        order: schedule.items.count
                    )
                    item.schedule = schedule
                    try? modelContext.save()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.isEmpty && itemType != "blank")
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 450)
    }
}
