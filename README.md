# TopPresenter

A professional Bible and worship presentation app for macOS, built with native SwiftUI and SwiftData. Designed for churches, worship teams, and anyone who needs to project scripture, lyrics, media, and custom slides to an external screen.

![macOS 15.7+](https://img.shields.io/badge/macOS-15.7+-blue)
![Swift 5.0+](https://img.shields.io/badge/Swift-5.0+-orange)
![SwiftUI](https://img.shields.io/badge/SwiftUI-Native-purple)
![SwiftData](https://img.shields.io/badge/SwiftData-Persistence-green)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Features

### 📖 Bible Module System
- **8 import formats**: TopPresenter JSON, OSIS XML, Zefania XML, MySword SQLite, USFM, Unbound Bible, and directory-based imports
- **Full-text search** across all imported modules
- **Reference search** — type "John 3:16" or "Gen 1:1-3" to jump directly
- **Two navigation modes**:
  - **List view** — Book/Chapter/Verse sidebar with Old/New Testament sections
  - **Grid view** — BibleShow-style button grid: Books → Chapters → Verses with breadcrumb navigation
- **Color-coded book categories** (10 categories: Law, History, Wisdom, Major Prophets, Minor Prophets, Gospels, Acts, Pauline Epistles, General Epistles, Prophecy) with Romanian labels — configurable in Settings
- **Multi-verse selection** (⌘+Click) for displaying multiple verses at once
- **Auto-fill verses** — automatically selects as many verses as fit on screen based on font size and layout
- **Block navigation** — when auto-fill is active, ← → skip by the full block size
- **Cross-chapter/book navigation** — seamlessly continue to next/previous chapter or book (visual indicators at boundaries)
- **Double-click** any verse to instantly send it to the output
- **Remember last Bible module** across sessions
- **Export** in TopPresenter JSON, Plain Text, and CSV formats (with format identifiers)

### 🎵 Song/Lyrics System
- **4 import formats**: OpenSong XML, OpenLyrics XML, PowerPoint (PPTX and PPT)
- **PowerPoint import** — each slide becomes a verse, auto-detects section labels (Verse, Chorus, Bridge, Pre-Chorus)
- **Collection-based organization** — songs grouped into named collections
- **Directory import** — import entire song folders at once
- **Full-text search** by title or lyrics content
- **Verse-by-verse navigation** with section labels and quick-jump tabs
- **Keyboard navigation** (← → arrows) between song sections
- **Export** in TopPresenter JSON (with format identifier), OpenLyrics XML, and Plain Text

### 🖥 Presentation Output
- **Auto-opens on the target screen** at launch — transparent, borderless, fullscreen
- **Transparent by default** — when nothing is shown, the output is invisible on the projector; no forced black background
- **Screen selector** — choose which connected display to project on
- **Window level control** — Normal, Floating, Always on Top, or Behind Desktop
- **Live preview** in the control panel with **target screen aspect ratio** (matches the actual projector resolution)
- **Preview background** is black for readability with a "Transparent" badge indicator when the output has no background
- **Background is optional** — toggle "Enable Background" to add a solid color, or keep it transparent
- **Black screen** toggle (⌘B)
- **Freeze display** — locks the output completely (content + all styling); preview still updates so you can prepare the next slide
- **Smooth transitions** with configurable duration
- **All settings persist across sessions** (font, colors, background, window level, etc.)

### 🎨 Presentation Styling
- Configurable **font family, size, and color**
- **Optional background color** and **background image** with opacity control
- **Text shadow** with adjustable radius
- **Text alignment** (left, center, right)
- **Line spacing** and **padding** controls
- **Inline quick settings panel** — collapsible sections shown per content type:
  - **Bible**: Text & Font, Background, Display & Output, Multi-Verse
  - **Songs**: Text & Font, Background, Display & Output
  - **Media**: Background, Display & Output
  - **Custom Slides**: Text & Font, Background, Display & Output
  - **Schedule**: No style settings (uses item-specific styles)

### 🔧 Context-Sensitive Right Panel
The right preview panel adapts to the active content type:

| Content | Panel Shows |
|---------|-------------|
| **Bible** | Preview card, verse nav (← →), auto-fill, Show/Hide, Black/Freeze, style settings |
| **Songs** | Preview card, verse section nav with quick-jump tabs, Show/Hide, Black/Freeze, style settings |
| **Media** | Media preview, action buttons (Use as Background / Play), Black, minimal settings |
| **Schedule** | Preview card, item nav, Go Live/Hide, running order list, Black/Freeze |
| **Custom Slides** | Preview card, slide nav (← →), Show/Hide, Black/Freeze, style settings |

### 🔲 Split Clear Button
The clear button is a unified split button:
- **Left half** — click to clear the output
- **Right half (▼)** — opens a dropdown with options:
  - Clear Screen
  - Clear & Go Black
  - Clear & Go to Bible / Songs / Media
  - Clear All (output + selection + auto-fill)
- **Right-click** — same options as context menu
- **Force Touch** (trackpad deep press) — configurable action (Clear All / Go Black / Go to Bible / Songs / Freeze) with haptic feedback

### 🖱 Native macOS Toolbar
All toolbar items are in the **native macOS window toolbar** (like Finder/Safari), with content-type-specific items:

| Content | Toolbar Items |
|---------|--------------|
| **Bible** | Module picker, Search field, Grid/List toggle, Import, Delete |
| **Songs** | Collection picker, Search field, Import, Delete |
| **Media** | Type filter (All/Images/Audio/Video), Add Media |
| **Schedule** | New Schedule, Add Item |
| **Custom Slides** | New Slide |
| **Always** | Screen selector, Black Screen, Clear |

### 📂 Universal Drag & Drop
Drop **any supported file** onto the app window — it auto-detects the type:
- **Bible files** (JSON, XML, SQLite, USFM, TXT) → Bible import
- **Song files** (XML, PPTX, PPT) → Song import
- **Media files** (images, audio, video) → Direct import to Media Library
- **Mixed drops** → Media imports silently, Bible/Songs open the batch import dialog

### 🎵 Audio Player
- Built-in **audio playback** with transport controls
- **Volume control** with mute toggle
- **Playback speed** (0.5x to 2x)
- **Seek** with progress bar
- **Skip forward/backward** (10 seconds)

### 🎬 Video Support
- **Video playback** with AVKit
- **Volume, speed, and loop** controls
- Common video formats (MP4, MOV, MKV, AVI, WebM)

### 📋 Service Schedule
- **Create service schedules** with date
- **Add items** (Bible, Song, Text, Blank) to the schedule
- **Double-click** to present schedule items
- **Running order** in the preview panel with live indicator

### 📝 Custom Slides
- **Create and edit** custom text slides
- **Rich text editing** with title and subtitle
- **Instant presentation** with one click

### 📁 Media Library
- **Import images, audio, and video** files
- **Grid view** with thumbnails
- **Filter by type** (All, Images, Audio, Video)
- **Set as background** with one click
- **Security-scoped bookmarks** — media references survive app restarts and file moves

### ⚡ Quick Search (⌘K)
- **Global search overlay** — search across Bible verses, songs, and slides from anywhere
- **Instant results** with keyboard navigation
- **Press Return** to present the selected result

### ⚙️ Settings
Organized in three tabs:

- **Interfață (Interface)** — Startup behavior, confirm before delete, verse display options, Force Touch action picker
- **Biblie (Bible)** — Module preferences, content display toggles, Book Category settings (enable/disable category colors and labels with preview grid)
- **Import / Export** — Format detection, metadata inclusion, pretty-print options

### 🗃 Data Architecture
- **SwiftData** with `VersionedSchema` and `SchemaMigrationPlan` — safe schema evolution
- **Cached sorted verses** — avoids re-sorting on every access for performance
- **UserDefaults persistence** for all display settings (didSet pattern)
- **Format identifiers** on all exports: `"format": "TopPresenter Bible"`, `"format": "TopPresenter Songs"` — importers check these for reliable auto-detection

---

## Architecture

```
TopPresenter/
├── Core/
│   ├── AppState.swift              # Global navigation state
│   ├── AppCommands.swift           # Menu bar commands + notification routing
│   ├── Constants.swift             # Formats, defaults, book mappings, categories
│   ├── DataMigration.swift         # VersionedSchema + SchemaMigrationPlan
│   ├── LibraryManager.swift        # Bible & song navigation, search, verse caching
│   └── PresentationManager.swift   # Live output state, freeze, display settings
│
├── Models/
│   ├── BibleModels.swift           # BibleModule → Book → Chapter → Verse
│   ├── SongModels.swift            # SongCollection → Song → SongVerse
│   └── PresentationModels.swift    # MediaItem, PresentationSlide, Schedule, LiveContent
│
├── Services/
│   ├── Import/
│   │   ├── ImportService.swift           # Central coordinator with importer registry
│   │   ├── DragDropImportHandler.swift   # Universal file classification & auto-import
│   │   ├── BibleImportProtocol.swift     # Protocol for Bible importers
│   │   ├── SongImportProtocol.swift      # Protocol for Song importers
│   │   ├── TopPresenterBibleImporter.swift # Native JSON (with format identifier)
│   │   ├── OSISBibleImporter.swift       # OSIS XML
│   │   ├── ZefaniaBibleImporter.swift    # Zefania XML
│   │   ├── MySwordBibleImporter.swift    # MySword SQLite
│   │   ├── USFMBibleImporter.swift       # USFM directory
│   │   ├── UnboundBibleImporter.swift    # Tab-delimited text
│   │   ├── OpenSongImporter.swift        # OpenSong XML songs
│   │   ├── OpenLyricsImporter.swift      # OpenLyrics XML songs
│   │   └── PowerPointSongImporter.swift  # PPT & PPTX (native Swift parser)
│   ├── Export/
│   │   └── ExportService.swift           # Bible + Song export (JSON, XML, TXT, CSV)
│   ├── Audio/
│   │   └── AudioPlayerManager.swift      # AVAudioPlayer wrapper
│   └── Video/
│       └── VideoPlayerService.swift      # AVPlayer wrapper
│
├── Views/
│   ├── Main/
│   │   ├── MainControlView.swift         # Window + native toolbar + drag & drop
│   │   ├── SidebarView.swift             # Navigation sidebar
│   │   ├── ContentAreaView.swift         # Content router (Bible/Songs/Media/etc.)
│   │   ├── PreviewPanelView.swift        # Panel router + shared components
│   │   ├── QuickSearchOverlay.swift      # ⌘K global search
│   │   └── Panels/
│   │       ├── BiblePreviewPanel.swift       # Bible-specific right panel
│   │       ├── SongsPreviewPanel.swift       # Songs-specific right panel
│   │       ├── MediaPreviewPanel.swift       # Media-specific right panel
│   │       ├── SchedulePreviewPanel.swift    # Schedule-specific right panel
│   │       └── CustomSlidesPreviewPanel.swift # Slides-specific right panel
│   ├── Bible/
│   │   ├── BibleView.swift               # List + grid view, book categories, search
│   │   └── BibleExportSheet.swift        # Export dialog
│   ├── Songs/
│   │   └── SongsView.swift               # Collections, search, lyrics
│   ├── Media/
│   │   └── MediaView.swift               # Media grid + detail
│   ├── Schedule/
│   │   └── ScheduleView.swift            # Service schedule management
│   ├── CustomSlides/
│   │   └── CustomSlidesView.swift        # Text slide editor
│   ├── Presentation/
│   │   └── PresentationOutputView.swift  # Transparent fullscreen output window
│   ├── Import/
│   │   ├── BatchImportSheet.swift        # Multi-file import dialog
│   │   └── BatchExportSheet.swift        # Multi-format export dialog
│   └── Settings/
│       ├── SettingsView.swift            # Tabbed preferences (Interface/Bible/Import)
│       └── KeyboardShortcutsSheet.swift  # Shortcuts reference
│
└── TopPresenterApp.swift                 # @main, window groups, menu commands
```

---

## Import Formats

### Bible
| Format | Extensions | Notes |
|--------|-----------|-------|
| TopPresenter JSON | `.json` | Native format with cross-references, footnotes, categories |
| OSIS XML | `.xml`, `.osis` | Open Scripture Information Standard |
| Zefania XML | `.xml`, `.zef` | Zefania Bible format |
| MySword | `.mybible`, `.bbl.mybible` | SQLite database |
| USFM | `.usfm`, `.sfm` | Directory of per-book files |
| Unbound Bible | `.txt`, `.utf8` | Tab-delimited text |

### Songs
| Format | Extensions | Notes |
|--------|-----------|-------|
| OpenSong XML | `.xml` | OpenSong worship format |
| OpenLyrics XML | `.xml` | OpenLyrics standard |
| PowerPoint | `.pptx`, `.ppt` | Each slide → verse, auto-detects sections |

### Media (drag & drop)
| Type | Extensions |
|------|-----------|
| Images | jpg, jpeg, png, gif, heic, heif, tiff, bmp, webp, svg |
| Audio | mp3, wav, aac, m4a, flac, ogg, wma, aiff |
| Video | mp4, mov, avi, mkv, wmv, flv, webm, m4v |

---

## Export Formats

### Bible
| Format | Identifier | Extension |
|--------|-----------|-----------|
| TopPresenter JSON | `"format": "TopPresenter Bible"` | `.json` |
| Plain Text | Header comment | `.txt` |
| CSV | Header row | `.csv` |

### Songs
| Format | Identifier | Extension |
|--------|-----------|-----------|
| TopPresenter JSON | `"format": "TopPresenter Songs"` | `.json` |
| OpenLyrics XML | XML comment | `.xml` |
| Plain Text | Header comment | `.txt` |

All TopPresenter exports include a `"format"` identifier at the top of the file for reliable auto-detection on re-import.

---

## Adding a New Bible Format

1. Create a new file in `Services/Import/` (e.g., `MyFormatImporter.swift`)
2. Implement the `BibleImporter` protocol:
```swift
final class MyFormatImporter: BibleImporter {
    let format: SupportedBibleFormat = .myFormat

    func parse(fileURL: URL) async throws -> BibleImportResult {
        // Parse the file and return books/chapters/verses
    }
}
```
3. Add the format to `SupportedBibleFormat` enum in `Constants.swift`
4. Register in `ImportService.swift`

### Adding a New Song Format

Same pattern — implement `SongImporter` protocol and register in `ImportService`.

---

## eBiblia.ro Scraper

Included: `eBiblia-Scraper.user.js` — a Tampermonkey userscript that scrapes Bible text from eBiblia.ro and exports it in TopPresenter JSON format for direct import.

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘K | Quick search overlay (global) |
| ⌘B | Toggle black screen |
| Return | Show/Hide current content on output |
| ← → | Navigate verses/slides (skips by block when auto-fill active) |
| Escape | Clear presentation output |
| ⌘+Click | Multi-select Bible verses |
| ⇧⌘Escape | Clear All (output + selection + auto-fill) |
| Double-Click | Instantly present item |
| Force Touch | Configurable action (Settings → Interface) |

---

## Requirements

- macOS 15.7+
- Xcode 16.3+
- Swift 5.0+

## Building

```bash
git clone https://github.com/RobyRew/TopPresenter.git
cd TopPresenter
open TopPresenter.xcodeproj
# Select the TopPresenter scheme → Build and Run (⌘R)
```

## License

MIT License — see [LICENSE](LICENSE) for details.
