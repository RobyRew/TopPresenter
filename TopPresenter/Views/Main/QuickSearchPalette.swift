//
//  QuickSearchPalette.swift
//  TopPresenter
//
//  ⌘K — Spotlight-style command palette. The search itself (PaletteSearch.run)
//  executes ONCE per keystroke in a DETACHED task over an immutable snapshot —
//  body only renders `hits` state, so typing stays instant on 60k songs +
//  whole Bibles. Typo-tolerant (fuzzy token fallback), highlighted matches,
//  recents on empty query. Enter opens/navigates; ⌘Enter presents LIVE.
//

import SwiftUI
import SwiftData

// MARK: - Recents (last opened/presented items, persisted)

struct PaletteRecent: Codable, Equatable, Identifiable {
    var kind: String              // "song" | "media" | "session" | "verse" | "reference"
    var uuid: UUID?               // song / media / session
    var bookNumber: Int = 0       // verse / reference
    var chapter: Int = 0
    var verseStart: Int = 0
    var verseEnd: Int = 0
    var title: String
    var subtitle: String

    var id: String { "\(kind):\(uuid?.uuidString ?? "\(bookNumber):\(chapter):\(verseStart)-\(verseEnd)")" }
}

/// Last 10 items opened/presented from the palette — shown on empty query.
@Observable
final class PaletteRecentsStore {
    static let shared = PaletteRecentsStore()
    private static let key = "palette_recents_v1"

