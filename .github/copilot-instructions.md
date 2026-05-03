# GitHub Copilot Instructions — TopPresenter

> These instructions apply to every file in this repository.
> Copilot must read and respect all rules below before suggesting or writing any code.

---

## Project Snapshot

TopPresenter is a **native macOS 15.7+ presentation app** for churches and worship teams.  
It projects Bible verses, song lyrics, media, and custom slides to an external screen or projector.  
Stack: **SwiftUI + SwiftData + AppKit where needed**, Xcode 16.3+, Swift 5.0+.  
Repo: https://github.com/RobyRew/TopPresenter  
License: **Apache 2.0** (`LICENSE` + `NOTICE`). Do not change to MIT or any other license.

---

## Non-Negotiable Patterns

### State Management
- Use `@Observable` + `@Environment` — **never `@EnvironmentObject` or `@ObservableObject`**
- The three root observable objects are `AppState`, `PresentationManager`, `LibraryManager`
- Inject at the `WindowGroup` level in `TopPresenterApp.swift`

### Command Routing
- Menu bar actions **always** post a `Notification.Name` (all defined in `AppCommands.swift`)
- Views subscribe with `.onReceive(NotificationCenter.default.publisher(for: ...))`
- Never call `PresentationManager` methods directly from a `Commands` struct

### Persistence
- **SwiftData only** — no CoreData, no NSPersistentContainer
- All `@Model` classes live in `Models/`
- Schema is versioned: current version is `SchemaV1` (1.0.0)
- When adding a new `@Model` property: add it to `SchemaV1.models` if it is a new type; bump the schema and add a migration stage for breaking changes
- Display settings on `PresentationManager` persist via `didSet { UserDefaults.standard.set(..., forKey: "pm_\(key)") }` — all keys are prefixed `pm_`
- **Never use `@AppStorage` for presentation display settings**

### Presentation Output Window
- The output window is **transparent by default** — `isOpaque = false`, `backgroundColor = .clear`
- Window level is configurable: `"normal"` / `"floating"` / `"alwaysOnTop"` / `"behindDesktop"`
- Window is found by `NSUserInterfaceItemIdentifier(WindowIdentifiers.presentation)` — never by index
- Showing/hiding uses `window.orderFront(nil)` / `window.orderOut(nil)` — **never `dismissWindow`**
- The window must never be made opaque; do not add `.background(.black)` to `PresentationOutputView`

### Escape / Clear behavior (critical — do not revert)
- Pressing Escape → `.clearOutput` notification → `PresentationManager.clearOutput()`
- `clearOutput()` clears live content AND calls `hidePresentationWindow()` when `isSingleScreenMode == true`
- The window is restored by `showPresentationWindow()` at the start of `showBibleVerse`, `showSongVerse`, `showCustomText`, and when `toggleBlack()` turns black on
- This behavior must be preserved when modifying any of those four methods

### Importers
- Conform to `BibleImporter` or `SongImporter` protocols
- Register in `ImportService.bibleImporters` / `ImportService.songImporters` (dictionary keyed by format enum)
- Auto-detection logic lives in `ImportService.detectBibleFormat` and `detectSongFormat`
- File security: always call `fileURL.startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()`
- USFM is a **directory** format (`isDirectoryFormat == true`) — handle accordingly

### Media
- Media file URLs are stored with a **security-scoped bookmark** (`MediaItem.bookmarkData`)
- Always resolve via `MediaItem.resolvedURL` — it handles stale bookmarks
- Never use raw `filePath` strings directly for file access

---

## Code Style

- File header: `// Created by Cosmin Calin on DD/MM/YYYY.`
- `MARK:` comments required for each logical section within a file
- All user-visible strings: `String(localized: "...", comment: "...")`
- No raw string literals in UI code
- Prefer `async/await` over callbacks in import/export operations
- `async` work must not block the main thread; use `Task { }` at call sites

---

## What Copilot Must Not Do

| Forbidden | Reason |
|-----------|--------|
| Add `@EnvironmentObject` | Project uses `@Observable` + `@Environment` |
| Add `@AppStorage` for `PresentationManager` properties | Use `UserDefaults` `didSet` pattern |
| Use `dismissWindow` | Window visibility managed via `orderOut`/`orderFront` |
| Make `PresentationOutputView` opaque | Projector overlay must stay transparent |
| Remove or bypass `security-scoped bookmark` logic | Required for sandboxed file access |
| Delete alpha pre-release tags | Each is unique and permanent |
| Introduce CoreData | SwiftData only |
| Change the license | Stay on Apache 2.0 |
| Use string literals for Notification.Name | Add to the `Notification.Name` extension in `AppCommands.swift` |
| Bump `MARKETING_VERSION` to `1.0.0` automatically | Only the developer does this manually |

---

## Versioning Rules

- App is currently on version `0.0.1` (alpha phase)
- Every push to `main` creates a unique GitHub prerelease: `v0.0.1-alpha.{run_number}`
- Stable releases use clean semver tags (`v1.0.0`, `v1.1.0`, …) pushed manually by the developer
- The CI `release` job only fires for tags that **do not contain `-`**
- Never delete existing prerelease tags from GitHub

---

## Screen Management Rules

- Built-in screen: `NSScreen.screens.first`
- External (target) screen: `NSScreen.screens.last` when count > 1
- `isSingleScreenMode`: `NSScreen.screens.count <= 1`
- Never hardcode screen indices; always derive from `NSScreen.screens` at call time
- Screen disconnect handling is in `PresentationManager.handleScreenConfigurationChange()`

---

## Localization

- Primary languages: English (`en`) and Romanian (`ro`)
- Use `String(localized:comment:)` for every user-visible string
- The alert `"Ecran Deconectat"` is intentionally in Romanian — do not translate it
- New settings panels must have both `en` and `ro` strings

---

## Quick Reference: Adding a Feature

### New Bible import format
1. `Services/Import/MyFormatImporter.swift` — implement `BibleImporter`
2. Add case to `SupportedBibleFormat` in `Constants.swift`
3. Register in `ImportService.bibleImporters`
4. Add extensions to `DragDropImportHandler`

### New Song import format
Same pattern using `SongImporter` and `SupportedSongFormat`.

### New `PresentationManager` display setting
1. Declare with `didSet { UserDefaults.standard.set(..., forKey: "pm_myKey") }`
2. Initialize from `UserDefaults` in `init()`
3. Add a corresponding output accessor (`outputMyProp`) for freeze-safe reads

### New `@Model`
1. Add to `Models/`
2. Add to `SchemaV1.models`
3. If it needs a cascade relationship, use `@Relationship(deleteRule: .cascade, inverse: \...)` 

### New keyboard shortcut
1. Add `Button` + `.keyboardShortcut` in the correct `Commands` struct in `AppCommands.swift`
2. Add `Notification.Name` to the `extension Notification.Name` block in `AppCommands.swift`
3. Add handler in the appropriate `ViewModifier` in `MainControlView.swift`
4. Update `KeyboardShortcutsSheet.swift`
