# TopPresenter — Agent Guide

> This file is the single source of truth for any AI agent working on this codebase.
> Read it in full before making any changes.

---

## Project Identity

| Field | Value |
|-------|-------|
| **Name** | TopPresenter |
| **Platform** | macOS 15.7+ |
| **Language** | **Swift 6 language mode** (SWIFT_VERSION 6.0, default MainActor isolation + approachable concurrency), SwiftUI, SwiftData |
| **Xcode** | 26.3 (17C529) — CI builds on macos-26 with the SAME version; never let CI drift to an older major (it silently ignores Swift-6-era build settings) |
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
│   ├── LibraryManager.swift    @Observable — Bible & Song navigation, search, verse caching,
│   │                           selectedMediaItem/selectedSchedule mirrors (drive tab title + panels)
│   ├── PinStore.swift          @Observable — session-only song pins („Fixează sus"); APP-GLOBAL
│   │                           (one per app, injected beside historyStore), in-memory only
│   ├── Search/
│   │   ├── SearchIndexService.swift  SearchIndex (@Observable, APP-GLOBAL) + SearchIndexBuilder
│   │   │                       (@ModelActor): off-main-built Sendable PROJECTIONS (SongIndexEntry…)
│   │   │                       + token inverted index — the browse/search backbone at 30-60k songs
│   │   └── BibleReferenceParser.swift  pure "ioan 3:16"/"1 cor 13 4-7" parser (unit-tested)
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
│   ├── Media/
│   │   └── MediaPresenter.swift        THE one way a MediaItem goes live (grid, panel, runner)
│   ├── Sessions/
│   │   ├── SessionModels.swift         SessionItemPayload (stable refs) + Draft + Resolution
│   │   ├── SessionService.swift        resolver REGISTRY (SessionItemResolving per itemType),
│   │   │                               append/create; new item kinds plug in here
│   │   ├── SessionRunner.swift         @Observable APP-GLOBAL runner — THE one presenter for
│   │   │                               schedule items (ScheduleView + panel never call pm.show*)
│   │   └── SessionArchive.swift        .tpschedule flat-JSON import/export + requiredMedia manifest
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
│   ├── Media/         MediaView.swift (presentable grid), MediaLibrary.swift (MediaKind + filter)
│   ├── Schedule/      ScheduleView.swift, AddToSessionMenu.swift (shared right-click fragment)
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

### Per-Presenter Layout Profiles (v7 — THE layout model)
- **EVERYTHING layout-related is per presenter.** `LayoutProfile` (frames, visibility, styles, sources/formats/static texts, custom text boxes, media boxes, boxOrder, background, ContentOptions, transitions) is stored per key in `pm.profiles` ("bible" / "song" / "text", persisted as ONE JSON blob under `pm_layoutProfiles`). The old flat per-box UserDefaults keys are LEGACY — read once by the init migration, never written again
- `pm.activeProfileKey` = the profile being EDITED (right bar, preview Edit Mode, Editor de Teme). It follows the sidebar module (`MainControlView.onChange(of: appState.selectedSidebarItem)`) and the editor header has a segmented Biblie/Cântece/Slide-uri picker bound to it (plus a copy-from menu → `copyProfile(from:to:)`)
- `pm.outputProfileKey` = the LIVE content's profile; output render paths use `outputOrderedBoxTokens()` / `outputBoxFrame` / `outputStyle` / `outputSectionVisible` — never the active-profile accessors
- ALL box accessors take a trailing `in key: String? = nil` (nil → activeProfileKey): `boxFrame(for:in:)`, `setSourceRaw(_:for:in:)`, `isSectionVisible(_:in:)`, custom/media CRUD, `orderedBoxTokens(in:)`, … Mutations route through `mutateProfile(_:_:)` which registers undo + persists. The flat compat properties (`verseBoxFrame`, `customTextBoxes`, `boxOrder`, `contentBackgrounds`, `contentOptions`, …) are computed views over the ACTIVE profile — fine in operator UI, NEVER in output render paths
- `relevantSections(for:)` decides which built-in boxes a presenter offers (song = verse+reference+subtitle+**chords**, NO translation; text = verse+reference). `canonicalTokens`/`orderedBoxTokens` enforce it, so songs never see Bible-only casete (and bible/text never see the chords box — `default` filters out `.chords`)
- **Chords casetá + transpose (v10)**: `TextBoxSection.chords` is a song-only built-in box (default OFF, default frame = `.defaultChords` = the verse area, so it's "tied to the verse"). It renders a chord-over-lyric chart, NOT plain text — `PresentationOutputView.sectionBox`, the editor `sampleContent`, and the preview card all special-case `section == .chords` → `ChordChartText(lines: pm.transposedSongLines(), …)` (monospaced layout so a chord at `pos` lands above lyric char `pos`). Chord data flows: `SongSlide.lines` (rich `[SongLine]`, chunked in lockstep with `text` by `splitToSlides`) → `showSongVerse(…, lines:)` → `LiveContent.songLines`; paths that only carry text use `richLines(forSlideText:in:)` to recover chords by line-text match. Transpose/capo are **display-only, ephemeral PM state** (`chordTransposeSemitones`, `chordCapo`, pinned per-song via `chordTransposeSongKey`; reset on song change in `showSongVerse` via `syncChordTranspose`; never mutate the stored song). `ChordTransposer` (pure, tested) does root/quality/bass parsing, enharmonic spelling per target key, semitone math, capo shapes + suggestions, and `recommendedKeys(fromExtensionsJSON:)`. Operator UI = `SongChordControl` (popover in the song detail header, shown when `songHasChords`): ±transpose, key picker, capo + suggested shapes, recommended-key chips, and an "Arată pe ecran" toggle that flips `.chords` visibility in the song profile. `sectionText(.chords)` returns the lyrics only to GATE mounting (non-empty == there's a chord slide); the chart reads `songLines` directly. **No overlap**: when the chords box is active (`chordsReplaceVerse(in:hasChartLines:)`) the verse box is suppressed in every render path (the chart already shows the lyrics). **Independent chord font (v10.1)**: the lyrics use the box's main `BoxTextStyle`; the chord LETTERS use a SECOND style stored under the reserved key `chordRow` in `LayoutProfile.styles` (`chordRowStyle`/`setChordRowStyle`/`resolvedChordRowStyle`/`outputChordRowStyle`). The editor's `selectedBoxStyleGroup` shows TWO `textStyleGroup`s for `.chords` (Versuri + Acorduri litere). `ChordChartText` takes `lyricStyle` + `chordStyle`, **measures** the lyric prefix width (AppKit `NSString.size`) to position each chord, so alignment holds for ANY lyric font + any chord size; it auto-fits via one scale factor
- **Song repeat markers (v10.1) — combinable bracket + count**: `applyRepeatMarker(_:count:bracket:countStyle:)` + `applyRepeatMarkerRich(...)` apply a BRACKET (`song_repeatBracket`: none/slash/bar/pipe — wraps first/last line, shifting first-line chord positions) AND a COUNT (`song_repeatCount`: none/times/bister — `(×N)`/bis/ter appended INLINE to the last line), so they combine: "‖: … :‖ (×2)". Both gate on `section.repeatCount > 1`; line count is unchanged so `text`+`richLines` chunk identically in `splitToSlides`. Count defaults to `times` so a ×N section shows immediately. `resolveRepeat(versionStyle:globalBracket:globalCount:)` maps the single per-version `repeatStyle` override (slash/bar/pipe→bracket, times/bister→count, none→both off, ""→inherit). **All paths** decorate: the filmstrip/`buildSongSlides(…bracket:countStyle:)` and — crucially — the live verse-navigation path (`SongVerseControlsBar`/`SongsPreviewPanel`) via `decoratedVerse(_:version:bracket:countStyle:)`, which the marker-less `SongVerse` cache otherwise skips. Settings UI = two pickers (Paranteze + Repetări) in the song-options panel
- The preview card (`PresentationPreviewCard`) renders with the explicit key `activeContentKey` (live key when live, else the panel's `formatHint`) — pass `in: key` everywhere there
- **Per-profile transitions — THREE phases**: `transitionInRaw` (first appearance), `transitionChangeRaw` (Intermediar — slide → slide), `transitionOutRaw` (clear), + `transitionDurationOverride` (−1 = global duration). `pm.contentChangeKind` ("appear"/"change"/"clear", set by `registerContentChange()` in the show* methods and `clearOutput`) decides which phase `boxTransition(in:)` builds. Catalog in `transitionOptions` (14: none/fade/zoomIn/zoomOut/slide×4/riseSoft/dropSoft/blur/blurZoom/fall/flip). Output applies `.id("\(token)|\(text)")` + `.transition(...)` per box inside `.animation(..., value: liveFingerprint)`. Editor UI lives in the **Tranziții** tab — selecting any effect (or its play button) demos it on the canvas via `playTransitionPreview` (`.id(transitionPreviewTick)` + the chosen `.transition`; commit the raw async-first or the removal plays the old effect)
- **Slide scope ("Afișare")**: every box can show on all/first/last slides (`LayoutProfile.displayOn` per section, `displayOnRaw` on CustomTextBox + MediaBox). `LiveContent` carries `slideIndex`/`slideCount` (every show* caller passes them: song verse position, slide deck position, schedule item position); gate rendering with `pm.scopeMatchesLiveSlide(_:)` — single-slide content counts as BOTH first and last. Use case: song title only on the first slide, "Amin." only on the last
- **Per-presenter casete naming + sources**: `TextBoxSection.label(for key:)` (Songs: Versuri/Titlu Cântec/Etichetă Strofă; Slides: Conținut/Titlu Slide) and `sourceOptions(for key:)` / `sourceOptionLabel(_:for:)` — song sources have no translation, all keys offer static/date/time/**slideNumber** ("2 / 7", resolved via `LiveContent.slideNumberText`). `CustomTextBox`/`MediaBox` now have resilient `init(from:)` — keep decodeIfPresent when adding box fields
- **Editor tab layout (v8/v8.2/v8.3)**: Layout tab = position/content/Afișare only; the per-box "Personalizează textul" style group lives in the **Text** tab (`selectedBoxStyleGroup`) under Text Global, and BOTH lists have the SAME 12 options in the SAME order: Font, Mărime, Greutate, Culoare, Aliniere, Vertical, Opacitate, Spațiere, Transform.(menu picker, NOT segmented — 4 segments overflow the 310pt inspector and center-clip the group), Padding, Umbră, Auto-fit — keep that parity when adding options. Per-box inherit sentinels: padding −1, shadowMode ""(global)/"on"/"off" + shadowRadius −1, autoFitMode ""/"on"/"off". Group inner VStacks carry `.frame(maxWidth: .infinity, alignment: .leading)` so an over-wide row can't center-clip the content
- **Per-box padding/shadow/auto-fit are RESOLVED STYLE fields**: `ResolvedBoxStyle.padding/shadowEnabled/shadowRadius/autoFit` — render paths take them from the style, never from `pm.padding`/`pm.shadowEnabled` directly (the old `scaledPadding` parameter is gone); auto-fit applies to ANY box whose style asks (global Auto-fit toggle still means verse box only by default)
- **Text transforms (v8.2) — STYLE-level, not field-level**: `displayFields` is GONE. `BoxTextStyle.transformRaw` ("" = inherit) resolves into `ResolvedBoxStyle.transformRaw` via `defaultTransform(for:in:)` (profile `options.textTransformRaw` = the Text Global "Transform." picker, applies to ALL boxes; legacy `referenceUppercase` still forces "upper" on the reference section). EVERY render path draws `Text(style.display(text))` — never raw text. `resolvedCustomStyle(_:in:)` needs the profile key. `BoxTextStyle` has a resilient `init(from:)` — keep decodeIfPresent when adding fields
- **Inspector structure (v8.1/v8.2) — NO quick-actions bar**: the `caseteGroup` (z-order list + add buttons + undo/redo) is PINNED above the inspector tab picker; the ROWS scroll inside the group (~3.5 visible, `rowHeight 27`, no dead space below); quick-align toggle buttons live inside Layout ▸ Poziție și Dimensiune; "Resetează Layout" sits at the bottom of the Layout tab. Don't reintroduce a toolbar row above the canvas
- **Show/Hide staging (v8.5) — transitions must actually RENDER**: `presentContent(_:)` wraps every show*: if the output window was hidden (single-screen idle) it orders the window front and mounts the content 60 ms LATER inside `withAnimation(easeInOut(phaseDuration))` — otherwise Intrare pops fully formed (a nil window, e.g. unit tests, applies immediately). `clearOutput` animates the clear with the Ieșire duration and, in single-screen mode, hides the window only AFTER `exitDuration + 0.15s` (guarded on still-not-live) — hiding immediately cut the exit animation AND left stale boxes that made the next Show crossfade like an Intermediar. The output's backgroundLayer is gated on `liveContent.isLive` with `.transition(.opacity)` so the background fades from/to transparency with Intrare/Ieșire (idle output = fully transparent)
- **The global `transitionDuration` has NO UI anymore** (removed from right bar ▸ Ieșire and Settings ▸ Comportament) — it survives only as the stored fallback base under the per-phase sliders. Don't resurface it; durations are edited per phase in Editor de Teme ▸ Tranziții
- **v9 (universal themes + text engine)**: the Teme gallery is UNIVERSAL — every panel shows every theme (a theme carries all presenter profiles); the `format` tag is only the default for newly saved themes + a badge. The gallery click-drag pans (`ScrollPosition` + `onScrollGeometryChange` + `DragGesture(minimumDistance: 12)` so taps/hover survive). Text-engine invariants: `font(at:)` MUST apply `.weight()` to custom fonts too (Greutate was a no-op for any non-System font); `resolve()`'s NOT-customized branch uses `globalVAlignRaw` directly (a stale seeded `vAlignRaw` used to stick after un-customizing); new globals `letterTracking` (pt @1080p, `.tracking(style.tracking * fontScale)` in every render path) and `shadowColorHex` (8-digit RRGGBBAA via `Color.toHexWithAlpha()`, alpha = intensity) — both in ThemePayload/capture/apply/init; per-box `tracking: Double?` (nil = global) + `shadowColorHex` ("" = global). Ranges: font ≤200 (`maxFontSize`), opacity 0–1 step 0.01 (rounded % display), line spacing 0–5 both levels, padding 0–300, shadow radius 0–50. Option order is now: …Opacitate, Spațiere, **Litere**, Transform., Padding, Umbră(color+radius), Auto-fit. Afișare scopes are per key (`displayScopeOptions(for:)`): songs add **Refren/Strofe** (chorus detection = `LiveContent.isChorusSlide`, diacritic/case-insensitive prefix refren/chorus/cor on the subtitle label). Casete list shows 4 rows; the row's drag/tap surface is ONLY the leading label area — eye/trash buttons sit outside it (18×18 hit areas) so clicks are never swallowed
- **v8.4 polish**: EVERY box row has eye + trash (built-ins HIDE — the eye re-enables; custom/media delete) and the same Elimină/Șterge in both context menus. The list color swatch is a `BoxColorSwatch` button (hover ring, popover ColorPicker, "Culoarea implicită" reset) backed by `LayoutProfile.boxColors` token-keyed; `boxColor(for:pm:)` resolves custom-then-default — editor chrome only, never rendered output. `lastLiveProfileKey` keeps `outputProfileKey` on the LAST presented profile after Hide/Clear/ESC so the Ieșire transition (content → transparency) plays with the right profile's effect. Tranziții UI: group is named "Global", each phase has a DIRECT 0–3 s Durată slider writing the phase override (no checkboxes, no general duration row — the global base stays in the right bar ▸ Ieșire); the per-casetă group mirrors that (direct Durată + Întârziere 0–3 s)
- **Per-box transitions (v8.2)**: `LayoutProfile.boxTransitionOverrides` keyed by z-order TOKEN holds `BoxTransition` (isCustomized gate + own in/change/out effects with "" = inherit, `delay` stagger, `duration` −1 = inherit). Per-PHASE durations: `transitionInDuration`/`transitionChangeDuration`/`transitionOutDuration` (−1 = profile general). Resolution order: box override → phase override → profile `transitionDurationOverride` → global. `boxTransition(in:token:)` resolves it all; a box with its own delay/duration carries its own `.animation(...)` clock; output's container animation uses `resolvedTransitionDuration(in:)`. UI: Tranziții tab = "General" group (3 effect rows + per-phase "Durată proprie" checkboxes + general duration toggle) + per-SELECTED-casetă `boxTransitionGroup` ("Personalizează tranziția"). Setting a pristine override DELETES the dict entry
- **Theme hover preview**: resting on a `ThemeCard` for 350 ms applies the theme TRANSIENTLY (`beginThemeHoverPreview`/`endThemeHoverPreview` — snapshot + applyPayload, never registers undo, restores on unhover/onDisappear). It is a NO-OP while `liveContent.isLive` (the projector must never flicker), and `applyTheme` calls `endThemeHoverPreview()` first so undo captures the true previous look
- ThemePayload carries `profiles` (+ global text/background); legacy flat payloads decode via `LegacyKeys` into identical per-presenter profiles. `.tptheme` v2 asset slots: "background", "profileBackground:<key>", "mediaBox:<key>:<uuid>" (v1 "contentBackground:<key>" and "mediaBox:<uuid>" still import)

### Per-Content Backgrounds & Themes
- **Backgrounds support the full media trio** (image / animated GIF / looping muted video) at BOTH levels: global (`backgroundMediaTypeRaw` + `backgroundMediaURL`) and per-content (`BackgroundConfig.mediaTypeRaw`). Render via `activeBackground(for:frozen:)` + `BackgroundMediaView` (plays on output/editor, thumbnail in the preview card) — never read backgroundEnabled/backgroundImage directly in render paths
- Bookmarks: ALWAYS use `PresentationManager.makeBookmark(for:)` / `resolveBookmark(_:)` — they try security-scoped first and fall back to plain (app-container files have no scope)
- Themes (`Theme` with `formatRaw` "all"/"bible"/"song"/"text") snapshot the ENTIRE look; the panel footer hosts a THUMBNAIL GALLERY (`ThemeGalleryView`, filtered by the panel's format + universal themes), with card context menus (apply/update/rename/format/export/delete); `ThemeMenuControl` remains in the editor header
- **Decoding is resilient**: `ThemePayload`/`Theme`/`BackgroundConfig`/`ThemeArchive` use decodeIfPresent with defaults — adding payload fields never breaks stored themes again. Keep this invariant when adding fields
- **.tptheme import/export**: directory package (theme.json `ThemeArchive` v2 + media/ with every referenced file). Export strips bookmarks and embeds files; import copies media into the app container (`themeMediaDirectory(for:)`) and re-bookmarks — themes are fully portable. UTI `com.robyrew.toppresenter.theme` declared in Info.plist
- The editor is called **"Editor de Teme"** everywhere (sheet title, toolbar, menu, footer button)
- Editor tabs: Layout / Text / Fundal / **Tranziții** — NO output/hardware settings in the editor; screen/window-level/transition/disconnect live in Settings (⌘,) ▸ Proiecție (`ProjectionSettingsTab`) AND compactly in the right bar's **Ieșire** disclosure (StyleQuickSettings `.output`, beneath General). Themes describe the LOOK, Settings describe the DEVICE
- **Per-presenter options** (`ContentOptions` keyed "bible"/"song"/"text", theme-persisted, resilient decoding): text transform (none/upper/lower), uppercase reference/title. Applied at RENDER time via `pm.displayFields(main:reference:translation:subtitle:contentKey:)` — output uses the live content key, the preview card uses its panel's `formatHint`. Extend ContentOptions (with decodeIfPresent defaults) when a presenter needs a new option
- Media module output prefs (NOT theme): `videoLoopsByDefault`, `fullscreenVideoFillRaw` — Settings ▸ Proiecție ▸ Media AND the Media panel's StyleQuickSettings `.media` section
- **Live Bible anchor (v10.5)**: `pm.bibleLiveAnchor` snapshots what's PRESENTED (translation+book+chapter+range); ←/→ while live call `pm.stepBibleAnchor(direction:context:)` — browsing/selection NEVER moves the live flow; Show/double-click/session runner re-anchor via the structured params of `showBibleVerse`; `clearOutput` clears the anchor. Don't reintroduce selection-driven live pushes
- **Black/Freeze are OUTPUT-only**: the preview card always renders content; the output state shows as NEGRU/ÎNGHEȚAT badges. Never blank the preview
- **Background stays on Hide (v10.5)**: `pm.backgroundStaysOnHide` (theme-persisted, default ON, toggle in Fundal) keeps the theme background rendered when `liveContent.isLive == false`
- **Personalizează OFF = full reset**: the customize toggle writes a fresh `BoxTextStyle()` (sentinels), never just the flag — stale per-box values must not survive
- **Song versions (v10.5)**: `Song.originalVersionID` picks the ORIGINAL (default) version; `activeVersion` resolves it (else first by order); import auto-sets `overridesMetadata` on versions whose metadata differs from the first and defaults the original to the first WITH a songbook; GOAT round-trips `"original": true`; star button in the detail panel's version picker calls `ImportService.applyOriginalVersionChange` (re-flattens SongVerse cache + re-links songbook)
- **Folder import depth**: the selected folder + at most TWO subfolder levels, everywhere (expandToImportableFiles guard + recursiveSongFiles `en.level > 3` skip); dropped FOLDERS expand through the same walk (MainControlView.handleDrop)
- **Performance backbone (v10.6)**: the Songs browser and ⌘K read ONLY `SearchIndex` projections (SongIndexEntry etc.) — NEVER iterate/fault Song models per keystroke or per cell (`collections.flatMap { $0.songs }` is banned). Real @Models are fetched ON DEMAND by id (`withSong`, predicate + fetchLimit 1). The index rebuilds off-main (SearchIndexBuilder @ModelActor), debounced on `.libraryDidChange` — POST that notification from every song/media/session mutation site or the UI goes stale. Verse full-text search covers the ACTIVE translation only (`indexVerses(moduleID:)`, follows module switch in MainControlView). ⌘K = QuickSearchPalette (Spotlight-style; Enter opens, ⌘Enter presents; reference parser + songs + verses + media + sessions). NO fetch-all to find one row — use a #Predicate (Song has `#Index` on id/title/ccliNumber); SongItemResolver has a ccli fast-path.
- **⌘K palette v2 (v10.7)**: the palette's `body` renders `hits: PaletteHits` STATE only — the search runs ONCE per (30 ms debounced) keystroke in a detached task via `PaletteSearch.run(query, in: index.snapshot())`. NEVER put searching into a computed property the body re-reads (the v1 palette recomputed the full search ~30× per keystroke through `sections`/`runningIndexBase`). Typo tolerance = `TokenIndex.fuzzyCandidates` (prefix-Levenshtein; `fuzzyDistance`: 0 for ≤3 chars / 1 for 4-6 / 2 for ≥7) — the fuzzy fallback fires per-token only when exact prefix has ZERO hits, and vocabulary scans run OFF-main only. Verses have their own `TokenIndex` (built in `buildVerses`) — no linear `contains` over 31k rows. Recents = `PaletteRecentsStore` (UserDefaults, cap 10, shown on empty query). Matches are highlighted via `paletteHighlight` (`range(of:options:[.caseInsensitive,.diacriticInsensitive])`). RESULT PRIORITY (user-locked, CONTEXT-AWARE since v10.10): section DISPLAY order comes from the pure `paletteSectionOrder(context:)` (SearchIndexService) keyed on `appState.selectedSidebarItem.rawValue` — reference is ALWAYS pinned first (it only exists when the query parses as one); Bible tabs then float verses above songs, Media/Schedule float their own kind, everything else keeps reference → `songsByTitle` → verses → `songsByContent` (lyrics-only matches) → media → sessions. The boosted section (first after ref) gets a collapsed cap of 8. Display-only — ranking INSIDE sections never changes; AppState is per-window so ordering is per-tab. SEARCH LOG: `HistoryStore.recordSearch` fires on COMMIT (open/present with a typed query) and on ABANDONED dismiss (non-empty query, nothing opened, kind "abandoned") — NEVER per keystroke; shown in History ▸ Căutări (`searchSummaries()` groups by folded query). NUMERIC query tokens match EXACTLY (`TokenIndex.candidates(for:)` — "matei 1 2" must never pull songs quoting "Matei 28:19") and never fuzz; single DIGITS are indexed (songbook numbers). Palette rows are identified by RESULT id — never `.id(flatIndex)` (an index-identity override made lazy rows render one result's content under another section's header). VERSE RANKING (v10.8): `buildVerses` sorts chapters/verses (relationship arrays are UNORDERED — index position = canonical Bible order); `PaletteSearch.bookHint` (STRICT name/abbrev prefix, any token position, never the reference parser's fuzzy) scopes „isus fapte" to Faptele Apostolilor — scoped hits rank FIRST, then global phrase-first hits capped 2/book while filling (spread), then relaxed. Songs rank by `presentCounts[songKey]` (HistoryStore.songSummaries, refreshed in rebuildNow) inside each bucket. `PaletteSearch.run` carries 50/category + per-category TOTALS; the palette owns collapsed caps (8/6/6/5/5) + „Arată mai multe" (`expandedSections`, reset per query). AUTOSCROLL: keyboard-only via `scrollTarget` + `anchor: nil` (minimal), hover suppressed ~250 ms after an arrow press — hover/click must NEVER scroll the list. SESSIONS (v10.13): ⌥↩ or row context-menu „Adaugă la sesiune" appends the selected result via `sessionDraft(for:)` → `SessionService.append` (library-linked payloads; target = selectedSchedule → most recent → new). The palette STAYS OPEN on ⌥↩ (stack several items) with a transient footer note; schedules are fetched on demand (FetchDescriptor limit 8), never @Query in the palette.
- **System Spotlight (v10.7)**: `SpotlightIndexer.reindex(songs:sessions:)` runs at the end of every `SearchIndex.rebuildNow()` (domains "songs"/"sessions", ids `song:<uuid>`/`session:<uuid>`); deep links come back as `CSSearchableItemActionType` activities handled in `MainWindowRoot.openFromSpotlight`. New findable entity kinds → extend BOTH the indexer and the parser/handler.
- **Verse index cache (v10.10) — build once, never contend**: `SearchIndex.indexVerses` resolves in-memory LRU (3 modules, `versePayloadLRU`) → `VerseIndexCache.load` on disk (binary plist, `App Support/TopPresenter/VerseIndex/<moduleID>.plist`, decoded in a detached task — pure file IO) → ONE `builder.buildVerses` walk, then `cache.save()`. NEVER reintroduce a SwiftData verse rebuild on module switch or on `.libraryDidChange`/`rebuildNow` — the rebuild storm shares the store coordinator with the main thread's display faults and beachballs version switching (song edits must never touch the verse index; bibles only change via import, which re-selects its module, or delete, which goes through `SearchIndex.moduleDeleted`). Cache invalidation = bump `VerseIndexCache.currentFormat` whenever BookIndexEntry/VerseIndexEntry/TokenIndex change shape (stale files are ignored and rebuilt, never migrated); module delete removes its file + LRU entry; Settings ▸ Avansat ▸ „Reindexează tot" (`reindexEverything`) wipes everything.
- **App-wide accent + highlight (v10.11)**: view code uses the globals `appAccent` and `appHighlight` (Core/AppAccent.swift) — NEVER `Color.accentColor` (ignores the in-app choice). SELECTION visuals (selected verses/chapters/books/cards/palette rows/module checks) use `appHighlight`; everything else accent. Backed by the @Observable `AccentStore`: accent = `.system` (LIVE `NSColor.controlAccentColor`) | preset | `.custom` (ColorPicker, persisted as sRGB components "appAccentCustom"); highlight follows the accent by default (`highlightFollowsAccent`) or gets its own preset/custom. Reading the globals in `body` registers Observation so a settings change re-renders everything; native controls follow the ONE `.tint(AccentStore.shared.tintOverride)` at MainWindowRoot — `tintOverride` is NIL on `.system` (controls INHERIT the real macOS accent; NSSwitch/NSPopUpButton IGNORE a tint built from the dynamic `NSColor.controlAccentColor`, which kept painting them with the old asset accent) and a concrete Color otherwise. The app has NO global accent asset: `AccentColor.colorset` + `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` were DELETED (v10.13) — never recreate either. Picker = swatch rows + ColorPicker wells in Settings ▸ Interfață ▸ Aspect (`AppAccentOption.presets` excludes `.custom` — the ColorPicker IS the custom swatch). Semantic colors (BibleBookCategory, palette row kind tints) stay non-accent.
- **⌘K show/hide FX (v10.11)**: the palette owns LAYERED transitions — the dim `Color.black` gets `.transition(.opacity)` (scaling it from the panel's corner read as a black sheet sliding in from the side), the panel gets the scale(0.92, top-right anchor)+opacity. Every `showQuickSearch`/`isPresented` flip goes through `withAnimation(QuickSearchPalette.showHideAnimation)` (capsule button, ⌘K handler, palette dismiss). Container-level `.animation(value: showQuickSearch)` is BANNED — it animated every coincident layout change (the module switch when Enter opens a result) with the palette's spring.
- **Pane resize dividers (v10.11)**: `paneResizeDivider` drags MUST use `DragGesture(coordinateSpace: .global)` — the divider itself moves while resizing, so local-space translation measures against a moving origin (feedback loop, the "very buggy" jitter). Hover cursor push/pop is guarded while a drag runs.
- **ResizableSplit = THE module layout (v10.12)**: every module (Bible "split_bible", Songs "split_songs", Media "split_media", Schedule "split_schedule", Custom Slides "split_custom") is `ResizableSplit` (Views/Main/ResizableSplit.swift) — navigation/list LEFT (default 1/3, FRACTION persisted per key so window resizes keep proportion, clamped minLeading…maxFraction), content RIGHT, one identical draggable divider (global-coordinate drag, guarded cursor). NEVER reintroduce `HSplitView` for module layouts and never fixed-formula pane widths. Media's right side = `MediaDetailPane` (big thumbnail preview + Prezintă via MediaPresenter).
- **Dynamic slides / token pipeline (v10.13)**: Custom Slides (and session TEXT items via the SessionRunner hook) store TEMPLATES with `{{scheme:argument#field|option}}` tokens (Core/SlideTokens/) resolved at PRESENT time. Grammar lives in `SlideTemplate.parse` (pure, tested — `{{{{` escapes, malformed stays literal, the `|option` may sit on the argument OR after the field). A NEW data source = ONE `SlideDataProvider` registered in `SlideTokenResolver.providers` — never special-case schemes elsewhere. Local providers (bible/song/date/time) resolve over SearchIndex PROJECTIONS (song `ccli`/`slide1` and `|ABBREV`-pinned translations are the only on-demand model fetches, predicate + fetchLimit 1). Remote (url/rss) go through `RemoteContentService`: hard 6s timeout, per-URL cache TTL 5 min, STALE fallback — a token may slow a present by at most the timeout, it can NEVER fail one (unresolved renders "—"). No live-ticking on the output in v1 — resolution happens per present. Editor UI: token WIZARDS („Inserează date” — verse/song/date/API-RSS cu „Testează”), never ask users to hand-write syntax; slide rows show the ⚡ token-count chip.
- **Schedule composer (v10.12)**: the old AddScheduleItemSheet is DELETED — sessions are built from the INLINE `ScheduleContentPicker` pinned under the running order (disclosure state "scheduleComposerOpen"; `.addScheduleItem` notification opens it). Songs/media rows come from SearchIndex projections (`searchSongs`/`index.media` — never fetch-all per keystroke), Bible passages go through `BibleReferenceParser.parse` over the ACTIVE translation's verse index (live preview + verse count), and EVERY add goes through `SessionService.append(SessionItemDraft…)` so items carry stable library-linked payloads. Real @Models are fetched by predicate + fetchLimit 1 only at add time.
- **Sidebar (v10.11)**: TWO stacked native Lists sharing ONE selection binding — content modules on top, the utility cluster (History · Settings · Account) PINNED TO THE BOTTOM (`scrollDisabled`, height sized for 3 rows per row-size option — keep `utilityListHeight` generous, a clipped bottom list eats the Account row). No custom row chrome; selection follows `.tint`. Row/icon size = `transformEnvironment(\.sidebarRowSize)` driven by `@AppStorage("sidebarRowSizeOption")` ("system" inherits macOS Appearance; small/medium/large native; "custom" = large rows + `.font(.system(size:))` from the `sidebarCustomIconSize` slider, clamped 11…20) — picker + slider in Settings ▸ Interfață ▸ Aspect. The Settings row is a `Button` row (`.buttonStyle(.plain)` + `.tag`) that both selects and counts the 10-click unlock — NEVER a gesture stacked on a selectable row (a `simultaneousGesture(TapGesture)` fought the list's native click handling and made the row feel dead). ADVANCED UNLOCK IS SESSION-SCOPED: it lives on `AppState.advancedSettingsUnlocked` (NOT AppStorage) — the 10th click also sets `AppState.settingsTabRequest = "advanced"` (SettingsContentView consumes it and jumps to the tab), and `selectedSidebarItem`'s `didSet` re-locks when the user leaves Settings.
- **Settings live IN-APP (v10.10)**: sidebar ▸ Settings (`SidebarItem.settings`) routes to `SettingsContentView` (History-style header + segmented sections; the old `Settings{}` window scene is DELETED — ⌘, is `SettingsCommands` replacing `.appSettings`, posting `.openSettings` handled by the KEY window via `onKeyWindowNotification`). ADVANCED tab: hidden until 10 quick clicks (≤2s apart) on the sidebar Settings row set `@AppStorage("advancedSettingsUnlocked")` (SidebarView.registerSettingsClick); contains reindex + the destructive delete-alls (`AdvancedSettingsTab`, every destructive op behind its own confirmation, delete-all-bibles also calls `SearchIndex.moduleDeleted` + `VerseIndexCache.deleteAll`). New SidebarItem cases must be handled in ContentAreaView AND PreviewPanelView (exhaustive switches).
- **List-row perf invariants (v10.7)**: (1) NEVER stack `.onTapGesture(count: 2)` + `.onTapGesture` on a row — AppKit waits out the double-click interval before delivering the single click; use `.gesture(TapGesture(count: 2))` + `.simultaneousGesture(TapGesture())` (see BibleVerseRow). (2) JSON-backed @Model computed vars (`BibleVerse.runs` & friends) must NEVER decode per row render — go through `VerseRunsCache`. (3) Row selection checks read `libraryManager.selectedVerseIDs` (Set, maintained by `didSet` on `selectedVerses`) — never `.contains` over the model array.
- **Toolbar (v10.9) — CUSTOMIZABLE, per-module**: `.toolbar(id: "tp-toolbar-\(sidebarItem.rawValue)")` — the id keys macOS's persisted customization, so EVERY module keeps its own user-edited layout (right-click → Customize Toolbar…). All items are `ToolbarItem(id:)` with stable ids (`bible.*`, `songs.*`, `output.*`, `search`); pickers are `.customizationBehavior(.disabled)`, delete buttons `.defaultCustomization(.hidden)`. The `search` item is a CAPSULE BUTTON that opens the ⌘K palette (`showQuickSearch`) — the LEGACY toolbar search (`bibleSearchQuery`/`searchBible`/`searchResultsView`/`songSearchQuery` + BibleSearchResult/SongSearchResult) was DELETED; never reintroduce a second search path, ⌘K owns global search. The media kind filter lives in MediaView's OWN header (one filter UI); Freeze sits next to Black/Clear in the presentation group
- **Bible browser skeleton (v10.9, split refined v10.10)**: ONE skeleton for list AND grid modes — left THIRD (`GeometryReader`, clamped 280…480) holds books + chapters, right two-thirds = `BibleContentPanel` full-text verses ALWAYS. Inside the third the arrangement is per-mode (user-locked): GRID stacks `BibleBooksGridPane` over `BibleChaptersPanel` (adaptive dense grid); LIST puts `BibleNavigationPanel` LEFT and `BibleChaptersPanel(fixedColumns: 2)` RIGHT — EXACTLY 2 chapter columns there. BOTH internal splits are USER-RESIZABLE via `paneResizeDivider` (fat invisible hit area + hairline + NSCursor push/pop; caller clamps and persists): list chapters width = `@AppStorage("bibleListChaptersWidth")` (clamp 84…paneWidth*0.6), grid books height fraction = `@AppStorage("bibleGridBooksFraction")` (clamp 0.25…0.8). Don't revert to fixed frames. The old `BibleGridNavigationView` drill-down (levels + breadcrumb + number-only verse grid) is DELETED — don't resurrect it. Book taps go through `selectBookOpeningFirstChapter` (new book → chapter 1 auto-selected; same book keeps the chapter). Verses header has ‹ › chapter steppers + the content toggle icons (Titluri/Note/Referințe/Strong). Keyboard flow in the verses panel (armed by clicking a verse): ↑↓ move selection, ←→ step chapters, Enter presents (single verse rich via shared `projectBibleVerse`, ranges joined)
- **Tabs auto-name only (v10.4)** — the manual "Rename Tab" toolbar button/alert was REMOVED; `autoTabTitle` in MainControlView derives per module (bible: "(RO) EDC100 – ref", songs, media, schedule: session name + date via the testable `MainControlView.scheduleTabDetail(name:date:)`). Don't reintroduce `@SceneStorage("tabCustomName")`
- **Media is a PRESENTABLE module (v10.4)**: MediaView = type tabs (Toate|Foto|Video|Audio) + rich grid (video/audio `durationSeconds` badges, artwork thumbnails via async `MediaThumbnailFactory`) + search on `libraryManager.mediaLibraryQuery`; selection = `libraryManager.selectedMediaItem` (NO notifications). The panel mirrors Bible/Songs anatomy and steps prev/next through `MediaLibrary.filter(...)` — THE one ordering shared with the grid. ALL "present media" paths go through `MediaPresenter.present` (fullscreen image = `pm.showMedia(kind:"image")` decodes the NSImage inside the caller's security scope → `LiveContent.mediaImage`; video = shared `VideoPlayerService`; audio = plays only, never claims the output). New media kinds = a `MediaKind` case + classify rule + icon
- **Sessions (v10.4)**: `ScheduleItem.payloadJSON` (= `SessionItemPayload`, resilient Codable) stores STABLE refs — song `HistoryStore.songKey` (+ optional versionID/versionName), bible translation-abbrev + book/chapter/verse numbers, media id + name fallback; `title/content/subtitle` remain display SNAPSHOTS. Resolution via `SessionService.resolve` (registry of `SessionItemResolving` per itemType — extend there, don't grow a switch); misses → `.missing` (greyed row + ⚠, runner skips). `SessionRunner` (app-global @Observable) is THE ONLY presenter for schedule items — slide-by-slide next/prev (songs expand via `buildSongSlides` with the CURRENT song options at present time), jump-to-item, `presentOnce` for one-shots. „Adaugă la sesiune" = shared `AddToSessionMenu` fragment in the Bible verse / song / media context menus („Sesiune nouă…" creates instantly, no sheet). `.tpschedule` = FLAT JSON (`SessionArchive`, schemaVersion 1, format "TopPresenter Session" REQUIRED on import) + `requiredMedia` manifest; media re-links by id→name on import — media files are NOT embedded
- **Sidebar (v10.2)** = `SidebarItem.contentItems` (bible/songs/media/schedule/customSlides) in the top `List`, + a PINNED bottom group (`utilityItems` = `.history`, `.account` as selectable destinations, plus a **Settings** button via `@Environment(\.openSettings)`). `.history`→`HistoryView`, `.account`→`ProfileView` (local prefs, `@AppStorage` only — no login) route through `ContentAreaView`; both return `EmptyView` in `PreviewPanelView` and the preview column is HIDDEN for them in `MainControlView` (full-width). Any new switch over `SidebarItem` must handle `.history` + `.account`
- **Single output window**: locate it via `presentationWindows` (plural) and call `dedupePresentationWindows()` (closes extras) at the top of `showPresentationWindow`/`movePresentationWindow`/`positionOnScreen` + after the launch auto-open (guarded by `hasPresentationWindow`); the presentation `WindowGroup` is `.restorationBehavior(.disabled)`. This killed the "two overlapping outputs" (state-restoration + auto-open) bug — don't reintroduce an unguarded `openWindow(.presentation)`
- **Song verified flag + edit log (v10.2)**: `Song.verified` (Bool, round-trips through GOAT — `songDictV2` writes `"verified"`, `TopPresenterSongImporter` reads it), `Song.modifiedDate` (drives the Recente sort), `Song.editLogJSON`→`editLog: [SongEditEntry]` (coarse change log, INTERNAL — not exported). The song editor snapshots the song to GOAT on open (`ExportService.exportSongToTopPresenterJSON`); **Renunță** reverts via `ImportService.applyResult(_:to:modelContext:)` (the GOAT→Song builder extracted from `createSongFromResult` — clears + rebuilds versions/sections, reused by import too); **Gata** diffs old↔new via `ImportService.summarizeChanges(old:new:)` → appends edit-log entries. `SectionEditorCard` uses `@FocusState` so clicking a section drives the editor preview. Library: verified badge in `songBadges`, "Doar verificate" filter + `verificat`/✓ search token, sort header chips (`SongSortKey` = A-Z/Artist/Carte/Limbă/Recente). Song slide thumbnails have PREVIEW + trash (delete = remove the section behind the slide, `.confirmationDialog`)
- **Song library browse (v10.3)**: the browser search lives on `LibraryManager.songLibraryQuery` (SHARED — NOT the Quick Search `songSearchQuery`), so detail-panel chips can set it. `SongDetailPanel` chips are clickable `searchChip(_:query:)`/`searchText(_:query:)` that set `songLibraryQuery` (find similar by artist/book/language/style/theme). `filtered` is grouped into subtle `Section` headers by the active `SortKey` (`grouped` + `initialLetter` diacritic-folded; Recente = ungrouped) in BOTH list and grid (grid uses `pinnedViews: [.sectionHeaders]`). `Song.sourceFile` (filename, stamped in `parseDirectory` default + `ImportService` single-file paths, set in `applyResult`) + `Song.webURL` (best-effort URL dug out of `_extensions`) show above the slides; the detail header is Title · book · artist(≤~half width) left, history "Prezentat ×" + key/chords + Edit (large) right
- **Unified z-order for EVERY box** (sections + custom + media interleaved): per-profile `boxOrder` token list ("section:<raw>" / "custom:<uuid>" / "media:<uuid>"), reconciled via `orderedBoxTokens()` (pure — safe in view body; new boxes land on top, media defaults to the back). ALL render paths (output `orderedBoxes`, preview card, editor canvas) iterate this order — never hardcode section/media layering again. Reorder via drag in the Casete list (front-first, `reorderBoxToken(_:above:)`) or the Ordonare context menu on any box (canvas + list)
- Custom + media boxes are renamable (`name` field, context-menu Redenumește); translation & subtitle rows have a trash button that HIDES them (built-ins are never deleted)
- Hidden boxes are COMPLETELY invisible everywhere — preview card AND editor canvas pass `showsHiddenBoxes: false`; the only place a hidden box appears is the Casete list (dimmed, eye to re-enable)
- The per-box Vertical picker lives INSIDE the "Personalizează textul" toggle (with a Global segment); non-customized boxes inherit `globalVAlignRaw`
- The GLOBAL text palette includes weight (`globalWeightRaw` — inherited by every section whose design default is regular), vertical alignment (`globalVAlignRaw` — inherited when a box's `vAlignRaw` is empty), and opacity (`globalTextOpacity` — multiplied into non-customized boxes). Every option must exist at BOTH levels — never add a per-box style control without its global counterpart
- The Fundal tab shows the global background + the EDITED profile's own background only — switch profiles in the editor header to set the others

### Multi-Window Tabs
- Each main window/tab owns its OWN `AppState` + `LibraryManager` (created in `MainWindowRoot`) — different tabs can browse different modules with different Bible sources. `PresentationManager`/audio/video are app-global: ONE output, whichever tab presses Show drives it
- File ▸ Filă Nouă (⌘T) opens a new window that joins as a native tab (`tabbingMode = .preferred` set in `WindowReader`); capped at 10 main windows
- **Notification handlers in window-hosted views MUST use `.onKeyWindowNotification(_:perform:)`** (WindowNotifications.swift), never raw `.onReceive` — otherwise every tab reacts to every menu command. Output-wide commands (black/freeze/clear/font size) are handled ONCE by `PresentationCommandRouter` (created in App.init), never per window
- **NEVER use a customizable toolbar (`.toolbar(id:)`) on the tabbed main window** — customizable toolbars sync items across the window-tab family via the customization plist, and the second tab re-inserts NavigationSplitView's sidebar toggle → `NSToolbar duplicate item` assertion CRASH. The main toolbar must stay a plain `.toolbar { }`

### Layout Undo / Redo
- Snapshot-based (`registerLayoutUndo()` called at the top of every box mutator; snapshots reuse `ThemePayload`); registrations <0.8s apart coalesce so a drag = one step; `applyPayload` sets `isRestoringLayout` so restores never re-register; undo/redo buttons live on the "Casete" group title in the editor. New box mutators MUST call `registerLayoutUndo()` first

### Fixed Text Box Layout (the layout system)
- Four FIXED built-in text boxes — verse content, reference/title, translation name, subtitle — each a `PresentationManager.TextBoxFrame` (normalized 0…1 x/y/width/height of the target screen), plus user-created `CustomTextBox`es (own text + style, stored in each profile)
- **Boxes never move or resize with their content.** Text is laid out INSIDE its box (horizontal alignment from text settings, per-box vertical alignment `pm_verseVAlign` / `pm_refVAlign`); `padding` is the inner horizontal inset
- Persisted inside the profile blob (`pm_layoutProfiles`); always go through `boxFrame(for:)` / `setBoxFrame(_:for:)` — overloads take `TextBoxSection` or `BoxIdentity` (`.section(...)` / `.custom(UUID)`) and clamp via `TextBoxFrame.clamped()`; freeze snapshots the frames (and custom boxes) like every other display setting
- **Resolution adaptivity:** font sizes are authored at a 1080-point reference height (`PresentationManager.referenceScreenHeight`) and multiplied by `fontScale(forHeight:)` / `targetFontScale` at render time. Normalized boxes + scaled fonts = the layout adapts automatically to any resolution / aspect ratio / PPI. Auto-fill must pass SCALED font/padding (`pm.fontSize * pm.targetFontScale`)
- `fittedVerseFontSize(text:boxSize:maxSize:padding:)` expects screen-scaled maxSize/padding; reference/translation/subtitle/custom boxes use `minimumScaleFactor` inside their boxes
- Bible auto-fill measures against `pm.verseBoxPointSize` — `LibraryManager.versesCountThatFits(screenSize:)` expects the verse-box point size, not the screen size
- The old per-section offset/scale/padding transforms and the `VerseTextRenderer` text-bounds overlay are GONE — do not reintroduce content-driven box geometry

### Layout Editor (the design studio)
- `LayoutEditorSheet` in `TextBoxLayout.swift` is THE home for all styling: canvas (drag/resize/click-select boxes, right-click context menus, arrow-key nudge 1%/⇧5%, quick-align TOGGLES that restore the previous frame on second press) + tabbed inspector — Layout / Text / Fundal / Tranziții
- Opened via: toolbar "Layout Editor" button, the `LayoutEditorButton` footer in every preview panel, or Presentation ▸ Layout Editor… (all post `.openLayoutEditor`)
- **The right preview panel is OPERATIONAL ONLY** — preview, navigation, Show/Hide/Black/Freeze/Clear, audio/video transport, Multi-Verse + General quick toggles. New style settings go in the Layout Editor inspector, never back into `StyleQuickSettings`
- Edit Mode (toolbar toggle) shows the drag/resize overlay on the preview card; fine editing happens in the Layout Editor
- Every box shows its DATA SOURCE (inspector "Sursă:", box tooltip, context-menu header). Built-in sections can be hidden (per-profile `visibility`); custom boxes support duplicate/delete
- **Sources are configurable on EVERY text box**: built-in sections default to `"auto"` (their natural field — keep that default) but can be overridden via `pm.sourceRaw(for:)` / `setSourceRaw` to any live field (mainText/reference/translation/subtitle), static text (`pm.staticText(for:)`), or date. Custom boxes default to `"static"`. All rendering goes through `pm.sectionText(_:main:reference:translation:subtitle:now:in:)` / `CustomTextBox.resolvedText` — output passes live values, preview passes its preview values, editor passes samples. A non-"auto" translation-box source bypasses the showTranslationName/isBible gate
- **Media boxes** (`PresentationManager.MediaBox`, stored per profile): image/GIF/video overlays with opacity, corner radius, edge feather (blurred-mask border fade), fit/fill, and `showOnRaw` content filters (always/bible/song/text). Rendering in `MediaBoxViews.swift` — GIFs animate via NSImageView (`animates = true`), videos loop muted via AVQueuePlayer+AVPlayerLooper and PLAY ONLY on the real output (preview/editor show placeholders)
- Picker gotcha: never attach `.help()` (or other modifiers) to tagged segmented-picker items — it breaks tag matching and the tabs stop switching
- Drag gotcha: box drag/resize gestures MUST measure in the overlay's named coordinate space (`TextBoxEditOverlay.canvasSpace`) — measuring in the moving view's own space feeds back into the gesture and the box jitters/shakes

### Sandbox Persistence
- The app is sandboxed (`com.apple.security.app-sandbox`); any user-chosen file that must survive relaunch needs a **security-scoped bookmark**, not a raw path
- Background image: bookmark stored under `pm_backgroundImageBookmark` (set in `setBackgroundImage(from:)`, removed in `removeBackgroundImage()`)
- Media files: `MediaItem.bookmarkData` / `resolvedURL`

### Import Pipeline Rules
- **NEVER spawn child processes (ditto, unzip, …) to read user-selected files** — children of a sandboxed app do NOT inherit the user's file-access grant, so extraction fails. PPTX is read in-process via `ZipArchiveReader` (Services/Import) — central directory + stored/deflate entries through the Compression framework (`COMPRESSION_ZLIB` == raw DEFLATE)
- Import file pickers (Bible + Songs) are intentionally UNRESTRICTED (no allowedContentTypes) — the selected format decides parsing; restricting types made .pptx unselectable. Keep them unrestricted

### Bible format = the GOAT superset (schemaVersion 1.0.0)
- **TopPresenter Bible JSON** (`schemaVersion: "1.0.0"`) is the superset of every format. All rich fields are OPTIONAL (empty when a source lacks them); `text` is always present for display/search. Decoding is version-agnostic + resilient (decodeIfPresent) — the importer keys on field presence, never on `schemaVersion`, so older/plainer files still import.
- Per-verse: `text`, `runs?[]` (`{text, kind, strong?, morph?, gloss?}`, kind = `plain|woc|add|divineName|quote` — carries red-letter + italics + Strong's + interlinear gloss at sub-verse granularity, concatenation reproduces `text`), `footnotes?[]`, `crossReferences?[]` (`{label?, targets[]}`; legacy `{references[]}` still decodes), `hasWordsOfChrist`, `gloss` (verse-level interlinear reading). Per-chapter: `headings?[]` (`{beforeVerse, level, text}`). Per-book: `nameEnglish`, `abbreviation`, `introduction`. Per-translation: `versification`, `canon`, `nameLocal`, `languageName`, `copyright`, `about` (foreword essays), `source`, `year`, `direction`, `hasWordsOfChrist`, `hasStrongs`, `incomplete`. Every level also carries `_extensions` (stored as `extensionsJSON`) so unknown/future fields round-trip. **The SwiftData model stores the COMPLETE superset losslessly** (BibleModule/Book/Chapter/Verse extended 2026-06-16; all additive optionals → lightweight migration); rich arrays as JSON strings (`runsJSON`/`footnotesJSON`/`crossRefsJSON`/`headingsJSON`); shared Codable types (`VerseRun`/`BibleHeading`/`BibleFootnote`/`BibleCrossRef`) in `BibleImportProtocol.swift`; `BibleRichData.encode` stashes them. Import → store → re-export is fully lossless; other formats (OSIS/USFM/MySword/Zefania) import/merge into the same DB and re-export as `toppresenter_json`.
- **Casete (box) Bible sources** (`PresentationManager.sourceOptions` "bible" case → `resolveBoxSource` → `LiveContent`): beyond `mainText`/`reference`/`translation`/`subtitle`, the Bible profile offers `heading`, `footnote`, `crossReference`, `gloss`, `strongs`. `LiveContent` carries these (populated by `showBibleVerse(...)`); `LibraryManager.selectedVerses{Footnotes,CrossRefs,Heading,Gloss,Strongs}` derive them for the live selection.
- **Format feature matrix** (importers now CAPTURE these instead of stripping): headings (OSIS `<title>`, USFM `\s`, eBiblia `headings`); red-letter (OSIS `<q who="Jesus">`, USFM `\wj`, eBiblia `<span class='Isus'>` — all wired into `runs[]`; Zefania/MySword pass through plain — future); footnotes/cross-refs/Strong's are schema-ready. `ExportService.exportToTopPresenterJSON` emits the full v2 schema — import any format, re-export the GOAT.
- **eBiblia data layer (reverse-engineered live, 2026-06-16)**: verses `eb<code>:BB:CCC:VVV`; extras `eb<code>-res:…` with key suffixes `t`(heading)/`x`(cross-ref)/`f`(footnote); front matter/foreword in the single `ebart:b:<code>` article (no separate book-intro keys); name in `ebart:b:t:<code>`. Verse markup variants the scraper's `parseRichVerse` handles: `<span class='Isus'>`→woc, `<em>`→add, inline `word<sr>G..</sr>`→Strong's (KJV), interlinear `<i><wd>W</wd><sr>S</sr><mf>M</mf></i>` (astl) and `<i><wd>W</wd><sr>S</sr><en>gloss</en></i>` (enint)→runs with `strong`/`morph`/`gloss`. `<sr>`/`<mf>` strong+morph exist in KJV and the whole interlinear family, not just interlinears.
- **Red-letter theme** (`PresentationManager.wocStyleEnabled` + `wocColorHex`, theme-persisted, Bible profile only): the output verse box composes `LiveContent.mainRuns` and colors `kind == "woc"` runs; the verse-show path threads `runs:` from the selected `BibleVerse` (single-verse only; multi-verse blocks render plain). Editor row in Text tab. Populated by OSIS/USFM **and** the eBiblia scraper v1.15.0 (`<span class='Isus'>`→woc, `<sr>`→strong, `<mf>`→morph, `<en>`→gloss).
- **Duplicate-on-import** (`ImportService`): `existingBibleModule(code:)` + `BibleConflictResolution` (ask/replace/merge/keepBoth/cancel). `.ask` throws `BibleConflict` (with stats) for the UI dialog; `.merge` fills only missing books/chapters/verses (existing verses win); `.keepBoth` disambiguates the name. BibleView shows the dialog; batch/drag-drop default to `.keepBoth` (non-destructive).

### Adding a Bible Importer
1. Create `Services/Import/MyFormatImporter.swift`
2. Conform to `BibleImporter` — implement `format` and `parse(fileURL:) async throws -> BibleImportResult` (populate the optional rich fields where the format provides them)
3. Add the format case to `SupportedBibleFormat` in `Constants.swift`
4. Register in `ImportService.bibleImporters`

### Adding a Song Importer
Same pattern — conform to `SongImporter`, add to `SupportedSongFormat`, register in `ImportService.songImporters`.

---

### Testing Gotchas
- Run unit tests with `-only-testing:TopPresenterTests` — the UI test target launches the real app and needs Accessibility permissions (it fails/hangs headless)
- Test targets MUST carry `DEVELOPMENT_TEAM = FJHAUWNNBH` like the app target; without it the xctest bundle is ad-hoc signed and dlopen rejects it ("different Team IDs")
- If results look stale (old failures at shifted line numbers, missing new tests), `touch` the test file and rebuild — Xcode occasionally reuses a stale test bundle

## Release & Versioning

### DMG installer UI (v10.13)
The CI DMG is the classic drag-to-Applications window: committed background `Packaging/dmg-background.tiff` (hi-dpi; regenerate via `swift Packaging/generate-dmg-background.swift` + the `tiffutil -cathidpicheck` line in its header) + `create-dmg` with window 660×420, icon size 128, app at (165,190), `--app-drop-link` at (495,190), volume icon from the app bundle. Geometry in the workflow and the generator MUST stay in sync. create-dmg is AppleScript/Finder-driven → the workflow retries 3× and falls back to a plain `hdiutil` DMG (release never dies over cosmetics); a mount-verify step asserts app + Applications link + `.background`.

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

### Signing invariant (DYLD Team-ID crash)
CI re-signs the packaged app UNIFORMLY ad-hoc, inside-out (Sparkle XPCs → Autoupdate →
Updater.app → Sparkle.framework → the .app, `--preserve-metadata=entitlements`, NO
`--options runtime` on ad-hoc) and then `codesign --verify --deep --strict`. Mixed
signatures (e.g. a dev-team app with ad-hoc Sparkle, or vice versa) crash at launch with
"different Team IDs" — never ship a bundle whose nested binaries differ from the outer app.

### Swift 6 patterns (established during the migration — follow them)
- Pure data layers (Constants enums, JSON helpers, Color hex, the whole Bible import
  parse layer) are `nonisolated` — new pure helpers must be too, or @Model accessors
  (nonisolated under Swift 6) can't call them.
- MainActor classes that clean up isolated state on teardown use SE-0371
  `isolated deinit` (AudioPlayerManager, VideoPlayerService, PresentationManager,
  PresentationCommandRouter).
- Bible importers are created FRESH per import (`makeBibleImporter`) — the XML parsers
  hold mutable state; never share importer instances.
- **Batch imports run on `BackgroundImportActor` (@ModelActor)** with chunked per-book
  saves inside `autoreleasepool`; `ImportService.importBible` is nonisolated(nonsending)
  — call it with a context that BELONGS to the calling isolation, never across.

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
| Session (.tpschedule) | `"format"` | `"TopPresenter Session"` |

All TopPresenter exports embed this identifier so importers can reliably distinguish them from generic JSON. Import MUST check the field is PRESENT (strict probe) — resilient decoders default it, which would accept foreign JSON. UTIs: `com.robyrew.toppresenter.theme` (package) + `com.robyrew.toppresenter.schedule` (public.json).

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
