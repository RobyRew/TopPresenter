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
│   ├── Presentation/  PresentationOutputView.swift, TextBoxLayout.swift
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

### Video Output
- `VideoPlayerService` (`@Observable`) is created in `TopPresenterApp.init()`, injected via `.environment(...)` into both windows, and linked back via `PresentationManager.videoService` (weak) so `clearOutput()` stops playback
- "Play Video" in `MediaPreviewPanel` → `videoService.loadVideo(url:)` + `play()` + `pm.showVideo()` (sets `LiveContent.contentType = .media`)
- The output window renders `OutputVideoView` (AVKit `AVPlayerView`, `controlsStyle = .none`) when `contentType == .media`; it stays mounted under the black-screen overlay so toggling black doesn't tear down the player
- `VideoPlayerService` holds `startAccessingSecurityScopedResource()` for the whole playback; released in `stop()`

### Preview Card Parity
- `PresentationPreviewCard` previews the **Bible verse selection** by default
- Non-Bible panels (Songs / Schedule / Custom Slides) must pass `pendingContent:` (`PendingContent(text:reference:subtitle:)`) so the card previews their selection before it goes live — never rely on the Bible-selection fallback there
- The preview card and `PresentationOutputView` must stay layout-identical: both render every section inside the same normalized `TextBoxFrame`s

### Uniform Box Styles (BoxTextStyle)
- EVERY text box (4 built-ins + custom) carries the same `BoxTextStyle`: `isCustomized == false` (default) inherits global text settings + section defaults (`styleDefaults(for:)` — ref 55%/semibold, translation 35%/0.6 opacity, subtitle 40%/0.6); the UI "Personalizează textul" toggle calls `enableStyleCustomization(for:)` which SEEDS fields with current resolved values
- Render exclusively through `resolvedStyle(for:)` / `outputStyle(for:)` (frozen-aware) / `resolvedCustomStyle(_:)` — never read raw style fields in views
- The old per-section properties (verseFontName, refFontWeight, showTranslationName, translationNameSizeRatio, …) are GONE; translation is a normal box (hidden by default, default frame top-left), subtitle hidden by default
- Sources support `date`/`time` with per-box formats (`formattedClock`); output wraps content in a TimelineView driven by `pm.clockTickInterval` so clocks tick live

