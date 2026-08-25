//
//  DuplicateResolver.swift
//  TopPresenter
//
//  "Have I already got this?" — asked once, in one place, for every library.
//
//  Before this, four of the six content types could be imported twice with no
//  check at all (media, sessions, themes, slides), and the two that did check
//  matched on a single field: a Bible on its abbreviation, a song on its title.
//  So two different KJV editions collided, two different songs sharing a title
//  merged, and dropping the same .tpschedule twice simply gave you it twice.
//
//  THE PRINCIPLE: same name ≠ same content.
//
//  The old check treated "you already have this exact module" and "you have
//  something else with the same abbreviation" as one question. They are two
//  questions with two different right answers:
//
//    · identical content   → the operator re-dropped a file they already have.
//                            Skip, silently, and say so in the count.
//    · same name, different content → a revision, or a genuinely different
//                            edition. Ask — and say HOW they differ, because an
//                            operator can only choose well if they can see what
//                            was compared.
//
//  So every type answers in two stages: an identity match (a ladder of rules,
//  first hit wins, each with a confidence), then a content comparison to grade
//  it. `differences` and `matchedOn` are written for the dialog, not for a log.
//

import CryptoKit
import Foundation

// MARK: - Verdicts

nonisolated enum DuplicateConfidence: Int, Sendable, Comparable, CaseIterable {
    case weak, strong, certain

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

nonisolated struct DuplicateMatch: Sendable, Equatable {
    /// Index into the `existing` array the caller passed in. Deliberately not a
    /// `PersistentIdentifier`: it keeps the resolver a pure function over value
    /// types, testable without a store, and reusable by the batch path and the
    /// interactive one — which is what stopped them agreeing last time.
    let existingIndex: Int
    let confidence: DuplicateConfidence
    /// What matched, in words: "CCLI 7104200", "abbreviation + language".
    let matchedOn: String
    /// How the two differ, in words. Empty means the content is the same.
    let differences: [String]
}

nonisolated enum DuplicateVerdict: Sendable, Equatable {
    case unique
    /// Same identity AND same content — the file is already in the library.
    case identical(DuplicateMatch)
    /// Certainly the same thing, but changed. Needs a decision.
    case sameIdentityDifferentContent(DuplicateMatch)
    /// Probably the same thing, matched on something weaker than an id.
    case probable(DuplicateMatch)

    var match: DuplicateMatch? {
        switch self {
        case .unique: return nil
        case .identical(let m), .sameIdentityDifferentContent(let m), .probable(let m): return m
        }
    }

    var existingIndex: Int? { match?.existingIndex }
    var isDuplicate: Bool { match != nil }

    /// The same verdict pointing at a different index.
    ///
    /// For a two-phase check: a cheap pass picks the one candidate worth the
    /// expensive comparison, the resolver then sees a one-element array, and the
    /// caller has to put the real index back before it means anything.
    func reindexed(to index: Int) -> DuplicateVerdict {
        guard let old = match else { return self }
        let m = DuplicateMatch(existingIndex: index, confidence: old.confidence,
                               matchedOn: old.matchedOn, differences: old.differences)
        switch self {
        case .unique: return .unique
        case .identical: return .identical(m)
        case .sameIdentityDifferentContent: return .sameIdentityDifferentContent(m)
        case .probable: return .probable(m)
        }
    }
}

// MARK: - Policy

nonisolated enum DuplicatePolicy: String, Sendable, CaseIterable, Identifiable {
    case ask, skip, replace, keepBoth, merge, addAsVersion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .ask: return String(localized: "Ask", comment: "Duplicate policy")
        case .skip: return String(localized: "Skip", comment: "Duplicate policy")
        case .replace: return String(localized: "Replace", comment: "Duplicate policy")
        case .keepBoth: return String(localized: "Keep both", comment: "Duplicate policy")
        case .merge: return String(localized: "Merge", comment: "Duplicate policy")
        case .addAsVersion: return String(localized: "Add as arrangement", comment: "Duplicate policy")
        }
    }

    /// Each kind offers only the choices that mean something for it — merging is
    /// a Bible idea, adding an arrangement is a song one.
    static func allowed(for kind: ImportKind) -> [DuplicatePolicy] {
        switch kind {
        case .bible: return [.ask, .skip, .replace, .merge, .keepBoth]
        case .song: return [.ask, .skip, .replace, .addAsVersion, .keepBoth]
        case .media: return [.skip, .keepBoth]
        case .session: return [.ask, .skip, .replace, .keepBoth]
        case .theme: return [.ask, .skip, .replace, .keepBoth]
        case .slides: return [.skip, .keepBoth]
        }
    }

    /// What to do when the operator has not said otherwise.
    ///
    /// Identical content is always Skip, whatever the kind: re-dropping a file
    /// you already have is not a conflict, and asking about it would make a
    /// 200-file import unusable. The interesting defaults are for content that
    /// genuinely differs.
    static func suggested(for verdict: DuplicateVerdict, kind: ImportKind) -> DuplicatePolicy {
        switch verdict {
        case .unique:
            return .keepBoth
        case .identical:
            return .skip
        case .sameIdentityDifferentContent:
            switch kind {
            case .bible, .session, .theme: return .ask
            case .song: return .addAsVersion
            case .media, .slides: return .skip
            }
        case .probable:
            switch kind {
            // Only a weak match reaches here. A song sharing nothing but its
            // title is not the same song, and merging two different ones is
            // worse than keeping both.
            case .song: return .keepBoth
            case .media: return .skip
            case .bible, .session, .theme, .slides: return .ask
            }
        }
    }
}

