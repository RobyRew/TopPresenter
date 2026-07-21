//
//  RemoteContentService.swift
//  TopPresenter
//
//  The network half of dynamic slides: plain GET with a HARD 6s timeout, an
//  in-memory per-URL cache (TTL 5 min — repeated refreshes during a service
//  never hammer the server), and STALE fallback: if a refresh fails and we
//  ever had data for that URL, the old data is used. A dead network can slow
//  a token down by at most the timeout — it can never fail a presentation.
//
//  Extraction is pure and unit-tested: JSON keypath ("items.0.title") and a
//  native XMLParser-based RSS/Atom item reader (no third-party).
//

import Foundation

actor RemoteContentService {
    static let shared = RemoteContentService()

    private struct CacheEntry {
        let data: Data
        let fetchedAt: Date
    }

    private var cache: [URL: CacheEntry] = [:]
    private let ttl: TimeInterval = 300
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 6
        session = URLSession(configuration: config)
    }

    // MARK: Fetch (cache → network → stale)

    private func data(for url: URL) async -> Data? {
        if let hit = cache[url], Date.now.timeIntervalSince(hit.fetchedAt) < ttl {
            return hit.data
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return cache[url]?.data   // stale beats nothing
            }
            cache[url] = CacheEntry(data: data, fetchedAt: .now)
            return data
        } catch {
            return cache[url]?.data
        }
    }

    // MARK: Public token entries

    /// `{{url:…#keypath}}` — fetch JSON, extract a leaf on the dotted keypath.
    func jsonValue(url: URL, keypath: String) async -> String? {
        guard let data = await data(for: url) else { return nil }
        return Self.extractJSON(data, keypath: keypath)
    }

    /// `{{rss:…#index.field}}` — fetch a feed, return an item's field.
    func rssValue(url: URL, field: String) async -> String? {
        guard let data = await data(for: url) else { return nil }
        return Self.rssField(items: Self.parseFeedItems(data), field: field)
    }

    // MARK: JSON keypath (pure)

    /// "items.0.title" → walks dictionaries by key and arrays by index; the
    /// leaf renders as a clean string. Empty keypath on a scalar returns it.
    nonisolated static func extractJSON(_ data: Data, keypath: String) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return nil }
        var node: Any = root
        if !keypath.isEmpty {
            for part in keypath.split(separator: ".").map(String.init) {
                if let dict = node as? [String: Any], let next = dict[part] {
                    node = next
                } else if let array = node as? [Any], let i = Int(part), array.indices.contains(i) {
                    node = array[i]
                } else {
                    return nil
                }
            }
        }
        switch node {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case is NSNull: return nil
        default: return nil   // dict/array leaves are not printable slide text
        }
    }

    // MARK: RSS / Atom (pure, native XMLParser)

    nonisolated struct FeedItem: Equatable, Sendable {
        var title = ""
        var descriptionText = ""
        var dateText = ""
    }

    nonisolated static func parseFeedItems(_ data: Data) -> [FeedItem] {
        let delegate = FeedDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    /// field = "0.title" (index.field) or "title" (first item). Fields:
    /// title | description | date.
    nonisolated static func rssField(items: [FeedItem], field: String) -> String? {
        var index = 0
        var name = field.isEmpty ? "title" : field
        let parts = field.split(separator: ".").map(String.init)
        if parts.count == 2, let i = Int(parts[0]) {
            index = i
            name = parts[1]
        } else if parts.count == 1, let i = Int(parts[0]) {
            index = i
            name = "title"
        }
        guard items.indices.contains(index) else { return nil }
        let item = items[index]
        let value: String
        switch name {
        case "description": value = item.descriptionText
        case "date": value = item.dateText
        default: value = item.title
        }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Collects <item> (RSS) and <entry> (Atom) children: title,
    /// description/summary/content, pubDate/updated/published.
    private final class FeedDelegate: NSObject, XMLParserDelegate {
        var items: [FeedItem] = []
        private var current: FeedItem?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            let element = name.lowercased()
            if element == "item" || element == "entry" {
                current = FeedItem()
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }

        func parser(_ parser: XMLParser, didEndElement name: String,
                    namespaceURI: String?, qualifiedName: String?) {
            let element = name.lowercased()
            if element == "item" || element == "entry" {
                if let current { items.append(current) }
                current = nil
                return
            }
            guard current != nil else { return }
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element {
            case "title":
                if current!.title.isEmpty { current!.title = value }
            case "description", "summary", "content":
                if current!.descriptionText.isEmpty { current!.descriptionText = value }
            case "pubdate", "updated", "published":
                if current!.dateText.isEmpty { current!.dateText = value }
            default:
                break
            }
        }
    }
}
