//
//  Constants.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

// MARK: - Window Identifiers
nonisolated enum WindowIdentifiers {
    static let main = "main-control"
    static let presentation = "presentation-output"
}

// MARK: - Supported File Types
nonisolated enum SupportedBibleFormat: String, CaseIterable, Identifiable {
    case topPresenter = "toppresenter"
    case osisXML = "osis"
    case zefaniaXML = "zefania"
    case mySword = "mysword"
    case usfm = "usfm"
    case unboundBible = "unbound"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topPresenter: return String(localized: "TopPresenter JSON", comment: "Bible format name")
        case .osisXML: return String(localized: "OSIS XML", comment: "Bible format name")
        case .zefaniaXML: return String(localized: "Zefania XML", comment: "Bible format name")
        case .mySword: return String(localized: "MySword", comment: "Bible format name")
        case .usfm: return String(localized: "USFM", comment: "Bible format name")
        case .unboundBible: return String(localized: "Unbound Bible", comment: "Bible format name")
        }
    }

    var fileExtensions: [String] {
        switch self {
        case .topPresenter: return ["json"]
        case .osisXML: return ["xml", "osis"]
        case .zefaniaXML: return ["xml", "zef"]
        case .mySword: return ["mybible", "bbl.mybible"]
        case .usfm: return ["usfm", "sfm", "txt"]
        case .unboundBible: return ["txt", "utf8"]
        }
    }

    var formatDescription: String {
        switch self {
        case .topPresenter: return String(localized: "TopPresenter native JSON format with cross-references, footnotes, and headings", comment: "Format description")
        case .osisXML: return String(localized: "Open Scripture Information Standard XML format", comment: "Format description")
        case .zefaniaXML: return String(localized: "Zefania XML Bible format", comment: "Format description")
        case .mySword: return String(localized: "MySword SQLite database (.bbl.mybible)", comment: "Format description")
        case .usfm: return String(localized: "Unified Standard Format Markers (folder of .usfm files)", comment: "Format description")
        case .unboundBible: return String(localized: "Tab-delimited text format from Unbound Bible project", comment: "Format description")
        }
    }

    /// Whether this format uses a directory (multiple files) rather than a single file
    var isDirectoryFormat: Bool {
        switch self {
        case .usfm: return true
        default: return false
        }
    }
}

// MARK: - Supported Export Formats
nonisolated enum SupportedExportFormat: String, CaseIterable, Identifiable {
    case topPresenter = "toppresenter"
    case plainText = "plaintext"
    case csv = "csv"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topPresenter: return String(localized: "TopPresenter JSON", comment: "Export format")
        case .plainText: return String(localized: "Plain Text", comment: "Export format")
        case .csv: return String(localized: "CSV", comment: "Export format")
        }
    }

    var fileExtension: String {
        switch self {
        case .topPresenter: return "json"
        case .plainText: return "txt"
        case .csv: return "csv"
        }
    }

    var formatDescription: String {
        switch self {
        case .topPresenter: return String(localized: "Native JSON with all metadata, cross-references, footnotes, and section headings", comment: "Export format description")
        case .plainText: return String(localized: "Simple text file with book, chapter, and verse numbers", comment: "Export format description")
        case .csv: return String(localized: "Comma-separated values: Book, Chapter, Verse, Text", comment: "Export format description")
        }
    }
}

