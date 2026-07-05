//
//  SessionService.swift
//  TopPresenter
//
//  Session CRUD + reference resolution. Resolution runs through a registry of
//  per-itemType resolvers so future kinds (countdown, slide decks, …) plug in by
//  conforming to SessionItemResolving and registering — no switch to grow.
//

import Foundation
import SwiftData

// MARK: - Resolver protocol (extension point for future item kinds)

protocol SessionItemResolving {
    /// The ScheduleItem.itemType this resolver owns.
    var itemType: String { get }
    func resolve(_ payload: SessionItemPayload, item: ScheduleItem,
                 context: ModelContext) -> SessionResolution
}

// MARK: - Service

enum SessionService {
    /// itemType → resolver. Registered once; extend for new kinds.
    static let resolvers: [String: any SessionItemResolving] = {
        let all: [any SessionItemResolving] = [
            BibleItemResolver(), SongItemResolver(), MediaItemResolver(),
            TextItemResolver(), BlankItemResolver(),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.itemType, $0) })
    }()

    static func payload(for item: ScheduleItem) -> SessionItemPayload {
        SessionItemPayload.decode(fromJSON: item.payloadJSON)
    }

    /// Resolve an item's stable reference back to presentable library content.
    static func resolve(_ item: ScheduleItem, context: ModelContext) -> SessionResolution {
        guard let resolver = resolvers[item.itemType] else {
            // Unknown kind (from a newer app version) → present the snapshot text.
            return .text(title: item.title, content: item.content)
        }
        return resolver.resolve(payload(for: item), item: item, context: context)
    }

    /// Create a session; empty name gets a dated default („Sesiune – duminică, 6 iul.").
    @discardableResult
    static func createSession(name: String, date: Date = .now, context: ModelContext) -> ServiceSchedule {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(localized: "Sesiune", comment: "Default session name prefix")
            + " – " + date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        let schedule = ServiceSchedule(name: trimmed.isEmpty ? fallback : trimmed, date: date)
        context.insert(schedule)
        try? context.save()
        return schedule
    }

    /// Append a draft to a session: stamps the stable payload + a display snapshot
    /// (title/content/subtitle) so the running order stays readable even if the
    /// referenced content is later deleted.
    @discardableResult
    static func append(_ draft: SessionItemDraft, to schedule: ServiceSchedule,
                       context: ModelContext) -> ScheduleItem {
        let nextOrder = (schedule.items.map(\.order).max() ?? -1) + 1
        var payload = SessionItemPayload()
        let item: ScheduleItem

        switch draft {
        case let .bible(translation, bookNumber, bookName, chapter, verseStart, verseEnd,
                        displayReference, snapshotText):
            payload.translation = translation
            payload.bookNumber = bookNumber
            payload.bookName = bookName
            payload.chapter = chapter
            payload.verseStart = verseStart
            payload.verseEnd = verseEnd
            item = ScheduleItem(title: displayReference, itemType: "bible",
                                content: snapshotText, subtitle: displayReference, order: nextOrder)

        case let .song(song, version):
            payload.songKey = HistoryStore.songKey(ccli: song.ccliNumber, title: song.title,
                                                   source: song.collection?.sourceFormat ?? "")
            payload.songTitle = song.title
            payload.versionID = version?.id.uuidString ?? ""
            payload.versionName = version?.name ?? ""
            let subtitle = [song.author, version?.name ?? ""]
                .filter { !$0.isEmpty }.joined(separator: " · ")
            item = ScheduleItem(title: song.title, itemType: "song",
                                content: "", subtitle: subtitle, order: nextOrder)

        case let .media(media):
            payload.mediaID = media.id.uuidString
            payload.mediaName = media.name
            item = ScheduleItem(title: media.name, itemType: "media",
                                content: "", subtitle: media.mediaType.capitalized, order: nextOrder)

        case let .text(title, content):
            item = ScheduleItem(title: title, itemType: "text",
                                content: content, subtitle: "", order: nextOrder)

        case .blank:
            item = ScheduleItem(title: String(localized: "Ecran negru", comment: "Blank session item"),
                                itemType: "blank", content: "", subtitle: "", order: nextOrder)
        }

        item.payloadJSON = payload.encodedJSON()
        item.schedule = schedule
        context.insert(item)
        try? context.save()
        return item
    }
}

// MARK: - Built-in resolvers

