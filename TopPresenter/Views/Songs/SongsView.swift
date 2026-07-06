//
//  SongsView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main Songs view: scalable library browser (left) + version-aware detail with a rendered
/// slide filmstrip (right).
struct SongsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AppState.self) private var appState

    @Query(sort: \SongCollection.name) private var collections: [SongCollection]

    @State private var showImportSheet = false
    @State private var showDeleteConfirmation = false
    @State private var collectionToDelete: SongCollection?

    var body: some View {
        VStack(spacing: 0) {
            if collections.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    SongListPanel()
                        .frame(minWidth: 260, maxWidth: 380)

                    SongDetailPanel()
                        .frame(minWidth: 420)
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            SongImportSheet()
        }
        .sheet(item: Binding(
            get: { libraryManager.songToEdit },
            set: { libraryManager.songToEdit = $0 }
        )) { song in
            SongEditorSheet(song: song)
        }
        .onChange(of: appState.triggerSongImport) { _, newValue in
            if newValue {
                showImportSheet = true
                appState.triggerSongImport = false
            }
        }
        .alert(
            String(localized: "Delete Collection", comment: "Alert title"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "Cancel", comment: "Alert button"), role: .cancel) { }
            Button(String(localized: "Delete", comment: "Alert button"), role: .destructive) {
                if let collection = collectionToDelete {
                    deleteCollection(collection)
                }
            }
        } message: {
            Text(String(localized: "Are you sure you want to delete \"\(collectionToDelete?.name ?? "")\"? This cannot be undone.", comment: "Alert message"))
        }
        .onKeyWindowNotification(.deleteSongCollection) { _ in
            collectionToDelete = libraryManager.selectedSongCollection
            showDeleteConfirmation = true
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(String(localized: "No Song Collections", comment: "Empty state title"))
                .font(.title2)

            Text(String(localized: "Import songs to get started.\nSupported: TopPresenter JSON, OpenSong, OpenLyrics, ChordPro, PowerPoint, plain text.", comment: "Empty state message"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showImportSheet = true
            } label: {
                Label(
                    String(localized: "Import Songs", comment: "Button"),
                    systemImage: "plus.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func deleteCollection(_ collection: SongCollection) {
        if libraryManager.selectedSongCollection?.id == collection.id {
            libraryManager.selectedSongCollection = nil
            libraryManager.selectedSong = nil
            libraryManager.selectedSongVerse = nil
        }
        modelContext.delete(collection)
        try? modelContext.save()
    }
}

// MARK: - Sort

enum SongSortKey: String, CaseIterable, Identifiable {
    case title, author, songbook, language, recent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: return String(localized: "A-Z", comment: "Sort")
        case .author: return String(localized: "Artist", comment: "Sort")
        case .songbook: return String(localized: "Carte", comment: "Sort — by songbook")
        case .language: return String(localized: "Limbă", comment: "Sort — by language")
        case .recent: return String(localized: "Recente", comment: "Sort")
        }
    }
    var systemImage: String {
        switch self {
        case .title: return "textformat.abc"
        case .author: return "music.mic"
        case .songbook: return "book.closed"
        case .language: return "globe"
        case .recent: return "clock"
        }
    }
}

// MARK: - Song Library Browser (search, list/grid, filters — scales to thousands)