// MARK: - USFM Book Abbreviation Mapping
nonisolated enum USFMBookIDs {
    static let mapping: [String: (name: String, number: Int)] = [
        "GEN": ("Genesis", 1), "EXO": ("Exodus", 2), "LEV": ("Leviticus", 3),
        "NUM": ("Numbers", 4), "DEU": ("Deuteronomy", 5), "JOS": ("Joshua", 6),
        "JDG": ("Judges", 7), "RUT": ("Ruth", 8), "1SA": ("1 Samuel", 9),
        "2SA": ("2 Samuel", 10), "1KI": ("1 Kings", 11), "2KI": ("2 Kings", 12),
        "1CH": ("1 Chronicles", 13), "2CH": ("2 Chronicles", 14), "EZR": ("Ezra", 15),
        "NEH": ("Nehemiah", 16), "EST": ("Esther", 17), "JOB": ("Job", 18),
        "PSA": ("Psalms", 19), "PRO": ("Proverbs", 20), "ECC": ("Ecclesiastes", 21),
        "SNG": ("Song of Solomon", 22), "ISA": ("Isaiah", 23), "JER": ("Jeremiah", 24),
        "LAM": ("Lamentations", 25), "EZK": ("Ezekiel", 26), "DAN": ("Daniel", 27),
        "HOS": ("Hosea", 28), "JOL": ("Joel", 29), "AMO": ("Amos", 30),
        "OBA": ("Obadiah", 31), "JON": ("Jonah", 32), "MIC": ("Micah", 33),
        "NAM": ("Nahum", 34), "HAB": ("Habakkuk", 35), "ZEP": ("Zephaniah", 36),
        "HAG": ("Haggai", 37), "ZEC": ("Zechariah", 38), "MAL": ("Malachi", 39),
        "MAT": ("Matthew", 40), "MRK": ("Mark", 41), "LUK": ("Luke", 42),
        "JHN": ("John", 43), "ACT": ("Acts", 44), "ROM": ("Romans", 45),
        "1CO": ("1 Corinthians", 46), "2CO": ("2 Corinthians", 47),
        "GAL": ("Galatians", 48), "EPH": ("Ephesians", 49), "PHP": ("Philippians", 50),
        "COL": ("Colossians", 51), "1TH": ("1 Thessalonians", 52),
        "2TH": ("2 Thessalonians", 53), "1TI": ("1 Timothy", 54),
        "2TI": ("2 Timothy", 55), "TIT": ("Titus", 56), "PHM": ("Philemon", 57),
        "HEB": ("Hebrews", 58), "JAS": ("James", 59), "1PE": ("1 Peter", 60),
        "2PE": ("2 Peter", 61), "1JN": ("1 John", 62), "2JN": ("2 John", 63),
        "3JN": ("3 John", 64), "JUD": ("Jude", 65), "REV": ("Revelation", 66)
    ]
}

// MARK: - MySword/Unbound Book Number Mapping
nonisolated enum BibleBookNumbers {
    /// Maps 1-based book number to (name, testament)
    static let mapping: [Int: (name: String, testament: String)] = {
        var map: [Int: (name: String, testament: String)] = [:]
        for (i, name) in BibleBookNames.oldTestament.enumerated() {
            map[i + 1] = (name, "OT")
        }
        for (i, name) in BibleBookNames.newTestament.enumerated() {
            map[i + 40] = (name, "NT")
        }
        return map
    }()
}

nonisolated enum SupportedSongFormat: String, CaseIterable, Identifiable {
    case topPresenterJSON = "toppresenter-song"
    case openSongXML = "opensong"
    case openLyricsXML = "openlyrics"
    case chordPro = "chordpro"
    case plainText = "plaintext"
    case powerPoint = "powerpoint"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topPresenterJSON: return String(localized: "TopPresenter Song JSON", comment: "Song format name")
        case .openSongXML: return String(localized: "OpenSong XML", comment: "Song format name")
        case .openLyricsXML: return String(localized: "OpenLyrics XML", comment: "Song format name")
        case .chordPro: return String(localized: "ChordPro", comment: "Song format name")
        case .plainText: return String(localized: "Plain Text", comment: "Song format name")
        case .powerPoint: return String(localized: "PowerPoint", comment: "Song format name")
        }
    }

    var fileExtensions: [String] {
        switch self {
        case .topPresenterJSON: return ["json"]
        case .openSongXML: return ["xml"]
        case .openLyricsXML: return ["xml"]
        case .chordPro: return ["cho", "crd", "chordpro", "chopro"]
        case .plainText: return ["txt"]
        case .powerPoint: return ["pptx", "ppt"]
        }
    }
}

// MARK: - Supported Song Export Formats
nonisolated enum SupportedSongExportFormat: String, CaseIterable, Identifiable {
    case topPresenter = "toppresenter"
    case openLyricsXML = "openlyrics"
    case plainText = "plaintext"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .topPresenter: return String(localized: "TopPresenter JSON", comment: "Song export format")
        case .openLyricsXML: return String(localized: "OpenLyrics XML", comment: "Song export format")
        case .plainText: return String(localized: "Plain Text", comment: "Song export format")
        }
    }

    var fileExtension: String {
        switch self {
        case .topPresenter: return "json"
        case .openLyricsXML: return "xml"
        case .plainText: return "txt"
        }
    }

    /// The format identifier stored at the top of the export file
    var formatIdentifier: String {
        switch self {
        case .topPresenter: return "TopPresenter Songs"
        case .openLyricsXML: return "OpenLyrics"
        case .plainText: return "Plain Text"
        }
    }
}

// MARK: - Presentation Defaults
nonisolated enum PresentationDefaults {
    static let fontSize: Double = 48.0
    static let minFontSize: Double = 12.0
    static let maxFontSize: Double = 200.0
    static let backgroundOpacity: Double = 0.7
    static let textColor = "FFFFFF"
    static let backgroundColor = "000000"
    static let fontName = "System"
    static let lineSpacing: Double = 1.2
    static let padding: Double = 40.0
    static let transitionDuration: Double = 0.3
}