### Per-Content Backgrounds & Themes
- `contentBackgrounds["bible"/"song"/"text"]` (`BackgroundConfig`) override the global background per presenter type; render via `activeBackground(for:frozen:)` — never read backgroundEnabled/backgroundImage directly in render paths
- Themes (`Theme`/`ThemePayload`) snapshot the ENTIRE look (global text, backgrounds, frames, visibility, styles, sources, custom + media boxes); `ThemeMenuControl` lives in every panel footer (`PanelFooter`) and the editor header
- **Unified z-order for EVERY box** (sections + custom + media interleaved): `pm.boxOrder` token list ("section:<raw>" / "custom:<uuid>" / "media:<uuid>"), reconciled via `orderedBoxTokens()` (pure — safe in view body; new boxes land on top, media defaults to the back). ALL render paths (output `orderedBoxes`, preview card, editor canvas) iterate this order — never hardcode section/media layering again. Reorder via drag in the Casete list (front-first, `reorderBoxToken(_:above:)`) or the Ordonare context menu on any box (canvas + list)
- Custom + media boxes are renamable (`name` field, context-menu Redenumește); translation & subtitle rows have a trash button that HIDES them (built-ins are never deleted)
- Hidden boxes are COMPLETELY invisible everywhere — preview card AND editor canvas pass `showsHiddenBoxes: false`; the only place a hidden box appears is the Casete list (dimmed, eye to re-enable)
- The per-box Vertical picker lives INSIDE the "Personalizează textul" toggle (with a Global segment); non-customized boxes inherit `globalVAlignRaw`
- The GLOBAL text palette includes weight (`globalWeightRaw` — inherited by every section whose design default is regular), vertical alignment (`globalVAlignRaw` — inherited when a box's `vAlignRaw` is empty), and opacity (`globalTextOpacity` — multiplied into non-customized boxes). Every option must exist at BOTH levels — never add a per-box style control without its global counterpart
- The Fundal tab shows only the per-presenter override relevant to the module the editor was opened from (Bible module → just "Biblie"); Schedule/Media show all three

### Multi-Window Tabs
- Each main window/tab owns its OWN `AppState` + `LibraryManager` (created in `MainWindowRoot`) — different tabs can browse different modules with different Bible sources. `PresentationManager`/audio/video are app-global: ONE output, whichever tab presses Show drives it
- File ▸ Filă Nouă (⌘T) opens a new window that joins as a native tab (`tabbingMode = .preferred` set in `WindowReader`); capped at 10 main windows
- **Notification handlers in window-hosted views MUST use `.onKeyWindowNotification(_:perform:)`** (WindowNotifications.swift), never raw `.onReceive` — otherwise every tab reacts to every menu command. Output-wide commands (black/freeze/clear/font size) are handled ONCE by `PresentationCommandRouter` (created in App.init), never per window
- **NEVER use a customizable toolbar (`.toolbar(id:)`) on the tabbed main window** — customizable toolbars sync items across the window-tab family via the customization plist, and the second tab re-inserts NavigationSplitView's sidebar toggle → `NSToolbar duplicate item` assertion CRASH. The main toolbar must stay a plain `.toolbar { }`

### Layout Undo / Redo
- Snapshot-based (`registerLayoutUndo()` called at the top of every box mutator; snapshots reuse `ThemePayload`); registrations <0.8s apart coalesce so a drag = one step; `applyPayload` sets `isRestoringLayout` so restores never re-register; undo/redo buttons live on the "Casete" group title in the editor. New box mutators MUST call `registerLayoutUndo()` first

### Fixed Text Box Layout (the layout system)
- Four FIXED built-in text boxes — verse content, reference/title, translation name, subtitle — each a `PresentationManager.TextBoxFrame` (normalized 0…1 x/y/width/height of the target screen), plus user-created `CustomTextBox`es (own text + style, persisted as JSON under `pm_customTextBoxes`)
- **Boxes never move or resize with their content.** Text is laid out INSIDE its box (horizontal alignment from text settings, per-box vertical alignment `pm_verseVAlign` / `pm_refVAlign`); `padding` is the inner horizontal inset
- Persisted as JSON under `pm_verseBoxFrame` / `pm_refBoxFrame` / `pm_translationBoxFrame` / `pm_subtitleBoxFrame`; always go through `boxFrame(for:)` / `setBoxFrame(_:for:)` — overloads take `TextBoxSection` or `BoxIdentity` (`.section(...)` / `.custom(UUID)`) and clamp via `TextBoxFrame.clamped()`; freeze snapshots the frames (and custom boxes) like every other display setting
- **Resolution adaptivity:** font sizes are authored at a 1080-point reference height (`PresentationManager.referenceScreenHeight`) and multiplied by `fontScale(forHeight:)` / `targetFontScale` at render time. Normalized boxes + scaled fonts = the layout adapts automatically to any resolution / aspect ratio / PPI. Auto-fill must pass SCALED font/padding (`pm.fontSize * pm.targetFontScale`)
- `fittedVerseFontSize(text:boxSize:maxSize:padding:)` expects screen-scaled maxSize/padding; reference/translation/subtitle/custom boxes use `minimumScaleFactor` inside their boxes
- Bible auto-fill measures against `pm.verseBoxPointSize` — `LibraryManager.versesCountThatFits(screenSize:)` expects the verse-box point size, not the screen size
- The old per-section offset/scale/padding transforms and the `VerseTextRenderer` text-bounds overlay are GONE — do not reintroduce content-driven box geometry

### Layout Editor (the design studio)
- `LayoutEditorSheet` in `TextBoxLayout.swift` is THE home for all styling: canvas (drag/resize/click-select boxes, right-click context menus, arrow-key nudge 1%/⇧5%, quick-align TOGGLES that restore the previous frame on second press) + tabbed inspector — Layout / Text / Background / Output
- Opened via: toolbar "Layout Editor" button, the `LayoutEditorButton` footer in every preview panel, or Presentation ▸ Layout Editor… (all post `.openLayoutEditor`)
- **The right preview panel is OPERATIONAL ONLY** — preview, navigation, Show/Hide/Black/Freeze/Clear, audio/video transport, Multi-Verse + General quick toggles. New style settings go in the Layout Editor inspector, never back into `StyleQuickSettings`
- Edit Mode (toolbar toggle) shows the drag/resize overlay on the preview card; fine editing happens in the Layout Editor
- Every box shows its DATA SOURCE (inspector "Sursă:", box tooltip, context-menu header). Built-in sections can be hidden (`pm_*BoxVisible`); custom boxes support duplicate/delete
- **Sources are configurable on EVERY text box**: built-in sections default to `"auto"` (their natural field — keep that default) but can be overridden via `pm.sourceRaw(for:)` / `setSourceRaw` to any live field (mainText/reference/translation/subtitle), static text (`pm.staticText(for:)`), or date. Custom boxes default to `"static"`. All rendering goes through `pm.sectionText(_:main:reference:translation:subtitle:)` / `CustomTextBox.resolvedText` — output passes live values, preview passes its preview values, editor passes samples. A non-"auto" translation-box source bypasses the showTranslationName/isBible gate
- **Media boxes** (`PresentationManager.MediaBox`, `pm_mediaBoxes`): image/GIF/video overlays with opacity, corner radius, edge feather (blurred-mask border fade), fit/fill, and `showOnRaw` content filters (always/bible/song/text). Rendering in `MediaBoxViews.swift` — GIFs animate via NSImageView (`animates = true`), videos loop muted via AVQueuePlayer+AVPlayerLooper and PLAY ONLY on the real output (preview/editor show placeholders)
- Picker gotcha: never attach `.help()` (or other modifiers) to tagged segmented-picker items — it breaks tag matching and the tabs stop switching
- Drag gotcha: box drag/resize gestures MUST measure in the overlay's named coordinate space (`TextBoxEditOverlay.canvasSpace`) — measuring in the moving view's own space feeds back into the gesture and the box jitters/shakes

### Sandbox Persistence
- The app is sandboxed (`com.apple.security.app-sandbox`); any user-chosen file that must survive relaunch needs a **security-scoped bookmark**, not a raw path
- Background image: bookmark stored under `pm_backgroundImageBookmark` (set in `setBackgroundImage(from:)`, removed in `removeBackgroundImage()`)
- Media files: `MediaItem.bookmarkData` / `resolvedURL`

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
- Do not give toolbar/panel buttons keyboard shortcuts already owned by a menu command — the menu always wins and the button shortcut is silently dead (this is why Edit Mode has no ⇧⌘E)
- Do not call `NSApp.sendAction(Selector(("showSettingsWindow:")))` — use `@Environment(\.openSettings)`

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
