# TopPresenter — Agent Guide

> This file is the single source of truth for any AI agent working on this codebase.
> Read it in full before making any changes.

---

## Project Identity

| Field | Value |
|-------|-------|
| **Name** | TopPresenter |
| **Platform** | macOS 15.7+ |
| **Language** | Swift 5.0+, SwiftUI, SwiftData |
| **Xcode** | 16.3+ |
| **Repo** | https://github.com/RobyRew/TopPresenter |
| **License** | Apache 2.0 (see `LICENSE` + `NOTICE`) |
| **Current version** | `0.0.1` (pre-release; bumped to `1.0.0` only when explicitly asked) |
| **Author** | Cosmin Calin / RobyRew |

---

## Architecture Overview

```
TopPresenter/
├── Core/
│   ├── AppState.swift          @Observable — global navigation + alert state
│   ├── AppCommands.swift       SwiftUI Commands (menu bar) + all Notification.Name constants
│   ├── Constants.swift         WindowIdentifiers, SupportedBibleFormat, SupportedExportFormat,
│   │                           USFMBookIDs, BibleBookCategory, PresentationDefaults
│   ├── DataMigration.swift     SchemaV1 + TopPresenterMigrationPlan (SchemaMigrationPlan)
│   ├── LibraryManager.swift    @Observable — Bible & Song navigation, search, verse caching
│   └── PresentationManager.swift @Observable — live output state, screen management,
│                               freeze/black/clear, all display settings (UserDefaults)
│
├── Models/                     All @Model (SwiftData)
│   ├── BibleModels.swift       BibleModule → BibleBook → BibleChapter → BibleVerse
│   ├── SongModels.swift        SongCollection → Song → SongVerse
│   └── PresentationModels.swift MediaItem, PresentationSlide, ServiceSchedule, ScheduleItem,
│                               PresentationStyle, LiveContent
│
├── Services/
│   ├── Import/
│   │   ├── BibleImportProtocol.swift   protocol BibleImporter + BibleImportResult structs
│   │   ├── SongImportProtocol.swift    protocol SongImporter + SongImportResult structs
│   │   ├── ImportService.swift         central coordinator — importer registry pattern
│   │   ├── DragDropImportHandler.swift classifies dropped files → .bible/.song/.media/.unknown
│   │   ├── TopPresenterBibleImporter.swift
│   │   ├── OSISBibleImporter.swift
│   │   ├── ZefaniaBibleImporter.swift
│   │   ├── MySwordBibleImporter.swift  (SQLite via libsqlite3)
│   │   ├── USFMBibleImporter.swift     (directory of .usfm files)
│   │   ├── UnboundBibleImporter.swift
│   │   ├── OpenSongImporter.swift
│   │   ├── OpenLyricsImporter.swift
│   │   └── PowerPointSongImporter.swift (native Swift ZIP/XML parser)
│   ├── Export/
│   │   └── ExportService.swift         Bible (JSON/TXT/CSV) + Song (JSON/XML/TXT)
│   ├── Audio/
│   │   └── AudioPlayerManager.swift    @Observable — AVAudioPlayer wrapper
│   └── Video/
│       └── VideoPlayerService.swift    @Observable — AVPlayer wrapper
│
├── Views/
│   ├── Main/
│   │   ├── MainControlView.swift       root window: sidebar + content + preview panel
│   │   ├── SidebarView.swift
│   │   ├── ContentAreaView.swift       routes to the active module view
│   │   ├── PreviewPanelView.swift      routes to the active preview panel
│   │   ├── QuickSearchOverlay.swift    ⌘K global search
│   │   └── Panels/
│   │       ├── BiblePreviewPanel.swift
│   │       ├── SongsPreviewPanel.swift
│   │       ├── MediaPreviewPanel.swift
│   │       ├── SchedulePreviewPanel.swift
│   │       └── CustomSlidesPreviewPanel.swift
│   ├── Bible/         BibleView.swift, BibleExportSheet.swift
│   ├── Songs/         SongsView.swift
│   ├── Media/         MediaView.swift
│   ├── Schedule/      ScheduleView.swift
│   ├── CustomSlides/  CustomSlidesView.swift
│   ├── Presentation/  PresentationOutputView.swift, VerseTextRenderer.swift
│   ├── Import/        BatchImportSheet.swift, BatchExportSheet.swift
│   └── Settings/      SettingsView.swift, KeyboardShortcutsSheet.swift
│
└── TopPresenterApp.swift   @main — two WindowGroups (main + presentation-output), menu commands
```

