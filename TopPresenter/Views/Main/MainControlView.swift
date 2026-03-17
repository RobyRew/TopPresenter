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
    @Environment(\.openWindow) private var openWindow

    @State private var showExportSheet = false
    @State private var showKeyboardShortcuts = false
    @State private var showQuickSearch = false
    @State private var showBatchImport = false
    @State private var showBatchExport = false
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
                .modifier(MenuCommandHandler(
                    appState: appState,
                    presentationManager: presentationManager,
                    showExportSheet: $showExportSheet,
                    showKeyboardShortcuts: $showKeyboardShortcuts,
                    openWindow: openWindow
                ))
                .modifier(QuickSearchCommandHandler(showQuickSearch: $showQuickSearch))
                .modifier(BatchExportCommandHandler(showBatchExport: $showBatchExport))
                .onReceive(NotificationCenter.default.publisher(for: .batchImportFiles)) { notification in
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
            ToolbarItemGroup(placement: .primaryAction) {
                toolbarContent
            }
        }
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
                Text(String(localized: "Bible modules and song files", comment: "Drag overlay subtitle"))
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
        var urls: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { data, _ in
                defer { group.leave() }
                if let data = data as? Data,
                   let urlString = String(data: data, encoding: .utf8),
                   let url = URL(string: urlString) {
                    urls.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            let classified = DragDropImportHandler.classify(urls)
            let known = classified.filter { if case .unknown = $0.category { return false }; return true }

            if known.isEmpty {
                appState.showError(
                    String(localized: "Unrecognized Files", comment: "Alert"),
                    message: String(localized: "None of the dropped files were recognized as Bible or Song files.", comment: "Alert")
                )
            } else if known.count == 1, let single = known.first {
                // Single file: go straight to import
                droppedFiles = [single]
                showBatchImport = true
            } else {
                // Multiple files: show batch import
                droppedFiles = classified
                showBatchImport = true
            }
        }
    }

    @ViewBuilder
    private var toolbarContent: some View {
        // Screen selector
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

        // Present button
        Button {
            openWindow(id: WindowIdentifiers.presentation, value: "main")
            presentationManager.isPresentationWindowOpen = true
        } label: {
            Label(
                String(localized: "Present", comment: "Toolbar button"),
                systemImage: "play.rectangle.fill"
            )
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])

        // Black screen toggle
        Button {
            presentationManager.toggleBlack()
        } label: {
            Label(
                String(localized: "Black Screen", comment: "Toolbar button"),
                systemImage: presentationManager.isBlackScreen ? "rectangle.fill" : "rectangle"
            )
        }
        .keyboardShortcut("b", modifiers: [.command])

        // Clear output
        Button {
            presentationManager.clearOutput()
        } label: {
            Label(
                String(localized: "Clear", comment: "Toolbar button"),
                systemImage: "xmark.rectangle"
            )
        }
        .keyboardShortcut(.escape, modifiers: [])
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
            .onReceive(NotificationCenter.default.publisher(for: .importBible)) { _ in
                appState.selectedSidebarItem = .bible
                appState.triggerBibleImport = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .importSongs)) { _ in
                appState.selectedSidebarItem = .songs
                appState.triggerSongImport = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportBible)) { _ in
                showExportSheet = true
            }
            .modifier(PresentationCommandHandler(
                presentationManager: presentationManager,
                openWindow: openWindow
            ))
            .modifier(NavigationCommandHandler(
                appState: appState,
                showKeyboardShortcuts: $showKeyboardShortcuts
            ))
    }
}

private struct PresentationCommandHandler: ViewModifier {
    let presentationManager: PresentationManager
    let openWindow: OpenWindowAction

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .startPresentation)) { _ in
                openWindow(id: WindowIdentifiers.presentation, value: "main")
                presentationManager.isPresentationWindowOpen = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleBlackScreen)) { _ in
                presentationManager.toggleBlack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleFreeze)) { _ in
                presentationManager.toggleFreeze()
            }
            .onReceive(NotificationCenter.default.publisher(for: .clearOutput)) { _ in
                presentationManager.clearOutput()
            }
            .onReceive(NotificationCenter.default.publisher(for: .increaseFontSize)) { _ in
                presentationManager.fontSize = min(presentationManager.fontSize + 2, PresentationDefaults.maxFontSize)
            }
            .onReceive(NotificationCenter.default.publisher(for: .decreaseFontSize)) { _ in
                presentationManager.fontSize = max(presentationManager.fontSize - 2, PresentationDefaults.minFontSize)
            }
            .onReceive(NotificationCenter.default.publisher(for: .resetFontSize)) { _ in
                presentationManager.fontSize = PresentationDefaults.fontSize
            }
    }
}

private struct NavigationCommandHandler: ViewModifier {
    let appState: AppState
    @Binding var showKeyboardShortcuts: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .navigateToBible)) { _ in
                appState.selectedSidebarItem = .bible
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSongs)) { _ in
                appState.selectedSidebarItem = .songs
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToMedia)) { _ in
                appState.selectedSidebarItem = .media
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToSchedule)) { _ in
                appState.selectedSidebarItem = .schedule
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToCustomSlides)) { _ in
                appState.selectedSidebarItem = .customSlides
            }
            .onReceive(NotificationCenter.default.publisher(for: .showKeyboardShortcuts)) { _ in
                showKeyboardShortcuts = true
            }
    }
}

private struct QuickSearchCommandHandler: ViewModifier {
    @Binding var showQuickSearch: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .quickSearch)) { _ in
                showQuickSearch = true
            }
    }
}

private struct BatchExportCommandHandler: ViewModifier {
    @Binding var showBatchExport: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .batchExport)) { _ in
                showBatchExport = true
            }
    }
}
