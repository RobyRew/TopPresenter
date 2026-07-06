//
//  SongModels.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation
import SwiftData

// MARK: - JSON helpers (blobs keep the rich layer flexible without exploding the table count)

// nonisolated: pure JSON round-trips — @Model accessors (nonisolated under
// Swift 6) call these, so they must not be MainActor-bound.
nonisolated func tpEncodeJSON<T: Encodable>(_ value: T, fallback: String) -> String {
    guard let data = try? JSONEncoder().encode(value),
          let string = String(data: data, encoding: .utf8) else { return fallback }
    return string
}

nonisolated func tpDecodeJSON<T: Decodable>(_ string: String, as type: T.Type, fallback: T) -> T {
    guard let data = string.data(using: .utf8),
          let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
    return value
}

// MARK: - Value Types (encoded into linesJSON / mediaJSON)

/// A chord placed at a character offset within a line (ChordPro-style).
struct SongChord: Codable, Hashable {
    var sym: String          // e.g. "G", "D/F#"
    var pos: Int             // character offset into the line text

    init(sym: String, pos: Int) {
        self.sym = sym
        self.pos = pos
    }
}

/// One lyric line: text + optional chords + optional per-language translations (bilingual).
struct SongLine: Codable, Hashable {
    var text: String
    var chords: [SongChord]
    var translations: [String: String]   // languageCode -> translated line

    init(text: String, chords: [SongChord] = [], translations: [String: String] = [:]) {
        self.text = text
        self.chords = chords
        self.translations = translations
    }
}

/// One coarse entry in a song's change log (edit-log only; never restored).
struct SongEditEntry: Codable, Hashable {
    var date: Date
    var summary: String

    init(date: Date = .now, summary: String) {
        self.date = date
        self.summary = summary
    }
}

/// A linked media asset (audio negative / karaoke / background).
struct SongMediaRef: Codable, Hashable {
    var role: String         // "negative" | "karaoke" | "audio" | "background"
    var kind: String         // "audio" | "video" | "image"
    var filename: String
    var bookmark: String?    // base64 security-scoped bookmark, optional

    init(role: String, kind: String, filename: String, bookmark: String? = nil) {
        self.role = role
        self.kind = kind
        self.filename = filename
        self.bookmark = bookmark
    }
}

// MARK: - Songbook (canonical hymnal a song may optionally belong to)
@Model
final class Songbook {
    @Attribute(.unique) var id: UUID
    var name: String
    var publisher: String = ""
    var language: String = ""
    var year: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Song.songbook)
    var songs: [Song] = []

    init(name: String, publisher: String = "", language: String = "", year: String = "") {
        self.id = UUID()
        self.name = name
        self.publisher = publisher
        self.language = language
        self.year = year
    }
}

// MARK: - Song Collection (import grouping / library)
@Model
final class SongCollection {
    @Attribute(.unique) var id: UUID
    var name: String
    var collectionDescription: String
    var sourceFormat: String
    var importDate: Date

    @Relationship(deleteRule: .cascade, inverse: \Song.collection)
    var songs: [Song] = []

    init(name: String, collectionDescription: String = "", sourceFormat: String) {
        self.id = UUID()
        self.name = name
        self.collectionDescription = collectionDescription
        self.sourceFormat = sourceFormat
        self.importDate = Date()
    }

