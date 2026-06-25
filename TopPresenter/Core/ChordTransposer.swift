//
//  ChordTransposer.swift
//  TopPresenter
//
//  Music-theory helper for the chord/transpose feature: parse a chord symbol
//  (root + quality + optional bass), transpose it by a number of semitones with
//  sensible enharmonic spelling, compute the interval between two keys, and derive
//  capo "shape" chords + capo suggestions for common open-chord keys.
//
//  Pure value logic — no UI, no model dependencies — so it is trivially testable.
//

import Foundation

enum ChordTransposer {

    // MARK: - Pitch-class tables

    /// Twelve pitch classes spelled with sharps (index = semitone, C = 0).
    static let sharpNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    /// Twelve pitch classes spelled with flats.
    static let flatNames  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    /// The full circle of keys offered in the transpose picker (one spelling per
    /// pitch class — the most common in worship lead sheets).
    static let keyWheel = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    /// Keys conventionally notated with flats (major + relative-minor roots).
    private static let flatKeyRoots: Set<String> = ["F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb"]
    /// Minor keys whose key signature uses flats.
    private static let flatMinorRoots: Set<String> = ["D", "G", "C", "F", "Bb", "Eb", "Ab"]

    // MARK: - Note <-> pitch class

    /// Pitch class (0–11) for a note name like "C", "C#", "Db", "B#", "Cb".
    /// Returns nil for anything that is not a note letter + optional accidental.
    static func pitchClass(of note: String) -> Int? {
        let n = note.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
        guard let letter = n.first else { return nil }
        let base: Int
        switch letter {
        case "C": base = 0
        case "D": base = 2
        case "E": base = 4
        case "F": base = 5
        case "G": base = 7
        case "A": base = 9
        case "B": base = 11
        default: return nil
        }
        var semitone = base
        for accidental in n.dropFirst() {
            if accidental == "#" { semitone += 1 }
            else if accidental == "b" { semitone -= 1 }
            else { break }   // not part of the root (it's the quality, e.g. "Cmaj7")
        }
        return ((semitone % 12) + 12) % 12
    }

    /// Spell a pitch class as a note name, choosing sharps or flats.
    static func name(forPitchClass pc: Int, preferFlats: Bool) -> String {
        let i = ((pc % 12) + 12) % 12
        return preferFlats ? flatNames[i] : sharpNames[i]
    }

    // MARK: - Key flavour

    /// Whether a key should be spelled with flats. Accepts "Eb", "Ebm", "Bbm", etc.
    static func preferFlats(forKey key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let isMinor = trimmed.lowercased().hasSuffix("m") && !trimmed.lowercased().hasSuffix("dim")
        // Root = leading letter + accidental(s).
        var root = String(trimmed.prefix(1))
        for ch in trimmed.dropFirst() where ch == "#" || ch == "b" || ch == "♯" || ch == "♭" {
            root.append(ch == "♯" ? "#" : (ch == "♭" ? "b" : ch))
        }
        if root.contains("b") { return true }
        if root.contains("#") { return false }
        return isMinor ? flatMinorRoots.contains(root) : flatKeyRoots.contains(root)
    }

    /// Semitone distance to get FROM one key TO another (0–11, forward).
    static func semitones(fromKey from: String, toKey to: String) -> Int {
        guard let a = pitchClass(of: from), let b = pitchClass(of: to) else { return 0 }
        return ((b - a) % 12 + 12) % 12
    }

    // MARK: - Chord parsing + transposition

    /// A chord broken into root, the quality text in between, and an optional bass.
    struct ParsedChord {
        var rootPC: Int
        var quality: String      // e.g. "m7", "sus4", "maj7", "" for a plain major
        var bassPC: Int?
        var hadBass: Bool { bassPC != nil }
    }

    /// Parse a chord symbol. Returns nil when the leading token isn't a note
    /// (e.g. "N.C.", "%", a stray annotation) so callers can leave it untouched.
    static func parse(_ symbol: String) -> ParsedChord? {
        let sym = symbol.trimmingCharacters(in: .whitespaces)
        guard !sym.isEmpty else { return nil }

        // Split off a slash bass first ("D/F#").
        let slashParts = sym.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let main = String(slashParts[0])
        let bassStr = slashParts.count > 1 ? String(slashParts[1]) : nil

        guard let (rootPC, qualityStart) = parseRoot(main) else { return nil }
        let quality = String(main[qualityStart...])
        let bassPC = bassStr.flatMap { pitchClass(of: $0) }
        return ParsedChord(rootPC: rootPC, quality: quality, bassPC: bassStr == nil ? nil : (bassPC ?? rootPC))
    }

