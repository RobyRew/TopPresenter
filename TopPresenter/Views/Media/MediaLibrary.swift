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
enum MediaKind: String, CaseIterable, Identifiable {
    case image, video, audio

    var id: String { rawValue }

    /// Segmented-filter label (Toate is handled by the caller's "all" token).
    var filterLabel: String {
        switch self {
        case .image: return String(localized: "Foto", comment: "Media kind filter")
        case .video: return String(localized: "Video", comment: "Media kind filter")
        case .audio: return String(localized: "Audio", comment: "Media kind filter")
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        }
    }

    /// File-extension classification — the single rule the importer uses.
    static func classify(extension ext: String) -> MediaKind {
        let e = ext.lowercased()
        let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "tif", "heic", "heif", "webp"]
        let audioExts: Set<String> = ["mp3", "wav", "aac", "m4a", "flac", "aiff", "aif", "ogg", "wma", "opus"]
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm", "mpg", "mpeg"]
        if audioExts.contains(e) { return .audio }
        if videoExts.contains(e) { return .video }
        if imageExts.contains(e) { return .image }
        return .image   // permissive fallback, matching the old importer
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
