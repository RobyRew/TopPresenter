//
//  AddToSessionMenu.swift
//  TopPresenter
//
//  Reusable „Adaugă la sesiune" context-menu fragment — dropped into the Bible
//  verse menu, the Songs menu, and the Media grid menu. Lists the most recent
//  sessions plus „Sesiune nouă…", which creates a dated session instantly and
//  appends (no sheet from a dismissing context menu — rename in the Schedule tab).
//

import SwiftUI
import SwiftData

struct AddToSessionMenu: View {
    /// Built lazily on tap — nil means nothing to add (menu hidden).
    let draft: () -> SessionItemDraft?

    @Query(sort: \ServiceSchedule.date, order: .reverse) private var schedules: [ServiceSchedule]
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    var body: some View {
        Menu {
            ForEach(schedules.prefix(8)) { schedule in
                Button {
                    append(to: schedule)
                } label: {
                    Text(verbatim: "\(schedule.name) – \(schedule.date.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            if !schedules.isEmpty { Divider() }
            Button {
                let session = SessionService.createSession(name: "", context: modelContext)
                append(to: session)
            } label: {
                Label(String(localized: "Sesiune nouă…", comment: "Menu — create session and add"),
                      systemImage: "plus")
            }
        } label: {
            Label(String(localized: "Adaugă la sesiune", comment: "Context menu"),
                  systemImage: "text.badge.plus")
        }
    }

    private func append(to schedule: ServiceSchedule) {
        guard let draft = draft() else { return }
        SessionService.append(draft, to: schedule, context: modelContext)
        appState.showSuccess(
            String(localized: "Adăugat la sesiune", comment: "Toast title"),
            message: String(localized: "Elementul a fost adăugat la „\(schedule.name)”.", comment: "Toast message")
        )
    }
}
