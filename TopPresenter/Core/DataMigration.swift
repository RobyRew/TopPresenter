//
//  DataMigration.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftData

// MARK: - Schema Version 1 (Initial)
enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            BibleModule.self,
            BibleBook.self,
            BibleChapter.self,
            BibleVerse.self,
            SongCollection.self,
            Song.self,
            SongVerse.self,
            PresentationSlide.self,
            ServiceSchedule.self,
            ScheduleItem.self,
            MediaItem.self,
            PresentationStyle.self,
        ]
    }
}

// MARK: - Schema Version 2 (rich Songs: Songbook + SongVersion + SongSection)
//
// Purely additive over V1 — new @Model types and new Song properties with inline
// defaults — so V1→V2 is a lightweight migration (no data loss, no custom code).
// SongVerse is retained as the flattened presentation cache of a song's active version.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            BibleModule.self,
            BibleBook.self,
            BibleChapter.self,
            BibleVerse.self,
            SongCollection.self,
            Song.self,
            SongVerse.self,
            Songbook.self,
            SongVersion.self,
            SongSection.self,
            PresentationSlide.self,
            ServiceSchedule.self,
            ScheduleItem.self,
            MediaItem.self,
            PresentationStyle.self,
        ]
    }
}

// MARK: - Migration Plan
enum TopPresenterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        // Intentionally empty. The SchemaV1→V2 change is purely additive and is handled by
        // SwiftData's automatic lightweight inference (the container is created without a
        // staged plan). Staged `.lightweight`/`.custom` stages cannot express adding new
        // @Model entities + relationships and throw at construction.
        []
    }
}
