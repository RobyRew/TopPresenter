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

    var body: some View {
        VStack(spacing: 0) {
            if modules.isEmpty {
                emptyStateView
            } else if viewMode == "grid" {
                // Grid navigation: Books → Chapters → Verses as button grids
                BibleGridNavigationView()
            } else {
                HSplitView {
                    // Left: Book/Chapter navigation
                    BibleNavigationPanel()
                        .frame(minWidth: 200, maxWidth: 250)

                    // Right: Verse list or search results
                    BibleContentPanel()
                        .frame(minWidth: 400)
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
        .onReceive(NotificationCenter.default.publisher(for: .deleteBibleModule)) { _ in
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
                let otBooks = module.books.filter { $0.testament == "OT" }.sorted { $0.bookNumber < $1.bookNumber }
                let ntBooks = module.books.filter { $0.testament == "NT" }.sorted { $0.bookNumber < $1.bookNumber }

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
                }
                .listStyle(.sidebar)

                // Chapter grid
                if let book = libraryManager.selectedBook {
                    Divider()
                    chapterGrid(book: book)
                }
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

    private func chapterGrid(book: BibleBook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Chapters", comment: "Section title"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                    ForEach(book.sortedChapters) { chapter in
                        Button {
                            libraryManager.selectChapter(chapter)
                        } label: {
                            Text("\(chapter.chapterNumber)")
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(
                                    libraryManager.selectedChapter?.id == chapter.id
                                        ? Color.accentColor
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                                .foregroundStyle(
                                    libraryManager.selectedChapter?.id == chapter.id
                                        ? .white
                                        : .primary
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: 200)
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Bible Content Panel (Verses / Search Results)
struct BibleContentPanel: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager

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

            // Verses list
            List(chapter.sortedVerses) { verse in
                BibleVerseRow(verse: verse)
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

    private var isSelected: Bool {
        libraryManager.selectedVerses.contains { $0.id == verse.id }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(verse.verseNumber)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, alignment: .trailing)

            Text(verse.text)
                .font(.body)
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
            // Double-click sends to presentation
            presentationManager.showBibleVerse(
                text: verse.text,
                reference: verse.fullReference,
                translationName: libraryManager.selectedBibleModule?.abbreviation ?? ""
            )
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
                presentationManager.showBibleVerse(
                    text: verse.text,
                    reference: verse.fullReference,
                    translationName: libraryManager.selectedBibleModule?.abbreviation ?? ""
                )
            }
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
}

// MARK: - Bible Grid Navigation View (BibleShow-style)
/// A full-panel grid view: Books → Chapters → Verses shown as tappable button grids
/// with breadcrumb navigation to go back.
struct BibleGridNavigationView: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var presentationManager
    @AppStorage("multiVerseLayout") private var multiVerseLayout: String = "inline"
    @AppStorage("showVerseNumberPrefix") private var showVerseNumberPrefix: Bool = false
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
                                        translationName: libraryManager.selectedBibleModule?.abbreviation ?? ""
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
                            Text(libraryManager.formattedSelectedVersesText(
                                layout: multiVerseLayout,
                                showPrefix: showVerseNumberPrefix
                            ))
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

    var body: some View {
        VStack(spacing: 20) {
            Text(String(localized: "Import Bible Module", comment: "Sheet title"))
                .font(.title2.bold())

            // File/folder selector — user picks first, format is auto-detected
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "Select a Bible file or folder to import:", comment: "Import instruction"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    if let url = selectedFileURL {
                        Image(systemName: fileIcon)
                            .foregroundStyle(Color.accentColor)
                        Text(url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(String(localized: "No file selected", comment: "Placeholder"))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Menu {
                        Button(String(localized: "Choose File...", comment: "Button")) {
                            chooseFile()
                        }
                        Button(String(localized: "Choose Folder (USFM)...", comment: "Button")) {
                            chooseFolder()
                        }
                    } label: {
                        Text(String(localized: "Browse...", comment: "Button"))
                    }
                }
                .padding()
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
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

            // Supported formats info
            if selectedFileURL == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Supported formats:", comment: "Section header"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(SupportedBibleFormat.allCases) { format in
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(format.displayName)
                                .font(.caption)
                            Text("(\(format.fileExtensions.map { ".\($0)" }.joined(separator: ", ")))")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
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
        panel.allowedContentTypes = [
            UTType(filenameExtension: "json") ?? .json,
            UTType(filenameExtension: "xml") ?? .xml,
            UTType(filenameExtension: "osis") ?? .xml,
            UTType(filenameExtension: "mybible") ?? .data,
            UTType(filenameExtension: "usfm") ?? .plainText,
            UTType(filenameExtension: "sfm") ?? .plainText,
            UTType(filenameExtension: "txt") ?? .plainText,
            UTType(filenameExtension: "utf8") ?? .plainText,
            UTType(filenameExtension: "zef") ?? .xml
        ]
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

    private func performImport() {
        guard let fileURL = selectedFileURL, let format = selectedFormat else { return }
        isImporting = true
        importProgress = 0
        importStatusText = String(localized: "Starting import...", comment: "Import progress")

        Task {
            do {
                let module = try await ImportService.importBible(
                    fileURL: fileURL,
                    format: format,
                    modelContext: modelContext
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
