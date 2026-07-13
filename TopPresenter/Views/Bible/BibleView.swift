//
//  BibleView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import os

/// Main Bible view with module selection, book/chapter navigation, search, and verse display.
struct BibleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AppState.self) private var appState
    @Environment(SearchIndex.self) private var searchIndex

    @Query(sort: \BibleModule.name) private var modules: [BibleModule]

    @State private var showImportSheet = false
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importStatusText = ""
    @State private var showDeleteConfirmation = false
    @State private var moduleToDelete: BibleModule?

    @AppStorage("bibleViewMode") private var viewMode: String = "list"
    @AppStorage("rememberLastModule") private var rememberLastModule: Bool = true
    @AppStorage("defaultBibleModuleName") private var defaultBibleModuleName: String = ""
    @State private var didRestoreModule = false

    // User-resizable books/chapters split, persisted per mode: LIST drags the
    // chapters COLUMN width, GRID drags the books/chapters HEIGHT fraction.
    @AppStorage("bibleListChaptersWidth") private var listChaptersWidth: Double = 132
    @AppStorage("bibleGridBooksFraction") private var gridBooksFraction: Double = 0.55
    @State private var dragBase: Double?

    var body: some View {
        VStack(spacing: 0) {
            if modules.isEmpty {
                emptyStateView
            } else if libraryManager.selectedBibleModule == nil {
                noModuleSelectedView
            } else {
                // ONE skeleton for BOTH modes: the left THIRD holds books +
                // chapters, the right two-thirds is always the full-text
                // verses panel. Inside the third, GRID stacks books over
                // chapters; LIST puts books left, chapters right. No more
                // drill-down levels — everything stays visible.
                GeometryReader { geo in
                    let paneWidth = min(max(geo.size.width / 3, 280), 480)
                    HStack(spacing: 0) {
                        Group {
                            if viewMode == "grid" {
                                VStack(spacing: 0) {
                                    BibleBooksGridPane()
                                        .frame(height: geo.size.height * min(max(gridBooksFraction, 0.25), 0.8))
                                    paneResizeDivider(.vertical) { base, delta in
                                        gridBooksFraction = min(max(base + delta / max(geo.size.height, 1), 0.25), 0.8)
                                    } currentValue: {
                                        gridBooksFraction
                                    }
                                    BibleChaptersPanel()
                                }
                            } else {
                                HStack(spacing: 0) {
                                    BibleNavigationPanel()
                                    paneResizeDivider(.horizontal) { base, delta in
                                        // Chapters sit on the RIGHT: dragging the
                                        // divider left (negative delta) widens them.
                                        listChaptersWidth = min(max(base - delta, 84), Double(paneWidth) * 0.6)
                                    } currentValue: {
                                        listChaptersWidth
                                    }
                                    BibleChaptersPanel(fixedColumns: 2)
                                        .frame(width: min(max(listChaptersWidth, 84), Double(paneWidth) * 0.6))
                                }
                            }
                        }
                        .frame(width: paneWidth)
                        Divider()
                        BibleContentPanel()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            BibleImportSheet(
                isImporting: $isImporting,
                importProgress: $importProgress,
                importStatusText: $importStatusText
            )
        }
        .onChange(of: appState.triggerBibleImport) { _, newValue in
            if newValue {
                showImportSheet = true
                appState.triggerBibleImport = false
            }
        }
        .alert(
            String(localized: "Delete Bible Module", comment: "Alert title"),
            isPresented: $showDeleteConfirmation
        ) {
            Button(String(localized: "Cancel", comment: "Alert button"), role: .cancel) { }
            Button(String(localized: "Delete", comment: "Alert button"), role: .destructive) {
                if let module = moduleToDelete {
                    deleteBibleModule(module)
                }
            }
        } message: {
            Text(String(localized: "Are you sure you want to delete \"\(moduleToDelete?.name ?? "")\"? This cannot be undone.", comment: "Alert message"))
        }
        .onKeyWindowNotification(.deleteBibleModule) { _ in
            moduleToDelete = libraryManager.selectedBibleModule
            showDeleteConfirmation = true
        }
        .onAppear {
            if !didRestoreModule && rememberLastModule && !defaultBibleModuleName.isEmpty {
                if libraryManager.selectedBibleModule == nil,
                   let saved = modules.first(where: { $0.name == defaultBibleModuleName }) {
                    libraryManager.selectModule(saved)
                }
                didRestoreModule = true
            }
        }
        .onChange(of: libraryManager.selectedBibleModule?.name) { _, newName in
            if rememberLastModule, let name = newName {
                defaultBibleModuleName = name
            }
        }
    }

    /// Draggable pane divider: a hairline with a fat invisible hit area. The
    /// drag hands the caller (valueAtDragStart, translation along the drag
    /// axis) — the caller owns clamping + AppStorage persistence. `dragAxis` =
    /// the direction the user DRAGS (.horizontal resizes the list chapters
    /// column, .vertical the grid books/chapters split).
    private func paneResizeDivider(
        _ dragAxis: Axis,
        onDrag: @escaping (Double, Double) -> Void,
        currentValue: @escaping () -> Double
    ) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: dragAxis == .horizontal ? 7 : nil,
                   height: dragAxis == .vertical ? 7 : nil)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: dragAxis == .horizontal ? 1 : nil,
                           height: dragAxis == .vertical ? 1 : nil)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                // While a drag runs, the pointer may leave the 7pt strip —
                // don't let hover-exit pop the resize cursor mid-drag.
                guard dragBase == nil else { return }
                if inside {
                    (dragAxis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                // GLOBAL coordinate space is load-bearing: the divider itself
                // moves while resizing, so a local-space translation is
                // measured against a moving origin — feedback loop, jitter.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        let base = dragBase ?? currentValue()
                        dragBase = base
                        onDrag(base, dragAxis == .horizontal ? v.translation.width : v.translation.height)
                    }
                    .onEnded { _ in dragBase = nil }
            )
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(String(localized: "No Bible Modules", comment: "Empty state title"))
                .font(.title2)

            Text(String(localized: "Import a Bible module to get started.\nSupported formats: TopPresenter JSON, OSIS XML, Zefania XML, MySword, USFM, Unbound Bible", comment: "Empty state message"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                showImportSheet = true
            } label: {
                Label(
                    String(localized: "Import Bible", comment: "Button"),
                    systemImage: "plus.circle.fill"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Shown when modules exist but none is selected — a single informational
    /// page (no empty Books/Chapters/Verses columns) that explains what this
    /// section does and lets the user pick a translation or import another.
    private var noModuleSelectedView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)

            Image(systemName: "books.vertical")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 7) {
                Text(String(localized: "Select a Bible Module", comment: "No-selection splash title"))
                    .font(.title2.weight(.semibold))
                Text(String(localized: "Pick a translation to browse its books, chapters and verses — then send any passage to the screen. You can switch translations anytime from the toolbar above.", comment: "No-selection splash message"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: 8) {
                Text(String(localized: "\(modules.count) translations available", comment: "No-selection splash subheader"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)

                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 110, maximum: 190), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(modules) { module in
                            Button {
                                libraryManager.selectModule(module)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(module.abbreviation.isEmpty ? module.name : module.abbreviation)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                    if !module.name.isEmpty, module.name != module.abbreviation {
                                        Text(module.name)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 8)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary.opacity(0.15)))
                            }
                            .buttonStyle(.plain)
                            .help(module.name)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }

            Button {
                showImportSheet = true
            } label: {
                Label(String(localized: "Import another module", comment: "Button"), systemImage: "square.and.arrow.down")
            }
            .controlSize(.large)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func deleteBibleModule(_ module: BibleModule) {
        if libraryManager.selectedBibleModule?.id == module.id {
            libraryManager.selectedBibleModule = nil
            libraryManager.selectedBook = nil
            libraryManager.selectedChapter = nil
            libraryManager.selectedVerses = []
        }
        searchIndex.moduleDeleted(module.id)
        modelContext.delete(module)
        try? modelContext.save()
    }
}

// MARK: - Shared book-tap behavior

/// Book tap for BOTH panes: re-tapping the current book keeps the chapter;
/// a NEW book opens instantly at chapter 1 — verses appear with one click.
func selectBookOpeningFirstChapter(_ book: BibleBook, in libraryManager: LibraryManager) {
    guard libraryManager.selectedBook?.id != book.id else { return }
    libraryManager.selectBook(book)
    if let first = book.sortedChapters.first {
        libraryManager.selectChapter(first)
    }
}

/// Projects ONE verse live with all its rich casete sources populated —
/// shared by the row (double-click/context menu) and the panel's Enter key.
func projectBibleVerse(_ verse: BibleVerse, libraryManager: LibraryManager,
                       presentationManager: PresentationManager) {
    let footnote = verse.footnotes
        .map { $0.marker.isEmpty ? $0.text : "\($0.marker) \($0.text)" }
        .joined(separator: "\n")
    let crossRef = verse.crossReferences
        .flatMap { ref in [ref.label].compactMap { $0 } + ref.targets }
        .joined(separator: "; ")
    let heading = (verse.chapter?.headings ?? [])
        .filter { $0.beforeVerse == verse.verseNumber }
        .map { $0.text }.joined(separator: "\n")
    let strongs = verse.runs.compactMap { $0.strong }.joined(separator: " ")
    presentationManager.showBibleVerse(
        text: verse.text,
        reference: verse.fullReference,
        translationName: libraryManager.selectedBibleModule?.abbreviation ?? "",
        runs: verse.runs,
        footnote: footnote, crossReference: crossRef, heading: heading,
        gloss: verse.gloss, strongs: strongs,
        bookNumber: verse.chapter?.book?.bookNumber ?? 0,
        bookName: verse.chapter?.book?.name ?? "",
        chapter: verse.chapter?.chapterNumber ?? 0,
        verseStart: verse.verseNumber, verseEnd: verse.verseNumber,
        translation: libraryManager.selectedBibleModule?.abbreviation ?? ""
    )
}

// MARK: - Books Grid Pane (left-top, grid mode)

/// Compact colored books grid — ALL books visible in the upper-left pane
/// (adaptive small cells), genre-tinted like the old grid but a third the size.
struct BibleBooksGridPane: View {
    @Environment(LibraryManager.self) private var libraryManager
    @AppStorage("showBookCategoryColors") private var showBookCategoryColors: Bool = true

    var body: some View {
        ScrollView {
            if let module = libraryManager.selectedBibleModule {
                let otBooks = module.books.filter { $0.bookNumber <= 39 }.sorted { $0.bookNumber < $1.bookNumber }
                let ntBooks = module.books.filter { $0.bookNumber >= 40 && $0.bookNumber <= 66 }.sorted { $0.bookNumber < $1.bookNumber }
                let dcBooks = module.books.filter { $0.bookNumber > 66 }.sorted { $0.bookNumber < $1.bookNumber }

                VStack(alignment: .leading, spacing: 10) {
                    if !otBooks.isEmpty {
                        gridSection(String(localized: "Old Testament", comment: "Section header"), otBooks)
                    }
                    if !ntBooks.isEmpty {
                        gridSection(String(localized: "New Testament", comment: "Section header"), ntBooks)
                    }
                    if !dcBooks.isEmpty {
                        gridSection(String(localized: "Deuterocanonical / Apocrypha", comment: "Section header"), dcBooks)
                    }
                }
                .padding(8)
            }
        }
    }

    private func gridSection(_ title: String, _ books: [BibleBook]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86), spacing: 4)], spacing: 4) {
                ForEach(books) { book in
                    bookCell(book)
                }
            }
        }
    }

    private func bookCell(_ book: BibleBook) -> some View {
        let category = BibleBookCategory.from(bookNumber: book.bookNumber)
        let isSelected = libraryManager.selectedBook?.id == book.id
        return Button {
            selectBookOpeningFirstChapter(book, in: libraryManager)
        } label: {
            Text(book.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .background(
                    isSelected
                        ? appAccent
                        : showBookCategoryColors ? category.color.opacity(0.26) : Color.gray.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help(book.name)
    }
}

// MARK: - Bible Navigation Panel (Books & Chapters)
struct BibleNavigationPanel: View {
    @Environment(LibraryManager.self) private var libraryManager
    @AppStorage("showBookCategoryColors") private var showBookCategoryColors: Bool = true
    @AppStorage("showBookCategoryLabels") private var showBookCategoryLabels: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            if let module = libraryManager.selectedBibleModule {
                // Split by canonical book number so deuterocanonical books
                // (67–83, e.g. BVB's Vulgata) are never hidden.
                let otBooks = module.books.filter { $0.bookNumber <= 39 }.sorted { $0.bookNumber < $1.bookNumber }
                let ntBooks = module.books.filter { $0.bookNumber >= 40 && $0.bookNumber <= 66 }.sorted { $0.bookNumber < $1.bookNumber }
                let dcBooks = module.books.filter { $0.bookNumber > 66 }.sorted { $0.bookNumber < $1.bookNumber }

                List(selection: Binding(
                    get: { libraryManager.selectedBook?.id },
                    set: { newID in
                        if let id = newID,
                           let book = module.books.first(where: { $0.id == id }) {
                            selectBookOpeningFirstChapter(book, in: libraryManager)
                        }
                    }
                )) {
                    if !otBooks.isEmpty {
                        Section(String(localized: "Old Testament", comment: "Section header")) {
                            ForEach(otBooks) { book in
                                bookRow(book)
                            }
                        }
                    }

                    if !ntBooks.isEmpty {
                        Section(String(localized: "New Testament", comment: "Section header")) {
                            ForEach(ntBooks) { book in
                                bookRow(book)
                            }
                        }
                    }

                    if !dcBooks.isEmpty {
                        Section(String(localized: "Deuterocanonical / Apocrypha", comment: "Section header")) {
                            ForEach(dcBooks) { book in
                                bookRow(book)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            } else {
                VStack {
                    Text(String(localized: "Select a module", comment: "Placeholder"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func bookRow(_ book: BibleBook) -> some View {
        let category = BibleBookCategory.from(bookNumber: book.bookNumber)
        return HStack(spacing: 8) {
            // Color indicator dot (conditional)
            if showBookCategoryColors {
                Circle()
                    .fill(category.color)
                    .frame(width: 10, height: 10)
            }
            Text(book.name)
                .lineLimit(1)
            Spacer()
            if showBookCategoryColors && showBookCategoryLabels {
                Text(category.localizedName)
                    .font(.system(size: 9))
                    .foregroundStyle(category.darkColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(category.color.opacity(0.2), in: Capsule())
            }
            Text("\(book.chapters.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .tag(book.id)
        .contentShape(Rectangle())
    }

}

// MARK: - Bible Chapters Panel (shared by list & grid modes)
struct BibleChaptersPanel: View {
    @Environment(LibraryManager.self) private var libraryManager

    /// nil = dense adaptive grid (grid mode's wide bottom pane); a number =
    /// exactly that many columns (list mode's narrow right column uses 2).
    var fixedColumns: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(libraryManager.selectedBook?.name ?? String(localized: "Chapters", comment: "Section title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if let book = libraryManager.selectedBook {
                    Text(String(localized: "\(book.chapters.count) capitole", comment: "Chapter count"))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()

            if let book = libraryManager.selectedBook {
                ScrollView {
                    // Wide pane (grid mode): adaptive dense grid so Psalmii's
                    // 150 chapters stay scannable. Narrow column (list mode):
                    // exactly `fixedColumns` (2) — buttons grow with the
                    // user-dragged column width.
                    LazyVGrid(columns: fixedColumns.map {
                        Array(repeating: GridItem(.flexible(), spacing: 4), count: $0)
                    } ?? [GridItem(.adaptive(minimum: 34), spacing: 4)], spacing: 4) {
                        ForEach(book.sortedChapters) { chapter in
                            let selected = libraryManager.selectedChapter?.id == chapter.id
                            Button {
                                libraryManager.selectChapter(chapter)
                            } label: {
                                Text("\(chapter.chapterNumber)")
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 28)
                                    .background(
                                        selected ? appAccent : Color.gray.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    )
                                    .foregroundStyle(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                }
            } else {
                Spacer()
                Text(String(localized: "Select a book", comment: "Placeholder"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
    }
}

// MARK: - Bible Content Panel (Verses / Search Results)
struct BibleContentPanel: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @AppStorage("bibleShowHeadings") private var showHeadings: Bool = true
    @AppStorage("bibleShowFootnotes") private var showFootnotes: Bool = false
    @AppStorage("bibleShowCrossRefs") private var showCrossRefs: Bool = false
    @AppStorage("bibleShowStrong") private var showStrong: Bool = false

    /// Keyboard flow: rows set this on click so ↑↓/←→/Enter work immediately.
    @FocusState private var versesFocused: Bool
    /// Keyboard-driven scroll anchor (result id) — clicks/hover never scroll.
    @State private var scrollTarget: UUID?

    var body: some View {
        VStack(spacing: 0) {
            if let chapter = libraryManager.selectedChapter {
                chapterVersesView(chapter: chapter)
            } else {
                VStack {
                    Image(systemName: "text.book.closed")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Select a book and chapter to view verses", comment: "Placeholder"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: Chapter stepping (‹ › buttons + ←→ keys)

    private func neighborChapter(_ delta: Int) -> BibleChapter? {
        guard let book = libraryManager.selectedBook,
              let current = libraryManager.selectedChapter else { return nil }
        let chapters = book.sortedChapters
        guard let idx = chapters.firstIndex(where: { $0.id == current.id }) else { return nil }
        let target = idx + delta
        guard chapters.indices.contains(target) else { return nil }
        return chapters[target]
    }

    private func stepChapter(_ delta: Int) {
        guard let chapter = neighborChapter(delta) else { return }
        libraryManager.selectChapter(chapter)
    }

    // MARK: Keyboard selection

    private func moveVerseSelection(_ delta: Int) -> KeyPress.Result {
        let verses = libraryManager.cachedSortedVerses
        guard !verses.isEmpty else { return .ignored }
        let anchorID = libraryManager.selectedVerses.last?.id
        let idx = verses.firstIndex(where: { $0.id == anchorID }) ?? -1
        let next = min(max(idx + delta, 0), verses.count - 1)
        libraryManager.selectVerse(verses[next])
        scrollTarget = verses[next].id
        return .handled
    }

    /// Enter — present the current selection (single verse rich, range joined).
    private func presentSelection() {
        let selection = libraryManager.selectedVerses
        guard !selection.isEmpty else { return }
        if selection.count == 1, let verse = selection.first {
            projectBibleVerse(verse, libraryManager: libraryManager,
                              presentationManager: presentationManager)
            return
        }
        let mv = presentationManager.bibleMultiVerse
        let numbers = selection.map(\.verseNumber).sorted()
        presentationManager.showBibleVerse(
            text: libraryManager.formattedSelectedVersesText(
                layout: mv.layout, showPrefix: mv.showNumbers,
                customEnabled: mv.customEnabled, customTemplate: mv.customText),
            reference: libraryManager.selectedVersesReference,
            translationName: libraryManager.selectedBibleModule?.abbreviation ?? "",
            runs: libraryManager.selectedVersesRuns,
            bookNumber: libraryManager.selectedBook?.bookNumber ?? 0,
            bookName: libraryManager.selectedBook?.name ?? "",
            chapter: libraryManager.selectedChapter?.chapterNumber ?? 0,
            verseStart: numbers.first ?? 0, verseEnd: numbers.last ?? 0,
            translation: libraryManager.selectedBibleModule?.abbreviation ?? "")
    }

    // MARK: Header pieces

    private func contentToggle(_ icon: String, _ help: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 24, height: 20)
                .background(
                    isOn.wrappedValue ? appAccent.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
                .foregroundStyle(isOn.wrappedValue ? appAccent : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder
    private func headingRow(_ h: BibleHeading) -> some View {
        Text(h.text)
            .font(h.level <= 1 ? .headline : .subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .listRowSeparator(.hidden)
    }

    private func chapterVersesView(chapter: BibleChapter) -> some View {
        VStack(spacing: 0) {
            // Header: ‹ › chapter stepper · title · content toggles · count.
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Button { stepChapter(-1) } label: { Image(systemName: "chevron.left") }
                        .disabled(neighborChapter(-1) == nil)
                        .help(String(localized: "Capitolul anterior (←)", comment: "Tooltip"))
                    Button { stepChapter(+1) } label: { Image(systemName: "chevron.right") }
                        .disabled(neighborChapter(+1) == nil)
                        .help(String(localized: "Capitolul următor (→)", comment: "Tooltip"))
                }
                .buttonStyle(.borderless)
                .controlSize(.small)

                if let book = libraryManager.selectedBook {
                    Text("\(book.name) \(chapter.chapterNumber)")
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 2) {
                    contentToggle("text.alignleft", String(localized: "Titluri de secțiune", comment: "Toggle tooltip"), isOn: $showHeadings)
                    contentToggle("note.text", String(localized: "Note de subsol", comment: "Toggle tooltip"), isOn: $showFootnotes)
                    contentToggle("link", String(localized: "Referințe încrucișate", comment: "Toggle tooltip"), isOn: $showCrossRefs)
                    contentToggle("number", String(localized: "Numere Strong", comment: "Toggle tooltip"), isOn: $showStrong)
                }
                Text(String(localized: "\(chapter.verses.count) verses", comment: "Verse count"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)

            Divider()

            // Verses list — section headings (pericopes) interleaved before
            // the verse they precede when the Titluri toggle is on.
            let verses = chapter.sortedVerses
            let allHeadings = showHeadings ? chapter.headings : []
            // A heading attaches to the FIRST verse whose number is ≥ its
            // beforeVerse (robust to versification gaps) — mapped once here,
            // not filtered per row.
            let headingsByVerse: [UUID: [BibleHeading]] = {
                guard !allHeadings.isEmpty else { return [:] }
                var map: [UUID: [BibleHeading]] = [:]
                for h in allHeadings.sorted(by: { $0.beforeVerse < $1.beforeVerse }) {
                    guard let v = verses.first(where: { $0.verseNumber >= h.beforeVerse }) else { continue }
                    map[v.id, default: []].append(h)
                }
                return map
            }()
            ScrollViewReader { proxy in
                List {
                    ForEach(verses, id: \.id) { verse in
                        if let attached = headingsByVerse[verse.id] {
                            ForEach(Array(attached.enumerated()), id: \.offset) { _, h in
                                headingRow(h)
                            }
                        }
                        BibleVerseRow(verse: verse, onSelect: { versesFocused = true })
                            .id(verse.id)
                    }
                    // Headings positioned past the last verse.
                    if showHeadings, let last = verses.last {
                        ForEach(Array(allHeadings.filter { $0.beforeVerse > last.verseNumber }.enumerated()), id: \.offset) { _, h in
                            headingRow(h)
                        }
                    }
                }
                .listStyle(.plain)
                .onChange(of: scrollTarget) { _, target in
                    if let target { proxy.scrollTo(target, anchor: nil) }
                }
            }
            // Keyboard flow (click a verse to arm it): ↑↓ move the selection,
            // ←→ step chapters, Enter presents. The ⌘K overlay owns the keys
            // while open (its TextField has focus), so no clash.
            .focusable()
            .focused($versesFocused)
            .focusEffectDisabled()
            .onKeyPress(.upArrow) { moveVerseSelection(-1) }
            .onKeyPress(.downArrow) { moveVerseSelection(+1) }
            .onKeyPress(.leftArrow) { stepChapter(-1); return .handled }
            .onKeyPress(.rightArrow) { stepChapter(+1); return .handled }
            .onKeyPress(.return) { presentSelection(); return .handled }
        }
    }
}

// MARK: - Decoded runs cache

/// `BibleVerse.runs` JSON-decodes on EVERY access — far too heavy to run per
/// list-row render (a selection change re-renders every row in the chapter).
/// Decode once per verse per session; re-imports mint new verse UUIDs, so
/// entries can't go stale.
@MainActor
final class VerseRunsCache {
    static let shared = VerseRunsCache()
    private var cache: [UUID: [VerseRun]] = [:]

    func runs(for verse: BibleVerse) -> [VerseRun] {
        if let hit = cache[verse.id] { return hit }
        if cache.count > 4096 { cache.removeAll(keepingCapacity: true) }
        let decoded = verse.runs
        cache[verse.id] = decoded
        return decoded
    }
}

// MARK: - Bible Verse Row
struct BibleVerseRow: View {
    let verse: BibleVerse
    /// Fired on single click — the content panel uses it to arm keyboard flow.
    var onSelect: () -> Void = {}

    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager

    @AppStorage("bibleShowFootnotes") private var showFootnotes: Bool = false
    @AppStorage("bibleShowCrossRefs") private var showCrossRefs: Bool = false
    @AppStorage("bibleShowStrong") private var showStrong: Bool = false

    private var isSelected: Bool {
        libraryManager.selectedVerseIDs.contains(verse.id)
    }

    /// Verse text with words-of-Christ colored (red-letter) — only when the runs
    /// reconstruct the text exactly, otherwise plain.
    private var verseText: Text {
        let runs = VerseRunsCache.shared.runs(for: verse)
        guard !runs.isEmpty, runs.contains(where: { $0.kind == "woc" }) else {
            return Text(verse.text)
        }
        return runs.reduce(Text("")) { acc, run in
            acc + (run.kind == "woc"
                ? Text(run.text).foregroundColor(presentationManager.wocColor)
                : Text(run.text))
        }
    }

    private var strongList: String {
        VerseRunsCache.shared.runs(for: verse).compactMap { $0.strong }.joined(separator: " ")
    }

    /// Best-effort jump to a cross-reference like "Ioan 3:16" / "1 In 4:9".
    private func jump(to ref: String) {
        guard let module = libraryManager.selectedBibleModule else { return }
        let segs = ref.split(separator: ":", maxSplits: 1)
        let left = segs.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        let tokens = left.split(separator: " ")
        guard tokens.count >= 2, let chap = Int(tokens.last!) else { return }
        let name = tokens.dropLast().joined(separator: " ")
        let verseNum = segs.count > 1 ? Int(segs[1].prefix(while: { $0.isNumber })) : nil
        let lname = name.lowercased()
        var book: BibleBook?
        // Deuterocanon refs arrive as "Book 67 3:16" (no abbrev) → match by number.
        if lname.hasPrefix("book "), let num = Int(name.dropFirst(5).trimmingCharacters(in: .whitespaces)) {
            book = module.books.first { $0.bookNumber == num }
        }
        if book == nil {
            book = module.books.first {
                $0.abbreviation.lowercased() == lname
                    || $0.name.lowercased() == lname
                    || $0.name.lowercased().hasPrefix(lname)
            }
        }
        guard let book, let chapter = book.sortedChapters.first(where: { $0.chapterNumber == chap }) else { return }
        libraryManager.selectBook(book)
        libraryManager.selectChapter(chapter)
        if let vn = verseNum, let v = chapter.sortedVerses.first(where: { $0.verseNumber == vn }) {
            libraryManager.selectVerse(v)
        }
    }

    /// Projects this verse live with all its rich casete sources populated.
    private func projectVerse() {
        projectBibleVerse(verse, libraryManager: libraryManager,
                          presentationManager: presentationManager)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(verse.verseNumber)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(appAccent)
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 5) {
                verseText
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showStrong, !strongList.isEmpty {
                    Text(strongList)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                if showFootnotes {
                    ForEach(Array(verse.footnotes.enumerated()), id: \.offset) { _, fn in
                        Label(fn.marker.isEmpty ? fn.text : "\(fn.marker) \(fn.text)", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                    }
                }
                if showCrossRefs, !verse.crossReferences.isEmpty {
                    let targets = verse.crossReferences.flatMap { $0.targets }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            Image(systemName: "link").font(.caption2).foregroundStyle(.secondary)
                            ForEach(Array(targets.enumerated()), id: \.offset) { _, ref in
                                Button { jump(to: ref) } label: {
                                    Text(ref)
                                        .font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(appAccent.opacity(0.12), in: Capsule())
                                        .foregroundStyle(appAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected ? appAccent.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        // simultaneousGesture, NOT a second onTapGesture: stacked single+double
        // tap gestures make AppKit wait the double-click interval before
        // delivering the single click — selection felt laggy. This way the
        // single tap selects INSTANTLY; a double-click selects then projects.
        .gesture(TapGesture(count: 2).onEnded {
            projectVerse()   // double-click sends to presentation
        })
        .simultaneousGesture(TapGesture().onEnded {
            if NSEvent.modifierFlags.contains(.command) {
                libraryManager.toggleVerseSelection(verse)
            } else {
                libraryManager.selectVerse(verse)
            }
            onSelect()
        })
        .contextMenu {
            Button(String(localized: "Show on Screen", comment: "Context menu")) {
                projectVerse()
            }
            AddToSessionMenu(draft: sessionDraft)
            Divider()
            Button(String(localized: "Copy Text", comment: "Context menu")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(verse.text, forType: .string)
            }
            Button(String(localized: "Copy Reference", comment: "Context menu")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(verse.fullReference, forType: .string)
            }
        }
    }

    /// Session draft for this row: the WHOLE current selection when the row is
    /// part of it (multi-verse range), else just this verse.
    private func sessionDraft() -> SessionItemDraft? {
        guard let module = libraryManager.selectedBibleModule,
              let book = libraryManager.selectedBook,
              let chapter = libraryManager.selectedChapter else { return nil }
        let selection = libraryManager.selectedVerses
        let inSelection = selection.contains { $0.id == verse.id }
        let verses = (inSelection && !selection.isEmpty) ? selection : [verse]
        let numbers = verses.map(\.verseNumber).sorted()
        guard let first = numbers.first, let last = numbers.last else { return nil }
        let range = first == last ? "\(first)" : "\(first)-\(last)"
        let reference = "\(book.name) \(chapter.chapterNumber):\(range)"
        let text = verses.sorted { $0.verseNumber < $1.verseNumber }.map(\.text).joined(separator: " ")
        return .bible(translation: module.abbreviation, bookNumber: book.bookNumber,
                      bookName: book.name, chapter: chapter.chapterNumber,
                      verseStart: first, verseEnd: last,
                      displayReference: reference, snapshotText: text)
    }
}

// MARK: - Bible Import Sheet
struct BibleImportSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(LibraryManager.self) private var libraryManager

    @Binding var isImporting: Bool
    @Binding var importProgress: Double
    @Binding var importStatusText: String

    @State private var selectedFormat: SupportedBibleFormat?
    @State private var selectedFileURL: URL?
    @State private var autoDetected = false
    @State private var isDropTargeted = false
    /// True while a picked folder/tree is being scanned on a background task.
    @State private var isScanning = false
    /// Duplicate-on-import: set when a same-code module already exists.
    @State private var pendingConflict: ImportService.BibleConflict?

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text(String(localized: "Import Bible", comment: "Sheet title"))
                    .font(.title2.bold())
                Text(String(localized: "Drop files or folders, or click to browse. Folders (and subfolders) are scanned — every Bible and song inside is imported.", comment: "Import subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Drag-and-drop zone (click to browse). Handles single files,
            // multi-selections, and whole folders (recursively).
            Button { browse() } label: {
                VStack(spacing: 10) {
                    Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "square.and.arrow.down")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(isDropTargeted ? appAccent : .secondary)
                    if let url = selectedFileURL {
                        HStack(spacing: 6) {
                            Image(systemName: fileIcon).foregroundStyle(appAccent)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle).fontWeight(.medium)
                        }
                        Text(String(localized: "Click Import below, or drop another to replace.", comment: "Drop hint"))
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(String(localized: "Drop Bible files or folders here", comment: "Drop zone title"))
                            .font(.callout.weight(.medium))
                        Text(String(localized: "or click to browse", comment: "Drop zone subtitle"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 156)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isDropTargeted ? appAccent.opacity(0.08) : Color.secondary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isDropTargeted ? appAccent : Color.secondary.opacity(0.35),
                                  style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
            }
            .buttonStyle(.plain)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                loadDroppedURLs(providers)
                return true
            }

            // Detected format display
            if let format = selectedFormat {
                HStack(spacing: 8) {
                    Image(systemName: autoDetected ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(autoDetected ? .green : .blue)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(String(localized: "Format:", comment: "Label"))
                                .fontWeight(.medium)
                            Text(format.displayName)
                                .foregroundStyle(appAccent)
                                .fontWeight(.semibold)
                            if autoDetected {
                                Text(String(localized: "(auto-detected)", comment: "Label"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(format.formatDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            // Manual format override
            if selectedFileURL != nil {
                DisclosureGroup(String(localized: "Override format manually", comment: "Disclosure label")) {
                    Picker(String(localized: "Format:", comment: "Picker label"), selection: Binding(
                        get: { selectedFormat ?? .osisXML },
                        set: { newValue in
                            selectedFormat = newValue
                            autoDetected = false
                        }
                    )) {
                        ForEach(SupportedBibleFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Supported formats — compact line.
            if selectedFileURL == nil {
                VStack(spacing: 5) {
                    Text(String(localized: "Supported formats", comment: "Section header"))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                    Text(SupportedBibleFormat.allCases.map { $0.displayName }.joined(separator: "  ·  "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }

            // Import progress
            if isImporting {
                VStack(spacing: 8) {
                    ProgressView(value: importProgress) {
                        Text(importStatusText)
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

                Spacer()

                Button(String(localized: "Import", comment: "Button")) {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedFileURL == nil || selectedFormat == nil || isImporting)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
        .overlay {
            if isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text(String(localized: "Scanning for Bible & song files…", comment: "Import scanning"))
                        .font(.callout.weight(.medium))
                    Text(String(localized: "Only supported file types are read.", comment: "Import scanning detail"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ultraThinMaterial)
            }
        }
        .confirmationDialog(
            pendingConflict.map {
                String(localized: "„\($0.code)” există deja (\($0.existingName), \($0.existingVerses) versete). Noul fișier are \($0.incomingVerses) versete.", comment: "Duplicate import dialog")
            } ?? "",
            isPresented: Binding(get: { pendingConflict != nil }, set: { if !$0 { pendingConflict = nil } }),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Combină (completează ce lipsește)", comment: "Conflict action")) {
                runImport(resolution: .merge)
            }
            Button(String(localized: "Înlocuiește complet", comment: "Conflict action"), role: .destructive) {
                runImport(resolution: .replace)
            }
            Button(String(localized: "Păstrează ambele", comment: "Conflict action")) {
                runImport(resolution: .keepBoth)
            }
            Button(String(localized: "Anulează", comment: "Conflict action"), role: .cancel) {
                pendingConflict = nil
            }
        }
    }

    private var fileIcon: String {
        guard let format = selectedFormat else { return "doc" }
        switch format {
        case .topPresenter: return "doc.text.fill"
        case .mySword: return "cylinder"
        case .usfm: return "folder"
        case .osisXML, .zefaniaXML: return "doc.text"
        case .unboundBible: return "tablecells"
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        // No type restriction — any file is selectable; the selected
        // format decides how it's parsed.
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = String(localized: "Select Bible file(s) to import", comment: "Open panel message")
        panel.prompt = String(localized: "Select", comment: "Open panel button")

        if panel.runModal() == .OK {
            let urls = panel.urls
            if urls.count == 1, let url = urls.first {
                selectedFileURL = url
                // Auto-detect format
                if let detected = ImportService.detectBibleFormat(fileURL: url) {
                    selectedFormat = detected
                    autoDetected = true
                } else {
                    selectedFormat = guessFormatFromExtension(url)
                    autoDetected = selectedFormat != nil
                }
            } else if urls.count > 1 {
                // Multiple files → open batch import instead
                dismiss()
                let classified = DragDropImportHandler.classify(urls)
                NotificationCenter.default.post(
                    name: .batchImportFiles,
                    object: nil,
                    userInfo: ["files": classified]
                )
            }
        }
    }

    /// Batch import: pick any mix of files AND folders (multi-select). Folders are
    /// scanned recursively — a folder of `.json` Bibles (or a tree of language
    /// subfolders) imports each one; a per-book USFM folder imports as one Bible.
    private func chooseBatch() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.message = String(localized: "Select Bible files and/or folders — subfolders are scanned automatically", comment: "Open panel message")
        panel.prompt = String(localized: "Import", comment: "Open panel button")

        guard panel.runModal() == .OK else { return }
        let pending = DragDropImportHandler.classifyExpanded(panel.urls)
        guard !pending.isEmpty else {
            appState.showError(
                String(localized: "Nothing to import", comment: "Alert title"),
                message: String(localized: "No recognizable Bible files were found in the selection.", comment: "Alert message")
            )
            return
        }
        dismiss()
        NotificationCenter.default.post(
            name: .batchImportFiles,
            object: nil,
            userInfo: ["files": pending]
        )
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Select a folder containing USFM Bible files", comment: "Open panel message")
        panel.prompt = String(localized: "Select Folder", comment: "Open panel button")

        if panel.runModal() == .OK, let url = panel.url {
            selectedFileURL = url
            // Auto-detect — for directories, check for USFM files
            if let detected = ImportService.detectBibleFormat(fileURL: url) {
                selectedFormat = detected
                autoDetected = true
            } else {
                selectedFormat = .usfm
                autoDetected = false
            }
        }
    }

    private func guessFormatFromExtension(_ url: URL) -> SupportedBibleFormat? {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        if ext == "json" { return .topPresenter }
        if name.contains(".bbl.mybible") || ext == "mybible" { return .mySword }
        if ext == "usfm" || ext == "sfm" { return .usfm }
        if ext == "osis" { return .osisXML }
        if ext == "zef" { return .zefaniaXML }
        // For .xml and .txt, we can't be sure without content inspection
        return nil
    }

    /// Open a panel to pick any mix of files and folders, then route them.
    private func browse() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        // Only supported file types are selectable; folders stay pickable.
        panel.allowedContentTypes = DragDropImportHandler.bibleSongContentTypes
        panel.message = String(localized: "Select Bible files and/or folders — subfolders are scanned automatically", comment: "Open panel message")
        panel.prompt = String(localized: "Open", comment: "Open panel button")
        guard panel.runModal() == .OK else { return }
        handleSelectedURLs(panel.urls)
    }

    /// Load dropped file URLs asynchronously, then route them.
    private func loadDroppedURLs(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        // Provider callbacks arrive on arbitrary threads — collect behind a lock.
        let collected = OSAllocatedUnfairLock(initialState: [URL]())
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.withLock { $0.append(url) } }
                group.leave()
            }
        }
        group.notify(queue: .main) { handleSelectedURLs(collected.withLock { $0 }) }
    }

    /// One file → inline single-import flow (detect/override format). Multiple
    /// files or any folder → expand recursively and hand off to batch import.
    ///
    /// The recursive scan runs on a background task: a Documents-sized tree would
    /// otherwise block the main thread (the spinning-rainbow beach ball) while it
    /// walks thousands of entries. The extension filter in `expandToImportableFiles`
    /// means we never open unrelated files (drone footage, archives, …).
    private func handleSelectedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isScanning = true
        Task {
            // The recursive walk + per-file classification run off the main actor
            // (Task.detached) so the UI stays live; only the small Sendable results
            // come back to the main actor below.
            let expanded = await Task.detached(priority: .userInitiated) {
                DragDropImportHandler.expandToImportableFiles(urls)
            }.value

            // A single Bible file → inline single-import flow (with format override).
            if expanded.count == 1, let url = expanded.first,
               case .bible = DragDropImportHandler.classify(url) {
                isScanning = false
                selectedFileURL = url
                if let detected = ImportService.detectBibleFormat(fileURL: url) {
                    selectedFormat = detected; autoDetected = true
                } else {
                    selectedFormat = guessFormatFromExtension(url); autoDetected = selectedFormat != nil
                }
                return
            }

            // Anything else — multiple files, folders, or a folder/tree that mixes
            // Bibles with songs (and media) — goes to batch import, which imports
            // each file by its detected kind.
            let pending = await Task.detached(priority: .userInitiated) {
                DragDropImportHandler.classify(expanded).filter {
                    if case .unknown = $0.category { return false }
                    return true
                }
            }.value

            isScanning = false
            guard !pending.isEmpty else {
                appState.showError(
                    String(localized: "Nothing to import", comment: "Alert title"),
                    message: String(localized: "No recognizable Bible or song files were found in the selection.", comment: "Alert message"))
                return
            }
            dismiss()
            NotificationCenter.default.post(name: .batchImportFiles, object: nil, userInfo: ["files": pending])
        }
    }

    /// First attempt uses `.ask` — if a same-code module exists it surfaces the
    /// conflict dialog; otherwise it imports straight away.
    private func performImport() {
        runImport(resolution: .ask)
    }

    private func runImport(resolution: ImportService.BibleConflictResolution) {
        guard let fileURL = selectedFileURL, let format = selectedFormat else { return }
        pendingConflict = nil
        isImporting = true
        importProgress = 0
        importStatusText = String(localized: "Starting import...", comment: "Import progress")

        Task {
            do {
                let module = try await ImportService.importBible(
                    fileURL: fileURL,
                    format: format,
                    modelContext: modelContext,
                    resolution: resolution
                ) { progress, status in
                    Task { @MainActor in
                        importProgress = progress
                        importStatusText = status
                    }
                }

                await MainActor.run {
                    libraryManager.selectModule(module)
                    isImporting = false
                    appState.showSuccess(
                        String(localized: "Import Successful", comment: "Alert title"),
                        message: String(localized: "Successfully imported \"\(module.name)\" with \(module.books.count) books.", comment: "Alert message")
                    )
                    dismiss()
                }
            } catch let conflict as ImportService.BibleConflict {
                // Same-code module exists → ask the operator what to do.
                await MainActor.run {
                    isImporting = false
                    pendingConflict = conflict
                }
            } catch is ImportService.BibleImportCancelled {
                await MainActor.run { isImporting = false }
            } catch {
                await MainActor.run {
                    isImporting = false
                    appState.showError(
                        String(localized: "Import Failed", comment: "Alert title"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }
}
