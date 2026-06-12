<p align="center">
  <img src="icon.png" width="128" height="128" alt="TopPresenter">
</p>

<h1 align="center">TopPresenter</h1>

<p align="center">
  <strong>Professional Bible &amp; worship presentation for macOS</strong><br>
  Project scripture, lyrics, media, and custom slides to any screen — with a full per-presenter theme engine, built in native SwiftUI &amp; SwiftData.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.7+-007AFF?logo=apple&logoColor=white" alt="macOS 15.7+">
  <img src="https://img.shields.io/badge/Swift-5.0+-F05138?logo=swift&logoColor=white" alt="Swift 5.0+">
  <img src="https://img.shields.io/badge/SwiftUI-Native-6C47FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/SwiftData-Persistence-34C759" alt="SwiftData">
  <img src="https://img.shields.io/badge/Version-0.1.0--alpha-orange" alt="0.1.0-alpha">
  <img src="https://img.shields.io/badge/License-Apache%202.0-yellow" alt="License">
</p>

---

## Highlights

- **100% native macOS** — SwiftUI interface, SwiftData persistence, no Electron, no web views
- **Theme engine (Editor de Teme)** — a full design studio: per-presenter layouts, text boxes, media overlays, backgrounds, and a three-phase transition system
- **Per-presenter profiles** — Bible, Songs, and Slides each have their own boxes, styles, backgrounds, and transitions; the output always renders the live content's profile
- **Universal themes** — one theme snapshots the entire look of all presenters; portable `.tptheme` packages travel between machines with all media embedded
- **Transparent output window** — invisible on the projector when idle; content fades in from transparency and back out
- **Multi-window tabs** (⌘T) — different modules and Bible translations per tab, one shared output
- **Multi-format import** — 6 Bible formats, OpenSong/OpenLyrics/PowerPoint songs, universal drag &amp; drop
- **Resolution adaptive** — layouts are defined in percentages and fonts scale from a 1080p reference; any projector resolution, aspect ratio, or PPI just works

---

## Starter Resources

