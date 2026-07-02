//
//  TopPresenterApp.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData

@main
struct TopPresenterApp: App {
    @State private var presentationManager: PresentationManager
    @State private var audioPlayerManager = AudioPlayerManager()
    @State private var videoPlayerService: VideoPlayerService
    /// Separate, isolated store for presentation history (its own DB file).
    @State private var historyStore: HistoryStore
    /// Sparkle-backed auto-updater (launch + scheduled checks, quiet prompts).
    @StateObject private var updateController = UpdateController()
    /// Handles output-wide menu commands (black/freeze/clear/font) exactly once —
    /// they act on the shared PresentationManager, not per window/tab.
    private let commandRouter: PresentationCommandRouter

    init() {
        let video = VideoPlayerService()
        let history = HistoryStore()
        let pm = PresentationManager()
        pm.videoService = video
        pm.historyStore = history
        _videoPlayerService = State(initialValue: video)
        _historyStore = State(initialValue: history)
        _presentationManager = State(initialValue: pm)
        commandRouter = PresentationCommandRouter(pm: pm)
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            // No staged migration plan: the SchemaV1→V2 change is purely additive
            // (new song entities + new Song attributes). SwiftData's automatic lightweight
            // inference handles adding entities/relationships, which the staged
            // `.lightweight`/`.custom` APIs reject at stage construction.
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // Main control window(s). Each window/tab gets its OWN navigation and
        // library state (own sidebar selection, own Bible module, own verse
        // selection) — the presentation OUTPUT stays app-global, so whichever
        // tab presses Show owns the projector.
        WindowGroup(id: WindowIdentifiers.main) {
            MainWindowRoot()
                .environment(presentationManager)
                .environment(audioPlayerManager)
                .environment(videoPlayerService)
                .environment(historyStore)
                .environmentObject(updateController)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1400, height: 900)
        .commands {
            FileCommands()
            ViewCommands()
            PresentationCommands()
            UpdaterCommands(updater: updateController)
            HelpCommands()
        }

        // Presentation output window
        WindowGroup(id: WindowIdentifiers.presentation, for: String.self) { _ in
            PresentationOutputView()
                .environment(presentationManager)
                .environment(videoPlayerService)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.plain)
        .windowResizability(.contentSize)
        .defaultSize(width: 1920, height: 1080)
        // Don't let macOS restore a stale output window on relaunch — the app
        // re-opens it itself, and a restored duplicate caused overlapping outputs.
        .restorationBehavior(.disabled)

        // Presentation history now lives IN the main window (sidebar ▸ History),
        // not as a separate window — see ContentAreaView + AppState.SidebarItem.history.

        // Settings window
        Settings {
            SettingsView()
                .environment(AppState())
                .environment(presentationManager)
                .environmentObject(updateController)
        }
        .modelContainer(sharedModelContainer)
    }
}

/// Root of one main window/tab: owns the PER-WINDOW state (navigation +
/// library selections), so different tabs can sit in different modules with
/// different Bible sources at the same time.
struct MainWindowRoot: View {
    @State private var appState = AppState()
    @State private var libraryManager = LibraryManager()

    var body: some View {
        MainControlView()
            .environment(appState)
            .environment(libraryManager)
    }
}