// MARK: - Bible Book Names (English canonical order)
nonisolated enum BibleBookNames {
    static let oldTestament: [String] = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy",
        "Joshua", "Judges", "Ruth", "1 Samuel", "2 Samuel",
        "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles",
        "Ezra", "Nehemiah", "Esther", "Job", "Psalms",
        "Proverbs", "Ecclesiastes", "Song of Solomon", "Isaiah", "Jeremiah",
        "Lamentations", "Ezekiel", "Daniel", "Hosea", "Joel",
        "Amos", "Obadiah", "Jonah", "Micah", "Nahum",
        "Habakkuk", "Zephaniah", "Haggai", "Zechariah", "Malachi"
    ]

    static let newTestament: [String] = [
        "Matthew", "Mark", "Luke", "John", "Acts",
        "Romans", "1 Corinthians", "2 Corinthians", "Galatians", "Ephesians",
        "Philippians", "Colossians", "1 Thessalonians", "2 Thessalonians",
        "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews",
        "James", "1 Peter", "2 Peter", "1 John", "2 John",
        "3 John", "Jude", "Revelation"
    ]

    static let all: [String] = oldTestament + newTestament
}

// MARK: - Bible Book Categories (for color-coding like BibleShow)
import SwiftUI

nonisolated enum BibleBookCategory: String, CaseIterable {
    case law            // Genesis–Deuteronomy (1–5)
    case history        // Joshua–Esther (6–17)
    case wisdom         // Job–Song of Solomon (18–22)
    case majorProphets  // Isaiah–Daniel (23–27)
    case minorProphets  // Hosea–Malachi (28–39)
    case gospels        // Matthew–John (40–43)
    case acts           // Acts (44)
    case paulineEpistles // Romans–Philemon (45–57)
    case generalEpistles // Hebrews–Jude (58–65)
    case prophecy       // Revelation (66)

    /// Color for this category — matches BibleShow-style palette.
    var color: Color {
        switch self {
        case .law:              return Color(red: 0.60, green: 0.85, blue: 0.60) // green
        case .history:          return Color(red: 0.55, green: 0.75, blue: 0.95) // blue
        case .wisdom:           return Color(red: 0.95, green: 0.85, blue: 0.45) // gold/yellow
        case .majorProphets:    return Color(red: 0.95, green: 0.65, blue: 0.35) // deep orange
        case .minorProphets:    return Color(red: 0.75, green: 0.30, blue: 0.30) // deep red/crimson
        case .gospels:          return Color(red: 0.65, green: 0.45, blue: 0.90) // deep purple
        case .acts:             return Color(red: 0.45, green: 0.85, blue: 0.85) // teal
        case .paulineEpistles:  return Color(red: 0.55, green: 0.75, blue: 0.95) // sky blue
        case .generalEpistles:  return Color(red: 0.70, green: 0.85, blue: 0.75) // mint
        case .prophecy:         return Color(red: 0.95, green: 0.55, blue: 0.70) // pink
        }
    }

    /// Darker text-friendly version for labels on light backgrounds.
    var darkColor: Color {
        switch self {
        case .law:              return Color(red: 0.20, green: 0.50, blue: 0.20)
        case .history:          return Color(red: 0.15, green: 0.35, blue: 0.65)
        case .wisdom:           return Color(red: 0.60, green: 0.50, blue: 0.10)
        case .majorProphets:    return Color(red: 0.70, green: 0.35, blue: 0.05)
        case .minorProphets:    return Color(red: 0.55, green: 0.10, blue: 0.10)
        case .gospels:          return Color(red: 0.35, green: 0.20, blue: 0.60)
        case .acts:             return Color(red: 0.10, green: 0.50, blue: 0.50)
        case .paulineEpistles:  return Color(red: 0.25, green: 0.45, blue: 0.70)
        case .generalEpistles:  return Color(red: 0.25, green: 0.50, blue: 0.35)
        case .prophecy:         return Color(red: 0.65, green: 0.20, blue: 0.35)
        }
    }

    /// Romanian name for the category.
    var romanianName: String {
        switch self {
        case .law:              return "Legea / Pentateuhul"
        case .history:          return "Cărți Istorice"
        case .wisdom:           return "Poezie și Înțelepciune"
        case .majorProphets:    return "Profeți Mari"
        case .minorProphets:    return "Profeți Mici"
        case .gospels:          return "Evanghelii"
        case .acts:             return "Faptele Apostolilor"
        case .paulineEpistles:  return "Epistolele lui Pavel"
        case .generalEpistles:  return "Epistole Generale"
        case .prophecy:         return "Profeție / Apocalipsa"
        }
    }

    /// English name for the category (fallback for export/import).
    var englishName: String {
        switch self {
        case .law:              return "Law / Pentateuch"
        case .history:          return "History"
        case .wisdom:           return "Poetry & Wisdom"
        case .majorProphets:    return "Major Prophets"
        case .minorProphets:    return "Minor Prophets"
        case .gospels:          return "Gospels"
        case .acts:             return "Acts"
        case .paulineEpistles:  return "Pauline Epistles"
        case .generalEpistles:  return "General Epistles"
        case .prophecy:         return "Prophecy"
        }
    }

    var localizedName: String {
        // Prefer Romanian, but fall back to localized English
        let locale = Locale.current.language.languageCode?.identifier ?? "en"
        if locale == "ro" {
            return romanianName
        }
        switch self {
        case .law:              return String(localized: "Legea / Pentateuhul", comment: "Bible category")
        case .history:          return String(localized: "Cărți Istorice", comment: "Bible category")
        case .wisdom:           return String(localized: "Poezie și Înțelepciune", comment: "Bible category")
        case .majorProphets:    return String(localized: "Profeți Mari", comment: "Bible category")
        case .minorProphets:    return String(localized: "Profeți Mici", comment: "Bible category")
        case .gospels:          return String(localized: "Evanghelii", comment: "Bible category")
        case .acts:             return String(localized: "Faptele Apostolilor", comment: "Bible category")
        case .paulineEpistles:  return String(localized: "Epistolele lui Pavel", comment: "Bible category")
        case .generalEpistles:  return String(localized: "Epistole Generale", comment: "Bible category")
        case .prophecy:         return String(localized: "Profeție / Apocalipsa", comment: "Bible category")
        }
    }

    /// Determine category from 1-based book number (works regardless of language).
    static func from(bookNumber: Int) -> BibleBookCategory {
        switch bookNumber {
        case 1...5:   return .law
        case 6...17:  return .history
        case 18...22: return .wisdom
        case 23...27: return .majorProphets
        case 28...39: return .minorProphets
        case 40...43: return .gospels
        case 44:      return .acts
        case 45...57: return .paulineEpistles
        case 58...65: return .generalEpistles
        case 66:      return .prophecy
        default:      return .history // fallback
        }
    }
}