Download from the [**Resurse** release](https://github.com/RobyRew/TopPresenter/releases/tag/resources-1):

- **6 starter themes** (`.tptheme.zip`) — photo and video backgrounds with preconfigured layouts and transitions: *Cer Nepal, Flori, Galaxie, Minimal, Particule, Plaja*. Unzip, then import from the **Teme** gallery (⤓ button) — selecting the whole folder imports everything inside.
- **Biblia EDC100** — Ediția Dumitru Cornilescu Centenară (Romanian, 66 books, 31,102 verses) in TopPresenter Bible JSON. Import from the Bible module or drag &amp; drop.
  > © British and Foreign Bible Society (BFBS) &amp; Societatea Biblică Interconfesională din România (SBIR), 1924/2024. Distributed for personal and liturgical use.

---

## Features

### 🎨 Theme Engine — *Editor de Teme*

The design studio behind everything you see on screen:

- **Per-presenter layout profiles** — Biblie / Cântece / Slide-uri are edited independently (segmented picker in the editor header, with one-click copy between presenters). Songs have song boxes (*Versuri, Titlu Cântec, Etichetă Strofă*), not Bible ones.
- **Fixed text boxes** — boxes never move or resize with their content; text flows inside them. Drag/resize on the canvas, arrow-key nudge (⇧ = 5%), numeric X/Y/W/H fields, quick-align toggles.
- **Custom text boxes &amp; media boxes** — add static text (church name, CCLI, "Amin."), live-fed boxes, clocks, slide counters, or image/GIF/video overlays with opacity, corner radius, edge feather, and fit/fill.
- **Unified z-order** — one stacking order for every box; drag rows in the always-visible *Casete* list or use the Ordonare context menu. Boxes are recolorable (click the swatch), removable, hideable.
- **Data sources per box** — every box can pull from any live field (lyrics, title, reference, translation, strofă label), static text, date, time, or slide number ("2 / 7"), with per-presenter source catalogs.
- **Slide scope (Afișare)** — show a box on all/first/last slides; songs add **Refren** / **Strofe** (chorus detection from section labels). Song title on the first slide, "Amin." on the last — done.
- **Complete text styling, twice** — Text Global and per-box *Personalizează* share the same 12 options in the same order: Font, Size (≤200pt), Weight, Color, Alignment, Vertical, Opacity, Line spacing, Letter spacing, Transform (MAJUSCULE/minuscule), Padding, Shadow (color + radius), Auto-fit. Every per-box option has a *Global* inherit.
- **Backgrounds** — global + per-presenter overrides; photos, animated GIFs, or looping muted videos.
- **Three-phase transitions** — *Intrare* (transparency → content), *Intermediar* (slide → slide), *Ieșire* (content → transparency on Hide/Clear/ESC). 14 effects (fade, zoom, slides, blur, blur+zoom, fall, 3D flip…), per-phase durations (0–3 s, 0 = instant), per-box overrides with stagger delay, and click-to-preview on the editor canvas.
- **Undo/redo** for every layout change, coalesced per gesture.

### 🖼 Themes

- A theme snapshots the **entire look** — all three presenter profiles plus global text/background settings. Selecting one restyles every presenter at once.
- **Thumbnail gallery** in every panel footer — click to apply, hover to live-preview (never while live), right-click to update/rename/export/delete. Drag sideways to pan.
- **`.tptheme` packages** — directory bundles with `theme.json` + every referenced media file embedded. Export/import is fully portable across machines; importing a folder imports every package inside it.

### 📖 Bible

- **6 import formats** — TopPresenter JSON, OSIS XML, Zefania XML, MySword SQLite, USFM, Unbound Bible
- **Full-text &amp; reference search** — type `John 3:16` or `Gen 1:1-3` to jump directly
- **List view &amp; Grid view** with color-coded book categories
- **Multi-verse selection** (⌘+Click) and **auto-fill** that measures the actual verse box
- **Block navigation** crossing chapter/book boundaries; double-click to go live
- **Export** as TopPresenter JSON, Plain Text, or CSV

### 🎵 Songs &amp; Lyrics

- **4 import formats** — OpenSong XML, OpenLyrics XML, PowerPoint (PPTX &amp; PPT — sandbox-safe, in-process parsing)
- Multi-select file/folder import with auto-detection; each PowerPoint slide becomes a verse with section detection (Verse, Chorus, Bridge)
- **Section quick-jump tabs**, ← → navigation, live slide position (first/last/chorus aware)
- **Export** as TopPresenter JSON, OpenLyrics XML, or Plain Text

### 🖥 Presentation Output

- **Transparent, borderless, fullscreen overlay** — auto-opens on the target screen
- **Single-screen mode** — the window hides after the exit transition and returns on Show
- **Black screen** (⌘B), **Freeze** (⌘F), **Clear/ESC**, split Clear button with Force Touch
- **Ieșire panel** in the right bar: screen, window level, disconnect behavior
- Live clocks tick on screen; full-screen video playback with transport controls

### 🪟 Multi-Window Tabs

⌘T opens native tabs — each with its own module, Bible translation, and selection. One output, driven by whichever tab presses Show.

### 📂 Universal Drag &amp; Drop, Media, Schedule, Quick Search

- Drop any file — Bibles, songs, media auto-classify (mixed drops handled)
- Media library with grid, type filter, thumbnails; audio player (speed, seek), video looping
- Service schedules with running order and go-live; custom text slides
- **⌘K Quick Search** across Bible, songs, and slides

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘K` | Quick search |
| `⌘T` | New tab |
| `⌘B` | Black screen |
| `⌘F` | Freeze / Unfreeze |
| `Return` | Show / Hide content |
| `← →` | Navigate verses / slides |
| `Escape` | Clear output (plays the Ieșire transition) |
| `⌘+Click` | Multi-select verses |
| `⇧⌘Escape` | Clear All |
| `Double-Click` | Instant present |

---

## Supported Formats

| | Formats |
|---|---|
| **Bible import** | TopPresenter JSON · OSIS XML · Zefania XML · MySword SQLite · USFM · Unbound Bible |
| **Song import** | OpenSong XML · OpenLyrics XML · PowerPoint (`.pptx`, `.ppt`) |
| **Media** | Images (jpg, png, gif, heic, tiff, bmp, webp, svg) · Audio (mp3, wav, aac, m4a, flac, ogg, aiff) · Video (mp4, mov, avi, mkv, webm, m4v) |
| **Themes** | `.tptheme` packages (theme.json + embedded media) |
| **Export** | Bible: TopPresenter JSON, TXT, CSV · Songs: TopPresenter JSON, OpenLyrics, TXT · Themes: `.tptheme` |

---

## eBiblia.ro Exporter (userscript)

[`eBiblia-Scraper.user.js`](eBiblia-Scraper.user.js) is a Tampermonkey/Violentmonkey userscript that exports complete Bible translations from [eBiblia.ro](https://ebiblia.ro) into the **TopPresenter Bible JSON** format.

**How it works:**

1. Install the script in Tampermonkey and open ebiblia.ro — a draggable exporter panel appears with every translation your account can access.
2. For each of the 66 books it walks chapter by chapter (1,189 total), first trying the site's own in-page data layer, then falling back to the `a1–a3.ebiblia.net` API endpoints with retries — throttled (~0.8 s/chapter, 1.5 s/book) to stay polite to the server.
3. Each verse is cleaned from raw HTML into plain text, keeping `rawHtml`, a diacritic-free `textNormalized` (for search), cross-references, footnotes, and section headings with levels.
4. The result is a single JSON file (`schemaVersion 1.0.0`, `format: "TopPresenter Bible"`) with translation metadata (code, name, language, copyright) and export stats — downloaded via `GM_download`, ready for direct import into TopPresenter.

The schema is documented in [`TopPresenterBibleImporter.swift`](TopPresenter/Services/Import/TopPresenterBibleImporter.swift); the importer also accepts partial files (any JSON with a `books` array).

> Please respect each translation's copyright — export only for personal and congregational use.

---

## Architecture

```
TopPresenter/
├── Core/                        # PresentationManager (state, profiles, themes,
│                                #   transitions), commands, constants, migration
├── Models/                      # BibleModule, Song, MediaItem, Schedule, LiveContent
├── Services/
│   ├── Import/                  # 9 importers, in-process ZIP reader, drag-drop
│   ├── Export/                  # Multi-format export service
│   ├── Audio/ & Video/          # AVFoundation wrappers
├── Views/
│   ├── Main/                    # Window, toolbar, sidebar, preview panels, tabs
│   ├── Bible/ Songs/ Media/     # Modules
│   ├── Schedule/ CustomSlides/
│   ├── Presentation/            # Output window, Editor de Teme, text-box engine,
│   │                            #   media boxes, theme gallery
│   └── Settings/                # Preferences, projection, shortcuts
└── TopPresenterApp.swift        # @main entry point
```

Key design decisions live in [`AGENTS.md`](AGENTS.md) — fixed text boxes (content never moves a box), per-presenter `LayoutProfile`s, snapshot-based undo, resilient Codable everywhere (stored data survives model growth), and a sandbox-safe bookmark layer.

---

## Building

```bash
git clone https://github.com/RobyRew/TopPresenter.git
cd TopPresenter
open TopPresenter.xcodeproj
```

Select the **TopPresenter** scheme → Build and Run (`⌘R`).

**Requirements:** macOS 15.7+, Xcode 16.3+, Swift 5.0+

Run the unit suite (70+ tests) with:

```bash
xcodebuild -scheme TopPresenter -destination 'platform=macOS' test -only-testing:TopPresenterTests
```

## Releases

- Every push to `main` publishes an **alpha pre-release**; the alpha number counts **per version**, so bumping `MARKETING_VERSION` restarts the series (e.g. `v0.1.0-alpha.1`).
- Stable releases come from final tags (`v1.0.0`): bump `MARKETING_VERSION`, push, then `git tag v1.0.0 && git push origin v1.0.0`.
- The [Resurse release](https://github.com/RobyRew/TopPresenter/releases/tag/resources-1) hosts the starter themes and the EDC100 Bible.

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.
