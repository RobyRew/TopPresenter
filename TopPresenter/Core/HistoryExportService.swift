//
//  HistoryExportService.swift
//  TopPresenter
//
//  Exports the presentation history (CSV + JSON) — launched only from the History
//  viewer. Deliberately separate from ExportService / the song & bible GOAT JSON:
//  history is never part of a song/bible file.
//

import Foundation

enum HistoryExportService {
    private static let iso = ISO8601DateFormatter()

    // MARK: CSV (flat event log — opens in Excel/Numbers/Sheets)

    static func eventsCSV(_ events: [PresentationEvent]) -> String {
        let header = ["timestamp", "type", "title", "songKey", "verse", "slide",
                      "translation", "book", "chapter", "verseStart", "verseEnd",
                      "reference", "sessionID", "dwellSeconds"]
        var rows = [header.joined(separator: ",")]
        for e in events {
            let cols: [String] = [
                iso.string(from: e.timestamp), e.contentType,
                e.contentType == "bible" ? e.bookName : e.songTitle, e.songKey,
                e.verseLabel, String(e.slideIndex),
                e.translation, e.bookName, e.chapter > 0 ? String(e.chapter) : "",
                e.verseStart > 0 ? String(e.verseStart) : "",
                e.verseEnd > 0 ? String(e.verseEnd) : "",
                e.reference, e.sessionID.uuidString, String(format: "%.1f", e.dwellSeconds),
            ]
            rows.append(cols.map(csvEscape).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    private static func csvEscape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: JSON ("TopPresenter History" — events + computed aggregates)

    static func json(_ store: HistoryStore) throws -> String {
        let events = store.exportEvents()
        let songs = store.songSummaries().map { s -> [String: Any] in
            ["songKey": s.songKey, "title": s.title, "timesPresented": s.timesPresented,
             "verseShows": s.verseShows, "firstPresented": iso.string(from: s.firstPresented),
             "lastPresented": iso.string(from: s.lastPresented)]
        }
        let bible = store.bibleSummaries().map { b -> [String: Any] in
            ["translation": b.translation, "reference": b.reference, "bookNumber": b.bookNumber,
             "bookName": b.bookName, "chapter": b.chapter, "verseStart": b.verseStart, "verseEnd": b.verseEnd,
             "timesPresented": b.timesPresented, "shows": b.shows,
             "firstPresented": iso.string(from: b.firstPresented), "lastPresented": iso.string(from: b.lastPresented)]
        }
        let eventObjs = events.map { e -> [String: Any] in
            var d: [String: Any] = ["timestamp": iso.string(from: e.timestamp), "type": e.contentType,
                                    "sessionID": e.sessionID.uuidString, "dwellSeconds": e.dwellSeconds]
            if e.contentType == "song" {
                d["title"] = e.songTitle; d["songKey"] = e.songKey
                if !e.versionName.isEmpty { d["version"] = e.versionName }
                if !e.verseLabel.isEmpty { d["verse"] = e.verseLabel }
                d["slide"] = e.slideIndex
            } else if e.contentType == "bible" {
                d["translation"] = e.translation; d["reference"] = e.reference
                d["bookNumber"] = e.bookNumber; d["bookName"] = e.bookName
                d["chapter"] = e.chapter; d["verseStart"] = e.verseStart; d["verseEnd"] = e.verseEnd
            } else {
                d["title"] = e.songTitle
            }
            return d
        }
        let root: [String: Any] = [
            "schemaVersion": "1.0.0", "format": "TopPresenter History",
            "exportInfo": ["source": "TopPresenter", "exportDate": iso.string(from: Date()),
                           "totalEvents": events.count],
            "aggregates": ["songs": songs, "bible": bible],
            "events": eventObjs,
        ]
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
