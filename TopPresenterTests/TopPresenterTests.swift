//
//  TopPresenterTests.swift
//  TopPresenterTests
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Testing
import Foundation
import Compression
import SwiftUI
import SwiftData
@testable import TopPresenter

// MARK: - TopPresenter JSON Importer Tests

@MainActor struct TopPresenterImporterTests {
    let importer = TopPresenterBibleImporter()

    @Test func parsesValidJSON() async throws {
        let json: [String: Any] = [
            "format": "TopPresenter Bible",
            "translation": [
                "code": "KJV",
                "name": "King James Version",
                "language": "en"
            ],
            "books": [
                [
                    "number": 1,
                    "name": "Genesis",
                    "testament": "OT",
                    "chapters": [
                        [
                            "number": 1,
                            "verses": [
                                ["number": 1, "text": "In the beginning God created the heaven and the earth."],
                                ["number": 2, "text": "And the earth was without form, and void."],
                                ["number": 3, "text": "And God said, Let there be light: and there was light."]
                            ]
                        ],
                        [
                            "number": 2,
                            "verses": [
                                ["number": 1, "text": "Thus the heavens and the earth were finished."]
                            ]
                        ]
                    ]
                ],
                [
                    "number": 40,
                    "name": "Matthew",
                    "testament": "NT",
                    "chapters": [
                        [
                            "number": 1,
                            "verses": [
                                ["number": 1, "text": "The book of the generation of Jesus Christ."]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let url = try writeJSON(json, filename: "test_kjv.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await importer.parse(fileURL: url)

        #expect(result.moduleName == "King James Version")
        #expect(result.abbreviation == "KJV")
        #expect(result.language == "en")
        #expect(result.books.count == 2)

        let genesis = result.books[0]
        #expect(genesis.name == "Genesis")
        #expect(genesis.bookNumber == 1)
        #expect(genesis.testament == "OT")
        #expect(genesis.chapters.count == 2)
        #expect(genesis.chapters[0].verses.count == 3)
        #expect(genesis.chapters[0].verses[0].text == "In the beginning God created the heaven and the earth.")
        #expect(genesis.chapters[1].chapterNumber == 2)
        #expect(genesis.chapters[1].verses.count == 1)

        let matthew = result.books[1]
        #expect(matthew.testament == "NT")
        #expect(matthew.bookNumber == 40)
    }

    @Test func rejectsEmptyBooksArray() async throws {
        let json: [String: Any] = [
            "format": "TopPresenter Bible",
            "translation": ["code": "TEST"],
            "books": [] as [[String: Any]]
        ]

        let url = try writeJSON(json, filename: "test_empty.json")
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: BibleImportError.self) {
            try await importer.parse(fileURL: url)
        }
    }

    @Test func handlesMissingTranslationMetadata() async throws {
        let json: [String: Any] = [
            "books": [
                [
                    "number": 1,
                    "name": "Genesis",
                    "chapters": [
                        [
                            "number": 1,
                            "verses": [
                                ["number": 1, "text": "In the beginning."]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let url = try writeJSON(json, filename: "test_no_meta.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await importer.parse(fileURL: url)

        // Should fall back to filename
        #expect(result.moduleName == "test_no_meta")
        #expect(result.abbreviation == "")
        #expect(result.books.count == 1)
    }

    @Test func skipsVersesWithEmptyText() async throws {
        let json: [String: Any] = [
            "format": "TopPresenter Bible",
            "translation": ["code": "TEST"],
            "books": [
                [
                    "number": 1,
                    "name": "Genesis",
                    "chapters": [
                        [
                            "number": 1,
                            "verses": [
                                ["number": 1, "text": "Valid verse."],
                                ["number": 2, "text": "   "],
                                ["number": 3, "text": "Another valid verse."]
                            ]
                        ]
                    ]
                ]
            ]
        ]

        let url = try writeJSON(json, filename: "test_empty_verses.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await importer.parse(fileURL: url)
        #expect(result.books[0].chapters[0].verses.count == 2)
    }

    @Test func parsesGoatV2RichFields() async throws {
        let json: [String: Any] = [
            "schemaVersion": "2.0.0",
            "format": "TopPresenter Bible",
            "translation": ["code": "TEST", "name": "Test", "versification": "kjv", "canon": "protestant"],
            "books": [[
                "number": 40, "name": "Matthew", "testament": "NT",
                "chapters": [[
                    "number": 5,
                    "headings": [["beforeVerse": 3, "level": 1, "text": "The Beatitudes"]],
                    "verses": [[
                        "number": 3, "text": "Blessed are the poor in spirit.",
                        "runs": [["text": "Blessed are the poor in spirit.", "kind": "woc", "strong": "G3107"]],
                        "footnotes": [["marker": "a", "text": "Or happy"]],
                        "crossReferences": [["targets": ["Luke 6:20"]]]
                    ]]
                ]]
            ]]
        ]
        let url = try writeJSON(json, filename: "test_goat_v2.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await importer.parse(fileURL: url)
        #expect(result.versification == "kjv")
        #expect(result.canon == "protestant")
        let ch = result.books[0].chapters[0]
        #expect(ch.headings?.first?.text == "The Beatitudes")
        let v = ch.verses[0]
        #expect(v.hasWordsOfChrist)                       // inferred from run kind
        #expect(v.runs?.first?.kind == "woc")
        #expect(v.runs?.first?.strong == "G3107")
        #expect(v.footnotes?.first?.text == "Or happy")
        #expect(v.crossReferences?.first?.targets == ["Luke 6:20"])
    }

    @Test func usfmExtractsRedLetterRuns() {
        // \wj …\wj* → words-of-Christ run; surrounding text stays plain.
        let raw = "And \\wj I am the light of the world\\wj*, he said."
        let r = USFMRich.parse(raw, plain: "And I am the light of the world, he said.")
        #expect(r.woc)
        let runs = try! #require(r.runs)
        #expect(runs.contains { $0.kind == "woc" && $0.text.contains("light of the world") })
        #expect(runs.contains { $0.kind == "plain" && $0.text.contains("And") })
        // Plain verse → no runs.
        #expect(USFMRich.parse("Just plain text.", plain: "Just plain text.").runs == nil)
    }

    @Test func parsesInterlinearRunsWithOriginalGlossStrongMorph() async throws {
        // A true interlinear verse (ENINT shape): each run = original word + gloss + Strong's + morph.
        let json: [String: Any] = [
            "format": "TopPresenter Bible",
            "translation": ["code": "ENINT", "hasStrongs": true],
            "books": [["number": 64, "name": "3 John", "chapters": [[
                "number": 1,
                "verses": [["number": 1, "text": "Ὁ πρεσβύτερος",
                            "runs": [
                                ["text": "Ὁ", "strong": "3588", "morph": "T-NSM", "gloss": "The"],
                                ["text": "πρεσβύτερος", "strong": "4245", "morph": "A-NSM", "gloss": "elder"],
                            ]]]
            ]]]],
        ]
        let url = try writeJSON(json, filename: "test_interlinear.json")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await importer.parse(fileURL: url)
        #expect(result.hasStrongs)
        let runs = try #require(result.books[0].chapters[0].verses[0].runs)
        #expect(runs.count == 2)
        #expect(runs[0].text == "Ὁ" && runs[0].strong == "3588" && runs[0].morph == "T-NSM" && runs[0].gloss == "The")
        #expect(runs[1].text == "πρεσβύτερος" && runs[1].gloss == "elder")
    }

    @Test func acceptsLegacyCrossRefShape() async throws {
        // eBiblia v1 used {references:[…]} — must still decode into targets.
        let json: [String: Any] = [
            "format": "TopPresenter Bible",
            "translation": ["code": "T"],
            "books": [["number": 1, "name": "Genesis", "chapters": [[
                "number": 1,
                "verses": [["number": 1, "text": "In the beginning.",
                            "crossReferences": [["references": ["John 1:1"]]]]]
            ]]]]
        ]
        let url = try writeJSON(json, filename: "test_legacy_xref.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await importer.parse(fileURL: url)
        #expect(result.books[0].chapters[0].verses[0].crossReferences?.first?.targets == ["John 1:1"])
    }

    // MARK: - Helpers

    private func writeJSON(_ json: [String: Any], filename: String) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}

// MARK: - Recursive folder import

@MainActor struct BibleFolderImportTests {
    private func writeBible(_ url: URL) throws {
        let json: [String: Any] = ["format": "TopPresenter Bible", "translation": ["code": "T"], "books": []]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }

    @Test func recursivelyFindsBiblesInFolderAndSubfolders() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tp_bibfolder_\(UUID().uuidString)")
        let lang1 = root.appendingPathComponent("Romana")
        let lang2deep = root.appendingPathComponent("English/extra")   // two levels deep
        try fm.createDirectory(at: lang1, withIntermediateDirectories: true)
        try fm.createDirectory(at: lang2deep, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try writeBible(lang1.appendingPathComponent("A.json"))
        try writeBible(lang1.appendingPathComponent("B.json"))
        try writeBible(lang2deep.appendingPathComponent("C.json"))     // nested subfolder
        try "not a bible".data(using: .utf8)!.write(to: root.appendingPathComponent("readme.txt"))
        // Beyond the 2-subfolder limit -> must be IGNORED.
        let tooDeep = root.appendingPathComponent("English/extra/way")
        try fm.createDirectory(at: tooDeep, withIntermediateDirectories: true)
        try writeBible(tooDeep.appendingPathComponent("D.json"))

        // Picking the ROOT folder finds Bibles up to 2 subfolder levels deep,
        // ignoring junk and anything deeper.
        let expanded = DragDropImportHandler.expandToImportableFiles([root])
        #expect(expanded.filter { $0.pathExtension == "json" }.count == 3)
        #expect(!expanded.contains { $0.lastPathComponent == "D.json" })

        let pending = DragDropImportHandler.classifyExpanded([root])
        let bibles = pending.filter { if case .bible = $0.category { return true }; return false }
        #expect(bibles.count == 3)
    }
}

// MARK: - Zefania XML Importer Tests

@MainActor struct ZefaniaImporterTests {
    let importer = ZefaniaBibleImporter()

    @Test func parsesValidZefaniaXML() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <XMLBIBLE biblename="Test Bible">
          <INFORMATION>
            <title>Test Bible Module</title>
            <language>en</language>
            <identifier>TB</identifier>
            <description>A test Bible module</description>
          </INFORMATION>
          <BIBLEBOOK bnumber="1">
            <CHAPTER cnumber="1">
              <VERS vnumber="1">In the beginning God created the heaven and the earth.</VERS>
              <VERS vnumber="2">And the earth was without form, and void.</VERS>
            </CHAPTER>
            <CHAPTER cnumber="2">
              <VERS vnumber="1">Thus the heavens and the earth were finished.</VERS>
            </CHAPTER>
          </BIBLEBOOK>
          <BIBLEBOOK bnumber="40">
            <CHAPTER cnumber="1">
              <VERS vnumber="1">The book of the generation of Jesus Christ.</VERS>
            </CHAPTER>
          </BIBLEBOOK>
        </XMLBIBLE>
        """

        let url = try writeXML(xml, filename: "test_zefania.xml")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await importer.parse(fileURL: url)

        #expect(result.moduleName == "Test Bible Module")
        #expect(result.abbreviation == "TB")
        #expect(result.language == "en")
        #expect(result.books.count == 2)

        let genesis = result.books[0]
        #expect(genesis.bookNumber == 1)
        #expect(genesis.testament == "OT")
        #expect(genesis.chapters.count == 2)
        #expect(genesis.chapters[0].verses.count == 2)
        #expect(genesis.chapters[0].verses[0].text == "In the beginning God created the heaven and the earth.")

        let matthew = result.books[1]
        #expect(matthew.bookNumber == 40)
        #expect(matthew.testament == "NT")
    }

    @Test func rejectsEmptyZefaniaXML() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <XMLBIBLE biblename="Empty Bible">
          <INFORMATION>
            <title>Empty</title>
          </INFORMATION>
        </XMLBIBLE>
        """

        let url = try writeXML(xml, filename: "test_empty_zefania.xml")
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: BibleImportError.self) {
            try await importer.parse(fileURL: url)
        }
    }

    // MARK: - Helpers

    private func writeXML(_ xml: String, filename: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try xml.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Rich-field extraction (lean Bible formats → GOAT superset)

/// Every lean Bible importer must map its format's full markup (headings, footnotes,
/// cross-refs, red-letter, Strong's, morphology) into the GOAT model so exports are rich.
@MainActor struct RichBibleExtractionTests {

    // MARK: OSIS

    @Test func osisExtractsHeadingsFootnotesCrossRefsStrongsAndWoc() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <osis xmlns="http://www.bibletechnologies.net/2003/OSIS/namespace">
          <osisText osisIDWork="KJV" xml:lang="en">
            <header><work osisWork="KJV">
              <title>King James Version</title>
              <identifier type="OSIS">Bible.en.KJV</identifier>
              <rights>Public Domain</rights>
              <language>en</language>
            </work></header>
            <div type="book" osisID="John">
              <chapter osisID="John.3">
                <title>God's Love</title>
                <verse osisID="John.3.16">For God so loved <q who="Jesus">the <w lemma="strong:G2889" morph="robinson:N-ASM">world</w></q><note type="crossReference"><reference osisRef="Rom.5.8">Rom 5:8</reference></note><note>A clarifying footnote.</note></verse>
              </chapter>
            </div>
          </osisText>
        </osis>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt_osis.xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await OSISBibleImporter().parse(fileURL: url)
        #expect(result.copyright == "Public Domain")
        #expect(result.hasWordsOfChrist)
        #expect(result.hasStrongs)

        let chapter = result.books[0].chapters[0]
        #expect(chapter.headings?.first?.text == "God's Love")

        let verse = chapter.verses[0]
        #expect(verse.hasWordsOfChrist)
        let runs = try #require(verse.runs)
        #expect(runs.contains { $0.kind == "woc" })
        #expect(runs.contains { $0.strong == "G2889" && $0.morph == "N-ASM" })
        #expect(verse.footnotes?.first?.text == "A clarifying footnote.")
        #expect(verse.crossReferences?.first?.targets == ["Rom.5.8"])
    }

    // MARK: USFM

    @Test func usfmExtractsFootnotesAndCrossRefs() {
        let raw = "For God so loved the world,\\f + \\fr 3.16 \\ft Greek: kosmos.\\f*\\x + \\xt Rom 5:8; John 1:29\\x* that he gave."
        let footnotes = USFMNotes.footnotes(raw)
        #expect(footnotes.first?.text.contains("Greek: kosmos.") == true)
        let xrefs = USFMNotes.crossRefs(raw)
        #expect(xrefs.first?.targets == ["Rom 5:8", "John 1:29"])
    }

    @Test func usfmExtractsStrongsFromWordMarkers() {
        let raw = "\\v 1 In the \\w beginning|strong=\"H7225\"\\w* God \\w created|strong=\"H1254\" x-morph=\"Vqp3ms\"\\w* the heavens."
        let r = USFMRich.parse(raw, plain: "In the beginning God created the heavens.")
        let runs = try! #require(r.runs)
        #expect(runs.contains { $0.strong == "H7225" })
        let created = runs.first { $0.strong == "H1254" }
        #expect(created?.morph == "Vqp3ms")
    }

    @Test func usfmFullVerseRoundTripsThroughImporter() async throws {
        let usfm = """
        \\id JHN John
        \\h John
        \\c 3
        \\s The Love of God
        \\v 16 For God so loved \\wj the world\\wj*,\\f + \\fr 3.16 \\ft kosmos\\f*\\x + \\xt Rom 5:8\\x* \\w that|strong="G3754"\\w* he gave.
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt_john.usfm")
        try usfm.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await USFMBibleImporter().parse(fileURL: url)
        #expect(result.hasWordsOfChrist)
        #expect(result.hasStrongs)
        let chapter = result.books[0].chapters[0]
        #expect(chapter.headings?.contains { $0.text == "The Love of God" } == true)
        let verse = chapter.verses[0]
        #expect(verse.hasWordsOfChrist)
        #expect(verse.runs?.contains { $0.kind == "woc" } == true)
        #expect(verse.runs?.contains { $0.strong == "G3754" } == true)
        #expect(verse.footnotes?.first?.text.contains("kosmos") == true)
        #expect(verse.crossReferences?.first?.targets == ["Rom 5:8"])
    }

    // MARK: MySword (GBF)

    @Test func mySwordGBFExtractsEverything() {
        let raw = "<TS>The Creation<Ts>In the beginning <FR>God<Fr> created<WG1254><WTHeb> the heaven.<RF>A footnote.<Rf><RX>Gen 1:1<Rx>"
        let p = MySwordGBF.parse(raw)
        #expect(p.text == "In the beginning God created the heaven.")
        #expect(p.headings.first == "The Creation")
        #expect(p.woc)
        let runs = try! #require(p.runs)
        #expect(runs.contains { $0.kind == "woc" && $0.text.contains("God") })
        let created = runs.first { $0.strong == "G1254" }
        #expect(created != nil)
        #expect(created?.morph == "Heb")
        #expect(p.footnotes.first?.text == "A footnote.")
        #expect(p.crossRefs.first?.targets == ["Gen 1:1"])
    }

    @Test func mySwordPlainTextHasNoRuns() {
        let p = MySwordGBF.parse("In the beginning God created the heaven and the earth.")
        #expect(p.text == "In the beginning God created the heaven and the earth.")
        #expect(p.runs == nil)
        #expect(!p.woc)
    }
}

// MARK: - Rich-field extraction (song formats → GOAT superset)

@MainActor struct RichSongExtractionTests {

    @Test func openLyricsExtractsSongbookVerseOrderCommentsAndTypedAuthors() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <song xmlns="http://openlyrics.info/namespace/2009/song" version="0.9">
          <properties>
            <titles><title>Amazing Grace</title><title>Grace</title></titles>
            <authors>
              <author type="words">John Newton</author>
              <author type="music">Traditional</author>
            </authors>
            <songbooks><songbook name="Hymns Ancient" entry="42"/></songbooks>
            <verseOrder>v1 c v1</verseOrder>
            <comments><comment>A beloved hymn.</comment></comments>
            <themes><theme>Grace</theme></themes>
          </properties>
          <lyrics>
            <verse name="v1"><lines>Amazing grace how sweet the sound</lines></verse>
            <verse name="c"><lines>How precious did that grace appear</lines></verse>
          </lyrics>
        </song>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt_amazing.xml")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await OpenLyricsImporter().parse(fileURL: url)
        #expect(result.title == "Amazing Grace")
        #expect(result.titles == ["Grace"])
        #expect(result.authorWords == "John Newton")
        #expect(result.authorMusic == "Traditional")
        #expect(result.notes == "A beloved hymn.")
        #expect(result.themes == ["Grace"])
        let version = try #require(result.versions.first)
        #expect(version.songbookName == "Hymns Ancient")
        #expect(version.songbookNumber == "42")
        #expect(version.arrangement == ["v1", "c", "v1"])
    }

    @Test func chordProExtractsTimeAlbumYearAndCapo() {
        let content = """
        {title: Test Song}
        {composer: J. Composer}
        {lyricist: L. Lyric}
        {time: 6/8}
        {capo: 2}
        {album: Hymns Vol 1}
        {year: 1779}

        [C]Amazing [G]grace how [Am]sweet
        """
        let result = ChordProImporter.parse(content: content, fallbackTitle: "x")
        #expect(result.authorMusic == "J. Composer")
        #expect(result.authorWords == "L. Lyric")
        let version = try! #require(result.versions.first)
        #expect(version.timeSignature == "6/8")
        #expect(version.capo == 2)
        #expect(version.notes.contains("Album: Hymns Vol 1"))
        #expect(version.notes.contains("Year: 1779"))
    }

    @Test func openSongExtractsCapoAkaAndTimeSignature() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <song>
          <title>Test Song</title>
          <author>Someone</author>
          <aka>Alternate Name</aka>
          <capo print="false">3</capo>
          <time_sig>3/4</time_sig>
          <user1>A production note</user1>
          <lyrics>
        [V1]
         Line one of the verse
        </lyrics>
        </song>
        """
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("rt_opensong")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await OpenSongImporter().parse(fileURL: url)
        #expect(result.titles == ["Alternate Name"])
        let version = try #require(result.versions.first)
        #expect(version.capo == 3)
        #expect(version.timeSignature == "3/4")
        #expect(version.notes.contains("A production note"))
    }
}

// MARK: - Bible Import Result Validation Tests

@MainActor struct BibleImportResultTests {
    @Test func verseRangeFormatting() {
        let result = BibleImportResult(
            moduleName: "Test",
            abbreviation: "TST",
            language: "en",
            description: "",
            books: [
                BibleImportBook(
                    name: "John",
                    bookNumber: 43,
                    testament: "NT",
                    chapters: [
                        BibleImportChapter(
                            chapterNumber: 3,
                            verses: [
                                BibleImportVerse(verseNumber: 16, text: "For God so loved the world.")
                            ]
                        )
                    ]
                )
            ]
        )

        #expect(result.books[0].chapters[0].verses[0].verseNumber == 16)
        #expect(result.books[0].chapters[0].verses[0].text.contains("loved"))
    }
}

// MARK: - Color Extension Tests

@MainActor struct ColorExtensionTests {
    @Test func hexToColor6Digit() {
        let color = Color(hex: "FF0000")
        #expect(color != nil)
    }

    @Test func hexToColor8Digit() {
        let color = Color(hex: "FF000080")
        #expect(color != nil)
    }

    @Test func hexToColorWithHash() {
        let color = Color(hex: "#00FF00")
        #expect(color != nil)
    }

    @Test func invalidHex() {
        let color = Color(hex: "XYZ")
        #expect(color == nil)
    }

    @Test func colorRoundTrip() {
        let original = Color(hex: "FF8040")!
        let hex = original.toHex()
        #expect(hex.count == 6)
    }
}

// MARK: - LiveContent Tests

@MainActor struct LiveContentTests {
    @Test func setBibleVerseUpdatesFields() {
        let content = LiveContent()
        content.setBibleVerse(text: "In the beginning", reference: "Genesis 1:1")

        #expect(content.mainText == "In the beginning")
        #expect(content.reference == "Genesis 1:1")
        #expect(content.subtitle == "")
        #expect(content.contentType == .bible)
    }

    @Test func setSongVerseUpdatesFields() {
        let content = LiveContent()
        content.setSongVerse(text: "Amazing grace", title: "Amazing Grace", verseLabel: "Verse 1")

        #expect(content.mainText == "Amazing grace")
        #expect(content.reference == "Amazing Grace")
        #expect(content.subtitle == "Verse 1")
        #expect(content.contentType == .song)
    }

    @Test func clearResetsEverything() {
        let content = LiveContent()
        content.setBibleVerse(text: "Test", reference: "Gen 1:1")
        content.isLive = true

        content.clear()

        #expect(content.mainText == "")
        #expect(content.reference == "")
        #expect(content.subtitle == "")
        #expect(content.isLive == false)
        #expect(content.contentType == .blank)
    }
}

// MARK: - ZIP / PPTX Importer Tests

@MainActor struct PPTXImporterTests {
    /// Builds a minimal valid ZIP in memory (stored or deflated entries).
    private func makeZip(entries: [(name: String, data: Data, deflate: Bool)]) -> Data {
        var out = Data()
        var central = Data()
        var offsets: [Int] = []

        func u16(_ v: Int) -> Data { Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]) }
        func u32(_ v: Int) -> Data {
            Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
        }

        for entry in entries {
            offsets.append(out.count)
            let nameData = entry.name.data(using: .utf8)!
            let payload: Data
            let method: Int
            if entry.deflate {
                payload = rawDeflate(entry.data)
                method = 8
            } else {
                payload = entry.data
                method = 0
            }
            // Local header
            out.append(u32(0x04034b50))
            out.append(u16(20)); out.append(u16(0)); out.append(u16(method))
            out.append(u16(0)); out.append(u16(0))      // time, date
            out.append(u32(0))                           // crc (unchecked by reader)
            out.append(u32(payload.count))
            out.append(u32(entry.data.count))
            out.append(u16(nameData.count)); out.append(u16(0))
            out.append(nameData)
            out.append(payload)
        }
        let cdStart = out.count
        for (i, entry) in entries.enumerated() {
            let nameData = entry.name.data(using: .utf8)!
            let payload = entry.deflate ? rawDeflate(entry.data) : entry.data
            central.append(u32(0x02014b50))
            central.append(u16(20)); central.append(u16(20)); central.append(u16(0))
            central.append(u16(entry.deflate ? 8 : 0))
            central.append(u16(0)); central.append(u16(0))   // time, date
            central.append(u32(0))                            // crc
            central.append(u32(payload.count))
            central.append(u32(entry.data.count))
            central.append(u16(nameData.count)); central.append(u16(0)); central.append(u16(0))
            central.append(u16(0)); central.append(u16(0))   // disk, internal attrs
            central.append(u32(0))                            // external attrs
            central.append(u32(offsets[i]))
            central.append(nameData)
        }
        out.append(central)
        // EOCD
        out.append(u32(0x06054b50))
        out.append(u16(0)); out.append(u16(0))
        out.append(u16(entries.count)); out.append(u16(entries.count))
        out.append(u32(out.count - cdStart - 4 - 12)) // cd size (not validated by reader)
        out.append(u32(cdStart))
        out.append(u16(0))
        return out
    }

    private func rawDeflate(_ data: Data) -> Data {
        var output = Data(count: data.count + 256)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            data.withUnsafeBytes { src -> Int in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, data.count + 256,
                    src.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        return output.prefix(written)
    }

    private func slideXML(title: String?, body: String) -> String {
        let titleShape = title.map {
            """
            <p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
            <p:txBody><a:p><a:r><a:t>\($0)</a:t></a:r></a:p></p:txBody></p:sp>
            """
        } ?? ""
        return """
        <?xml version="1.0"?>
        <p:sld xmlns:p="urn:p" xmlns:a="urn:a"><p:cSld><p:spTree>
        \(titleShape)
        <p:sp><p:nvSpPr><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>
        <p:txBody><a:p><a:r><a:t>\(body)</a:t></a:r></a:p></p:txBody></p:sp>
        </p:spTree></p:cSld></p:sld>
        """
    }

    @Test func zipReaderExtractsStoredAndDeflated() throws {
        let storedContent = Data("hello stored".utf8)
        let deflatedContent = Data(String(repeating: "verse text ", count: 50).utf8)
        let zip = makeZip(entries: [
            ("a.txt", storedContent, false),
            ("b.txt", deflatedContent, true),
        ])

        let reader = try ZipArchiveReader(data: zip)
        #expect(reader.entries.count == 2)
        #expect(try reader.extract(reader.entry(named: "a.txt")!) == storedContent)
        #expect(try reader.extract(reader.entry(named: "b.txt")!) == deflatedContent)
    }

    @Test func importsPPTXWithoutSpawningProcesses() async throws {
        // A real (minimal) pptx: deflated slide XMLs + core metadata
        let zip = makeZip(entries: [
            ("docProps/core.xml", Data("<cp><dc:title>Cântec Test</dc:title></cp>".utf8), true),
            ("ppt/slides/slide1.xml", Data(slideXML(title: "Chorus", body: "La la la").utf8), true),
            ("ppt/slides/slide2.xml", Data(slideXML(title: nil, body: "Strofa a doua").utf8), false),
            ("ppt/slides/_rels/slide1.xml.rels", Data("<rels/>".utf8), false),
        ])

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).pptx")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PowerPointSongImporter().parse(fileURL: url)
        #expect(result.title == "Cântec Test")
        #expect(result.verses.count == 2)
        #expect(result.verses[0].verseType == "chorus")
        #expect(result.verses[0].text.contains("La la la"))
        #expect(result.verses[1].text.contains("Strofa a doua"))
    }

    @Test func powerPointDedupsRepeatedChorusIntoArrangement() async throws {
        // V1, Chorus, V2, Chorus(identical) → 3 unique sections, 4-step arrangement.
        let chorus = "Slăvit să fie Domnul"
        let zip = makeZip(entries: [
            ("docProps/core.xml", Data("<cp><dc:title>Test Dedup</dc:title></cp>".utf8), true),
            ("ppt/slides/slide1.xml", Data(slideXML(title: nil, body: "Strofa unu aici").utf8), true),
            ("ppt/slides/slide2.xml", Data(slideXML(title: nil, body: chorus).utf8), true),
            ("ppt/slides/slide3.xml", Data(slideXML(title: nil, body: "Strofa doi aici").utf8), true),
            ("ppt/slides/slide4.xml", Data(slideXML(title: nil, body: chorus).utf8), true),
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dedup-\(UUID().uuidString).pptx")
        try zip.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = try await PowerPointSongImporter().parse(fileURL: url)
        let version = try #require(result.versions.first)
        #expect(version.sections.count == 3)                 // chorus stored once
        #expect(version.arrangement.count == 4)              // but played 4 times
        #expect(version.sections.contains { $0.type == "chorus" })  // repeated slide → chorus
    }
}

// MARK: - Batch Song Import Tests

@MainActor struct SongBatchImportTests {
    private func makeInMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test func importsMixOfFilesAndReportsFailures() async throws {
        let context = try makeInMemoryContext()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("songs-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        // A valid OpenSong file
        let openSong = dir.appendingPathComponent("Cantec.xml")
        try """
        <song><title>Cântec Bun</title><lyrics>[V1]
        Prima strofă</lyrics></song>
        """.data(using: .utf8)!.write(to: openSong)

        // An unknown file type
        let junk = dir.appendingPathComponent("nota.rtf")
        try Data("junk".utf8).write(to: junk)

        let result = await ImportService.importSongItems(
            urls: [openSong, junk],
            collectionName: "Test Batch",
            modelContext: context
        )

        #expect(result.importedTitles.count == 1)
        #expect(result.importedTitles.first == "Cântec Bun")
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.file == "nota.rtf")
        #expect(result.collection?.songs.count == 1)
    }

    @Test func importsDirectoryWithAutoDetection() async throws {
        let context = try makeInMemoryContext()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("songdir-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try """
        <song><title>Unu</title><lyrics>[V1]
        La la</lyrics></song>
        """.data(using: .utf8)!.write(to: dir.appendingPathComponent("a.xml"))
        try """
        <song><title>Doi</title><lyrics>[V1]
        Lo lo</lyrics></song>
        """.data(using: .utf8)!.write(to: dir.appendingPathComponent("b.xml"))

        // Pass the DIRECTORY itself — files are discovered + auto-detected
        let result = await ImportService.importSongItems(
            urls: [dir],
            collectionName: "Director",
            modelContext: context
        )

        #expect(result.importedTitles.sorted() == ["Doi", "Unu"])
        #expect(result.failures.isEmpty)
    }

    @Test func importsMultiSongBundleAsSeparateSongs() async throws {
        let context = try makeInMemoryContext()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("bundle-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        func song(_ title: String, _ line: String) -> [String: Any] {
            ["title": title, "language": "ro", "versions": [[
                "name": "Original",
                "sections": [["id": "v1", "type": "verse", "label": "Strofă 1", "order": 0,
                              "lines": [["text": line]]]]
            ]]]
        }

        // A per-letter bundle: one file, many songs (ResurseCrestine userscript shape).
        let bundle: [String: Any] = [
            "schemaVersion": "1.0.0", "format": "TopPresenter Song",
            "songs": [song("Cântec Unu", "Linia unu"),
                      song("Cântec Doi", "Linia doi"),
                      song("Cântec Trei", "Linia trei")]
        ]
        let bundleURL = dir.appendingPathComponent("litera-c.json")
        try JSONSerialization.data(withJSONObject: bundle, options: .prettyPrinted).write(to: bundleURL)

        // A single-song doc still yields exactly one song.
        let single: [String: Any] = [
            "schemaVersion": "1.0.0", "format": "TopPresenter Song",
            "song": song("Singur", "O linie")
        ]
        let singleURL = dir.appendingPathComponent("singur.json")
        try JSONSerialization.data(withJSONObject: single, options: .prettyPrinted).write(to: singleURL)

        let result = await ImportService.importSongItems(
            urls: [bundleURL, singleURL],
            collectionName: "Bundle Test",
            modelContext: context,
            duplicateResolution: .keepBoth
        )

        #expect(result.failures.isEmpty)
        #expect(result.importedTitles.sorted() == ["Cântec Doi", "Cântec Trei", "Cântec Unu", "Singur"])
        #expect(result.collection?.songs.count == 4)
    }

    @Test func pptRecordWalkerDescendsIntoContainers() {
        // Slide container (recVer 0xF) WRAPPING a TextCharsAtom child —
        // the old walker skipped container children and found no text.
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] {
            [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
        }

        let text = "Salut lume"
        let textBytes = [UInt8](text.data(using: .utf16LittleEndian)!)
        var child: [UInt8] = []
        child += u16(0x0000)            // ver/instance (atom)
        child += u16(0x0FA0)            // RT_TextCharsAtom
        child += u32(textBytes.count)
        child += textBytes

        var container: [UInt8] = []
        container += u16(0x000F)        // ver 0xF = container
        container += u16(0x03EE)        // RT_Slide
        container += u32(child.count)
        container += child

        let slides = PowerPointSongImporter().parsePPTRecords(data: Data(container))
        #expect(slides.count == 1)
        #expect(slides.first?.first == "Salut lume")
    }
}

// MARK: - PresentationManager Tests

// MainActor: PresentationManager drives NSWindow/NSScreen (AppKit is main-thread-only),
// and Swift Testing otherwise runs test functions on background threads.
@MainActor
struct PresentationManagerTests {
    @Test func freezeSnapshotsCurrentValues() {
        let pm = PresentationManager()
        pm.fontSize = 72.0
        pm.fontName = "Helvetica"

        pm.toggleFreeze()

        #expect(pm.isFrozen == true)
        #expect(pm.outputFontSize == 72.0)
        #expect(pm.outputFontName == "Helvetica")

        // Changing live values shouldn't affect output while frozen
        pm.fontSize = 48.0
        #expect(pm.outputFontSize == 72.0)
    }

    @Test func unfreezeRestoresLiveValues() {
        let pm = PresentationManager()
        pm.fontSize = 72.0
        pm.toggleFreeze()
        pm.fontSize = 48.0

        pm.toggleFreeze() // unfreeze

        #expect(pm.isFrozen == false)
        #expect(pm.outputFontSize == 48.0)
    }

    @Test func clearOutputResetsFreezeAndBlack() {
        let pm = PresentationManager()
        pm.toggleFreeze()
        pm.isBlackScreen = true
        pm.liveContent.setBibleVerse(text: "Test", reference: "Gen 1:1")
        pm.liveContent.isLive = true

        pm.clearOutput()

        #expect(pm.isFrozen == false)
        #expect(pm.isBlackScreen == false)
        #expect(pm.liveContent.isLive == false)
        #expect(pm.liveContent.mainText == "")
    }

    @Test func showBibleVerseBlockedWhenFrozen() {
        let pm = PresentationManager()
        pm.liveContent.setBibleVerse(text: "First verse", reference: "Gen 1:1")
        pm.toggleFreeze()

        pm.showBibleVerse(text: "Second verse", reference: "Gen 1:2")

        // Should still show the first verse since it's frozen
        #expect(pm.liveContent.mainText == "First verse")
    }

    @Test func toggleBlack() {
        let pm = PresentationManager()
        #expect(pm.isBlackScreen == false)

        pm.toggleBlack()
        #expect(pm.isBlackScreen == true)

        pm.toggleBlack()
        #expect(pm.isBlackScreen == false)
    }

    // MARK: Fixed Text Boxes

    @Test func boxFrameClampsToScreen() {
        let frame = PresentationManager.TextBoxFrame(x: 0.9, y: -0.2, width: 0.5, height: 0.01)
        let clamped = frame.clamped()

        #expect(clamped.height == PresentationManager.TextBoxFrame.minSize)
        #expect(clamped.y == 0)
        #expect(clamped.x + clamped.width <= 1.0)
        #expect(clamped.width == 0.5)
    }

    @Test func boxFrameRectScalesToCanvas() {
        let frame = PresentationManager.TextBoxFrame(x: 0.1, y: 0.2, width: 0.5, height: 0.25)
        let rect = frame.rect(in: CGSize(width: 1000, height: 800))

        #expect(rect.origin.x == 100)
        #expect(rect.origin.y == 160)
        #expect(rect.width == 500)
        #expect(rect.height == 200)
    }

    @Test func setBoxFrameClampsAndPersistsRoundTrip() throws {
        let pm = PresentationManager()
        let original = pm.boxFrame(for: .verseContent, in: "bible")
        pm.setBoxFrame(.init(x: 0.95, y: 0.1, width: 0.3, height: 0.2), for: .verseContent, in: "bible")
        defer { pm.setBoxFrame(original, for: .verseContent, in: "bible") }

        // x clamped so the box stays fully on screen
        let frame = pm.boxFrame(for: .verseContent, in: "bible")
        #expect(frame.x + frame.width <= 1.0)

        // Profiles persist as ONE blob — decode it back and compare
        let data = try #require(UserDefaults.standard.data(forKey: "pm_layoutProfiles"))
        let profiles = try JSONDecoder().decode(
            [String: PresentationManager.LayoutProfile].self, from: data
        )
        #expect(profiles["bible"]?.frames[TextBoxSection.verseContent.rawValue] == frame)
    }

    @Test func profilesAreIndependentPerPresenter() {
        let pm = PresentationManager()
        let originalSong = pm.boxFrame(for: .verseContent, in: "song")
        let originalBible = pm.boxFrame(for: .verseContent, in: "bible")
        defer {
            pm.setBoxFrame(originalSong, for: .verseContent, in: "song")
            pm.setBoxFrame(originalBible, for: .verseContent, in: "bible")
        }

        let frame = PresentationManager.TextBoxFrame(x: 0.11, y: 0.12, width: 0.5, height: 0.3)
        pm.setBoxFrame(frame, for: .verseContent, in: "song")
        #expect(pm.boxFrame(for: .verseContent, in: "song") == frame)
        // The Bible layout is untouched by a Songs edit
        #expect(pm.boxFrame(for: .verseContent, in: "bible") == originalBible)
    }

    @Test func relevantSectionsFilterPerPresenter() {
        // Songs have no Bible translation box but DO have the chord chart;
        // slides have neither; chords are song-only.
        #expect(!PresentationManager.relevantSections(for: "song").contains(.translationName))
        #expect(PresentationManager.relevantSections(for: "song").contains(.chords))
        #expect(!PresentationManager.relevantSections(for: "text").contains(.subtitle))
        #expect(!PresentationManager.relevantSections(for: "bible").contains(.chords))
        #expect(PresentationManager.relevantSections(for: "bible") == TextBoxSection.allCases.filter { $0 != .chords })

        // The unified z-order only offers a profile's relevant boxes
        let pm = PresentationManager()
        #expect(!pm.orderedBoxTokens(in: "song").contains("section:translationName"))
        #expect(pm.orderedBoxTokens(in: "song").contains("section:chords"))
        #expect(pm.orderedBoxTokens(in: "bible").contains("section:translationName"))
        #expect(!pm.orderedBoxTokens(in: "bible").contains("section:chords"))
    }

    @Test func transitionCatalogResolvesEveryOption() {
        #expect(PresentationManager.transitionOptions.count >= 14)
        for option in PresentationManager.transitionOptions {
            _ = PresentationManager.transitionPart(option.raw) // must not crash
            #expect(PresentationManager.transitionLabel(option.raw) == option.label)
        }
    }

    @Test func copyProfileClonesLayoutBetweenPresenters() {
        let pm = PresentationManager()
        let originalSong = pm.profile("song")
        let originalBibleRef = pm.boxFrame(for: .reference, in: "bible")
        defer {
            pm.mutateProfile("song") { $0 = originalSong }
            pm.setBoxFrame(originalBibleRef, for: .reference, in: "bible")
        }

        let frame = PresentationManager.TextBoxFrame(x: 0.2, y: 0.25, width: 0.4, height: 0.2)
        pm.setBoxFrame(frame, for: .reference, in: "bible")
        pm.copyProfile(from: "bible", to: "song")
        #expect(pm.boxFrame(for: .reference, in: "song") == frame)
    }

    @Test func slideScopeMatchesFirstAndLast() {
        let pm = PresentationManager()
        pm.liveContent.setSongVerse(text: "v1", title: "T", verseLabel: "Strofa 1", slideIndex: 0, slideCount: 3)
        #expect(pm.scopeMatchesLiveSlide("all"))
        #expect(pm.scopeMatchesLiveSlide("first"))
        #expect(!pm.scopeMatchesLiveSlide("last"))

        pm.liveContent.setSongVerse(text: "v3", title: "T", verseLabel: "Strofa 3", slideIndex: 2, slideCount: 3)
        #expect(!pm.scopeMatchesLiveSlide("first"))
        #expect(pm.scopeMatchesLiveSlide("last"))

        // Single slide counts as both first AND last
        pm.liveContent.setCustomText(text: "x", title: "t")
        #expect(pm.scopeMatchesLiveSlide("first"))
        #expect(pm.scopeMatchesLiveSlide("last"))
        pm.liveContent.clear()
    }

    @Test func sourceOptionsArePerPresenter() {
        let songRaws = PresentationManager.sourceOptions(for: "song").map(\.raw)
        #expect(!songRaws.contains("translation")) // songs have no Bible translation
        #expect(songRaws.contains("slideNumber"))
        let bibleRaws = PresentationManager.sourceOptions(for: "bible").map(\.raw)
        #expect(bibleRaws.contains("translation"))
        #expect(PresentationManager.sourceOptionLabel("reference", for: "song")
                != PresentationManager.sourceOptionLabel("reference", for: "bible"))
    }

    @Test func slideNumberSourceResolves() {
        let resolved = PresentationManager.resolveBoxSource(
            "slideNumber", autoValue: "", staticText: "",
            main: "", reference: "", translation: "", subtitle: "",
            slideNumber: "2 / 7"
        )
        #expect(resolved == "2 / 7")

        let live = LiveContent()
        live.setSongVerse(text: "v", title: "T", verseLabel: "S1", slideIndex: 1, slideCount: 7)
        #expect(live.slideNumberText == "2 / 7")
    }

    @Test func boxColorPersistsPerToken() {
        let pm = PresentationManager()
        let token = "section:reference"
        defer { pm.setBoxColorHex(nil, forToken: token, in: "song") }

        #expect(pm.boxColorHex(forToken: token, in: "song") == nil)
        pm.setBoxColorHex("FF8800", forToken: token, in: "song")
        #expect(pm.boxColorHex(forToken: token, in: "song") == "FF8800")
        #expect(pm.boxColorHex(forToken: token, in: "bible") == nil) // per profile

        pm.setBoxColorHex(nil, forToken: token, in: "song") // reset drops the entry
        #expect(pm.boxColorHex(forToken: token, in: "song") == nil)
    }

    @Test func outputKeepsLastLiveProfileAfterClear() {
        let pm = PresentationManager()
        pm.activeProfileKey = "bible"
        pm.showSongVerse(text: "v", title: "T", verseLabel: "S1")
        #expect(pm.outputProfileKey == "song")

        // After Hide/Clear/ESC the EXIT transition must still use the song
        // profile, not whatever the operator is editing.
        pm.clearOutput()
        #expect(pm.outputProfileKey == "song")
        #expect(pm.contentChangeKind == "clear")
    }

    @Test func contentChangeKindTracksAppearChangeClear() {
        let pm = PresentationManager()
        pm.clearOutput()
        pm.showSongVerse(text: "v1", title: "T", verseLabel: "S1", slideIndex: 0, slideCount: 2)
        #expect(pm.contentChangeKind == "appear")
        pm.showSongVerse(text: "v2", title: "T", verseLabel: "S2", slideIndex: 1, slideCount: 2)
        #expect(pm.contentChangeKind == "change")
        pm.clearOutput()
        #expect(pm.contentChangeKind == "clear")
    }

    @Test func boxTransitionOverrideIsPerTokenAndProfile() {
        let pm = PresentationManager()
        let token = "section:verseContent"
        let original = pm.boxTransitionOverride(forToken: token, in: "song")
        defer { pm.setBoxTransitionOverride(original, forToken: token, in: "song") }

        var override = PresentationManager.BoxTransition()
        override.isCustomized = true
        override.inRaw = "blurZoom"
        override.delay = 0.3
        override.duration = 0.8
        pm.setBoxTransitionOverride(override, forToken: token, in: "song")

        let stored = pm.boxTransitionOverride(forToken: token, in: "song")
        #expect(stored.inRaw == "blurZoom")
        #expect(abs(stored.delay - 0.3) < 0.001)
        // Independent per profile
        #expect(!pm.boxTransitionOverride(forToken: token, in: "bible").isCustomized)
        _ = pm.boxTransition(in: "song", token: token) // builds without crashing

        // Resetting to a pristine override drops the stored entry
        pm.setBoxTransitionOverride(PresentationManager.BoxTransition(), forToken: token, in: "song")
        #expect(pm.boxTransitionOverride(forToken: token, in: "song") == PresentationManager.BoxTransition())
    }

    @Test func phaseDurationOverridesResolveInOrder() {
        let pm = PresentationManager()
        let originalChange = pm.phaseDurationOverride("change", in: "song")
        let originalGeneral = pm.profile("song").transitionDurationOverride
        defer {
            pm.setPhaseDurationOverride(originalChange, "change", in: "song")
            pm.setTransitionDurationOverride(originalGeneral, in: "song")
        }

        // No overrides → global duration
        pm.setPhaseDurationOverride(-1, "change", in: "song")
        pm.setTransitionDurationOverride(-1, in: "song")
        #expect(pm.resolvedTransitionDuration(phase: "change", in: "song") == pm.transitionDuration)

        // Profile general override wins over global
        pm.setTransitionDurationOverride(0.9, in: "song")
        #expect(abs(pm.resolvedTransitionDuration(phase: "change", in: "song") - 0.9) < 0.001)

        // Phase override wins over the general one
        pm.setPhaseDurationOverride(0.2, "change", in: "song")
        #expect(abs(pm.resolvedTransitionDuration(phase: "change", in: "song") - 0.2) < 0.001)
        // Other phases keep the general duration
        #expect(abs(pm.resolvedTransitionDuration(phase: "appear", in: "song") - 0.9) < 0.001)
    }

    @Test func themeHoverPreviewAppliesAndRestores() {
        let pm = PresentationManager()
        pm.clearOutput()
        let originalFont = pm.fontSize
        defer { pm.fontSize = originalFont }

        pm.fontSize = 99
        let theme = pm.saveCurrentAsTheme(named: "Hover Test", formatRaw: "all")
        defer { pm.deleteTheme(id: theme.id) }
        pm.fontSize = originalFont

        pm.beginThemeHoverPreview(id: theme.id)
        #expect(pm.isHoverPreviewingTheme)
        #expect(pm.fontSize == 99)
        pm.endThemeHoverPreview()
        #expect(!pm.isHoverPreviewingTheme)
        #expect(pm.fontSize == originalFont)

        // While LIVE the hover preview is a no-op (projector must not flicker)
        pm.showCustomText(text: "x", title: "t")
        pm.beginThemeHoverPreview(id: theme.id)
        #expect(!pm.isHoverPreviewingTheme)
        #expect(pm.fontSize == originalFont)
        pm.clearOutput()
    }

    @Test func themePayloadCarriesPerProfileTransitions() {
        let pm = PresentationManager()
        let originalIn = pm.transitionInRaw(in: "song")
        defer { pm.setTransitionIn(originalIn, in: "song") }

        pm.setTransitionIn("blurZoom", in: "song")
        let theme = pm.saveCurrentAsTheme(named: "Trans Test", formatRaw: "song")
        defer { pm.deleteTheme(id: theme.id) }

        pm.setTransitionIn("fade", in: "song")
        pm.applyTheme(id: theme.id)
        #expect(pm.transitionInRaw(in: "song") == "blurZoom")
    }

    @Test func resetAllBoxFramesRestoresDefaults() {
        let pm = PresentationManager()
        pm.setBoxFrame(.init(x: 0.2, y: 0.2, width: 0.4, height: 0.3), for: .reference)

        pm.resetAllBoxFrames()

        #expect(pm.refBoxFrame == .defaultReference)
        #expect(pm.verseBoxFrame == .defaultVerse)
    }

    @Test func fittedFontSizeNeverExceedsConfiguredSize() {
        let pm = PresentationManager()
        pm.autoFitVerseFont = true

        let longText = String(repeating: "For God so loved the world. ", count: 40)
        let fitted = pm.fittedVerseFontSize(
            text: longText,
            boxSize: CGSize(width: 800, height: 300),
            maxSize: 80,
            padding: 40,
            fontName: "",
            lineSpacing: 1.0
        )

        #expect(fitted <= 80)
        #expect(fitted >= 10)
    }

    @Test func customTextBoxLifecycle() {
        let pm = PresentationManager()
        let initialCount = pm.customTextBoxes.count

        var box = pm.addCustomTextBox()
        #expect(pm.customTextBoxes.count == initialCount + 1)

        box.text = "CCLI #123456"
        box.style.isCustomized = true
        box.style.fontSize = 24
        pm.updateCustomTextBox(box)
        #expect(pm.customTextBox(id: box.id)?.text == "CCLI #123456")
        #expect(pm.customTextBox(id: box.id)?.style.fontSize == 24)

        pm.removeCustomTextBox(id: box.id)
        #expect(pm.customTextBox(id: box.id) == nil)
        #expect(pm.customTextBoxes.count == initialCount)
    }

    @Test func quickAlignCentersBox() {
        let pm = PresentationManager()
        pm.setBoxFrame(.init(x: 0.0, y: 0.0, width: 0.4, height: 0.2), for: .verseContent)

        pm.centerBoxHorizontally(.section(.verseContent))
        pm.centerBoxVertically(.section(.verseContent))

        let frame = pm.verseBoxFrame
        #expect(abs(frame.x - 0.3) < 0.0001)
        #expect(abs(frame.y - 0.4) < 0.0001)
    }

    @Test func fontScaleUsesReferenceHeight() {
        #expect(PresentationManager.fontScale(forHeight: 1080) == 1.0)
        #expect(PresentationManager.fontScale(forHeight: 2160) == 2.0)
        #expect(PresentationManager.fontScale(forHeight: 540) == 0.5)
        #expect(PresentationManager.fontScale(forHeight: 0) == 1.0)
    }

    @Test func customBoxResolvesDynamicSources() {
        var box = PresentationManager.CustomTextBox()
        box.text = "Static text"

        let live = LiveContent()
        live.setBibleVerse(text: "Verse body", reference: "Ioan 3:16", translationName: "VDC")

        box.sourceRaw = "static"
        #expect(box.resolvedText(live: live) == "Static text")

        box.sourceRaw = "reference"
        #expect(box.resolvedText(live: live) == "Ioan 3:16")

        box.sourceRaw = "translation"
        #expect(box.resolvedText(live: live) == "VDC")
    }

    @Test func sectionSourceOverrideResolvesText() {
        let pm = PresentationManager()
        let originalSource = pm.sourceRaw(for: .reference)
        let originalStatic = pm.staticText(for: .reference)

        // Default "auto" → the box's natural field
        pm.setSourceRaw("auto", for: .reference)
        #expect(pm.sectionText(.reference, main: "M", reference: "R", translation: "T", subtitle: "S") == "R")

        // Override to another live field
        pm.setSourceRaw("translation", for: .reference)
        #expect(pm.sectionText(.reference, main: "M", reference: "R", translation: "T", subtitle: "S") == "T")

        // Static text
        pm.setSourceRaw("static", for: .reference)
        pm.setStaticText("Biserica Sion", for: .reference)
        #expect(pm.sectionText(.reference, main: "M", reference: "R", translation: "T", subtitle: "S") == "Biserica Sion")

        pm.setSourceRaw(originalSource, for: .reference)
        pm.setStaticText(originalStatic, for: .reference)
    }

    @Test func sectionVisibilityToggles() {
        let pm = PresentationManager()
        let original = pm.refBoxVisible

        pm.setSectionVisible(false, for: .reference)
        #expect(pm.isSectionVisible(.reference) == false)

        pm.toggleBoxVisibility(.section(.reference))
        #expect(pm.isSectionVisible(.reference) == true)

        pm.setSectionVisible(original, for: .reference)
    }

    @Test func mediaBoxShowsForContentFilters() {
        var box = PresentationManager.MediaBox()

        box.showOnRaw = "always"
        #expect(box.showsFor(contentType: .blank, isLive: false))

        box.showOnRaw = "bible"
        #expect(box.showsFor(contentType: .bible, isLive: true))
        #expect(!box.showsFor(contentType: .song, isLive: true))
        #expect(!box.showsFor(contentType: .bible, isLive: false))
    }

    @Test func duplicateCustomBoxOffsetsFrame() {
        let pm = PresentationManager()
        var original = pm.addCustomTextBox()
        original.text = "Original"
        pm.updateCustomTextBox(original)

        let copy = pm.duplicateCustomTextBox(id: original.id)
        #expect(copy != nil)
        #expect(copy?.id != original.id)
        #expect(copy?.text == "Original")
        #expect(copy!.frame.x > original.frame.x || copy!.frame.y > original.frame.y)

        pm.removeCustomTextBox(id: original.id)
        if let copy { pm.removeCustomTextBox(id: copy.id) }
    }

    @Test func boxStyleResolvesGlobalsWhenNotCustomized() {
        let pm = PresentationManager()
        let originalStyle = pm.refStyle
        pm.refStyle = PresentationManager.BoxTextStyle() // not customized

        let resolved = pm.resolvedStyle(for: .reference)
        // Inherits globals + the section defaults (55% size, semibold)
        #expect(abs(resolved.fontSize - pm.fontSize * 0.55) < 0.001)
        #expect(resolved.weight == .semibold)
        #expect(resolved.hAlign == pm.textAlignment)

        pm.refStyle = originalStyle
    }

    @Test func enableStyleCustomizationSeedsCurrentValues() {
        let pm = PresentationManager()
        let originalStyle = pm.verseStyle
        pm.verseStyle = PresentationManager.BoxTextStyle()

        pm.enableStyleCustomization(for: .verseContent)
        #expect(pm.verseStyle.isCustomized)
        #expect(abs(pm.verseStyle.fontSize - pm.fontSize) < 0.001)

        pm.verseStyle = originalStyle
    }

    @Test func clockFormatsProduceOutput() {
        let now = Date.now
        #expect(!PresentationManager.formattedClock(source: "date", format: "", now: now).isEmpty)
        #expect(!PresentationManager.formattedClock(source: "date", format: "short", now: now).isEmpty)
        #expect(!PresentationManager.formattedClock(source: "time", format: "", now: now).isEmpty)
        let hms = PresentationManager.formattedClock(source: "time", format: "hms", now: now)
        #expect(hms.split(separator: ":").count == 3)
    }

    @Test func resilientPayloadDecodesPartialJSON() throws {
        // Imported/old themes may carry only a subset of fields
        let json = """
        {"fontSize": 72, "backgroundMediaTypeRaw": "video",
         "frames": {"verseContent": {"x": 0.1, "y": 0.2, "width": 0.8, "height": 0.5}},
         "visibility": {"translationName": true}}
        """
        let payload = try JSONDecoder().decode(
            PresentationManager.ThemePayload.self,
            from: json.data(using: .utf8)!
        )
        #expect(payload.fontSize == 72)
        #expect(payload.backgroundMediaTypeRaw == "video")
        // Legacy flat layout fields are rebuilt as per-presenter profiles
        #expect(payload.profiles["bible"]?.frames["verseContent"]?.width == 0.8)
        #expect(payload.profiles["song"]?.frames["verseContent"]?.width == 0.8)
        #expect(payload.fontName == PresentationDefaults.fontName) // default filled in
        #expect(payload.profiles["bible"]?.customTextBoxes.isEmpty == true)
    }

    @Test func themeImportExportRoundTrip() throws {
        let pm = PresentationManager()
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("tptheme-test-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        // Build a package like the generator does (subset JSON + media file)
        let pkg = tmp.appendingPathComponent("Test.tptheme")
        let mediaDir = pkg.appendingPathComponent("media")
        try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        let fakeMedia = mediaDir.appendingPathComponent("bg.jpg")
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: fakeMedia)
        let archiveJSON = """
        {"version": 1, "name": "Temă Test", "format": "bible",
         "payload": {"fontSize": 64, "useBackgroundImage": true, "backgroundMediaTypeRaw": "image"},
         "assets": [{"slot": "background", "file": "bg.jpg", "mediaType": "image"}]}
        """
        try archiveJSON.data(using: .utf8)!.write(to: pkg.appendingPathComponent("theme.json"))

        // Import: media lands in the container, bookmark resolves
        let imported = try pm.importTheme(from: pkg)
        defer {
            pm.deleteTheme(id: imported.id)
            try? fm.removeItem(at: PresentationManager.themeMediaDirectory(for: imported.id))
        }
        #expect(imported.name == "Temă Test")
        #expect(imported.formatRaw == "bible")
        #expect(imported.payload.fontSize == 64)
        #expect(imported.payload.backgroundImageBookmark != nil)
        let resolved = PresentationManager.resolveBookmark(imported.payload.backgroundImageBookmark!)
        #expect(resolved != nil)

        // Export it back out: package contains theme.json + the media file
        let exportPkg = tmp.appendingPathComponent("Exported.tptheme")
        try pm.exportTheme(id: imported.id, to: exportPkg)
        #expect(fm.fileExists(atPath: exportPkg.appendingPathComponent("theme.json").path))
        #expect(fm.fileExists(atPath: exportPkg.appendingPathComponent("media/bg.jpg").path))

        let exportedData = try Data(contentsOf: exportPkg.appendingPathComponent("theme.json"))
        let archive = try JSONDecoder().decode(PresentationManager.ThemeArchive.self, from: exportedData)
        #expect(archive.name == "Temă Test")
        #expect(archive.format == "bible")
        #expect(archive.assets.count == 1)
        #expect(archive.payload.backgroundImageBookmark == nil) // stripped, file embedded
    }

    @Test func mediaTypeDetection() {
        #expect(PresentationManager.mediaType(forExtension: "jpg") == "image")
        #expect(PresentationManager.mediaType(forExtension: "GIF") == "gif")
        #expect(PresentationManager.mediaType(forExtension: "mp4") == "video")
        #expect(PresentationManager.mediaType(forExtension: "MOV") == "video")
    }

    @Test func verticalAlignFollowsGlobalWhenNotCustomized() {
        let pm = PresentationManager()
        let originalStyle = pm.boxStyle(for: .reference, in: "bible")
        let originalVAlign = pm.globalVAlignRaw
        defer {
            pm.setBoxStyle(originalStyle, for: .reference, in: "bible")
            pm.globalVAlignRaw = originalVAlign
        }

        // Customize (seeds vAlign), then un-customize — the stale seeded value
        // must NOT stick; the box follows the global again.
        pm.globalVAlignRaw = "top"
        pm.enableStyleCustomization(for: .reference, in: "bible")
        var style = pm.boxStyle(for: .reference, in: "bible")
        style.vAlignRaw = "bottom"
        pm.setBoxStyle(style, for: .reference, in: "bible")
        #expect(pm.resolvedStyle(for: .reference, in: "bible").vAlignRaw == "bottom")

        style.isCustomized = false
        pm.setBoxStyle(style, for: .reference, in: "bible")
        pm.globalVAlignRaw = "center"
        #expect(pm.resolvedStyle(for: .reference, in: "bible").vAlignRaw == "center")
    }

    @Test func trackingAndShadowColorResolve() {
        let pm = PresentationManager()
        let originalStyle = pm.boxStyle(for: .verseContent, in: "bible")
        let originalTracking = pm.letterTracking
        let originalShadowHex = pm.shadowColorHex
        defer {
            pm.setBoxStyle(originalStyle, for: .verseContent, in: "bible")
            pm.letterTracking = originalTracking
            pm.shadowColorHex = originalShadowHex
        }

        pm.letterTracking = 4
        var inherited = pm.resolvedStyle(for: .verseContent, in: "bible")
        #expect(inherited.tracking == 4)

        var style = pm.boxStyle(for: .verseContent, in: "bible")
        style.isCustomized = true
        style.tracking = 10
        style.shadowColorHex = "FF0000FF"
        pm.setBoxStyle(style, for: .verseContent, in: "bible")
        let overridden = pm.resolvedStyle(for: .verseContent, in: "bible")
        #expect(overridden.tracking == 10)

        // Un-set per-box tracking → back to global
        style.tracking = nil
        pm.setBoxStyle(style, for: .verseContent, in: "bible")
        inherited = pm.resolvedStyle(for: .verseContent, in: "bible")
        #expect(inherited.tracking == 4)
    }

    @Test func chorusScopeMatchesRefrenLabels() {
        let pm = PresentationManager()
        pm.liveContent.setSongVerse(text: "v", title: "T", verseLabel: "Refren 2", slideIndex: 1, slideCount: 4)
        #expect(pm.scopeMatchesLiveSlide("chorus"))
        #expect(!pm.scopeMatchesLiveSlide("verses"))

        pm.liveContent.setSongVerse(text: "v", title: "T", verseLabel: "Strofa 1", slideIndex: 0, slideCount: 4)
        #expect(!pm.scopeMatchesLiveSlide("chorus"))
        #expect(pm.scopeMatchesLiveSlide("verses"))

        pm.liveContent.setSongVerse(text: "v", title: "T", verseLabel: "CHORUS", slideIndex: 2, slideCount: 4)
        #expect(pm.scopeMatchesLiveSlide("chorus"))
        pm.liveContent.clear()

        // Song-only options exist just for the song profile
        let songRaws = PresentationManager.displayScopeOptions(for: "song").map(\.raw)
        #expect(songRaws.contains("chorus") && songRaws.contains("verses"))
        #expect(!PresentationManager.displayScopeOptions(for: "bible").map(\.raw).contains("chorus"))
    }

    @Test func payloadRoundTripsTrackingAndShadowColor() throws {
        var payload = PresentationManager.ThemePayload()
        payload.letterTracking = 7.5
        payload.shadowColorHex = "112233CC"
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PresentationManager.ThemePayload.self, from: data)
        #expect(decoded.letterTracking == 7.5)
        #expect(decoded.shadowColorHex == "112233CC")

        // Legacy payloads without the fields fall back to defaults
        let legacy = try JSONDecoder().decode(
            PresentationManager.ThemePayload.self,
            from: #"{"fontSize": 60}"#.data(using: .utf8)!
        )
        #expect(legacy.letterTracking == 0)
        #expect(legacy.shadowColorHex == "000000B3")
        #expect(legacy.wocStyleEnabled == true)
        #expect(legacy.wocColorHex == "C0392B")
    }

    @Test func redLetterThemeTravelsWithThemes() {
        let pm = PresentationManager()
        let originalEnabled = pm.wocStyleEnabled
        let originalColor = pm.wocColorHex
        defer { pm.wocStyleEnabled = originalEnabled; pm.wocColorHex = originalColor }

        pm.wocStyleEnabled = true
        pm.wocColorHex = "FF3300"
        let theme = pm.saveCurrentAsTheme(named: "WOC Test", formatRaw: "all")
        defer { pm.deleteTheme(id: theme.id) }

        pm.wocStyleEnabled = false
        pm.wocColorHex = "000000"
        pm.applyTheme(id: theme.id)
        #expect(pm.wocStyleEnabled)
        #expect(pm.wocColorHex == "FF3300")
    }

    @Test func interlinearColumnsMapRunsToWordStacks() {
        let runs = [
            VerseRun(text: "In the", kind: "plain"),
            VerseRun(text: "beginning", kind: "plain", strong: "G746", morph: "N-DSF", gloss: "început"),
        ]
        let cols = interlinearColumns(from: runs)
        #expect(cols.count == 3)                                   // 2 bare + 1 annotated
        #expect(cols[0].word == "In" && cols[0].strong == nil)
        #expect(cols[1].word == "the")
        let last = cols[2]
        #expect(last.word == "beginning")
        #expect(last.strong == "G746")
        #expect(last.morph == "N-DSF")
        #expect(last.gloss == "început")
    }

    @Test func interlinearEngagesOnlyWithContentAndMode() {
        let annotated = [VerseRun(text: "λόγος", strong: "G3056", morph: "N-NSM", gloss: "Cuvântul")]
        var off = PresentationManager.ContentOptions(); off.interlinearModeRaw = "off"
        #expect(!interlinearHasContent(annotated, options: off))

        var gloss = PresentationManager.ContentOptions(); gloss.interlinearModeRaw = "gloss"
        #expect(interlinearHasContent(annotated, options: gloss))

        var fullNoGloss = PresentationManager.ContentOptions()
        fullNoGloss.interlinearModeRaw = "full"; fullNoGloss.interlinearShowGloss = false
        #expect(interlinearHasContent(annotated, options: fullNoGloss))   // strong/morph in full

        var full = PresentationManager.ContentOptions(); full.interlinearModeRaw = "full"
        #expect(!interlinearHasContent([VerseRun(text: "word", kind: "plain")], options: full))  // nothing to show
    }

    @Test func interlinearOptionsTravelWithThemes() {
        let pm = PresentationManager()
        let original = pm.contentOptions(for: "bible")
        defer { pm.setContentOptions(original, for: "bible") }

        var o = original
        o.interlinearModeRaw = "full"
        o.interlinearShowMorph = false
        o.interlinearStrongColorHex = "D9A441"
        o.interlinearGlossScale = 0.6
        pm.setContentOptions(o, for: "bible")
        let theme = pm.saveCurrentAsTheme(named: "IL Test", formatRaw: "all")
        defer { pm.deleteTheme(id: theme.id) }

        var reset = pm.contentOptions(for: "bible")
        reset.interlinearModeRaw = "off"; reset.interlinearShowMorph = true
        reset.interlinearStrongColorHex = ""; reset.interlinearGlossScale = 0.55
        pm.setContentOptions(reset, for: "bible")

        pm.applyTheme(id: theme.id)
        let back = pm.contentOptions(for: "bible")
        #expect(back.interlinearModeRaw == "full")
        #expect(back.interlinearShowMorph == false)
        #expect(back.interlinearStrongColorHex == "D9A441")
        #expect(abs(back.interlinearGlossScale - 0.6) < 0.001)
    }

    @Test func duplicateImportMergeFillsMissingChapters() async throws {
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext

        func write(_ j: [String: Any], _ name: String) throws -> URL {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try JSONSerialization.data(withJSONObject: j).write(to: u)
            return u
        }
        // First import: Daniel with chapters 6 and 8 only (7 missing).
        let v1: [String: Any] = ["format": "TopPresenter Bible", "translation": ["code": "DUP", "name": "Dup"],
            "books": [["number": 27, "name": "Daniel", "testament": "OT", "chapters": [
                ["number": 6, "verses": [["number": 1, "text": "six"]]],
                ["number": 8, "verses": [["number": 1, "text": "eight"]]]]]]]
        let m1 = try await ImportService.importBible(fileURL: try write(v1, "dup1.json"), format: .topPresenter, modelContext: ctx, resolution: .keepBoth)
        #expect(m1.books.first?.chapters.count == 2)

        // Second import (same code) supplying the missing chapter 7 → MERGE.
        let v2: [String: Any] = ["format": "TopPresenter Bible", "translation": ["code": "DUP", "name": "Dup"],
            "books": [["number": 27, "name": "Daniel", "testament": "OT", "chapters": [
                ["number": 6, "verses": [["number": 1, "text": "SIX-overwrite-attempt"]]],
                ["number": 7, "verses": [["number": 1, "text": "seven"]]]]]]]
        let merged = try await ImportService.importBible(fileURL: try write(v2, "dup2.json"), format: .topPresenter, modelContext: ctx, resolution: .merge)

        #expect(merged.id == m1.id)                                          // merged INTO existing
        let daniel = try #require(merged.books.first)
        #expect(Set(daniel.chapters.map { $0.chapterNumber }) == [6, 7, 8])  // 7 filled in
        let ch6 = try #require(daniel.chapters.first { $0.chapterNumber == 6 })
        #expect(ch6.verses.first?.text == "six")                             // existing verse kept
        let mods = try ctx.fetch(FetchDescriptor<BibleModule>())
        #expect(mods.filter { $0.abbreviation == "DUP" }.count == 1)         // no duplicate module
    }

    @Test func duplicateImportAskThrowsConflict() async throws {
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        let j: [String: Any] = ["format": "TopPresenter Bible", "translation": ["code": "ASK", "name": "Ask"],
            "books": [["number": 1, "name": "Genesis", "testament": "OT",
                       "chapters": [["number": 1, "verses": [["number": 1, "text": "x"]]]]]]]
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("ask.json")
        try JSONSerialization.data(withJSONObject: j).write(to: u)
        _ = try await ImportService.importBible(fileURL: u, format: .topPresenter, modelContext: ctx, resolution: .keepBoth)
        await #expect(throws: ImportService.BibleConflict.self) {
            _ = try await ImportService.importBible(fileURL: u, format: .topPresenter, modelContext: ctx, resolution: .ask)
        }
    }

    @Test func liveContentCarriesVerseRuns() {
        let pm = PresentationManager()
        pm.showBibleVerse(text: "I am the light.", reference: "John 8:12",
                          runs: [VerseRun(text: "I am the light.", kind: "woc")])
        #expect(pm.liveContent.mainRuns.contains { $0.kind == "woc" })
        // A song clears the runs.
        pm.showSongVerse(text: "la la", title: "T", verseLabel: "S1")
        #expect(pm.liveContent.mainRuns.isEmpty)
        pm.clearOutput()
    }

    @Test func perBoxPaddingShadowAutoFitResolve() {
        let pm = PresentationManager()
        let original = pm.boxStyle(for: .reference, in: "song")
        defer { pm.setBoxStyle(original, for: .reference, in: "song") }

        // Not customized → inherits the globals
        var style = PresentationManager.BoxTextStyle()
        pm.setBoxStyle(style, for: .reference, in: "song")
        let inherited = pm.resolvedStyle(for: .reference, in: "song")
        #expect(inherited.padding == pm.padding)
        #expect(inherited.shadowEnabled == pm.shadowEnabled)
        #expect(inherited.autoFit == false) // global auto-fit only targets the verse box

        // Customized overrides win
        style.isCustomized = true
        style.padding = 5
        style.shadowMode = "off"
        style.autoFitMode = "on"
        pm.setBoxStyle(style, for: .reference, in: "song")
        let overridden = pm.resolvedStyle(for: .reference, in: "song")
        #expect(overridden.padding == 5)
        #expect(overridden.shadowEnabled == false)
        #expect(overridden.autoFit == true)
    }

    @Test func transformResolvesGlobalAndPerBox() {
        let pm = PresentationManager()
        let originalOptions = pm.contentOptions(for: "song")
        let originalStyle = pm.boxStyle(for: .verseContent, in: "song")
        defer {
            pm.setContentOptions(originalOptions, for: "song")
            pm.setBoxStyle(originalStyle, for: .verseContent, in: "song")
        }

        // Profile-global transform → every non-customized box inherits it
        var options = PresentationManager.ContentOptions()
        options.textTransformRaw = "upper"
        pm.setContentOptions(options, for: "song")
        let inherited = pm.resolvedStyle(for: .verseContent, in: "song")
        #expect(inherited.transformRaw == "upper")
        #expect(inherited.display("la la la") == "LA LA LA")

        // A per-box override beats the global default
        var style = pm.boxStyle(for: .verseContent, in: "song")
        style.isCustomized = true
        style.transformRaw = "lower"
        pm.setBoxStyle(style, for: .verseContent, in: "song")
        let overridden = pm.resolvedStyle(for: .verseContent, in: "song")
        #expect(overridden.transformRaw == "lower")
        #expect(overridden.display("La La") == "la la")

        // Other presenters are unaffected
        #expect(pm.resolvedStyle(for: .verseContent, in: "bible").transformRaw
                == pm.contentOptions(for: "bible").textTransformRaw)
    }

    @Test func contentOptionsTravelWithThemes() {
        let pm = PresentationManager()
        let originalOptions = pm.contentOptions

        var options = PresentationManager.ContentOptions()
        options.textTransformRaw = "upper"
        pm.setContentOptions(options, for: "song")
        let theme = pm.saveCurrentAsTheme(named: "Opt Test", formatRaw: "song")

        pm.setContentOptions(PresentationManager.ContentOptions(), for: "song")
        pm.applyTheme(id: theme.id)
        #expect(pm.contentOptions(for: "song").textTransformRaw == "upper")

        pm.deleteTheme(id: theme.id)
        pm.contentOptions = originalOptions
    }

    @Test func themesFilterByFormat() {
        let pm = PresentationManager()
        let bible = pm.saveCurrentAsTheme(named: "B", formatRaw: "bible")
        let song = pm.saveCurrentAsTheme(named: "S", formatRaw: "song")
        let universal = pm.saveCurrentAsTheme(named: "U", formatRaw: "all")
        defer {
            pm.deleteTheme(id: bible.id)
            pm.deleteTheme(id: song.id)
            pm.deleteTheme(id: universal.id)
        }

        let bibleThemes = pm.themes(forFormat: "bible")
        #expect(bibleThemes.contains(where: { $0.id == bible.id }))
        #expect(bibleThemes.contains(where: { $0.id == universal.id }))
        #expect(!bibleThemes.contains(where: { $0.id == song.id }))
    }

    @Test func themeRoundTripRestoresLook() {
        let pm = PresentationManager()
        let originalThemes = pm.themes
        let originalFrame = pm.verseBoxFrame
        let originalFontSize = pm.fontSize

        pm.fontSize = 72
        pm.setBoxFrame(.init(x: 0.1, y: 0.1, width: 0.5, height: 0.3), for: .verseContent)
        let theme = pm.saveCurrentAsTheme(named: "Test")

        // Change things, then apply the theme back
        pm.fontSize = 48
        pm.setBoxFrame(.defaultVerse, for: .verseContent)
        pm.applyTheme(id: theme.id)

        #expect(pm.fontSize == 72)
        #expect(pm.verseBoxFrame == PresentationManager.TextBoxFrame(x: 0.1, y: 0.1, width: 0.5, height: 0.3))
        #expect(pm.activeThemeID == theme.id)

        pm.deleteTheme(id: theme.id)
        pm.themes = originalThemes
        pm.verseBoxFrame = originalFrame
        pm.fontSize = originalFontSize
    }

    @Test func layoutUndoRedoRestoresBoxState() async throws {
        let pm = PresentationManager()
        let originalFrame = pm.verseBoxFrame

        let moved = PresentationManager.TextBoxFrame(x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        pm.setBoxFrame(moved, for: .verseContent)
        #expect(pm.canUndoLayout)

        pm.undoLayout()
        #expect(pm.verseBoxFrame == originalFrame)
        #expect(pm.canRedoLayout)

        pm.redoLayout()
        #expect(pm.verseBoxFrame == moved)

        // Restoring must not pollute the undo stack (suppression flag)
        pm.undoLayout()
        #expect(pm.verseBoxFrame == originalFrame)

        // Cleanup: put the frame back without leaving coalesced state behind
        try await Task.sleep(for: .milliseconds(900))
        pm.setBoxFrame(originalFrame, for: .verseContent)
    }

    @Test func layoutUndoCoalescesRapidChanges() {
        let pm = PresentationManager()
        let originalFrame = pm.verseBoxFrame
        let stackBefore = pm.layoutUndoStack.count

        // Simulates a drag: many rapid frame updates → ONE undo step
        for i in 1...20 {
            pm.setBoxFrame(.init(x: Double(i) * 0.01, y: 0.2, width: 0.4, height: 0.3), for: .verseContent)
        }
        #expect(pm.layoutUndoStack.count == stackBefore + 1)

        pm.undoLayout()
        #expect(pm.verseBoxFrame == originalFrame)
    }

    @Test func unifiedZOrderReordersAnyBox() {
        let pm = PresentationManager()
        let originalOrder = pm.boxOrder

        // Every box appears exactly once in the reconciled order
        let tokens = pm.orderedBoxTokens()
        #expect(tokens.contains("section:verseContent"))
        #expect(tokens.contains("section:reference"))
        #expect(Set(tokens).count == tokens.count)

        // Built-in sections can be sent to front/back too
        pm.moveBoxTokenToEdge("section:reference", front: true)
        #expect(pm.orderedBoxTokens().last == "section:reference")

        pm.moveBoxTokenToEdge("section:reference", front: false)
        #expect(pm.orderedBoxTokens().first == "section:reference")

        // Drag-drop placement: token lands directly above the target
        pm.reorderBoxToken("section:reference", above: "section:verseContent")
        let after = pm.orderedBoxTokens()
        let refIdx = after.firstIndex(of: "section:reference")!
        let verseIdx = after.firstIndex(of: "section:verseContent")!
        #expect(refIdx == verseIdx + 1)

        pm.boxOrder = originalOrder
    }

    @Test func freezeSnapshotsBoxFrames() {
        let pm = PresentationManager()
        let custom = PresentationManager.TextBoxFrame(x: 0.1, y: 0.1, width: 0.5, height: 0.3)
        pm.setBoxFrame(custom, for: .verseContent)

        pm.toggleFreeze()
        pm.setBoxFrame(.defaultVerse, for: .verseContent)

        // Output keeps the frozen frame while live edits continue underneath
        #expect(pm.outputBoxFrame(for: .verseContent) == custom)
        #expect(pm.verseBoxFrame == .defaultVerse)

        pm.toggleFreeze()
        #expect(pm.outputBoxFrame(for: .verseContent) == .defaultVerse)
    }
}

// MARK: - GOAT Song JSON round-trip + new importers

@MainActor struct SongGoatFormatTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test func roundTripsRichSongThroughGoatJSON() throws {
        let ctx = try makeContext()
        let collection = SongCollection(name: "T", sourceFormat: "test")
        ctx.insert(collection)
        let song = Song(title: "Mare ești Tu", author: "Anon", copyright: "©", ccliNumber: "123", songNumber: "7")
        ctx.insert(song)
        song.collection = collection
        song.titles = ["How Great Thou Art"]
        song.language = "ro"
        song.themes = ["worship", "easter"]
        song.style = "imn"
        song.songbookNumber = "42"
        let book = Songbook(name: "Cântările Evangheliei", publisher: "X", language: "ro", year: "1990")
        ctx.insert(book)
        song.songbook = book

        let v = SongVersion(name: "Clasică", order: 0, language: "ro", key: "G", capo: 2, tempo: "72", timeSignature: "4/4")
        v.arrangement = ["v1", "c", "v1", "c"]
        v.song = song
        let s1 = SongSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [
            SongLine(text: "Mare ești Tu", chords: [SongChord(sym: "G", pos: 0)], translations: ["en": "How great Thou art"])
        ])
        s1.version = v
        let s2 = SongSection(sectionKey: "c", type: "chorus", label: "Refren", order: 1, lines: [
            SongLine(text: "Atunci cânt eu", chords: [SongChord(sym: "D", pos: 6)])
        ])
        s2.version = v
        try ctx.save()

        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let results = try TopPresenterSongImporter.allResults(from: Data(json.utf8))
        // Use plain `guard let` (not #require/#expect) to unwrap the rich structs — the
        // Swift Testing macros segfault copying a large optional struct here.
        guard let r = results.first else { #expect(Bool(false), "no song parsed"); return }

        #expect(r.title == "Mare ești Tu")
        #expect(r.titles.contains("How Great Thou Art"))
        #expect(r.language == "ro")
        #expect(r.themes.contains("easter"))
        #expect(r.style == "imn")
        let bookName = r.songbook?.name
        let bookNumber = r.songbook?.number
        #expect(bookName == "Cântările Evangheliei")
        #expect(bookNumber == "42")

        guard let rv = r.versions.first else { #expect(Bool(false), "no version parsed"); return }
        let key = rv.key
        let capo = rv.capo
        let arrangement = rv.arrangement
        let secCount = rv.sections.count
        let v1Sym = rv.sections.first { $0.sectionKey == "v1" }?.lines.first?.chords.first?.sym
        let v1Trans = rv.sections.first { $0.sectionKey == "v1" }?.lines.first?.translations["en"]
        #expect(key == "G")
        #expect(capo == 2)
        #expect(arrangement == ["v1", "c", "v1", "c"])
        #expect(secCount == 2)
        #expect(v1Sym == "G")
        #expect(v1Trans == "How great Thou art")
    }

    @Test func roundTripsPerVersionOverrides() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let ctx = ModelContext(container)
        let col = SongCollection(name: "T", sourceFormat: "test"); ctx.insert(col)
        let song = Song(title: "Mare ești Tu"); ctx.insert(song); song.collection = col

        let v0 = SongVersion(name: "Original", order: 0, key: "G"); v0.song = song
        let s0 = SongSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [SongLine(text: "Mare ești Tu")])
        s0.version = v0

        let v1 = SongVersion(name: "Spaniolă", order: 1); v1.song = song
        v1.overridesMetadata = true
        v1.displayTitle = "Grande eres Tú"
        v1.author = "Trad. X"
        v1.language = "es"
        v1.key = "A"
        let s1 = SongSection(sectionKey: "v1", type: "verse", label: "Estrofa", order: 0, repeatCount: 2, lines: [SongLine(text: "Grande eres Tú")])
        s1.version = v1
        try ctx.save()

        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let results = try TopPresenterSongImporter.allResults(from: Data(json.utf8))
        guard let r = results.first, r.versions.count >= 2 else { #expect(Bool(false), "missing versions"); return }

        let rv1 = r.versions[1]
        let overrides = rv1.overridesMetadata
        let dt = rv1.displayTitle
        let auth = rv1.author
        let lang = rv1.language
        let key = rv1.key
        let rep = rv1.sections.first?.repeatCount
        #expect(r.versions.count == 2)
        #expect(overrides == true)
        #expect(dt == "Grande eres Tú")
        #expect(auth == "Trad. X")
        #expect(lang == "es")
        #expect(key == "A")
        #expect(rep == 2)
    }

    @Test func chordProParsesChordsAndSections() {
        let content = """
        {title: Amazing Grace}
        {artist: John Newton}
        {key: G}
        {start_of_verse}
        [G]Amazing [G7]grace how [C]sweet the [G]sound
        {end_of_verse}
        {start_of_chorus}
        [D]Praise the [G]Lord
        {end_of_chorus}
        """
        let r = ChordProImporter.parse(content: content, fallbackTitle: "x")
        #expect(r.title == "Amazing Grace")
        #expect(r.key == "G")
        // Extract scalars before #expect (avoids the macro copying the whole struct).
        let sectionCount = r.versions.first?.sections.count
        let firstType = r.versions.first?.sections.first?.type
        let firstLine = r.versions.first?.sections.first?.lines.first?.text
        let firstChord = r.versions.first?.sections.first?.lines.first?.chords.first?.sym
        let lastType = r.versions.first?.sections.last?.type
        #expect(sectionCount == 2)
        #expect(firstType == "verse")
        #expect(firstLine == "Amazing grace how sweet the sound")
        #expect(firstChord == "G")
        #expect(lastType == "chorus")
    }

    @Test func plainTextSplitsStanzasAndDetectsChorus() {
        let content = """
        Strofa unu
        linia doi

        [Chorus]
        Refrenul aici
        înca o linie
        """
        let r = PlainTextSongImporter.parse(content: content, fallbackTitle: "Cant")
        #expect(r.title == "Cant")
        let sectionCount = r.versions.first?.sections.count
        let firstType = r.versions.first?.sections.first?.type
        let lastType = r.versions.first?.sections.last?.type
        let lastLineCount = r.versions.first?.sections.last?.lines.count
        #expect(sectionCount == 2)
        #expect(firstType == "verse")
        #expect(lastType == "chorus")
        #expect(lastLineCount == 2)
    }
}

// MARK: - Recursive bulk import + duplicate→version

@MainActor struct SongBulkImportTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func writeSong(_ title: String, to url: URL) throws {
        let xml = "<song><title>\(title)</title><lyrics>[V1]\nPrima strofa\n[C]\nRefren aici</lyrics></song>"
        try Data(xml.utf8).write(to: url)
    }

    @Test func recursiveImportFindsSongsInSubfolders() async throws {
        let context = try makeContext()
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("bulk-\(UUID().uuidString)")
        let sub = root.appendingPathComponent("Laszlo/Nesortate")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        try writeSong("Cantec Unu", to: root.appendingPathComponent("a.xml"))
        try writeSong("Cantec Doi", to: sub.appendingPathComponent("b.xml"))

        let result = await ImportService.importSongItems(urls: [root], collectionName: "Bulk", modelContext: context)
        #expect(result.importedTitles.count == 2)
        #expect(result.collection?.songs.count == 2)
    }

    @Test func duplicateImportAddsAsVersionDiacriticInsensitive() async throws {
        let context = try makeContext()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("dup-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try writeSong("Același Cântec", to: dir.appendingPathComponent("v1.xml"))
        try writeSong("Acelasi Cantec", to: dir.appendingPathComponent("v2.xml")) // diacritic-folded match

        let result = await ImportService.importSongItems(
            urls: [dir], collectionName: "Dup", modelContext: context, duplicateResolution: .addAsVersion
        )
        #expect(result.collection?.songs.count == 1)
        let song = try #require(result.collection?.songs.first)
        #expect(song.versions.count == 2)
    }

    @Test func keepBothImportsSeparately() async throws {
        let context = try makeContext()
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("keep-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        try writeSong("Egal", to: dir.appendingPathComponent("a.xml"))
        try writeSong("Egal", to: dir.appendingPathComponent("b.xml"))

        let result = await ImportService.importSongItems(
            urls: [dir], collectionName: "Keep", modelContext: context, duplicateResolution: .keepBoth
        )
        #expect(result.collection?.songs.count == 2)
    }

    @Test func slideBuilderAutoSplitsAndExpandsArrangement() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let ctx = ModelContext(container)
        let song = Song(title: "X")
        ctx.insert(song)
        let v = SongVersion(name: "V", order: 0)
        v.song = song
        let s1 = SongSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0,
                             lines: (1...5).map { SongLine(text: "linia \($0)") })
        s1.version = v
        let s2 = SongSection(sectionKey: "c", type: "chorus", label: "Refren", order: 1,
                             lines: [SongLine(text: "ref")])
        s2.version = v
        v.arrangement = ["v1", "c", "v1"]   // verse (splits) + chorus + verse again
        try ctx.save()

        let slides = buildSongSlides(version: v, maxLines: 2, bilingual: false, language: nil)
        // v1 (5 lines / 2 = 3 slides) + c (1) + v1 (3) = 7
        #expect(slides.count == 7)
        #expect(slides.allSatisfy { $0.total == 7 })
        #expect(slides.first?.text.contains("linia 1") == true)
    }
}

// MARK: - Bible language detection / correction

@MainActor
struct BibleLanguageDetectionTests {
    @Test func refineOverridesNonLatinMismatches() {
        // A Greek interlinear mistakenly tagged "ro" → corrected to "gr".
        #expect(BibleLanguageDetection.refine(declared: "ro", sample: "Ἐν ἀρχῇ ἐποίησεν ὁ θεὸς τὸν οὐρανὸν") == "gr")
        // Hebrew → "ebr".
        #expect(BibleLanguageDetection.refine(declared: "ro", sample: "בְּרֵאשִׁית בָּרָא אֱלֹהִים אֵת הַשָּׁמַיִם") == "ebr")
        // Cyrillic mislabeled "ro" → "ru"; an already-Cyrillic code is kept.
        #expect(BibleLanguageDetection.refine(declared: "ro", sample: "В начале сотворил Бог небо и землю") == "ru")
        #expect(BibleLanguageDetection.refine(declared: "ukr", sample: "На початку Бог створив небо і землю") == "ukr")
    }

    @Test func refineLeavesLatinAndMatchingScriptsAlone() {
        // Latin script → trust the declared code (can't tell ro/en/de by letters).
        #expect(BibleLanguageDetection.refine(declared: "ro", sample: "La început a făcut Dumnezeu cerurile și pământul") == "ro")
        #expect(BibleLanguageDetection.refine(declared: "en", sample: "In the beginning God created the heavens") == "en")
        // Already-correct non-Latin code stays.
        #expect(BibleLanguageDetection.refine(declared: "gr", sample: "Ἐν ἀρχῇ ἦν ὁ λόγος καὶ ὁ λόγος") == "gr")
    }

    @Test func importCorrectsGreekModuleTaggedRomanian() async throws {
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let ctx = container.mainContext
        func write(_ j: [String: Any], _ name: String) throws -> URL {
            let u = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try JSONSerialization.data(withJSONObject: j).write(to: u)
            return u
        }

        // Greek verse text but declared language "ro" (the mislabel bug) → corrected to "gr".
        let greek: [String: Any] = ["format": "TopPresenter Bible",
            "translation": ["code": "INTER", "name": "Interlinear", "language": "ro"],
            "books": [["number": 64, "name": "3 John", "testament": "NT", "chapters": [
                ["number": 1, "verses": [["number": 1, "text": "Ὁ πρεσβύτερος τῷ ἀγαπητῷ Γαΐῳ ὃν ἐγὼ ἀγαπῶ"]]]]]]]
        let gm = try await ImportService.importBible(fileURL: try write(greek, "lang_gr.json"), format: .topPresenter, modelContext: ctx, resolution: .keepBoth)
        #expect(gm.language == "gr")
        #expect(gm.languageName == "Ελληνικά")

        // A genuinely Romanian module keeps "ro".
        let ro: [String: Any] = ["format": "TopPresenter Bible",
            "translation": ["code": "VDC", "name": "Cornilescu", "language": "ro"],
            "books": [["number": 64, "name": "3 Ioan", "testament": "NT", "chapters": [
                ["number": 1, "verses": [["number": 1, "text": "Bătrânul, către preaiubitul Gaiu, pe care îl iubesc în adevăr"]]]]]]]
        let rm = try await ImportService.importBible(fileURL: try write(ro, "lang_ro.json"), format: .topPresenter, modelContext: ctx, resolution: .keepBoth)
        #expect(rm.language == "ro")
    }
}

// MARK: - melodia.ro song: chords + arrangement + _extensions round-trip

@MainActor struct MelodiaSongRoundTripTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// A melodia-shaped GOAT song (chords at positions, deduped chorus reused in
    /// the arrangement, melodia extras under `_extensions`) imports with all of it
    /// preserved, and re-exports the `_extensions` block intact.
    @Test func importsChordsArrangementAndExtensionsThenReExports() async throws {
        let json = """
        { "schemaVersion": "1.0.0", "format": "TopPresenter Song",
          "song": {
            "title": "Voi cânta bunătatea Ta", "language": "ro",
            "themes": ["Bunatate", "indurare"],
            "authorWords": "Revive", "authorMusic": "Revive",
            "copyright": "©Revive 2023",
            "versions": [{
              "name": "", "language": "ro", "key": "F", "capo": 0, "tempo": "180", "timeSignature": "4/4",
              "source": "https://melodia.ro/cantari/Voi-canta-bunatatea-Ta",
              "arrangement": ["v1", "c1", "v2", "c1"],
              "sections": [
                { "id": "v1", "type": "verse", "label": "Strofa 1", "order": 0,
                  "lines": [{ "text": "Voi cânta a Ta îndurare,", "chords": [{ "sym": "F", "pos": 1 }] }] },
                { "id": "c1", "type": "chorus", "label": "Refren", "order": 1,
                  "lines": [{ "text": "Voi cânta bunătatea Ta,", "chords": [{ "sym": "Bb", "pos": 0 }, { "sym": "C", "pos": 13 }] }] },
                { "id": "v2", "type": "verse", "label": "Strofa 2", "order": 2,
                  "lines": [{ "text": "Ceru-ntreg e uimit de Tine", "chords": [{ "sym": "F", "pos": 1 }] }] }
              ]
            }],
            "_extensions": { "melodia": {
              "id": "7080", "slug": "Voi-canta-bunatatea-Ta", "composedYear": 2022, "meetingsCount": 100,
              "availableKeys": ["C", "Db", "D", "F"],
              "instruments": { "guitar": { "recommendedCapo": 3, "shapeKey": "D" } },
              "anatomiaEvangheliei": { "score": 4, "scoreMax": 5, "categories": [{ "name": "Adorare", "percent": 72 }] }
            } }
          } }
        """
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("mel-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Voi-canta-bunatatea-Ta.json")
        try Data(json.utf8).write(to: file)

        let ctx = try makeContext()
        let result = await ImportService.importSongItems(urls: [file], collectionName: "melodia", modelContext: ctx)
        let song = try #require(result.collection?.songs.first)

        // melodia extras survived import → DB.
        #expect(song.extensionsJSON.contains("anatomiaEvangheliei"))
        #expect(song.extensionsJSON.contains("\"composedYear\""))
        #expect(song.extensionsJSON.contains("7080"))

        // Chords + arrangement (deduped chorus reused) survived.
        let version = try #require(song.activeVersion)
        #expect(version.key == "F")
        #expect(version.arrangement == ["v1", "c1", "v2", "c1"])
        #expect(version.sortedSections.count == 3)            // chorus stored ONCE
        let chorus = try #require(version.sortedSections.first { $0.type == "chorus" })
        #expect(chorus.lines.first?.chords.map(\.sym) == ["Bb", "C"])

        // Re-export keeps the _extensions block.
        let exported = try ExportService.exportSongToTopPresenterJSON(song)
        #expect(exported.contains("_extensions"))
        #expect(exported.contains("anatomiaEvangheliei"))
        #expect(exported.contains("\"composedYear\""))
    }
}

// MARK: - Scraped sources (cantaricrestine / acorduri) import into TopPresenter

@MainActor struct ScrapedSongsImportTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }
    private func importOne(_ json: String) async throws -> Song {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scrape-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("song.json")
        try Data(json.utf8).write(to: file)
        let ctx = try makeContext()
        let res = await ImportService.importSongItems(urls: [file], collectionName: "scrape", modelContext: ctx)
        return try #require(res.collection?.songs.first)
    }

    /// A cantaricrestine song (lyrics + songbook + PowerPoint ref) imports with all of it.
    @Test func importsCantaricrestineSong() async throws {
        let json = """
        { "schemaVersion": "1.0.0", "format": "TopPresenter Song",
          "song": {
            "title": "Aceasta e ziua Domnului", "language": "ro", "songNumber": "001",
            "songbook": { "name": "Cantecele Bucuriei", "number": "001" },
            "versions": [{ "name": "", "language": "ro", "arrangement": ["v1"],
              "sections": [{ "id": "v1", "type": "verse", "label": "Strofa 1", "order": 0,
                "lines": [{ "text": "Aceasta e ziua Domnului," }, { "text": "Veseli să fim, să ne bucurăm;" }] }] }],
            "_extensions": { "cantaricrestine": { "id": "8445", "pptUrl": "https://www.cantaricrestine.ro/cantari/cb/x.ppt",
              "dataAdaugare": "2019-03-15 10:30:00", "downloads": 342, "categorySymbol": "cb", "hasLyrics": true, "hasPptx": true } }
          } }
        """
        let song = try await importOne(json)
        #expect(song.title == "Aceasta e ziua Domnului")
        #expect(song.songbook?.name == "Cantecele Bucuriei" || song.songbookNumber == "001")
        #expect(song.extensionsJSON.contains("cantaricrestine"))
        #expect(song.extensionsJSON.contains("8445"))
        let sec = try #require(song.activeVersion?.sortedSections.first)
        #expect(sec.lines.first?.text == "Aceasta e ziua Domnului,")
        // re-export keeps the source extras
        let exported = try ExportService.exportSongToTopPresenterJSON(song)
        #expect(exported.contains("cantaricrestine") && exported.contains("pptUrl"))
    }

    /// An acorduri song (author + key + positional chords) imports with chords intact.
    @Test func importsAcorduriSongWithChords() async throws {
        let json = """
        { "schemaVersion": "1.0.0", "format": "TopPresenter Song",
          "song": {
            "title": "Lauda", "language": "ro", "author": "Trei, doi, unu",
            "versions": [{ "name": "", "language": "ro", "key": "A", "arrangement": ["v1"],
              "sections": [{ "id": "v1", "type": "verse", "label": "Strofa 1", "order": 0,
                "lines": [{ "text": "Lauda fie adusa celui ce S-a nascut",
                  "chords": [{ "sym": "A", "pos": 0 }, { "sym": "D", "pos": 7 }, { "sym": "F#m", "pos": 25 }] }] }] }],
            "_extensions": { "resursecrestineAcorduri": { "id": "200084", "slug": "lauda", "hasChords": true, "keyInferred": true } }
          } }
        """
        let song = try await importOne(json)
        #expect(song.title == "Lauda")
        #expect(song.author.contains("Trei"))
        let version = try #require(song.activeVersion)
        #expect(version.key == "A")
        let line = try #require(version.sortedSections.first?.lines.first)
        #expect(line.chords.map(\.sym) == ["A", "D", "F#m"])
        #expect(line.chords.map(\.pos) == [0, 7, 25])
        #expect(song.extensionsJSON.contains("resursecrestineAcorduri"))
    }

    /// A worshiptogether song (CCLI + key + themes + positional chords + arrangement
    /// reuse) imports with everything intact — the richest of the song sources.
    @Test func importsWorshipTogetherSong() async throws {
        let json = """
        { "schemaVersion": "1.0.0", "format": "TopPresenter Song",
          "song": {
            "title": "Nothing But The Blood", "language": "en",
            "author": "Tommee Profitt, Jeremy Rosado", "authorMusic": "Tommee Profitt",
            "copyright": "© 2021 Capitol CMG", "ccliNumber": "7278328",
            "themes": ["Adoration & Praise", "Communion", "Easter"],
            "versions": [{ "name": "", "language": "en", "key": "E", "tempo": "111",
              "arrangement": ["v1", "c1", "v2", "c1", "b1"],
              "sections": [
                { "id": "v1", "type": "verse", "label": "Verse 1", "order": 0,
                  "lines": [{ "text": "What can wash away my sin?", "chords": [{ "sym": "E5", "pos": 0 }, { "sym": "B/D#", "pos": 9 }, { "sym": "C#m7", "pos": 22 }] }] },
                { "id": "c1", "type": "chorus", "label": "Chorus", "order": 1,
                  "lines": [{ "text": "O precious is the flow", "chords": [{ "sym": "E", "pos": 0 }] }] },
                { "id": "v2", "type": "verse", "label": "Verse 2", "order": 2, "lines": [{ "text": "For my pardon this I see" }] },
                { "id": "b1", "type": "bridge", "label": "Bridge", "order": 3, "lines": [{ "text": "Through Him I'll overcome" }] }
              ] }],
            "_extensions": { "worshipTogether": { "url": "https://www.worshiptogether.com/songs/x/", "ccli": "7278328",
              "originalKey": "E", "recommendedKeys": ["Db", "D", "Eb"], "bpm": 111, "tempoLabel": "Medium",
              "scripture": "Hebrews 9:22; Ephesians 1:7", "themes": ["Adoration & Praise"] } }
          } }
        """
        let song = try await importOne(json)
        #expect(song.title == "Nothing But The Blood")
        #expect(song.ccliNumber == "7278328")
        #expect(song.themes.contains("Communion"))
        let version = try #require(song.activeVersion)
        #expect(version.key == "E")
        #expect(version.arrangement == ["v1", "c1", "v2", "c1", "b1"])   // chorus reused
        let line = try #require(version.sortedSections.first?.lines.first)
        #expect(line.chords.map(\.sym) == ["E5", "B/D#", "C#m7"])
        #expect(song.extensionsJSON.contains("worshipTogether"))
        #expect(song.extensionsJSON.contains("Hebrews 9:22"))
    }
}

// MARK: - Presentation history (separate store)

@MainActor
struct HistoryStoreTests {
    private func makeStore() -> HistoryStore { HistoryStore(inMemory: true) }

    @Test func songKeyPrefersCCLIElseNormalizedTitle() {
        #expect(HistoryStore.songKey(ccli: "7278328", title: "X", source: "wt") == "ccli:7278328")
        // Same song, different casing/source → same stable key (survives re-import).
        let a = HistoryStore.songKey(ccli: "", title: "Nothing But The Blood", source: "worshiptogether")
        let b = HistoryStore.songKey(ccli: "", title: "nothing but the blood", source: "WORSHIPTOGETHER")
        #expect(a == b)
    }

    @Test func aggregatesSongSessionsAndVerses() throws {
        let s = makeStore()
        let s1 = UUID(), s2 = UUID(), key = "ccli:111"
        // Session 1: verses 1,2,3; session 2: verses 1,2.
        for (i, sess) in [(0, s1), (1, s1), (2, s1), (0, s2), (1, s2)] {
            s.record(PresentationEvent(timestamp: Date().addingTimeInterval(Double(i)), sessionID: sess,
                dwellSeconds: 5, contentType: "song", songKey: key, songTitle: "Test", verseLabel: "v\(i + 1)"))
        }
        let sum = try #require(s.summary(forSongKey: key))
        #expect(sum.timesPresented == 2)   // distinct sessions
        #expect(sum.verseShows == 5)
        #expect(s.verseTallies(forSongKey: key).contains { $0.label == "v1" && $0.count == 2 })
        #expect(s.sessions(forSongKey: key).count == 2)
    }

    @Test func aggregatesBibleVerse() throws {
        let s = makeStore()
        s.record(PresentationEvent(timestamp: .now, sessionID: UUID(), dwellSeconds: 5, contentType: "bible",
            translation: "EDC100", translationName: "Cornilescu", bookNumber: 43, bookName: "Ioan",
            chapter: 3, verseStart: 16, verseEnd: 16, reference: "Ioan 3:16"))
        let b = try #require(s.bibleSummaries().first)
        #expect(b.reference == "Ioan 3:16")
        #expect(b.translation == "EDC100")
        #expect(b.timesPresented == 1)
    }

    @Test func exportsCSVAndJSON() throws {
        let s = makeStore()
        s.record(PresentationEvent(timestamp: .now, sessionID: UUID(), dwellSeconds: 5, contentType: "song",
            songKey: "ccli:1", songTitle: "Amazing Grace", verseLabel: "v1"))
        let csv = HistoryExportService.eventsCSV(s.exportEvents())
        #expect(csv.contains("timestamp,type,title"))
        #expect(csv.contains("Amazing Grace"))
        let json = try HistoryExportService.json(s)
        #expect(json.contains("TopPresenter History"))
        #expect(json.contains("aggregates"))
    }
}

// MARK: - ChordTransposer

@MainActor struct ChordTransposerTests {

    @Test func parsesRootQualityAndBass() {
        let c = ChordTransposer.parse("Dm7")
        #expect(c?.rootPC == 2)
        #expect(c?.quality == "m7")
        #expect(c?.bassPC == nil)

        let slash = ChordTransposer.parse("D/F#")
        #expect(slash?.rootPC == 2)
        #expect(slash?.quality == "")
        #expect(slash?.bassPC == 6)

        // Non-chords are left for the caller to keep verbatim.
        #expect(ChordTransposer.parse("N.C.") == nil)
        #expect(ChordTransposer.parse("") == nil)
    }

    @Test func transposesUpKeepingQuality() {
        // C -> D is +2 semitones.
        #expect(ChordTransposer.transpose("C", by: 2, preferFlats: false) == "D")
        #expect(ChordTransposer.transpose("Am7", by: 2, preferFlats: false) == "Bm7")
        #expect(ChordTransposer.transpose("G/B", by: 2, preferFlats: false) == "A/C#")
        #expect(ChordTransposer.transpose("Csus4", by: 5, preferFlats: false) == "Fsus4")
    }

    @Test func enharmonicSpellingFollowsTargetFlavour() {
        // +1 from C: sharp world = C#, flat world = Db.
        #expect(ChordTransposer.transpose("C", by: 1, preferFlats: false) == "C#")
        #expect(ChordTransposer.transpose("C", by: 1, preferFlats: true) == "Db")
        // A flat key prefers flats throughout.
        #expect(ChordTransposer.preferFlats(forKey: "Eb"))
        #expect(ChordTransposer.preferFlats(forKey: "Bbm"))
        #expect(!ChordTransposer.preferFlats(forKey: "E"))
        #expect(!ChordTransposer.preferFlats(forKey: "A"))
    }

    @Test func semitonesBetweenKeys() {
        #expect(ChordTransposer.semitones(fromKey: "C", toKey: "D") == 2)
        #expect(ChordTransposer.semitones(fromKey: "E", toKey: "C") == 8)  // forward wrap
        #expect(ChordTransposer.semitones(fromKey: "G", toKey: "G") == 0)
    }

    @Test func transposesAWholeLineKeepingPositions() {
        let line = SongLine(text: "Mare ești Tu", chords: [SongChord(sym: "G", pos: 0), SongChord(sym: "D", pos: 10)])
        let up = ChordTransposer.transpose(line: line, by: 2, preferFlats: false)
        #expect(up.text == "Mare ești Tu")
        #expect(up.chords.map(\.sym) == ["A", "E"])
        #expect(up.chords.map(\.pos) == [0, 10])
        // A full octave (or no shift) is a no-op.
        #expect(ChordTransposer.transpose(line: line, by: 12, preferFlats: false).chords.map(\.sym) == ["G", "D"])
    }

    @Test func capoShapesAndSuggestions() {
        // Sounding E with capo 2 is fingered as D shapes.
        #expect(ChordTransposer.shapeChord("E", capo: 2, preferFlats: false) == "D")
        #expect(ChordTransposer.shapeChord("A", capo: 2, preferFlats: false) == "G")
        // To sound in F, capo 1 + E shapes (or capo 3 + D shapes, etc.).
        let sugg = ChordTransposer.capoSuggestions(forSoundingKey: "F")
        #expect(sugg.contains { $0.capo == 1 && $0.shapeKey == "E" })
        #expect(sugg.allSatisfy { $0.capo >= 1 && $0.capo <= 7 })
    }

    @Test func parsesRecommendedKeysFromExtensions() {
        let json = #"{"worshipTogether":{"recommendedKeys":["Db","D","Eb"],"bpm":111}}"#
        #expect(ChordTransposer.recommendedKeys(fromExtensionsJSON: json) == ["Db", "D", "Eb"])
        // Comma string + junk are tolerated.
        let json2 = #"{"melodia":{"keys":"G, A, junk"}}"#
        #expect(ChordTransposer.recommendedKeys(fromExtensionsJSON: json2) == ["G", "A"])
        #expect(ChordTransposer.recommendedKeys(fromExtensionsJSON: "{}") == [])
    }
}

// MARK: - Chord chart repeat markers

@MainActor struct ChordChartMarkerTests {

    @Test func bracketShiftsFirstLineChordPositions() {
        let lines = [
            SongLine(text: "Mare ești", chords: [SongChord(sym: "G", pos: 0), SongChord(sym: "D", pos: 5)]),
            SongLine(text: "Doamne", chords: [SongChord(sym: "C", pos: 0)]),
        ]
        let out = applyRepeatMarkerRich(lines, count: 2, bracket: "slash", countStyle: "none")
        #expect(out.count == 2)
        // First line gets the "/: " prefix and every chord shifts right by 3.
        #expect(out[0].text == "/: Mare ești")
        #expect(out[0].chords.map(\.pos) == [3, 8])
        #expect(out[0].chords.map(\.sym) == ["G", "D"])
        // Last line gets the closing marker; its chords are untouched.
        #expect(out[1].text == "Doamne :/")
        #expect(out[1].chords.map(\.pos) == [0])
    }

    @Test func bracketAndCountCombineInline() {
        let lines = [
            SongLine(text: "Mare ești", chords: [SongChord(sym: "G", pos: 0)]),
            SongLine(text: "Doamne", chords: [SongChord(sym: "C", pos: 0)]),
        ]
        let out = applyRepeatMarkerRich(lines, count: 2, bracket: "bar", countStyle: "times")
        #expect(out.count == 2)                         // no extra line — count is inline
        #expect(out[0].text == "‖: Mare ești")
        #expect(out[0].chords.map(\.pos) == [3])        // shifted by the 3-char prefix
        #expect(out[1].text == "Doamne :‖ (×2)")        // bracket + count on the last line
        #expect(out[1].chords.map(\.pos) == [0])
        // Text path produces the SAME line count so slides chunk identically.
        #expect(applyRepeatMarker(["Mare ești", "Doamne"], count: 2, bracket: "bar", countStyle: "times").count == 2)
    }

    @Test func bisterCountSuffix() {
        let lines = [SongLine(text: "Aleluia")]
        #expect(applyRepeatMarkerRich(lines, count: 2, bracket: "none", countStyle: "bister")[0].text == "Aleluia bis")
        #expect(applyRepeatMarkerRich(lines, count: 3, bracket: "none", countStyle: "bister")[0].text == "Aleluia ter")
    }

    @Test func noMarkerWhenSingleOrAllNone() {
        let lines = [SongLine(text: "x", chords: [SongChord(sym: "C", pos: 0)])]
        #expect(applyRepeatMarkerRich(lines, count: 1, bracket: "slash", countStyle: "times") == lines)
        #expect(applyRepeatMarkerRich(lines, count: 2, bracket: "none", countStyle: "none") == lines)
    }

    @Test func versionOverrideResolvesBracketVsCount() {
        // A version bracket override keeps the global count; a count override keeps the global bracket.
        #expect(resolveRepeat(versionStyle: "bar", globalBracket: "none", globalCount: "times") == ("bar", "times"))
        #expect(resolveRepeat(versionStyle: "times", globalBracket: "slash", globalCount: "none") == ("slash", "times"))
        #expect(resolveRepeat(versionStyle: "none", globalBracket: "bar", globalCount: "times") == ("none", "none"))
        #expect(resolveRepeat(versionStyle: "", globalBracket: "pipe", globalCount: "bister") == ("pipe", "bister"))
    }
}

// MARK: - Song verified flag + edit-log diff

@MainActor struct SongVerifiedAndEditLogTests {

    private func result(title: String, verified: Bool = false, sections: [SongImportSection]) -> SongImportResult {
        SongImportResult(
            title: title, author: "A", copyright: "", ccliNumber: "", key: "C", tempo: "",
            songNumber: "", tags: "", verses: [],
            versions: [SongImportVersion(name: "", sections: sections)], verified: verified)
    }

    @Test func verifiedExportsAndParses() {
        // Export side: songDictV2 carries the flag only when true.
        let song = Song(title: "Test")
        #expect(ExportService.songDictV2(song)["verified"] == nil)
        song.verified = true
        #expect(ExportService.songDictV2(song)["verified"] as? Bool == true)
        // Import side: round-trips back through the GOAT parser.
        let json = #"{"song":{"title":"X","verified":true,"versions":[]}}"#
        #expect(TopPresenterSongImporter.result(fromJSON: json)?.verified == true)
        #expect(TopPresenterSongImporter.result(fromJSON: #"{"song":{"title":"Y"}}"#)?.verified == false)
    }

    @Test func editLogDiffSummarizesChanges() {
        let v1 = SongImportSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [SongLine(text: "a")])
        let old = result(title: "Cântec", sections: [v1])

        let v1edited = SongImportSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [SongLine(text: "a schimbat")])
        let chorus = SongImportSection(sectionKey: "c", type: "chorus", label: "Refren", order: 1, lines: [SongLine(text: "r")])
        let new = result(title: "Cântec nou", verified: true, sections: [v1edited, chorus])

        let s = ImportService.summarizeChanges(old: old, new: new)
        #expect(s.contains("Titlu modificat"))
        #expect(s.contains("Marcat verificat"))
        #expect(s.contains { $0.contains("Strofa 1") && $0.contains("editat") })
        #expect(s.contains { $0.contains("Refren") && $0.contains("adăugat") })

        // No changes → no entries.
        #expect(ImportService.summarizeChanges(old: old, new: old).isEmpty)
    }

    @Test func deletedSectionIsReported() {
        let v1 = SongImportSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [SongLine(text: "a")])
        let chorus = SongImportSection(sectionKey: "c", type: "chorus", label: "Refren", order: 1, lines: [SongLine(text: "r")])
        let old = result(title: "C", sections: [v1, chorus])
        let new = result(title: "C", sections: [v1])
        let s = ImportService.summarizeChanges(old: old, new: new)
        #expect(s.contains { $0.contains("Refren") && $0.contains("șters") })
    }
}

// MARK: - PinStore Tests (session-only song pins)

@MainActor struct PinStoreTests {
    @Test @MainActor func toggleAndClearSemantics() {
        let store = PinStore()
        let a = UUID(), b = UUID()
        #expect(!store.hasPins)

        store.togglePin(a)
        #expect(store.isPinned(a))
        #expect(!store.isPinned(b))
        #expect(store.hasPins)

        store.togglePin(a)   // toggle off
        #expect(!store.isPinned(a))
        #expect(!store.hasPins)

        store.togglePin(a); store.togglePin(b)
        store.clearPins()
        #expect(!store.isPinned(a) && !store.isPinned(b))
        #expect(!store.hasPins)
    }

    @Test @MainActor func partitionPreservesOrderAndExcludesPinnedFromRest() {
        let s1 = Song(title: "Alfa"), s2 = Song(title: "Beta"), s3 = Song(title: "Gama")
        let songs = [s1, s2, s3]

        // Empty pins → everything in rest, order intact.
        let none = PinStore.partition(songs, pinnedIDs: [])
        #expect(none.pinned.isEmpty)
        #expect(none.rest.map(\.id) == songs.map(\.id))

        // Pin the middle one → floats out of rest, both halves keep input order.
        let some = PinStore.partition(songs, pinnedIDs: [s2.id])
        #expect(some.pinned.map(\.id) == [s2.id])
        #expect(some.rest.map(\.id) == [s1.id, s3.id])

        // Pin all (plus an unknown id) → rest empty, order preserved.
        let all = PinStore.partition(songs, pinnedIDs: Set(songs.map(\.id) + [UUID()]))
        #expect(all.pinned.map(\.id) == songs.map(\.id))
        #expect(all.rest.isEmpty)
    }
}

// MARK: - Session Tests (stable refs, resolution, runner navigation)

@MainActor
struct SessionTests {
    private func makeInMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    // MARK: Payload round-trip + resilience

    @Test func payloadRoundTripsAndDecodesMissingKeys() {
        var p = SessionItemPayload()
        p.translation = "EDC100"; p.bookNumber = 43; p.bookName = "Ioan"
        p.chapter = 3; p.verseStart = 16; p.verseEnd = 17
        let decoded = SessionItemPayload.decode(fromJSON: p.encodedJSON())
        #expect(decoded == p)

        // Older/minimal JSON (missing keys) → defaults, no crash.
        let minimal = SessionItemPayload.decode(fromJSON: #"{"songKey":"ccli:12345"}"#)
        #expect(minimal.songKey == "ccli:12345")
        #expect(minimal.translation.isEmpty && minimal.verseStart == 0)
        // Garbage → empty payload.
        #expect(SessionItemPayload.decode(fromJSON: "not json").isEmpty)
    }

    // MARK: Append drafts

    @Test func appendStampsPayloadSnapshotAndOrder() throws {
        let context = try makeInMemoryContext()
        let schedule = SessionService.createSession(name: "Duminică", context: context)

        let song = Song(title: "Măreț ești Tu", ccliNumber: "14181")
        context.insert(song)
        let media = MediaItem(name: "fundal.jpg", filePath: "/x/fundal.jpg", mediaType: "image")
        context.insert(media)

        SessionService.append(.bible(translation: "EDC100", bookNumber: 43, bookName: "Ioan",
                                     chapter: 3, verseStart: 16, verseEnd: 17,
                                     displayReference: "Ioan 3:16-17", snapshotText: "Fiindcă atât..."),
                              to: schedule, context: context)
        SessionService.append(.song(song, version: nil), to: schedule, context: context)
        SessionService.append(.media(media), to: schedule, context: context)
        SessionService.append(.blank, to: schedule, context: context)

        let items = schedule.sortedItems
        #expect(items.map(\.itemType) == ["bible", "song", "media", "blank"])
        #expect(items.map(\.order) == [0, 1, 2, 3])
        // Snapshots stay readable.
        #expect(items[0].title == "Ioan 3:16-17")
        #expect(items[1].title == "Măreț ești Tu")
        // Stable refs stamped.
        #expect(SessionService.payload(for: items[0]).verseStart == 16)
        #expect(SessionService.payload(for: items[1]).songKey == "ccli:14181")
        #expect(SessionService.payload(for: items[2]).mediaID == media.id.uuidString)
    }

    // MARK: Resolution

    @Test func songResolvesByStableKeyAndMediaByIDThenName() throws {
        let context = try makeInMemoryContext()
        let schedule = SessionService.createSession(name: "Test", context: context)

        let song = Song(title: "Aleluia", ccliNumber: "777")
        context.insert(song)
        let media = MediaItem(name: "intro.mp4", filePath: "/x/intro.mp4", mediaType: "video")
        context.insert(media)
        let songItem = SessionService.append(.song(song, version: nil), to: schedule, context: context)
        let mediaItem = SessionService.append(.media(media), to: schedule, context: context)

        // Song: delete + re-import with a NEW UUID but same CCLI → still resolves.
        context.delete(song)
        let reimported = Song(title: "Aleluia (nou)", ccliNumber: "777")
        context.insert(reimported)
        try context.save()
        guard case let .song(resolved, _) = SessionService.resolve(songItem, context: context) else {
            Issue.record("song did not resolve"); return
        }
        #expect(resolved.id == reimported.id)

        // Media: delete + same NAME → resolves by name fallback.
        context.delete(media)
        let renamedID = MediaItem(name: "intro.mp4", filePath: "/y/intro.mp4", mediaType: "video")
        context.insert(renamedID)
        try context.save()
        guard case let .media(resolvedMedia) = SessionService.resolve(mediaItem, context: context) else {
            Issue.record("media did not resolve"); return
        }
        #expect(resolvedMedia.id == renamedID.id)

        // Gone entirely → .missing.
        context.delete(renamedID)
        context.delete(reimported)
        try context.save()
        #expect(SessionService.resolve(songItem, context: context).isMissing)
        #expect(SessionService.resolve(mediaItem, context: context).isMissing)
    }

    @Test func bibleResolvesVerseRangeFromLibrary() throws {
        let context = try makeInMemoryContext()
        let module = BibleModule(name: "Test Bible", abbreviation: "TB1", language: "ro", sourceFormat: "test")
        let book = BibleBook(name: "Ioan", bookNumber: 43, testament: "NT")
        let chapter = BibleChapter(chapterNumber: 3)
        chapter.verses = [
            BibleVerse(verseNumber: 16, text: "Fiindcă atât de mult a iubit Dumnezeu lumea"),
            BibleVerse(verseNumber: 17, text: "Dumnezeu nu a trimis pe Fiul Său ca să judece"),
        ]
        book.chapters = [chapter]
        module.books = [book]
        context.insert(module)
        try context.save()

        let schedule = SessionService.createSession(name: "T", context: context)
        let item = SessionService.append(.bible(translation: "TB1", bookNumber: 43, bookName: "Ioan",
                                                chapter: 3, verseStart: 16, verseEnd: 17,
                                                displayReference: "Ioan 3:16-17", snapshotText: "x"),
                                         to: schedule, context: context)

        guard case let .bible(text, reference, translationName) = SessionService.resolve(item, context: context) else {
            Issue.record("bible did not resolve"); return
        }
        #expect(text.contains("iubit") && text.contains("judece"))
        #expect(reference == "Ioan 3:16-17")
        #expect(translationName == "TB1")

        // Unknown translation → missing.
        let bad = SessionService.append(.bible(translation: "NOPE", bookNumber: 43, bookName: "Ioan",
                                               chapter: 3, verseStart: 16, verseEnd: 16,
                                               displayReference: "Ioan 3:16", snapshotText: "x"),
                                        to: schedule, context: context)
        #expect(SessionService.resolve(bad, context: context).isMissing)
    }

    // MARK: Runner navigation

    @Test func runnerWalksItemsSkipsMissingAndClamps() throws {
        let context = try makeInMemoryContext()
        let schedule = SessionService.createSession(name: "Flux", context: context)
        SessionService.append(.text(title: "Bun venit", content: "Salut"), to: schedule, context: context)
        // A missing item in the middle (media that doesn't exist).
        let ghost = MediaItem(name: "ghost.mp4", filePath: "/none", mediaType: "video")
        context.insert(ghost)
        SessionService.append(.media(ghost), to: schedule, context: context)
        context.delete(ghost)
        SessionService.append(.text(title: "Încheiere", content: "Amin"), to: schedule, context: context)
        try context.save()

        let runner = SessionRunner()   // no pm wired — navigation math only
        runner.start(schedule, context: context)
        #expect(runner.isRunning)
        #expect(runner.itemIndex == 0)

        runner.next(context: context)          // skips the missing media
        #expect(runner.itemIndex == 2)
        runner.next(context: context)          // clamped at the end
        #expect(runner.itemIndex == 2)
        runner.previous(context: context)      // skips back over the missing one
        #expect(runner.itemIndex == 0)
        runner.previous(context: context)      // clamped at the start
        #expect(runner.itemIndex == 0)

        runner.jump(toItem: 99, context: context)
        #expect(runner.itemIndex == 2)         // clamped jump
        runner.stop()
        #expect(!runner.isRunning)
    }
}

// MARK: - Session Archive Tests (.tpschedule round-trip)

@MainActor
struct SessionArchiveTests {
    private func makeInMemoryContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    @Test func exportImportRoundTripPreservesEverything() throws {
        let source = try makeInMemoryContext()
        let schedule = SessionService.createSession(name: "Duminică dimineața", context: source)
        schedule.notes = "Cu botez"
        SessionService.append(.bible(translation: "EDC100", bookNumber: 43, bookName: "Ioan",
                                     chapter: 3, verseStart: 16, verseEnd: 16,
                                     displayReference: "Ioan 3:16", snapshotText: "Fiindcă atât…"),
                              to: schedule, context: source)
        SessionService.append(.text(title: "Anunțuri", content: "Program de vară"), to: schedule, context: source)
        SessionService.append(.blank, to: schedule, context: source)

        let data = try SessionArchiveService.export(schedule)

        // Import into a FRESH library.
        let dest = try makeInMemoryContext()
        let (imported, unresolved) = try SessionArchiveService.importSession(data, context: dest)
        #expect(imported.name == "Duminică dimineața")
        #expect(imported.notes == "Cu botez")
        #expect(unresolved.isEmpty)

        let items = imported.sortedItems
        #expect(items.map(\.itemType) == ["bible", "text", "blank"])
        #expect(items.map(\.order) == [0, 1, 2])
        #expect(items[0].title == "Ioan 3:16")
        #expect(SessionService.payload(for: items[0]).verseStart == 16)
        #expect(items[1].content == "Program de vară")
    }

    @Test func importRelinksMediaByNameAndReportsMissing() throws {
        let source = try makeInMemoryContext()
        let schedule = SessionService.createSession(name: "Media test", context: source)
        let media = MediaItem(name: "intro.mp4", filePath: "/a/intro.mp4", mediaType: "video")
        source.insert(media)
        SessionService.append(.media(media), to: schedule, context: source)
        let ghost = MediaItem(name: "ghost.jpg", filePath: "/a/ghost.jpg", mediaType: "image")
        source.insert(ghost)
        SessionService.append(.media(ghost), to: schedule, context: source)
        let data = try SessionArchiveService.export(schedule)

        // Destination library has "intro.mp4" under a DIFFERENT id, and no ghost.
        let dest = try makeInMemoryContext()
        let localIntro = MediaItem(name: "intro.mp4", filePath: "/b/intro.mp4", mediaType: "video")
        dest.insert(localIntro)
        try dest.save()

        let (imported, unresolved) = try SessionArchiveService.importSession(data, context: dest)
        #expect(unresolved == ["ghost.jpg"])
        let payload = SessionService.payload(for: imported.sortedItems[0])
        #expect(payload.mediaID == localIntro.id.uuidString)   // re-linked by name
        // The re-linked item resolves; the ghost is missing.
        #expect(!SessionService.resolve(imported.sortedItems[0], context: dest).isMissing)
        #expect(SessionService.resolve(imported.sortedItems[1], context: dest).isMissing)
    }

    @Test func decodesMinimalAndRejectsForeignJSON() throws {
        let dest = try makeInMemoryContext()
        // Older/minimal archive (missing keys everywhere) still imports.
        let minimal = #"{"format":"TopPresenter Session","items":[{"itemType":"blank"}]}"#
        let (imported, _) = try SessionArchiveService.importSession(Data(minimal.utf8), context: dest)
        #expect(imported.sortedItems.count == 1)
        #expect(imported.sortedItems[0].itemType == "blank")

        // Foreign JSON is rejected with a clear error.
        #expect(throws: (any Error).self) {
            try SessionArchiveService.importSession(Data(#"{"hello":1}"#.utf8), context: dest)
        }
    }
}

// MARK: - MediaLibrary Tests (kind classification + shared filter/stepping)

@MainActor struct MediaLibraryTests {
    @Test func classifiesByExtension() {
        #expect(MediaKind.classify(extension: "JPG") == .image)
        #expect(MediaKind.classify(extension: "heic") == .image)
        #expect(MediaKind.classify(extension: "mp4") == .video)
        #expect(MediaKind.classify(extension: "MOV") == .video)
        #expect(MediaKind.classify(extension: "mp3") == .audio)
        #expect(MediaKind.classify(extension: "flac") == .audio)
        #expect(MediaKind.classify(extension: "xyz") == .image)   // permissive fallback
    }

    @Test @MainActor func filterByKindAndQueryPreservesOrder() {
        let a = MediaItem(name: "Închinare fundal.jpg", filePath: "/a", mediaType: "image")
        let b = MediaItem(name: "Intro video.mp4", filePath: "/b", mediaType: "video")
        let c = MediaItem(name: "Inchinare pian.mp3", filePath: "/c", mediaType: "audio")
        let items = [a, b, c]

        // "all" + empty query → everything, input order.
        #expect(MediaLibrary.filter(items, kindRaw: "all", query: "").map(\.id) == items.map(\.id))
        // Kind filter.
        #expect(MediaLibrary.filter(items, kindRaw: "video", query: "").map(\.id) == [b.id])
        // Diacritic-insensitive query matches both "Închinare" and "Inchinare".
        #expect(MediaLibrary.filter(items, kindRaw: "all", query: "inchinare").map(\.id) == [a.id, c.id])
        // Query + kind combine.
        #expect(MediaLibrary.filter(items, kindRaw: "audio", query: "închinare").map(\.id) == [c.id])
    }

    @Test @MainActor func neighborStepsAndClamps() {
        let a = MediaItem(name: "a", filePath: "/a", mediaType: "image")
        let b = MediaItem(name: "b", filePath: "/b", mediaType: "image")
        let c = MediaItem(name: "c", filePath: "/c", mediaType: "image")
        let items = [a, b, c]

        #expect(MediaLibrary.neighbor(of: b, in: items, direction: +1)?.id == c.id)
        #expect(MediaLibrary.neighbor(of: b, in: items, direction: -1)?.id == a.id)
        // Clamped at the ends.
        #expect(MediaLibrary.neighbor(of: c, in: items, direction: +1)?.id == c.id)
        #expect(MediaLibrary.neighbor(of: a, in: items, direction: -1)?.id == a.id)
        // No selection → first/last depending on direction; empty list → nil.
        #expect(MediaLibrary.neighbor(of: nil, in: items, direction: +1)?.id == a.id)
        #expect(MediaLibrary.neighbor(of: nil, in: items, direction: -1)?.id == c.id)
        #expect(MediaLibrary.neighbor(of: a, in: [], direction: +1) == nil)
    }
}

// MARK: - Search Index Tests (token inverted index + folding)

struct SearchIndexTests {
    @Test func tokenIndexPrefixMatchAndIntersection() {
        let blobs = [
            searchFold("Măreț ești Tu Doamne mare"),      // 0
            searchFold("Ce mare ești Tu Isuse"),           // 1
            searchFold("Aleluia cântați Domnului"),        // 2
        ]
        let idx = TokenIndex.build(blobs: blobs)

        // Prefix match, diacritic-insensitive.
        #expect(idx.candidates(prefix: "mare") == Set([0, 1]))
        #expect(idx.candidates(prefix: "mar") == Set([0, 1]))       // "maret" + "mare"
        // Multi-token AND.
        #expect(idx.match(queryTokens: ["mare", "isuse"]) == Set([1]))
        #expect(idx.match(queryTokens: ["mare", "aleluia"])?.isEmpty == true)
        // Empty query → nil (no filter).
        #expect(idx.match(queryTokens: []) == nil)
        // Diacritic query folds the same way.
        #expect(searchTokens("Cântați") == ["cantati"])
        #expect(idx.match(queryTokens: searchTokens("cântați")) == Set([2]))
    }
}

// MARK: - Palette Search Tests (typo tolerance + verse token search)

struct PaletteSearchTests {
    private func song(_ title: String, author: String = "", lyrics: String = "") -> SongIndexEntry {
        SongIndexEntry(id: UUID(), title: title, author: author, language: "", songNumber: "",
                       songbookName: "", collectionID: nil, collectionName: "", versionCount: 1,
                       hasMedia: false, verified: false, modifiedDate: .now,
                       firstLine: "", blob: searchFold("\(title) \(author) \(lyrics)"),
                       songKey: HistoryStore.songKey(ccli: "", title: title, source: ""))
    }

    private func verse(_ book: Int, _ bookName: String, _ chapter: Int, _ v: Int,
                       _ text: String, moduleID: UUID = UUID()) -> VerseIndexEntry {
        VerseIndexEntry(moduleID: moduleID, bookNumber: book, bookName: bookName,
                        chapter: chapter, verse: v, text: text, folded: searchFold(text))
    }

    private func snapshot(songs: [SongIndexEntry] = [], verses: [VerseIndexEntry] = [],
                          books: [BookIndexEntry] = [],
                          presentCounts: [String: Int] = [:]) -> PaletteSnapshot {
        PaletteSnapshot(songs: songs,
                        songTokens: TokenIndex.build(blobs: songs.map(\.blob)),
                        verses: verses,
                        verseTokens: TokenIndex.build(blobs: verses.map(\.folded)),
                        media: [], sessions: [], books: books,
                        presentCounts: presentCounts)
    }

    @Test func fuzzyPrefixToleratesTypos() {
        let idx = TokenIndex.build(blobs: [searchFold("Amazing grace how sweet the sound")])
        // No exact prefix for the typo…
        #expect(idx.candidates(prefix: "amaizng").isEmpty)
        // …but the fuzzy fallback finds it (transposition = 2 edits).
        #expect(idx.fuzzyCandidates(token: "amaizng", maxDistance: 2) == Set([0]))
        #expect(idx.fuzzyCandidates(token: "grce", maxDistance: 1) == Set([0]))
        // Distance policy: short tokens never fuzz.
        #expect(TokenIndex.fuzzyDistance(for: "hai") == 0)
        #expect(TokenIndex.fuzzyDistance(for: "grace") == 1)
        #expect(TokenIndex.fuzzyDistance(for: "amazing") == 2)
    }

    @Test func paletteSearchFindsSongsDespiteTypos() {
        let s = snapshot(songs: [song("Amazing Grace"), song("Mărire Ție"), song("Ce mare ești Tu")])
        #expect(PaletteSearch.run("amazing", in: s).songsByTitle.first?.title == "Amazing Grace")
        // One typo'd token + one clean token still AND-match (typo'd tokens
        // can't be verified against the title, so they land in the content bucket).
        let typo = PaletteSearch.run("amaizng grace", in: s)
        #expect((typo.songsByTitle + typo.songsByContent).first?.title == "Amazing Grace")
        // Typo over a diacritic word.
        let dia = PaletteSearch.run("marrire", in: s)
        #expect((dia.songsByTitle + dia.songsByContent).first?.title == "Mărire Ție")
        // Nonsense stays empty.
        let none = PaletteSearch.run("xyzzyq", in: s)
        #expect(none.songsByTitle.isEmpty && none.songsByContent.isEmpty)
    }

    @Test func titleMatchesRankAboveLyricsMatches() {
        let s = snapshot(songs: [
            song("Isus e viu"),
            song("Cântare de laudă", lyrics: "isus este domn peste toate"),
        ])
        let hits = PaletteSearch.run("isus", in: s)
        #expect(hits.songsByTitle.map(\.title) == ["Isus e viu"])
        #expect(hits.songsByContent.map(\.title) == ["Cântare de laudă"])
    }

    @Test func numericTokensMatchExactlyNotByPrefix() {
        let s = snapshot(songs: [
            song("Cântare specială", lyrics: "cum spune in matei 28 19 mergeti"),
            song("Cântarea 5"),
        ])
        // "matei 1 2" must NOT match a song quoting Matei 28:19 (1⊄19, 2⊄28).
        let wrong = PaletteSearch.run("matei 1 2", in: s)
        #expect(wrong.songsByTitle.isEmpty && wrong.songsByContent.isEmpty)
        // The exact numbers DO match.
        let right = PaletteSearch.run("matei 28 19", in: s)
        #expect((right.songsByTitle + right.songsByContent).count == 1)
        // Single digits are indexed and match exactly.
        #expect(PaletteSearch.run("cantarea 5", in: s).songsByTitle.first?.title == "Cântarea 5")
        // Numbers never fuzz: "12" must not drift to anything.
        let idx = TokenIndex.build(blobs: ["psalm 121"])
        #expect(PaletteSearch.matchTokens(["psalm", "12"], index: idx)?.isEmpty == true)
    }

    @Test func verseTokenSearchFindsPhrasesAndTypos() {
        let verses = [
            verse(1, "Geneza", 1, 1, "La început, Dumnezeu a făcut cerurile și pământul."),
            verse(43, "Ioan", 3, 16, "Fiindcă atât de mult a iubit Dumnezeu lumea"),
        ]
        let s = snapshot(verses: verses)
        // Whole phrase ranks first.
        #expect(PaletteSearch.run("facut cerurile", in: s).verses.first?.bookNumber == 1)
        // Typo'd verse word still matches via fuzzy.
        #expect(PaletteSearch.run("ceruriel", in: s).verses.count == 1)
        // Both verses share "dumnezeu"; the total travels with the hits.
        let both = PaletteSearch.run("dumnezeu", in: s)
        #expect(both.verses.count == 2)
        #expect(both.versesTotal == 2)
    }

    private var romanianBooks: [BookIndexEntry] {
        let mod = UUID()
        return [
            .init(moduleID: mod, bookNumber: 40, name: "Matei", folded: "matei",
                  abbreviationFolded: "mt", chapterCount: 28),
            .init(moduleID: mod, bookNumber: 44, name: "Faptele Apostolilor", folded: "faptele apostolilor",
                  abbreviationFolded: "fa", chapterCount: 28),
            .init(moduleID: mod, bookNumber: 48, name: "Galateni", folded: "galateni",
                  abbreviationFolded: "gal", chapterCount: 6),
            .init(moduleID: mod, bookNumber: 22, name: "Cântarea Cântărilor", folded: "cantarea cantarilor",
                  abbreviationFolded: "cant", chapterCount: 8),
        ]
    }

    @Test func bookHintResolvesAnyTokenPosition() {
        let books = romanianBooks
        // Book word in ANY position, remaining tokens = the text query.
        let hint1 = PaletteSearch.bookHint(tokens: ["isus", "fapte"], books: books)
        #expect(hint1?.book.bookNumber == 44)
        #expect(hint1?.remaining == ["isus"])
        let hint2 = PaletteSearch.bookHint(tokens: ["fapte", "isus"], books: books)
        #expect(hint2?.book.bookNumber == 44)
        #expect(hint2?.remaining == ["isus"])
        // "galile" is Galileea (text), not Galateni — no prefix match, no hint.
        #expect(PaletteSearch.bookHint(tokens: ["isus", "galile"], books: books) == nil)
        // All-numeric remainder is a REFERENCE — parser owns it, no hint.
        #expect(PaletteSearch.bookHint(tokens: ["matei", "1", "2"], books: books) == nil)
        // Single token = no hint (nothing left to search).
        #expect(PaletteSearch.bookHint(tokens: ["fapte"], books: books) == nil)
    }

    @Test func bookScopedVersesRankAboveGlobalMatches() {
        let verses = [
            // Luca-style verse containing BOTH words as text (global match).
            verse(42, "Luca", 24, 19, "Ce s-a întâmplat cu Isus, prooroc puternic în fapte și cuvinte"),
            // Verse IN Faptele Apostolilor containing doar "isus" (scoped match).
            verse(44, "Faptele Apostolilor", 1, 1, "Teofile, am vorbit despre tot ce a început Isus să facă"),
        ]
        let s = snapshot(verses: verses, books: romanianBooks)
        let hits = PaletteSearch.run("isus fapte", in: s).verses
        // Faptele verse first (book-scoped), the Luca text match after.
        #expect(hits.first?.bookNumber == 44)
        #expect(hits.count == 2)
    }

    @Test func globalVerseFillSpreadsAcrossBooksThenRelaxes() {
        let verses = [
            verse(40, "Matei", 1, 1, "Isus unu"),
            verse(40, "Matei", 1, 2, "Isus doi"),
            verse(40, "Matei", 1, 3, "Isus trei"),
            verse(41, "Marcu", 1, 1, "Isus la Marcu"),
        ]
        let s = snapshot(verses: verses)
        let r = PaletteSearch.run("isus", in: s)
        // Diversity first (max 2/book), then relaxed fill keeps everything reachable.
        #expect(r.verses.map(\.bookNumber) == [40, 40, 41, 40])
        #expect(r.versesTotal == 4)
    }

    @Test func popularSongsRankFirstWithinBucket() {
        let a = song("Isus e viu")
        let b = song("Isus, Numele minunat")
        let s = snapshot(songs: [a, b],
                         presentCounts: [b.songKey: 12])
        // Alphabetical would put A first — popularity boosts B.
        #expect(PaletteSearch.run("isus", in: s).songsByTitle.map(\.title)
                == ["Isus, Numele minunat", "Isus e viu"])
    }

    @Test func bareBookQueryOffersTheBook() {
        let books = romanianBooks + [.init(moduleID: UUID(), bookNumber: 66, name: "Apocalipsa",
                                           folded: "apocalipsa", abbreviationFolded: "ap",
                                           chapterCount: 22)]
        let s = snapshot(books: books)
        // "apocal" / "apocalipsa" were dead ends — now they open the book.
        let partial = PaletteSearch.run("apocal", in: s)
        #expect(partial.reference?.isBookOnly == true)
        #expect(partial.reference?.bookNumber == 66)
        #expect(!partial.isEmpty)
        #expect(PaletteSearch.run("apocalipsa", in: s).reference?.bookNumber == 66)
    }
}

// MARK: - Search Index Builder Order Tests

@MainActor struct SearchIndexBuilderOrderTests {
    /// Relationship arrays are unordered — the verse index must come out in
    /// canonical Bible order regardless of insertion order.
    @Test func verseIndexIsCanonicallyOrdered() async throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let module = BibleModule(name: "Test", abbreviation: "TST", sourceFormat: "test")
        context.insert(module)
        let book = BibleBook(name: "Matei", bookNumber: 40, testament: "NT")
        book.module = module
        context.insert(book)
        // Chapters and verses inserted deliberately OUT of order.
        for chapterNumber in [2, 1] {
            let chapter = BibleChapter(chapterNumber: chapterNumber)
            chapter.book = book
            context.insert(chapter)
            for verseNumber in [3, 1, 2] {
                let verse = BibleVerse(verseNumber: verseNumber, text: "c\(chapterNumber) v\(verseNumber)")
                verse.chapter = chapter
                context.insert(verse)
            }
        }
        try context.save()

        let builder = SearchIndexBuilder(modelContainer: container)
        let payload = await builder.buildVerses(moduleID: module.id)
        #expect(payload.verses.map { "\($0.chapter):\($0.verse)" }
                == ["1:1", "1:2", "1:3", "2:1", "2:2", "2:3"])
    }
}

// MARK: - Palette Highlight Tests

@MainActor
struct PaletteHighlightTests {
    @Test func highlightsDiacriticInsensitiveRanges() {
        let attr = paletteHighlight("Mărire Ție, Doamne", tokens: ["marire"],
                                    highlightFont: .body.bold())
        let colored = attr.runs.filter { $0.foregroundColor != nil }
        #expect(colored.count == 1)
        if let run = colored.first {
            #expect(String(attr.characters[run.range]) == "Mărire")
        }
    }
}

// MARK: - Spotlight Identifier Tests

struct SpotlightIdentifierTests {
    @Test func parsesKnownKindsAndRejectsJunk() {
        let id = UUID()
        let song = SpotlightIndexer.parse(identifier: "song:\(id.uuidString)")
        #expect(song?.kind == "song")
        #expect(song?.id == id)
        let session = SpotlightIndexer.parse(identifier: "session:\(id.uuidString)")
        #expect(session?.kind == "session")
        #expect(SpotlightIndexer.parse(identifier: "media:\(id.uuidString)") == nil)
        #expect(SpotlightIndexer.parse(identifier: "song:not-a-uuid") == nil)
        #expect(SpotlightIndexer.parse(identifier: "garbage") == nil)
    }
}

// MARK: - Bible Reference Parser Tests

struct BibleReferenceParserTests {
    private let books: [BookIndexEntry] = [
        .init(moduleID: UUID(), bookNumber: 43, name: "Ioan", folded: "ioan",
              abbreviationFolded: "in", chapterCount: 21),
        .init(moduleID: UUID(), bookNumber: 62, name: "1 Ioan", folded: "1 ioan",
              abbreviationFolded: "1in", chapterCount: 5),
        .init(moduleID: UUID(), bookNumber: 46, name: "1 Corinteni", folded: "1 corinteni",
              abbreviationFolded: "1cor", chapterCount: 16),
        .init(moduleID: UUID(), bookNumber: 19, name: "Psalmii", folded: "psalmii",
              abbreviationFolded: "ps", chapterCount: 150),
    ]

    @Test func parsesSimpleAndRangedReferences() {
        let simple = BibleReferenceParser.parse("ioan 3:16", books: books)
        #expect(simple == BibleReferenceMatch(bookNumber: 43, bookName: "Ioan",
                                              chapter: 3, verseStart: 16, verseEnd: 16))
        // Space instead of colon + range.
        let range = BibleReferenceParser.parse("1 corinteni 13 4-7", books: books)
        #expect(range?.bookNumber == 46)
        #expect(range?.chapter == 13)
        #expect(range?.verseStart == 4)
        #expect(range?.verseEnd == 7)
        // Chapter only.
        let chapter = BibleReferenceParser.parse("Psalmii 23", books: books)
        #expect(chapter == BibleReferenceMatch(bookNumber: 19, bookName: "Psalmii",
                                               chapter: 23, verseStart: nil, verseEnd: nil))
    }

    @Test func matchesPrefixesAbbreviationsAndLeadingDigits() {
        // Prefix: shortest name wins ("ioan" → Ioan, not 1 Ioan).
        #expect(BibleReferenceParser.parse("ioan 1:1", books: books)?.bookNumber == 43)
        // Leading-digit book.
        #expect(BibleReferenceParser.parse("1 ioan 4:8", books: books)?.bookNumber == 62)
        // Abbreviation.
        #expect(BibleReferenceParser.parse("ps 23:1", books: books)?.bookNumber == 19)
        // Diacritics in the query.
        #expect(BibleReferenceParser.parse("PSALMII 23", books: books)?.bookNumber == 19)
        // Fuzzy word match with leading digit: "1 cor 13".
        #expect(BibleReferenceParser.parse("1 cor 13", books: books)?.bookNumber == 46)
        // Non-references stay nil.
        #expect(BibleReferenceParser.parse("maret esti tu", books: books) == nil)
        // A bare book name now resolves as an OPEN-BOOK reference.
        let bare = BibleReferenceParser.parse("ioan", books: books)
        #expect(bare?.isBookOnly == true)
        #expect(bare?.bookNumber == 43)
    }

    @Test func bareBookNamesAndVerseClamping() {
        // Bare book: name prefix ≥ 3 chars or exact abbreviation, shortest wins.
        #expect(BibleReferenceParser.parse("psal", books: books)
                == BibleReferenceMatch(bookNumber: 19, bookName: "Psalmii", chapter: 1,
                                       verseStart: nil, verseEnd: nil, isBookOnly: true))
        #expect(BibleReferenceParser.parse("1 ioan", books: books)?.isBookOnly == true)
        #expect(BibleReferenceParser.parse("ps", books: books)?.bookNumber == 19)  // exact abbrev
        #expect(BibleReferenceParser.parse("io", books: books) == nil)             // 2-char non-abbrev
        #expect(BibleReferenceParser.parse("xyzzy", books: books) == nil)

        // Verse sanity against indexed per-chapter counts.
        let counted = [BookIndexEntry(moduleID: UUID(), bookNumber: 66, name: "Apocalipsa",
                                      folded: "apocalipsa", abbreviationFolded: "ap",
                                      chapterCount: 22, verseCounts: [22: 21])]
        // Impossible START verse → falls back to a chapter reference.
        let dropped = BibleReferenceParser.parse("apocalipsa 22 420", books: counted)
        #expect(dropped?.chapter == 22)
        #expect(dropped?.verseStart == nil)
        #expect(dropped?.isBookOnly == false)
        // Impossible END verse → clamps to the chapter's last verse.
        let clamped = BibleReferenceParser.parse("apocalipsa 22:15-420", books: counted)
        #expect(clamped?.verseStart == 15)
        #expect(clamped?.verseEnd == 21)
        // Valid verses untouched.
        #expect(BibleReferenceParser.parse("apocalipsa 22:20", books: counted)?.verseEnd == 20)
    }
}

// MARK: - Tab Auto-naming Tests

@MainActor struct TabAutoNamingTests {
    @Test @MainActor func scheduleTabDetailCombinesNameAndDate() {
        // Fixed date: 2026-07-06 (a Monday).
        var comps = DateComponents(); comps.year = 2026; comps.month = 7; comps.day = 6; comps.hour = 12
        let date = Calendar(identifier: .gregorian).date(from: comps)!

        let detail = MainControlView.scheduleTabDetail(name: "Sesiune Duminică", date: date)
        #expect(detail.hasPrefix("Sesiune Duminică – "))
        #expect(detail.contains("6"))   // day number, locale-independent

        // Empty / whitespace name → just the formatted date (no dangling dash).
        let noName = MainControlView.scheduleTabDetail(name: "   ", date: date)
        #expect(!noName.contains("–"))
        #expect(noName.contains("6"))
    }
}

// MARK: - Verse index disk cache (version-switch beachball fix)

struct VerseIndexCacheTests {
    private func sample(moduleID: UUID) -> VerseIndexCache {
        let verses = [
            VerseIndexEntry(moduleID: moduleID, bookNumber: 43, bookName: "Ioan",
                            chapter: 3, verse: 16, text: "Fiindcă atât de mult a iubit Dumnezeu lumea",
                            folded: searchFold("Fiindcă atât de mult a iubit Dumnezeu lumea")),
            VerseIndexEntry(moduleID: moduleID, bookNumber: 43, bookName: "Ioan",
                            chapter: 3, verse: 17, text: "Dumnezeu nu a trimis pe Fiul Său",
                            folded: searchFold("Dumnezeu nu a trimis pe Fiul Său")),
        ]
        let books = [BookIndexEntry(moduleID: moduleID, bookNumber: 43, name: "Ioan",
                                    folded: "ioan", abbreviationFolded: "in",
                                    chapterCount: 21, verseCounts: [3: 36])]
        return VerseIndexCache(moduleID: moduleID, books: books, verses: verses,
                               tokens: TokenIndex.build(blobs: verses.map(\.folded)))
    }

    @Test func roundTripsThroughDisk() throws {
        let moduleID = UUID()
        defer { VerseIndexCache.delete(moduleID: moduleID) }
        let cache = sample(moduleID: moduleID)
        cache.save()

        let loaded = try #require(VerseIndexCache.load(moduleID: moduleID))
        #expect(loaded.moduleID == moduleID)
        #expect(loaded.verses.count == 2)
        #expect(loaded.verses[0].text == cache.verses[0].text)
        #expect(loaded.books[0].verseCounts[3] == 36)
        // The token index survives byte-for-byte: same query → same postings.
        #expect(loaded.tokens.candidates(prefix: "dumnezeu") == cache.tokens.candidates(prefix: "dumnezeu"))
        #expect(loaded.tokens.candidates(prefix: "dumnezeu") == Set([0, 1]))
    }

    @Test func rejectsStaleFormatAndForeignModule() throws {
        let moduleID = UUID()
        defer { VerseIndexCache.delete(moduleID: moduleID) }
        var stale = sample(moduleID: moduleID)
        stale.format = VerseIndexCache.currentFormat + 1
        stale.save()
        // Wrong format version → treated as missing (rebuild, never migrate).
        #expect(VerseIndexCache.load(moduleID: moduleID) == nil)
        // And a module with no file at all → nil.
        #expect(VerseIndexCache.load(moduleID: UUID()) == nil)
    }

    @Test func deleteRemovesTheFile() {
        let moduleID = UUID()
        sample(moduleID: moduleID).save()
        VerseIndexCache.delete(moduleID: moduleID)
        #expect(VerseIndexCache.load(moduleID: moduleID) == nil)
    }
}

// MARK: - ⌘K context-aware section order

struct PaletteSectionOrderTests {
    @Test func bibleContextFloatsVersesAboveSongs() {
        let order = paletteSectionOrder(context: "Bible")
        #expect(order.firstIndex(of: "verses")! < order.firstIndex(of: "songs")!)
        #expect(order.first == "ref")
    }

    @Test func defaultContextKeepsSongsFirst() {
        for context in ["Songs", "Custom Slides", "History", "Settings", "Account", "whatever"] {
            let order = paletteSectionOrder(context: context)
            #expect(order.firstIndex(of: "songs")! < order.firstIndex(of: "verses")!, "\(context)")
            #expect(order.first == "ref", "\(context)")
        }
    }

    @Test func mediaAndScheduleFloatTheirOwnKind() {
        #expect(paletteSectionOrder(context: "Media").dropFirst().first == "media")
        #expect(paletteSectionOrder(context: "Schedule").dropFirst().first == "sessions")
    }

    @Test func everyContextListsAllSixSections() {
        let all = Set(["ref", "songs", "verses", "songContent", "media", "sessions"])
        for context in ["Bible", "Songs", "Media", "Schedule", "Custom Slides", "x"] {
            #expect(Set(paletteSectionOrder(context: context)) == all, "\(context)")
        }
    }
}

// MARK: - ⌘K search history (HistoryStore.SearchEvent)

@MainActor struct SearchHistoryTests {
    private func makeStore() -> HistoryStore { HistoryStore(inMemory: true) }

    @Test func groupsByFoldedQueryNewestFirst() throws {
        let s = makeStore()
        // Same query in three spellings (case + diacritics) + one other query.
        s.recordSearch(query: "marire", resultKind: "abandoned", resultTitle: "", module: "Songs")
        s.recordSearch(query: "Mărire", resultKind: "song", resultTitle: "Mărire Ție", module: "Songs")
        s.recordSearch(query: "MARIRE", resultKind: "song", resultTitle: "Mărire, mărire", module: "Bible")
        s.recordSearch(query: "ioan 3 16", resultKind: "reference", resultTitle: "Ioan 3:16", module: "Bible")

        let sums = s.searchSummaries()
        #expect(sums.count == 2)
        let marire = try #require(sums.first { $0.key == "marire" })
        #expect(marire.count == 3)
        // Last COMMITTED result wins (newest first), abandoned rows don't.
        #expect(marire.lastResultTitle == "Mărire, mărire")
        #expect(marire.lastResultKind == "song")
        #expect(s.totalSearches() == 4)
    }

    @Test func abandonedOnlyGroupHasEmptyResult() throws {
        let s = makeStore()
        s.recordSearch(query: "nimic găsit", resultKind: "abandoned", resultTitle: "", module: "Songs")
        let sum = try #require(s.searchSummaries().first)
        #expect(sum.count == 1)
        #expect(sum.lastResultKind.isEmpty)
        #expect(sum.lastResultTitle.isEmpty)
    }

    @Test func emptyQueriesAreNeverRecorded() {
        let s = makeStore()
        s.recordSearch(query: "   ", resultKind: "song", resultTitle: "X", module: "Songs")
        #expect(s.totalSearches() == 0)
    }

    @Test func clearSearchHistoryLeavesPresentations() {
        let s = makeStore()
        s.record(PresentationEvent(timestamp: .now, sessionID: UUID(), dwellSeconds: 5,
                                   contentType: "song", songKey: "ccli:1", songTitle: "A", verseLabel: "v1"))
        s.recordSearch(query: "test", resultKind: "song", resultTitle: "A", module: "Songs")
        s.clearSearchHistory()
        #expect(s.totalSearches() == 0)
        #expect(s.totalEvents() == 1)

        s.recordSearch(query: "test", resultKind: "song", resultTitle: "A", module: "Songs")
        s.clearAll()
        #expect(s.totalSearches() == 0)
        #expect(s.totalEvents() == 0)
    }
}

// MARK: - Custom Slides v2 — token grammar

struct SlideTemplateTests {
    @Test func parsesLiteralsAndTokens() {
        let segs = SlideTemplate.parse("Azi: {{date}} — {{bible:Ioan 3:16#ref|VDC}}!")
        #expect(segs.count == 5)
        #expect(segs[0] == .literal("Azi: "))
        #expect(segs[1] == .token(SlideToken(scheme: "date", argument: "", field: "", option: "")))
        #expect(segs[2] == .literal(" — "))
        #expect(segs[3] == .token(SlideToken(scheme: "bible", argument: "Ioan 3:16",
                                             field: "ref", option: "VDC")))
        #expect(segs[4] == .literal("!"))
    }

    @Test func optionOnArgumentAndOnField() {
        // |option directly on the argument…
        let a = SlideTemplate.parse("{{bible:Psalmi 23|KJV}}")
        #expect(a == [.token(SlideToken(scheme: "bible", argument: "Psalmi 23", field: "", option: "KJV"))])
        // …and after the field — both accepted.
        let b = SlideTemplate.parse("{{bible:Psalmi 23#full|KJV}}")
        #expect(b == [.token(SlideToken(scheme: "bible", argument: "Psalmi 23", field: "full", option: "KJV"))])
    }

    @Test func escapesAndMalformedStayLiteral() {
        #expect(SlideTemplate.parse("a {{{{ b") == [.literal("a {{ b")])
        #expect(SlideTemplate.parse("open {{bible:Ioan") == [.literal("open {{bible:Ioan")])
        #expect(SlideTemplate.parse("{{}}") == [.literal("{{}}")])
        #expect(SlideTemplate.parse("{{123:x}}") == [.literal("{{123:x}}")])
    }

    @Test func countsTokens() {
        #expect(SlideTemplate.tokenCount("{{date}} și {{time}}") == 2)
        #expect(SlideTemplate.containsTokens("text simplu") == false)
        #expect(SlideTemplate.containsTokens("{{song:Nume}}") == true)
    }
}

// MARK: - Custom Slides v2 — providers (pure paths)

struct SlideProviderTests {
    private func verse(_ chapter: Int, _ v: Int, _ text: String) -> VerseIndexEntry {
        VerseIndexEntry(moduleID: UUID(), bookNumber: 43, bookName: "Ioan",
                        chapter: chapter, verse: v, text: text, folded: searchFold(text))
    }
    private var books: [BookIndexEntry] {
        [BookIndexEntry(moduleID: UUID(), bookNumber: 43, name: "Ioan", folded: "ioan",
                        abbreviationFolded: "in", chapterCount: 21, verseCounts: [3: 36])]
    }

    @Test func bibleTokenResolvesTextRefAndFull() {
        let verses = [verse(3, 16, "Fiindcă atât de mult a iubit Dumnezeu lumea"),
                      verse(3, 17, "Dumnezeu nu a trimis pe Fiul Său să judece")]
        #expect(BibleTokenProvider.resolve(reference: "Ioan 3:16", field: "",
                                           books: books, verses: verses)
                == "Fiindcă atât de mult a iubit Dumnezeu lumea")
        #expect(BibleTokenProvider.resolve(reference: "Ioan 3:16-17", field: "ref",
                                           books: books, verses: verses)
                == "Ioan 3:16-17")
        let full = BibleTokenProvider.resolve(reference: "Ioan 3:16-17", field: "full",
                                              books: books, verses: verses)
        #expect(full?.contains("(16)") == true)
        #expect(full?.hasSuffix("— Ioan 3:16-17") == true)
        #expect(BibleTokenProvider.resolve(reference: "Nimicul 9:9", field: "",
                                           books: books, verses: verses) == nil)
    }

    @Test func songProjectionFields() {
        let entry = SongIndexEntry(id: UUID(), title: "Ce mare ești Tu", author: "Stuart Hine",
                                   language: "ro", songNumber: "27", songbookName: "Cântările Evangheliei",
                                   collectionID: nil, collectionName: "", versionCount: 1,
                                   hasMedia: false, verified: true, modifiedDate: .now,
                                   firstLine: "O, Doamne mare, când privesc eu lumea",
                                   blob: "", songKey: "x")
        #expect(SongTokenProvider.projectionField("", entry: entry) == "O, Doamne mare, când privesc eu lumea")
        #expect(SongTokenProvider.projectionField("title", entry: entry) == "Ce mare ești Tu")
        #expect(SongTokenProvider.projectionField("author", entry: entry) == "Stuart Hine")
        #expect(SongTokenProvider.projectionField("book", entry: entry) == "Cântările Evangheliei")
        #expect(SongTokenProvider.projectionField("number", entry: entry) == "27")
        #expect(SongTokenProvider.projectionField("ccli", entry: entry) == nil)   // model fetch
    }

    @Test func dateFormatsDeterministically() {
        var comps = DateComponents(); comps.year = 2026; comps.month = 7; comps.day = 19; comps.hour = 10; comps.minute = 30
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let ro = Locale(identifier: "ro_RO")
        #expect(DateTokenProvider.format(date, pattern: "dd.MM.yyyy", locale: ro) == "19.07.2026")
        #expect(DateTokenProvider.format(date, pattern: "EEEE", locale: ro).lowercased() == "duminică")
        #expect(DateTokenProvider.format(date, pattern: "", locale: ro).contains("2026"))
        #expect(TimeTokenProvider.format(date, pattern: "HH:mm", locale: ro) == "10:30")
    }
}

// MARK: - Custom Slides v2 — remote extraction (pure)

struct RemoteExtractionTests {
    @Test func jsonKeypathWalksDictsAndArrays() {
        let json = #"{"items":[{"title":"Primul","views":12},{"title":"Al doilea"}],"ok":true}"#.data(using: .utf8)!
        #expect(RemoteContentService.extractJSON(json, keypath: "items.0.title") == "Primul")
        #expect(RemoteContentService.extractJSON(json, keypath: "items.1.title") == "Al doilea")
        #expect(RemoteContentService.extractJSON(json, keypath: "items.0.views") == "12")
        #expect(RemoteContentService.extractJSON(json, keypath: "items.9.title") == nil)
        #expect(RemoteContentService.extractJSON(json, keypath: "missing") == nil)
        // Container leaves are not slide text; scalar fragments are.
        #expect(RemoteContentService.extractJSON(json, keypath: "items") == nil)
        #expect(RemoteContentService.extractJSON(#""doar text""#.data(using: .utf8)!, keypath: "") == "doar text")
    }

    @Test func rssAndAtomItemsParse() {
        let rss = """
        <?xml version="1.0"?><rss version="2.0"><channel><title>Canal</title>
        <item><title>Știrea unu</title><description><![CDATA[Detalii unu]]></description>\
        <pubDate>Sun, 19 Jul 2026 08:00:00 +0000</pubDate></item>
        <item><title>Știrea doi</title><description>Detalii doi</description></item>
        </channel></rss>
        """.data(using: .utf8)!
        let items = RemoteContentService.parseFeedItems(rss)
        #expect(items.count == 2)
        #expect(RemoteContentService.rssField(items: items, field: "") == "Știrea unu")
        #expect(RemoteContentService.rssField(items: items, field: "0.description") == "Detalii unu")
        #expect(RemoteContentService.rssField(items: items, field: "1.title") == "Știrea doi")
        #expect(RemoteContentService.rssField(items: items, field: "0.date")?.contains("2026") == true)
        #expect(RemoteContentService.rssField(items: items, field: "5.title") == nil)

        let atom = """
        <?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">
        <title>Feed</title><entry><title>Intrare Atom</title><summary>Rezumat</summary>\
        <updated>2026-07-19T08:00:00Z</updated></entry></feed>
        """.data(using: .utf8)!
        let entries = RemoteContentService.parseFeedItems(atom)
        #expect(entries.count == 1)
        #expect(RemoteContentService.rssField(items: entries, field: "0.title") == "Intrare Atom")
        #expect(RemoteContentService.rssField(items: entries, field: "0.description") == "Rezumat")
    }
}
