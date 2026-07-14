//
//  TopPresenterApp.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import CoreSpotlight

@main
struct TopPresenterApp: App {
    @State private var presentationManager: PresentationManager
    @State private var audioPlayerManager: AudioPlayerManager
    @State private var videoPlayerService: VideoPlayerService
    /// Separate, isolated store for presentation history (its own DB file).
    @State private var historyStore: HistoryStore
    /// Session-only song pins („Fixează sus") — app-global, clears on quit.
    @State private var pinStore = PinStore()
    /// THE session runner — one live output ⇒ one running session, app-global.
    @State private var sessionRunner: SessionRunner
    /// Search/browse backbone: off-main-built projections + token index for the
    /// whole library (30-60k songs stay instant). App-global.
    @State private var searchIndex = SearchIndex()
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
        let audio = AudioPlayerManager()
        let runner = SessionRunner()
        runner.pm = pm
        runner.video = video
        runner.audio = audio
        _audioPlayerManager = State(initialValue: audio)
        _videoPlayerService = State(initialValue: video)
        _historyStore = State(initialValue: history)
        _presentationManager = State(initialValue: pm)
        _sessionRunner = State(initialValue: runner)
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
                .environment(pinStore)
                .environment(sessionRunner)
                .environment(searchIndex)
                .environmentObject(updateController)
                .frame(minWidth: 1100, minHeight: 700)
                .task { searchIndex.configure(container: sharedModelContainer, history: historyStore) }
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1400, height: 900)
        .commands {
            FileCommands()
            ViewCommands()
            SettingsCommands()
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

        // Presentation history AND Settings live IN the main window (sidebar ▸
        // History / Settings) — no separate windows. ⌘, is a replaced
        // .appSettings command (SettingsCommands) that navigates the KEY tab.
    }
}

/// Root of one main window/tab: owns the PER-WINDOW state (navigation +
/// library selections), so different tabs can sit in different modules with
/// different Bible sources at the same time.
struct MainWindowRoot: View {
    @Environment(\.modelContext) private var modelContext
    @State private var appState = AppState()
    @State private var libraryManager = LibraryManager()

    var body: some View {
        MainControlView()
            .environment(appState)
            .environment(libraryManager)
            // App-wide accent: native controls (pickers, toggles, list
            // selection) follow the chosen accent; custom views read the
            // same value via the global `appAccent`. On „Sistem” the tint is
            // NIL — inheriting the real macOS accent (see AccentStore.tintOverride).
            .tint(AccentStore.shared.tintOverride)
            // System Spotlight result clicked → jump straight to the item.
            .onContinueUserActivity(CSSearchableItemActionType) { activity in
                guard let raw = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                      let (kind, id) = SpotlightIndexer.parse(identifier: raw) else { return }
                openFromSpotlight(kind: kind, id: id)
            }
    }

    private func openFromSpotlight(kind: String, id: UUID) {
        switch kind {
        case "song":
            var d = FetchDescriptor<Song>(predicate: Song.predicate(forID: id))
            d.fetchLimit = 1
            guard let song = (try? modelContext.fetch(d))?.first else { return }
            appState.selectedSidebarItem = .songs
            if let col = song.collection { libraryManager.selectCollection(col) }
            libraryManager.selectSong(song)
        case "session":
            var d = FetchDescriptor<ServiceSchedule>(predicate: ServiceSchedule.predicate(forID: id))
            d.fetchLimit = 1
            guard let schedule = (try? modelContext.fetch(d))?.first else { return }
            appState.selectedSidebarItem = .schedule
            libraryManager.selectedSchedule = schedule
        default:
            break
        }
    }
}
