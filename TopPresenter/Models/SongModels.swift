//
//  SongModels.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation
import SwiftData

// MARK: - Song Collection
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

// MARK: - Song
@Model
final class Song {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String
    var copyright: String
    var ccliNumber: String
    var key: String
    var tempo: String
    var songNumber: String
    var tags: String // comma-separated

    var collection: SongCollection?

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

    var sortedVerses: [SongVerse] {
        verses.sorted { $0.order < $1.order }
    }

    var verseLabels: [String] {
        sortedVerses.map { $0.label }
    }
}

// MARK: - Song Verse
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
