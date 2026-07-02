<p align="center">
  <img src="icon.png" width="150" alt="TopPresenter — Liquid Glass app icon">
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
- **Multi-format import** — 6 Bible formats, 6 song formats (incl. the GOAT TopPresenter Song JSON with versions + chords), universal drag &amp; drop
- **Chords &amp; live transpose** — a song-only *Acorduri* casetá renders chords over the lyrics with independent styling, plus on-the-fly transpose, capo suggestions, and combinable repeat markers
- **Presentation history** — every song verse and Bible passage shown is tracked (per service, dwell-gated), with per-verse/book roll-ups and CSV/JSON export — kept in its own store
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

- **Per-presenter layout profiles** — Biblie / Cântece / Slide-uri are edited independently (segmented picker in the editor header, with one-click copy between presenters). Songs have song boxes (*Versuri, Titlu Cântec, Etichetă Strofă, Acorduri*), not Bible ones.
- **Chords casetá + live transpose** — *Acorduri* is a song-only box that renders the lyrics with chords above them (each chord aligned over its syllable, for any font). It ships hidden — turn it on for a stage/musician layout and it replaces the plain lyrics at the verse position. The chord **letters have their own independent style** (font, size, weight, color) separate from the lyrics, both edited in the box's Text tab. A transpose/capo control in the song header changes key on the fly (±semitone or pick any of 12 keys), with **capo suggestions** and the recommended keys from the song's metadata — all **display-only**, the saved chords are never touched.
- **Repeat markers** — mark a repeated strofă/refren with a **bracket** (`/: :/`, `‖: :‖`, `|: :|`) and/or a **count** (`(×2)`, `bis/ter`) — the two combine (`‖: … :‖ (×2)`). They appear consistently on the filmstrip, previews, theme preview and the live output (including the chord chart, with chords kept aligned).
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
- **The GOAT format** — TopPresenter Bible JSON **v1.0.0** is a superset of every format: section headings, footnotes, cross-references, Strong's numbers, poetry, and **red-letter** (words of Christ) all round-trip through import → store → export. Fields are optional; nothing is lost importing OSIS/USFM and re-exporting.
- **Red-letter theme** — highlight the words spoken by Jesus in any color, per theme (Editor de Teme ▸ Text ▸ *Cuvintele lui Isus*). Populated from OSIS/USFM Bibles that mark them.
- **Smart duplicate handling** — importing a Bible whose code already exists prompts **Combină / Înlocuiește / Păstrează ambele / Anulează**; *Combină* fills in only the chapters/verses you're missing.
- **Language auto-correction** — a Bible whose declared language contradicts its actual script (e.g. a Greek interlinear mistagged Romanian) is filed under the correct language group on import.
- **Full-text &amp; reference search** — type `John 3:16` or `Gen 1:1-3` to jump directly
- **List view &amp; Grid view** with color-coded book categories
- **Multi-verse selection** (⌘+Click) and **auto-fill** that measures the actual verse box
- **Block navigation** crossing chapter/book boundaries; double-click to go live
- **Export** as TopPresenter JSON (full v2 schema), Plain Text, or CSV

### 🎵 Songs &amp; Lyrics

