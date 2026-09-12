//
//  SongSections.swift
//  TopPresenter
//
//  What kind a song section is, and what to CALL it on screen.
//

import SwiftUI

/// The canonical kinds a song section can be.
///
/// A section's stored `type` is whatever its importer wrote, and importers
/// write their source's vocabulary: OpenSong says "chorus", a ChordPro file may
/// say "refrain", a `.tpsong` scraped from a Romanian site says „refren".
/// Classifying once, here, is what lets everything downstream — colours, labels,
/// the chorus-only slide scope — ask about the KIND rather than pattern-match
/// strings in five places.
nonisolated enum SongSectionKind: String, CaseIterable, Sendable {
    case verse, chorus, bridge, prechorus, intro, ending, tag, interlude, other

    /// Best guess for a raw `type` or label string.
    ///
    /// Matching is diacritic- and case-insensitive and covers the words the app
    /// actually meets in files, in the languages TopPresenter ships. Anything
    /// unrecognised stays `.other` rather than being forced into `.verse` — a
    /// wrong kind renumbers the verses on the projector.
    static func classify(_ raw: String) -> SongSectionKind {
        let key = raw.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return .other }
        // Longest-prefix first: "prechorus" must not be read as "chorus", and
        // "pre-refren" must not be read as "refren".
        for (kind, prefixes) in prefixTable {
            if prefixes.contains(where: { key.hasPrefix($0) }) { return kind }
        }
        return .other
    }

    /// Ordered so a longer, more specific family is tested before the family it
    /// contains.
    private static let prefixTable: [(SongSectionKind, [String])] = [
        (.prechorus, ["prechorus", "pre-chorus", "pre chorus", "prerefren", "pre-refren",
                      "pre refren", "preestribillo", "pre-estribillo", "prerefrain",
                      "pre-refrain", "pre-strophe", "pred-pripev", "predpripev"]),
        (.interlude, ["interlude", "interludiu", "interludio", "interludium", "zwischenspiel",
                      "intermezzo", "interlyudiya"]),
        (.intro, ["intro", "introducere", "introduccion", "introduction", "einleitung",
                  "vorspiel", "vstuplenie"]),
        (.chorus, ["chorus", "refren", "refrain", "estribillo", "chor", "coro", "cor",
                   "pripev"]),
        (.bridge, ["bridge", "punte", "puente", "pont", "brucke", "bridzh", "bridg"]),
        (.ending, ["ending", "outro", "final", "end", "coda", "schluss", "okonchanie",
                   "concluzie"]),
        (.verse, ["verse", "strofa", "strophe", "estrofa", "couplet", "kuplet", "vers",
                  "stanza"]),
        (.tag, ["tag"]),
    ]

    /// The kind's name in the APP's language.
    var localizedName: String {
        switch self {
        case .verse:     return String(localized: "Strofă", comment: "Section type")
        case .chorus:    return String(localized: "Refren", comment: "Section type")
        case .bridge:    return String(localized: "Punte", comment: "Section type")
        case .prechorus: return String(localized: "Pre-refren", comment: "Section type")
        case .intro:     return String(localized: "Intro", comment: "Section type")
        case .ending:    return String(localized: "Final", comment: "Section type")
        case .tag:       return String(localized: "Tag", comment: "Section type")
        case .interlude: return String(localized: "Interludiu", comment: "Section type")
        case .other:     return String(localized: "Altul", comment: "Section type")
        }
    }

    var color: Color {
        switch self {
        case .chorus: return .orange
        case .bridge: return .purple
        case .prechorus: return .pink
        case .intro, .ending: return .teal
        case .tag: return .green
        case .interlude: return .indigo
        case .verse, .other: return .blue
        }
    }
}

/// Names a version's sections in the APP's language, with their position.
///
/// The stored `label` is whatever the source file said, so a Romanian service
/// could project "Chorus" and an English one „Strofa 2" — the label followed the
/// file, not the operator. These are derived from the section's KIND instead:
/// verses are numbered against how many verses the song has („2/4"), every other
/// kind against its own kind („Refren", „Refren 2" when there are two).
@MainActor
enum SongSectionLabeling {
    /// Position-aware labels for one version's sections, in the SAME order.
    ///
    /// Takes the types as plain strings so it can be called from the version
    /// model, the flattened verse cache, or a test fixture without any of them
    /// having to agree on a type first.
    static func labels(forTypes types: [String]) -> [String] {
        let kinds = types.map(SongSectionKind.classify)
        var totals: [SongSectionKind: Int] = [:]
        for kind in kinds { totals[kind, default: 0] += 1 }

        var seen: [SongSectionKind: Int] = [:]
        return kinds.map { kind in
            let n = (seen[kind] ?? 0) + 1
            seen[kind] = n
            return label(kind: kind, position: n, total: totals[kind] ?? 1)
        }
    }

    /// One section's label. Verses read as a position in the song („2/4"), which
    /// is what an operator glancing at the projector needs; other kinds read as
    /// their name, numbered only when the song has more than one of them.
    static func label(kind: SongSectionKind, position: Int, total: Int) -> String {
        switch kind {
        case .verse:
            return total > 1 ? "\(position)/\(total)" : kind.localizedName
        default:
            return total > 1 ? "\(kind.localizedName) \(position)" : kind.localizedName
        }
    }
}

// MARK: - Compatibility shims for the existing call sites

let songSectionTypes = SongSectionKind.allCases.map(\.rawValue)

func songTypeColor(_ type: String) -> Color { SongSectionKind.classify(type).color }

func songTypeLabel(_ type: String) -> String { SongSectionKind.classify(type).localizedName }