// MARK: - The comparison

nonisolated protocol DuplicateComparable: Sendable {
    /// The identity ladder — first rule that hits wins. nil = not the same thing.
    func identityMatch(with other: Self) -> (matchedOn: String, confidence: DuplicateConfidence)?
    /// What "different content" means here, in words the operator can read.
    func differences(from other: Self) -> [String]
}

nonisolated enum DuplicateResolver {

    static func verdict<T: DuplicateComparable>(for incoming: T, against existing: [T]) -> DuplicateVerdict {
        for (index, candidate) in existing.enumerated() {
            guard let identity = incoming.identityMatch(with: candidate) else { continue }
            let match = DuplicateMatch(
                existingIndex: index,
                confidence: identity.confidence,
                matchedOn: identity.matchedOn,
                differences: incoming.differences(from: candidate)
            )
            if match.differences.isEmpty { return .identical(match) }
            // Strong evidence is still evidence of the SAME thing: two modules
            // sharing an abbreviation and a language, with different verse
            // counts, are one translation in two editions — a decision to make,
            // not a guess to flag. Only a weak match (a shared title and
            // nothing else) is merely probable.
            return identity.confidence >= .strong
                ? .sameIdentityDifferentContent(match)
                : .probable(match)
        }
        return .unique
    }

    /// Duplicates WITHIN one batch, by file fingerprint.
    ///
    /// The scanner already drops the same path picked twice. It cannot see that
    /// `Biblia.tpbible` and `Biblia copy.tpbible` in the same folder are the
    /// same file — both import today. Returns, for each index that duplicates an
    /// earlier one, the index it duplicates: the first is kept and the rest are
    /// deselected, with the row saying which file it matched.
    static func duplicatesWithinBatch(_ fingerprints: [ContentFingerprint?]) -> [Int: Int] {
        var firstSeen: [ContentFingerprint: Int] = [:]
        var duplicates: [Int: Int] = [:]
        for (index, fingerprint) in fingerprints.enumerated() {
            guard let fingerprint else { continue }
            if let original = firstSeen[fingerprint] {
                duplicates[index] = original
            } else {
                firstSeen[fingerprint] = index
            }
        }
        return duplicates
    }
}

// MARK: - File fingerprint