- **The GOAT format** — **TopPresenter Song JSON v2.0.0** is one file per song and a superset of every source: per-song versions, sections with **inline chords** (ChordPro positions) and **bilingual translation lines**, arrangement/play-order, section **repeat counts**, linked media, and rich metadata all round-trip through import → store → export. Source-specific extras (chord/capo charts, song analysis, external ids) ride along losslessly in `_extensions`.
- **Multiple versions per song** — a song groups several renditions (e.g. 3 Romanian variants, an ES translation). Each version owns its own metadata (title shown, authors, language, key/capo/tempo, copyright, CCLI, songbook, style, themes, notes, repeat marker) and **inherits the original's by default**, with a per-version toggle to customize.
- **6 import formats** — TopPresenter Song JSON, OpenSong XML, OpenLyrics XML (translations + chords), ChordPro, plain text, and PowerPoint (PPTX &amp; PPT — sandbox-safe, in-process parsing, with filename titles + chorus-reuse detection).
- **Recursive folder import** for thousands of files, with progress, format auto-detection, and duplicate handling (add as new version / keep both / skip). Only TopPresenter-supported file types are scanned and the walk runs off the main thread, so picking a huge folder never freezes the app.
- **Scalable browser** — list ⇄ grid with theme-rendered thumbnails, instant indexed search, sort header chips (A-Z · Artist · Carte · Limbă · Recente), and filters (collection, language, media, **verified-only**).
- **Verified flag** — mark a song as checked &amp; good; a green seal shows in the list/grid/detail, you can filter to verified-only (or search `verificat`/`✓`), and it round-trips through GOAT export/import.
- **Song studio editor** — two-pane visual editor with a live theme-rendered preview that follows the section you click, version tabs, color-coded section cards (drag-to-reorder, duplicate, ×N repeat, inline-chord mode), per-version metadata, a **Verifică** toggle, **Renunță** (revert all edits), and a per-song **change log** (what changed, when).
- **Rendered slide filmstrip** — sections auto-split to fit the screen (configurable lines/slide); **Edit** button + song facts (CCLI, BPM, language, import source…) above it; click to project, double-click or ▶ to go live; each slide has a **PREVIEW** button and a delete (with confirm); bilingual + repeat markers (`/: :/`, `‖: :‖`, `|: :|`, `(×N)`, `bis/ter`) applied per the theme.
- **Export** as TopPresenter Song JSON (one file per song or a whole folder), OpenLyrics XML, or Plain Text.

### 🖥 Presentation Output

- **Transparent, borderless, fullscreen overlay** — auto-opens on the target screen
- **Single-screen mode** — the window hides after the exit transition and returns on Show
- **Black screen** (⌘B), **Freeze** (⌘F), **Clear/ESC**, split Clear button with Force Touch
- **Ieșire panel** in the right bar: screen, window level, disconnect behavior
- Live clocks tick on screen; full-screen video playback with transport controls

### 🪟 Multi-Window Tabs

⌘T opens native tabs — each with its own module, Bible translation, and selection. Tabs are titled by **type + (lang) version + reference** (e.g. *Bible - (RO) EDC100 - Ioan 3:16*, *Songs — Înaintea Ta venim*), or rename any tab manually. One output, driven by whichever tab presses Show.

### 🧭 Sidebar &amp; History

- **Sidebar** — content sections (Bible, Songs, Media, Schedule, Custom Slides) up top, with **History · Settings · Account** pinned in a utility group at the bottom. **Account** opens a local profile/preferences screen (presenter name, church, defaults — no online login).
- **Presentation History** (sidebar ▸ History, ⌘Y) — a record of everything shown to the audience: songs and Bible passages, how many times (per service/session), and when. Verses are logged only after a short on-screen dwell, so fast scrubbing doesn't pollute it. Drill into a song for its session timeline + per-verse counts; Bible passages roll up by translation → book → chapter. Stored in its **own** database (never part of the song/bible JSON) with its **own** CSV / JSON export. Each song's detail panel shows its history at a glance.

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
| `⌘1`–`⌘5` | Jump to Bible / Songs / Media / Schedule / Custom Slides |
| `⌘Y` | Presentation History |
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
| **Song import** | TopPresenter Song JSON · OpenSong XML · OpenLyrics XML · ChordPro (`.cho`, `.crd`, `.chordpro`) · Plain text (`.txt`) · PowerPoint (`.pptx`, `.ppt`) |
| **Media** | Images (jpg, png, gif, heic, tiff, bmp, webp, svg) · Audio (mp3, wav, aac, m4a, flac, ogg, aiff) · Video (mp4, mov, avi, mkv, webm, m4v) |
| **Themes** | `.tptheme` packages (theme.json + embedded media) |
| **Export** | Bible: TopPresenter JSON, TXT, CSV · Songs: TopPresenter JSON, OpenLyrics, TXT · Themes: `.tptheme` |

---

## eBiblia.ro Exporter (userscript)

