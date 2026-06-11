//
//  MainControlView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The main control window - split into sidebar, content area, and preview panel.
struct MainControlView: View {
    @Environment(AppState.self) private var appState
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    @State private var showExportSheet = false
    @State private var showKeyboardShortcuts = false
    @State private var showQuickSearch = false
    @State private var showBatchImport = false
    @State private var showBatchExport = false
    @State private var showLayoutEditor = false
    @State private var droppedFiles: [PendingImportFile] = []
    @State private var isDragTargeted = false

    var body: some View {
        @Bindable var state = appState

        ZStack {
            mainContent
                .alert(
                    appState.alertTitle,
                    isPresented: $state.showAlert
                ) {
                    Button(String(localized: "OK", comment: "Alert button")) { }
                } message: {
                    Text(appState.alertMessage)
                }
                .sheet(isPresented: $showExportSheet) {
                    BibleExportSheet()
                }
                .sheet(isPresented: $showKeyboardShortcuts) {
                    KeyboardShortcutsSheet()
                }
                .sheet(isPresented: $showBatchImport) {
                    BatchImportSheet(pendingFiles: droppedFiles)
                }
                .sheet(isPresented: $showBatchExport) {
                    BatchExportSheet()
                }
                .sheet(isPresented: $showLayoutEditor) {
                    LayoutEditorSheet()
                }
                .onKeyWindowNotification(.openLayoutEditor) { _ in
                    showLayoutEditor = true
                }
                .modifier(MenuCommandHandler(
                    appState: appState,
                    presentationManager: presentationManager,
                    showExportSheet: $showExportSheet,
                    showKeyboardShortcuts: $showKeyboardShortcuts,
                    openWindow: openWindow
                ))
                .modifier(QuickSearchCommandHandler(showQuickSearch: $showQuickSearch))
                .modifier(BatchExportCommandHandler(showBatchExport: $showBatchExport))
                .onKeyWindowNotification(.batchImportFiles) { notification in
                    if let files = notification.userInfo?["files"] as? [PendingImportFile] {
                        droppedFiles = files
                        showBatchImport = true
                    }
                }
                // Drag & Drop support
                .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                .overlay {
                    if isDragTargeted {
                        dragTargetOverlay
                    }
                }

            // Quick Search overlay (⌘K)
            if showQuickSearch {
                QuickSearchOverlay(isPresented: $showQuickSearch)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showQuickSearch)
        .onAppear {
            // Auto-open the presentation output window on app launch
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                openWindow(id: WindowIdentifiers.presentation, value: "main")
                presentationManager.isPresentationWindowOpen = true
            }
            // Start monitoring screen connect/disconnect
            presentationManager.startScreenMonitoring()
        }
        // Screen disconnection alert
        .alert(
            String(localized: "Ecran Deconectat", comment: "Alert title"),
            isPresented: Binding(
                get: { presentationManager.showScreenDisconnectedAlert },
                set: { presentationManager.showScreenDisconnectedAlert = $0 }
            )
        ) {
            Button(String(localized: "Mută pe alt ecran", comment: "Alert button")) {
                presentationManager.moveToNextAvailableScreen()
            }
            .keyboardShortcut(.defaultAction)

            Button(String(localized: "Ecran Negru", comment: "Alert button")) {
                presentationManager.isBlackScreen = true
            }

            Button(String(localized: "Nu face nimic", comment: "Alert button"), role: .cancel) {
                // Do nothing
            }

            Button(String(localized: "Oprește prezentarea", comment: "Alert button"), role: .destructive) {
                presentationManager.clearOutput()
                presentationManager.isPresentationWindowOpen = false
            }
        } message: {
            Text(String(localized: "Ecranul de prezentare a fost deconectat. Ce dorești să faci?", comment: "Alert message"))
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView()
        } detail: {
            HSplitView {
                // Main content area
                ContentAreaView()
                    .frame(minWidth: 500)

                // Preview & controls panel
                PreviewPanelView()
                    .frame(minWidth: 300, maxWidth: 400)
            }
        }
        .navigationTitle("")
        .toolbar {
            bibleToolbarContent
            songToolbarContent
            mediaToolbarContent
            scheduleToolbarContent
            customSlidesToolbarContent
            presentationToolbarContent
        }
        .toolbarRole(.editor)
    }

