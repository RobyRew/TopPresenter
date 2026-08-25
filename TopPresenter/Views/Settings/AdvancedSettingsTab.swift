//
//  AdvancedSettingsTab.swift
//  TopPresenter
//
//  Settings ▸ Avansat — hidden behind the 10-click unlock on the sidebar
//  Settings row (SidebarView.registerSettingsClick). Power/rescue operations:
//  full reindex plus the destructive delete-alls, every destructive action
//  behind its own confirmation.
//

import SwiftUI
import SwiftData

struct AdvancedSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SearchIndex.self) private var index
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(HistoryStore.self) private var history
    @Environment(AppState.self) private var appState
    @Environment(LibraryTaskRunner.self) private var libraryTasks
    @Environment(PresentationManager.self) private var presentationManager

    /// Themes ticked for deletion. Deleting is one confirmed action over a
    /// selection rather than a row of individual buttons, because clearing out
    /// a bad import means removing a dozen at once.
    @State private var themesToDelete: Set<UUID> = []
    @State private var confirmThemeDelete = false
    @State private var themeDeleteBlockers: [String] = []

    @State private var pendingAction: DestructiveAction?
    @State private var isWorking = false
    @State private var lastActionNote = ""

    private enum DestructiveAction: String, Identifiable {
        case deleteSongs, deleteBibles, deleteHistory
        var id: String { rawValue }

        var title: String {
            switch self {
            case .deleteSongs: return String(localized: "Șterge TOATE cântecele?", comment: "Advanced confirm title")
            case .deleteBibles: return String(localized: "Șterge TOATE Bibliile?", comment: "Advanced confirm title")
            case .deleteHistory: return String(localized: "Șterge tot istoricul?", comment: "Advanced confirm title")
            }
        }
        var message: String {
            switch self {
            case .deleteSongs:
                return String(localized: "Toate colecțiile, cântecele, versiunile și cărțile de cântări dispar definitiv. Nu se poate anula.", comment: "Advanced confirm message")
            case .deleteBibles:
                return String(localized: "Toate traducerile importate (cărți, capitole, versete) dispar definitiv. Nu se poate anula.", comment: "Advanced confirm message")
            case .deleteHistory:
                return String(localized: "Istoricul prezentărilor ȘI al căutărilor ⌘K dispare definitiv. Nu se poate anula.", comment: "Advanced confirm message")
            }
        }
        var buttonLabel: String {
            switch self {
            case .deleteSongs: return String(localized: "Șterge cântecele", comment: "Advanced confirm button")
            case .deleteBibles: return String(localized: "Șterge Bibliile", comment: "Advanced confirm button")
            case .deleteHistory: return String(localized: "Șterge istoricul", comment: "Advanced confirm button")
            }
        }
    }

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Cântece indexate", comment: "Advanced stat"),
                               value: "\(index.songs.count)")
                LabeledContent(String(localized: "Versete indexate (traducerea activă)", comment: "Advanced stat"),
                               value: "\(index.verses.count)")
                LabeledContent(String(localized: "Evenimente în istoric", comment: "Advanced stat"),
                               value: "\(history.totalEvents())")
                LabeledContent(String(localized: "Căutări ⌘K înregistrate", comment: "Advanced stat"),
                               value: "\(history.totalSearches())")

                HStack {
                    Button {
                        reindexAll()
                    } label: {
                        Label(String(localized: "Reindexează tot", comment: "Advanced button"),
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(isWorking || index.isBuilding || index.isIndexingVerses)

                    if isWorking || index.isBuilding || index.isIndexingVerses {
                        ProgressView().controlSize(.small).padding(.leading, 4)
                    }
                    Spacer()
                }
            } header: {
                Text(String(localized: "Indexare", comment: "Advanced section"))
            } footer: {
                Text(String(localized: "Șterge cache-urile de căutare (memorie + disc + Spotlight) și reconstruiește indexul din bibliotecă. Indexarea rulează oricum automat la import — folosește doar dacă rezultatele par greșite.", comment: "Advanced footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if presentationManager.themes.isEmpty {
                    Text(String(localized: "Nicio temă salvată.", comment: "Advanced empty"))
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    ForEach(presentationManager.themes) { theme in
                        Toggle(isOn: Binding(
                            get: { themesToDelete.contains(theme.id) },
                            set: { on in
                                if on { themesToDelete.insert(theme.id) }
                                else { themesToDelete.remove(theme.id) }
                            }
                        )) {
                            HStack(spacing: 6) {
                                Text(theme.name)
                                if presentationManager.activeThemeID == theme.id {
                                    Text(String(localized: "activă", comment: "Active theme badge"))
                                        .font(.caption2)
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(Capsule().fill(.tint.opacity(0.18)))
                                }
                            }
                        }
                    }

                    HStack {
                        Button(role: .destructive) {
                            confirmThemeDelete = true
                        } label: {
                            Label(String(localized: "Șterge temele bifate (\(themesToDelete.count))",
                                         comment: "Advanced button"),
                                  systemImage: "trash")
                        }
                        .disabled(themesToDelete.isEmpty)

                        Button(String(localized: "Deselectează", comment: "Advanced button")) {
                            themesToDelete = []
                        }
                        .disabled(themesToDelete.isEmpty)
                        Spacer()
                    }

                    if !themeDeleteBlockers.isEmpty {
                        Text(String(localized: "Încă folosite de: \(themeDeleteBlockers.joined(separator: ", "))",
                                    comment: "Advanced note"))
                            .font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } header: {
                Text(String(localized: "Teme", comment: "Advanced section"))
            } footer: {
                Text(String(localized: "Șterge teme salvate fără să treci prin galeria din editor. O temă folosită de un prezentator nu se șterge — îți spune care.", comment: "Advanced footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                destructiveRow(String(localized: "Șterge toate cântecele", comment: "Advanced button"),
                               icon: "music.note", action: .deleteSongs)
                destructiveRow(String(localized: "Șterge toate Bibliile", comment: "Advanced button"),
                               icon: "book.closed", action: .deleteBibles)
                destructiveRow(String(localized: "Șterge istoricul (prezentări + căutări)", comment: "Advanced button"),
                               icon: "clock.arrow.circlepath", action: .deleteHistory)

                Button {
                    PaletteRecentsStore.shared.clear()
                    lastActionNote = String(localized: "Recentele ⌘K au fost golite.", comment: "Advanced note")
                } label: {
                    Label(String(localized: "Golește recentele ⌘K", comment: "Advanced button"),
                          systemImage: "clock")
                }
                .disabled(isWorking)
            } header: {
                Text(String(localized: "Date (ireversibil)", comment: "Advanced section"))
            } footer: {
                if !lastActionNote.isEmpty {
                    Text(lastActionNote).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button {
                    appState.advancedSettingsUnlocked = false
                } label: {
                    Label(String(localized: "Ascunde meniul avansat", comment: "Advanced button"),
                          systemImage: "eye.slash")
                }
            } footer: {
                Text(String(localized: "Meniul se ascunde automat când părăsești Setările și reapare cu 10 click-uri rapide pe butonul Setări din bara laterală.", comment: "Advanced footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .alert(
            pendingAction?.title ?? "",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { action in
            Button(role: .destructive) { perform(action) } label: { Text(action.buttonLabel) }
            Button(String(localized: "Cancel", comment: "Alert button"), role: .cancel) {}
        } message: { action in
            Text(action.message)
        }
        .alert(String(localized: "Șterge \(themesToDelete.count) teme?", comment: "Advanced confirm title"),
               isPresented: $confirmThemeDelete) {
            Button(String(localized: "Șterge", comment: "Alert button"), role: .destructive) {
                deleteSelectedThemes()
            }
            Button(String(localized: "Cancel", comment: "Alert button"), role: .cancel) {}
        } message: {
            Text(String(localized: "Temele dispar din galerie. Layout-urile care le-au folosit rămân neschimbate — o temă este o fotografie salvată, nu o legătură vie.", comment: "Advanced confirm message"))
        }
    }

    /// Deletes what is ticked, keeping any theme a presenter still points at.
    ///
    /// `deleteTheme` refuses those and names the presenters; a refusal leaves
    /// the theme ticked so the reason stays attached to something visible.
    private func deleteSelectedThemes() {
        var blockers: [String] = []
        for id in themesToDelete {
            let refused = presentationManager.deleteTheme(id: id)
            if refused.isEmpty {
                themesToDelete.remove(id)
            } else {
                blockers.append(contentsOf: refused)
            }
        }
        themeDeleteBlockers = Array(Set(blockers)).sorted()
        if blockers.isEmpty {
            lastActionNote = String(localized: "Temele bifate au fost șterse.", comment: "Advanced note")
        }
    }

    private func destructiveRow(_ title: String, icon: String, action: DestructiveAction) -> some View {
        Button(role: .destructive) {
            pendingAction = action
        } label: {
            Label(title, systemImage: icon)
        }
        .disabled(isWorking)
    }

    // MARK: Operations

    private func reindexAll() {
        guard !isWorking else { return }
        isWorking = true
        lastActionNote = ""
        Task {
            await index.reindexEverything(activeModuleID: libraryManager.selectedBibleModule?.id)
            isWorking = false
            lastActionNote = String(localized: "Reindexare pornită — se termină în fundal.", comment: "Advanced note")
        }
    }

    private func perform(_ action: DestructiveAction) {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        switch action {
        case .deleteSongs:
            // Was the Bibles' beach ball in miniature: fetch every collection,
            // song and songbook onto the MAIN context, delete them one object
            // at a time, save once. Now three batch deletes on the maintenance
            // actor — and the note is written when the job finishes, not while
            // it is still running, so it cannot claim success before there is
            // any.
            libraryTasks.deleteAllSongs(clearing: libraryManager) { succeeded in
                lastActionNote = succeeded
                    ? String(localized: "Toate cântecele au fost șterse.", comment: "Advanced note")
                    : String(localized: "Ștergerea nu a putut fi salvată.", comment: "Advanced error")
            }

        case .deleteBibles:
            // THE six-minute beach ball. This used to delete every module on
            // the MAIN context and save once at the end: seventy Bibles is over
            // two million cascade-deleted rows in a single transaction, on the
            // thread that draws the window. Moving it to a background actor was
            // only half the cure — it still built every one of those objects in
            // order to delete them. It runs as a batch delete now, in SQL, with
            // a progress strip and a Stop button.
            let modules = (try? modelContext.fetch(FetchDescriptor<BibleModule>())) ?? []
            VerseIndexCache.deleteAll()
            libraryTasks.deleteBibleModules(modules, searchIndex: index,
                                            clearing: libraryManager)
            lastActionNote = String(localized: "Se șterg \(modules.count) Biblii…", comment: "Advanced note")

        case .deleteHistory:
            history.clearAll()
            lastActionNote = String(localized: "Istoricul a fost șters.", comment: "Advanced note")
        }
    }
}