    var sortedSongs: [Song] {
        songs.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Song (conceptual work; owns one or more versions)
@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String                 // legacy combined author (display fallback)
    var copyright: String
    var ccliNumber: String
    var key: String
    var tempo: String
    var songNumber: String
    var tags: String                   // comma-separated

    // Rich metadata (v2; additive — inline defaults keep the migration lightweight)
    var titlesJSON: String = "[]"      // alternate titles / aliases
    var language: String = ""
    var themesJSON: String = "[]"
    var style: String = ""             // style-of-singing (imn/coral/contemporan…)
    var songbookNumber: String = ""
    var authorWords: String = ""
    var authorMusic: String = ""
    var authorTranslation: String = ""
    var notes: String = ""
    var mediaJSON: String = "[]"       // [SongMediaRef]
    var extensionsJSON: String = "{}"  // future params (_extensions)
    var searchText: String = ""        // denormalized lowercase (title+aliases+author+lyrics)
    var verified: Bool = false         // user-confirmed "checked & good" (round-trips through GOAT)
    var modifiedDate: Date = Date.now  // last edit — drives sort + the change log
    var editLogJSON: String = "[]"     // [SongEditEntry] — coarse change log (internal, not exported)
    var sourceFile: String = ""        // filename this song was imported from (e.g. "1000-tongues.json")
    /// UUID string of the ORIGINAL version — the default: presented, searched
    /// first, source of slides. "" = fall back to the first version by order.
    /// Round-trips through GOAT ("original": true on the version dict).
    var originalVersionID: String = "" // additive, inline default — lightweight migration

    var collection: SongCollection?
    var songbook: Songbook?

    /// Rich layer — the source of truth for lyrics.
    @Relationship(deleteRule: .cascade, inverse: \SongVersion.song)
    var versions: [SongVersion] = []

    /// Flattened presentation cache of the active version (legacy consumers: presenter / search / schedule).
    /// Regenerated from the active `SongVersion`; never hand-edited.
    @Relationship(deleteRule: .cascade, inverse: \SongVerse.song)
    var verses: [SongVerse] = []

    init(
        title: String,
        author: String = "",
        copyright: String = "",
        ccliNumber: String = "",
        key: String = "",
        tempo: String = "",
        songNumber: String = "",
        tags: String = ""
    ) {
        self.id = UUID()
        self.title = title
        self.author = author
        self.copyright = copyright
        self.ccliNumber = ccliNumber
        self.key = key
        self.tempo = tempo
        self.songNumber = songNumber
        self.tags = tags
    }

    var sortedVersions: [SongVersion] { versions.sorted { $0.order < $1.order } }
    /// The ORIGINAL (default) version: the one marked via `originalVersionID`,
    /// else the first by order. Presenting other versions stays possible by
    /// explicit selection (`selectedSongVersion`).
    var activeVersion: SongVersion? {
        if !originalVersionID.isEmpty,
           let original = versions.first(where: { $0.id.uuidString == originalVersionID }) {
            return original
        }
        return sortedVersions.first
    }

    var sortedVerses: [SongVerse] { verses.sorted { $0.order < $1.order } }
    var verseLabels: [String] { sortedVerses.map { $0.label } }

    // Decoded convenience accessors
    var titles: [String] {
        get { tpDecodeJSON(titlesJSON, as: [String].self, fallback: []) }
        set { titlesJSON = tpEncodeJSON(newValue, fallback: "[]") }
    }
    var themes: [String] {
        get { tpDecodeJSON(themesJSON, as: [String].self, fallback: []) }
        set { themesJSON = tpEncodeJSON(newValue, fallback: "[]") }
    }
    var media: [SongMediaRef] {
        get { tpDecodeJSON(mediaJSON, as: [SongMediaRef].self, fallback: []) }
        set { mediaJSON = tpEncodeJSON(newValue, fallback: "[]") }
    }
    var editLog: [SongEditEntry] {
        get { tpDecodeJSON(editLogJSON, as: [SongEditEntry].self, fallback: []) }
        set { editLogJSON = tpEncodeJSON(newValue, fallback: "[]") }
    }

    /// Best-effort web link captured from `_extensions` — scrapers store the song's
    /// source page URL (e.g. `_extensions.melodia.url`). nil when none is present.
    var webURL: URL? {
        guard let data = extensionsJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func find(_ any: Any) -> String? {
            if let dict = any as? [String: Any] {
                for key in ["url", "sourceUrl", "songUrl", "pageUrl", "link", "href"] {
                    if let s = dict[key] as? String, s.hasPrefix("http") { return s }
                }
                for (_, v) in dict { if let f = find(v) { return f } }
            }
            return nil
        }
        return find(obj).flatMap { URL(string: $0) }
    }

    /// Denormalized, lowercased search blob used by the scalable library browser.
    static func makeSearchText(
        title: String, titles: [String] = [], author: String = "", authorWords: String = "",
        songNumber: String = "", songbookNumber: String = "", lyrics: String = ""
    ) -> String {
        (([title] + titles + [author, authorWords, songNumber, songbookNumber, lyrics]))
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}

// MARK: - Song Version (a specific rendition: 3 RO versions, an ES translation, an alt arrangement…)
@Model
final class SongVersion {
    @Attribute(.unique) var id: UUID
    var name: String = ""              // distinguishing label, e.g. "Versiunea clasică"
    // Per-version metadata. When empty, the song-level value is used instead (overrides).
    var displayTitle: String = ""      // title shown on screen for THIS version (e.g. a translation)
    var author: String = ""
    var language: String = ""
    var key: String = ""
    var capo: Int = 0
    var tempo: String = ""
    var timeSignature: String = ""
    var copyright: String = ""
    var ccliNumber: String = ""
    var source: String = ""
    var repeatStyle: String = ""       // repeat-marker style override ("" = use the global default)
    // Per-version overrides for the song's shared ("comun") fields. Used only when
    // overridesMetadata is true; empty otherwise (the original's values are inherited).
    var titlesJSON: String = "[]"      // alternate titles / aliases
    var authorWords: String = ""
    var authorMusic: String = ""
    var authorTranslation: String = ""
    var style: String = ""
    var songbookNumber: String = ""
    var themesJSON: String = "[]"
    var notes: String = ""
    var songbookName: String = ""      // per-version songbook name (book the version is from)
    /// When false, this version inherits the original (first) version's metadata; its own
    /// override fields are ignored. The "Original" version is always treated as authoritative.
    var overridesMetadata: Bool = false
    var arrangementJSON: String = "[]" // [sectionKey] play order (section reuse)
    var order: Int

    var song: Song?

    @Relationship(deleteRule: .cascade, inverse: \SongSection.version)
    var sections: [SongSection] = []

    init(
        name: String = "",
        order: Int = 0,
        language: String = "",
        key: String = "",
        capo: Int = 0,
        tempo: String = "",
        timeSignature: String = "",
        copyright: String = "",
        ccliNumber: String = "",
        source: String = ""
    ) {
        self.id = UUID()
        self.name = name
        self.order = order
        self.language = language
        self.key = key
        self.capo = capo
        self.tempo = tempo
        self.timeSignature = timeSignature
        self.copyright = copyright
        self.ccliNumber = ccliNumber
        self.source = source
    }

    var sortedSections: [SongSection] { sections.sorted { $0.order < $1.order } }

    var arrangement: [String] {
        get { tpDecodeJSON(arrangementJSON, as: [String].self, fallback: []) }
        set { arrangementJSON = tpEncodeJSON(newValue, fallback: "[]") }
    }

    var titles: [String] {
        get { tpDecodeJSON(titlesJSON, as: [String].self, fallback: []) }
        set { titlesJSON = tpEncodeJSON(newValue, fallback: "[]") }
    }
    var themes: [String] {
        get { tpDecodeJSON(themesJSON, as: [String].self, fallback: []) }
        set { themesJSON = tpEncodeJSON(newValue, fallback: "[]") }
    }

    /// Sections expanded in `arrangement` order (repeats a reused chorus, etc.).
    /// Falls back to plain section order when no arrangement is defined.
    var arrangedSections: [SongSection] {
        let order = arrangement
        guard !order.isEmpty else { return sortedSections }
        let byKey = Dictionary(sections.map { ($0.sectionKey, $0) }, uniquingKeysWith: { a, _ in a })
        let mapped = order.compactMap { byKey[$0] }
        return mapped.isEmpty ? sortedSections : mapped
    }
}

// MARK: - Song Section (verse / chorus / bridge … with rich lines)
@Model
final class SongSection {
    @Attribute(.unique) var id: UUID
    var sectionKey: String        // "v1", "c", "b1" — referenced by a version's arrangement
    var type: String              // verse/chorus/bridge/prechorus/intro/ending/tag/interlude
    var label: String
    var order: Int
    var repeatCount: Int = 1      // sung N times — rendered with the theme's repeat-marker style
    var linesJSON: String = "[]"  // [SongLine] — text + chords + translations
    var plainText: String         // flattened lines (quick render + search)

    var version: SongVersion?

    init(sectionKey: String, type: String, label: String, order: Int, repeatCount: Int = 1, lines: [SongLine] = []) {
        self.id = UUID()
        self.sectionKey = sectionKey
        self.type = type
        self.label = label
        self.order = order
        self.repeatCount = repeatCount
        self.plainText = lines.map { $0.text }.joined(separator: "\n")
        self.linesJSON = tpEncodeJSON(lines, fallback: "[]")
    }

    var lines: [SongLine] {
        get { tpDecodeJSON(linesJSON, as: [SongLine].self, fallback: []) }
        set {
            linesJSON = tpEncodeJSON(newValue, fallback: "[]")
            plainText = newValue.map { $0.text }.joined(separator: "\n")
        }
    }
}

// MARK: - Song Verse (flattened presentation cache; see Song.verses)
@Model
final class SongVerse {
    @Attribute(.unique) var id: UUID
    var label: String  // e.g., "Verse 1", "Chorus", "Bridge"
    var verseType: String  // "verse", "chorus", "bridge", "pre-chorus", "tag", "ending", "other"
    var text: String
    var order: Int

    var song: Song?

    init(label: String, verseType: String = "verse", text: String, order: Int) {
        self.id = UUID()
        self.label = label
        self.verseType = verseType
        self.text = text
        self.order = order
    }
}

// MARK: - Song Search Result (non-persisted)
struct SongSearchResult: Identifiable, Hashable {
    let id = UUID()
    let songID: UUID
    let title: String
    let author: String
    let collectionName: String
    let matchedVerse: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SongSearchResult, rhs: SongSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}