    // MARK: - Drag & Drop

    private var dragTargetOverlay: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down.on.square.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                Text(String(localized: "Drop files to import", comment: "Drag overlay"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(String(localized: "Bible, Songs, PowerPoint, Images, Audio, Video", comment: "Drag overlay subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                .padding(4)
        )
        .allowsHitTesting(false)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        // Provider callbacks arrive on arbitrary threads — serialize the appends.
        let lock = NSLock()
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                defer { group.leave() }
                if let data = data as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString) {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }

        group.notify(queue: .main) { [self] in
            guard !urls.isEmpty else { return }
            let classified = DragDropImportHandler.classify(urls)

            // Separate by category
            let bibleFiles = classified.filter { if case .bible = $0.category { return true }; return false }
            let songFiles = classified.filter { if case .song = $0.category { return true }; return false }
            let mediaFiles = classified.filter { if case .media = $0.category { return true }; return false }
            let unknownFiles = classified.filter { if case .unknown = $0.category { return true }; return false }

            // Auto-import media files immediately (no dialog needed)
            if !mediaFiles.isEmpty {
                let _ = DragDropImportHandler.importMedia(
                    files: mediaFiles,
                    modelContext: modelContext,
                    onUpdate: { _, _ in }
                )
                let count = mediaFiles.count
                appState.showSuccess(
                    String(localized: "Media Imported", comment: "Alert"),
                    message: String(localized: "\(count) media file(s) imported.", comment: "Alert")
                )
                // Switch to media tab if only media was dropped
                if bibleFiles.isEmpty && songFiles.isEmpty {
                    appState.selectedSidebarItem = .media
                }
            }

            // Process Bible and Song files through batch import
            let importableFiles = bibleFiles + songFiles
            if !importableFiles.isEmpty {
                if importableFiles.count == 1, let single = importableFiles.first {
                    droppedFiles = [single]
                    showBatchImport = true
                } else {
                    droppedFiles = importableFiles
                    showBatchImport = true
                }
            }

            // Show error only if everything was unknown
            if bibleFiles.isEmpty && songFiles.isEmpty && mediaFiles.isEmpty && !unknownFiles.isEmpty {
                appState.showError(
                    String(localized: "Unrecognized Files", comment: "Alert"),
                    message: String(localized: "None of the dropped files were recognized. Supported: Bible modules (.json, .xml, .mybible, .usfm), Songs (.xml, .pptx, .ppt), Media (images, audio, video).", comment: "Alert")
                )
            }
        }
    }

    // MARK: - Bible Toolbar Helpers

    @ToolbarContentBuilder
    private var bibleToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if appState.selectedSidebarItem == .bible {
                bibleModulePicker
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .bible {
                bibleSearchField
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .bible {
                bibleViewModeToggle
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .bible {
                Button {
                    appState.triggerBibleImport = true
                } label: {
                    Label(String(localized: "Import", comment: "Toolbar button"), systemImage: "square.and.arrow.down")
                }
                .help(String(localized: "Import Bible Module", comment: "Toolbar tooltip"))
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .bible && libraryManager.selectedBibleModule != nil {
                Button {
                    NotificationCenter.default.post(name: .deleteBibleModule, object: nil)
                } label: {
                    Label(String(localized: "Delete", comment: "Toolbar button"), systemImage: "trash")
                }
                .help(String(localized: "Delete Selected Module", comment: "Toolbar tooltip"))
            }
        }
    }

    // MARK: - Songs Toolbar Content

    @ToolbarContentBuilder
    private var songToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if appState.selectedSidebarItem == .songs {
                songCollectionPicker
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .songs {
                songSearchField
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .songs {
                Button {
                    appState.triggerSongImport = true
                } label: {
                    Label(String(localized: "Import", comment: "Toolbar button"), systemImage: "square.and.arrow.down")
                }
                .help(String(localized: "Import Songs", comment: "Toolbar tooltip"))
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .songs && libraryManager.selectedSongCollection != nil {
                Button {
                    NotificationCenter.default.post(name: .deleteSongCollection, object: nil)
                } label: {
                    Label(String(localized: "Delete", comment: "Toolbar button"), systemImage: "trash")
                }
                .help(String(localized: "Delete Selected Collection", comment: "Toolbar tooltip"))
            }
        }
    }

    // MARK: - Media Toolbar Content

    @ToolbarContentBuilder
    private var mediaToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if appState.selectedSidebarItem == .media {
                Picker(
                    String(localized: "Filter", comment: "Toolbar picker"),
                    selection: Binding(
                        get: { UserDefaults.standard.string(forKey: "mediaTypeFilter") ?? "all" },
                        set: { UserDefaults.standard.set($0, forKey: "mediaTypeFilter") }
                    )
                ) {
                    Text(String(localized: "All", comment: "Filter option")).tag("all")
                    Text(String(localized: "Images", comment: "Filter option")).tag("image")
                    Text(String(localized: "Audio", comment: "Filter option")).tag("audio")
                    Text(String(localized: "Video", comment: "Filter option")).tag("video")
                }
                .frame(minWidth: 100, maxWidth: 180)
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .media {
                Button {
                    NotificationCenter.default.post(name: .importMedia, object: nil)
                } label: {
                    Label(String(localized: "Add Media", comment: "Toolbar button"), systemImage: "plus")
                }
                .help(String(localized: "Import media files", comment: "Toolbar tooltip"))
            }
        }
    }

    // MARK: - Schedule Toolbar Content

    @ToolbarContentBuilder
    private var scheduleToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if appState.selectedSidebarItem == .schedule {
                Button {
                    NotificationCenter.default.post(name: .newSchedule, object: nil)
                } label: {
                    Label(String(localized: "New Schedule", comment: "Toolbar button"), systemImage: "plus.rectangle")
                }
                .help(String(localized: "Create new schedule", comment: "Toolbar tooltip"))
            }
        }

        ToolbarItem(placement: .automatic) {
            if appState.selectedSidebarItem == .schedule {
                Button {
                    NotificationCenter.default.post(name: .addScheduleItem, object: nil)
                } label: {
                    Label(String(localized: "Add Item", comment: "Toolbar button"), systemImage: "plus")
                }
                .help(String(localized: "Add item to schedule", comment: "Toolbar tooltip"))
            }
        }
    }

    // MARK: - Custom Slides Toolbar Content

    @ToolbarContentBuilder
    private var customSlidesToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if appState.selectedSidebarItem == .customSlides {
                Button {
                    NotificationCenter.default.post(name: .addSlide, object: nil)
                } label: {
                    Label(String(localized: "New Slide", comment: "Toolbar button"), systemImage: "plus.rectangle")
                }
                .help(String(localized: "Create new slide", comment: "Toolbar tooltip"))
            }
        }
    }

    // MARK: - Presentation Toolbar Content

    @ToolbarContentBuilder
    private var presentationToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            screenSelectorMenu
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                presentationManager.toggleBlack()
            } label: {
                Label(
                    String(localized: "Black Screen", comment: "Toolbar button"),
                    systemImage: presentationManager.isBlackScreen ? "rectangle.fill" : "rectangle"
                )
            }
            .keyboardShortcut("b", modifiers: [.command])
            .help(String(localized: "Toggle Black Screen", comment: "Toolbar tooltip"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                presentationManager.clearOutput()
            } label: {
                Label(
                    String(localized: "Clear", comment: "Toolbar button"),
                    systemImage: "xmark.rectangle"
                )
            }
            .keyboardShortcut(.escape, modifiers: [])
            .help(String(localized: "Clear Output", comment: "Toolbar tooltip"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                presentationManager.isEditMode.toggle()
            } label: {
                Label(
                    String(localized: "Edit Mode", comment: "Toolbar button"),
                    systemImage: presentationManager.isEditMode
                        ? "rectangle.dashed.badge.record"
                        : "rectangle.dashed"
                )
            }
            // No keyboard shortcut: ⇧⌘E belongs to Batch Export (File menu wins anyway)
            .help(String(localized: "Toggle Edit Mode — shows layout bounds", comment: "Toolbar tooltip"))
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                showLayoutEditor = true
            } label: {
                Label(
                    String(localized: "Layout Editor", comment: "Toolbar button"),
                    systemImage: "rectangle.and.pencil.and.ellipsis"
                )
            }
            .help(String(localized: "Open the Layout Editor — boxes, text, background, output", comment: "Toolbar tooltip"))
        }
    }

    // MARK: - Bible Toolbar View Helpers

    @Query(sort: \BibleModule.name) private var modules: [BibleModule]
    @Query(sort: \SongCollection.name) private var songCollections: [SongCollection]
    @AppStorage("bibleViewMode") private var bibleViewMode: String = "list"

    @ViewBuilder
    private var bibleModulePicker: some View {
        Picker(
            String(localized: "Module", comment: "Toolbar picker label"),
            selection: Binding(
                get: { libraryManager.selectedBibleModule?.id },
                set: { newID in
                    if let id = newID, let module = modules.first(where: { $0.id == id }) {
                        libraryManager.selectModule(module)
                    }
                }
            )
        ) {
            Text(String(localized: "Select Module", comment: "Picker placeholder"))
                .tag(nil as UUID?)
            ForEach(modules) { module in
                Text(module.abbreviation.isEmpty ? module.name : "\(module.abbreviation) - \(module.name)")
                    .tag(module.id as UUID?)
            }
        }
        .frame(minWidth: 140, maxWidth: 280)
    }

    @ViewBuilder
    private var bibleSearchField: some View {
        let library = Bindable(libraryManager)
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "Search (e.g., John 3:16)", comment: "Search placeholder"),
                text: library.bibleSearchQuery
            )
            .textFieldStyle(.plain)
            .frame(minWidth: 140, maxWidth: 260)
            .onSubmit {
                libraryManager.searchBible(query: libraryManager.bibleSearchQuery, in: modules)
            }

            if !libraryManager.bibleSearchQuery.isEmpty {
                Button {
                    libraryManager.bibleSearchQuery = ""
                    libraryManager.bibleSearchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var bibleViewModeToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                bibleViewMode = bibleViewMode == "list" ? "grid" : "list"
            }
        } label: {
            Label(
                bibleViewMode == "grid"
                    ? String(localized: "List View", comment: "Toolbar button")
                    : String(localized: "Grid View", comment: "Toolbar button"),
                systemImage: bibleViewMode == "grid" ? "list.bullet" : "square.grid.2x2"
            )
        }
        .help(bibleViewMode == "grid"
            ? String(localized: "Switch to list view", comment: "Toolbar tooltip")
            : String(localized: "Switch to grid view", comment: "Toolbar tooltip")
        )
    }

    // MARK: - Songs Toolbar Helpers

    @ViewBuilder
    private var songCollectionPicker: some View {
        Picker(
            String(localized: "Collection", comment: "Toolbar picker label"),
            selection: Binding(
                get: { libraryManager.selectedSongCollection?.id },
                set: { newID in
                    if let id = newID, let coll = songCollections.first(where: { $0.id == id }) {
                        libraryManager.selectCollection(coll)
                    }
                }
            )
        ) {
            Text(String(localized: "All Collections", comment: "Picker option"))
                .tag(nil as UUID?)
            ForEach(songCollections) { coll in
                Text(coll.name).tag(coll.id as UUID?)
            }
        }
        .frame(minWidth: 140, maxWidth: 280)
    }

    @ViewBuilder
    private var songSearchField: some View {
        let library = Bindable(libraryManager)
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                String(localized: "Search songs...", comment: "Search placeholder"),
                text: library.songSearchQuery
            )
            .textFieldStyle(.plain)
            .frame(minWidth: 140, maxWidth: 260)
            .onSubmit {
                libraryManager.searchSongs(
                    query: libraryManager.songSearchQuery,
                    in: songCollections
                )
            }

            if !libraryManager.songSearchQuery.isEmpty {
                Button {
                    libraryManager.songSearchQuery = ""
                    libraryManager.songSearchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Screen Selector

    private var screenSelectorMenu: some View {
        Menu {
            ForEach(Array(presentationManager.availableScreens.enumerated()), id: \.offset) { index, screen in
                Button {
                    presentationManager.positionOnScreen(screen)
                } label: {
                    let screenName = screen.localizedName
                    if index == presentationManager.presentationScreenIndex {
                        Label(screenName, systemImage: "checkmark")
                    } else {
                        Text(screenName)
                    }
                }
            }

            Divider()

            Button {
                presentationManager.refreshScreens()
            } label: {
                Label(
                    String(localized: "Refresh Screens", comment: "Menu item"),
                    systemImage: "arrow.clockwise"
                )
            }
        } label: {
            Label(
                String(localized: "Screens", comment: "Toolbar button"),
                systemImage: "rectangle.on.rectangle"
            )
        }
    }
}

// MARK: - Menu Command Handler (broken out to help the type checker)
private struct MenuCommandHandler: ViewModifier {
    let appState: AppState
    let presentationManager: PresentationManager
    @Binding var showExportSheet: Bool
    @Binding var showKeyboardShortcuts: Bool
    let openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        content
            .onKeyWindowNotification(.importBible) { _ in
                appState.selectedSidebarItem = .bible
                appState.triggerBibleImport = true
            }
            .onKeyWindowNotification(.importSongs) { _ in
                appState.selectedSidebarItem = .songs
                appState.triggerSongImport = true
            }
            .onKeyWindowNotification(.exportBible) { _ in
                showExportSheet = true
            }
            // Black/freeze/clear/font-size commands are handled ONCE app-wide by
            // PresentationCommandRouter — never per window/tab.
            .onKeyWindowNotification(.startPresentation) { _ in
                openWindow(id: WindowIdentifiers.presentation, value: "main")
                presentationManager.isPresentationWindowOpen = true
            }
            .modifier(NavigationCommandHandler(
                appState: appState,
                showKeyboardShortcuts: $showKeyboardShortcuts
            ))
    }
}

