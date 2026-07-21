//
//  SlideTokenResolver.swift
//  TopPresenter
//
//  Custom Slides v2 — dynamic slides. A slide's title/subtitle/content store
//  a TEMPLATE with `{{scheme:argument#field|option}}` tokens, resolved at
//  PRESENT time (and live in the editor preview):
//
//    {{bible:Ioan 3:16-18}}            verse text from the ACTIVE translation
//    {{bible:Psalmi 23#ref|VDC}}       fields: text (default) | ref | full;
//                                      |ABBREV pins a specific translation
//    {{song:Nume cântec}}              fields: first (default) | title |
//                                      author | book | number | ccli | slide1
//    {{date}} / {{date:EEEE, d MMMM}}  formatted current date
//    {{time}} / {{time:HH:mm}}         formatted current time
//    {{url:https://…#items.0.title}}   GET JSON + keypath extraction
//    {{rss:https://…#0.title}}         RSS/Atom item field (title|description|date)
//
//  `{{{{` escapes a literal `{{`.
//
//  ARCHITECTURE: one `SlideDataProvider` per scheme, looked up in a registry —
//  a NEW data source (weather, church API, anything) is ONE new provider,
//  nothing else changes. Local providers resolve synchronously over the
//  SearchIndex projections (zero SwiftData per token); remote ones go through
//  RemoteContentService (timeout + cache + stale fallback) and can NEVER
//  block or fail a presentation — unresolvable tokens render as "—".
//

import Foundation
import SwiftData

// MARK: - Grammar (pure, testable)

nonisolated struct SlideToken: Equatable, Sendable {
    let scheme: String     // lowercased: bible | song | date | time | url | rss | …
    let argument: String   // reference / song name / format / URL
    let field: String      // after '#' (field id or keypath), "" when absent
    let option: String     // after '|' (translation abbrev …), "" when absent
}

nonisolated enum SlideTemplate {
    enum Segment: Equatable, Sendable {
        case literal(String)
        case token(SlideToken)
    }

    /// Split a template into literal runs and parsed tokens. Unclosed or
    /// empty braces stay literal — typing in the editor never explodes.
    static func parse(_ template: String) -> [Segment] {
        var segments: [Segment] = []
        var literal = ""
        var rest = Substring(template)

        while let open = rest.range(of: "{{") {
            literal += rest[..<open.lowerBound]
            let afterOpen = rest[open.upperBound...]
            // Escape: {{{{ → literal {{
            if afterOpen.hasPrefix("{{") {
                literal += "{{"
                rest = afterOpen.dropFirst(2)
                continue
            }
            guard let close = afterOpen.range(of: "}}") else {
                literal += rest[open.lowerBound...]
                rest = Substring("")
                break
            }
            let body = String(afterOpen[..<close.lowerBound])
            if let token = parseBody(body) {
                if !literal.isEmpty { segments.append(.literal(literal)); literal = "" }
                segments.append(.token(token))
            } else {
                literal += "{{" + body + "}}"
            }
            rest = afterOpen[close.upperBound...]
        }
        literal += rest
        if !literal.isEmpty { segments.append(.literal(literal)) }
        return segments
    }

    /// `scheme:argument#field|option` — scheme required; the rest optional.
    private static func parseBody(_ body: String) -> SlideToken? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let scheme: String
        var remainder: String
        if let colon = trimmed.firstIndex(of: ":") {
            scheme = String(trimmed[..<colon]).lowercased().trimmingCharacters(in: .whitespaces)
            remainder = String(trimmed[trimmed.index(after: colon)...])
        } else {
            scheme = trimmed.lowercased()
            remainder = ""
        }
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isLetter }) else { return nil }

        // The option pipe may sit on the argument ({{bible:Ioan 3:16|VDC}})
        // OR after the field ({{bible:Ioan 3:16#ref|VDC}}) — accept both.
        var field = ""
        var option = ""
        if let hash = remainder.firstIndex(of: "#") {
            field = String(remainder[remainder.index(after: hash)...]).trimmingCharacters(in: .whitespaces)
            remainder = String(remainder[..<hash])
            if let pipe = field.firstIndex(of: "|") {
                option = String(field[field.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
                field = String(field[..<pipe]).trimmingCharacters(in: .whitespaces)
            }
        }
        if let pipe = remainder.firstIndex(of: "|") {
            let fromArg = String(remainder[remainder.index(after: pipe)...]).trimmingCharacters(in: .whitespaces)
            if option.isEmpty { option = fromArg }
            remainder = String(remainder[..<pipe])
        }
        return SlideToken(scheme: scheme,
                          argument: remainder.trimmingCharacters(in: .whitespaces),
                          field: field, option: option)
    }

    static func containsTokens(_ s: String) -> Bool { tokenCount(s) > 0 }

    static func tokenCount(_ s: String) -> Int {
        parse(s).reduce(0) { if case .token = $1 { return $0 + 1 } else { return $0 } }
    }
}