    /// Read a root note off the front of a chord body, returning its pitch class
    /// and the index where the quality begins.
    private static func parseRoot(_ body: String) -> (pc: Int, qualityStart: String.Index)? {
        guard let letter = body.first, "ABCDEFG".contains(letter) else { return nil }
        var idx = body.index(after: body.startIndex)
        var root = String(letter)
        // At most one accidental belongs to the root.
        if idx < body.endIndex {
            let c = body[idx]
            if c == "#" || c == "b" || c == "♯" || c == "♭" {
                root.append(c == "♯" ? "#" : (c == "♭" ? "b" : c))
                idx = body.index(after: idx)
            }
        }
        guard let pc = pitchClass(of: root) else { return nil }
        return (pc, idx)
    }

    /// Transpose a single chord symbol by `semitones`, spelling with `preferFlats`.
    /// Unparseable tokens are returned unchanged.
    static func transpose(_ symbol: String, by semitones: Int, preferFlats: Bool) -> String {
        guard let parsed = parse(symbol) else { return symbol }
        let newRoot = name(forPitchClass: parsed.rootPC + semitones, preferFlats: preferFlats)
        var out = newRoot + parsed.quality
        if let bass = parsed.bassPC {
            out += "/" + name(forPitchClass: bass + semitones, preferFlats: preferFlats)
        }
        return out
    }

    // MARK: - Whole-line / song transposition (sym only; positions are unchanged)

    /// Transpose every chord on a line, keeping each chord at its character offset.
    static func transpose(line: SongLine, by semitones: Int, preferFlats: Bool) -> SongLine {
        guard !line.chords.isEmpty, semitones % 12 != 0 else { return line }
        let moved = line.chords.map { SongChord(sym: transpose($0.sym, by: semitones, preferFlats: preferFlats), pos: $0.pos) }
        return SongLine(text: line.text, chords: moved, translations: line.translations)
    }

    // MARK: - Capo

    /// The chord shapes a capo'd player actually fingers: the sounding chords
    /// transposed DOWN by the capo fret (capo raises pitch, so shapes sit lower).
    static func shapeChord(_ soundingSymbol: String, capo: Int, preferFlats: Bool) -> String {
        guard capo != 0 else { return soundingSymbol }
        return transpose(soundingSymbol, by: -capo, preferFlats: preferFlats)
    }

    /// Common open-position keys guitarists capo from.
    static let openShapeKeys = ["G", "E", "D", "A", "C"]

    /// Suggest a capo fret + shape key so a guitarist can play `soundingKey` using
    /// familiar open shapes. Frets 1–7, smallest first.
    static func capoSuggestions(forSoundingKey soundingKey: String) -> [(capo: Int, shapeKey: String)] {
        guard let soundPC = pitchClass(of: soundingKey) else { return [] }
        var seen = Set<Int>()
        var out: [(Int, String)] = []
        for shape in openShapeKeys {
            guard let shapePC = pitchClass(of: shape) else { continue }
            let fret = ((soundPC - shapePC) % 12 + 12) % 12
            guard fret >= 1, fret <= 7, !seen.contains(fret) else { continue }
            seen.insert(fret)
            out.append((fret, shape))
        }
        return out.sorted { $0.0 < $1.0 }
    }

    // MARK: - Recommended keys (from scraped _extensions)

    /// Pull a list of recommended key strings out of a song's `_extensions` JSON
    /// blob (worshipTogether `recommendedKeys`, melodia `keys`, etc.). Best-effort.
    static func recommendedKeys(fromExtensionsJSON json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        var found: [String] = []
        for (_, value) in obj {
            guard let dict = value as? [String: Any] else { continue }
            for field in ["recommendedKeys", "keys", "recommended_keys"] {
                if let arr = dict[field] as? [Any] {
                    found.append(contentsOf: arr.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) })
                } else if let s = dict[field] as? String {
                    found.append(contentsOf: s.split(whereSeparator: { ",;/".contains($0) }).map { $0.trimmingCharacters(in: .whitespaces) })
                }
            }
        }
        // Keep only things that parse as a key, de-duplicated, order preserved.
        var seen = Set<String>()
        return found.filter { !$0.isEmpty && pitchClass(of: $0) != nil && seen.insert($0).inserted }
    }
}