private struct NavigationCommandHandler: ViewModifier {
    let appState: AppState
    @Binding var showKeyboardShortcuts: Bool

    func body(content: Content) -> some View {
        content
            .onKeyWindowNotification(.navigateToBible) { _ in
                appState.selectedSidebarItem = .bible
            }
            .onKeyWindowNotification(.navigateToSongs) { _ in
                appState.selectedSidebarItem = .songs
            }
            .onKeyWindowNotification(.navigateToMedia) { _ in
                appState.selectedSidebarItem = .media
            }
            .onKeyWindowNotification(.navigateToSchedule) { _ in
                appState.selectedSidebarItem = .schedule
            }
            .onKeyWindowNotification(.navigateToCustomSlides) { _ in
                appState.selectedSidebarItem = .customSlides
            }
            .onKeyWindowNotification(.showKeyboardShortcuts) { _ in
                showKeyboardShortcuts = true
            }
    }
}

private struct QuickSearchCommandHandler: ViewModifier {
    @Binding var showQuickSearch: Bool

    func body(content: Content) -> some View {
        content
            .onKeyWindowNotification(.quickSearch) { _ in
                showQuickSearch = true
            }
    }
}

private struct BatchExportCommandHandler: ViewModifier {
    @Binding var showBatchExport: Bool

    func body(content: Content) -> some View {
        content
            .onKeyWindowNotification(.batchExport) { _ in
                showBatchExport = true
            }
    }
}