struct SongListPanel: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(PinStore.self) private var pinStore
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SongCollection.name) private var collections: [SongCollection]
    @AppStorage("song_maxLinesPerSlide") private var maxLines: Int = 6
    @AppStorage("song_repeatBracket") private var repeatBracket = "none"
    @AppStorage("song_repeatCount") private var repeatCount = "times"

    /// Lives on LibraryManager so detail-panel chips can set it to search.
    private var query: String { libraryManager.songLibraryQuery }
    private var queryBinding: Binding<String> {
        Binding(get: { libraryManager.songLibraryQuery }, set: { libraryManager.songLibraryQuery = $0 })
    }
    @State private var isGrid = false
    @State private var sortKey: SongSortKey = .title
    @State private var languageFilter = ""        // "" = all
    @State private var collectionFilter: UUID?    // nil = all
    @State private var onlyWithMedia = false
    @State private var onlyVerified = false
    /// Grid cell under the pointer — reveals its pin toggle on hover.
    @State private var hoveredSongID: UUID?

    private var sourceSongs: [Song] {
        if let id = collectionFilter, let col = collections.first(where: { $0.id == id }) {
            return col.songs
        }
        return collections.flatMap { $0.songs }
    }

    private var availableLanguages: [String] {
        Array(Set(sourceSongs.map(\.language).filter { !$0.isEmpty })).sorted()
    }

    private var filtered: [Song] {
        let tokens = query.lowercased().split(separator: " ").map(String.init)
        var songs = sourceSongs.filter { song in
            if !languageFilter.isEmpty && song.language != languageFilter { return false }
            if onlyWithMedia && song.media.isEmpty { return false }
            if onlyVerified && !song.verified { return false }
            guard !tokens.isEmpty else { return true }
            // "verificat" / "✓" match verified songs, alongside the text search.
            let hay = song.searchText.isEmpty ? song.title.lowercased() : song.searchText
            return tokens.allSatisfy { tok in
                if (tok == "verificat" || tok == "✓"), song.verified { return true }
                return hay.contains(tok)
            }
        }
        switch sortKey {
        case .title:
            songs.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .author:
            songs.sort { $0.author.localizedStandardCompare($1.author) == .orderedAscending }
        case .songbook:
            songs.sort { ($0.songbook?.name ?? "\u{10FFFF}").localizedStandardCompare($1.songbook?.name ?? "\u{10FFFF}") == .orderedAscending }
        case .language:
            songs.sort {
                let c = $0.language.localizedStandardCompare($1.language)
                return c == .orderedSame
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : c == .orderedAscending
            }
        case .recent:
            songs.sort { $0.modifiedDate > $1.modifiedDate }
        }
        return songs
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if filtered.isEmpty {
                ContentUnavailableView(
                    String(localized: "Niciun cântec", comment: "Empty"),
                    systemImage: "magnifyingglass",
                    description: Text(String(localized: "Ajustează căutarea sau filtrele.", comment: "Empty"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isGrid {
                gridView
            } else {
                listView
            }
        }
    }

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(String(localized: "Caută cântece…", comment: "Search"), text: queryBinding)
                    .textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { libraryManager.songLibraryQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 6) {
                Picker("", selection: $collectionFilter) {
                    Text(String(localized: "Toate", comment: "All collections")).tag(UUID?.none)
                    ForEach(collections) { col in
                        Text(col.name).tag(UUID?.some(col.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 140)

                Spacer()

                Menu {
                    if !availableLanguages.isEmpty {
                        Picker(String(localized: "Limbă", comment: "Language"), selection: $languageFilter) {
                            Text(String(localized: "Toate", comment: "All")).tag("")
                            ForEach(availableLanguages, id: \.self) { Text($0.uppercased()).tag($0) }
                        }
                    }
                    Toggle(String(localized: "Doar cu media", comment: "Filter"), isOn: $onlyWithMedia)
                    Toggle(String(localized: "Doar verificate", comment: "Filter — verified only"), isOn: $onlyVerified)
                } label: {
                    Image(systemName: onlyVerified || onlyWithMedia || !languageFilter.isEmpty
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .menuStyle(.borderlessButton).fixedSize()

                Button { isGrid.toggle() } label: {
                    Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                }
                .buttonStyle(.borderless)
                .help(isGrid ? String(localized: "Listă", comment: "View") : String(localized: "Grilă", comment: "View"))
            }

            // Sort header chips — quick A-Z / Artist / Carte / Limbă / Recente.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(SongSortKey.allCases) { key in
                        let on = sortKey == key
                        Button { sortKey = key } label: {
                            Label(key.label, systemImage: key.systemImage)
                                .labelStyle(.titleAndIcon).font(.caption2.weight(on ? .semibold : .regular))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(on ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary), in: Capsule())
                                .foregroundStyle(on ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(String(localized: "\(filtered.count) cântece", comment: "Count"))
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
    }

    /// Sentinel group key for the session pins — \u{0} can never collide with an
    /// A-Z initial, book name, or language code.
    static let pinnedGroupKey = "\u{0}pinned"

    /// `filtered` grouped by the active sort key (A-Z initial / book / language /
    /// artist initial). Empty key = a single ungrouped section (Recente). Order is
    /// preserved from `filtered`, which is already sorted. Pinned songs float into
    /// a single "Fixate" group prepended on top (they appear ONLY there).
    private var grouped: [(key: String, songs: [Song])] {
        let (pinned, songs) = PinStore.partition(filtered, pinnedIDs: pinStore.pinnedSongIDs)
        var groups: [(key: String, songs: [Song])] = []
        if !pinned.isEmpty { groups.append((Self.pinnedGroupKey, pinned)) }
        if sortKey == .recent {
            groups.append(("", songs))
            return groups
        }
        func keyFor(_ s: Song) -> String {
            switch sortKey {
            case .title: return initialLetter(s.title)
            case .author: return s.author.isEmpty ? "—" : initialLetter(s.author)
            case .songbook: return s.songbook?.name ?? String(localized: "Fără carte", comment: "No songbook")
            case .language: return s.language.isEmpty ? "—" : s.language.uppercased()
            case .recent: return ""
            }
        }
        var order: [String] = []
        var map: [String: [Song]] = [:]
        for s in songs {
            let k = keyFor(s)
            if map[k] == nil { order.append(k); map[k] = [] }
            map[k]?.append(s)
        }
        return groups + order.map { ($0, map[$0] ?? []) }
    }

    /// First letter (diacritic-folded) for an A-Z heading; "#" for non-letters.
    private func initialLetter(_ s: String) -> String {
        guard let c = s.trimmingCharacters(in: .whitespaces).first else { return "#" }
        let u = String(c).folding(options: .diacriticInsensitive, locale: nil).uppercased()
        return u.range(of: "[A-Z]", options: .regularExpression) != nil ? u : "#"
    }

    /// A very subtle group heading.
    private func subtleHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Group heading, with the pinned ("Fixate") group getting a pin icon and a
    /// clear-all-pins button; every other key renders the plain subtle header.
    @ViewBuilder
    private func groupHeader(_ key: String) -> some View {
        if key == Self.pinnedGroupKey {
            HStack(spacing: 4) {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "Fixate", comment: "Pinned songs group heading"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    pinStore.clearPins()
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.tertiary)
                .help(String(localized: "Șterge toate fixările", comment: "Tooltip — clear session pins"))
            }
        } else {
            subtleHeader(key)
        }
    }

    private var songSelection: Binding<UUID?> {
        Binding(get: { libraryManager.selectedSong?.id },
                set: { id in if let id, let s = filtered.first(where: { $0.id == id }) { libraryManager.selectSong(s) } })
    }

    private var listView: some View {
        List(selection: songSelection) {
            ForEach(grouped, id: \.key) { group in
                if group.key.isEmpty {
                    ForEach(group.songs) { song in songRow(song).tag(song.id) }
                } else {
                    Section {
                        ForEach(group.songs) { song in songRow(song).tag(song.id) }
                    } header: { groupHeader(group.key) }
                }
            }
        }
        .listStyle(.inset)
    }

    private func songRow(_ song: Song) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(song.title).font(.body).lineLimit(1)
            HStack(spacing: 6) {
                if !song.author.isEmpty {
                    Text(song.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                songBadges(song)
            }
        }
        .padding(.vertical, 2)
        .contextMenu { songMenu(song) }
    }

    private var gridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 164), spacing: 10)], spacing: 10, pinnedViews: [.sectionHeaders]) {
                ForEach(grouped, id: \.key) { group in
                    Section {
                        ForEach(group.songs) { song in gridCell(song) }
                    } header: {
                        if !group.key.isEmpty {
                            groupHeader(group.key)
                                .padding(.horizontal, 2).padding(.vertical, 3)
                                .background(.bar)
                        }
                    }
                }
            }
            .padding(8)
        }
    }

    private func gridCell(_ song: Song) -> some View {
        Button { libraryManager.selectSong(song) } label: {
            VStack(spacing: 0) {
                SongThemeSlideView(text: firstSlideText(song), fontSize: 8)
                    .frame(height: 62)
                    .clipped()
                VStack(alignment: .leading, spacing: 3) {
                    Text(song.title).font(.callout.weight(.medium)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !song.author.isEmpty {
                        Text(song.author).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    HStack { songBadges(song); Spacer() }
                }
                .padding(8)
            }
            .frame(height: 132, alignment: .top)
            .background(
                libraryManager.selectedSong?.id == song.id
                    ? Color.accentColor.opacity(0.18)
                    : Color.secondary.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(libraryManager.selectedSong?.id == song.id ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            // Pin toggle: always visible when pinned, revealed on hover otherwise.
            if pinStore.isPinned(song.id) || hoveredSongID == song.id {
                Button { pinStore.togglePin(song.id) } label: {
                    Image(systemName: pinStore.isPinned(song.id) ? "pin.fill" : "pin")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(pinStore.isPinned(song.id) ? Color.accentColor : .secondary)
                        .padding(4)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(4)
                .help(pinStore.isPinned(song.id)
                        ? String(localized: "Anulează fixarea", comment: "Tooltip — unpin song")
                        : String(localized: "Fixează sus", comment: "Tooltip — pin song to top"))
            }
        }
        .onHover { inside in
            if inside { hoveredSongID = song.id }
            else if hoveredSongID == song.id { hoveredSongID = nil }
        }
        .contextMenu { songMenu(song) }
    }

    private func firstSlideText(_ song: Song) -> String {
        if let section = song.activeVersion?.sortedSections.first, !section.plainText.isEmpty {
            return section.plainText
        }
        return song.sortedVerses.first?.text ?? song.title
    }

    @ViewBuilder
    private func songMenu(_ song: Song) -> some View {
        Button { pinStore.togglePin(song.id) } label: {
            Label(pinStore.isPinned(song.id)
                    ? String(localized: "Anulează fixarea", comment: "Menu — unpin song")
                    : String(localized: "Fixează sus", comment: "Menu — pin song to top for this session"),
                  systemImage: pinStore.isPinned(song.id) ? "pin.slash" : "pin")
        }
        Divider()
        Button { projectFirstSlide(song) } label: {
            Label(String(localized: "Proiectează", comment: "Menu"), systemImage: "play.fill")
        }
        AddToSessionMenu(draft: { .song(song, version: nil) })
        Button { libraryManager.selectSong(song) } label: {
            Label(String(localized: "Deschide", comment: "Menu"), systemImage: "eye")
        }
        Button {
            libraryManager.selectSong(song)
            libraryManager.songEditVersionID = nil
            libraryManager.songEditSectionKey = nil
            libraryManager.songToEdit = song
        } label: {
            Label(String(localized: "Editează…", comment: "Menu"), systemImage: "pencil")
        }
        Button { song.verified.toggle(); song.modifiedDate = .now } label: {
            Label(song.verified ? String(localized: "Scoate verificarea", comment: "Menu")
                                : String(localized: "Marchează verificat", comment: "Menu"),
                  systemImage: song.verified ? "checkmark.seal.fill" : "checkmark.seal")
        }
        Divider()
        Button { exportSong(song) } label: {
            Label(String(localized: "Exportă JSON…", comment: "Menu"), systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) { deleteSong(song) } label: {
            Label(String(localized: "Șterge cântecul", comment: "Menu"), systemImage: "trash")
        }
    }

    private func projectFirstSlide(_ song: Song) {
        libraryManager.selectSong(song)
        let version = song.activeVersion
        let slides = buildSongSlides(song: song, version: version, maxLines: maxLines, bilingual: false, language: nil, bracket: repeatBracket, countStyle: repeatCount)
        guard let first = slides.first else { return }
        libraryManager.selectSongSlide(text: first.text, label: first.label, index: 0, count: first.total)
        presentationManager.showSongVerse(
            text: first.text, title: song.title, verseLabel: first.label,
            slideIndex: 0, slideCount: first.total, song: song, version: version, lines: first.lines
        )
    }

    private func exportSong(_ song: Song) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(song.title).json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ExportService.exportSongToTopPresenterJSON(song).write(to: url, atomically: true, encoding: .utf8)
    }

    private func deleteSong(_ song: Song) {
        if libraryManager.selectedSong?.id == song.id {
            libraryManager.selectedSong = nil
            libraryManager.selectedSongVersion = nil
            libraryManager.selectedSongVerse = nil
        }
        modelContext.delete(song)
        try? modelContext.save()
    }

    @ViewBuilder
    private func songBadges(_ song: Song) -> some View {
        HStack(spacing: 4) {
            if pinStore.isPinned(song.id) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10)).foregroundStyle(Color.accentColor)
                    .help(String(localized: "Fixat pentru această sesiune", comment: "Pinned badge"))
            }
            if song.verified {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10)).foregroundStyle(.green)
                    .help(String(localized: "Verificat", comment: "Verified badge"))
            }
            if song.versions.count > 1 { badge("\(song.versions.count)×", color: .purple) }
            if !song.language.isEmpty { badge(song.language.uppercased(), color: .blue) }
            if !song.songNumber.isEmpty { badge("#\(song.songNumber)", color: .gray) }
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Song Detail (version picker + rendered slide filmstrip)

struct SongDetailPanel: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(HistoryStore.self) private var historyStore
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @AppStorage("song_maxLinesPerSlide") private var maxLines: Int = 6
    @AppStorage("song_bilingual") private var bilingual: Bool = false

    private static let histFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
    }()

    var body: some View {
        if let song = libraryManager.selectedSong {
            let version = libraryManager.selectedSongVersion ?? song.activeVersion
            VStack(spacing: 0) {
                header(song: song, version: version)
                Divider()
                SongSlideFilmstrip(song: song, version: version, maxLines: maxLines, bilingual: bilingual)
            }
        } else {
            placeholder(icon: "music.note", text: String(localized: "Selectează un cântec", comment: "Placeholder"))
        }
    }

    @ViewBuilder
    private func header(song: Song, version: SongVersion?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                // Left column: Title · Book (middle) · Artist (max half width).
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(song.title).font(.title3.bold()).lineLimit(2)
                        if song.verified {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                                .help(String(localized: "Verificat", comment: "Verified"))
                        }
                    }
                    if let sb = song.songbook {
                        searchText(sb.name + (song.songbookNumber.isEmpty ? "" : " #\(song.songbookNumber)"),
                                   query: sb.name, font: .caption)
                    }
                    if !song.author.isEmpty {
                        searchText(song.author, query: song.author, font: .subheadline)
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: 280, alignment: .leading)   // artist ≈ half the panel
                    }
                }
                Spacer(minLength: 8)
                // Right column: presentation history on top, key/chords, then Edit (lower).
                VStack(alignment: .trailing, spacing: 6) {
                    if let h = songHistory(song) {
                        Button { appState.selectedSidebarItem = .history } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.circlepath").font(.caption2)
                                Text(String(localized: "Prezentat \(h.timesPresented)×", comment: "History chip"))
                                Text("·").foregroundStyle(.secondary)
                                Text(Self.histFmt.string(from: h.lastPresented))
                            }
                            .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Deschide istoricul prezentărilor", comment: "History tooltip"))
                    }
                    if songHasChords(song) {
                        SongChordControl(song: song, version: version)
                    } else if let key = version?.key, !key.isEmpty {
                        infoChip(String(localized: "Ton: \(key)", comment: "Key"))
                    }
                    Button {
                        libraryManager.selectSong(song)
                        libraryManager.songEditVersionID = version?.id
                        libraryManager.songEditSectionKey = nil
                        libraryManager.songToEdit = song
                    } label: {
                        Label(String(localized: "Editează", comment: "Edit button"), systemImage: "pencil")
                            .frame(minWidth: 100)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .help(String(localized: "Editează cântecul", comment: "Edit tooltip"))
                }
            }
            if song.sortedVersions.count > 1 {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(
                        get: { (libraryManager.selectedSongVersion ?? song.activeVersion)?.id },
                        set: { id in
                            if let id, let v = song.versions.first(where: { $0.id == id }) {
                                libraryManager.selectSongVersion(v)
                            }
                        }
                    )) {
                        ForEach(song.sortedVersions) { v in
                            Text(verbatim: (song.originalVersionID == v.id.uuidString ? "★ " : "")
                                 + (v.name.isEmpty ? String(localized: "Versiune", comment: "Version") : v.name))
                                .tag(Optional(v.id))
                        }
                    }
                    .labelsHidden().fixedSize()

                    // Mark the shown version as ORIGINAL — the default that gets
                    // presented, searched first and exported as "original": true.
                    let shown = libraryManager.selectedSongVersion ?? song.activeVersion
                    let isOriginal = shown.map { song.originalVersionID == $0.id.uuidString } ?? false
                    Button {
                        guard let shown else { return }
                        song.originalVersionID = shown.id.uuidString
                        ImportService.applyOriginalVersionChange(for: song, modelContext: modelContext)
                    } label: {
                        Image(systemName: isOriginal ? "star.fill" : "star")
                            .foregroundStyle(isOriginal ? .yellow : .secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isOriginal)
                    .help(isOriginal
                          ? String(localized: "Versiunea originală (implicită)", comment: "Tooltip")
                          : String(localized: "Marchează ca original — devine versiunea implicită", comment: "Tooltip"))
                }
            }

            // Quick song facts — most chips search for more songs with that value.
            infoRow(song: song, version: version)
        }
        .padding(.horizontal).padding(.vertical, 8)
    }

    /// A compact row of song facts shown above the slides. Tag-like chips are
    /// clickable and refine the library search; source file + web link are special.
    @ViewBuilder
    private func infoRow(song: Song, version: SongVersion?) -> some View {
        let tempo = (version?.tempo.isEmpty == false ? version?.tempo : nil) ?? (song.tempo.isEmpty ? nil : song.tempo)
        let lang = (version?.language.isEmpty == false ? version?.language : nil) ?? (song.language.isEmpty ? nil : song.language)
        let sectionCount = version?.sections.count ?? 0
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !song.sourceFile.isEmpty {
                    Label(song.sourceFile, systemImage: "doc.text")
                        .font(.caption).labelStyle(.titleAndIcon)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: Capsule()).lineLimit(1)
                        .help(String(localized: "Fișierul importat", comment: "Import file tooltip"))
                } else if let col = song.collection?.name, !col.isEmpty {
                    searchChip(col, query: col, systemImage: "tray.and.arrow.down")
                }
                if let url = song.webURL {
                    Link(destination: url) {
                        Label(String(localized: "Pe web", comment: "Web link chip"), systemImage: "link")
                            .font(.caption).labelStyle(.titleAndIcon)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                    .help(url.absoluteString)
                }
                if !song.ccliNumber.isEmpty { infoChip("CCLI \(song.ccliNumber)") }
                if let tempo { infoChip("\(tempo) BPM") }
                if let lang { searchChip(lang.uppercased(), query: lang) }
                if !song.style.isEmpty { searchChip(song.style, query: song.style) }
                if sectionCount > 0 { infoChip(String(localized: "\(sectionCount) secțiuni", comment: "Section count")) }
                ForEach(song.themes.prefix(5), id: \.self) { searchChip($0, query: $0) }
                if !song.editLog.isEmpty {
                    infoChip(String(localized: "Modificat \(Self.histFmt.string(from: song.modifiedDate))", comment: "Modified date"))
                }
            }
        }
    }

    /// A chip that, when clicked, sets the library search to `query` (find similar).
    private func searchChip(_ text: String, query: String, systemImage: String? = nil) -> some View {
        Button { libraryManager.songLibraryQuery = query } label: {
            Group {
                if let systemImage {
                    Label(text, systemImage: systemImage).labelStyle(.titleAndIcon)
                } else {
                    Text(text)
                }
            }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: Capsule()).lineLimit(1)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Caută cântece cu „\(query)”", comment: "Search-by-chip tooltip"))
    }

    /// Plain text that doubles as a search chip (used for author/book in the title block).
    private func searchText(_ text: String, query: String, font: Font) -> some View {
        Button { libraryManager.songLibraryQuery = query } label: {
            Text(text).font(font).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Caută „\(query)”", comment: "Search tooltip"))
    }

    /// This song's presentation-history summary (nil if never presented).
    private func songHistory(_ song: Song) -> SongHistorySummary? {
        let key = HistoryStore.songKey(ccli: song.ccliNumber, title: song.title,
                                       source: song.collection?.sourceFormat ?? "")
        return historyStore.summary(forSongKey: key)
    }

    private func infoChip(_ text: String) -> some View {
        Text(text).font(.caption)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
            .lineLimit(1)
    }

    @ViewBuilder
    private func placeholder(icon: String = "music.note", text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 44)).foregroundStyle(.secondary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Song Slides (auto-split + filmstrip)

struct SongSlide: Identifiable, Hashable {
    let id = UUID()
    let sectionKey: String
    let label: String
    let type: String
    let text: String
    /// Rich lyric lines (text + chords) for this slide, chunked in lockstep with
    /// `text`. Drives the chord casetă; empty for fallback songs without chords.
    var lines: [SongLine] = []
    let index: Int
    let total: Int
}

/// Split pre-rendered sections into slides, auto-splitting any section that overflows
/// `maxLines`. The plain `lines` (display strings) and `richLines` (text + chords) are
/// chunked together so slide N's text and chords always correspond.
private func splitToSlides(_ sections: [(key: String, label: String, type: String, lines: [String], richLines: [SongLine])], maxLines: Int) -> [SongSlide] {
    var raw: [(key: String, label: String, type: String, text: String, rich: [SongLine])] = []
    for s in sections {
        // Keep the two arrays the same length so they chunk identically.
        let rich = s.richLines.count == s.lines.count ? s.richLines : []
        if maxLines > 0 && s.lines.count > maxLines {
            var start = 0
            while start < s.lines.count {
                let end = min(start + maxLines, s.lines.count)
                let chunk = Array(s.lines[start..<end])
                let richChunk = rich.isEmpty ? [] : Array(rich[start..<end])
                raw.append((s.key, s.label, s.type, chunk.joined(separator: "\n"), richChunk))
                start += maxLines
            }
        } else {
            raw.append((s.key, s.label, s.type, s.lines.joined(separator: "\n"), rich))
        }
    }
    let total = max(raw.count, 1)
    return raw.enumerated().map { idx, r in
        SongSlide(sectionKey: r.key, label: r.label, type: r.type, text: r.text, lines: r.rich, index: idx, total: total)
    }
}

/// Expand a version into projectable slides: arrangement order → sections → auto-split by `maxLines`.
/// When `bilingual`, each line is paired with its `language` translation (if present).
func buildSongSlides(version: SongVersion, maxLines: Int, bilingual: Bool, language: String?,
                     bracket: String = "none", countStyle: String = "none") -> [SongSlide] {
    // The version's own override wins over the global defaults.
    let (b, c) = resolveRepeat(versionStyle: version.repeatStyle, globalBracket: bracket, globalCount: countStyle)
    let sections = version.arrangedSections.map { section -> (key: String, label: String, type: String, lines: [String], richLines: [SongLine]) in
        let source = section.lines
        var rendered = source.map { line -> String in
            if bilingual, let language, let t = line.translations[language], !t.isEmpty {
                return line.text + "\n" + t
            }
            return line.text
        }
        rendered = applyRepeatMarker(rendered, count: section.repeatCount, bracket: b, countStyle: c)
        // Rich lines carry the SAME repeat markers (positions shifted so chords stay
        // aligned). Counts match `rendered`, so the two chunk identically in splitToSlides.
        let rich = applyRepeatMarkerRich(source, count: section.repeatCount, bracket: b, countStyle: c)
        return (section.sectionKey, section.label, section.type, rendered, rich)
    }
    return splitToSlides(sections, maxLines: maxLines)
}

/// Build slides for a song. Uses the rich version when present; otherwise falls back to the
/// flattened `SongVerse` cache (songs imported before the version model existed).
func buildSongSlides(song: Song, version: SongVersion?, maxLines: Int, bilingual: Bool, language: String?,
                     bracket: String = "none", countStyle: String = "none") -> [SongSlide] {
    if let version, !version.sections.isEmpty {
        return buildSongSlides(version: version, maxLines: maxLines, bilingual: bilingual, language: language, bracket: bracket, countStyle: countStyle)
    }
    let sections = song.sortedVerses.map { v -> (key: String, label: String, type: String, lines: [String], richLines: [SongLine]) in
        (v.label, v.label, v.verseType, v.text.components(separatedBy: "\n"), [])
    }
    return splitToSlides(sections, maxLines: maxLines)
}

/// Best-effort rich (chorded) lines for a slide that only carries plain text:
/// each text line is matched against the version's section lines to recover its
/// chords. Used by the live/schedule paths that work off the flattened verse cache.
/// Returns `[]` when the version has no chords at all (the chord casetá stays empty).
func richLines(forSlideText text: String, in version: SongVersion?) -> [SongLine] {
    guard let version else { return [] }
    var byText: [String: [SongChord]] = [:]
    for sec in version.sections {
        for line in sec.lines where !line.chords.isEmpty {
            byText[line.text.trimmingCharacters(in: .whitespaces)] = line.chords
        }
    }
    guard !byText.isEmpty else { return [] }
    return text.components(separatedBy: "\n").map { raw in
        SongLine(text: raw, chords: byText[raw.trimmingCharacters(in: .whitespaces)] ?? [])
    }
}

/// Decorate a flattened verse (text + recovered chords) with repeat markers — used
/// by the live verse-navigation path, which works off the marker-less SongVerse cache
/// (so markers reach the output/preview there, not only via the filmstrip).
func decoratedVerse(_ verse: SongVerse, version: SongVersion?, bracket: String, countStyle: String) -> (text: String, lines: [SongLine]) {
    let matched = richLines(forSlideText: verse.text, in: version)
    let base = matched.isEmpty ? verse.text.components(separatedBy: "\n").map { SongLine(text: $0) } : matched
    let count = version?.sections.first { $0.label == verse.label || $0.sectionKey == verse.label }?.repeatCount ?? 1
    let (b, c) = resolveRepeat(versionStyle: version?.repeatStyle ?? "", globalBracket: bracket, globalCount: countStyle)
    let rich = applyRepeatMarkerRich(base, count: count, bracket: b, countStyle: c)
    return (rich.map { $0.text }.joined(separator: "\n"), rich)
}

struct SongSlideFilmstrip: View {
    let song: Song
    let version: SongVersion?
    let maxLines: Int
    let bilingual: Bool

    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(\.modelContext) private var modelContext
    @AppStorage("song_repeatBracket") private var repeatBracket = "none"
    @AppStorage("song_repeatCount") private var repeatCount = "times"
    @State private var slideToDelete: SongSlide?

    private var bilingualLanguage: String? {
        guard bilingual else { return nil }
        for sec in (version?.sections ?? []) {
            for line in sec.lines {
                if let lang = line.translations.keys.sorted().first { return lang }
            }
        }
        return nil
    }

    private var slides: [SongSlide] {
        buildSongSlides(song: song, version: version, maxLines: maxLines, bilingual: bilingual, language: bilingualLanguage, bracket: repeatBracket, countStyle: repeatCount)
    }

    var body: some View {
        if slides.isEmpty {
            ContentUnavailableView(
                String(localized: "Niciun slide", comment: "Empty"),
                systemImage: "rectangle.on.rectangle.slash",
                description: Text(String(localized: "Acest cântec nu are versuri.", comment: "Empty"))
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(slides) { slide in
                        SongSlideThumbnail(
                            slide: slide,
                            isSelected: libraryManager.songSlideLabel == slide.label
                                && libraryManager.songSlideText == slide.text,
                            onShow: { project(slide) },
                            onPreview: { select(slide) },
                            onEdit: {
                                libraryManager.songEditVersionID = version?.id
                                libraryManager.songEditSectionKey = slide.sectionKey
                                libraryManager.songToEdit = song
                            },
                            onDelete: { slideToDelete = slide }
                        )
                        // Double-tap projects; single-tap selects (updates the sidebar's rendered preview).
                        .onTapGesture(count: 2) { project(slide) }
                        .onTapGesture { select(slide) }
                        .contextMenu {
                            Button {
                                project(slide)
                            } label: {
                                Label(String(localized: "Proiectează", comment: "Menu"), systemImage: "play.fill")
                            }
                            Button {
                                select(slide)
                            } label: {
                                Label(String(localized: "Previzualizează", comment: "Menu"), systemImage: "eye")
                            }
                            Divider()
                            Button {
                                libraryManager.songEditVersionID = version?.id
                                libraryManager.songEditSectionKey = slide.sectionKey
                                libraryManager.songToEdit = song
                            } label: {
                                Label(String(localized: "Editează cântecul…", comment: "Menu"), systemImage: "pencil")
                            }
                            Divider()
                            Button(role: .destructive) {
                                slideToDelete = slide
                            } label: {
                                Label(String(localized: "Șterge", comment: "Menu"), systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(12)
            }
            .confirmationDialog(
                String(localized: "Ștergi această secțiune?", comment: "Delete slide confirm"),
                isPresented: Binding(get: { slideToDelete != nil }, set: { if !$0 { slideToDelete = nil } }),
                presenting: slideToDelete
            ) { slide in
                Button(String(localized: "Șterge «\(slide.label)»", comment: "Delete confirm button"), role: .destructive) {
                    deleteSection(for: slide)
                }
                .keyboardShortcut(.defaultAction)
                Button(String(localized: "Anulează", comment: "Cancel"), role: .cancel) { slideToDelete = nil }
            } message: { slide in
                Text(String(localized: "Slide-ul face parte din secțiunea «\(slide.label)», care va fi ștearsă din cântec.", comment: "Delete slide message"))
            }
        }
    }

    /// Delete the SECTION a slide belongs to (a slide is an auto-split piece of a
    /// section, so there's nothing smaller to remove). Rebuilds the verse cache.
    private func deleteSection(for slide: SongSlide) {
        defer { slideToDelete = nil }
        guard let version, let section = version.sections.first(where: { $0.sectionKey == slide.sectionKey }) else { return }
        modelContext.delete(section)
        // Keep the flattened SongVerse cache + searchText in sync.
        for old in song.verses { modelContext.delete(old) }
        if libraryManager.songSlideText == slide.text { libraryManager.selectSongSlide(text: "", label: "", index: 0, count: 0) }
        try? modelContext.save()
    }

    private func select(_ slide: SongSlide) {
        libraryManager.selectSongSlide(text: slide.text, label: slide.label, index: slide.index, count: slide.total)
    }

    private func project(_ slide: SongSlide) {
        select(slide)
        presentationManager.showSongVerse(
            text: slide.text, title: song.title, verseLabel: slide.label,
            slideIndex: slide.index, slideCount: slide.total,
            song: song, version: version, lines: slide.lines
        )
    }
}

struct SongSlideThumbnail: View {
    let slide: SongSlide
    let isSelected: Bool
    var onShow: () -> Void = {}
    var onPreview: () -> Void = {}
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                SongThemeSlideView(text: slide.text.isEmpty ? slide.label : slide.text, fontSize: 9)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                // Quick actions: show on screen + preview + edit + delete
                HStack(spacing: 6) {
                    Button(action: onShow) { Image(systemName: "play.fill") }
                        .help(String(localized: "Arată pe ecran", comment: "Tooltip"))
                    Button(action: onPreview) {
                        Text(verbatim: "PREVIEW").font(.system(size: 8, weight: .heavy))
                    }
                    .help(String(localized: "Previzualizează", comment: "Tooltip"))
                    Button(action: onEdit) { Image(systemName: "pencil") }
                        .help(String(localized: "Editează", comment: "Tooltip"))
                    Button(action: onDelete) { Image(systemName: "trash") }
                        .help(String(localized: "Șterge slide-ul", comment: "Tooltip"))
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(5)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(5)
            }

            HStack {
                Text(slide.label).font(.caption2.weight(.medium)).lineLimit(1)
                Spacer()
                Text("\(slide.index + 1)/\(slide.total)")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4).padding(.vertical, 3)
        }
        .background(
            isSelected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Song Import Sheet
struct SongImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var collectionName: String = ""
    @State private var selectedURLs: [URL] = []
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importStatusText = ""
    @State private var dupMode = "version"   // version | keepBoth | skip
    @Query(sort: \SongCollection.name) private var existingCollections: [SongCollection]

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "Import Songs", comment: "Sheet title"))
                .font(.title2.bold())

            Text(String(localized: "Alege fișiere și/sau directoare (subdirectoarele sunt incluse) — formatul fiecărui fișier este detectat automat.", comment: "Import sheet hint"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    TextField(
                        String(localized: "Nume folder (gol = Nesortate)", comment: "Text field placeholder"),
                        text: $collectionName
                    )
                    .textFieldStyle(.roundedBorder)
                    if !existingCollections.isEmpty {
                        Menu {
                            ForEach(existingCollections) { c in
                                Button(c.name) { collectionName = c.name }
                            }
                        } label: { Image(systemName: "folder") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .help(String(localized: "Alege un folder existent", comment: "Tooltip"))
                    }
                }
                Picker(String(localized: "La nume existent", comment: "Label"), selection: $dupMode) {
                    Text(String(localized: "Versiune nouă", comment: "Option")).tag("version")
                    Text(String(localized: "Cântec nou", comment: "Option")).tag("keepBoth")
                    Text(String(localized: "Sări peste", comment: "Option")).tag("skip")
                }
                .pickerStyle(.segmented)
            }

            HStack {
                if selectedURLs.isEmpty {
                    Text(String(localized: "Nimic selectat", comment: "Placeholder"))
                        .foregroundStyle(.secondary)
                } else if selectedURLs.count == 1 {
                    Text(selectedURLs[0].lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(String(localized: "\(selectedURLs.count) elemente selectate", comment: "Selection summary"))
                }

                Spacer()

                Button(String(localized: "Alege…", comment: "Button")) {
                    chooseLocation()
                }
            }
            .padding()
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            if selectedURLs.count > 1 {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(selectedURLs, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
            }

            if isImporting {
                ProgressView(value: importProgress) {
                    Text(importStatusText).font(.caption)
                }
                .progressViewStyle(.linear)
            }

            HStack {
                Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(String(localized: "Import", comment: "Button")) { performImport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedURLs.isEmpty || isImporting)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        // Only supported song file types are selectable; folders stay pickable.
        panel.allowedContentTypes = SupportedSongFormat.allCases
            .flatMap { $0.fileExtensions }
            .compactMap { UTType(filenameExtension: $0) }
        panel.message = String(localized: "Alege cântece (fișiere sau directoare)", comment: "Open panel message")

        if panel.runModal() == .OK {
            selectedURLs = panel.urls
            if collectionName.isEmpty, let first = panel.urls.first {
                collectionName = first.deletingPathExtension().lastPathComponent
            }
        }
    }

    private func performImport() {
        guard !selectedURLs.isEmpty else { return }
        isImporting = true
        let targetName = collectionName.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "Nesortate", comment: "Default collection")
            : collectionName
        let resolution: SongDuplicateResolution = {
            switch dupMode {
            case "keepBoth": return .keepBoth
            case "skip": return .skip
            default: return .addAsVersion
            }
        }()

        Task {
            let result = await ImportService.importSongItems(
                urls: selectedURLs,
                collectionName: targetName,
                modelContext: modelContext,
                duplicateResolution: resolution,
                progressHandler: { progress, status in
                    Task { @MainActor in
                        importProgress = progress
                        importStatusText = status
                    }
                }
            )

            await MainActor.run {
                isImporting = false
                if result.failures.isEmpty, !result.importedTitles.isEmpty {
                    appState.showSuccess(
                        String(localized: "Import Successful", comment: "Alert title"),
                        message: String(localized: "Au fost importate \(result.importedTitles.count) cântece în \"\(targetName)\".", comment: "Alert message")
                    )
                    dismiss()
                } else if result.importedTitles.isEmpty {
                    let details = result.failures
                        .prefix(5)
                        .map { "\($0.file): \($0.reason)" }
                        .joined(separator: "\n")
                    appState.showError(
                        String(localized: "Import Failed", comment: "Alert title"),
                        message: details.isEmpty
                            ? String(localized: "Nu a fost găsit niciun cântec.", comment: "Alert message")
                            : details
                    )
                } else {
                    let details = result.failures
                        .prefix(5)
                        .map { "\($0.file): \($0.reason)" }
                        .joined(separator: "\n")
                    appState.showSuccess(
                        String(localized: "Import Parțial", comment: "Alert title"),
                        message: String(localized: "Importate: \(result.importedTitles.count). Eșuate: \(result.failures.count).\n\(details)", comment: "Alert message")
                    )
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Song Editor (visual editing of all stored content)

let songSectionTypes = ["verse", "chorus", "bridge", "prechorus", "intro", "ending", "tag", "interlude", "other"]

func songTypeColor(_ type: String) -> Color {
    switch type {
    case "chorus": return .orange
    case "bridge": return .purple
    case "prechorus": return .pink
    case "intro", "ending": return .teal
    case "tag": return .green
    case "interlude": return .indigo
    default: return .blue   // verse / other
    }
}

func songTypeLabel(_ type: String) -> String {
    switch type {
    case "verse": return String(localized: "Strofă", comment: "Section type")
    case "chorus": return String(localized: "Refren", comment: "Section type")
    case "bridge": return String(localized: "Punte", comment: "Section type")
    case "prechorus": return String(localized: "Pre-refren", comment: "Section type")
    case "intro": return String(localized: "Intro", comment: "Section type")
    case "ending": return String(localized: "Final", comment: "Section type")
    case "tag": return String(localized: "Tag", comment: "Section type")
    case "interlude": return String(localized: "Interludiu", comment: "Section type")
    default: return String(localized: "Altul", comment: "Section type")
    }
}

/// A theme-rendered slide: the song profile's background (image > color > global) with the
/// theme text color — so previews/thumbnails look like the real output, not a plain box.
struct SongThemeSlideView: View {
    let text: String
    var fontSize: CGFloat = 13
    @Environment(PresentationManager.self) private var pm

    var body: some View {
        let bg = pm.backgroundConfig(for: "song")
        ZStack {
            if bg.enabled, bg.useImage, let img = pm.contentBackgroundImages["song"] {
                Image(nsImage: img).resizable().scaledToFill()
            } else if bg.enabled, bg.showColor {
                (Color(hex: bg.colorHex) ?? .black)
            } else {
                pm.backgroundColor
            }
            Text(text)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Color(hex: pm.textColorHex) ?? .white)
                .multilineTextAlignment(.center)
                .lineLimit(8)
                .padding(8)
                .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
        }
        .clipped()
    }
}

// ChordPro round-trip so the editor can show/edit inline [G] chords without losing them.
func songLinesToChordPro(_ lines: [SongLine]) -> String {
    lines.map { line in
        let chords = line.chords.sorted { $0.pos < $1.pos }
        var out = ""
        var ci = 0
        for (i, ch) in line.text.enumerated() {
            while ci < chords.count && chords[ci].pos <= i { out += "[\(chords[ci].sym)]"; ci += 1 }
            out.append(ch)
        }
        while ci < chords.count { out += "[\(chords[ci].sym)]"; ci += 1 }
        return out
    }.joined(separator: "\n")
}

func songChordProToLines(_ text: String) -> [SongLine] {
    text.components(separatedBy: "\n").map { raw in
        var t = ""
        var chords: [SongChord] = []
        var i = raw.startIndex
        while i < raw.endIndex {
            if raw[i] == "[", let close = raw[i...].firstIndex(of: "]") {
                let sym = String(raw[raw.index(after: i)..<close])
                if !sym.isEmpty { chords.append(SongChord(sym: sym, pos: t.count)) }
                i = raw.index(after: close)
                continue
            }
            t.append(raw[i])
            i = raw.index(after: i)
        }
        return SongLine(text: t, chords: chords)
    }
}

/// Apply the theme's repeat-marker style to a repeated section's lines (count > 1).
/// Opening/closing bracket glyphs for a repeat-bracket style ("" when none).
func repeatBracketGlyphs(_ bracket: String) -> (open: String, close: String) {
    switch bracket {
    case "slash": return ("/: ", " :/")
    case "bar":   return ("‖: ", " :‖")
    case "pipe":  return ("|: ", " :|")
    default:      return ("", "")
    }
}

/// The inline repeat-count suffix for a count style ("" when none/≤1).
func repeatCountSuffix(_ countStyle: String, count: Int) -> String {
    guard count > 1 else { return "" }
    switch countStyle {
    case "times":  return " (×\(count))"
    case "bister": return " " + (count == 2 ? "bis" : (count == 3 ? "ter" : "×\(count)"))
    default:       return ""
    }
}

/// Decorate display lines with a repeat BRACKET (wraps first/last line) and/or a
/// repeat COUNT (appended inline to the last line) — the two combine, e.g.
/// "‖: … :‖ (×2)". Line count is unchanged, so text + rich chunk identically.
func applyRepeatMarker(_ lines: [String], count: Int, bracket: String, countStyle: String) -> [String] {
    guard count > 1, !lines.isEmpty else { return lines }
    let (open, close) = repeatBracketGlyphs(bracket)
    let suffix = repeatCountSuffix(countStyle, count: count)
    guard !open.isEmpty || !suffix.isEmpty else { return lines }
    var out = lines
    out[0] = open + out[0]
    out[out.count - 1] = out[out.count - 1] + close + suffix
    return out
}

/// Repeat markers on rich (chorded) lines — mirrors `applyRepeatMarker`, shifting
/// the first line's chord positions by the opening bracket so chords stay aligned.
func applyRepeatMarkerRich(_ lines: [SongLine], count: Int, bracket: String, countStyle: String) -> [SongLine] {
    guard count > 1, !lines.isEmpty else { return lines }
    let (open, close) = repeatBracketGlyphs(bracket)
    let suffix = repeatCountSuffix(countStyle, count: count)
    guard !open.isEmpty || !suffix.isEmpty else { return lines }
    var out = lines
    let first = out[0]
    out[0] = SongLine(text: open + first.text,
                      chords: first.chords.map { SongChord(sym: $0.sym, pos: $0.pos + open.count) },
                      translations: first.translations)
    let li = out.count - 1
    let last = out[li]
    out[li] = SongLine(text: last.text + close + suffix, chords: last.chords, translations: last.translations)
    return out
}

/// Resolve the effective repeat bracket + count for a version, honoring its single
/// legacy `repeatStyle` override: slash/bar/pipe overrides the bracket; times/bister
/// overrides the count; "none" disables both; "" inherits the globals.
func resolveRepeat(versionStyle: String, globalBracket: String, globalCount: String) -> (bracket: String, count: String) {
    switch versionStyle {
    case "slash", "bar", "pipe": return (versionStyle, globalCount)
    case "times", "bister":      return (globalBracket, versionStyle)
    case "none":                 return ("none", "none")
    default:                     return (globalBracket, globalCount)
    }
}

struct SongEditorSheet: View {
    @Bindable var song: Song
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(LibraryManager.self) private var libraryManager
    @Query(sort: \Songbook.name) private var allSongbooks: [Songbook]
    @State private var selectedVersionID: UUID?
    @State private var focusedSectionID: UUID?
    @State private var newBookName = ""
    /// GOAT snapshot captured when the editor opens — used to revert on Cancel and to
    /// diff for the change log on Gata.
    @State private var openSnapshot: String = ""
    @State private var showChangeLog = false
    @AppStorage("song_repeatBracket") private var globalRepeatBracket = "none"
    @AppStorage("song_repeatCount") private var globalRepeatCount = "times"

    private var currentVersion: SongVersion? {
        if let id = selectedVersionID, let v = song.versions.first(where: { $0.id == id }) { return v }
        return song.activeVersion
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            versionTabBar
            Divider()
            HSplitView {
                metadataPane
                    .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
                versionPane
                    .frame(minWidth: 440)
            }
        }
        .frame(minWidth: 900, idealWidth: 1020, minHeight: 660, idealHeight: 800)
        .onAppear {
            ensureVersion()
            if openSnapshot.isEmpty { openSnapshot = (try? ExportService.exportSongToTopPresenterJSON(song)) ?? "" }
        }
    }

    private var isOriginalVersion: Bool {
        currentVersion?.id == song.sortedVersions.first?.id
    }

    // MARK: Version tabs (top)
    private var versionTabBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(song.sortedVersions.enumerated()), id: \.element.id) { idx, v in
                        let selected = currentVersion?.id == v.id
                        let title = idx == 0
                            ? String(localized: "Original", comment: "Version")
                            : (v.name.isEmpty ? "Versiunea \(idx + 1)" : v.name)
                        Button {
                            selectedVersionID = v.id
                            focusedSectionID = nil
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: idx == 0 ? "star.fill" : "doc.on.doc").font(.system(size: 9))
                                Text(title).font(.caption.weight(.medium)).lineLimit(1)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: Capsule())
                            .foregroundStyle(selected ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if idx != 0 {
                                Button(role: .destructive) { deleteVersion(v) } label: {
                                    Label(String(localized: "Șterge versiunea", comment: "Menu"), systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            Button { addVersion() } label: {
                Label(String(localized: "Versiune", comment: "Button"), systemImage: "plus").font(.caption)
            }
            .buttonStyle(.bordered)
            .help(String(localized: "Adaugă o versiune (copie a originalului)", comment: "Tooltip"))
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Editor cântec", comment: "Editor title")).font(.headline)
                Text(song.title.isEmpty ? String(localized: "Fără titlu", comment: "Placeholder") : song.title)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !song.editLog.isEmpty {
                Button { showChangeLog = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Istoric modificări", comment: "Tooltip"))
                .popover(isPresented: $showChangeLog, arrowEdge: .bottom) {
                    changeLogView.frame(width: 320, height: 260)
                }
            }
            Button {
                song.verified.toggle()
                song.modifiedDate = .now
            } label: {
                Label(song.verified ? String(localized: "Verificat", comment: "Verified button")
                                    : String(localized: "Verifică", comment: "Verify button"),
                      systemImage: song.verified ? "checkmark.seal.fill" : "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .tint(song.verified ? .green : .secondary)
            .help(String(localized: "Marchează cântecul ca verificat", comment: "Verify tooltip"))

            Button(String(localized: "Renunță", comment: "Cancel button")) { revert(); dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Gata", comment: "Button")) { save(); dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    /// The song's coarse change log, newest first.
    private var changeLogView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "Istoric modificări", comment: "Change log title"))
                .font(.headline).padding(12)
            Divider()
            if song.editLog.isEmpty {
                Text(String(localized: "Nicio modificare înregistrată.", comment: "Empty change log"))
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(song.editLog.sorted { $0.date > $1.date }, id: \.self) { entry in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.summary).font(.callout)
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Metadata pane (left) — per-version metadata + shared song identity
    private var metadataPane: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                versionMetadataGroup
                songIdentityGroup
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder private var versionMetadataGroup: some View {
        if let v = currentVersion {
            let editable = isOriginalVersion || v.overridesMetadata
            let src = editable ? v : (song.sortedVersions.first ?? v)   // inherited values shown read-only
            VStack(alignment: .leading, spacing: 8) {
                if !isOriginalVersion {
                    Toggle(isOn: Binding(
                        get: { v.overridesMetadata },
                        set: { on in
                            if on && !v.overridesMetadata { seedOverrides(into: v) }   // pre-fill from original
                            v.overridesMetadata = on
                        }
                    )) {
                        Text(String(localized: "Date proprii pentru versiune", comment: "Toggle")).font(.caption.bold())
                    }
                    .toggleStyle(.switch).controlSize(.small)
                    if !v.overridesMetadata {
                        Text(String(localized: "Moștenește datele din „Original”. Activează pentru a edita.", comment: "Hint"))
                            .font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                editorGroup(String(localized: "Date versiune", comment: "Group"), icon: "rectangle.stack") {
                    versionField(String(localized: "Titlu afișat", comment: "Field"), src: src, keyPath: \.displayTitle, editable: editable)
                    versionField(String(localized: "Autor", comment: "Field"), src: src, keyPath: \.author, editable: editable)
                    HStack {
                        versionField(String(localized: "Versuri de", comment: "Field"), src: src, keyPath: \.authorWords, editable: editable)
                        versionField(String(localized: "Muzica de", comment: "Field"), src: src, keyPath: \.authorMusic, editable: editable)
                    }
                    versionField(String(localized: "Traducere de", comment: "Field"), src: src, keyPath: \.authorTranslation, editable: editable)
                    HStack {
                        versionField(String(localized: "Limbă", comment: "Field"), src: src, keyPath: \.language, editable: editable, width: 64)
                        versionField(String(localized: "Ton", comment: "Field"), src: src, keyPath: \.key, editable: editable, width: 64)
                        versionField(String(localized: "Tempo", comment: "Field"), src: src, keyPath: \.tempo, editable: editable, width: 64)
                    }
                    versionSongbookField(src: src, editable: editable)
                    HStack {
                        versionField(String(localized: "Stil", comment: "Field"), src: src, keyPath: \.style, editable: editable)
                        versionField(String(localized: "Nr. carte", comment: "Field"), src: src, keyPath: \.songbookNumber, editable: editable, width: 80)
                    }
                    HStack {
                        versionField(String(localized: "Copyright", comment: "Field"), src: src, keyPath: \.copyright, editable: editable)
                        versionField(String(localized: "CCLI", comment: "Field"), src: src, keyPath: \.ccliNumber, editable: editable, width: 90)
                    }
                    versionListField(String(localized: "Teme", comment: "Field"), get: { src.themes }, set: { src.themes = $0 }, editable: editable)
                    if editable {
                        HStack {
                            Stepper("Capo \(src.capo)", value: Binding(get: { src.capo }, set: { src.capo = $0 }), in: 0...11)
                                .font(.caption).fixedSize()
                            Spacer()
                            versionRepeatPicker(src)
                        }
                    } else {
                        HStack {
                            Text("Capo \(src.capo)").font(.callout)
                            Spacer()
                            Text(String(localized: "Repetare: \(repeatStyleLabel(src.repeatStyle))", comment: "Info"))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    versionNotesField(src: src, editable: editable)
                }
            }
        }
    }

    @ViewBuilder private var songIdentityGroup: some View {
        editorGroup(String(localized: "Identitate cântec", comment: "Group"), icon: "music.note") {
            field(String(localized: "Titlu canonic (pentru bibliotecă)", comment: "Field"), text: $song.title)
            field(String(localized: "Alte titluri (toate versiunile)", comment: "Field"),
                  text: listBinding(get: { song.titles }, set: { song.titles = $0 }),
                  hint: String(localized: "separate prin virgulă", comment: "Hint"))
            Text(String(localized: "Restul câmpurilor se editează per versiune, mai sus.", comment: "Hint"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func versionSongbookField(src: SongVersion, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Carte de cântări", comment: "Field")).font(.caption2).foregroundStyle(.secondary)
            if editable {
                HStack(spacing: 6) {
                    Picker("", selection: Binding(get: { src.songbookName }, set: { src.songbookName = $0 })) {
                        Text(String(localized: "Fără carte", comment: "Option")).tag("")
                        ForEach(allSongbooks) { book in Text(book.name).tag(book.name) }
                        if !src.songbookName.isEmpty && !allSongbooks.contains(where: { $0.name == src.songbookName }) {
                            Text(src.songbookName).tag(src.songbookName)
                        }
                    }
                    .labelsHidden()
                    TextField(String(localized: "Carte nouă…", comment: "Field"), text: $newBookName)
                        .textFieldStyle(.roundedBorder)
                    Button(String(localized: "Adaugă", comment: "Button")) { addBook(to: src) }
                        .disabled(newBookName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Text(src.songbookName.isEmpty ? "—" : src.songbookName)
                    .font(.callout).foregroundStyle(src.songbookName.isEmpty ? .tertiary : .primary)
            }
        }
    }

    private func addBook(to src: SongVersion) {
        let name = newBookName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !allSongbooks.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            modelContext.insert(Songbook(name: name))   // add to the shared list of books
        }
        src.songbookName = name
        newBookName = ""
    }

    @ViewBuilder
    private func versionListField(_ label: String, get: @escaping () -> [String], set: @escaping ([String]) -> Void, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            if editable {
                TextField(String(localized: "separate prin virgulă", comment: "Hint"),
                          text: Binding(get: { get().joined(separator: ", ") },
                                        set: { set($0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }))
                    .textFieldStyle(.roundedBorder)
            } else {
                let joined = get().joined(separator: ", ")
                Text(joined.isEmpty ? "—" : joined)
                    .font(.callout).foregroundStyle(joined.isEmpty ? .tertiary : .primary)
            }
        }
    }

    @ViewBuilder
    private func versionNotesField(src: SongVersion, editable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Note", comment: "Field")).font(.caption2).foregroundStyle(.secondary)
            if editable {
                TextEditor(text: Binding(get: { src.notes }, set: { src.notes = $0 }))
                    .font(.body).frame(minHeight: 44)
                    .scrollContentBackground(.hidden)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            } else {
                Text(src.notes.isEmpty ? "—" : src.notes)
                    .font(.callout).foregroundStyle(src.notes.isEmpty ? .tertiary : .primary)
            }
        }
    }

    /// Seed a version's override fields from the original (so toggling "own data" starts from
    /// the inherited values rather than blanks).
    private func seedOverrides(into v: SongVersion) {
        guard let orig = song.sortedVersions.first, orig.id != v.id else { return }
        if v.displayTitle.isEmpty { v.displayTitle = orig.displayTitle.isEmpty ? song.title : orig.displayTitle }
        if v.author.isEmpty { v.author = orig.author.isEmpty ? song.author : orig.author }
        if v.language.isEmpty { v.language = orig.language }
        if v.key.isEmpty { v.key = orig.key }
        if v.tempo.isEmpty { v.tempo = orig.tempo }
        if v.copyright.isEmpty { v.copyright = orig.copyright }
        if v.ccliNumber.isEmpty { v.ccliNumber = orig.ccliNumber }
        if v.capo == 0 { v.capo = orig.capo }
        if v.repeatStyle.isEmpty { v.repeatStyle = orig.repeatStyle }
        if v.authorWords.isEmpty { v.authorWords = orig.authorWords }
        if v.authorMusic.isEmpty { v.authorMusic = orig.authorMusic }
        if v.authorTranslation.isEmpty { v.authorTranslation = orig.authorTranslation }
        if v.style.isEmpty { v.style = orig.style }
        if v.songbookNumber.isEmpty { v.songbookNumber = orig.songbookNumber }
        if v.songbookName.isEmpty { v.songbookName = orig.songbookName }
        if v.themes.isEmpty { v.themes = orig.themes }
        if v.notes.isEmpty { v.notes = orig.notes }
    }

    /// Existing/imported songs store metadata on the Song. Copy it onto the original version
    /// (where empty) so the per-version editor and inheritance have a real source.
    private func hydrateOriginalFromSong() {
        guard let orig = song.sortedVersions.first else { return }
        if orig.displayTitle.isEmpty { orig.displayTitle = song.title }
        if orig.author.isEmpty { orig.author = song.author }
        if orig.authorWords.isEmpty { orig.authorWords = song.authorWords }
        if orig.authorMusic.isEmpty { orig.authorMusic = song.authorMusic }
        if orig.authorTranslation.isEmpty { orig.authorTranslation = song.authorTranslation }
        if orig.language.isEmpty { orig.language = song.language }
        if orig.key.isEmpty { orig.key = song.key }
        if orig.tempo.isEmpty { orig.tempo = song.tempo }
        if orig.copyright.isEmpty { orig.copyright = song.copyright }
        if orig.ccliNumber.isEmpty { orig.ccliNumber = song.ccliNumber }
        if orig.style.isEmpty { orig.style = song.style }
        if orig.songbookNumber.isEmpty { orig.songbookNumber = song.songbookNumber }
        if orig.songbookName.isEmpty { orig.songbookName = song.songbook?.name ?? "" }
        if orig.themes.isEmpty { orig.themes = song.themes }
        if orig.notes.isEmpty { orig.notes = song.notes }
    }

    /// Mirror the original version's metadata back onto the Song so the library browser
    /// and search stay accurate.
    private func mirrorOriginalToSong() {
        guard let orig = song.sortedVersions.first else { return }
        if !orig.displayTitle.isEmpty { song.title = orig.displayTitle }
        song.author = orig.author
        song.authorWords = orig.authorWords
        song.authorMusic = orig.authorMusic
        song.authorTranslation = orig.authorTranslation
        song.language = orig.language
        song.key = orig.key
        song.tempo = orig.tempo
        song.copyright = orig.copyright
        song.ccliNumber = orig.ccliNumber
        song.style = orig.style
        song.songbookNumber = orig.songbookNumber
        if !orig.songbookName.isEmpty {
            song.songbook = allSongbooks.first { $0.name.caseInsensitiveCompare(orig.songbookName) == .orderedSame }
                ?? { let b = Songbook(name: orig.songbookName); modelContext.insert(b); return b }()
        }
        song.themes = orig.themes
        song.notes = orig.notes
    }

    @ViewBuilder
    private func versionField(_ label: String, src: SongVersion, keyPath: ReferenceWritableKeyPath<SongVersion, String>, editable: Bool, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            if editable {
                TextField("", text: Binding(get: { src[keyPath: keyPath] }, set: { src[keyPath: keyPath] = $0 }))
                    .textFieldStyle(.roundedBorder).frame(width: width)
            } else {
                Text(src[keyPath: keyPath].isEmpty ? "—" : src[keyPath: keyPath])
                    .font(.callout)
                    .foregroundStyle(src[keyPath: keyPath].isEmpty ? .tertiary : .primary)
                    .frame(width: width, alignment: .leading)
            }
        }
    }

    private func repeatStyleLabel(_ style: String) -> String {
        switch style {
        case "slash": return "/: :/"
        case "bar": return "‖: :‖"
        case "pipe": return "|: :|"
        case "times": return "(×N)"
        case "bister": return "bis/ter"
        case "none": return String(localized: "Fără", comment: "Repeat style")
        default: return String(localized: "Implicit", comment: "Repeat style")
        }
    }

    // MARK: Version pane (right)
    private var versionPane: some View {
        VStack(spacing: 0) {
            if let version = currentVersion, let section = focusedSection(in: version) {
                let (b, c) = resolveRepeat(versionStyle: version.repeatStyle, globalBracket: globalRepeatBracket, globalCount: globalRepeatCount)
                let previewLines = applyRepeatMarker(section.lines.map { $0.text }, count: section.repeatCount, bracket: b, countStyle: c)
                let previewText = previewLines.joined(separator: "\n")
                SongThemeSlideView(text: previewText.isEmpty ? section.label : previewText, fontSize: 16)
                    .frame(height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(12)
                Divider()
            }

            if let version = currentVersion {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(version.sortedSections) { section in
                            SectionEditorCard(
                                section: section,
                                isFocused: focusedSectionID == section.id,
                                onFocus: { focusedSectionID = section.id },
                                onMoveUp: { move(section, by: -1, in: version) },
                                onMoveDown: { move(section, by: 1, in: version) },
                                onDelete: { deleteSection(section, in: version) },
                                onDuplicate: { duplicateSection(section, in: version) },
                                onDrop: { draggedID in reorder(draggedID: draggedID, before: section, in: version) }
                            )
                        }
                        addSectionMenu(version)
                    }
                    .padding(12)
                }
            } else {
                ContentUnavailableView(String(localized: "Nicio versiune", comment: "Empty"), systemImage: "music.note")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func addSectionMenu(_ version: SongVersion) -> some View {
        Menu {
            ForEach(songSectionTypes, id: \.self) { type in
                Button(songTypeLabel(type)) { addSection(type, to: version) }
            }
        } label: {
            Label(String(localized: "Adaugă strofă", comment: "Button"), systemImage: "plus.rectangle.on.rectangle")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.borderlessButton)
    }

    // MARK: small builders
    @ViewBuilder
    private func editorGroup<C: View>(_ title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.bold()).foregroundStyle(.secondary)
            content()
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
    }

    private func field(_ label: String, text: Binding<String>, hint: String = "") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder)
        }
    }

    private func compactField(_ label: String, text: Binding<String>, width: CGFloat? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            TextField("", text: text).textFieldStyle(.roundedBorder).frame(width: width)
        }
    }

    private func versionRepeatPicker(_ version: SongVersion) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "Repetare", comment: "Field")).font(.system(size: 9)).foregroundStyle(.secondary)
            Picker("", selection: Binding(get: { version.repeatStyle }, set: { version.repeatStyle = $0 })) {
                Text(String(localized: "Implicit", comment: "Option")).tag("")
                Text(String(localized: "Fără", comment: "Option")).tag("none")
                Text("/: :/").tag("slash")
                Text("‖: :‖").tag("bar")
                Text("|: :|").tag("pipe")
                Text("(×N)").tag("times")
                Text("bis/ter").tag("bister")
            }
            .labelsHidden().controlSize(.small).fixedSize()
        }
    }

    private var songbookField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Carte de cântări", comment: "Field")).font(.caption2).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { song.songbook?.id },
                set: { id in song.songbook = allSongbooks.first { $0.id == id } }
            )) {
                Text(String(localized: "Fără carte", comment: "Option")).tag(UUID?.none)
                ForEach(allSongbooks) { book in
                    Text(book.name).tag(UUID?.some(book.id))
                }
            }
            .labelsHidden()
            HStack(spacing: 6) {
                TextField(String(localized: "Carte nouă…", comment: "Field"), text: $newBookName)
                    .textFieldStyle(.roundedBorder)
                Button(String(localized: "Adaugă", comment: "Button")) { addBook() }
                    .disabled(newBookName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addBook() {
        let name = newBookName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let existing = allSongbooks.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            song.songbook = existing
        } else {
            let book = Songbook(name: name)
            modelContext.insert(book)
            song.songbook = book
        }
        newBookName = ""
    }

    private func focusedSection(in version: SongVersion) -> SongSection? {
        if let id = focusedSectionID, let s = version.sections.first(where: { $0.id == id }) { return s }
        return version.sortedSections.first
    }

    private func addSection(_ type: String, to version: SongVersion) {
        let n = version.sections.count
        let s = SongSection(sectionKey: "\(type.prefix(1))\(n + 1)", type: type,
                            label: "\(songTypeLabel(type)) \(n + 1)", order: n, lines: [SongLine(text: "")])
        s.version = version
        focusedSectionID = s.id
    }

    /// Delete a strofă: remove it from the version's relationship (so the card
    /// list refreshes immediately), renumber the remaining sections (no order
    /// gaps), and delete the model. Committed at „Gata"; „Renunță" still reverts
    /// via the GOAT snapshot.
    private func deleteSection(_ section: SongSection, in version: SongVersion) {
        if focusedSectionID == section.id { focusedSectionID = nil }
        version.sections.removeAll { $0.id == section.id }
        modelContext.delete(section)
        for (i, s) in version.sortedSections.enumerated() { s.order = i }
    }

    private func duplicateSection(_ section: SongSection, in version: SongVersion) {
        // Make room right after the original, then insert the copy there.
        for s in version.sortedSections where s.order > section.order {
            s.order += 1
        }
        let copy = SongSection(
            sectionKey: "\(section.sectionKey)2", type: section.type, label: section.label,
            order: section.order + 1, repeatCount: section.repeatCount, lines: section.lines
        )
        copy.version = version
        focusedSectionID = copy.id
    }

    private func move(_ section: SongSection, by delta: Int, in version: SongVersion) {
        let sorted = version.sortedSections
        guard let i = sorted.firstIndex(where: { $0.id == section.id }) else { return }
        let j = i + delta
        guard j >= 0, j < sorted.count else { return }
        let tmp = sorted[i].order
        sorted[i].order = sorted[j].order
        sorted[j].order = tmp
    }

    /// Drag-reorder: move the dragged section to sit just before `target`, then renumber.
    private func reorder(draggedID: String, before target: SongSection, in version: SongVersion) {
        guard let dragged = version.sections.first(where: { $0.id.uuidString == draggedID }),
              dragged.id != target.id else { return }
        var ordered = version.sortedSections
        ordered.removeAll { $0.id == dragged.id }
        guard let ti = ordered.firstIndex(where: { $0.id == target.id }) else { return }
        ordered.insert(dragged, at: ti)
        for (i, s) in ordered.enumerated() { s.order = i }
    }

    private func listBinding(get: @escaping () -> [String], set: @escaping ([String]) -> Void) -> Binding<String> {
        Binding(
            get: { get().joined(separator: ", ") },
            set: { set($0.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }) }
        )
    }

    /// Older songs (imported before versions existed) get a version synthesized from the
    /// flattened cache the first time they're edited — an on-demand backfill.
    private func ensureVersion() {
        if song.versions.isEmpty {
            let v = SongVersion(name: "Original", order: 0)
            v.song = song
            for (i, verse) in song.sortedVerses.enumerated() {
                let s = SongSection(
                    sectionKey: verse.label.isEmpty ? "s\(i)" : verse.label,
                    type: verse.verseType, label: verse.label, order: i,
                    lines: verse.text.components(separatedBy: "\n").map { SongLine(text: $0) }
                )
                s.version = v
            }
            modelContext.insert(v)
            selectedVersionID = v.id
        } else {
            // Open the version the slide came from (if any), else the original/active one.
            selectedVersionID = libraryManager.songEditVersionID ?? song.activeVersion?.id
        }
        hydrateOriginalFromSong()
        libraryManager.songEditVersionID = nil
        // Focus the section the user clicked "edit" on (from a slide), else the first.
        if let key = libraryManager.songEditSectionKey,
           let match = currentVersion?.sections.first(where: { $0.sectionKey == key }) {
            focusedSectionID = match.id
            libraryManager.songEditSectionKey = nil
        } else {
            focusedSectionID = currentVersion?.sortedSections.first?.id
        }
    }

    /// New versions start as a copy of the current one (key/tempo/arrangement + all sections).
    private func addVersion() {
        let v = SongVersion(name: "Versiunea \(song.versions.count + 1)", order: song.versions.count)
        v.song = song
        if let source = song.activeVersion {
            v.key = source.key
            v.capo = source.capo
            v.tempo = source.tempo
            v.timeSignature = source.timeSignature
            v.language = source.language
            v.arrangement = source.arrangement
            for sec in source.sortedSections {
                let copy = SongSection(sectionKey: sec.sectionKey, type: sec.type, label: sec.label, order: sec.order, lines: sec.lines)
                copy.version = v
            }
        } else {
            let s = SongSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [SongLine(text: "")])
            s.version = v
        }
        modelContext.insert(v)
        selectedVersionID = v.id
        focusedSectionID = v.sortedSections.first?.id
    }

    private func deleteVersion(_ v: SongVersion) {
        let fallback = song.sortedVersions.first { $0.id != v.id }?.id
        modelContext.delete(v)
        selectedVersionID = fallback
    }

    /// Keep the flattened SongVerse cache + searchText in sync with the active version.
    private func save() {
        mirrorOriginalToSong()
        for old in song.verses { modelContext.delete(old) }
        var lyrics = ""
        if let active = song.activeVersion {
            for (i, sec) in active.sortedSections.enumerated() {
                let verse = SongVerse(label: sec.label, verseType: sec.type, text: sec.plainText, order: i)
                verse.song = song
                lyrics += " " + sec.plainText
            }
        }
        song.searchText = Song.makeSearchText(
            title: song.title, titles: song.titles, author: song.author,
            authorWords: song.authorWords, songNumber: song.songNumber,
            songbookNumber: song.songbookNumber, lyrics: lyrics
        )
        // Append a coarse change-log entry if anything actually changed since open.
        recordEditLog()
        try? modelContext.save()
    }

    /// Diff the open snapshot against the current song and append summaries to the
    /// change log (edit-log only — no restore). Updates `modifiedDate` on any change.
    private func recordEditLog() {
        guard let old = TopPresenterSongImporter.result(fromJSON: openSnapshot),
              let new = TopPresenterSongImporter.result(fromJSON: (try? ExportService.exportSongToTopPresenterJSON(song)) ?? "") else { return }
        let summaries = ImportService.summarizeChanges(old: old, new: new)
        guard !summaries.isEmpty else { return }
        let now = Date.now
        var log = song.editLog
        log.append(contentsOf: summaries.map { SongEditEntry(date: now, summary: $0) })
        song.editLog = log
        song.modifiedDate = now
        // Re-baseline so a second Gata without edits doesn't double-log.
        openSnapshot = (try? ExportService.exportSongToTopPresenterJSON(song)) ?? openSnapshot
    }

    /// Discard all edits made in this session by rebuilding the song from the snapshot.
    private func revert() {
        guard let result = TopPresenterSongImporter.result(fromJSON: openSnapshot) else { return }
        ImportService.applyResult(result, to: song, modelContext: modelContext)
        try? modelContext.save()
    }
}

struct SectionEditorCard: View {
    @Bindable var section: SongSection
    var isFocused: Bool
    var onFocus: () -> Void
    var onMoveUp: () -> Void
    var onMoveDown: () -> Void
    var onDelete: () -> Void
    var onDuplicate: () -> Void = {}
    var onDrop: (String) -> Void = { _ in }

    @State private var chordsOverride: Bool? = nil
    @FocusState private var editorFocused: Bool
    private var sectionHasChords: Bool { section.lines.contains { !$0.chords.isEmpty } }
    private var showChords: Bool { chordsOverride ?? sectionHasChords }

    private var lyricsBinding: Binding<String> {
        if showChords {
            return Binding(
                get: { songLinesToChordPro(section.lines) },
                set: { section.lines = songChordProToLines($0) }
            )
        }
        return Binding(
            get: { section.plainText },
            set: { section.lines = $0.components(separatedBy: "\n").map { SongLine(text: $0) } }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Drag handle (reorder)
                Image(systemName: "line.3.horizontal")
                    .font(.caption).foregroundStyle(.tertiary)
                    .draggable(section.id.uuidString)
                    .help(String(localized: "Trage pentru reordonare", comment: "Tooltip"))

                // Colored type badge + picker
                Menu {
                    ForEach(songSectionTypes, id: \.self) { type in
                        Button(songTypeLabel(type)) { section.type = type }
                    }
                } label: {
                    Text(songTypeLabel(section.type))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(songTypeColor(section.type).opacity(0.2), in: Capsule())
                        .foregroundStyle(songTypeColor(section.type))
                }
                .menuStyle(.borderlessButton).fixedSize()

                TextField(String(localized: "Etichetă", comment: "Field"), text: $section.label)
                    .textFieldStyle(.plain).font(.callout.weight(.medium))

                Spacer()

                Stepper("×\(section.repeatCount)", value: $section.repeatCount, in: 1...8)
                    .controlSize(.mini).fixedSize()
                    .help(String(localized: "De câte ori se cântă", comment: "Tooltip"))

                Button { chordsOverride = !showChords } label: {
                    Image(systemName: "music.note")
                        .foregroundStyle(showChords ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Acorduri inline [G]", comment: "Tooltip"))

                Button(action: onMoveUp) { Image(systemName: "chevron.up") }.buttonStyle(.borderless)
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }.buttonStyle(.borderless)
                Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }
                    .buttonStyle(.borderless)
                    .help(String(localized: "Duplică strofa", comment: "Tooltip"))
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
            }

            TextEditor(text: lyricsBinding)
                .font(showChords ? .system(.body, design: .monospaced) : .body)
                .frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                // Editing/clicking into a section drives the editor preview to it.
                .focused($editorFocused)
                .onChange(of: editorFocused) { _, focused in if focused { onFocus() } }

            if showChords {
                Text(String(localized: "Scrie acordurile între paranteze: [G]Mare ești [D]Tu", comment: "Hint"))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(
            isFocused ? songTypeColor(section.type).opacity(0.08) : Color.secondary.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isFocused ? songTypeColor(section.type) : .clear, lineWidth: 1.5)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(songTypeColor(section.type))
                .frame(width: 3)
                .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .dropDestination(for: String.self) { items, _ in
            if let id = items.first { onDrop(id) }
            return true
        }
    }
}