/// Cheap enough to take on every candidate: the size, plus a digest of the
/// first 64 KB. The classifier already reads a prefix to identify the format,
/// so this costs nothing extra beyond the file already being open.
///
/// It identifies FILES, not content: two exports of the same module differ in
/// their `exportedAt` and so fingerprint differently. That is what the per-type
/// identity ladders are for.
nonisolated struct ContentFingerprint: Sendable, Equatable, Hashable {
    let byteSize: Int
    let digest: String

    static let sampleLength = 64 * 1024

    init(byteSize: Int, digest: String) {
        self.byteSize = byteSize
        self.digest = digest
    }

    init?(contentsOf url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let sample = try? handle.read(upToCount: Self.sampleLength) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? sample.count
        self.init(byteSize: size, digest: Self.digest(of: sample))
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(of text: String) -> String {
        digest(of: Data(text.utf8))
    }
}

// MARK: - Bible

nonisolated struct BibleIdentity: DuplicateComparable, Equatable {
    /// Stable across libraries, carried in the file header. Empty for modules
    /// imported before it existed, which is why the ladder has two more rungs.
    var contentID = ""
    var abbreviation = ""
    var language = ""
    var name = ""
    var bookCount = 0
    var verseCount = 0
    /// The module's SHAPE plus a few of its words: one entry per chapter
    /// (book, chapter, verse count), then the text of three verses that exist
    /// in essentially every edition.
    ///
    /// The shape half is not optional. Counting books and verses alone called
    /// two modules identical whenever they happened to total the same — a
    /// partial Daniel 6+8 and a partial Daniel 6+7 have one book and two verses
    /// each — and "identical" means "skip silently", so the second module would
    /// have been dropped without a word. Per-chapter counts are as cheap as the
    /// verse count, which already walks the whole module.
    var contentDigest = ""

    func identityMatch(with other: Self) -> (matchedOn: String, confidence: DuplicateConfidence)? {
        if !contentID.isEmpty, contentID == other.contentID {
            return (String(localized: "the same module", comment: "Duplicate match reason"), .certain)
        }
        // Language matters: two different-language modules can legitimately
        // share an abbreviation, and merging them would be nonsense.
        if !abbreviation.isEmpty,
           abbreviation.caseInsensitiveCompare(other.abbreviation) == .orderedSame,
           language.caseInsensitiveCompare(other.language) == .orderedSame {
            return (String(localized: "abbreviation \(abbreviation) and language \(language)",
                           comment: "Duplicate match reason"), .strong)
        }
        // A module with no abbreviation was never matched at all before, so
        // every re-import of one silently duplicated it.
        if abbreviation.isEmpty, other.abbreviation.isEmpty,
           !name.isEmpty, name.caseInsensitiveCompare(other.name) == .orderedSame {
            return (String(localized: "the name \(name)", comment: "Duplicate match reason"), .weak)
        }
        return nil
    }

    func differences(from other: Self) -> [String] {
        var out: [String] = []
        if bookCount != other.bookCount {
            out.append(String(localized: "\(bookCount) books against \(other.bookCount)",
                              comment: "Duplicate difference"))
        }
        if verseCount != other.verseCount {
            out.append(String(localized: "\(verseCount) verses against \(other.verseCount)",
                              comment: "Duplicate difference"))
        }
        if contentDigest != other.contentDigest, bookCount == other.bookCount, verseCount == other.verseCount {
            out.append(String(localized: "the same number of books and verses, but different content",
                              comment: "Duplicate difference"))
        }
        return out
    }
}

// MARK: - Song

nonisolated struct SongIdentity: DuplicateComparable, Equatable {
    var ccliNumber = ""
    var normalizedTitle = ""
    /// The strongest cheap signal there is. Titles vary across translations and
    /// songbooks; first lines do not.
    var normalizedFirstLine = ""
    var versionCount = 0
    var sectionCount = 0
    var lyricsDigest = ""

    func identityMatch(with other: Self) -> (matchedOn: String, confidence: DuplicateConfidence)? {
        if !ccliNumber.isEmpty, ccliNumber == other.ccliNumber {
            return (String(localized: "CCLI \(ccliNumber)", comment: "Duplicate match reason"), .certain)
        }
        if !normalizedTitle.isEmpty, normalizedTitle == other.normalizedTitle {
            if !normalizedFirstLine.isEmpty, normalizedFirstLine == other.normalizedFirstLine {
                return (String(localized: "the title and the first line",
                               comment: "Duplicate match reason"), .strong)
            }
            return (String(localized: "the title only", comment: "Duplicate match reason"), .weak)
        }
        return nil
    }

    func differences(from other: Self) -> [String] {
        var out: [String] = []
        if lyricsDigest != other.lyricsDigest {
            out.append(String(localized: "the lyrics differ", comment: "Duplicate difference"))
        }
        if versionCount != other.versionCount {
            out.append(String(localized: "\(versionCount) arrangements against \(other.versionCount)",
                              comment: "Duplicate difference"))
        }
        if sectionCount != other.sectionCount, versionCount == other.versionCount {
            out.append(String(localized: "\(sectionCount) sections against \(other.sectionCount)",
                              comment: "Duplicate difference"))
        }
        return out
    }
}

// MARK: - Media

nonisolated struct MediaIdentity: DuplicateComparable, Equatable {
    var resolvedPath = ""
    var filename = ""
    var byteSize = 0

    func identityMatch(with other: Self) -> (matchedOn: String, confidence: DuplicateConfidence)? {
        if !resolvedPath.isEmpty, resolvedPath == other.resolvedPath {
            return (String(localized: "the same file on disk", comment: "Duplicate match reason"), .certain)
        }
        if !filename.isEmpty, filename == other.filename, byteSize == other.byteSize, byteSize > 0 {
            return (String(localized: "the name and the size", comment: "Duplicate match reason"), .strong)
        }
        return nil
    }

    /// No content hash, deliberately: hashing multi-GB video on import
    /// beach-balls, and path plus name plus size catches every realistic case.
    /// Stated as a limit rather than hidden — two different clips with the same
    /// name and byte size would be taken for one.
    func differences(from other: Self) -> [String] {
        guard byteSize != other.byteSize else { return [] }
        return [String(localized: "the file at that path has changed size",
                       comment: "Duplicate difference")]
    }
}

// MARK: - Session

nonisolated struct SessionIdentity: DuplicateComparable, Equatable {
    var sessionID = ""
    var name = ""
    var dateISO = ""
    var itemCount = 0
    var itemTypes: [String] = []

    func identityMatch(with other: Self) -> (matchedOn: String, confidence: DuplicateConfidence)? {
        if !sessionID.isEmpty, sessionID == other.sessionID {
            return (String(localized: "the same session", comment: "Duplicate match reason"), .certain)
        }
        if !name.isEmpty, name == other.name, dateISO == other.dateISO {
            return (String(localized: "the name and the date", comment: "Duplicate match reason"), .strong)
        }
        return nil
    }

    func differences(from other: Self) -> [String] {
        var out: [String] = []
        if itemCount != other.itemCount {
            out.append(String(localized: "\(itemCount) items against \(other.itemCount)",
                              comment: "Duplicate difference"))
        } else if itemTypes != other.itemTypes {
            out.append(String(localized: "the same number of items, in a different order",
                              comment: "Duplicate difference"))
        }
        return out
    }
}

// MARK: - Theme

nonisolated struct ThemeIdentity: DuplicateComparable, Equatable {
    var id = ""
    var name = ""
    var payloadDigest = ""

    func identityMatch(with other: Self) -> (matchedOn: String, confidence: DuplicateConfidence)? {
        if !id.isEmpty, id == other.id {
            return (String(localized: "the same theme", comment: "Duplicate match reason"), .certain)
        }
        if !name.isEmpty, name.caseInsensitiveCompare(other.name) == .orderedSame {
            return (String(localized: "the name \(name)", comment: "Duplicate match reason"), .strong)
        }
        return nil
    }

    func differences(from other: Self) -> [String] {
        payloadDigest == other.payloadDigest
            ? []
            : [String(localized: "the look differs", comment: "Duplicate difference")]
    }
}
