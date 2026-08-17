//
//  BibleBookLocalization.swift
//  TopPresenter
//
//  Book names in the language of the APP, not of the translation.
//
//  A module carries the book names its source file happened to use: a Cornilescu
//  file says "Geneza", a Reina-Valera file says "Génesis". Displaying those raw
//  meant an operator running the app in English read a Romanian book list — the
//  library is the operator's tool, and it has to speak the operator's language
//  whatever translation is loaded.
//
//  What this does NOT touch, deliberately:
//   • the reference on the LIVE OUTPUT — the congregation is reading the
//     translation, so "Geneza 1:1" belongs over Romanian text
//   • anything exported or stored (session items, history rows, `.tpbible`) —
//     those keep the module's own names so files round-trip byte-for-byte
//
//  Identification is by NAME, not by book number. Book numbers cannot be
//  trusted: `OSISBibleImporter` numbers books with a running counter, so an
//  NT-only file has Matthew at 1 — mapping 1 → Genesis there would be a lie.
//  A name resolves through every language we know at once, so "Matthew",
//  "Matei" and "Matthäus" all land on 40 regardless of what the file numbered
//  them. The number is used only as a last resort, and only when the book's own
//  testament agrees with it.
//

import Foundation

nonisolated enum BibleBookLocalization {

    // MARK: - The table (canonical order, 66 entries each)

    /// English is `BibleBookNames.all` — one table, not two.
    private static let en = BibleBookNames.all

    private static let ro: [String] = [
        "Geneza", "Exodul", "Leviticul", "Numeri", "Deuteronomul",
        "Iosua", "Judecători", "Rut", "1 Samuel", "2 Samuel",
        "1 Împărați", "2 Împărați", "1 Cronici", "2 Cronici",
        "Ezra", "Neemia", "Estera", "Iov", "Psalmii",
        "Proverbe", "Eclesiastul", "Cântarea Cântărilor", "Isaia", "Ieremia",
        "Plângerile lui Ieremia", "Ezechiel", "Daniel", "Osea", "Ioel",
        "Amos", "Obadia", "Iona", "Mica", "Naum",
        "Habacuc", "Țefania", "Hagai", "Zaharia", "Maleahi",
        "Matei", "Marcu", "Luca", "Ioan", "Faptele Apostolilor",
        "Romani", "1 Corinteni", "2 Corinteni", "Galateni", "Efeseni",
        "Filipeni", "Coloseni", "1 Tesaloniceni", "2 Tesaloniceni",
        "1 Timotei", "2 Timotei", "Tit", "Filimon", "Evrei",
        "Iacov", "1 Petru", "2 Petru", "1 Ioan", "2 Ioan",
        "3 Ioan", "Iuda", "Apocalipsa"
    ]

    private static let es: [String] = [
        "Génesis", "Éxodo", "Levítico", "Números", "Deuteronomio",
        "Josué", "Jueces", "Rut", "1 Samuel", "2 Samuel",
        "1 Reyes", "2 Reyes", "1 Crónicas", "2 Crónicas",
        "Esdras", "Nehemías", "Ester", "Job", "Salmos",
        "Proverbios", "Eclesiastés", "Cantares", "Isaías", "Jeremías",
        "Lamentaciones", "Ezequiel", "Daniel", "Oseas", "Joel",
        "Amós", "Obadías", "Jonás", "Miqueas", "Nahúm",
        "Habacuc", "Sofonías", "Hageo", "Zacarías", "Malaquías",
        "Mateo", "Marcos", "Lucas", "Juan", "Hechos",
        "Romanos", "1 Corintios", "2 Corintios", "Gálatas", "Efesios",
        "Filipenses", "Colosenses", "1 Tesalonicenses", "2 Tesalonicenses",
        "1 Timoteo", "2 Timoteo", "Tito", "Filemón", "Hebreos",
        "Santiago", "1 Pedro", "2 Pedro", "1 Juan", "2 Juan",
        "3 Juan", "Judas", "Apocalipsis"
    ]

    private static let fr: [String] = [
        "Genèse", "Exode", "Lévitique", "Nombres", "Deutéronome",
        "Josué", "Juges", "Ruth", "1 Samuel", "2 Samuel",
        "1 Rois", "2 Rois", "1 Chroniques", "2 Chroniques",
        "Esdras", "Néhémie", "Esther", "Job", "Psaumes",
        "Proverbes", "Ecclésiaste", "Cantique des Cantiques", "Ésaïe", "Jérémie",
        "Lamentations", "Ézéchiel", "Daniel", "Osée", "Joël",
        "Amos", "Abdias", "Jonas", "Michée", "Nahum",
        "Habaquq", "Sophonie", "Aggée", "Zacharie", "Malachie",
        "Matthieu", "Marc", "Luc", "Jean", "Actes",
        "Romains", "1 Corinthiens", "2 Corinthiens", "Galates", "Éphésiens",
        "Philippiens", "Colossiens", "1 Thessaloniciens", "2 Thessaloniciens",
        "1 Timothée", "2 Timothée", "Tite", "Philémon", "Hébreux",
        "Jacques", "1 Pierre", "2 Pierre", "1 Jean", "2 Jean",
        "3 Jean", "Jude", "Apocalypse"
    ]

    /// Luther naming — what German-speaking congregations read on a hymn board.
    /// `Genesis`/`Exodus`/… are carried as variants so an Einheitsübersetzung
    /// file still resolves.
    private static let de: [String] = [
        "1. Mose", "2. Mose", "3. Mose", "4. Mose", "5. Mose",
        "Josua", "Richter", "Rut", "1. Samuel", "2. Samuel",
        "1. Könige", "2. Könige", "1. Chronik", "2. Chronik",
        "Esra", "Nehemia", "Ester", "Hiob", "Psalmen",
        "Sprüche", "Prediger", "Hoheslied", "Jesaja", "Jeremia",
        "Klagelieder", "Hesekiel", "Daniel", "Hosea", "Joel",
        "Amos", "Obadja", "Jona", "Micha", "Nahum",
        "Habakuk", "Zefanja", "Haggai", "Sacharja", "Maleachi",
        "Matthäus", "Markus", "Lukas", "Johannes", "Apostelgeschichte",
        "Römer", "1. Korinther", "2. Korinther", "Galater", "Epheser",
        "Philipper", "Kolosser", "1. Thessalonicher", "2. Thessalonicher",
        "1. Timotheus", "2. Timotheus", "Titus", "Philemon", "Hebräer",
        "Jakobus", "1. Petrus", "2. Petrus", "1. Johannes", "2. Johannes",
        "3. Johannes", "Judas", "Offenbarung"
    ]

    /// Synodal naming. Note 1–4 Царств covers 1 Samuel … 2 Kings.
    private static let ru: [String] = [
        "Бытие", "Исход", "Левит", "Числа", "Второзаконие",
        "Иисус Навин", "Судей", "Руфь", "1 Царств", "2 Царств",
        "3 Царств", "4 Царств", "1 Паралипоменон", "2 Паралипоменон",
        "Ездра", "Неемия", "Есфирь", "Иов", "Псалтирь",
        "Притчи", "Екклесиаст", "Песнь Песней", "Исаия", "Иеремия",
        "Плач Иеремии", "Иезекииль", "Даниил", "Осия", "Иоиль",
        "Амос", "Авдий", "Иона", "Михей", "Наум",
        "Аввакум", "Софония", "Аггей", "Захария", "Малахия",
        "Матфея", "Марка", "Луки", "Иоанна", "Деяния",
        "Римлянам", "1 Коринфянам", "2 Коринфянам", "Галатам", "Ефесянам",
        "Филиппийцам", "Колоссянам", "1 Фессалоникийцам", "2 Фессалоникийцам",
        "1 Тимофею", "2 Тимофею", "Титу", "Филимону", "Евреям",
        "Иакова", "1 Петра", "2 Петра", "1 Иоанна", "2 Иоанна",
        "3 Иоанна", "Иуды", "Откровение"
    ]

    /// Other FULL names the same book appears under. These feed identification,
    /// so anything genuinely ambiguous is left out on purpose — Romanian
    /// „1 Regi" is 1 Samuel in Orthodox editions and 1 Kings in others, and a
    /// module using it is better off showing its own names than the wrong ones.
    private static let variants: [Int: [String]] = [
        1:  ["Facerea", "1 Mose", "Prima carte a lui Moise", "Bereshit"],
        2:  ["Ieșirea", "2 Mose", "Exodus", "Éxodo"],
        3:  ["Levitic", "3 Mose", "Levitikus", "Levíticos"],
        4:  ["Numerii", "4 Mose", "Numeri", "Nombres"],
        5:  ["Deuteronom", "A doua lege", "5 Mose", "Deuteronomium"],
        6:  ["Iosua Navi", "Josua Navi"],
        7:  ["Judecătorii", "Judecatori", "Jueces de Israel", "Richterbuch"],
        8:  ["Ruta"],
        9:  ["1 Samuil", "1. Samuelis", "I Samuel"],
        10: ["2 Samuil", "2. Samuelis", "II Samuel"],
        // „1 Regi" / „2 Regi" are deliberately absent: Orthodox Romanian
        // editions number them 1–4 Regi starting at 1 Samuel, others start at
        // 1 Kings. A module using them keeps its own names.
        11: ["I Reyes", "I Împărați"],
        12: ["II Reyes", "II Împărați"],
        13: ["1 Paralipomena", "I Crónicas", "1. Chronica"],
        14: ["2 Paralipomena", "II Crónicas", "2. Chronica"],
        15: ["Esdra"],
        16: ["Nehemia", "Neemias"],
        17: ["Ester"],
        18: ["Hiobul"],
        19: ["Psalmi", "Psalmul", "Salterio", "Psalter"],
        20: ["Proverbele", "Proverbele lui Solomon", "Sprichwörter", "Пословицы"],
        21: ["Ecclesiastul", "Kohelet", "Predicatorul", "Qohelet"],
        22: ["Cantarea Cantarilor", "Cântarea lui Solomon", "Cantar de los Cantares",
             "Cantar de Cantares", "Song of Songs", "Hohelied"],
        23: ["Isaiia", "Esaïe", "Isaïe"],
        24: ["Jeremia", "Ieremias"],
        25: ["Plângeri", "Plangeri", "Plângerile", "Lamentaciones de Jeremías",
             "Threni"],
        26: ["Ezekiel", "Ezechiel", "Ezequiel"],
        27: ["Danielul"],
        28: ["Hosea", "Osee"],
        29: ["Joel", "Ioil"],
        30: ["Amosa"],
        31: ["Abdia", "Abdías", "Obadiah", "Obadja"],
        32: ["Jonah", "Ionas"],
        33: ["Miheia", "Micah"],
        34: ["Nahum"],
        35: ["Habakuk", "Avacum", "Habacuq"],
        36: ["Sofonia", "Tefania", "Zephaniah"],
        37: ["Agheu", "Haggeu", "Aggeus"],
        38: ["Zacharia", "Zaharias"],
        39: ["Malachi", "Maleahia"],
        40: ["Matthäus", "Mateiu", "San Mateo", "Evanghelia după Matei"],
        41: ["San Marcos", "Evanghelia după Marcu"],
        42: ["San Lucas", "Evanghelia după Luca"],
        43: ["San Juan", "Evanghelia după Ioan"],
        44: ["Fapte", "Faptele", "Hechos de los Apóstoles", "Actes des Apôtres",
             "Acts of the Apostles"],
        45: ["Romanilor", "Epistola către Romani"],
        46: ["1 Corintieni", "I Corintios", "I Corinteni"],
        47: ["2 Corintieni", "II Corintios", "II Corinteni"],
        48: ["Galatieni", "Gálatas"],
        49: ["Efesieni", "Efesos"],
        50: ["Filipieni", "Filipenii"],
        51: ["Colosenii", "Colossenses"],
        52: ["1 Tesalonicieni", "I Tesalonicenses"],
        53: ["2 Tesalonicieni", "II Tesalonicenses"],
        54: ["1 Timoteiu", "I Timoteo"],
        55: ["2 Timoteiu", "II Timoteo"],
        56: ["Titus", "Tit"],
        57: ["Filemon", "Filimonului"],
        58: ["Evreii", "Ebrei", "Hebreus"],
        59: ["Jacob", "Iacob", "Sant Iago"],
        60: ["1 Pedru", "I Pedro"],
        61: ["2 Pedru", "II Pedro"],
        62: ["1 Ioanu", "I Juan", "I Ioan"],
        63: ["2 Ioanu", "II Juan", "II Ioan"],
        64: ["3 Ioanu", "III Juan", "III Ioan"],
        65: ["Judas Tadeo", "Epistola lui Iuda"],
        66: ["Revelation", "Apocalipsa lui Ioan", "Revelação", "Откровение Иоанна",
             "Descoperirea"]
    ]

    /// Typing shortcuts for the ⌘K reference parser. NOT used to identify a
    /// module's books — an abbreviation is far likelier to collide with a real
    /// name than a full name is.
    private static let abbreviations: [Int: [String]] = [
        1: ["gen", "gn", "fac"], 2: ["ex", "exo", "exod", "ies"],
        3: ["lev", "lv"], 4: ["num", "nm", "nu"], 5: ["deut", "dt", "deu"],
        6: ["ios", "jos", "josh"], 7: ["jud", "jdg", "judec", "jue"],
        8: ["rut", "rt"], 9: ["1sam", "1sa", "1s"], 10: ["2sam", "2sa", "2s"],
        11: ["1imp", "1reg", "1ki", "1re", "1rey"], 12: ["2imp", "2reg", "2ki", "2re", "2rey"],
        13: ["1cron", "1cro", "1ch"], 14: ["2cron", "2cro", "2ch"],
        15: ["ezr", "esd"], 16: ["neem", "neh", "ne"], 17: ["est"],
        18: ["iov", "job", "jb"], 19: ["ps", "psa", "psalm", "salm"],
        20: ["prov", "pr", "pro", "prv"], 21: ["ecl", "ecc", "eccl", "ecle"],
        22: ["cant", "cc", "sng", "song"], 23: ["is", "isa", "isai"],
        24: ["ier", "jer"], 25: ["plang", "lam", "la"], 26: ["ezec", "eze", "ezk", "ezeq"],
        27: ["dan", "dn"], 28: ["osea", "os", "hos"], 29: ["ioel", "joe", "jl"],
        30: ["amos", "am"], 31: ["obad", "oba", "ob", "abd"], 32: ["iona", "jon", "jns"],
        33: ["mica", "mic", "miq"], 34: ["naum", "nah", "nam"], 35: ["hab", "hba", "habac"],
        36: ["tef", "sof", "zep", "zef"], 37: ["hag", "agg", "hga"],
        38: ["zah", "zac", "zec", "sach"], 39: ["mal", "maleahi"],
        40: ["mat", "mt", "matei", "mate"], 41: ["mc", "mrk", "marcu", "marc"],
        42: ["lc", "luk", "luca", "luc"], 43: ["in", "jhn", "ioan", "juan"],
        44: ["fa", "fap", "act", "hch"], 45: ["rom", "rm"],
        46: ["1cor", "1co", "1c"], 47: ["2cor", "2co", "2c"],
        48: ["gal", "ga", "gl"], 49: ["ef", "efes", "eph"],
        50: ["fil", "flp", "php", "filip"], 51: ["col", "cl", "colos"],
        52: ["1tes", "1th", "1ts"], 53: ["2tes", "2th", "2ts"],
        54: ["1tim", "1ti", "1tm"], 55: ["2tim", "2ti", "2tm"],
        56: ["tit", "tt"], 57: ["filim", "phm", "flm", "filem"],
        58: ["evr", "heb", "hb", "hebr"], 59: ["iac", "jas", "jac", "sant"],
        60: ["1pet", "1pe", "1p", "1petr"], 61: ["2pet", "2pe", "2p", "2petr"],
        62: ["1in", "1jn", "1ioan", "1juan"], 63: ["2in", "2jn", "2ioan", "2juan"],
        64: ["3in", "3jn", "3ioan", "3juan"],
        // No "jud" here — that is Judges (7). Ambiguous shortcuts belong to the
        // book an operator is far likelier to mean.
        65: ["iuda", "jd", "jude"],
        66: ["apoc", "ap", "rev", "apo", "off"]
    ]

    /// Language code → the 66 names, so `name(number:language:)` is one lookup.
    private static let byLanguage: [String: [String]] = [
        "en": en, "ro": ro, "es": es, "fr": fr, "de": de, "ru": ru
    ]

    // MARK: - Match keys

    /// The form both sides of an identification are compared in: diacritics and
    /// case folded away, ordinal dots dropped ("1. Mose" → "1 mose"), runs of
    /// whitespace collapsed. `searchFold` alone is not enough — the reference
    /// parser already strips dots from what the operator types, so the table has
    /// to be stored the same way or German would never match.
    static func matchKey(_ name: String) -> String {
        let folded = searchFold(name)
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        return folded.split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// Every full name that identifies a book → its canonical number.
    ///
    /// Built once. A key already taken is NOT overwritten: two languages
    /// spelling different books the same way would otherwise resolve by table
    /// order, and silently. `duplicateNameKeys` exposes the collisions so the
    /// test suite fails instead.
    private static let nameKeyIndex: [String: Int] = {
        var index: [String: Int] = [:]
        for (_, names) in byLanguage {
            for (offset, name) in names.enumerated() {
                index[matchKey(name)] = offset + 1
            }
        }
        for (number, extra) in variants {
            for name in extra {
                let key = matchKey(name)
                if let taken = index[key], taken != number { continue }
                index[key] = number
            }
        }
        return index
    }()

    /// Names that two DIFFERENT books share across the table — must stay empty.
    static var duplicateNameKeys: [String: Set<Int>] {
        var seen: [String: Set<Int>] = [:]
        for (_, names) in byLanguage {
            for (offset, name) in names.enumerated() {
                seen[matchKey(name), default: []].insert(offset + 1)
            }
        }
        for (number, extra) in variants {
            for name in extra { seen[matchKey(name), default: []].insert(number) }
        }
        return seen.filter { $0.value.count > 1 }
    }

    /// Canonical number → every key the reference parser may match on: the six
    /// names, the variants, and the abbreviations.
    private static let searchKeysByNumber: [Int: [String]] = {
        var map: [Int: Set<String>] = [:]
        for (_, names) in byLanguage {
            for (offset, name) in names.enumerated() {
                map[offset + 1, default: []].insert(matchKey(name))
            }
        }
        for (number, extra) in variants {
            for name in extra { map[number, default: []].insert(matchKey(name)) }
        }
        for (number, abbrevs) in abbreviations {
            for abbrev in abbrevs { map[number, default: []].insert(matchKey(abbrev)) }
        }
        return map.mapValues { Array($0) }
    }()

    // MARK: - API

    /// The localization the bundle actually resolved at launch, reduced to a
    /// bare language code. Read once — `AppleLanguages` only takes effect on a
    /// restart, so this cannot change under a running app.
    static let uiLanguage: String = {
        let resolved = Bundle.main.preferredLocalizations.first ?? "en"
        let code = String(resolved.prefix(2)).lowercased()
        return byLanguage[code] == nil ? "en" : code
    }()

    /// Canonical name for a book number, or nil outside 1…66 / for a language
    /// with no table (deuterocanonical books have no canonical table either).
    ///
    /// Strict on purpose — no silent English fallback. Callers pass a
    /// TRANSLATION's language code as well as the UI's, and there are 17 of those
    /// in the Bible library; answering "Genesis" for a Dutch module would be a
    /// worse mistake than leaving its own name alone.
    static func name(number: Int, language: String = uiLanguage) -> String? {
        guard let names = byLanguage[language], (1...names.count).contains(number) else { return nil }
        return names[number - 1]
    }

    /// The canonical number of a book written in ANY language we know, or nil.
    static func canonicalNumber(forName name: String) -> Int? {
        let key = matchKey(name)
        guard !key.isEmpty else { return nil }
        return nameKeyIndex[key]
    }

    /// `name` restated in the app's language — unchanged when the book cannot be
    /// identified, which is the whole safety story: an unusual edition keeps its
    /// own wording rather than being renamed into a guess.
    static func localizedName(for name: String, language: String = uiLanguage) -> String {
        guard let number = canonicalNumber(forName: name),
              let localized = self.name(number: number, language: language) else { return name }
        return localized
    }

    /// Every key the reference parser may accept for this book.
    static func searchKeys(number: Int) -> [String] {
        searchKeysByNumber[number] ?? []
    }

    /// A stored reference („Geneza 1:1", „Faptele Apostolilor 2:1-4") restated in
    /// the app's language, keeping the chapter/verse part exactly as written.
    ///
    /// History rows and session items persist the reference as one string in the
    /// translation's language; this is how they are shown to the operator in the
    /// app's language without rewriting what was saved. Multi-word book names
    /// mean the split has to be found from the RIGHT — the last whitespace run
    /// before the chapter number.
    static func localizedReference(_ reference: String, language: String = uiLanguage) -> String {
        let trimmed = reference.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return reference }
        // Walk back over the chapter:verse tail — digits, ':', '-', ',', '–'.
        let tailSet = Set("0123456789:-,–—")
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            let previous = trimmed.index(before: index)
            guard tailSet.contains(trimmed[previous]) else { break }
            index = previous
        }
        guard index < trimmed.endIndex else { return reference }  // no numeric tail
        let bookPart = trimmed[trimmed.startIndex..<index].trimmingCharacters(in: .whitespaces)
        guard !bookPart.isEmpty, let number = canonicalNumber(forName: bookPart),
              let localized = name(number: number, language: language) else { return reference }
        return localized + " " + trimmed[index...]
    }
}