// MARK: - OSIS Book ID Mapping
nonisolated enum OSISBookIDs {
    static let mapping: [String: String] = [
        "Gen": "Genesis", "Exod": "Exodus", "Lev": "Leviticus",
        "Num": "Numbers", "Deut": "Deuteronomy", "Josh": "Joshua",
        "Judg": "Judges", "Ruth": "Ruth", "1Sam": "1 Samuel",
        "2Sam": "2 Samuel", "1Kgs": "1 Kings", "2Kgs": "2 Kings",
        "1Chr": "1 Chronicles", "2Chr": "2 Chronicles", "Ezra": "Ezra",
        "Neh": "Nehemiah", "Esth": "Esther", "Job": "Job",
        "Ps": "Psalms", "Prov": "Proverbs", "Eccl": "Ecclesiastes",
        "Song": "Song of Solomon", "Isa": "Isaiah", "Jer": "Jeremiah",
        "Lam": "Lamentations", "Ezek": "Ezekiel", "Dan": "Daniel",
        "Hos": "Hosea", "Joel": "Joel", "Amos": "Amos",
        "Obad": "Obadiah", "Jonah": "Jonah", "Mic": "Micah",
        "Nah": "Nahum", "Hab": "Habakkuk", "Zeph": "Zephaniah",
        "Hag": "Haggai", "Zech": "Zechariah", "Mal": "Malachi",
        "Matt": "Matthew", "Mark": "Mark", "Luke": "Luke",
        "John": "John", "Acts": "Acts", "Rom": "Romans",
        "1Cor": "1 Corinthians", "2Cor": "2 Corinthians",
        "Gal": "Galatians", "Eph": "Ephesians", "Phil": "Philippians",
        "Col": "Colossians", "1Thess": "1 Thessalonians",
        "2Thess": "2 Thessalonians", "1Tim": "1 Timothy",
        "2Tim": "2 Timothy", "Titus": "Titus", "Phlm": "Philemon",
        "Heb": "Hebrews", "Jas": "James", "1Pet": "1 Peter",
        "2Pet": "2 Peter", "1John": "1 John", "2John": "2 John",
        "3John": "3 John", "Jude": "Jude", "Rev": "Revelation"
    ]
}
