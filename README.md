<p align="center">
  <img src="icon.png" width="128" height="128" alt="TopPresenter">
</p>

<h1 align="center">TopPresenter</h1>

<p align="center">
  <strong>Professional Bible &amp; worship presentation for macOS</strong><br>
  Project scripture, lyrics, media, and custom slides to any screen — built with native SwiftUI &amp; SwiftData.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-15.7+-007AFF?logo=apple&logoColor=white" alt="macOS 15.7+">
  <img src="https://img.shields.io/badge/Swift-5.0+-F05138?logo=swift&logoColor=white" alt="Swift 5.0+">
  <img src="https://img.shields.io/badge/SwiftUI-Native-6C47FF" alt="SwiftUI">
  <img src="https://img.shields.io/badge/SwiftData-Persistence-34C759" alt="SwiftData">
  <img src="https://img.shields.io/badge/License-MIT-yellow" alt="License">
</p>

---

## Highlights

- **100% native macOS** — SwiftUI interface, SwiftData persistence, no Electron, no web views
- **Transparent output window** — invisible on the projector when idle, no forced black screen
- **Multi-format Bible import** — 6 formats including OSIS, Zefania, MySword, USFM, and more
- **Song lyrics from PowerPoint** — import PPTX/PPT files directly, one slide per verse
- **Smart auto-fill** — automatically fits as many verses as the screen allows
- **Universal drag & drop** — drop any file and the app figures out what to do with it
- **Runs on a single screen or with a projector** — adapts automatically

---

## Features

### 📖 Bible

- **6 import formats** — TopPresenter JSON, OSIS XML, Zefania XML, MySword SQLite, USFM, Unbound Bible
- **Full-text & reference search** — type `John 3:16` or `Gen 1:1-3` to jump directly
- **List view & Grid view** — classic sidebar or BibleShow-style button grid with breadcrumbs
- **10 color-coded book categories** — Law, History, Wisdom, Prophets, Gospels, Epistles, etc.
- **Multi-verse selection** (⌘+Click) and **auto-fill** based on available screen space
- **Block navigation** — ← → skip by block size; cross-chapter/book boundaries seamlessly
- **Double-click** any verse to send it live instantly
- **Export** as TopPresenter JSON, Plain Text, or CSV

### 🎵 Songs & Lyrics

- **4 import formats** — OpenSong XML, OpenLyrics XML, PowerPoint (PPTX & PPT)
- **PowerPoint import** — each slide becomes a verse, auto-detects sections (Verse, Chorus, Bridge)
- **Collection-based organization** with directory import
- **Full-text search** by title or lyrics content
- **Section navigation** with quick-jump tabs and ← → keyboard arrows
- **Export** as TopPresenter JSON, OpenLyrics XML, or Plain Text

### 🖥 Presentation Output

- **Auto-opens on the target screen** — transparent, borderless, fullscreen overlay
- **Screen selector** — pick which connected display to project on
- **Window level control** — Normal, Floating, Always on Top, or Behind Desktop
- **Live preview** matching the target screen's aspect ratio and resolution
- **Black screen** (⌘B), **Freeze** (⌘F), and **Clear** (Escape) controls
- **Auto-hide on built-in screen** — when presenting on the laptop's own display, Escape hides the window entirely; it reappears when new content is sent
- **Smooth transitions** with configurable duration
- **All settings persist** across sessions

### 🎨 Styling & Layout

- **Font family, size, color** per section (verse text, reference, subtitle)
- **Background color** and **background image** with opacity control
- **Text shadow**, **alignment**, **line spacing**, and **padding**
- **Inline settings panel** — collapsible, context-aware per content type

### 🔧 Context-Sensitive Preview Panel

| Content | Panel |
|---------|-------|
| **Bible** | Preview, verse nav, auto-fill, Show/Hide, Black/Freeze, style settings |
| **Songs** | Preview, section nav with quick-jump tabs, Show/Hide, Black/Freeze, style settings |
| **Media** | Preview, Use as Background / Play, Black, minimal settings |
| **Schedule** | Preview, item nav, Go Live/Hide, running order, Black/Freeze |
| **Custom Slides** | Preview, slide nav, Show/Hide, Black/Freeze, style settings |

### 🖱 Native macOS Toolbar

