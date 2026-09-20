//
//  SongPriority.swift
//  TopPresenter
//
//  Which song the operator wants FIRST when several match the query equally well.
//

import Foundation
import Observation

/// A property of a song that ranking can band by.
///
/// Facets are a fixed set because each one needs a way to read its value off a
/// projection; the BANDS built from them are unlimited, which is what makes the
/// order editable without inventing a rules language.
nonisolated enum SongFacet: String, Codable, Sendable, CaseIterable, Identifiable {
    case songbook, author, collection, source, website, language

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .songbook:   return String(localized: "Carte de cântări", comment: "Ranking facet")
        case .author:     return String(localized: "Autor", comment: "Ranking facet")
        case .collection: return String(localized: "Colecție", comment: "Ranking facet")
        case .source:     return String(localized: "Sursă import", comment: "Ranking facet")
        case .website:    return String(localized: "Site web", comment: "Ranking facet")
        case .language:   return String(localized: "Limbă", comment: "Ranking facet")
        }
    }

    /// This song's value for the facet — "" when it has none.
    func value(of entry: SongIndexEntry) -> String {
        switch self {
        case .songbook:   return entry.songbookName
        case .author:     return entry.author
        case .collection: return entry.collectionName
        case .source:     return entry.sourceFormat
        case .website:    return entry.webHost
        case .language:   return entry.language
        }
    }
}

/// One rank band: "songs that come from a songbook — and of those, these books
/// in this order".
nonisolated struct SongPriorityBand: Codable, Sendable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var facet: SongFacet
    var isEnabled: Bool = true
    /// Preferred values, best first. Songs whose value is not listed still
    /// belong to the band — they just sort after the listed ones.
    var values: [String] = []
    /// When true ONLY the listed values belong to the band. This is what
    /// separates "any song that has an author" from "songs written in the app",
    /// which is one specific value of a facet every song has.
    var restrictedToValues: Bool = false

    /// Where `entry` sits in this band, or nil when it does not belong.
    ///
    /// Folding happens only when there are listed values to compare against:
    /// three of the four standard bands list none, and folding their facet
    /// value anyway was three string folds per hit per keystroke — 60 000 of
    /// them for one common query on a 40k library.
    func position(of entry: SongIndexEntry) -> Int? {
        let value = facet.value(of: entry)
        guard !value.isEmpty else { return nil }
        if values.isEmpty { return restrictedToValues ? nil : 0 }
        // Exact match first — the internal marker values ("manual") and most
        // book names hit here without any folding.
        if let idx = values.firstIndex(of: value) { return idx }
        let folded = searchFold(value)
        if let idx = values.firstIndex(where: { searchFold($0) == folded }) { return idx }
        return restrictedToValues ? nil : values.count
    }
}

/// The operator's ordering preference, as a list of bands.
nonisolated struct SongPriorityRules: Codable, Sendable, Equatable {
    var isEnabled: Bool = true
    var bands: [SongPriorityBand] = []

    /// Where a song sorts. Lower is better. A song matching no band lands in a
    /// band after every configured one, so adding a band never pushes anything
    /// it does not mention ahead of what it does.
    func rank(_ entry: SongIndexEntry) -> (band: Int, position: Int) {
        guard isEnabled else { return (0, 0) }
        let active = bands.filter(\.isEnabled)
        for (i, band) in active.enumerated() {
            if let position = band.position(of: entry) { return (i, position) }
        }
        return (active.count, 0)
    }

    /// One `Int32` that orders the way `(band, position)` does — band in the
    /// high half, position clamped into the low half. The rank table stores
    /// these, and the ranker compares them with a single integer comparison.
    static func pack(_ r: (band: Int, position: Int)) -> Int32 {
        Int32(min(r.band, 0x7FFF)) << 16 | Int32(min(r.position, 0xFFFF))
    }

    /// Fixed ids for the four default bands.
    ///
    /// `SongPriorityBand.id` defaults to a fresh `UUID`, which is right for a
    /// band the operator adds but wrong for these: a minted id makes
    /// `.standard != .standard`, so "are we still on the defaults?" can never be
    /// answered, `resetToStandard` looks like a change and re-persists every
    /// time, and SwiftUI rebuilds every row of the editor on a reset because
    /// `ForEach` sees four new identities.
    private enum StandardID {
        static let songbook = UUID(uuidString: "7B1C0001-0000-4000-8000-000000000001")!
        static let author   = UUID(uuidString: "7B1C0002-0000-4000-8000-000000000002")!
        static let written  = UUID(uuidString: "7B1C0003-0000-4000-8000-000000000003")!
        static let website  = UUID(uuidString: "7B1C0004-0000-4000-8000-000000000004")!
    }

    /// The order the operator described: a song from a hymnal first, then one
    /// with a named author, then what was written here, then what came off a
    /// website — everything else last.
    static var standard: SongPriorityRules {
        SongPriorityRules(isEnabled: true, bands: [
            SongPriorityBand(
                id: StandardID.songbook,
                name: String(localized: "Din carte", comment: "Ranking band"),
                facet: .songbook),
            SongPriorityBand(
                id: StandardID.author,
                name: String(localized: "Cu autor", comment: "Ranking band"),
                facet: .author),
            SongPriorityBand(
                id: StandardID.written,
                name: String(localized: "Scrise aici", comment: "Ranking band"),
                facet: .source,
                values: [SongFactory.manualSourceFormat],
                restrictedToValues: true),
            SongPriorityBand(
                id: StandardID.website,
                name: String(localized: "De pe internet", comment: "Ranking band"),
                facet: .website),
        ])
    }
}

/// App-global, persisted ranking preference.
///
/// Lives beside `PinStore`: one per app rather than one per window, because a
/// second window showing a different order for the same query would be a bug,
/// not a feature.
@MainActor
@Observable
final class SongPriorityStore {
    static let shared = SongPriorityStore()

    private static let defaultsKey = "songPriorityRules"

    var rules: SongPriorityRules {
        didSet { guard rules != oldValue else { return }; persist() }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(SongPriorityRules.self, from: data) {
            rules = decoded
        } else {
            rules = .standard
        }
    }

    func resetToStandard() { rules = .standard }

    private func persist() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
