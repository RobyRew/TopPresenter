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
    @State private var appState = AppState()
    @State private var presentationManager = PresentationManager()
    @State private var libraryManager = LibraryManager()
    @State private var audioPlayerManager = AudioPlayerManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            BibleModule.self,
            BibleBook.self,
            BibleChapter.self,
            BibleVerse.self,
            SongCollection.self,
            Song.self,
            SongVerse.self,
            PresentationSlide.self,
            ServiceSchedule.self,
            ScheduleItem.self,
            MediaItem.self,
            PresentationStyle.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // Main control window
        WindowGroup(id: WindowIdentifiers.main) {
            MainControlView()
                .environment(appState)
                .environment(presentationManager)
                .environment(libraryManager)
                .environment(audioPlayerManager)
                .frame(minWidth: 1100, minHeight: 700)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1400, height: 900)
        .commands {
            FileCommands()
            ViewCommands()
            PresentationCommands()
            HelpCommands()
        }

        // Presentation output window
        WindowGroup(id: WindowIdentifiers.presentation, for: String.self) { _ in
            PresentationOutputView()
                .environment(presentationManager)
        }
        .modelContainer(sharedModelContainer)
        .windowStyle(.plain)
        .defaultSize(width: 1920, height: 1080)

        // Settings window
        Settings {
            SettingsView()
                .environment(appState)
                .environment(presentationManager)
        }
        .modelContainer(sharedModelContainer)
    }
}
