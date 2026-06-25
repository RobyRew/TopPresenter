//
//  HistoryView.swift
//  TopPresenter
//
//  The presentation-history view (sidebar ▸ History, in the main window): what
//  songs and Bible passages were shown, how often, and when. Reads the separate
//  HistoryStore; exports CSV / JSON.
//

import SwiftUI
import AppKit

private let historyDateFormat: DateFormatter = {
    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f
}()
private func fmt(_ d: Date) -> String { historyDateFormat.string(from: d) }

struct HistoryView: View {
    @Environment(HistoryStore.self) private var store

    @State private var tab = "songs"
    @State private var songs: [SongHistorySummary] = []
    @State private var bible: [BibleHistorySummary] = []
    @State private var selectedSong: String?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if songs.isEmpty && bible.isEmpty {
                emptyState
            } else if tab == "songs" {
                songsPane
            } else {
                biblePane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: reload)
    }

    private func reload() {
        songs = store.songSummaries()
        bible = store.bibleSummaries()
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Presentation History", comment: "History window title")).font(.headline)
                Text(String(localized: "\(store.totalEvents()) shows recorded", comment: "History subtitle"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker("", selection: $tab) {
                Text(String(localized: "Songs", comment: "History tab")).tag("songs")
                Text(String(localized: "Bible", comment: "History tab")).tag("bible")
            }
            .pickerStyle(.segmented).frame(width: 200).labelsHidden()

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Filter", comment: "History filter"), text: $query)
                    .textFieldStyle(.plain).frame(width: 150)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))

            Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                .help(String(localized: "Refresh", comment: "History"))

            Menu {
                Button(String(localized: "Export CSV…", comment: "History export")) { exportCSV() }
                Button(String(localized: "Export JSON…", comment: "History export")) { exportJSON() }
            } label: { Label(String(localized: "Export", comment: "History"), systemImage: "square.and.arrow.up") }
                .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(12)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark").font(.system(size: 52)).foregroundStyle(.secondary)
            Text(String(localized: "No presentation history yet", comment: "History empty")).font(.title3)
            Text(String(localized: "Songs and Bible verses you present on screen will be tracked here.", comment: "History empty detail"))
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    // MARK: Songs

    private var filteredSongs: [SongHistorySummary] {
        query.isEmpty ? songs : songs.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var songsPane: some View {
        HSplitView {
            List(filteredSongs, selection: $selectedSong) { s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title).font(.callout.weight(.medium)).lineLimit(1)
                    HStack(spacing: 8) {
                        Label("\(s.timesPresented)×", systemImage: "rectangle.on.rectangle").labelStyle(.titleAndIcon)
                        Text("·").foregroundStyle(.secondary)
                        Text(fmt(s.lastPresented))
                    }.font(.caption2).foregroundStyle(.secondary)
                }.tag(s.songKey)
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)

            songDetail.frame(minWidth: 360)
        }
    }

    @ViewBuilder private var songDetail: some View {
        if let key = selectedSong, let s = songs.first(where: { $0.songKey == key }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(s.title).font(.title2.bold())
                    HStack(spacing: 24) {
                        stat("\(s.timesPresented)", String(localized: "times presented", comment: "History stat"))
                        stat("\(s.verseShows)", String(localized: "verse shows", comment: "History stat"))
                    }
                    Text(String(localized: "First: \(fmt(s.firstPresented))   ·   Last: \(fmt(s.lastPresented))", comment: "History dates"))
                        .font(.caption).foregroundStyle(.secondary)

                    sectionTitle(String(localized: "Sessions", comment: "History"))
                    ForEach(Array(store.sessions(forSongKey: key).enumerated()), id: \.offset) { _, sess in
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(.secondary)
                            Text(fmt(sess.date))
                            Spacer()
                            Text(String(localized: "\(sess.verses) verses", comment: "History")).foregroundStyle(.secondary)
                        }.font(.callout).padding(.vertical, 2)
                    }

                    sectionTitle(String(localized: "Per-verse", comment: "History"))
                    ForEach(store.verseTallies(forSongKey: key)) { t in
                        HStack {
                            Text(t.label)
                            Spacer()
                            Text("\(t.count)×").foregroundStyle(Color.accentColor)
                        }.font(.callout).padding(.vertical, 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            }
        } else {
            Text(String(localized: "Select a song to see its history", comment: "History placeholder"))
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Bible

    private var filteredBible: [BibleHistorySummary] {
        query.isEmpty ? bible : bible.filter {
            $0.reference.localizedCaseInsensitiveContains(query) || $0.translation.localizedCaseInsensitiveContains(query)
        }
    }

    private var biblePane: some View {
        Table(filteredBible) {
            TableColumn(String(localized: "Reference", comment: "History column")) { Text($0.reference) }
            TableColumn(String(localized: "Translation", comment: "History column")) { Text($0.translation) }.width(110)
            TableColumn(String(localized: "Times", comment: "History column")) { Text("\($0.timesPresented)×") }.width(70)
            TableColumn(String(localized: "Shows", comment: "History column")) { Text("\($0.shows)") }.width(70)
            TableColumn(String(localized: "Last presented", comment: "History column")) { Text(fmt($0.lastPresented)) }
        }
    }

    // MARK: Bits

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Color.accentColor)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.headline).padding(.top, 4)
    }

    // MARK: Export

    private func save(_ text: String, suggested: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggested
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    private func exportCSV() { save(HistoryExportService.eventsCSV(store.exportEvents()), suggested: "TopPresenter-History.csv") }
    private func exportJSON() { save((try? HistoryExportService.json(store)) ?? "{}", suggested: "TopPresenter-History.json") }
}
