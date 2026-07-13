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

    @AppStorage("advancedSettingsUnlocked") private var advancedUnlocked = false

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
                    advancedUnlocked = false
                } label: {
                    Label(String(localized: "Ascunde meniul avansat", comment: "Advanced button"),
                          systemImage: "eye.slash")
                }
            } footer: {
                Text(String(localized: "Meniul reapare cu 10 click-uri rapide pe butonul Setări din bara laterală.", comment: "Advanced footer"))
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
            // Collections cascade their songs; orphan songs + songbooks swept after.
            for col in (try? modelContext.fetch(FetchDescriptor<SongCollection>())) ?? [] {
                modelContext.delete(col)
            }
            for song in (try? modelContext.fetch(FetchDescriptor<Song>())) ?? [] {
                modelContext.delete(song)
            }
            for book in (try? modelContext.fetch(FetchDescriptor<Songbook>())) ?? [] {
                modelContext.delete(book)
            }
            try? modelContext.save()
            libraryManager.selectedSongCollection = nil
            libraryManager.selectedSong = nil
            libraryManager.selectedSongVersion = nil
            libraryManager.selectedSongVerse = nil
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            lastActionNote = String(localized: "Toate cântecele au fost șterse.", comment: "Advanced note")

        case .deleteBibles:
            libraryManager.selectedBibleModule = nil
            libraryManager.selectedBook = nil
            libraryManager.selectedChapter = nil
            libraryManager.selectedVerses = []
            for module in (try? modelContext.fetch(FetchDescriptor<BibleModule>())) ?? [] {
                index.moduleDeleted(module.id)
                modelContext.delete(module)
            }
            VerseIndexCache.deleteAll()
            try? modelContext.save()
            NotificationCenter.default.post(name: .libraryDidChange, object: nil)
            lastActionNote = String(localized: "Toate Bibliile au fost șterse.", comment: "Advanced note")

        case .deleteHistory:
            history.clearAll()
            lastActionNote = String(localized: "Istoricul a fost șters.", comment: "Advanced note")
        }
    }
}