    private(set) var items: [PaletteRecent] = []

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([PaletteRecent].self, from: data) {
            items = decoded
        }
    }

    func record(_ recent: PaletteRecent) {
        items.removeAll { $0.id == recent.id }
        items.insert(recent, at: 0)
        if items.count > 10 { items.removeLast(items.count - 10) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// Advanced settings ▸ „Golește recentele ⌘K".
    func clear() {
        items = []
        UserDefaults.standard.removeObject(forKey: Self.key)
    }
}

// MARK: - Results

private enum PaletteResult {
    case reference(BibleReferenceMatch)
    case song(SongIndexEntry)
    case verse(VerseIndexEntry)
    case media(MediaIndexEntry)
    case session(SessionIndexEntry)
    case recent(PaletteRecent)

    var id: String {
        switch self {
        case .reference(let r): return "ref:\(r.bookNumber):\(r.chapter):\(r.verseStart ?? 0)-\(r.verseEnd ?? 0)"
        case .song(let e): return "song:\(e.id.uuidString)"
        case .verse(let v): return "verse:\(v.bookNumber):\(v.chapter):\(v.verse)"
        case .media(let m): return "media:\(m.id.uuidString)"
        case .session(let s): return "session:\(s.id.uuidString)"
        case .recent(let r): return "recent:\(r.id)"
        }
    }
}

extension PaletteResult {
    fileprivate var iconName: String {
        switch self {
        case .reference: return "book.fill"
        case .song: return "music.note"
        case .verse: return "text.quote"
        case .media(let m): return (MediaKind(rawValue: m.mediaType) ?? .image).systemImage
        case .session: return "list.bullet.rectangle"
        case .recent(let r): return PaletteRow.icon(forKind: r.kind)
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .reference: return .blue
        case .song: return .purple
        case .verse: return .green
        case .media: return .orange
        case .session: return .teal
        case .recent: return .gray
        }
    }

    fileprivate var titleText: String {
        switch self {
        case .reference(let r):
            if r.isBookOnly { return r.bookName }
            if let vs = r.verseStart, let ve = r.verseEnd {
                return vs == ve ? "\(r.bookName) \(r.chapter):\(vs)" : "\(r.bookName) \(r.chapter):\(vs)-\(ve)"
            }
            return "\(r.bookName) \(r.chapter)"
        case .song(let e): return e.title
        case .verse(let v): return "\(v.bookName) \(v.chapter):\(v.verse)"
        case .media(let m): return m.name
        case .session(let s): return s.name
        case .recent(let r): return r.title
        }
    }

    fileprivate var subtitleText: String {
        switch self {
        case .reference(let r):
            return r.isBookOnly
                ? String(localized: "Deschide cartea", comment: "Palette row subtitle")
                : String(localized: "Sari la pasaj", comment: "Palette row subtitle")
        case .song(let e): return e.author.isEmpty ? e.collectionName : e.author
        case .verse(let v): return String(v.text.prefix(90))
        case .media(let m): return m.mediaType.capitalized
        case .session(let s): return s.date.formatted(date: .abbreviated, time: .omitted)
        case .recent(let r): return r.subtitle
        }
    }

    /// Small kind label for the preview header.
    fileprivate var kindLabel: String {
        switch self {
        case .reference: return String(localized: "Referință", comment: "Palette kind")
        case .song: return String(localized: "Cântec", comment: "Palette kind")
        case .verse: return String(localized: "Verset", comment: "Palette kind")
        case .media: return String(localized: "Media", comment: "Palette kind")
        case .session: return String(localized: "Sesiune", comment: "Palette kind")
        case .recent: return String(localized: "Recent", comment: "Palette kind")
        }
    }
}

private struct PaletteRowItem: Identifiable {
    let flatIndex: Int
    let result: PaletteResult
    var id: String { result.id }
}

private struct PaletteSection: Identifiable {
    let id: String
    let title: String
    /// Already sliced for display (collapsed cap or full carried set).
    let rows: [PaletteRowItem]
    /// TOTAL matches in the index (can exceed what was carried to the UI).
    let total: Int
    let expanded: Bool
    /// More rows available than shown (collapsed) — or collapsible (expanded).
    let expandable: Bool
    /// Expanded, but the index holds more than the carried 50.
    let truncated: Bool
}

// MARK: - Palette

struct QuickSearchPalette: View {
    /// THE show/hide spring — every `showQuickSearch`/`isPresented` flip must
    /// go through `withAnimation(Self.showHideAnimation)`. Container-level
    /// `.animation(value:)` is banned: it animated unrelated layout changes
    /// that landed in the same tick (module switch on Enter).
    static let showHideAnimation = Animation.spring(duration: 0.25, bounce: 0.15)

    @Environment(\.modelContext) private var modelContext
    @Environment(SearchIndex.self) private var index
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var pm
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService
    @Environment(AppState.self) private var appState
    @Environment(HistoryStore.self) private var history

    @Binding var isPresented: Bool

    @State private var query = ""
    @State private var hits = PaletteHits.none
    @State private var selectedIndex = 0
    /// Sections the user expanded via „Arată mai multe" — reset per query.
    @State private var expandedSections: Set<String> = []
    /// Set ONLY by keyboard navigation — hover/click never scroll the list.
    @State private var scrollTarget: String?
    /// While keyboard-scrolling, the list moves under a stationary cursor —
    /// ignore hover "selection" until this passes (mouse regains control by
    /// actually moving after the window).
    @State private var suppressHoverUntil: Date = .distantPast
    /// Set when a result was opened/presented this session — a dismiss with a
    /// typed query and NO commit logs the search as "abandoned".
    @State private var didCommitSearch = false
    @FocusState private var fieldFocused: Bool

    @AppStorage("song_maxLinesPerSlide") private var maxLines: Int = 6
    @AppStorage("song_repeatBracket") private var repeatBracket = "none"
    @AppStorage("song_repeatCount") private var repeatCount = "times"

    private let recents = PaletteRecentsStore.shared

    // MARK: Display model (cheap mapping over `hits` state — NO searching here)

    private var isQueryEmpty: Bool { query.trimmingCharacters(in: .whitespaces).isEmpty }

    private var sections: [PaletteSection] {
        var out: [PaletteSection] = []
        var idx = 0
        func add(_ id: String, _ title: String, _ results: [PaletteResult],
                 total: Int? = nil, collapsed: Int = .max) {
            guard !results.isEmpty else { return }
            let total = total ?? results.count
            let expanded = expandedSections.contains(id)
            let visible = expanded ? results : Array(results.prefix(collapsed))
            let rows = visible.map { r -> PaletteRowItem in
                defer { idx += 1 }
                return PaletteRowItem(flatIndex: idx, result: r)
            }
            out.append(PaletteSection(
                id: id, title: title, rows: rows, total: total,
                expanded: expanded,
                expandable: results.count > min(collapsed, results.count) || expanded,
                truncated: expanded && total > results.count
            ))
        }

        if isQueryEmpty {
            add("recents", String(localized: "Recente", comment: "Palette section"),
                recents.items.map { .recent($0) })
            return out
        }
        // PRIORITY ORDER is CONTEXT-AWARE (paletteSectionOrder): the module
        // this tab is in floats its own kind right under the pinned reference
        // row — Bible tabs list verses above songs, Songs tabs the opposite.
        // Display-only: ranking inside each section is untouched.
        let specs: [(id: String, title: String, results: [PaletteResult], total: Int, collapsed: Int)] = [
            ("ref", String(localized: "Referință biblică", comment: "Palette section"),
             hits.reference.map { [PaletteResult.reference($0)] } ?? [], hits.reference == nil ? 0 : 1, .max),
            ("songs", String(localized: "Cântece", comment: "Palette section"),
             hits.songsByTitle.map { .song($0) }, hits.songsByTitleTotal, 8),
            ("verses",
             String(localized: "Versete (\(libraryManager.selectedBibleModule?.abbreviation ?? ""))", comment: "Palette section"),
             hits.verses.map { .verse($0) }, hits.versesTotal, 6),
            ("songContent", String(localized: "Cântece – potrivire în versuri", comment: "Palette section"),
             hits.songsByContent.map { .song($0) }, hits.songsByContentTotal, 6),
            ("media", String(localized: "Media", comment: "Palette section"),
             hits.media.map { .media($0) }, hits.mediaTotal, 5),
            ("sessions", String(localized: "Sesiuni", comment: "Palette section"),
             hits.sessions.map { .session($0) }, hits.sessionsTotal, 5),
        ]
        let order = paletteSectionOrder(context: appState.selectedSidebarItem.rawValue)
        // The boosted section (first after the pinned reference) gets a taller
        // collapsed slice before needing „Arată mai multe".
        let boostedID = order.dropFirst().first
        for spec in specs.sorted(by: {
            (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count)
        }) {
            add(spec.id, spec.title, spec.results, total: spec.total,
                collapsed: spec.id == boostedID ? max(spec.collapsed, 8) : spec.collapsed)
        }
        return out
    }

    private var flatResults: [PaletteResult] {
        sections.flatMap { $0.rows.map(\.result) }
    }

    private var selectedResult: PaletteResult? {
        let flat = flatResults
        guard !flat.isEmpty else { return nil }
        return flat[min(selectedIndex, flat.count - 1)]
    }

    /// Search results are stale while `hits.query` lags the typed query.
    private var isSearching: Bool {
        !isQueryEmpty && hits.query != query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Body

    var body: some View {
        ZStack {
            // Layered transitions: the dim always FADES (it covers the whole
            // window — scaling it from the panel's corner read as a black
            // sheet sliding in from the side), only the PANEL gets the scale.
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .transition(.opacity)

            // The panel HUGS its content — never `.frame(maxHeight:)` here: a
            // max-height frame is greedy (min(proposed, max)), which rendered a
            // 480-pt slab with the content floating loose inside it.
            VStack(spacing: 0) {
                searchField
                Divider()
                if isQueryEmpty && recents.items.isEmpty {
                    idleHint
                } else if flatResults.isEmpty {
                    if isSearching {
                        ProgressView().controlSize(.small)
                            .frame(maxWidth: .infinity, minHeight: 150)
                    } else {
                        noResults
                    }
                } else {
                    // Fixed results height (Spotlight-style) — the panel keeps
                    // one stable size while typing instead of jumping around.
                    HStack(spacing: 0) {
                        resultsList
                            .frame(width: 396)
                        Divider()
                        previewPane
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 356)
                }
                Divider()
                footerBar
            }
            .frame(width: 700)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1))
            .shadow(color: .black.opacity(0.42), radius: 38, y: 16)
            .padding(.top, 100)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            // The scale anchors near the toolbar's search capsule so opening
            // reads as the field expanding down into the palette.
            .transition(.scale(scale: 0.92, anchor: UnitPoint(x: 0.85, y: 0))
                .combined(with: .opacity))
        }
        .onAppear {
            fieldFocused = true
            // Make sure the active translation's verse index is (being) built.
            if let moduleID = libraryManager.selectedBibleModule?.id {
                index.indexVerses(moduleID: moduleID)
            }
        }
        // THE search executor: one detached run per (debounced) keystroke or
        // index generation bump. body never computes results itself.
        .task(id: "\(query)#\(index.generation)") {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                hits = .none
                selectedIndex = 0
                expandedSections = []
                return
            }
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled else { return }
            let snapshot = index.snapshot()
            let result = await Task.detached(priority: .userInitiated) {
                PaletteSearch.run(trimmed, in: snapshot)
            }.value
            guard !Task.isCancelled else { return }
            hits = result
            selectedIndex = 0
            expandedSections = []
            scrollTarget = flatResults.first?.id
        }
        .onKeyPress(.escape) { dismiss(); return .handled }
        .onKeyPress(.downArrow) { moveSelection(+1); return .handled }
        .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
        .onKeyPress(keys: [.return], phases: .down) { press in
            guard let result = selectedResult else { return .ignored }
            if press.modifiers.contains(.command) {
                present(result)
            } else {
                open(result)
            }
            return .handled
        }
    }

    /// Keyboard navigation: moves the selection, requests a MINIMAL scroll,
    /// and briefly suppresses hover-selection (the list is about to move under
    /// the stationary cursor).
    private func moveSelection(_ delta: Int) {
        let flat = flatResults
        guard !flat.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), flat.count - 1)
        suppressHoverUntil = Date.now.addingTimeInterval(0.25)
        scrollTarget = flat[selectedIndex].id
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "Cântece, Ioan 3:16, versete, media, sesiuni…", comment: "Palette placeholder"),
                text: $query
            )
            .textFieldStyle(.plain)
            .font(.system(size: 19))
            .focused($fieldFocused)

            if index.isBuilding || isSearching {
                ProgressView().controlSize(.small)
                    .help(String(localized: "Se caută…", comment: "Tooltip"))
            }
            if !query.isEmpty {
                Button {
                    query = ""
                    selectedIndex = 0
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(sections) { section in
                        sectionHeader(section)
                        ForEach(section.rows) { row in
                            PaletteRow(result: row.result,
                                       isSelected: row.flatIndex == selectedIndex,
                                       highlightTokens: hits.tokens)
                                // Scroll anchor = the ForEach identity (result
                                // id). NEVER tag rows with the flat INDEX — an
                                // index-based identity override made lazy rows
                                // show one result's content under another
                                // section's header while results changed.
                                .id(row.id)
                                .contentShape(Rectangle())
                                .onTapGesture { selectedIndex = row.flatIndex; open(row.result) }
                                .onHover { inside in
                                    // The mouse only steals selection when it
                                    // MOVES — not when the list scrolls under
                                    // a stationary cursor during arrow keys.
                                    if inside, Date.now >= suppressHoverUntil {
                                        selectedIndex = row.flatIndex
                                    }
                                }
                        }
                        if section.truncated {
                            Text(String(localized: "afișate \(section.rows.count) din \(section.total) — rafinează căutarea",
                                        comment: "Palette truncation note"))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                        }
                    }
                    if index.isIndexingVerses, !isQueryEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(String(localized: "Se indexează versetele…", comment: "Palette note"))
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.vertical, 6)
            }
            // Keyboard-only autoscroll: minimal movement (anchor nil), never
            // re-centering, never fired by hover/click.
            .onChange(of: scrollTarget) { _, target in
                if let target { proxy.scrollTo(target, anchor: nil) }
            }
        }
    }

    private func sectionHeader(_ section: PaletteSection) -> some View {
        HStack(spacing: 6) {
            Text(section.title)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.7)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 4)
            Text(String(localized: "\(section.total) rezultate", comment: "Palette section count"))
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
            if section.expandable {
                Button {
                    if section.expanded {
                        expandedSections.remove(section.id)
                    } else {
                        expandedSections.insert(section.id)
                    }
                    selectedIndex = min(selectedIndex, max(flatResults.count - 1, 0))
                } label: {
                    HStack(spacing: 3) {
                        Text(section.expanded
                             ? String(localized: "Mai puține", comment: "Palette collapse")
                             : String(localized: "Arată mai multe", comment: "Palette expand"))
                        Image(systemName: section.expanded ? "chevron.up" : "chevron.down")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }

    @ViewBuilder
    private var previewPane: some View {
        if let result = selectedResult {
            VStack(alignment: .leading, spacing: 0) {
                // Header: tinted icon chip + title + kind.
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: result.iconName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(result.tint)
                        .frame(width: 36, height: 36)
                        .background(result.tint.opacity(0.14),
                                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.titleText)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(2)
                        Text(result.kindLabel)
                            .font(.system(size: 10.5, weight: .medium))
                            .tracking(0.5)
                            .textCase(.uppercase)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                }

                Divider().padding(.vertical, 11)

                switch result {
                case .song(let e):
                    VStack(alignment: .leading, spacing: 8) {
                        if !e.author.isEmpty { previewMeta("person", e.author) }
                        if !e.songbookName.isEmpty { previewMeta("book.closed", e.songbookName) }
                        if e.versionCount > 1 {
                            previewMeta("square.stack",
                                        String(localized: "\(e.versionCount) versiuni", comment: "Palette preview"))
                        }
                        if !e.firstLine.isEmpty {
                            Text(e.firstLine)
                                .font(.system(size: 12.5))
                                .italic()
                                .foregroundStyle(.secondary)
                                .lineLimit(5)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.4),
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                case .verse(let v):
                    Text(paletteHighlight(v.text, tokens: hits.tokens,
                                          highlightFont: .system(size: 13, weight: .semibold)))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(11)
                case .reference(let r):
                    Text(referencePreviewText(r))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .lineLimit(11)
                case .media(let m):
                    previewMeta("tag", m.mediaType.capitalized)
                case .session(let s):
                    previewMeta("calendar", s.date.formatted(date: .complete, time: .omitted))
                case .recent(let r):
                    if !r.subtitle.isEmpty {
                        Text(r.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .lineLimit(11)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    private func previewMeta(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var idleHint: some View {
        VStack(spacing: 16) {
            Text(String(localized: "Caută în toată biblioteca", comment: "Palette hint title"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                hintChip("music.note", String(localized: "Cântece", comment: "Palette hint chip"), .purple)
                hintChip("book.fill", "Ioan 3:16", .blue)
                hintChip("text.quote", String(localized: "Versete", comment: "Palette hint chip"), .green)
                hintChip("photo.on.rectangle", "Media", .orange)
                hintChip("list.bullet.rectangle", String(localized: "Sesiuni", comment: "Palette hint chip"), .teal)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
    }

    private func hintChip(_ icon: String, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var noResults: some View {
        VStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(.quaternary)
            Text(String(localized: "Niciun rezultat pentru „\(query)”", comment: "Palette empty"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text(String(localized: "Am căutat și cu toleranță la greșeli de scriere", comment: "Palette empty note"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            keyHint("↩", String(localized: "Deschide", comment: "Palette key hint"))
            keyHint("⌘↩", String(localized: "Proiectează", comment: "Palette key hint"))
            keyHint("↑↓", String(localized: "Navighează", comment: "Palette key hint"))
            Spacer()
            keyHint("esc", String(localized: "Închide", comment: "Palette key hint"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.25))
    }

    private func keyHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Reference helpers (read the in-memory verse index — no SwiftData)

    private func referenceLabel(_ r: BibleReferenceMatch) -> String {
        if r.isBookOnly { return r.bookName }
        if let vs = r.verseStart, let ve = r.verseEnd {
            return vs == ve ? "\(r.bookName) \(r.chapter):\(vs)" : "\(r.bookName) \(r.chapter):\(vs)-\(ve)"
        }
        return "\(r.bookName) \(r.chapter)"
    }

    private func referenceVerses(_ r: BibleReferenceMatch) -> [VerseIndexEntry] {
        index.verses.filter {
            $0.bookNumber == r.bookNumber && $0.chapter == r.chapter
                && (r.verseStart == nil || ($0.verse >= r.verseStart! && $0.verse <= (r.verseEnd ?? r.verseStart!)))
        }
    }

    private func referencePreviewText(_ r: BibleReferenceMatch) -> String {
        let verses = referenceVerses(r).prefix(4)
        return verses.map { "(\($0.verse)) \($0.text)" }.joined(separator: " ")
    }

    // MARK: Actions

    /// Enter — NAVIGATE to the item (safe during a service).
    private func open(_ result: PaletteResult) {
        switch result {
        case .song(let e):
            appState.selectedSidebarItem = .songs
            withModel(Song.self, id: e.id) { song in
                if let col = song.collection { libraryManager.selectCollection(col) }
                libraryManager.selectSong(song)
            }
        case .verse(let v):
            navigateBible(bookNumber: v.bookNumber, chapter: v.chapter, verse: v.verse)
        case .reference(let r):
            navigateBible(bookNumber: r.bookNumber, chapter: r.chapter, verse: r.verseStart)
        case .media(let m):
            appState.selectedSidebarItem = .media
            withModel(MediaItem.self, id: m.id) { libraryManager.selectedMediaItem = $0 }
        case .session(let s):
            appState.selectedSidebarItem = .schedule
            withModel(ServiceSchedule.self, id: s.id) { libraryManager.selectedSchedule = $0 }
        case .recent(let r):
            openRecent(r)
            return
        }
        recordSearchCommit(result)
        recents.record(makeRecent(result))
        dismiss()
    }

    /// ⌘Enter — PRESENT the item live, right from the palette.
    private func present(_ result: PaletteResult) {
        switch result {
        case .song(let e):
            presentSong(id: e.id)
        case .verse(let v):
            presentVerses([v], bookName: v.bookName, chapter: v.chapter)
        case .reference(let r):
            let verses = referenceVerses(r)
            guard !verses.isEmpty else { return }
            presentVerses(verses, bookName: r.bookName, chapter: r.chapter)
        case .media(let m):
            withModel(MediaItem.self, id: m.id) { item in
                MediaPresenter.present(item, pm: pm, video: videoPlayerService, audio: audioPlayerManager)
            }
        case .session(let s):
            withModel(ServiceSchedule.self, id: s.id) { schedule in
                appState.selectedSidebarItem = .schedule
                libraryManager.selectedSchedule = schedule
            }
        case .recent(let r):
            presentRecent(r)
            return
        }
        recordSearchCommit(result)
        recents.record(makeRecent(result))
        dismiss()
    }

    private func presentSong(id: UUID) {
        withModel(Song.self, id: id) { song in
            let version = song.activeVersion
            let slides = buildSongSlides(song: song, version: version, maxLines: maxLines,
                                         bilingual: false, language: nil,
                                         bracket: repeatBracket, countStyle: repeatCount)
            guard let first = slides.first else { return }
            libraryManager.selectSong(song)
            libraryManager.selectSongSlide(text: first.text, label: first.label, index: 0, count: first.total)
            pm.showSongVerse(text: first.text, title: song.title, verseLabel: first.label,
                             slideIndex: 0, slideCount: first.total,
                             song: song, version: version, lines: first.lines)
        }
    }

    /// Push verses live with full coordinates (sets the live Bible anchor).
    private func presentVerses(_ verses: [VerseIndexEntry], bookName: String, chapter: Int) {
        guard let first = verses.first, let last = verses.last else { return }
        let mv = pm.bibleMultiVerse
        let separator = mv.layout == "newLine" ? "\n" : " "
        let text = verses
            .map { mv.showNumbers ? "(\($0.verse)) \($0.text)" : $0.text }
            .joined(separator: separator)
        let range = first.verse == last.verse ? "\(first.verse)" : "\(first.verse)-\(last.verse)"
        let abbrev = libraryManager.selectedBibleModule?.abbreviation ?? ""
        pm.showBibleVerse(text: text, reference: "\(bookName) \(chapter):\(range)",
                          translationName: abbrev,
                          bookNumber: first.bookNumber, bookName: bookName, chapter: chapter,
                          verseStart: first.verse, verseEnd: last.verse, translation: abbrev)
    }

    /// Navigate the Bible browser to a book/chapter(/verse) in the active module.
    private func navigateBible(bookNumber: Int, chapter: Int, verse: Int?) {
        appState.selectedSidebarItem = .bible
        guard let module = libraryManager.selectedBibleModule,
              let book = module.books.first(where: { $0.bookNumber == bookNumber }) else { return }
        libraryManager.selectBook(book)
        guard let chap = book.chapters.first(where: { $0.chapterNumber == chapter }) else { return }
        libraryManager.selectChapter(chap)
        if let verse, let v = chap.verses.first(where: { $0.verseNumber == verse }) {
            libraryManager.selectVerse(v)
        }
    }

    // MARK: Recents plumbing

    private func makeRecent(_ result: PaletteResult) -> PaletteRecent {
        switch result {
        case .song(let e):
            return PaletteRecent(kind: "song", uuid: e.id, title: e.title,
                                 subtitle: e.author.isEmpty ? e.collectionName : e.author)
        case .verse(let v):
            return PaletteRecent(kind: "verse", uuid: nil, bookNumber: v.bookNumber,
                                 chapter: v.chapter, verseStart: v.verse, verseEnd: v.verse,
                                 title: "\(v.bookName) \(v.chapter):\(v.verse)",
                                 subtitle: String(v.text.prefix(90)))
        case .reference(let r):
            return PaletteRecent(kind: "reference", uuid: nil, bookNumber: r.bookNumber,
                                 chapter: r.chapter, verseStart: r.verseStart ?? 0,
                                 verseEnd: r.verseEnd ?? r.verseStart ?? 0,
                                 title: referenceLabel(r),
                                 subtitle: String(localized: "Sari la pasaj", comment: "Palette row subtitle"))
        case .media(let m):
            return PaletteRecent(kind: "media", uuid: m.id, title: m.name,
                                 subtitle: m.mediaType.capitalized)
        case .session(let s):
            return PaletteRecent(kind: "session", uuid: s.id, title: s.name,
                                 subtitle: s.date.formatted(date: .abbreviated, time: .omitted))
        case .recent(let r):
            return r
        }
    }

    private func openRecent(_ r: PaletteRecent) {
        switch r.kind {
        case "song":
            guard let id = r.uuid else { return }
            appState.selectedSidebarItem = .songs
            withModel(Song.self, id: id) { song in
                if let col = song.collection { libraryManager.selectCollection(col) }
                libraryManager.selectSong(song)
            }
        case "media":
            guard let id = r.uuid else { return }
            appState.selectedSidebarItem = .media
            withModel(MediaItem.self, id: id) { libraryManager.selectedMediaItem = $0 }
        case "session":
            guard let id = r.uuid else { return }
            appState.selectedSidebarItem = .schedule
            withModel(ServiceSchedule.self, id: id) { libraryManager.selectedSchedule = $0 }
        case "verse", "reference":
            navigateBible(bookNumber: r.bookNumber, chapter: r.chapter,
                          verse: r.verseStart > 0 ? r.verseStart : nil)
        default:
            return
        }
        recents.record(r)
        dismiss()
    }

    private func presentRecent(_ r: PaletteRecent) {
        switch r.kind {
        case "song":
            guard let id = r.uuid else { return }
            presentSong(id: id)
        case "media":
            guard let id = r.uuid else { return }
            withModel(MediaItem.self, id: id) { item in
                MediaPresenter.present(item, pm: pm, video: videoPlayerService, audio: audioPlayerManager)
            }
        case "session":
            openRecent(r)
            return
        case "verse", "reference":
            // Resolve coordinates against the ACTIVE module's verse index.
            let verses = index.verses.filter {
                $0.bookNumber == r.bookNumber && $0.chapter == r.chapter
                    && (r.verseStart == 0 || ($0.verse >= r.verseStart && $0.verse <= max(r.verseEnd, r.verseStart)))
            }
            guard let first = verses.first else { return }
            presentVerses(verses, bookName: first.bookName, chapter: first.chapter)
        default:
            return
        }
        recents.record(r)
        dismiss()
    }

    /// Predicate + fetchLimit 1 — never fetch-all to find one row.
    private func withModel<T: PersistentModel>(_ type: T.Type, id: UUID, _ action: (T) -> Void)
        where T: IdentifiableByUUID {
        var d = FetchDescriptor<T>(predicate: T.predicate(forID: id))
        d.fetchLimit = 1
        if let model = (try? modelContext.fetch(d))?.first { action(model) }
    }

    // MARK: ⌘K search log (History ▸ Căutări)

    /// One row per COMMITTED result; never per keystroke.
    private func recordSearchCommit(_ result: PaletteResult) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        let kind: String
        switch result {
        case .reference: kind = "reference"
        case .song: kind = "song"
        case .verse: kind = "verse"
        case .media: kind = "media"
        case .session: kind = "session"
        case .recent(let r): kind = r.kind
        }
        history.recordSearch(query: q, resultKind: kind, resultTitle: result.titleText,
                             module: appState.selectedSidebarItem.rawValue)
        didCommitSearch = true
    }

    private func dismiss() {
        // Dead-end searches matter too: closed with a typed query and nothing
        // opened → log as "abandoned".
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty, !didCommitSearch {
            history.recordSearch(query: q, resultKind: "abandoned", resultTitle: "",
                                 module: appState.selectedSidebarItem.rawValue)
        }
        didCommitSearch = false
        withAnimation(Self.showHideAnimation) { isPresented = false }
        query = ""
        hits = .none
        selectedIndex = 0
    }
}

// MARK: - Match highlighting

/// Accent + heavier weight on every (folded) occurrence of the query tokens.
/// `range(of:options:)` handles diacritics natively („marire” finds „Mărire”).
func paletteHighlight(_ text: String, tokens: [String], highlightFont: Font) -> AttributedString {
    var attr = AttributedString(text)
    for tok in tokens where tok.count >= 2 {
        var start = text.startIndex
        while start < text.endIndex,
              let r = text.range(of: tok, options: [.caseInsensitive, .diacriticInsensitive],
                                 range: start..<text.endIndex) {
            if let ar = Range(r, in: attr) {
                attr[ar].foregroundColor = .accentColor
                attr[ar].font = highlightFont
            }
            start = r.upperBound
        }
    }
    return attr
}

// MARK: - UUID predicate helper (SwiftData #Predicate needs concrete key paths)

protocol IdentifiableByUUID: PersistentModel {
    static func predicate(forID id: UUID) -> Predicate<Self>
}

extension Song: IdentifiableByUUID {
    static func predicate(forID id: UUID) -> Predicate<Song> { #Predicate { $0.id == id } }
}
extension MediaItem: IdentifiableByUUID {
    static func predicate(forID id: UUID) -> Predicate<MediaItem> { #Predicate { $0.id == id } }
}
extension ServiceSchedule: IdentifiableByUUID {
    static func predicate(forID id: UUID) -> Predicate<ServiceSchedule> { #Predicate { $0.id == id } }
}

// MARK: - Row

private struct PaletteRow: View {
    let result: PaletteResult
    let isSelected: Bool
    let highlightTokens: [String]

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(result.tint)
                .frame(width: 28, height: 28)
                .background(result.tint.opacity(isSelected ? 0.22 : 0.13),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(paletteHighlight(result.titleText, tokens: highlightTokens,
                                      highlightFont: .system(size: 13, weight: .bold)))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                let subtitle = result.subtitleText
                if !subtitle.isEmpty {
                    Text(paletteHighlight(subtitle, tokens: highlightTokens,
                                          highlightFont: .system(size: 11, weight: .bold)))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? appAccent.opacity(0.2) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 8)
    }

    static func icon(forKind kind: String) -> String {
        switch kind {
        case "song": return "music.note"
        case "verse": return "text.quote"
        case "reference": return "book.fill"
        case "media": return "photo.on.rectangle"
        case "session": return "list.bullet.rectangle"
        default: return "clock.arrow.circlepath"
        }
    }
}