private struct BibleItemResolver: SessionItemResolving {
    let itemType = "bible"

    func resolve(_ p: SessionItemPayload, item: ScheduleItem, context: ModelContext) -> SessionResolution {
        // Legacy free-form bible items (no payload) → present the snapshot.
        guard !p.translation.isEmpty, p.bookNumber > 0, p.chapter > 0 else {
            if !item.content.isEmpty { return .bible(text: item.content, reference: item.subtitle, translationName: "") }
            return .missing(String(localized: "Referință biblică incompletă", comment: "Missing session item reason"))
        }
        let wanted = p.translation.lowercased()
        let modules = (try? context.fetch(FetchDescriptor<BibleModule>())) ?? []
        guard let module = modules.first(where: { $0.abbreviation.lowercased() == wanted }) else {
            return .missing(String(localized: "Traducerea \(p.translation) nu e în bibliotecă", comment: "Missing session item reason"))
        }
        guard let book = module.books.first(where: { $0.bookNumber == p.bookNumber }),
              let chapter = book.chapters.first(where: { $0.chapterNumber == p.chapter }) else {
            return .missing(String(localized: "Pasajul \(p.bookName) \(p.chapter) lipsește din \(p.translation)", comment: "Missing session item reason"))
        }
        let end = max(p.verseEnd, p.verseStart)
        let verses = chapter.verses
            .filter { $0.verseNumber >= p.verseStart && $0.verseNumber <= end }
            .sorted { $0.verseNumber < $1.verseNumber }
        guard !verses.isEmpty else {
            return .missing(String(localized: "Versetele \(p.verseStart)-\(end) lipsesc", comment: "Missing session item reason"))
        }
        let text = verses.map(\.text).joined(separator: " ")
        let range = p.verseStart == end ? "\(p.verseStart)" : "\(p.verseStart)-\(end)"
        let reference = "\(book.name) \(p.chapter):\(range)"
        return .bible(text: text, reference: reference, translationName: module.abbreviation)
    }
}

private struct SongItemResolver: SessionItemResolving {
    let itemType = "song"

    func resolve(_ p: SessionItemPayload, item: ScheduleItem, context: ModelContext) -> SessionResolution {
        // Legacy free-form song items → present the snapshot text.
        guard !p.songKey.isEmpty else {
            if !item.content.isEmpty { return .text(title: item.title, content: item.content) }
            return .missing(String(localized: "Cântec fără referință", comment: "Missing session item reason"))
        }
        let songs = (try? context.fetch(FetchDescriptor<Song>())) ?? []
        guard let song = songs.first(where: {
            HistoryStore.songKey(ccli: $0.ccliNumber, title: $0.title,
                                 source: $0.collection?.sourceFormat ?? "") == p.songKey
        }) else {
            return .missing(String(localized: "„\(p.songTitle)” nu mai e în bibliotecă", comment: "Missing session item reason"))
        }
        // Arrangement: exact id → name match → active version.
        var version: SongVersion? = nil
        if !p.versionID.isEmpty { version = song.versions.first { $0.id.uuidString == p.versionID } }
        if version == nil, !p.versionName.isEmpty { version = song.versions.first { $0.name == p.versionName } }
        return .song(song, version: version ?? song.activeVersion)
    }
}

private struct MediaItemResolver: SessionItemResolving {
    let itemType = "media"

    func resolve(_ p: SessionItemPayload, item: ScheduleItem, context: ModelContext) -> SessionResolution {
        let items = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        if let byID = items.first(where: { $0.id.uuidString == p.mediaID }) { return .media(byID) }
        let name = p.mediaName.isEmpty ? item.title : p.mediaName
        if let byName = items.first(where: { $0.name == name }) { return .media(byName) }
        return .missing(String(localized: "Fișierul media „\(name)” lipsește", comment: "Missing session item reason"))
    }
}

private struct TextItemResolver: SessionItemResolving {
    let itemType = "text"
    func resolve(_ p: SessionItemPayload, item: ScheduleItem, context: ModelContext) -> SessionResolution {
        .text(title: item.title, content: item.content)
    }
}

private struct BlankItemResolver: SessionItemResolving {
    let itemType = "blank"
    func resolve(_ p: SessionItemPayload, item: ScheduleItem, context: ModelContext) -> SessionResolution {
        .blank
    }
}