// MARK: - Provider protocol + registry

/// Everything a provider may need — captured on the MainActor once per
/// resolution pass, then handed to providers.
@MainActor
struct SlideTokenContext {
    let index: SearchIndex
    let modelContext: ModelContext?

    /// The value an unresolvable token renders as — visible but harmless.
    nonisolated static let unresolved = "—"
}

@MainActor
protocol SlideDataProvider {
    var scheme: String { get }
    func resolve(_ token: SlideToken, context: SlideTokenContext) async -> String?
}

// MARK: - Resolver façade

@MainActor
enum SlideTokenResolver {
    /// scheme → provider. A NEW source = append one entry here.
    static let providers: [String: any SlideDataProvider] = {
        let all: [any SlideDataProvider] = [
            BibleTokenProvider(), SongTokenProvider(),
            DateTokenProvider(), TimeTokenProvider(),
            UrlTokenProvider(), RssTokenProvider(),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.scheme, $0) })
    }()

    static func resolve(_ template: String, context: SlideTokenContext) async -> String {
        var out = ""
        for segment in SlideTemplate.parse(template) {
            switch segment {
            case .literal(let s):
                out += s
            case .token(let token):
                if let provider = providers[token.scheme],
                   let value = await provider.resolve(token, context: context) {
                    out += value
                } else {
                    out += SlideTokenContext.unresolved
                }
            }
        }
        return out
    }

    /// One call for a whole slide.
    static func resolveSlide(title: String, subtitle: String, content: String,
                             context: SlideTokenContext)
        async -> (title: String, subtitle: String, content: String) {
        (await resolve(title, context: context),
         await resolve(subtitle, context: context),
         await resolve(content, context: context))
    }
}

// MARK: - Bible provider

@MainActor
struct BibleTokenProvider: SlideDataProvider {
    let scheme = "bible"

    func resolve(_ token: SlideToken, context: SlideTokenContext) async -> String? {
        // Pinned translation (|ABBREV) → small targeted SwiftData walk;
        // otherwise the ACTIVE translation's in-memory verse index.
        if !token.option.isEmpty, let modelContext = context.modelContext {
            return Self.resolvePinned(reference: token.argument, abbreviation: token.option,
                                      field: token.field, activeBooks: context.index.books,
                                      modelContext: modelContext)
        }
        return Self.resolve(reference: token.argument, field: token.field,
                            books: context.index.books, verses: context.index.verses)
    }

    /// Pure resolution over index projections — unit-tested directly.
    nonisolated static func resolve(reference: String, field: String,
                                    books: [BookIndexEntry], verses: [VerseIndexEntry]) -> String? {
        guard let match = BibleReferenceParser.parse(reference, books: books) else { return nil }
        let picked = verses.filter {
            $0.bookNumber == match.bookNumber && $0.chapter == match.chapter
                && (match.verseStart == nil
                    || ($0.verse >= match.verseStart! && $0.verse <= (match.verseEnd ?? match.verseStart!)))
        }
        guard let first = picked.first, let last = picked.last else { return nil }
        let ref = first.verse == last.verse
            ? "\(first.bookName) \(first.chapter):\(first.verse)"
            : "\(first.bookName) \(first.chapter):\(first.verse)-\(last.verse)"
        let text = picked.count == 1
            ? picked[0].text
            : picked.map { "(\($0.verse)) \($0.text)" }.joined(separator: " ")
        switch field {
        case "ref": return ref
        case "full": return text + " — " + ref
        default: return text
        }
    }

