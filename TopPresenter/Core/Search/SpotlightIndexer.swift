//
//  SpotlightIndexer.swift
//  TopPresenter
//
//  Publishes songs + sessions to the SYSTEM Spotlight index so they're
//  findable outside the app (⌘Space). Reindexing piggybacks on SearchIndex
//  rebuilds (already debounced, fired only on .libraryDidChange) — no extra
//  invalidation plumbing. Clicking a result deep-links back via
//  NSUserActivity (CSSearchableItemActionType), handled in TopPresenterApp.
//  Native CoreSpotlight only — no entitlements required.
//

import Foundation
import CoreSpotlight

nonisolated enum SpotlightIndexer {
    static let songDomain = "songs"
    static let sessionDomain = "sessions"

    /// Replace both domains with the fresh projections, off-main, batched.
    static func reindex(songs: [SongIndexEntry], sessions: [SessionIndexEntry]) {
        Task.detached(priority: .utility) {
            let index = CSSearchableIndex.default()
            try? await index.deleteSearchableItems(withDomainIdentifiers: [songDomain, sessionDomain])

            var items: [CSSearchableItem] = []
            items.reserveCapacity(songs.count + sessions.count)
            for s in songs {
                let attr = CSSearchableItemAttributeSet(contentType: .text)
                attr.title = s.title
                attr.contentDescription = s.author.isEmpty ? s.firstLine : s.author
                attr.keywords = [s.songbookName, s.language, s.collectionName].filter { !$0.isEmpty }
                items.append(CSSearchableItem(uniqueIdentifier: "song:\(s.id.uuidString)",
                                              domainIdentifier: songDomain, attributeSet: attr))
            }
            for s in sessions {
                let attr = CSSearchableItemAttributeSet(contentType: .text)
                attr.title = s.name
                attr.contentDescription = s.date.formatted(date: .complete, time: .omitted)
                items.append(CSSearchableItem(uniqueIdentifier: "session:\(s.id.uuidString)",
                                              domainIdentifier: sessionDomain, attributeSet: attr))
            }

            var start = 0
            while start < items.count {
                let end = min(start + 1000, items.count)
                try? await index.indexSearchableItems(Array(items[start..<end]))
                start = end
            }
        }
    }

    /// "song:<uuid>" / "session:<uuid>" → (kind, id). nil for anything else.
    static func parse(identifier: String) -> (kind: String, id: UUID)? {
        let parts = identifier.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              parts[0] == "song" || parts[0] == "session",
              let id = UUID(uuidString: String(parts[1])) else { return nil }
        return (String(parts[0]), id)
    }
}