---

## Key Architectural Patterns

### State Management
- **`@Observable`** on `AppState`, `PresentationManager`, `LibraryManager`, `AudioPlayerManager`
- Objects injected via `.environment(...)` at the top level in `TopPresenterApp.swift`
- **Never use `@EnvironmentObject`** — this project uses the newer `@Observable` + `@Environment` pairing

### Command Routing
- All menu bar actions post `Notification.Name` (all defined in `AppCommands.swift`)
- Views subscribe via `.onReceive(NotificationCenter.default.publisher(for: ...))`
- **Do not call `PresentationManager` methods directly from commands** — always go through notifications

### SwiftData
- All persistent models are `@Model` classes in `Models/`
- Schema version: `SchemaV1` (1.0.0). Future schema changes must add a new `VersionedSchema` type and register a migration stage in `TopPresenterMigrationPlan`
- `LibraryManager` caches sorted verses in `cachedSortedVerses` — refresh by calling `refreshCachedVerses()` via `selectedChapter.didSet`

### Display Settings Persistence
- Every `PresentationManager` display property uses `didSet { UserDefaults.standard.set(..., forKey: "pm_\(property)") }`
- Keys are all prefixed `pm_` to avoid collisions
- Do not use `AppStorage` or `@AppStorage` for presentation settings — stick to the `didSet` pattern

### Presentation Output Window
- `WindowIdentifiers.presentation = "presentation-output"` — a plain, borderless, transparent `WindowGroup`
- Window is configured in `TransparentWindowConfigurator` (NSViewRepresentable inside `PresentationOutputView`)
- `PresentationManager.movePresentationWindow(to:)` finds the window by `NSUserInterfaceItemIdentifier(WindowIdentifiers.presentation)`
- **The window must never be made opaque** — background transparency is intentional for projector overlays
- Window auto-opens on app launch (0.3 s delay in `MainControlView.onAppear`)

### Escape / Clear Behavior
- Escape → posts `.clearOutput` notification → `clearOutput()` on `PresentationManager`
- `clearOutput()` calls `hidePresentationWindow()` when `isSingleScreenMode == true` (single display)
- `hidePresentationWindow()` uses `window.orderOut(nil)` — **not** `dismissWindow`
- `showPresentationWindow()` uses `window.orderFront(nil)` and is called at the start of `showBibleVerse`, `showSongVerse`, `showCustomText`, and when `toggleBlack()` turns black on

### Screen Management
- Built-in screen = `NSScreen.screens.first`
- External (target) screen = `NSScreen.screens.last` when more than one screen is available
- `isSingleScreenMode = NSScreen.screens.count <= 1`
- On screen disconnect: configurable action (`doNothing` / `moveToAvailable` / `goBlack` / `ask`)
- Monitoring started in `MainControlView.onAppear` via `presentationManager.startScreenMonitoring()`

### Adding a Bible Importer
1. Create `Services/Import/MyFormatImporter.swift`
2. Conform to `BibleImporter` — implement `format` and `parse(fileURL:) async throws -> BibleImportResult`
3. Add the format case to `SupportedBibleFormat` in `Constants.swift`
4. Register in `ImportService.bibleImporters`

### Adding a Song Importer
Same pattern — conform to `SongImporter`, add to `SupportedSongFormat`, register in `ImportService.songImporters`.

---

## Release & Versioning

### Pre-releases (alpha)
- Every push to `main` triggers the `pre-release` job in `.github/workflows/build-and-release.yml`
- Tag format: `v{MARKETING_VERSION}-alpha.{GITHUB_RUN_NUMBER}` (e.g. `v0.0.1-alpha.7`)
- Each prerelease is **unique** — old ones are never deleted or overwritten
- Pre-release series: `0.0.1`, `0.0.2`, `0.1.0`, …

