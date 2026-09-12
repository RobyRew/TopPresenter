//
//  SongFactory.swift
//  TopPresenter
//
//  Making a song by hand, rather than importing one.
//

import Foundation
import SwiftData

/// Creates songs that did not come from a file.
///
/// Until this existed `Song(...)` was only ever called by `ImportService`, so
/// the only way to get a song into the library was to import one — there was no
/// "new song" anywhere in the app. A song written during a service had to be
/// typed into a text file outside TopPresenter and imported back.
@MainActor
enum SongFactory {
    /// Marks the collection hand-written songs go into.
    ///
    /// Matched on rather than the name, because the name is localized and the
    /// operator can rename it; `sourceFormat` is internal and stable, so a
    /// renamed collection still receives the next song instead of a duplicate
    /// appearing beside it.
    nonisolated static let manualSourceFormat = "manual"

    /// The collection new songs go into, created on first use.
    static func defaultCollection(context: ModelContext) -> SongCollection {
        let marker = manualSourceFormat
        var d = FetchDescriptor<SongCollection>(predicate: #Predicate { $0.sourceFormat == marker })
        d.fetchLimit = 1
        if let existing = (try? context.fetch(d))?.first { return existing }
        let created = SongCollection(
            name: String(localized: "Cântecele mele", comment: "Collection holding hand-written songs"),
            collectionDescription: String(localized: "Cântece scrise în TopPresenter.",
                                          comment: "Description of the hand-written songs collection"),
            sourceFormat: manualSourceFormat)
        context.insert(created)
        return created
    }

    /// An empty song with one empty verse, ready to open in the editor.
    ///
    /// The version and its first section are created HERE rather than left to
    /// the editor's `ensureVersion`, which builds sections from the flattened
    /// verse cache — empty for a song that was never imported, so the editor
    /// would open with nothing to type into.
    @discardableResult
    static func create(title: String = "", in collection: SongCollection? = nil,
                       context: ModelContext) -> Song {
        let song = Song(title: title)
        song.collection = collection ?? defaultCollection(context: context)
        song.searchText = Song.makeSearchText(title: title)
        context.insert(song)

        let version = SongVersion(name: String(localized: "Original", comment: "Song version name"), order: 0)
        version.song = song
        song.originalVersionID = version.id.uuidString
        let section = SongSection(sectionKey: "v1", type: "verse",
                                  label: SongSectionLabeling.label(kind: .verse, position: 1, total: 1),
                                  order: 0, lines: [SongLine(text: "")])
        section.version = version
        context.insert(version)

        // The flattened presentation cache mirrors the sections, so the song is
        // presentable the moment it exists rather than only after a first save.
        let verse = SongVerse(label: section.label, verseType: section.type, text: "", order: 0)
        verse.song = song

        try? context.save()
        return song
    }
}
