# TopPresenter

A professional Bible and worship presentation app for macOS, built with native SwiftUI and SwiftData.

![macOS 15.7+](https://img.shields.io/badge/macOS-15.7+-blue)
![Swift 5.0+](https://img.shields.io/badge/Swift-5.0+-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

### � Bible Module System
- **Import Bibles** in OSIS XML and Zefania XML formats
- **Modular importer architecture** — easy to add new formats
- **Full-text search** across all imported modules
- **Reference search** (e.g., "John 3:16", "Gen 1:1-3")
- **Book/Chapter/Verse navigation** with Old/New Testament sections
- **Multi-verse selection** (Cmd+Click) for displaying multiple verses
- **Auto-fill verses** — automatically select as many verses as fit on screen
- **Block navigation** — when auto-fill is active, ← → skip by the full block size
- **Cross-chapter navigation** — seamlessly continue to the next/previous chapter or book
- **Double-click** any verse to instantly send it to presentation output
- **Remember last Bible module** across sessions

### 🎵 Song/Lyrics System
- **Import songs** in OpenSong XML and OpenLyrics XML formats
- **Collection-based organization**
- **Directory import** — import entire song folders at once
- **Full-text search** by title or lyrics content
- **Verse-by-verse navigation** with section labels (Verse, Chorus, Bridge, etc.)
- **Keyboard navigation** (← → arrows) between song sections

### 🖥 Multi-Screen Presentation
- **Separate presentation output window** for projectors/external screens
- **Screen selector** — choose which display to present on
- **Live preview** in the control panel (always shows what's coming next)
- **Show/Hide toggle** — single button to push content live or clear it
- **Black screen** toggle (⌘B)
- **Freeze display** — locks the output completely (content + styling), preview still updates so you can prepare the next slide
- **Smooth transitions** with configurable duration
- **Full-screen presentation** with .plain window style
- **All settings persist across sessions** (font, colors, background, etc.)

### 🎨 Presentation Styling
- Configurable **font family, size, and color**
- **Background color** and **background image** with opacity control
- **Text shadow** with adjustable radius
- **Text alignment** (left, center, right)
- **Line spacing** and **padding** controls
- **Inline quick settings panel** — all controls accessible right in the preview panel
- **Collapsible sections** — Text & Font, Background, Display & Output, Multi-Verse, General

### 🎵 Audio Player
- Built-in **audio playback** with transport controls
- **Volume control** with mute toggle
- **Playback speed** (0.5x to 2x)
- **Seek** with progress bar
- **Skip forward/backward** (10 seconds)

### 🎬 Video Support
- **Video playback** with AVKit
- **Volume, speed, and loop** controls
- Playback of common video formats (MP4, MOV, etc.)

### 📋 Service Schedule
- **Create service schedules** with date
- **Add items** (Bible, Song, Text, Blank) to the schedule
- **Double-click** to present schedule items
- **Reusable** across services

### 📝 Custom Slides
- **Create and edit** custom text slides
- **Rich text editing** with title and subtitle
- **Instant presentation** with one click

### 📁 Media Library
- **Import images, audio, and video** files
- **Grid view** with thumbnails
- **Filter by type** (All, Images, Audio, Video)
- **Set as background** with one click
- **Detail panel** with preview

## Architecture

```
TopPresenter/
├── Core/                          # App-wide state and configuration
│   ├── AppState.swift             # Global app state (navigation, alerts)
│   ├── Constants.swift            # Enums, defaults, book name mappings
│   ├── LibraryManager.swift       # Bible & song navigation/search state
│   └── PresentationManager.swift  # Live presentation state and display settings
│
├── Models/                        # SwiftData persistent models
│   ├── BibleModels.swift          # BibleModule, Book, Chapter, Verse
│   ├── SongModels.swift           # SongCollection, Song, SongVerse
│   └── PresentationModels.swift   # Slides, MediaItem, Style, Schedule, LiveContent
│
├── Services/
│   ├── Import/                    # Modular import system
│   │   ├── BibleImportProtocol.swift    # Protocol for Bible importers
│   │   ├── SongImportProtocol.swift     # Protocol for Song importers
│   │   ├── ImportService.swift          # Central coordinator with importer registry
│   │   ├── OSISBibleImporter.swift      # OSIS XML parser
│   │   ├── ZefaniaBibleImporter.swift   # Zefania XML parser
│   │   ├── OpenSongImporter.swift       # OpenSong XML parser
│   │   └── OpenLyricsImporter.swift     # OpenLyrics XML parser
│   ├── Audio/
│   │   └── AudioPlayerManager.swift     # AVAudioPlayer wrapper
│   └── Video/
│       └── VideoPlayerService.swift     # AVPlayer wrapper
│
├── Views/
│   ├── Main/                      # Main window layout
│   │   ├── MainControlView.swift  # Primary window with toolbar
│   │   ├── SidebarView.swift      # Navigation sidebar
│   │   ├── ContentAreaView.swift  # Content router
│   │   └── PreviewPanelView.swift # Live preview + controls + settings
│   ├── Bible/
│   │   └── BibleView.swift        # Bible module, search, navigation, verses
│   ├── Songs/
│   │   └── SongsView.swift        # Song collections, search, lyrics
│   ├── Media/
│   │   └── MediaView.swift        # Media library grid and detail
│   ├── Schedule/
│   │   └── ScheduleView.swift     # Service schedule management
│   ├── CustomSlides/
│   │   └── CustomSlidesView.swift # Custom text slide editor
│   ├── Presentation/
│   │   └── PresentationOutputView.swift  # External screen output
│   └── Settings/
│       └── SettingsView.swift     # App preferences
│
└── TopPresenterApp.swift          # @main entry point, window groups
```

## Adding a New Bible Format

1. Create a new file in `Services/Import/` (e.g., `MySwordBibleImporter.swift`)
2. Implement the `BibleImporter` protocol:

```swift
final class MySwordBibleImporter: BibleImporter {
    let format: SupportedBibleFormat = .mySword  // Add to enum first

    func parse(fileURL: URL) async throws -> BibleImportResult {
        // Your parsing logic here
    }
}
```

3. Add the format to `SupportedBibleFormat` enum in `Constants.swift`
4. Register the importer in `ImportService.swift`:
```swift
let mySwordImporter = MySwordBibleImporter()
importers[mySwordImporter.format] = mySwordImporter
```

## Adding a New Song Format

Same pattern — implement `SongImporter` protocol and register in `ImportService`.

## Localization

All user-visible strings use `String(localized:comment:)` for localization support.
Add new languages by creating `.lproj` folders with `Localizable.strings` files.

## Requirements

- macOS 15.7+
- Xcode 16.3+
- Swift 5.0+

## Building

1. Clone the repository:
   ```bash
   git clone https://github.com/RobyRew/TopPresenter.git
   ```
2. Open `TopPresenter.xcodeproj` in Xcode
3. Select the TopPresenter scheme
4. Build and Run (⌘R)

## License

MIT License — see [LICENSE](LICENSE) for details.

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘⇧P | Open presentation window |
| ⌘B | Toggle black screen |
| ⌘K | Quick search overlay |
| Return | Show/Hide current content on screen |
| ← → | Navigate verses (skips by block when auto-fill is active) |
| Escape | Clear presentation |
| ⌘+Click | Multi-select Bible verses |
| Double-Click | Instantly present item |
