//
//  MediaLibrary.swift
//  TopPresenter
//
//  The media taxonomy + the ONE filter/ordering shared by the Media grid and the
//  right panel's prev/next stepping — both call the same pure functions with the
//  same shared state, so they can never disagree. New media kinds (e.g. PDFs,
//  web pages) slot in as a MediaKind case + a classify rule + an icon.
//

import Foundation

/// Extensible media taxonomy — raw values match `MediaItem.mediaType` in the DB.
///
/// THE media list. There used to be a second one in `DragDropImportHandler`
/// that did not agree with this: it knew `svg`, `ico` and `flv` and this did
/// not, so an `.flv` was a video to the drop handler and an image here. Which
/// list you happened to ask decided what a file was.
nonisolated enum MediaKind: String, CaseIterable, Identifiable, Sendable {
    case image, video, audio, document

    var id: String { rawValue }

    /// The extensions this kind owns. `flv` is deliberately absent: AVPlayer
    /// cannot play it, so importing one produces a library item that never
    /// works. `svg` and `ico` are images the old media list already accepted.
    var fileExtensions: Set<String> {
        switch self {
        case .image: return ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif",
                             "heic", "heif", "webp", "svg", "ico"]
        case .audio: return ["mp3", "wav", "aac", "m4a", "flac", "aiff", "aif",
                             "ogg", "wma", "opus"]
        case .video: return ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm",
                             "mpg", "mpeg"]
        // PDF only, deliberately. It is the one page-based format macOS can
        // render natively (PDFKit), and every tool that makes slides — Keynote,
        // PowerPoint, Google Slides, Word — exports to it. Taking `.pptx` here
        // would mean promising to draw DrawingML, which is a graphics engine
        // rather than a feature; `.pptx` stays a SONG import, where only its
        // text is wanted.
        case .document: return ["pdf"]
        }
    }

    static let allExtensions: Set<String> = allCases.reduce(into: Set<String>()) {
        $0.formUnion($1.fileExtensions)
    }

    /// Segmented-filter label (Toate is handled by the caller's "all" token).
    var filterLabel: String {
        switch self {
        case .image: return String(localized: "Foto", comment: "Media kind filter")
        case .video: return String(localized: "Video", comment: "Media kind filter")
        case .audio: return String(localized: "Audio", comment: "Media kind filter")
        case .document: return String(localized: "PDF", comment: "Media kind filter")
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .document: return "doc.richtext"
        }
    }

    /// This kind is presented one PAGE at a time rather than as a single frame.
    var isPaged: Bool { self == .document }

    /// Reaches the output as a still bitmap rather than a video stream.
    ///
    /// The output used to test `mediaKind == "image"` literally, so a PDF —
    /// which arrives as a fully rendered page in exactly the same slot — failed
    /// the test, fell through to the branch that hands the box to the VIDEO
    /// player, and ended up drawing a placeholder glyph instead of the page.
    var rendersAsStillImage: Bool { self == .image || self == .document }

    /// Same question, from the raw string the live content carries.
    static func rendersAsStillImage(rawValue: String) -> Bool {
        MediaKind(rawValue: rawValue)?.rendersAsStillImage ?? (rawValue == "image")
    }

    /// File-extension classification — the single rule the importer uses.
    ///
    /// Optional, and that is the point. It used to answer `.image` for anything
    /// it did not recognise, which was harmless while only a media picker asked
    /// — the panel had already filtered to media. Now that the folder walk
    /// recurses whole trees, a permissive answer would file every `.docx` and
    /// `.zip` it met as a photo. "Not media" has to be sayable.
    static func classify(extension ext: String) -> MediaKind? {
        let e = ext.lowercased()
        return allCases.first { $0.fileExtensions.contains(e) }
    }
}

/// Pure filtering/ordering helpers over the media library.
enum MediaLibrary {
    /// Kind filter ("all" passes everything) + diacritic/case-insensitive name
    /// match. Input order is preserved (the @Query sorts by importDate desc).
    static func filter(_ items: [MediaItem], kindRaw: String, query: String) -> [MediaItem] {
        let tokens = query
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(separator: " ").map(String.init)
        return items.filter { item in
            if kindRaw != "all" && item.mediaType != kindRaw { return false }
            guard !tokens.isEmpty else { return true }
            let hay = item.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            return tokens.allSatisfy { hay.contains($0) }
        }
    }

    /// The item before/after `item` in `items` (direction -1/+1), clamped to the
    /// ends — powers the panel's prev/next stepping.
    static func neighbor(of item: MediaItem?, in items: [MediaItem], direction: Int) -> MediaItem? {
        guard !items.isEmpty else { return nil }
        guard let item, let idx = items.firstIndex(where: { $0.id == item.id }) else {
            return direction > 0 ? items.first : items.last
        }
        let target = min(max(idx + direction, 0), items.count - 1)
        return items[target]
    }
}

extension MediaItem {
    /// "3:07" / "1:02:45" badge text; nil when the duration is unknown.
    var durationBadge: String? {
        guard durationSeconds > 0.5 else { return nil }
        let total = Int(durationSeconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