[`eBiblia-Scraper.user.js`](scrapers/eBiblia-Scraper.user.js) is a Tampermonkey/Violentmonkey userscript that exports complete Bible translations from [eBiblia.ro](https://ebiblia.ro) into the **TopPresenter Bible JSON** format.

It exports straight to **TopPresenter Bible JSON** — clean verse text plus red-letter (words of Christ), section headings, cross-references, footnotes, Strong's numbers, morphology, interlinear glosses, and full translation metadata (name, year, copyright, foreword). Toggle the rich-content groups to keep files lean. **⏬ Toate** exports every translation your account can open at once, organized into per-language folders. Works on Chrome, Firefox and Safari.

> Please respect each translation's copyright — export only for personal and congregational use.

---

## Song Scrapers — melodia · ResurseCrestine · cantaricrestine · WorshipTogether

Dependency-free scrapers that export worship songs (Romanian + English/Spanish/Portuguese) into **TopPresenter Song JSON** — one file per song, ready for recursive folder-import. Source-specific extras are preserved losslessly under each song's `_extensions`, surviving import → store → export. Every scraper's output is verified to import back into TopPresenter with its chords, keys, authors and metadata intact.

### melodia.ro

- **[`melodia-scraper.mjs`](scrapers/melodia-scraper.mjs)** (Node 18+, resumable) — enumerates the sitemap and exports every song: lyrics with **inline chords at exact character positions**, key, tempo (BPM) and time signature, authors (*Muzică / Versuri*), copyright, composed year, keyword tags, and the song structure as a play-order **arrangement** (identical re-rendered sections are de-duplicated and reused). melodia's *Anatomia Evangheliei* analysis, available keys and a computed per-instrument capo recommendation are kept under `_extensions.melodia`. Chords are stored **once** in the song's own key — every other key (C, C#, Db, D…) is derivable by transposition. Run: `node melodia-scraper.mjs --out ./songs`.
- **[`melodia-scraper.user.js`](scrapers/melodia-scraper.user.js)** (Tampermonkey) — same export, but reads melodia's React-rendered capo charts to capture the **exact** guitar **and** ukulele fingerings (shape, capo, frets, fingers, barre). One-click ⬇ button (Alt+T).

### ResurseCrestine

- **[`resursecrestine-scraper.mjs`](scrapers/resursecrestine-scraper.mjs)** / **[`.user.js`](scrapers/resursecrestine-scraper.user.js)** — crawl the full [resursecrestine.ro/cantece](https://www.resursecrestine.ro) catalog (~28k songs) into TopPresenter Song JSON: rich sections (verse/chorus + `/: :/` repeat markers), with author / album / theme metadata and bible reference carried across.
- **[`resursecrestine-acorduri-scraper.mjs`](scrapers/resursecrestine-acorduri-scraper.mjs)** — the **chords** section (`/acorduri`, ~4.2k songs). Each acord page holds the full lyrics *with* chords, so every file is a complete song-with-chords: the chord-over-lyric charts are parsed into **positional chords** (`{sym, pos}`), with chorus detection, author, and an inferred key. A `matchKey` is carried so you can dedupe against the lyrics-only `/cantece` songs.

### cantaricrestine.ro — "Cântări Creștine în PowerPoint"

- **[`cantaricrestine-scraper.mjs`](scrapers/cantaricrestine-scraper.mjs)** (Node 18+, resumable) — uses the site's public JSON API (`api.php`; `token` is just a random anti-bot value) to export all **~9.5k songs**, organized into **per-book folders**. Each song carries its lyrics (parsed into sections with `//: ://` repeats), book/number, and `_extensions.cantaricrestine` (id, date added, downloads/views, PowerPoint URL). It also **downloads every PowerPoint** (`.ppt`/`.pptx`) next to the JSON, and writes a `_completeness.json` (which songs have lyrics vs are PowerPoint-only). Run `--no-ppt` for JSON only. Disk-full-resilient (always writes the JSON; flags any PowerPoint it couldn't save).
- **[`cantaricrestine-scraper.user.js`](scrapers/cantaricrestine-scraper.user.js)** (Tampermonkey) — pick a book (or *Toate*) and download a single importable TopPresenter Songs bundle, straight from the API.

### worshiptogether.com — modern worship (EN / ES / PT)

- **[`worshiptogether-scraper.mjs`](scrapers/worshiptogether-scraper.mjs)** (Node 18+, resumable) — enumerates the per-language sitemaps (`sitemap-{en,es,pt}.xml`, ~4.7k songs) and parses each song's ChordPro markup into **positional chords** (`{sym, pos}`) with section detection and play-order **arrangement** (`REPEAT CHORUS` → reuse). The richest source: it captures **CCLI #**, original + recommended keys, BPM, tempo, **themes**, **scripture references** and writers/copyright (under `_extensions.worshipTogether`). Organized into `en/`, `es/`, `pt/` folders.
- **[`worshiptogether-scraper.user.js`](scrapers/worshiptogether-scraper.user.js)** (Tampermonkey) — exports the current song from your **logged-in** session by reading the rendered ChordPro DOM. ⬇ button / Alt+T.

> These are copyrighted modern worship songs — for personal/congregational use; projecting the lyrics still requires your church's **CCLI** license.

### Keeping your library up to date

Re-running a scraper into the **same output folder** fetches only the songs you don't already have — it skips every `.json` already present (`--resume`, on by default). So `node melodia-scraper.mjs --out ./songs` next month grabs just the newly-added songs; the existing thousands skip in seconds. Keep the output folder as your archive so the scraper knows what's missing.

How each source signals change (so you know what a re-run can and can't catch):

| Source | What exists (enumerate) | New items | Edited items |
|---|---|---|---|
| **melodia.ro** | `sitemap.xml` (per-song `<lastmod>`) | ✅ new slug | ✅ via `<lastmod>` |
| **cantaricrestine.ro** | `api.php` (per-song `data_adaugare`) | ✅ new id | ✅ via `data_adaugare` |
| **worshiptogether.com** | `sitemap-{en,es,pt}.xml` (per-song `<lastmod>`) | ✅ new slug | ✅ via `<lastmod>` |
| **resursecrestine** | alphabetical index pages | ✅ new slug/id | ❌ no timestamps — re-fetch manually |
| **eBiblia** | live catalog `window.app.BIBLES` | ✅ new code | ❌ no version field — re-export manually |

A plain re-run (`--resume`) always tops up **new** songs. Detecting **edits** to songs you already have is possible where the source carries a timestamp (melodia's `<lastmod>`, cantaricrestine's `data_adaugare`); for resursecrestine/eBiblia you'd re-fetch the specific item by hand.

> Scraped corpora are kept local (git-ignored), not committed. Please respect each song's copyright — export only for personal and congregational use.

---

## Roadmap

**Shipped**
- [x] Native SwiftUI + SwiftData app — Bible, Songs, Slides, Media, Schedules
- [x] Per-presenter theme engine: layouts, transitions, custom & media boxes, portable `.tptheme`
- [x] 6 Bible + 6 song import formats; lossless TopPresenter Bible **and** Song JSON (GOAT) round-trip — songs carry versions, chords, bilingual lines, arrangement &amp; repeats
- [x] Red-letter, footnotes, cross-references, headings, Strong's & morphology stored in the DB
- [x] Three-column Bible reader (Books · Chapters · Verses) with language groups & canon badges
- [x] Drag-and-drop batch import (files *and* folders, recursive); eBiblia exporter
- [x] Liquid Glass app icon (Icon Composer `.icon` + `.icns` fallback)

**Planned**
- [ ] Stage / monitor display — next slide, clock, speaker notes
- [ ] Remote control from phone or tablet
- [ ] Schedules → full service planning & running order
- [ ] Interlinear + Strong's display in the Bible reader (data already captured)
- [ ] NDI / Syphon output for video mixers
- [ ] Cloud sync for themes & libraries
- [ ] Fully localized UI

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
- The [Bible Library release](https://github.com/RobyRew/TopPresenter/releases/tag/bibles-1) bundles **all 70 Bible translations** (17 languages) as TopPresenter JSON — red-letter, Strong's, headings, cross-references and metadata included.
- The [Themes release](https://github.com/RobyRew/TopPresenter/releases/tag/themes-1) bundles the starter `.tptheme` pack (Default, Cer Nepal, Galaxie, Minimal) with backgrounds embedded.

## License

Apache 2.0 — see [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.
