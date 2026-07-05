//
//  SessionModels.swift
//  TopPresenter
//
//  A session (ServiceSchedule) stores INTENT, not frozen text: each item carries a
//  stable reference to real library content in `ScheduleItem.payloadJSON`, resolved
//  back to live content at present time. Stable keys: songs → HistoryStore.songKey
//  (CCLI-first), bible → translation abbreviation + book/chapter/verse numbers,
//  media → MediaItem.id with a name fallback. All Codable is resilient
//  (decodeIfPresent + defaults) so old payloads keep decoding as fields grow.
//

import Foundation

// MARK: - Stable reference payload (stored in ScheduleItem.payloadJSON)

struct SessionItemPayload: Codable, Equatable {
    // Bible — translation abbreviation + numeric coordinates.
    var translation = ""
    var bookNumber = 0
    var bookName = ""
    var chapter = 0
    var verseStart = 0
    var verseEnd = 0

    // Song — HistoryStore.songKey + display title; optional specific arrangement.
    var songKey = ""
    var songTitle = ""
    var versionID = ""      // UUID string; "" = the song's active version
    var versionName = ""    // fuzzy re-match fallback after re-import

    // Media — MediaItem id + name fallback.
    var mediaID = ""
    var mediaName = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        translation = try c.decodeIfPresent(String.self, forKey: .translation) ?? ""
        bookNumber = try c.decodeIfPresent(Int.self, forKey: .bookNumber) ?? 0
        bookName = try c.decodeIfPresent(String.self, forKey: .bookName) ?? ""
        chapter = try c.decodeIfPresent(Int.self, forKey: .chapter) ?? 0
        verseStart = try c.decodeIfPresent(Int.self, forKey: .verseStart) ?? 0
        verseEnd = try c.decodeIfPresent(Int.self, forKey: .verseEnd) ?? 0
        songKey = try c.decodeIfPresent(String.self, forKey: .songKey) ?? ""
        songTitle = try c.decodeIfPresent(String.self, forKey: .songTitle) ?? ""
        versionID = try c.decodeIfPresent(String.self, forKey: .versionID) ?? ""
        versionName = try c.decodeIfPresent(String.self, forKey: .versionName) ?? ""
        mediaID = try c.decodeIfPresent(String.self, forKey: .mediaID) ?? ""
        mediaName = try c.decodeIfPresent(String.self, forKey: .mediaName) ?? ""
    }

    var isEmpty: Bool { self == SessionItemPayload() }

    func encodedJSON() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    static func decode(fromJSON json: String) -> SessionItemPayload {
        guard let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(SessionItemPayload.self, from: data) else {
            return SessionItemPayload()
        }
        return p
    }
}

// MARK: - What a tab hands to „Adaugă la sesiune"

enum SessionItemDraft {
    case bible(translation: String, bookNumber: Int, bookName: String,
               chapter: Int, verseStart: Int, verseEnd: Int,
               displayReference: String, snapshotText: String)
    /// Whole song + optional specific arrangement; slides derive at present time.
    case song(Song, version: SongVersion?)
    case media(MediaItem)
    case text(title: String, content: String)
    case blank
}

// MARK: - Present-time resolution result

enum SessionResolution {
    case bible(text: String, reference: String, translationName: String)
    case song(Song, version: SongVersion?)
    case media(MediaItem)
    case text(title: String, content: String)
    case blank
    /// Localized reason the reference no longer resolves (deleted/renamed content).
    case missing(String)

    var isMissing: Bool {
        if case .missing = self { return true }
        return false
    }
}
