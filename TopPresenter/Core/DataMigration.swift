//
//  DataMigration.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftData

// MARK: - Schema Version 1 (Initial)
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

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

// MARK: - Migration Plan
enum TopPresenterMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        // No migrations yet — will be added as the schema evolves.
        // Example for future use:
        // .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)
        []
    }
}
