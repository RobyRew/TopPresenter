//
//  BibleView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Main Bible view with module selection, book/chapter navigation, search, and verse display.
struct BibleView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AppState.self) private var appState

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

    // Reading-pane content toggles (shared with BibleVerseRow via @AppStorage).
    @AppStorage("bibleShowHeadings") private var showHeadings: Bool = true
    @AppStorage("bibleShowFootnotes") private var showFootnotes: Bool = false
    @AppStorage("bibleShowCrossRefs") private var showCrossRefs: Bool = false
    @AppStorage("bibleShowStrong") private var showStrong: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if modules.isEmpty {
                emptyStateView
            } else if libraryManager.selectedBibleModule == nil {
                noModuleSelectedView
            } else if viewMode == "grid" {
                // Grid navigation: Books → Chapters → Verses as button grids
                BibleGridNavigationView()
            } else {
                // Three columns — Books │ Chapters │ Verses — under a toggle bar.
                bibleToggleBar
                Divider()
                HSplitView {
                    BibleNavigationPanel()
                        .frame(minWidth: 150, idealWidth: 190, maxWidth: 240)
                    BibleChaptersPanel()
                        .frame(minWidth: 80, idealWidth: 110, maxWidth: 160)
                    BibleContentPanel()
                        .frame(minWidth: 340)
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

    /// Toolbar above the three columns — module label + reading-content toggles.
    private var bibleToggleBar: some View {
        HStack(spacing: 10) {
            if let m = libraryManager.selectedBibleModule {
                Label(m.abbreviation.isEmpty ? m.name : m.abbreviation, systemImage: "book.closed")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            toggleChip(String(localized: "Titluri", comment: "Toggle"), "text.alignleft", isOn: $showHeadings)
            toggleChip(String(localized: "Note", comment: "Toggle"), "note.text", isOn: $showFootnotes)
            toggleChip(String(localized: "Referințe", comment: "Toggle"), "link", isOn: $showCrossRefs)
            toggleChip(String(localized: "Strong", comment: "Toggle"), "number", isOn: $showStrong)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func toggleChip(_ title: String, _ icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            Label(title, systemImage: icon)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    isOn.wrappedValue ? Color.accentColor.opacity(0.16) : Color.clear,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isOn.wrappedValue ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.3),
                        lineWidth: 1
                    )
                )
                .foregroundStyle(isOn.wrappedValue ? Color.accentColor : Color.secondary)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Afișează/ascunde în panoul de versete", comment: "Toggle tooltip"))
    }

    private func deleteBibleModule(_ module: BibleModule) {
        if libraryManager.selectedBibleModule?.id == module.id {
            libraryManager.selectedBibleModule = nil
            libraryManager.selectedBook = nil
            libraryManager.selectedChapter = nil
            libraryManager.selectedVerses = []
        }
        modelContext.delete(module)
        try? modelContext.save()
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
                            libraryManager.selectBook(book)
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

// MARK: - Bible Chapters Panel (middle column)
struct BibleChaptersPanel: View {
    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(libraryManager.selectedBook?.name ?? String(localized: "Chapters", comment: "Section title"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            Divider()

            if let book = libraryManager.selectedBook {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2), spacing: 6) {
                        ForEach(book.sortedChapters) { chapter in
                            let selected = libraryManager.selectedChapter?.id == chapter.id
                            Button {
                                libraryManager.selectChapter(chapter)
                            } label: {
                                Text("\(chapter.chapterNumber)")
                                    .font(.system(.callout, design: .rounded).weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(
                                        selected ? Color.accentColor : Color.gray.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 6)
                                    )
                                    .foregroundStyle(selected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
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

    var body: some View {
        VStack(spacing: 0) {
            // Show search results or chapter verses
            if !libraryManager.bibleSearchResults.isEmpty {
                searchResultsView
            } else if let chapter = libraryManager.selectedChapter {
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

    private var searchResultsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "\(libraryManager.bibleSearchResults.count) results", comment: "Search results count"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Clear Search", comment: "Button")) {
                    libraryManager.bibleSearchQuery = ""
                    libraryManager.bibleSearchResults = []
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)

            Divider()

            List(libraryManager.bibleSearchResults) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.reference)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                    Text(result.text)
                        .font(.body)
                        .lineLimit(3)
                }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    presentationManager.showBibleVerse(
                        text: result.text,
                        reference: result.reference,
                        translationName: libraryManager.selectedBibleModule?.abbreviation ?? ""
                    )
                }
                .onTapGesture {
                    presentationManager.showBibleVerse(
                        text: result.text,
                        reference: result.reference,
                        translationName: libraryManager.selectedBibleModule?.abbreviation ?? ""
                    )
                }
            }
        }
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
            // Header
            HStack {
                if let book = libraryManager.selectedBook {
                    Text("\(book.name) \(chapter.chapterNumber)")
                        .font(.headline)
                }
                Spacer()
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
            let allHeadings = chapter.headings
            List {
                ForEach(Array(verses.enumerated()), id: \.element.id) { idx, verse in
                    if showHeadings {
                        // A heading attaches to the first verse whose number is
                        // ≥ its beforeVerse (robust to versification gaps).
                        let prev = idx > 0 ? verses[idx - 1].verseNumber : Int.min
                        ForEach(Array(allHeadings.filter { $0.beforeVerse > prev && $0.beforeVerse <= verse.verseNumber }.enumerated()), id: \.offset) { _, h in
                            headingRow(h)
                        }
                    }
                    BibleVerseRow(verse: verse)
                }
                // Headings positioned past the last verse.
                if showHeadings, let last = verses.last {
                    ForEach(Array(allHeadings.filter { $0.beforeVerse > last.verseNumber }.enumerated()), id: \.offset) { _, h in
                        headingRow(h)
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - Bible Verse Row
struct BibleVerseRow: View {
    let verse: BibleVerse

    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager

    @AppStorage("bibleShowFootnotes") private var showFootnotes: Bool = false
    @AppStorage("bibleShowCrossRefs") private var showCrossRefs: Bool = false
    @AppStorage("bibleShowStrong") private var showStrong: Bool = false

    private var isSelected: Bool {
        libraryManager.selectedVerses.contains { $0.id == verse.id }
    }

    /// Verse text with words-of-Christ colored (red-letter) — only when the runs
    /// reconstruct the text exactly, otherwise plain.
    private var verseText: Text {
        let runs = verse.runs
        guard !runs.isEmpty, runs.contains(where: { $0.kind == "woc" }) else {
            return Text(verse.text)
        }
        return runs.reduce(Text("")) { acc, run in
            acc + (run.kind == "woc"
                ? Text(run.text).foregroundColor(presentationManager.wocColor)
                : Text(run.text))
        }
    }

    private var strongList: String { verse.runs.compactMap { $0.strong }.joined(separator: " ") }

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

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(verse.verseNumber)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.accentColor)
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
                                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                                        .foregroundStyle(Color.accentColor)
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
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            projectVerse()   // double-click sends to presentation
        }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                libraryManager.toggleVerseSelection(verse)
            } else {
                libraryManager.selectVerse(verse)
            }
        }
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

// MARK: - Bible Grid Navigation View (BibleShow-style)
/// A full-panel grid view: Books → Chapters → Verses shown as tappable button grids
/// with breadcrumb navigation to go back.
struct BibleGridNavigationView: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @AppStorage("showBookCategoryColors") private var showBookCategoryColors: Bool = true
    @AppStorage("showBookCategoryLabels") private var showBookCategoryLabels: Bool = true

    /// Grid navigation level
    enum GridLevel {
        case books
        case chapters
        case verses
    }

    @State private var level: GridLevel = .books

    var body: some View {
        VStack(spacing: 0) {
            // Breadcrumb bar
            breadcrumbBar
            Divider()

            // Grid content
            switch level {
            case .books:
                booksGrid
            case .chapters:
                chaptersGrid
            case .verses:
                versesGrid
            }
        }
        .onChange(of: libraryManager.selectedBibleModule) { _, _ in
            level = .books
        }
    }

    // MARK: - Breadcrumb Bar
    private var breadcrumbBar: some View {
        HStack(spacing: 4) {
            // Module/Books level
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    level = .books
                    libraryManager.selectedBook = nil
                    libraryManager.selectedChapter = nil
                    libraryManager.selectedVerses = []
                    libraryManager.isAutoFillActive = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "book.fill")
                        .font(.caption2)
                    Text(libraryManager.selectedBibleModule?.abbreviation ?? String(localized: "Books", comment: "Breadcrumb"))
                        .fontWeight(level == .books ? .bold : .regular)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(level == .books ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(level == .books ? Color.accentColor : .primary)

            if let book = libraryManager.selectedBook {
                let bookCategory = BibleBookCategory.from(bookNumber: book.bookNumber)

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                // Chapter level
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        level = .chapters
                        libraryManager.selectedChapter = nil
                        libraryManager.selectedVerses = []
                        libraryManager.isAutoFillActive = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if showBookCategoryColors {
                            Circle().fill(bookCategory.color).frame(width: 8, height: 8)
                        }
                        Text(book.name)
                            .fontWeight(level == .chapters ? .bold : .regular)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        level == .chapters
                            ? (showBookCategoryColors ? bookCategory.color.opacity(0.15) : Color.accentColor.opacity(0.15))
                            : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
                .foregroundStyle(level == .chapters ? bookCategory.darkColor : .primary)

                if let chapter = libraryManager.selectedChapter {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    // Verse level
                    Text("\(String(localized: "Chapter", comment: "Breadcrumb")) \(chapter.chapterNumber)")
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                }
            }

            Spacer()

            // Verse count when viewing verses
            if level == .verses, let chapter = libraryManager.selectedChapter {
                Text(String(localized: "\(chapter.verses.count) verses", comment: "Verse count"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Books Grid
    private var booksGrid: some View {
        ScrollView {
            if let module = libraryManager.selectedBibleModule {
                let otBooks = module.books.filter { $0.testament == "OT" }.sorted { $0.bookNumber < $1.bookNumber }
                let ntBooks = module.books.filter { $0.testament == "NT" }.sorted { $0.bookNumber < $1.bookNumber }

                VStack(alignment: .leading, spacing: 16) {
                    if !otBooks.isEmpty {
                        bookSection(
                            title: String(localized: "Old Testament", comment: "Section header"),
                            books: otBooks
                        )
                    }
                    if !ntBooks.isEmpty {
                        bookSection(
                            title: String(localized: "New Testament", comment: "Section header"),
                            books: ntBooks
                        )
                    }
                }
                .padding(12)
            }
        }
    }

    private func bookSection(title: String, books: [BibleBook]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.leading, 4)

            // Category legend (conditional)
            if showBookCategoryColors && showBookCategoryLabels {
                let categories = Set(books.map { BibleBookCategory.from(bookNumber: $0.bookNumber) })
                HStack(spacing: 8) {
                    ForEach(Array(categories).sorted(by: { $0.localizedName < $1.localizedName }), id: \.self) { cat in
                        HStack(spacing: 3) {
                            Circle().fill(cat.color).frame(width: 8, height: 8)
                            Text(cat.localizedName)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 4)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
                ForEach(books) { book in
                    let category = BibleBookCategory.from(bookNumber: book.bookNumber)
                    let isSelected = libraryManager.selectedBook?.id == book.id
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            libraryManager.selectBook(book)
                            level = .chapters
                        }
                    } label: {
                        Text(book.name)
                            .font(.system(.callout, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                isSelected
                                    ? Color.accentColor
                                    : showBookCategoryColors ? category.color.opacity(0.3) : Color.gray.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 8)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        showBookCategoryColors ? category.color.opacity(0.6) : Color.gray.opacity(0.2),
                                        lineWidth: 1
                                    )
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Chapters Grid
    private var chaptersGrid: some View {
        ScrollView {
            if let book = libraryManager.selectedBook {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "Select a chapter from \(book.name)", comment: "Grid instruction"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 8), spacing: 6) {
                        ForEach(book.sortedChapters) { chapter in
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    libraryManager.selectChapter(chapter)
                                    level = .verses
                                }
                            } label: {
                                Text("\(chapter.chapterNumber)")
                                    .font(.system(.title3, design: .rounded, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        libraryManager.selectedChapter?.id == chapter.id
                                            ? Color.accentColor
                                            : Color.gray.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .foregroundStyle(
                                        libraryManager.selectedChapter?.id == chapter.id ? .white : .primary
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
            }
        }
    }

    // MARK: - Verses Grid
    private var versesGrid: some View {
        VStack(spacing: 0) {
            if let chapter = libraryManager.selectedChapter {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                        ForEach(chapter.sortedVerses) { verse in
                            let isSelected = libraryManager.selectedVerses.contains { $0.id == verse.id }

                            Button {
                                if NSEvent.modifierFlags.contains(.command) {
                                    libraryManager.toggleVerseSelection(verse)
                                } else {
                                    libraryManager.selectVerse(verse)
                                }
                            } label: {
                                Text("\(verse.verseNumber)")
                                    .font(.system(.body, design: .rounded, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        isSelected
                                            ? Color.accentColor
                                            : Color.gray.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: 8)
                                    )
                                    .foregroundStyle(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                            .help(verse.text.prefix(120) + (verse.text.count > 120 ? "…" : ""))
                            .contextMenu {
                                Button(String(localized: "Show on Screen", comment: "Context menu")) {
                                    presentationManager.showBibleVerse(
                                        text: verse.text,
                                        reference: verse.fullReference,
                                        translationName: libraryManager.selectedBibleModule?.abbreviation ?? "",
                                        runs: verse.runs,
                                        bookNumber: verse.chapter?.book?.bookNumber ?? 0,
                                        bookName: verse.chapter?.book?.name ?? "",
                                        chapter: verse.chapter?.chapterNumber ?? 0,
                                        verseStart: verse.verseNumber, verseEnd: verse.verseNumber,
                                        translation: libraryManager.selectedBibleModule?.abbreviation ?? ""
                                    )
                                }
                                Button(String(localized: "Copy Text", comment: "Context menu")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(verse.text, forType: .string)
                                }
                            }
                        }
                    }
                    .padding(12)
                }

                // Selected verse preview at the bottom
                if !libraryManager.selectedVerses.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(libraryManager.selectedVersesReference)
                                .font(.subheadline.bold())
                                .foregroundStyle(Color.accentColor)
                            Spacer()
                            Text(String(localized: "\(libraryManager.selectedVerses.count) selected", comment: "Selection count"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ScrollView {
                            Text({
                                let mv = presentationManager.bibleMultiVerse
                                return libraryManager.formattedSelectedVersesText(
                                    layout: mv.layout, showPrefix: mv.showNumbers,
                                    customEnabled: mv.customEnabled, customTemplate: mv.customText
                                )
                            }())
                            .font(.body)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                    .padding(12)
                    .background(.quaternary.opacity(0.3))
                }
            }
        }
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
                        .foregroundStyle(isDropTargeted ? Color.accentColor : .secondary)
                    if let url = selectedFileURL {
                        HStack(spacing: 6) {
                            Image(systemName: fileIcon).foregroundStyle(Color.accentColor)
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
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
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
                                .foregroundStyle(Color.accentColor)
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
        let lock = NSLock()
        var urls: [URL] = []
        for p in providers where p.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { handleSelectedURLs(urls) }
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