### Stable releases (manual)
1. Bump `MARKETING_VERSION` in `TopPresenter.xcodeproj/project.pbxproj` to the final version (e.g. `1.0.0`)
2. Commit and push
3. Tag and push: `git tag v1.0.0 && git push origin v1.0.0`
4. The `release` job fires only for tags that **do not contain `-`** (e.g. `v1.0.0` qualifies; `v0.0.1-alpha.7` does not)

### Build (unsigned, for CI)
```bash
xcodebuild \
  -scheme TopPresenter \
  -project TopPresenter.xcodeproj \
  -configuration Release \
  -derivedDataPath build \
  -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  clean build
```
Unsigned builds require users to right-click → Open, or run `xattr -cr TopPresenter.app`.

---

## Keyboard Shortcuts (do not change without updating `KeyboardShortcutsSheet.swift`)

| Shortcut | Action |
|----------|--------|
| `⌘K` | Quick search |
| `⌘B` | Black screen |
| `⌘F` | Freeze / Unfreeze |
| `Return` | Show / Hide content |
| `← →` | Navigate verses / slides |
| `Escape` | Clear output (hides window on built-in screen) |
| `⌘+Click` | Multi-select verses |
| `⇧⌘Escape` | Clear All |
| `⌘1–5` | Navigate to Bible / Songs / Media / Schedule / Custom Slides |
| `⌘I` | Import Bible |
| `⇧⌘I` | Import Songs |
| `⌘E` | Export Bible module |
| `⇧⌘E` | Batch Export |
| `⌘+` / `⌘-` / `⌘0` | Increase / Decrease / Reset font size |
| `⇧⌘P` | Start Presentation |
| `⇧⌘K` | Keyboard shortcuts reference |

---

## Localization

- All user-visible strings use `String(localized: "...", comment: "...")` — never raw string literals
- Locales in `i18n/locales/`: `en`, `ro` (Romanian is the primary deployment language)
- Alert strings in `AppState.showError` / `showSuccess` must be localized
- One existing Romanian string slipped into `MainControlView`: `"Ecran Deconectat"` — leave it, it's intentional

---

## What NOT To Do

- Do not add `@AppStorage` or `@State` for presentation display settings — use `PresentationManager` + `UserDefaults` `didSet`
- Do not use `dismissWindow` — window visibility is managed by `orderOut`/`orderFront` directly
- Do not make the presentation output window opaque
- Do not delete or merge the `beta` tag — it no longer exists; pre-releases use numbered alpha tags
- Do not use `@EnvironmentObject` — use `@Environment` with `@Observable`
- Do not add `NSPersistentContainer` or CoreData — SwiftData only
- Do not hardcode screen indices — always use `NSScreen.screens` dynamically
- Do not skip `security-scoped bookmark` handling for media files — `MediaItem.resolvedURL` handles this

---

## File Format Identifiers (for import auto-detection)

| Export type | JSON field | Value |
|-------------|-----------|-------|
| Bible | `"format"` | `"TopPresenter Bible"` |
| Songs | `"format"` | `"TopPresenter Songs"` |

All TopPresenter exports embed this identifier so importers can reliably distinguish them from generic JSON.

---

## Keeping This File Up To Date

**This file must be updated whenever any of the following change:**

- A new architectural pattern is introduced or an existing one is changed (e.g. a new observable class, a new notification name, a new persistence model)
- A new importer/exporter format is added (update the File Format Identifiers table + the Importer section)
- A new keyboard shortcut is added or an existing one is remapped
- A new `@Model` type is added to the SwiftData schema (update `DataMigration.swift` section + models list)
- A new screen management rule is established
- A "What NOT To Do" rule is discovered (e.g. after a painful bug or regression)
- The deployment target, Xcode version, or Swift version changes
- The versioning or release process changes
- A new localization locale is added
- Any important constraint or behaviour is explained verbally in a chat — **if it's worth saying once, write it here so it doesn't need to be said again**

When in doubt: add it. Future agents and contributors will thank you.