Toolbar items adapt to the active content type — module/collection picker, search, import/delete, screen selector, Black, and Clear are always available.

### 📂 Universal Drag & Drop

Drop files onto the window — the app auto-classifies:
- **Bible files** (JSON, XML, SQLite, USFM, TXT) → Bible import
- **Song files** (XML, PPTX, PPT) → Song import
- **Media files** (images, audio, video) → Media Library
- **Mixed drops** → Media imports silently; Bible/Songs open the batch import dialog

### 🔲 Split Clear Button

- **Click** to clear the output
- **▼ Dropdown** — Clear Screen, Clear & Go Black, Clear & Go to Bible/Songs/Media, Clear All
- **Right-click** — same options as context menu
- **Force Touch** — configurable action with haptic feedback

### 🎵 Audio & Video

- Built-in audio player with volume, speed (0.5×–2×), seek, and skip (±10s)
- Video playback (MP4, MOV, MKV, AVI, WebM) with loop control

### 📋 Schedule, Custom Slides & Media Library

- **Service schedules** with date, running order, and double-click to go live
- **Custom text slides** with title and subtitle
- **Media library** with grid view, type filter, thumbnails, and security-scoped bookmarks

### ⚡ Quick Search (⌘K)

Global search overlay — search across Bible, songs, and slides from anywhere. Keyboard navigation + Return to present.

---

## Keyboard Shortcuts

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
| `Double-Click` | Instant present |
| `Force Touch` | Configurable action |

---

## Supported Formats

### Bible Import
| Format | Extensions |
|--------|-----------|
| TopPresenter JSON | `.json` |
| OSIS XML | `.xml`, `.osis` |
| Zefania XML | `.xml`, `.zef` |
| MySword SQLite | `.mybible`, `.bbl.mybible` |
| USFM | `.usfm`, `.sfm` |
| Unbound Bible | `.txt`, `.utf8` |

### Song Import
| Format | Extensions |
|--------|-----------|
| OpenSong XML | `.xml` |
| OpenLyrics XML | `.xml` |
| PowerPoint | `.pptx`, `.ppt` |

### Media (drag & drop)
| Type | Extensions |
|------|-----------|
| Images | jpg, png, gif, heic, tiff, bmp, webp, svg |
| Audio | mp3, wav, aac, m4a, flac, ogg, aiff |
| Video | mp4, mov, avi, mkv, webm, m4v |

### Export
| Content | Formats |
|---------|---------|
| Bible | TopPresenter JSON, Plain Text, CSV |
| Songs | TopPresenter JSON, OpenLyrics XML, Plain Text |

---

## Architecture

```
TopPresenter/
├── Core/                        # App state, commands, constants, migration
├── Models/                      # BibleModule, Song, MediaItem, Schedule, LiveContent
├── Services/
│   ├── Import/                  # 9 importers + drag-drop handler
│   ├── Export/                  # Multi-format export service
│   ├── Audio/                   # AVAudioPlayer wrapper
│   └── Video/                   # AVPlayer wrapper
├── Views/
│   ├── Main/                    # Window, toolbar, sidebar, preview panels
│   ├── Bible/                   # List & grid views, export sheet
│   ├── Songs/                   # Collections, search, lyrics
│   ├── Media/                   # Grid, thumbnails, filters
│   ├── Schedule/                # Service order management
│   ├── CustomSlides/            # Text slide editor
│   ├── Presentation/            # Transparent fullscreen output + verse renderer
│   ├── Import/                  # Batch import/export sheets
│   └── Settings/                # Preferences, keyboard shortcuts
└── TopPresenterApp.swift        # @main entry point
```

---

## eBiblia.ro Scraper

Included: `eBiblia-Scraper.user.js` — a Tampermonkey userscript that scrapes Bible text from [eBiblia.ro](https://ebiblia.ro) and exports it in TopPresenter JSON format for direct import.

---

## Building

```bash
git clone https://github.com/RobyRew/TopPresenter.git
cd TopPresenter
open TopPresenter.xcodeproj
```

Select the **TopPresenter** scheme → Build and Run (`⌘R`).

**Requirements:** macOS 15.7+, Xcode 16.3+, Swift 5.0+

## License

MIT — see [LICENSE](LICENSE) for details.
