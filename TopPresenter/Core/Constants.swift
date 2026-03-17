//
//  Constants.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation

// MARK: - Window Identifiers
enum WindowIdentifiers {
    static let main = "main-control"
    static let presentation = "presentation-output"
}

// MARK: - Supported File Types
enum SupportedBibleFormat: String, CaseIterable, Identifiable {
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
enum SupportedExportFormat: String, CaseIterable, Identifiable {
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
enum USFMBookIDs {
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
enum BibleBookNumbers {
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

enum SupportedSongFormat: String, CaseIterable, Identifiable {
    case openSongXML = "opensong"
    case openLyricsXML = "openlyrics"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openSongXML: return String(localized: "OpenSong XML", comment: "Song format name")
        case .openLyricsXML: return String(localized: "OpenLyrics XML", comment: "Song format name")
        }
    }

    var fileExtensions: [String] {
        switch self {
        case .openSongXML: return ["xml"]
        case .openLyricsXML: return ["xml"]
        }
    }
}

// MARK: - Presentation Defaults
enum PresentationDefaults {
    static let fontSize: Double = 48.0
    static let minFontSize: Double = 12.0
    static let maxFontSize: Double = 120.0
    static let backgroundOpacity: Double = 0.7
    static let textColor = "FFFFFF"
    static let backgroundColor = "000000"
    static let fontName = "System"
    static let lineSpacing: Double = 1.2
    static let padding: Double = 40.0
    static let transitionDuration: Double = 0.3
}

// MARK: - Bible Book Names (English canonical order)
enum BibleBookNames {
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

// MARK: - OSIS Book ID Mapping
enum OSISBookIDs {
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