    /// |ABBREV path: fetch that one module and adapt its passage to the same
    /// pure resolver shapes.
    private static func resolvePinned(reference: String, abbreviation: String, field: String,
                                      activeBooks: [BookIndexEntry],
                                      modelContext: ModelContext) -> String? {
        let all = (try? modelContext.fetch(FetchDescriptor<BibleModule>())) ?? []
        guard let module = all.first(where: {
            $0.abbreviation.compare(abbreviation, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) else { return nil }
        // Parse against the pinned module's own book names (fall back to the
        // active index's names so "Ioan 3:16|KJV" still finds book 43).
        let books = module.books.map {
            BookIndexEntry(moduleID: module.id, bookNumber: $0.bookNumber, name: $0.name,
                           folded: searchFold($0.name), abbreviationFolded: searchFold($0.abbreviation),
                           chapterCount: $0.chapters.count)
        }
        let match = BibleReferenceParser.parse(reference, books: books)
            ?? BibleReferenceParser.parse(reference, books: activeBooks)
        guard let match,
              let book = module.books.first(where: { $0.bookNumber == match.bookNumber }),
              let chapter = book.chapters.first(where: { $0.chapterNumber == match.chapter })
        else { return nil }
        let verses = chapter.verses.sorted { $0.verseNumber < $1.verseNumber }.filter {
            match.verseStart == nil
                || ($0.verseNumber >= match.verseStart! && $0.verseNumber <= (match.verseEnd ?? match.verseStart!))
        }.map {
            VerseIndexEntry(moduleID: module.id, bookNumber: book.bookNumber, bookName: book.name,
                            chapter: chapter.chapterNumber, verse: $0.verseNumber,
                            text: $0.text, folded: "")
        }
        guard let first = verses.first, let last = verses.last else { return nil }
        let ref = first.verse == last.verse
            ? "\(first.bookName) \(first.chapter):\(first.verse)"
            : "\(first.bookName) \(first.chapter):\(first.verse)-\(last.verse)"
        let text = verses.count == 1
            ? verses[0].text
            : verses.map { "(\($0.verse)) \($0.text)" }.joined(separator: " ")
        switch field {
        case "ref": return ref
        case "full": return text + " — " + ref
        default: return text
        }
    }
}

// MARK: - Song provider

@MainActor
struct SongTokenProvider: SlideDataProvider {
    let scheme = "song"

    func resolve(_ token: SlideToken, context: SlideTokenContext) async -> String? {
        guard let entry = context.index.searchSongs(token.argument, limit: 1).first else { return nil }
        // Projection-backed fields — no SwiftData.
        if let value = Self.projectionField(token.field, entry: entry) { return value }
        // ccli / slide1 need the real model — one predicate fetch, on demand.
        guard let modelContext = context.modelContext else { return nil }
        var d = FetchDescriptor<Song>(predicate: Song.predicate(forID: entry.id))
        d.fetchLimit = 1
        guard let song = (try? modelContext.fetch(d))?.first else { return nil }
        switch token.field {
        case "ccli":
            return song.ccliNumber.isEmpty ? nil : song.ccliNumber
        case "slide1":
            let slides = buildSongSlides(song: song, version: song.activeVersion, maxLines: 6,
                                         bilingual: false, language: nil,
                                         bracket: "none", countStyle: "times")
            return slides.first?.text
        default:
            return nil
        }
    }

    /// Pure field extraction over the index projection — unit-tested directly.
    nonisolated static func projectionField(_ field: String, entry: SongIndexEntry) -> String? {
        switch field {
        case "", "first": return entry.firstLine.isEmpty ? entry.title : entry.firstLine
        case "title": return entry.title
        case "author": return entry.author.isEmpty ? nil : entry.author
        case "book": return entry.songbookName.isEmpty ? nil : entry.songbookName
        case "number": return entry.songNumber.isEmpty ? nil : entry.songNumber
        default: return nil   // ccli / slide1 → model fetch
        }
    }
}

// MARK: - Date / time providers

@MainActor
struct DateTokenProvider: SlideDataProvider {
    let scheme = "date"
    func resolve(_ token: SlideToken, context: SlideTokenContext) async -> String? {
        Self.format(.now, pattern: token.argument, locale: .current)
    }
    /// Pure + injectable — unit-tested with a fixed date/locale.
    nonisolated static func format(_ date: Date, pattern: String, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        if pattern.isEmpty {
            f.dateStyle = .full
            f.timeStyle = .none
        } else {
            f.dateFormat = pattern
        }
        return f.string(from: date)
    }
}

@MainActor
struct TimeTokenProvider: SlideDataProvider {
    let scheme = "time"
    func resolve(_ token: SlideToken, context: SlideTokenContext) async -> String? {
        Self.format(.now, pattern: token.argument, locale: .current)
    }
    nonisolated static func format(_ date: Date, pattern: String, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        if pattern.isEmpty {
            f.dateStyle = .none
            f.timeStyle = .short
        } else {
            f.dateFormat = pattern
        }
        return f.string(from: date)
    }
}

// MARK: - Remote providers (url / rss)

@MainActor
struct UrlTokenProvider: SlideDataProvider {
    let scheme = "url"
    func resolve(_ token: SlideToken, context: SlideTokenContext) async -> String? {
        guard let url = URL(string: token.argument), url.scheme?.hasPrefix("http") == true else { return nil }
        return await RemoteContentService.shared.jsonValue(url: url, keypath: token.field)
    }
}

@MainActor
struct RssTokenProvider: SlideDataProvider {
    let scheme = "rss"
    func resolve(_ token: SlideToken, context: SlideTokenContext) async -> String? {
        guard let url = URL(string: token.argument), url.scheme?.hasPrefix("http") == true else { return nil }
        return await RemoteContentService.shared.rssValue(url: url, field: token.field)
    }
}
