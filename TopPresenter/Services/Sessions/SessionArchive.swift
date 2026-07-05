//
//  SessionArchive.swift
//  TopPresenter
//
//  .tpschedule import/export — a FLAT versioned JSON file (not a package):
//  sessions are lists of stable REFERENCES, so media is not embedded; a
//  `requiredMedia` manifest tells the receiving operator what to import, and
//  unresolved items degrade to the existing `.missing` handling. Same resilience
//  rules as the GOAT formats: schemaVersion + decodeIfPresent everywhere.
//

import Foundation
import SwiftData

// MARK: - Archive format

struct SessionArchive: Codable {
    var schemaVersion = 1
    var format = "TopPresenter Session"
    var name = ""
    var dateISO = ""
    var notes = ""
    var items: [Item] = []
    var requiredMedia: [MediaRef] = []

    struct Item: Codable {
        var itemType = "text"
        var title = ""
        var content = ""
        var subtitle = ""
        var order = 0
        var payload = SessionItemPayload()

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            itemType = try c.decodeIfPresent(String.self, forKey: .itemType) ?? "text"
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
            subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
            order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
            payload = try c.decodeIfPresent(SessionItemPayload.self, forKey: .payload) ?? SessionItemPayload()
        }
    }

    struct MediaRef: Codable {
        var name = ""
        var mediaType = ""

        init(name: String, mediaType: String) {
            self.name = name
            self.mediaType = mediaType
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? ""
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "TopPresenter Session"
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        dateISO = try c.decodeIfPresent(String.self, forKey: .dateISO) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        items = try c.decodeIfPresent([Item].self, forKey: .items) ?? []
        requiredMedia = try c.decodeIfPresent([MediaRef].self, forKey: .requiredMedia) ?? []
    }
}

// MARK: - Export / Import service

enum SessionArchiveService {
    static let fileExtension = "tpschedule"

    /// Serialize a session (pretty + sorted keys, like the GOAT exports).
    static func export(_ schedule: ServiceSchedule) throws -> Data {
        var archive = SessionArchive()
        archive.name = schedule.name
        archive.dateISO = ISO8601DateFormatter().string(from: schedule.date)
        archive.notes = schedule.notes
        archive.items = schedule.sortedItems.map { item in
            var a = SessionArchive.Item()
            a.itemType = item.itemType
            a.title = item.title
            a.content = item.content
            a.subtitle = item.subtitle
            a.order = item.order
            a.payload = SessionService.payload(for: item)
            return a
        }
        // Manifest: what media the receiving library needs for full resolution.
        archive.requiredMedia = archive.items
            .filter { $0.itemType == "media" }
            .map { SessionArchive.MediaRef(name: $0.payload.mediaName.isEmpty ? $0.title : $0.payload.mediaName,
                                           mediaType: $0.subtitle.lowercased()) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    /// Import a .tpschedule: recreates the session + items, re-linking media
    /// payloads to the LOCAL library (by id, else by name). Returns the new
    /// session and the media names that did NOT resolve (for the user alert).
    @discardableResult
    static func importSession(_ data: Data, context: ModelContext)
        throws -> (schedule: ServiceSchedule, unresolvedMedia: [String]) {
        // Identity check FIRST, strictly: the resilient archive decoder defaults
        // missing keys, so it would happily "decode" foreign JSON. The format
        // marker must actually be present (same keying as the Bible/Song imports).
        struct FormatProbe: Codable { var format: String? }
        let probe = try JSONDecoder().decode(FormatProbe.self, from: data)
        guard probe.format == "TopPresenter Session" else {
            throw NSError(domain: "TopPresenter.SessionArchive", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Fișierul nu este o sesiune TopPresenter.",
                                                  comment: "Import error"),
            ])
        }
        let archive = try JSONDecoder().decode(SessionArchive.self, from: data)

        let date = ISO8601DateFormatter().date(from: archive.dateISO) ?? .now
        let schedule = ServiceSchedule(
            name: archive.name.isEmpty
                ? String(localized: "Sesiune importată", comment: "Default imported session name")
                : archive.name,
            date: date, notes: archive.notes
        )
        context.insert(schedule)

        let localMedia = (try? context.fetch(FetchDescriptor<MediaItem>())) ?? []
        var unresolved: [String] = []

        for archived in archive.items.sorted(by: { $0.order < $1.order }) {
            let item = ScheduleItem(title: archived.title, itemType: archived.itemType,
                                    content: archived.content, subtitle: archived.subtitle,
                                    order: archived.order)
            var payload = archived.payload

            // Re-link media to THIS library: exact id, else name match.
            if archived.itemType == "media" {
                let name = payload.mediaName.isEmpty ? archived.title : payload.mediaName
                if let byID = localMedia.first(where: { $0.id.uuidString == payload.mediaID }) {
                    payload.mediaID = byID.id.uuidString
                    payload.mediaName = byID.name
                } else if let byName = localMedia.first(where: { $0.name == name }) {
                    payload.mediaID = byName.id.uuidString
                    payload.mediaName = byName.name
                } else {
                    unresolved.append(name)
                }
            }

            item.payloadJSON = payload.encodedJSON()
            item.schedule = schedule
            context.insert(item)
        }

        try context.save()
        return (schedule, unresolved)
    }
}
