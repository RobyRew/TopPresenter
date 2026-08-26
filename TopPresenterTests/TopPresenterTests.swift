//
//  TopPresenterTests.swift
//  TopPresenterTests
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Testing
import Foundation
import UniformTypeIdentifiers
import Compression
import SwiftUI
import SwiftData
@testable import TopPresenter

/// A `PresentationManager` on a throwaway settings suite.
///
/// The test host runs inside the real app bundle, so a plain
/// `makeTestManager()` read AND wrote the operator's actual saved layouts,
/// themes and settings. That corrupted real data on every run, and left tests
/// depending on whatever the previous run happened to leave behind. Each manager
/// now gets its own empty domain and therefore its own clean defaults.
/// A manager with NO output window, which is what a test almost always wants.
///
/// The window lookup inside `PresentationManager` is process-global, so before
/// this every test manager drove the test HOST's real presentation window. Tests
/// that hide it (to exercise the staged-show path) then changed the behaviour of
/// every test running in parallel: `presentContent` defers its apply by 60 ms
/// when the window exists and is hidden, so an assertion made right after a show
/// read stale content. `liveContentCarriesVerseRuns` failed about one run in
/// five that way, and nothing in its body hinted why.
///
/// Headless also means `presentContent` always takes its immediate path, so a
/// test can assert on `liveContent` the moment it returns.
@MainActor func makeTestManager(_ store: UserDefaults? = nil) -> PresentationManager {
    PresentationManager(defaults: store ?? makeTestDefaults(), presentationWindowSource: { [] })
}

/// A manager wired to a presentation window this test OWNS, for the two tests
/// that are about staging itself. It starts hidden, which is the condition that
/// makes `presentContent` stage.
///
/// Owning the window is the point: the staging tests used to borrow the host
/// app's, which is what leaked staging into everyone else's tests.
@MainActor func makeStagingTestManager() -> (PresentationManager, NSWindow) {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
                          styleMask: [.borderless], backing: .buffered, defer: true)
    window.isReleasedWhenClosed = false
    window.identifier = NSUserInterfaceItemIdentifier(WindowIdentifiers.presentation)
    let manager = PresentationManager(defaults: makeTestDefaults(),
                                      presentationWindowSource: { [window] })
    return (manager, window)
}

/// An empty settings domain. Pass the SAME one to two managers to test that a
/// setting survives a relaunch — that is the only reason to share a store.
@MainActor func makeTestDefaults() -> UserDefaults {
    // Force-unwrap is right here: a suite name that isn't a reserved domain
    // always succeeds, and a nil would silently hand back .standard.
    UserDefaults(suiteName: "TopPresenterTests-" + UUID().uuidString)!
}

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

        try writeBible(lang1.appendingPathComponent("A.tpbible"))
        try writeBible(lang1.appendingPathComponent("B.tpbible"))
        try writeBible(lang2deep.appendingPathComponent("C.tpbible"))  // nested subfolder
        try "not a bible".data(using: .utf8)!.write(to: root.appendingPathComponent("readme.txt"))
        // Four levels down. This used to be silently ignored: the walk stopped
        // at three, which any real library tree exceeds. It is found now, and
        // what stops a runaway scan is the budget — which SAYS that it stopped.
        let deeper = root.appendingPathComponent("English/extra/way")
        try fm.createDirectory(at: deeper, withIntermediateDirectories: true)
        try writeBible(deeper.appendingPathComponent("D.tpbible"))

        let scan = ImportScanner.scan([root])
        #expect(scan.files.filter { $0.pathExtension == "tpbible" }.count == 4)
        #expect(scan.files.contains { $0.lastPathComponent == "D.tpbible" })
        #expect(!scan.wasTruncated, "nothing here comes close to the budget")

        let pending = DragDropImportHandler.classifyExpanded([root])
        let bibles = pending.filter { if case .bible = $0.category { return true }; return false }
        #expect(bibles.count == 4)
    }

    /// The budget replaces the depth cap, and the difference that matters is
    /// that it reports itself. A scan that quietly returns half a folder is how
    /// "I imported it and songs are missing" happens.
    @Test func exceedingTheDepthBudgetIsReportedRatherThanSilent() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tp_deep_\(UUID().uuidString)")
        let deep = root.appendingPathComponent(Array(repeating: "n", count: 10).joined(separator: "/"))
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        try writeBible(deep.appendingPathComponent("TooDeep.tpbible"))
        defer { try? fm.removeItem(at: root) }

        let scan = ImportScanner.scan([root])
        #expect(scan.files.isEmpty)
        #expect(scan.truncations.contains(.depth(8)))
        #expect(scan.truncations.first?.message.isEmpty == false,
                "the truncation has to be sayable to the operator, not just detectable")
    }

    @Test func theCandidateBudgetStopsAndSaysSo() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("tp_many_\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        for index in 0..<25 { try writeBible(root.appendingPathComponent("b\(index).tpbible")) }

        var budget = ImportScanner.Budget.default
        budget.maxCandidates = 10
        let scan = ImportScanner.scan([root], budget: budget)
        #expect(scan.files.count == 10)
        #expect(scan.truncations.contains(.candidates(10)))
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
        pm.fontSize = 72.0
        pm.toggleFreeze()
        pm.fontSize = 48.0

        pm.toggleFreeze() // unfreeze

        #expect(pm.isFrozen == false)
        #expect(pm.outputFontSize == 48.0)
    }

    @Test func clearOutputResetsFreezeAndBlack() {
        let pm = makeTestManager()
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

    // MARK: - Language

    @Test func languageOverrideWritesApplePreferredLanguages() {
        let d = UserDefaults.standard
        let savedSetting = d.string(forKey: AppLanguage.settingKey)
        let savedApple = d.array(forKey: AppLanguage.overrideKey)
        defer {
            if let s = savedSetting { d.set(s, forKey: AppLanguage.settingKey) }
            else { d.removeObject(forKey: AppLanguage.settingKey) }
            if let a = savedApple { d.set(a, forKey: AppLanguage.overrideKey) }
            else { d.removeObject(forKey: AppLanguage.overrideKey) }
        }

        AppLanguage.apply(.system)
        AppLanguage.apply(.fr)
        #expect(AppLanguage.current == .fr)
        // AppleLanguages is a GLOBAL key: reading it back returns the resolved
        // preferred-language list, not the array verbatim. What matters is that
        // our override sits at the front of it.
        let preferred = d.array(forKey: AppLanguage.overrideKey) as? [String] ?? []
        #expect(preferred.first?.hasPrefix("fr") == true)

        AppLanguage.apply(.system)                      // back to following macOS
        #expect(AppLanguage.current == .system)
        #expect(d.object(forKey: AppLanguage.overrideKey) == nil ||
                (d.array(forKey: AppLanguage.overrideKey) as? [String])?.first?.hasPrefix("fr") == false)
    }

    /// The regression that shipped: the Settings picker is bound to `settingKey`
    /// through `@AppStorage`, which writes it BEFORE `.onChange` runs. `apply`
    /// used to bail when the requested language already matched the stored one,
    /// so in the real UI it matched every single time and macOS was never told
    /// anything. The setting looked applied and nothing changed, restart or not.
    @Test func applyWritesEvenWhenTheStoredSettingIsAlreadyUpToDate() {
        let d = UserDefaults.standard
        let savedSetting = d.string(forKey: AppLanguage.settingKey)
        let savedApple = d.array(forKey: AppLanguage.overrideKey)
        defer {
            if let s = savedSetting { d.set(s, forKey: AppLanguage.settingKey) }
            else { d.removeObject(forKey: AppLanguage.settingKey) }
            if let a = savedApple { d.set(a, forKey: AppLanguage.overrideKey) }
            else { d.removeObject(forKey: AppLanguage.overrideKey) }
        }

        d.removeObject(forKey: AppLanguage.overrideKey)
        // Exactly what @AppStorage does the instant the picker changes:
        d.set(AppLanguage.de.rawValue, forKey: AppLanguage.settingKey)
        #expect(AppLanguage.current == .de)   // stored setting already agrees

        AppLanguage.apply(.de)                // …and apply must STILL write through

        let preferred = d.array(forKey: AppLanguage.overrideKey) as? [String] ?? []
        #expect(preferred.first?.hasPrefix("de") == true)
    }

    /// Anyone who used the broken build has a stored language and no
    /// AppleLanguages entry. Re-picking the same value in the picker fires no
    /// change event, so launching must repair it or they stay stuck forever.
    @Test func launchRepairsAChoiceThatNeverReachedMacOS() {
        let d = UserDefaults.standard
        let savedSetting = d.string(forKey: AppLanguage.settingKey)
        let savedApple = d.array(forKey: AppLanguage.overrideKey)
        defer {
            if let s = savedSetting { d.set(s, forKey: AppLanguage.settingKey) }
            else { d.removeObject(forKey: AppLanguage.settingKey) }
            if let a = savedApple { d.set(a, forKey: AppLanguage.overrideKey) }
            else { d.removeObject(forKey: AppLanguage.overrideKey) }
        }

        // Exactly the state found on the reporter's machine.
        d.set(AppLanguage.de.rawValue, forKey: AppLanguage.settingKey)
        d.removeObject(forKey: AppLanguage.overrideKey)

        AppLanguage.captureLaunchState()

        let preferred = d.array(forKey: AppLanguage.overrideKey) as? [String] ?? []
        #expect(preferred.first?.hasPrefix("de") == true)
    }

    /// Proves the catalog actually SHIPS usable resources: an unmatched or empty
    /// catalog emits no .lproj at all and every build stays green regardless.
    @Test func translatedResourcesResolveAtRuntime() throws {
        for (code, key, expected) in [
            ("es", "Clear Output", "Limpiar salida"),
            ("fr", "Clear Output", "Effacer la sortie"),
            ("de", "Black Screen", "Schwarzbild"),
            ("ru", "Delete", "Удалить"),
            ("ro", "Freeze", "Îngheață"),
            ("en", "Editor de Teme…", "Theme Editor…"),   // Romanian key, English override
            // The regression this guards against: adding an English override to a
            // Romanian-authored key must NOT make Romanian fall through to it. With
            // no `ro` entry the lookup has to return the key itself — the Romanian
            // source — not the English translation.
            ("ro", "Editor de Teme…", "Editor de Teme…"),
            ("ro", "%lld capitole", "%lld capitole"),
        ] {
            let path = try #require(Bundle.main.path(forResource: code, ofType: "lproj"),
                                    "missing \(code).lproj")
            let bundle = try #require(Bundle(path: path))
            #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
        }
    }

    // MARK: - A staged show must never overwrite a newer one

    /// `orderFront` makes the window visible synchronously, so a second Show right
    /// after a staged one takes the immediate path and lands FIRST. Without a
    /// generation token the staged apply then overwrites the projector with stale
    /// content 60 ms after the operator already moved on.
    /// The whole suite leans on this. A test manager that can see the host app's
    /// output window takes `presentContent`'s staged path whenever that window
    /// happens to be hidden, applying content 60 ms LATE — so any test asserting
    /// right after a show reads stale content, intermittently, depending on what
    /// else is running in parallel. That is exactly how
    /// `liveContentCarriesVerseRuns` failed about one run in five.
    @Test func atestManagerIsHeadlessSoEveryShowAppliesImmediately() {
        let pm = makeTestManager()
        #expect(pm.hasPresentationWindow == false,
                "makeTestManager is seeing a real window — presentContent will stage, and shows will land 60 ms late")
        pm.showBibleVerse(text: "Imediat", reference: "Gen 1:1")
        #expect(pm.hasStagedShow == false)
        #expect(pm.liveContent.mainText == "Imediat",
                "the show was deferred instead of applied")
    }

    @Test func newerShowSupersedesAStagedOne() async {
        // This one is ABOUT staging, so it owns a window instead of borrowing the
        // host's — which is what used to leak the staged path into every test
        // running alongside it. Hidden window ⇒ `presentContent` stages.
        let (pm, window) = makeStagingTestManager()
        defer { window.orderOut(nil); window.close() }
        #expect(pm.hasPresentationWindow, "the staged path needs a window to stage for")

        pm.showBibleVerse(text: "Verset A", reference: "Gen 1:1")
        #expect(pm.hasStagedShow)
        pm.showBibleVerse(text: "Verset B", reference: "Gen 1:2")

        try? await Task.sleep(for: .milliseconds(200))
        #expect(pm.liveContent.mainText == "Verset B")   // A must not come back

        pm.clearOutput()
    }

    /// Same hazard in the other direction: Show while hidden, then Escape.
    @Test func clearCancelsAStagedShow() async {
        let (pm, window) = makeStagingTestManager()
        defer { window.orderOut(nil); window.close() }
        #expect(pm.hasPresentationWindow, "the staged path needs a window to stage for")

        pm.showBibleVerse(text: "Verset A", reference: "Gen 1:1")
        #expect(pm.hasStagedShow)
        pm.clearOutput()
        #expect(pm.hasStagedShow == false)   // dropped outright, not left to no-op

        try? await Task.sleep(for: .milliseconds(200))
        #expect(pm.liveContent.isLive == false)
        #expect(pm.liveContent.mainText == "")
    }

    // MARK: - Screen changes must never lock the operator out

    @Test func askOnDisconnectParksOutputWithoutRetargeting() {
        let pm = makeTestManager()
        pm.screenDisconnectAction = .ask
        pm.isPresentationWindowOpen = true
        pm.presentationScreenIndex = 99  // target display no longer exists

        pm.handleScreenConfigurationChange()

        #expect(pm.showScreenDisconnectedAlert == true)
        #expect(pm.pendingScreenChange == .disconnected)
        #expect(pm.pendingConnectedScreenIndex == nil)
        // Regression: the output used to be moved onto the operator's remaining
        // display BEFORE asking, burying the app — and this very prompt — under a
        // full-screen always-on-top overlay.
        #expect(pm.presentationScreenIndex == 99)

    }

    @Test func goBlackOnDisconnectActsWithoutPrompting() {
        let pm = makeTestManager()
        pm.screenDisconnectAction = .goBlack
        pm.isPresentationWindowOpen = true
        pm.presentationScreenIndex = 99

        pm.handleScreenConfigurationChange()

        #expect(pm.isBlackScreen == true)
        #expect(pm.showScreenDisconnectedAlert == false)

        pm.screenDisconnectAction = .ask  // restore the persisted default
    }

    @Test func screenChangeIsSilentWhenOutputWindowClosed() {
        let pm = makeTestManager()
        pm.screenDisconnectAction = .ask
        pm.isPresentationWindowOpen = false
        pm.presentationScreenIndex = 99

        pm.handleScreenConfigurationChange()

        #expect(pm.showScreenDisconnectedAlert == false)
    }

    /// It used to be a computed property over UserDefaults — the only one of the
    /// 34 persisted settings that was, which also kept it outside Observation.
    @Test func screenDisconnectActionPersistsLikeItsSiblings() {
        // One store, two managers — the point is that the second one reads back
        // what the first one wrote, exactly as a relaunch would.
        let store = makeTestDefaults()
        let pm = makeTestManager(store)

        pm.screenDisconnectAction = .goBlack
        // A fresh instance restores it in init(), like every other didSet setting.
        #expect(makeTestManager(store).screenDisconnectAction == .goBlack)

        pm.screenDisconnectAction = .moveToAvailable
        #expect(makeTestManager(store).screenDisconnectAction == .moveToAvailable)
    }

    @Test func pendingScreenMoveIgnoresMissingTarget() {
        let pm = makeTestManager()
        pm.presentationScreenIndex = 0

        pm.pendingConnectedScreenIndex = nil
        pm.movePresentationToPendingScreen()
        #expect(pm.presentationScreenIndex == 0)

        pm.pendingConnectedScreenIndex = 999  // out of range
        pm.movePresentationToPendingScreen()
        #expect(pm.presentationScreenIndex == 0)
    }

    /// A single display always means the output is sitting on the operator's own
    /// screen — that is what makes Escape/⌘⎋ hide it instead of leaving it up.
    @Test func singleDisplayImpliesOutputCoversOperator() {
        let pm = makeTestManager()
        #expect(!pm.isSingleScreenMode || pm.isOutputOnOperatorScreen)
    }

    @Test func hideOutputNowKeepsLiveContentIntact() {
        let pm = makeTestManager()
        pm.liveContent.setBibleVerse(text: "Test", reference: "Gen 1:1")
        pm.liveContent.isLive = true

        pm.hideOutputNow()

        // The panic hatch gives the screen back; it does not end the presentation,
        // so the next Show resumes exactly where the operator left off.
        #expect(pm.liveContent.isLive == true)
        #expect(pm.liveContent.mainText == "Test")

    }

    @Test func showBibleVerseBlockedWhenFrozen() {
        let pm = makeTestManager()
        pm.liveContent.setBibleVerse(text: "First verse", reference: "Gen 1:1")
        pm.toggleFreeze()

        pm.showBibleVerse(text: "Second verse", reference: "Gen 1:2")

        // Should still show the first verse since it's frozen
        #expect(pm.liveContent.mainText == "First verse")
    }

    @Test func toggleBlack() {
        let pm = makeTestManager()
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
        let pm = makeTestManager()
        let original = pm.boxFrame(for: .verseContent, in: "bible")
        pm.setBoxFrame(.init(x: 0.95, y: 0.1, width: 0.3, height: 0.2), for: .verseContent, in: "bible")
        defer { pm.setBoxFrame(original, for: .verseContent, in: "bible") }

        // x clamped so the box stays fully on screen
        let frame = pm.boxFrame(for: .verseContent, in: "bible")
        #expect(frame.x + frame.width <= 1.0)

        // Profiles persist as ONE blob, written debounced — flush first, exactly as
        // the editor does at the end of a drag.
        pm.persistProfilesNow()
        let data = try #require(pm.defaults.data(forKey: "pm_layoutProfiles"))
        let profiles = try JSONDecoder().decode(
            [String: PresentationManager.LayoutProfile].self, from: data
        )
        #expect(profiles["bible"]?.frames[TextBoxSection.verseContent.rawValue] == frame)
    }

    /// The debounce must never cost an edit: the write is deferred, but a flush
    /// point (gesture end, app quit/deactivate) commits it immediately.
    @Test func debouncedProfileWriteIsFlushedOnDemand() throws {
        let pm = makeTestManager()
        let original = pm.boxFrame(for: .verseContent, in: "song")
        defer { pm.setBoxFrame(original, for: .verseContent, in: "song"); pm.persistProfilesNow() }

        pm.setBoxFrame(.init(x: 0.11, y: 0.22, width: 0.33, height: 0.15), for: .verseContent, in: "song")
        pm.persistProfilesNow()

        let data = try #require(pm.defaults.data(forKey: "pm_layoutProfiles"))
        let profiles = try JSONDecoder().decode(
            [String: PresentationManager.LayoutProfile].self, from: data
        )
        #expect(profiles["song"]?.frames[TextBoxSection.verseContent.rawValue]
                == pm.boxFrame(for: .verseContent, in: "song"))
    }

    /// Two auto-fit boxes on screen must both stay cached. As a single slot the
    /// cache thrashed: each call missed and overwrote the other's entry.
    @Test func autoFitCacheServesSeveralBoxesAtOnce() {
        let pm = makeTestManager()
        let wasEnabled = pm.autoFitVerseFont
        pm.autoFitVerseFont = true
        defer { pm.autoFitVerseFont = wasEnabled }

        let long = String(repeating: "Cuvântul Domnului rămâne în veac. ", count: 12)
        let short = "Ioan 3:16"
        let bigBox = CGSize(width: 900, height: 300)
        let smallBox = CGSize(width: 300, height: 90)

        let a1 = pm.fittedVerseFontSize(text: long, boxSize: bigBox, maxSize: 96, padding: 12,
                                        fontName: "Helvetica", lineSpacing: 1.0)
        let b1 = pm.fittedVerseFontSize(text: short, boxSize: smallBox, maxSize: 48, padding: 8,
                                        fontName: "Helvetica", lineSpacing: 1.0)
        // Interleave again — with a one-slot cache these would both be recomputed.
        let a2 = pm.fittedVerseFontSize(text: long, boxSize: bigBox, maxSize: 96, padding: 12,
                                        fontName: "Helvetica", lineSpacing: 1.0)
        let b2 = pm.fittedVerseFontSize(text: short, boxSize: smallBox, maxSize: 48, padding: 8,
                                        fontName: "Helvetica", lineSpacing: 1.0)

        #expect(a1 == a2)
        #expect(b1 == b2)
        #expect(a1 <= 96)
        #expect(b1 <= 48)
    }

    @Test func profilesAreIndependentPerPresenter() {
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
        pm.clearOutput()
        pm.showSongVerse(text: "v1", title: "T", verseLabel: "S1", slideIndex: 0, slideCount: 2)
        #expect(pm.contentChangeKind == "appear")
        pm.showSongVerse(text: "v2", title: "T", verseLabel: "S2", slideIndex: 1, slideCount: 2)
        #expect(pm.contentChangeKind == "change")
        pm.clearOutput()
        #expect(pm.contentChangeKind == "clear")
    }

    @Test func boxTransitionOverrideIsPerTokenAndProfile() {
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
        pm.setBoxFrame(.init(x: 0.2, y: 0.2, width: 0.4, height: 0.3), for: .reference)

        pm.resetAllBoxFrames()

        #expect(pm.refBoxFrame == .defaultReference)
        #expect(pm.verseBoxFrame == .defaultVerse)
    }

    @Test func fittedFontSizeNeverExceedsConfiguredSize() {
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let m1 = try await ImportService.importBible(fileURL: try write(v1, "dup1.json"), format: .topPresenter, modelContext: ctx, resolution: .keepBoth).module
        #expect(m1.books.first?.chapters.count == 2)

        // Second import (same code) supplying the missing chapter 7 → MERGE.
        let v2: [String: Any] = ["format": "TopPresenter Bible", "translation": ["code": "DUP", "name": "Dup"],
            "books": [["number": 27, "name": "Daniel", "testament": "OT", "chapters": [
                ["number": 6, "verses": [["number": 1, "text": "SIX-overwrite-attempt"]]],
                ["number": 7, "verses": [["number": 1, "text": "seven"]]]]]]]
        let merged = try await ImportService.importBible(fileURL: try write(v2, "dup2.json"), format: .topPresenter, modelContext: ctx, resolution: .merge).module

        #expect(merged.id == m1.id)                                          // merged INTO existing
        let daniel = try #require(merged.books.first)
        #expect(Set(daniel.chapters.map { $0.chapterNumber }) == [6, 7, 8])  // 7 filled in
        let ch6 = try #require(daniel.chapters.first { $0.chapterNumber == 6 })
        #expect(ch6.verses.first?.text == "six")                             // existing verse kept
        let mods = try ctx.fetch(FetchDescriptor<BibleModule>())
        #expect(mods.filter { $0.abbreviation == "DUP" }.count == 1)         // no duplicate module
    }

    /// A conflict is "you have something else under this name", not "you have
    /// this". Re-importing the identical file used to raise the dialog too,
    /// which is a question with no useful answer: every option does nothing.
    @Test func duplicateImportAskThrowsConflictOnlyWhenTheContentDiffers() async throws {
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
        let original: [String: Any] = ["format": "TopPresenter Bible", "translation": ["code": "ASK", "name": "Ask"],
            "books": [["number": 1, "name": "Genesis", "testament": "OT",
                       "chapters": [["number": 1, "verses": [["number": 1, "text": "x"]]]]]]]
        let u = try write(original, "ask.json")
        _ = try await ImportService.importBible(fileURL: u, format: .topPresenter, modelContext: ctx, resolution: .keepBoth)

        // The SAME file again: not a conflict, and not a second module.
        let again = try await ImportService.importBible(fileURL: u, format: .topPresenter,
                                                        modelContext: ctx, resolution: .ask)
        #expect(again.action == .skippedDuplicate(matchedOn: "abbreviation ASK and language en"))
        #expect(try ctx.fetch(FetchDescriptor<BibleModule>()).count == 1)

        // A DIFFERENT edition under the same code is what the dialog is for.
        let revised: [String: Any] = ["format": "TopPresenter Bible", "translation": ["code": "ASK", "name": "Ask"],
            "books": [["number": 1, "name": "Genesis", "testament": "OT",
                       "chapters": [["number": 1, "verses": [["number": 1, "text": "x"],
                                                             ["number": 2, "text": "y"]]]]]]]
        await #expect(throws: ImportService.BibleConflict.self) {
            _ = try await ImportService.importBible(fileURL: try write(revised, "ask2.json"),
                                                    format: .topPresenter, modelContext: ctx, resolution: .ask)
        }
    }

    @Test func liveContentCarriesVerseRuns() {
        let pm = makeTestManager()
        pm.showBibleVerse(text: "I am the light.", reference: "John 8:12",
                          runs: [VerseRun(text: "I am the light.", kind: "woc")])
        #expect(pm.liveContent.mainRuns.contains { $0.kind == "woc" })
        // A song clears the runs.
        pm.showSongVerse(text: "la la", title: "T", verseLabel: "S1")
        #expect(pm.liveContent.mainRuns.isEmpty)
        pm.clearOutput()
    }

    @Test func perBoxPaddingShadowAutoFitResolve() {
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let pm = makeTestManager()
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
        let gm = try await ImportService.importBible(fileURL: try write(greek, "lang_gr.json"), format: .topPresenter, modelContext: ctx, resolution: .keepBoth).module
        #expect(gm.language == "gr")
        #expect(gm.languageName == "Ελληνικά")

        // A genuinely Romanian module keeps "ro".
        let ro: [String: Any] = ["format": "TopPresenter Bible",
            "translation": ["code": "VDC", "name": "Cornilescu", "language": "ro"],
            "books": [["number": 64, "name": "3 Ioan", "testament": "NT", "chapters": [
                ["number": 1, "verses": [["number": 1, "text": "Bătrânul, către preaiubitul Gaiu, pe care îl iubesc în adevăr"]]]]]]]
        let rm = try await ImportService.importBible(fileURL: try write(ro, "lang_ro.json"), format: .topPresenter, modelContext: ctx, resolution: .keepBoth).module
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
        // Compare against the SAME localized strings the code produces — asserting
        // the Romanian wording made these tests fail the moment English shipped.
        #expect(s.contains(String(localized: "Titlu modificat", comment: "Edit log")))
        #expect(s.contains(String(localized: "Marcat verificat", comment: "Edit log")))
        // The section labels are DATA, so they stay verbatim in every language.
        #expect(s.contains { $0.contains("Strofa 1") })
        #expect(s.contains { $0.contains("Refren") })
        #expect(s.count == 4)

        // No changes → no entries.
        #expect(ImportService.summarizeChanges(old: old, new: old).isEmpty)
    }

    @Test func deletedSectionIsReported() {
        let v1 = SongImportSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [SongLine(text: "a")])
        let chorus = SongImportSection(sectionKey: "c", type: "chorus", label: "Refren", order: 1, lines: [SongLine(text: "r")])
        let old = result(title: "C", sections: [v1, chorus])
        let new = result(title: "C", sections: [v1])
        let s = ImportService.summarizeChanges(old: old, new: new)
        // Build the expectation through the SAME interpolated key the code uses
        // («%@» șters). A literal "«Refren» șters" is a different key entirely —
        // untranslated, so it would resolve to Romanian while the code returns
        // the localized form.
        let label = "Refren"
        #expect(s == [String(localized: "«\(label)» șters", comment: "Edit log")])
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

    /// The runner's actual job — dispatching to the live output — had no coverage:
    /// the test above deliberately leaves `pm` unwired and only checks index math.
    @Test func runnerWiredToPresentationManagerPutsTextOnTheOutput() throws {
        let context = try makeInMemoryContext()
        let schedule = SessionService.createSession(name: "Flux", context: context)
        SessionService.append(.text(title: "Bun venit", content: "Salut"), to: schedule, context: context)
        SessionService.append(.text(title: "Încheiere", content: "Amin"), to: schedule, context: context)
        try context.save()

        let pm = makeTestManager()
        let runner = SessionRunner()
        runner.pm = pm

        runner.start(schedule, context: context)
        #expect(pm.liveContent.mainText == "Salut")
        #expect(pm.liveContent.isLive)
        // Plain text carries no tokens, so nothing is resolved asynchronously.
        #expect(runner.isResolvingSlide == false)

        runner.next(context: context)
        #expect(pm.liveContent.mainText == "Amin")

        runner.stop()
        #expect(runner.isResolvingSlide == false)
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

// MARK: - Custom slide search
//
// The one library list that had no search at all. It searches more than the
// title because a slide is often "Untitled" until someone names it, and the
// thing the operator remembers is the text on it.

@MainActor struct CustomSlideSearchTests {

    private func slides() -> [PresentationSlide] {
        [
            PresentationSlide(title: "Anunțuri", content: "Vă așteptăm duminică"),
            PresentationSlide(title: "Untitled", content: "Bine ați venit!", subtitle: "Intro"),
            PresentationSlide(title: "Verset", content: "{bible:Ioan 3:16}"),
        ]
    }

    @Test func anEmptyQueryKeepsEverythingInOrder() {
        let all = slides()
        #expect(CustomSlideLibrary.filter(all, query: "").map(\.id) == all.map(\.id))
        // Whitespace is not a search — trimming keeps a stray space from
        // emptying the list.
        #expect(CustomSlideLibrary.filter(all, query: "   ").map(\.id) == all.map(\.id))
    }

    @Test func itMatchesWithoutDiacritics() {
        // The operator's keyboard layout may have no ț — typing "anunturi" must
        // still find „Anunțuri", or the search is worse than scrolling.
        let all = slides()
        #expect(CustomSlideLibrary.filter(all, query: "anunturi").map(\.title) == ["Anunțuri"])
        #expect(CustomSlideLibrary.filter(all, query: "ANUNȚURI").map(\.title) == ["Anunțuri"])
    }

    @Test func itSearchesBodyAndSubtitleNotJustTheTitle() {
        let all = slides()
        // "Untitled" is findable only by what it says.
        #expect(CustomSlideLibrary.filter(all, query: "bine ați venit").map(\.title) == ["Untitled"])
        #expect(CustomSlideLibrary.filter(all, query: "intro").map(\.title) == ["Untitled"])
        // A dynamic slide is recognised by the token it carries.
        #expect(CustomSlideLibrary.filter(all, query: "bible:").map(\.title) == ["Verset"])
    }

    @Test func noMatchIsEmptyRatherThanEverything() {
        #expect(CustomSlideLibrary.filter(slides(), query: "zzzz").isEmpty)
    }
}

@MainActor struct MediaLibraryTests {
    @Test func classifiesByExtension() {
        #expect(MediaKind.classify(extension: "JPG") == .image)
        #expect(MediaKind.classify(extension: "heic") == .image)
        #expect(MediaKind.classify(extension: "mp4") == .video)
        #expect(MediaKind.classify(extension: "MOV") == .video)
        #expect(MediaKind.classify(extension: "mp3") == .audio)
        #expect(MediaKind.classify(extension: "flac") == .audio)
        #expect(MediaKind.classify(extension: "xyz") == nil)      // "not media" is sayable now
        #expect(MediaKind.classify(extension: "svg") == .image)   // was known to one list only
        #expect(MediaKind.classify(extension: "flv") == nil)      // AVPlayer cannot play it
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

// MARK: - Book abbreviations (compact grid + narrow columns)
//
// Most modules carry no `abbreviation` — the field exists only when the source
// format had one — so the compact views cannot depend on it and derive a label
// instead. What matters is that derived labels stay DISTINCT: an abbreviation
// that collides is worse than a truncation, because it looks authoritative.

struct BookAbbreviationTests {

    @Test func aDerivedAbbreviationKeepsItsOrdinal() {
        // 1/2 Samuel, 1/2 Împărați, 1/2/3 Ioan all share a stem. Dropping the
        // ordinal would render them identically in the grid.
        #expect(BibleBook.deriveAbbreviation(from: "1 Împărați") == "1Împ")
        #expect(BibleBook.deriveAbbreviation(from: "2 Împărați") == "2Împ")
        #expect(BibleBook.deriveAbbreviation(from: "1 Samuel") == "1Sam")
        #expect(BibleBook.deriveAbbreviation(from: "2 Samuel") == "2Sam")
        #expect(BibleBook.deriveAbbreviation(from: "1 Ioan") == "1Ioa")
        #expect(BibleBook.deriveAbbreviation(from: "3 Ioan") == "3Ioa")
    }

    @Test func ordinalBooksStayDistinctFromEachOther() {
        let names = ["1 Împărați", "2 Împărați", "1 Cronici", "2 Cronici",
                     "1 Samuel", "2 Samuel", "1 Ioan", "2 Ioan", "3 Ioan",
                     "1 Corinteni", "2 Corinteni", "1 Petru", "2 Petru",
                     "1 Tesaloniceni", "2 Tesaloniceni", "1 Timotei", "2 Timotei"]
        let derived = names.map { BibleBook.deriveAbbreviation(from: $0) }
        #expect(Set(derived).count == names.count, "two books abbreviate the same: \(derived)")
    }

    @Test func aSingleWordBookUsesItsOwnStem() {
        #expect(BibleBook.deriveAbbreviation(from: "Geneza") == "Gene")
        #expect(BibleBook.deriveAbbreviation(from: "Exodul") == "Exod")
        #expect(BibleBook.deriveAbbreviation(from: "Apocalipsa") == "Apoc")
    }

    @Test func aMultiWordBookAbbreviatesOnItsLastWord() {
        // "Cântarea Cântărilor" and "Faptele Apostolilor" are the two that blow
        // out the grid; the distinguishing word is the last one.
        #expect(BibleBook.deriveAbbreviation(from: "Cântarea Cântărilor") == "Cânt")
        #expect(BibleBook.deriveAbbreviation(from: "Faptele Apostolilor") == "Apos")
    }

    @Test func aShortNameIsLeftAlone() {
        // Shorter than the stem length: prefix() must not pad or crash.
        #expect(BibleBook.deriveAbbreviation(from: "Iov") == "Iov")
        #expect(BibleBook.deriveAbbreviation(from: "Ezra") == "Ezra")
        #expect(BibleBook.deriveAbbreviation(from: "") == "")
    }

    @Test func aModuleSuppliedAbbreviationWins() {
        // When the source format DID carry one, it is authoritative — the
        // translator's own short form beats anything derived from the name.
        // Language is explicit: the abbreviation has to match the name shown
        // beside it, so it only wins while the module's own name is displayed.
        let book = BibleBook(name: "Cântarea Cântărilor", bookNumber: 22,
                             testament: "OT", abbreviation: "Cânt.C")
        #expect(book.displayAbbreviation(language: "ro") == "Cânt.C")

        let untagged = BibleBook(name: "Cântarea Cântărilor", bookNumber: 22, testament: "OT")
        #expect(untagged.displayAbbreviation(language: "ro") == "Cânt")
    }

    @Test func aBlankAbbreviationFallsBackRatherThanShowingNothing() {
        // Some importers write "" or "   " into the field; an empty grid cell
        // would be worse than a derived label.
        let book = BibleBook(name: "Geneza", bookNumber: 1, testament: "OT", abbreviation: "   ")
        #expect(book.displayAbbreviation(language: "ro") == "Gene")
    }

    @Test func aTranslationAbbreviationIsDroppedWhenTheNameIsLocalized() {
        // „Cânt.C" beside "Song of Solomon" is a mismatch the operator has to
        // decode; a derived short form at least matches the label above it.
        let book = BibleBook(name: "Cântarea Cântărilor", bookNumber: 22,
                             testament: "OT", abbreviation: "Cânt.C")
        #expect(book.displayAbbreviation(language: "en") == "Solo")
    }

    @Test func anAbbreviationThatStillFitsTheLocalizedNameIsKept() {
        // The published KJV module names its books in Romanian but abbreviates
        // them "Gen", "Ex", "1Sam" — which read perfectly beside the English
        // names, and beat anything derived.
        let genesis = BibleBook(name: "Geneza", bookNumber: 1, testament: "OT",
                                abbreviation: "Gen")
        #expect(genesis.displayAbbreviation(language: "en") == "Gen")

        // Dots and spaces fold away, so an ordinal short form still fits.
        let samuel = BibleBook(name: "1 Samuel", bookNumber: 9, testament: "OT",
                               abbreviation: "1Sam")
        #expect(samuel.displayAbbreviation(language: "en") == "1Sam")

        // A short form from the other language does not fit and is dropped.
        let facerea = BibleBook(name: "Geneza", bookNumber: 1, testament: "OT",
                                abbreviation: "Fac")
        #expect(facerea.displayAbbreviation(language: "en") == "Gene")
    }

    @Test func germanOrdinalsKeepTheirNumber() {
        // Without stripping the ordinal's dot, 1.–5. Mose all abbreviated to
        // "Mose" — five identical cells in the grid.
        #expect(BibleBook.deriveAbbreviation(from: "1. Mose") == "1Mos")
        #expect(BibleBook.deriveAbbreviation(from: "2. Korinther") == "2Kor")
        #expect(BibleBook.deriveAbbreviation(from: "1 Ioan") == "1Ioa")
    }
}

// MARK: - The Fast Bible-Import Path
//
// A Bible is ~31 000 verses and SwiftData writes them at ~5 000/s, which is 6.2s
// a translation and over eight minutes for a seventy-Bible library. These suites
// pin the two things that make the fast path legitimate rather than a hope: that
// the Core Data model derived from SwiftData's own `Schema` is the very model
// the store was created with, and that a Bible written through it is
// indistinguishable from one SwiftData wrote.
//
// Findings kept because they cost a day to learn:
//  • A hand-built NSManagedObjectModel is refused: Core Data compares version
//    hashes across EVERY entity, and uniqueness constraints count too — dropping
//    them for speed makes the store reject the model outright.
//  • SwiftData does not expose its own NSManagedObjectModel by reflection, so it
//    cannot be borrowed. It does expose `Schema`, which is public and complete,
//    and `SwiftDataModelBridge` derives the model from that instead.
//  • Core Data's batch operations cannot write relationships. Batch insert drops
//    them silently (pinned below); batch update raises NSInvalidArgumentException
//    — "Invalid relationship (… name chapter …) passed to propertiesToUpdate" —
//    which is an ObjC exception, so it aborts the process rather than throwing
//    and CANNOT be pinned by a test. Do not try.

import CoreData

struct ManagedObjectModelBridgeTests {

    private func tempStore(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "bridge-\(UUID().uuidString)-\(name).store")
    }
    private func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }

    /// THE guard. Core Data will not open a store whose recorded version hashes
    /// disagree with the model handed to it, so this failing means the fast path
    /// has silently switched itself off for every user — an import that is seven
    /// times slower for a reason nobody would think to look for.
    ///
    /// The usual cause is a new `@Model` property whose type or `@Attribute`
    /// option `SwiftDataModelBridge` does not map yet. The fix is in the bridge,
    /// and the entity named below says where to look.
    @Test func theDerivedModelIsTheOneTheStoreWasCreatedWith() throws {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let url = tempStore("hashes")
        defer { remove(url) }
        _ = try ModelContainer(for: schema, configurations: ModelConfiguration(url: url))

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let recorded = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        let derived = try SwiftDataModelBridge.managedObjectModel(for: schema).entityVersionHashesByName

        let mismatched = Set(recorded.keys).union(derived.keys)
            .filter { recorded[$0] == nil || recorded[$0] != derived[$0] }
            .sorted()
        #expect(mismatched.isEmpty, """
            SwiftDataModelBridge no longer reproduces \(mismatched.joined(separator: ", ")). \
            Every Bible import has fallen back to the slow path. Check what changed \
            in those @Model types — most likely a property type or an @Attribute \
            option the bridge does not map.
            """)
        #expect(recorded.count == 15, "the app's schema has 15 entities; got \(recorded.count)")
    }

    /// The end-to-end version of the same claim: Core Data opens, and can read,
    /// the file SwiftData wrote.
    @Test func theCoordinatorOpensAStoreSwiftDataCreated() throws {
        let url = tempStore("open")
        defer { remove(url) }
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(url: url))
        let ctx = ModelContext(container)
        ctx.insert(BibleModule(name: "Opened", abbreviation: "OPN", sourceFormat: "test"))
        try ctx.save()

        let coordinator = try SwiftDataModelBridge.coordinator(for: container)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let names: [String] = try context.performAndWait {
            try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "BibleModule"))
                .compactMap { $0.value(forKey: "name") as? String }
        }
        #expect(names == ["Opened"])
    }

    /// Tests and previews run in memory, and an in-memory store has no file for
    /// a second coordinator to open. Declining is the correct answer, not a bug —
    /// and it is what keeps every other suite in this file on the SwiftData path.
    @Test func inMemoryContainersDeclineTheBridge() throws {
        let container = try ModelContainer(
            for: BibleModule.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #expect(throws: SwiftDataModelBridge.StoreAccessError.self) {
            _ = try SwiftDataModelBridge.coordinator(for: container)
        }
    }
}

/// Counts notifications from whatever queue delivers them.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.lock(); count += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor struct BibleBulkWriterTests {

    private func tempStore(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "bulk-\(UUID().uuidString)-\(name).store")
    }
    private func remove(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
        }
    }
    private func fileBackedContext(_ url: URL) throws -> ModelContext {
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(url: url))
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        return ctx
    }

    /// The one that means "without losing anything".
    ///
    /// The same exported Bible is imported into two file-backed stores — once
    /// through Core Data, once through SwiftData — and the two are compared with
    /// `BibleModuleSnapshot`, the same whole-object snapshot the round-trip
    /// suite uses. New `@Model` properties are dragged into this comparison
    /// automatically, because `ModelFieldCoverageTests` refuses to let a
    /// persisted field stay out of the snapshot.
    @Test func bothWritePathsProduceTheSameBible() async throws {
        let fixtureStore = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let source = ModelContext(fixtureStore)
        let module = BibleRoundTripTests().fullyPopulatedModule(in: source)

        let file = FileManager.default.temporaryDirectory
            .appending(path: "bulk_equiv_\(UUID().uuidString).tpbible")
        try await ExportService.exportBible(module: module, format: .topPresenter, to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let slowURL = tempStore("slow"), fastURL = tempStore("fast")
        defer { remove(slowURL); remove(fastURL) }

        let previous = ImportService.usesBulkBibleWriter
        defer { ImportService.usesBulkBibleWriter = previous }

        ImportService.usesBulkBibleWriter = false
        let slow = try await ImportService.importBible(
            fileURL: file, format: .topPresenter,
            modelContext: try fileBackedContext(slowURL), resolution: .keepBoth).module
        let slowSnapshot = BibleModuleSnapshot(slow)

        ImportService.usesBulkBibleWriter = true
        let fast = try await ImportService.importBible(
            fileURL: file, format: .topPresenter,
            modelContext: try fileBackedContext(fastURL), resolution: .keepBoth).module

        #expect(BibleBulkWriter.lastDeclineReason == nil,
                "the fast path declined (\(BibleBulkWriter.lastDeclineReason ?? "")) — this test then proves nothing")
        #expect(BibleModuleSnapshot(fast) == slowSnapshot,
                "a Bible written through Core Data differs from one written through SwiftData")
    }

    /// After the bulk write the importing context has to see the books, because
    /// callers read `outcome.module.books` straight afterwards — and that context
    /// cached the module while its relationship was still empty.
    @Test func theImportingContextSeesTheBulkWrittenBooks() async throws {
        let fixtureStore = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let module = BibleRoundTripTests().fullyPopulatedModule(in: ModelContext(fixtureStore))
        let file = FileManager.default.temporaryDirectory
            .appending(path: "bulk_ctx_\(UUID().uuidString).tpbible")
        try await ExportService.exportBible(module: module, format: .topPresenter, to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let url = tempStore("ctx"); defer { remove(url) }
        let previous = ImportService.usesBulkBibleWriter
        defer { ImportService.usesBulkBibleWriter = previous }
        ImportService.usesBulkBibleWriter = true

        let imported = try await ImportService.importBible(
            fileURL: file, format: .topPresenter,
            modelContext: try fileBackedContext(url), resolution: .keepBoth).module

        #expect(BibleBulkWriter.lastDeclineReason == nil)
        #expect(!imported.books.isEmpty, "the module came back with no books — the context kept its stale, empty relationship")
        let verses = imported.books.reduce(0) { $0 + $1.chapters.reduce(0) { $0 + $1.verses.count } }
        #expect(verses > 0, "no verses reachable from the module")
    }

    /// The library list is a `@Query`, and `@Query` re-runs when a SwiftData
    /// context saves — not when some other coordinator writes the file. Without
    /// a real SwiftData save at the end of the fast path, an imported Bible is
    /// in the store, fetchable, and invisible in the sidebar until relaunch.
    ///
    /// This watches for the save itself rather than for the row, because the row
    /// is there either way; the notification is the part that can go missing.
    @Test func theFastPathStillNotifiesSwiftDataThatTheLibraryChanged() async throws {
        let fixtureStore = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let module = BibleRoundTripTests().fullyPopulatedModule(in: ModelContext(fixtureStore))
        let file = FileManager.default.temporaryDirectory
            .appending(path: "bulk_notify_\(UUID().uuidString).tpbible")
        try await ExportService.exportBible(module: module, format: .topPresenter, to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let url = tempStore("notify"); defer { remove(url) }
        let previous = ImportService.usesBulkBibleWriter
        defer { ImportService.usesBulkBibleWriter = previous }
        ImportService.usesBulkBibleWriter = true

        let saves = Counter()
        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: nil) { _ in saves.bump() }
        defer { NotificationCenter.default.removeObserver(token) }

        _ = try await ImportService.importBible(
            fileURL: file, format: .topPresenter,
            modelContext: try fileBackedContext(url), resolution: .keepBoth).module

        #expect(BibleBulkWriter.lastDeclineReason == nil)
        #expect(saves.value > 0, """
            the fast path finished without a single SwiftData save, so nothing told             the library's @Query to re-run — the Bible is in the store and absent             from the sidebar.
            """)
    }

    /// WHY the writer builds objects instead of calling `NSBatchInsertRequest`,
    /// which is three times faster again. Batch insert accepts a relationship in
    /// the dictionary, reports success, and writes a null foreign key: every
    /// verse an orphan, in a Bible that looks imported.
    ///
    /// If this ever fails, Apple has started honouring relationships in batch
    /// inserts and the writer is worth revisiting.
    @Test func batchInsertSilentlyDropsRelationships() throws {
        let url = tempStore("batch"); defer { remove(url) }
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(url: url))
        var chapterUUID = UUID()
        do {
            let ctx = ModelContext(container)
            let module = BibleModule(name: "Batch", abbreviation: "BAT", sourceFormat: "test")
            ctx.insert(module)
            let book = BibleBook(name: "Genesis", bookNumber: 1, testament: "OT")
            book.module = module
            let chapter = BibleChapter(chapterNumber: 1)
            chapter.book = book
            chapterUUID = chapter.id
            try ctx.save()
        }

        let coordinator = try SwiftDataModelBridge.coordinator(for: container)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator

        let inserted: Int = try context.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "BibleChapter")
            fetch.predicate = NSPredicate(format: "id == %@", chapterUUID as CVarArg)
            let chapterID = try #require(try context.fetch(fetch).first?.objectID)

            var index = 0
            let request = NSBatchInsertRequest(entityName: "BibleVerse", dictionaryHandler: { dict in
                if index >= 50 { return true }
                dict["id"] = UUID()
                dict["verseNumber"] = index + 1
                dict["text"] = "Verse \(index + 1)"
                dict["hasWordsOfChrist"] = false
                dict["gloss"] = ""
                dict["chapter"] = chapterID     // accepted, and ignored
                index += 1
                return false
            })
            request.resultType = .count
            return ((try context.execute(request) as? NSBatchInsertResult)?.result as? Int) ?? -1
        }
        #expect(inserted == 50, "batch insert reports success")

        let check = ModelContext(try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(url: url)))
        let orphans = try check.fetch(FetchDescriptor<BibleVerse>()).filter { $0.chapter == nil }
        #expect(orphans.count == 50, """
            batch insert now honours relationships — it dropped \(50 - orphans.count) fewer than before. \
            Revisit BibleBulkWriter: batch insert measured three times faster than the object path.
            """)
    }

    /// The whole Bible is one transaction, so a failure has to leave the store
    /// exactly as it was — that is what makes falling back to SwiftData safe
    /// rather than a way to write some books twice.
    ///
    /// The failure is real rather than injected: a module whose `id` already
    /// exists violates the entity's uniqueness constraint, and Core Data raises
    /// it at `save()` — after every book, chapter and verse has been built.
    @Test func afailedWriteLeavesNothingBehind() throws {
        let url = tempStore("fail"); defer { remove(url) }
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(url: url))
        let ctx = ModelContext(container)
        let squatter = BibleModule(name: "Already here", abbreviation: "AH", sourceFormat: "test")
        ctx.insert(squatter)
        try ctx.save()

        let clash = BibleModule(name: "Doomed", abbreviation: "DMD", sourceFormat: "test")
        clash.id = squatter.id
        let books = [BibleImportBook(name: "Genesis", bookNumber: 1, testament: "OT",
                                     chapters: [BibleImportChapter(chapterNumber: 1,
                                         verses: [BibleImportVerse(verseNumber: 1, text: "x")])])]
        #expect(throws: (any Error).self) {
            _ = try BibleBulkWriter.write(module: BibleBulkWriter.ModuleFields(clash),
                                          books: books, container: container)
        }

        let check = ModelContext(container)
        #expect(try check.fetch(FetchDescriptor<BibleBook>()).isEmpty,
                "a write that threw still left books in the store")
        #expect(try check.fetch(FetchDescriptor<BibleVerse>()).isEmpty)
        #expect(try check.fetch(FetchDescriptor<BibleModule>()).count == 1,
                "and it left a second module behind")
    }
}


// MARK: - Batch Song Import
//
// Importing 5 000 songs took 4m48s and was O(n^2) — per-song cost climbed from
// 5.3ms to 25.8ms as the run went on, so the 73 397-song library would have
// taken over an hour. `SongImportRun` made it 14.8s and flat at ~3ms.
//
// The speed is not asserted here: a loaded machine must not fail a correctness
// test. What IS asserted is the behaviour the two fixes could break — a
// songbook fetched once per run instead of once per song, and a collection
// linked at the end instead of per song.

@MainActor struct BatchSongImportTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Song.self, SongCollection.self, Songbook.self, SongVersion.self,
                SongSection.self, SongVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        return ctx
    }

    /// Writes `count` TopPresenter songs, every one naming the same songbook.
    private func writeSongs(count: Int, songbook: String, titlePrefix: String = "Cântecul",
                            into dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<count {
            let payload: [String: Any] = [
                "schemaVersion": "1.0.0",
                "format": "TopPresenter Song",
                "song": [
                    "title": "\(titlePrefix) \(i)",
                    "language": "ro",
                    "songbook": ["name": songbook, "publisher": "Editura", "year": "1990"],
                    "versions": [[
                        "name": "Original",
                        "sections": [["id": "v1", "type": "verse", "label": "1",
                                      "lines": [["text": "Rând unu al cântecului \(i)"]]]],
                    ]],
                ],
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            try data.write(to: dir.appending(path: "song\(i).tpsong"))
        }
    }

    /// The songbook cache must behave exactly like the per-song fetch it
    /// replaced: one row for one name, however many songs mention it.
    @Test func abatchNamingOneSongbookCreatesExactlyOne() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sb-\(UUID().uuidString)")
        try writeSongs(count: 40, songbook: "Imnuri Creștine", into: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ctx = try makeContext()
        let result = await ImportService.importSongItems(
            urls: [dir], collectionName: "Test", modelContext: ctx)

        #expect(result.importedTitles.count == 40)
        let books = try ctx.fetch(FetchDescriptor<Songbook>())
        #expect(books.count == 1, "got \(books.map(\.name)) — the cache must dedupe by name")
        #expect(books.first?.publisher == "Editura")
        #expect(try ctx.fetch(FetchDescriptor<Song>()).allSatisfy { $0.songbook?.name == "Imnuri Creștine" })
    }

    /// And it must find the songbooks already in the store, not shadow them with
    /// a second copy — the cache is seeded from one fetch, and if that fetch
    /// were skipped this is what would break.
    @Test func abatchReusesASongbookAlreadyInTheLibrary() async throws {
        let ctx = try makeContext()
        let existing = Songbook(name: "Imnuri Creștine", publisher: "Veche")
        ctx.insert(existing)
        try ctx.save()

        let dir = FileManager.default.temporaryDirectory.appending(path: "sb2-\(UUID().uuidString)")
        try writeSongs(count: 10, songbook: "Imnuri Creștine", into: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = await ImportService.importSongItems(
            urls: [dir], collectionName: "Test", modelContext: ctx)

        let books = try ctx.fetch(FetchDescriptor<Songbook>())
        #expect(books.count == 1, "a second songbook was created alongside the existing one")
        #expect(books.first?.id == existing.id)
        #expect(books.first?.publisher == "Veche", "the existing row must win, not be overwritten")
    }

    /// The collection is linked once at the end rather than per song. If that
    /// assignment were ever dropped, every imported song would be orphaned —
    /// present in the library and in no collection — which is exactly the kind
    /// of thing a speed change breaks quietly.
    @Test func everySongInABatchEndsUpInTheCollection() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "col-\(UUID().uuidString)")
        try writeSongs(count: 30, songbook: "Diverse", into: dir)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ctx = try makeContext()
        let result = await ImportService.importSongItems(
            urls: [dir], collectionName: "Colecția mea", modelContext: ctx)

        let collection = try #require(result.collection)
        #expect(collection.songs.count == 30, "\(collection.songs.count) of 30 songs made it into the collection")
        let songs = try ctx.fetch(FetchDescriptor<Song>())
        #expect(songs.count == 30)
        #expect(songs.allSatisfy { $0.collection?.name == "Colecția mea" },
                "\(songs.filter { $0.collection == nil }.count) songs came out with no collection")
    }

    /// A second batch has to join the songs already there, not replace them.
    @Test func asecondBatchAddsToTheCollectionInsteadOfReplacingIt() async throws {
        let ctx = try makeContext()
        for round in 0..<2 {
            let dir = FileManager.default.temporaryDirectory
                .appending(path: "col\(round)-\(UUID().uuidString)")
            // Distinct titles per round: identical ones are correctly merged as
            // extra versions of one song, which is a different test.
            try writeSongs(count: 5, songbook: "Diverse \(round)",
                           titlePrefix: "Runda \(round)", into: dir)
            defer { try? FileManager.default.removeItem(at: dir) }
            _ = await ImportService.importSongItems(
                urls: [dir], collectionName: "Aceeași", modelContext: ctx)
        }
        let collections = try ctx.fetch(FetchDescriptor<SongCollection>())
        #expect(collections.count == 1)
        #expect(collections.first?.songs.count == 10,
                "the second batch replaced the first instead of joining it")
    }
}

// MARK: - Why A Theme Package Would Not Open
//
// A report of "Pachetul de temă este invalid (lipsește theme.json)" on some
// themes and not others could not be reproduced. Eliminated, with evidence:
// diacritics in the theme name, the package name and the media name all import
// fine (including NFC, NFD and emoji); the published archives are structurally
// correct and both `unzip` and `ditto` extract them with theme.json in place;
// and `ImportScanner` treats a `.tptheme` as a leaf rather than walking into it.
//
// What was left was a message that could not tell those causes apart — a `.zip`
// under a package's name, a folder the sandbox refuses, an empty or truncated
// download all produced the same sentence. So the failure now says which it is.

@MainActor struct ThemePackageDiagnosisTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "tpd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The likeliest explanation, and the one the old message hid completely:
    /// the release ships `.tptheme.zip`, and a `.zip` renamed to `.tptheme` — or
    /// one that travelled through something that flattened the package — is a
    /// FILE where a folder is expected.
    @Test func azipUnderAPackageNameSaysToUnarchiveIt() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let fake = dir.appending(path: "Auroră.tptheme")
        try Data("PK\u{03}\u{04}not really a package".utf8).write(to: fake)

        #expect(PresentationManager.diagnosePackage(at: fake, underlying: nil) == .notAPackage)

        let pm = makeTestManager()
        #expect(throws: PresentationManager.ThemeIOError.self) {
            _ = try pm.importTheme(from: fake)
        }
    }

    @Test func amissingPackageSaysSo() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(PresentationManager.diagnosePackage(
            at: dir.appending(path: "Nu există.tptheme"), underlying: nil) == .missing)
    }

    @Test func anemptyPackageSaysSo() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pkg = dir.appending(path: "Goală.tptheme")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        #expect(PresentationManager.diagnosePackage(at: pkg, underlying: nil) == .empty)
    }

    /// A package with contents but no `theme.json` names what it DOES hold —
    /// which is how a double-wrapped folder ("Auroră.tptheme/Auroră.tptheme/…")
    /// becomes obvious instead of mysterious.
    @Test func apackageWithoutThemeJsonListsWhatItHolds() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pkg = dir.appending(path: "Auroră.tptheme")
        try FileManager.default.createDirectory(at: pkg.appending(path: "media"),
                                                withIntermediateDirectories: true)
        try Data("x".utf8).write(to: pkg.appending(path: "readme.txt"))

        let diagnosis = PresentationManager.diagnosePackage(at: pkg, underlying: nil)
        #expect(diagnosis == .noThemeJSON(contents: ["media", "readme.txt"]),
                "got: \(diagnosis)")
        // The operator has to be able to READ it too, in whatever language.
        #expect(diagnosis.localizedReason.contains("theme.json"))
    }

    /// Diacritics were the reported pattern and are NOT the cause. Kept so the
    /// elimination stays proven rather than remembered — every form of the name
    /// that macOS can produce round-trips.
    @Test func diacriticsInEveryNameRoundTrip() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = [
            "Abstract",
            "Auror\u{0103}",                 // ă precomposed (NFC)
            "Auror\u{0061}\u{0306}",         // a + combining breve (NFD)
            "Cerneal\u{0103} 🌅",
        ]
        for name in names {
            let pm = makeTestManager()
            pm.fontSize = 44
            let theme = pm.saveCurrentAsTheme(named: name, formatRaw: "all")
            let pkg = dir.appending(path: "\(name).tptheme")
            try pm.exportTheme(id: theme.id, to: pkg)

            let fresh = makeTestManager()
            let imported = try fresh.importTheme(from: pkg)
            #expect(imported.payload.fontSize == 44,
                    "\(name) did not survive the round trip")
        }
    }
}

// MARK: - Batch Import Caches
//
// Every importer answered "is this already in the library?" by re-reading the
// library, per FILE. All five were quadratic:
//
//     slides    16.6 ms/deck at 50  →  125.7 at 400   (50.3s)  →  1.05s
//     sessions  25.0 ms/file at 50  →  111.3 at 400   (44.5s)  →  0.68s
//     themes    10.4 ms/file at 25  →   70.7 at 200   (14.1s)  →  0.38s
//     media      2.03 ms/file at 250 →   3.44 at 2000  (6.9s)  →  4.72s
//
// `ImportRun` holds that work once per batch. Speed is NOT asserted here — a
// loaded machine must not fail a correctness test. What is asserted is the one
// thing a cache can get wrong and a benchmark will never notice: the second file
// in a batch has to see what the first one imported. Miss that and duplicates
// sail straight through the check that exists to stop them.

@MainActor struct BatchImportRunTests {

    private func store(_ types: [any PersistentModel.Type]) throws -> ModelContext {
        let ctx = ModelContext(try ModelContainer(for: Schema(types),
                                                  configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        ctx.autosaveEnabled = false
        return ctx
    }

    @Test func asecondCopyOfADeckInOneRunIsRecognised() throws {
        let ctx = try store([PresentationSlide.self])
        let deck = try SlideDeckArchiveService.export((0..<4).map {
            PresentationSlide(title: "Slide \($0)", content: "C\($0)",
                              subtitle: "s", slideType: "text", order: $0)
        })
        let run = ImportRun()
        let first = try SlideDeckArchiveService.importDeck(deck, context: ctx, run: run)
        let second = try SlideDeckArchiveService.importDeck(deck, context: ctx, run: run)

        #expect(first.imported.count == 4)
        #expect(second.imported.isEmpty, "the cache did not see the first deck — \(second.imported.count) slides imported twice")
        #expect(second.skipped.count == 4)
        #expect(try ctx.fetch(FetchDescriptor<PresentationSlide>()).count == 4)
    }

    @Test func slidesFromTwoDecksInOneRunGetDistinctOrders() throws {
        let ctx = try store([PresentationSlide.self])
        let run = ImportRun()
        for deck in 0..<3 {
            let data = try SlideDeckArchiveService.export((0..<3).map {
                PresentationSlide(title: "D\(deck)S\($0)", content: "c\(deck)\($0)",
                                  subtitle: "", slideType: "text", order: $0)
            })
            _ = try SlideDeckArchiveService.importDeck(data, context: ctx, run: run)
        }
        let orders = try ctx.fetch(FetchDescriptor<PresentationSlide>()).map(\.order)
        #expect(orders.count == 9)
        #expect(Set(orders).count == 9, "orders collided across decks: \(orders.sorted())")
    }

    @Test func asecondCopyOfASessionInOneRunIsRecognised() throws {
        let ctx = try store([ServiceSchedule.self, ScheduleItem.self, MediaItem.self])
        let session = SessionService.createSession(name: "Duminică", context: ctx)
        SessionService.append(.text(title: "Bun venit", content: "Salut"), to: session, context: ctx)
        try ctx.save()
        let data = try SessionArchiveService.export(session)
        ctx.delete(session)
        try ctx.save()

        let run = ImportRun()
        let first = try SessionArchiveService.importSession(data, context: ctx, run: run)
        let second = try SessionArchiveService.importSession(data, context: ctx, run: run)

        #expect(first.schedule.id == second.schedule.id,
                "the cache did not see the first session — it was imported twice")
        #expect(try ctx.fetch(FetchDescriptor<ServiceSchedule>()).count == 1)
    }

    /// The media library is fetched once per run and used to re-link session
    /// items. A session imported LATER in the batch must still resolve its clip.
    @Test func sessionsLaterInARunStillResolveTheirMedia() throws {
        let ctx = try store([ServiceSchedule.self, ScheduleItem.self, MediaItem.self])
        let clip = MediaItem(name: "Worship Loop.mp4", filePath: "/tmp/Worship Loop.mp4", mediaType: "video")
        ctx.insert(clip)
        try ctx.save()

        var archives: [Data] = []
        for i in 0..<3 {
            let s = SessionService.createSession(name: "Sesiunea \(i)", context: ctx)
            SessionService.append(.media(clip), to: s, context: ctx)
            try ctx.save()
            archives.append(try SessionArchiveService.export(s))
            ctx.delete(s)
            try ctx.save()
        }

        let run = ImportRun()
        for data in archives {
            let result = try SessionArchiveService.importSession(data, context: ctx, run: run)
            #expect(result.unresolvedMedia.isEmpty,
                    "a session lost its clip: \(result.unresolvedMedia)")
        }
    }

    @Test func asecondCopyOfAThemeInOneRunIsRecognised() throws {
        let pm = makeTestManager()
        pm.fontSize = 42
        let theme = pm.saveCurrentAsTheme(named: "Galaxie", formatRaw: "all")
        let pkg = FileManager.default.temporaryDirectory.appending(path: "t-\(UUID().uuidString).tptheme")
        try pm.exportTheme(id: theme.id, to: pkg)
        defer { try? FileManager.default.removeItem(at: pkg) }

        let fresh = makeTestManager()
        let run = ImportRun()
        fresh.suspendThemePersistence()
        defer { fresh.flushThemes() }
        _ = try fresh.importTheme(from: pkg, run: run)
        _ = try fresh.importTheme(from: pkg, run: run)

        #expect(fresh.themes.count == 1,
                "the cache did not see the first theme — the gallery has \(fresh.themes.count)")
    }

    /// Suspended and never flushed means the gallery lives in memory and is gone
    /// on the next launch. That is the failure this pairing can produce, so it is
    /// asserted through a SECOND manager reading the same settings store.
    @Test func abatchOfThemesIsActuallyPersisted() throws {
        let defaults = makeTestDefaults()
        let source = makeTestManager()
        source.fontSize = 33
        let theme = source.saveCurrentAsTheme(named: "Persistată", formatRaw: "all")
        let pkg = FileManager.default.temporaryDirectory.appending(path: "tp-\(UUID().uuidString).tptheme")
        try source.exportTheme(id: theme.id, to: pkg)
        defer { try? FileManager.default.removeItem(at: pkg) }

        do {
            let importer = makeTestManager(defaults)
            importer.suspendThemePersistence()
            defer { importer.flushThemes() }
            _ = try importer.importTheme(from: pkg, run: ImportRun())
            #expect(importer.themes.count == 1)
        }

        // A fresh manager on the SAME store is what "survives a relaunch" means.
        let relaunched = makeTestManager(defaults)
        #expect(relaunched.themes.count == 1,
                "the batch was never written — the themes were in memory only")
        #expect(relaunched.themes.first?.name == "Persistată")
    }

    @Test func asecondCopyOfAMediaFileInOneRunIsSkipped() throws {
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!
        let dir = FileManager.default.temporaryDirectory.appending(path: "m-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "photo.png")
        try png.write(to: file)
        // A different path with the same name and size — the resolver's second
        // rule, which the superset pre-check must not hide.
        let twin = dir.appending(path: "copy/photo.png")
        try FileManager.default.createDirectory(at: dir.appending(path: "copy"), withIntermediateDirectories: true)
        try png.write(to: twin)

        let ctx = try store([MediaItem.self])
        let outcome = MediaImportService.importMedia(urls: [file, file, twin], modelContext: ctx,
                                                    run: ImportRun())
        #expect(outcome.imported.count == 1, "imported \(outcome.imported.count) — duplicates got through")
        #expect(outcome.skipped.count == 2)
        #expect(try ctx.fetch(FetchDescriptor<MediaItem>()).count == 1)
    }

    /// Without a run every importer must behave exactly as it always did, or the
    /// fast path has quietly become a second implementation of the rules.
    @Test func importersWithoutARunAreUnchanged() throws {
        let ctx = try store([PresentationSlide.self])
        let deck = try SlideDeckArchiveService.export([
            PresentationSlide(title: "Solo", content: "C", subtitle: "", slideType: "text", order: 0),
        ])
        _ = try SlideDeckArchiveService.importDeck(deck, context: ctx)
        let second = try SlideDeckArchiveService.importDeck(deck, context: ctx)
        #expect(second.imported.isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<PresentationSlide>()).count == 1)
    }
}

// MARK: - Collections Can Be Managed

struct CollectionManagementTests {

    private func container() throws -> ModelContainer {
        try ModelContainer(for: Song.self, SongCollection.self, Songbook.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func movingSongsEmptiesTheSourceAndKeepsThem() async throws {
        let c = try container()
        let ctx = ModelContext(c)
        let from = SongCollection(name: "Scraped", sourceFormat: "mixed")
        let to = SongCollection(name: "Cantări", sourceFormat: "mixed")
        ctx.insert(from); ctx.insert(to)
        for i in 0..<25 {
            let song = Song(title: "Cântec \(i)")
            song.collection = from
            ctx.insert(song)
        }
        try ctx.save()

        let actor = LibraryMaintenanceActor(modelContainer: c)
        let moved = await actor.moveSongs(fromCollection: from.id, toCollection: to.id)
        #expect(moved == 25)

        // Read back on a fresh context — the actor saved on its own.
        let check = ModelContext(c)
        let all = try check.fetch(FetchDescriptor<Song>())
        #expect(all.count == 25, "moving must never lose a song")
        #expect(all.allSatisfy { $0.collection?.name == "Cantări" })

        let source = try check.fetch(FetchDescriptor<SongCollection>(
            predicate: #Predicate { $0.name == "Scraped" })).first
        #expect(source != nil, "the source collection stays — deleting it is a separate decision")
        #expect(source?.songs.isEmpty == true)
    }

    @Test func movingToAMissingCollectionChangesNothing() async throws {
        let c = try container()
        let ctx = ModelContext(c)
        let from = SongCollection(name: "A", sourceFormat: "mixed")
        ctx.insert(from)
        let song = Song(title: "One")
        song.collection = from
        ctx.insert(song)
        try ctx.save()

        let actor = LibraryMaintenanceActor(modelContainer: c)
        let moved = await actor.moveSongs(fromCollection: from.id, toCollection: UUID())
        #expect(moved == 0)

        let check = ModelContext(c)
        #expect(try check.fetch(FetchDescriptor<Song>()).first?.collection?.name == "A")
    }

    @Test func deletingACollectionTakesItsSongsWithIt() throws {
        // The relationship is `.cascade`, which is WHY the confirmation names
        // the song count: "delete the collection" and "delete these 4 930 songs"
        // are the same gesture, and the operator has to be told that.
        let c = try container()
        let ctx = ModelContext(c)
        let col = SongCollection(name: "Doomed", sourceFormat: "mixed")
        ctx.insert(col)
        for i in 0..<5 {
            let song = Song(title: "S\(i)")
            song.collection = col
            ctx.insert(song)
        }
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Song>()).count == 5)

        ctx.delete(col)
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<Song>()).isEmpty)
    }
}

// MARK: - The Open Panel Must Allow Every Native Format

struct ImportPanelTypeTests {

    @Test func everyNativeExtensionResolvesToItsDeclaredType() {
        // `UTType(filenameExtension:)` means `conformingTo: .data`. A `.tptheme`
        // is a PACKAGE — `public.directory`, never `public.data` — so the
        // declared type was skipped and the extension resolved to a dynamic
        // `dyn.…` identifier that matches nothing real. The open panel greyed
        // out every theme: "Choose Files…" could not select one at all.
        for ext in ["tptheme", "tpbible", "tpsong", "tpsongcollection", "tpslides", "tpschedule"] {
            let resolved = UTType(filenameExtension: ext, conformingTo: .item)
            #expect(resolved?.identifier.hasPrefix("com.robyrew.toppresenter") == true,
                    "\(ext) resolved to \(resolved?.identifier ?? "nil")")
        }
    }

    @Test func theOpenPanelAcceptsThemesAndBibles() {
        let types = ImportCatalog.contentTypes()
        #expect(types.contains { $0.identifier == "com.robyrew.toppresenter.theme" },
                "a theme package must be selectable in the import panel")
        #expect(types.contains { $0.identifier == "com.robyrew.toppresenter.bible" })
        // A dynamic type is fine for an extension nobody registered (`.cho`,
        // `.usfm`): the file gets the same dynamic type, so they match. It is
        // wrong only where a REAL type exists and was missed — then the panel
        // filters out the very files it is meant to offer. So: every one of our
        // own types is present, by name.
        let native = types.filter { $0.identifier.hasPrefix("com.robyrew.toppresenter") }
        #expect(native.count == 6, "expected all six native types, got \(native.map(\.identifier).sorted())")
    }
}

// MARK: - Format Sniffing Survives Diacritics And Long Headers

/// Why some `.tpsong` / `.tpbible` files were "not recognised" and others,
/// same format, were fine.
struct FormatProbeTests {

    private func write(_ text: String, _ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "probe-\(UUID().uuidString)-\(name)")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test func aDiacriticStraddlingTheCutNoLongerKillsDetection() throws {
        // The old probe took `data.prefix(2000)` and decoded it with
        // `String(data:encoding:.utf8)`, which returns nil when the cut lands
        // inside a multi-byte character. Padding is sized so a „ș" (2 bytes)
        // sits exactly across byte 2000, and the marker comes after it.
        var json = "{\"format\": \"TopPresenter Song\", \"pad\": \""
        let head = json.utf8.count
        json += String(repeating: "a", count: 2000 - head - 1)   // one byte short
        json += "ș"                                              // straddles 2000
        json += "\", \"versions\": [], \"verses\": []}"

        let url = try write(json, "diacritic.tpsong")
        defer { try? FileManager.default.removeItem(at: url) }

        let raw = try Data(contentsOf: url)
        #expect(String(data: raw.prefix(2000), encoding: .utf8) == nil,
                "fixture must actually straddle the old cut, or it proves nothing")
        #expect(ImportService.detectSongFormat(fileURL: url) == .topPresenterJSON)
    }

    @Test func aMarkerPastTheOldWindowIsStillFound() throws {
        // A native file with a long copyright / aboutText block pushed the
        // marker past the old 1–4 KB window, and the file was refused on
        // content even though its extension was right.
        let filler = String(repeating: "Cuvânt înainte. ", count: 900)   // ~14 KB
        let json = "{\"format\": \"TopPresenter Bible\", \"aboutText\": \"\(filler)\", \"books\": []}"
        let url = try write(json, "long.tpbible")
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(json.utf8.count > 4000, "fixture must exceed the old window")
        #expect(ImportService.detectBibleFormat(fileURL: url) == .topPresenter)
    }

    @Test func foreignJSONIsStillRefused() throws {
        // The window got bigger, not laxer — a stray JSON must not be adopted.
        let url = try write("{\"name\": \"something else\", \"items\": [1, 2, 3]}", "foreign.json")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ImportService.detectSongFormat(fileURL: url) == nil)
        #expect(ImportService.detectBibleFormat(fileURL: url) == nil)
    }
}

// MARK: - Section Type Reaches The Output

/// Setting a section's type in the editor has to change what the slide IS, not
/// just what the editor draws.
@MainActor
struct SectionTypeTests {

    @Test func theDeclaredTypeDecidesTheChorusScope() {
        // The theme's Refren / Strofe scope used to be judged by sniffing the
        // LABEL for "refren"/"chorus"/"cor". A section typed as a chorus but
        // labelled "Strofa 2" was styled as a verse, and nothing the operator
        // did in the type picker changed it.
        let live = LiveContent()
        live.setSongVerse(text: "…", title: "T", verseLabel: "Strofa 2", sectionType: "chorus")
        #expect(live.isChorusSlide)

        live.setSongVerse(text: "…", title: "T", verseLabel: "Refren", sectionType: "verse")
        #expect(!live.isChorusSlide, "a declared verse is not a chorus, whatever it is called")
    }

    @Test func labelSniffingStaysForSongsWithNoType() {
        // Songs imported before the version model have no sections and no type.
        // Guessing from the label is all there is, so it has to keep working.
        let live = LiveContent()
        live.setSongVerse(text: "…", title: "T", verseLabel: "Refren 2", sectionType: "")
        #expect(live.isChorusSlide)

        live.setSongVerse(text: "…", title: "T", verseLabel: "Strofa 1", sectionType: "")
        #expect(!live.isChorusSlide)
    }

    @Test func clearingResetsTheType() {
        // A stale type would style the NEXT thing shown as a chorus.
        let live = LiveContent()
        live.setSongVerse(text: "…", title: "T", verseLabel: "R", sectionType: "chorus")
        live.clear()
        #expect(live.sectionType.isEmpty)
        #expect(!live.isChorusSlide)
    }
}

// MARK: - Click-Outside Dismiss

/// Which click abandons the import sheet.
struct SheetDismissRuleTests {
    // Stand-ins for four distinct NSWindows.
    private final class Win {}
    private let sheetWin = Win(), parentWin = Win(), panelWin = Win()

    private func dismisses(_ clicked: Win?, parent: Win?, blocked: Bool = false) -> Bool {
        SheetDismissRule.dismisses(clicked: clicked.map(ObjectIdentifier.init),
                                   sheet: ObjectIdentifier(sheetWin),
                                   parent: parent.map(ObjectIdentifier.init),
                                   isBlocked: blocked)
    }

    @Test func clickingTheWindowBehindDismisses() {
        #expect(dismisses(parentWin, parent: parentWin))
    }

    @Test func choosingAFileInTheOpenPanelDoesNot() {
        // THE BUG: the sheet opens an NSOpenPanel, the operator clicks a file in
        // it, and the import sheet standing behind vanishes. The panel is this
        // app's window, so "anything that is not the sheet" caught it.
        #expect(!dismisses(panelWin, parent: parentWin))
    }

    @Test func clicksInsideTheSheetNeverDismiss() {
        #expect(!dismisses(sheetWin, parent: parentWin))
    }

    @Test func nothingDismissesWhileSomethingIsLayeredOnTop() {
        // A panel or alert is up: even a click that lands on the parent belongs
        // to it, not to us.
        #expect(!dismisses(parentWin, parent: parentWin, blocked: true))
        #expect(!dismisses(panelWin, parent: parentWin, blocked: true))
    }

    @Test func anUnattachedSheetKeepsTheOldRule() {
        // Presented as a plain window rather than a real sheet — better to keep
        // the gesture working loosely than to lose it silently.
        #expect(dismisses(panelWin, parent: nil))
        #expect(!dismisses(sheetWin, parent: nil))
    }

    @Test func anEventWithNoWindowIsIgnored() {
        #expect(!dismisses(nil, parent: parentWin))
    }
}

// MARK: - Book Names In The App's Language

/// A module carries the book names its source file used. The library has to read
/// in the operator's language whatever translation is loaded — and must never
/// rename a book it cannot positively identify.
struct BibleBookLocalizationTests {

    @Test func everyLanguageHasAllSixtySixBooks() {
        for language in ["en", "ro", "es", "fr", "de", "ru"] {
            #expect(BibleBookLocalization.name(number: 1, language: language) != nil,
                    "\(language) is missing Genesis")
            #expect(BibleBookLocalization.name(number: 66, language: language) != nil,
                    "\(language) is missing Revelation")
            for number in 1...66 {
                let name = BibleBookLocalization.name(number: number, language: language) ?? ""
                #expect(!name.isEmpty, "\(language) book \(number) is blank")
            }
        }
        // Outside the canon there is no table — deuterocanonical books keep the
        // module's own wording rather than being renamed into a guess.
        #expect(BibleBookLocalization.name(number: 0) == nil)
        #expect(BibleBookLocalization.name(number: 67) == nil)
    }

    @Test func noTwoBooksShareAName() {
        // The whole table is one flat name→number index. If two DIFFERENT books
        // fold to the same key, which one a name resolves to depends on
        // dictionary order — silently, and differently per launch.
        let duplicates = BibleBookLocalization.duplicateNameKeys
        #expect(duplicates.isEmpty,
                "these names claim more than one book: \(duplicates.keys.sorted())")
    }

    @Test func aBookIsIdentifiedFromAnyLanguage() {
        for name in ["Genesis", "Geneza", "Génesis", "Genèse", "1. Mose", "Бытие", "Facerea"] {
            #expect(BibleBookLocalization.canonicalNumber(forName: name) == 1, "\(name) → 1")
        }
        for name in ["Revelation", "Apocalipsa", "Apocalipsis", "Apocalypse",
                     "Offenbarung", "Откровение"] {
            #expect(BibleBookLocalization.canonicalNumber(forName: name) == 66, "\(name) → 66")
        }
        // Case and diacritics fold away; ordinal dots do too.
        #expect(BibleBookLocalization.canonicalNumber(forName: "CÂNTAREA CÂNTĂRILOR") == 22)
        #expect(BibleBookLocalization.canonicalNumber(forName: "cantarea cantarilor") == 22)
        #expect(BibleBookLocalization.canonicalNumber(forName: "2. Korinther") == 47)
        // Nonsense stays unidentified rather than resolving to something near.
        #expect(BibleBookLocalization.canonicalNumber(forName: "Cartea Mormonilor") == nil)
        #expect(BibleBookLocalization.canonicalNumber(forName: "") == nil)
    }

    @Test func anUnknownBookKeepsItsOwnName() {
        // The safety property the whole feature rests on.
        #expect(BibleBookLocalization.localizedName(for: "Înțelepciunea lui Solomon",
                                                    language: "en")
                == "Înțelepciunea lui Solomon")
        #expect(BibleBookLocalization.localizedName(for: "Sirach", language: "ro") == "Sirach")
    }

    @Test func namesCrossOverBetweenLanguages() {
        #expect(BibleBookLocalization.localizedName(for: "Geneza", language: "en") == "Genesis")
        #expect(BibleBookLocalization.localizedName(for: "Genesis", language: "ro") == "Geneza")
        #expect(BibleBookLocalization.localizedName(for: "Faptele Apostolilor", language: "es")
                == "Hechos")
        #expect(BibleBookLocalization.localizedName(for: "1 Ioan", language: "de")
                == "1. Johannes")
        #expect(BibleBookLocalization.localizedName(for: "Song of Solomon", language: "fr")
                == "Cantique des Cantiques")
    }

    @Test func ambiguousEditionsAreLeftAlone() {
        // Orthodox Romanian editions number 1–4 Regi from 1 Samuel; others start
        // at 1 Kings. Guessing would put the wrong book name on the screen, so
        // „Regi" is not in the table at all.
        #expect(BibleBookLocalization.canonicalNumber(forName: "1 Regi") == nil)
        #expect(BibleBookLocalization.localizedName(for: "1 Regi", language: "en") == "1 Regi")
        // The unambiguous Cornilescu wording still resolves.
        #expect(BibleBookLocalization.localizedName(for: "1 Împărați", language: "en") == "1 Kings")
    }

    @Test func aBookNumberedByACounterIsNotRenamed() {
        // `OSISBibleImporter` numbers books with a running counter, so an NT-only
        // file has Matthew at 1. Resolving by NAME is what keeps that honest —
        // this is the test that would fail if anyone switched to the number.
        let matthew = BibleBook(name: "Matthew", bookNumber: 1, testament: "NT")
        #expect(matthew.displayName(language: "ro") == "Matei")

        // And in a file whose numbering we DO trust, a name that lands somewhere
        // else is an edition naming books its own way — Douay-Rheims calls
        // 1 Samuel "1 Kings". Renaming that would show the wrong book.
        let douay = BibleBook(name: "1 Kings", bookNumber: 9, testament: "OT")
        #expect(douay.displayName(language: "ro") == "1 Kings")
    }

    @Test func englishNameWinsOverTheDisplayName() {
        // TopPresenter's own format carries `nameEnglish`; it is the most
        // reliable field in the record, so it is consulted first.
        let book = BibleBook(name: "Ps", bookNumber: 19, testament: "OT",
                             nameEnglish: "Psalms")
        #expect(book.displayName(language: "ro") == "Psalmii")
    }

    @Test func aNumberedBookFallsBackOnItsPositionOnlyWhenTheTestamentAgrees() {
        // Last resort for a module whose names we cannot read at all (a
        // transliterated or abbreviated file).
        let readable = BibleBook(name: "Kniha Genezis", bookNumber: 1, testament: "OT")
        #expect(readable.displayName(language: "en") == "Genesis")
        // Counter-numbered NT-only file: position 1 says Genesis, testament says
        // NT. Contradiction → keep the file's own name.
        let counter = BibleBook(name: "Evangelium podľa Matúša", bookNumber: 1, testament: "NT")
        #expect(counter.displayName(language: "en") == "Evangelium podľa Matúša")
    }

    @Test func storedReferencesAreRestatedWithoutTouchingTheNumbers() {
        // History rows and session items persist one string in the translation's
        // language. The chapter/verse tail must survive exactly.
        #expect(BibleBookLocalization.localizedReference("Geneza 1:1", language: "en")
                == "Genesis 1:1")
        #expect(BibleBookLocalization.localizedReference("Faptele Apostolilor 2:1-4",
                                                         language: "en")
                == "Acts 2:1-4")
        #expect(BibleBookLocalization.localizedReference("1 Ioan 4:7,9", language: "es")
                == "1 Juan 4:7,9")
        #expect(BibleBookLocalization.localizedReference("Psalmii 23", language: "de")
                == "Psalmen 23")
        // Unidentifiable book, no numeric tail, empty — all returned untouched.
        #expect(BibleBookLocalization.localizedReference("Sirah 2:1", language: "en")
                == "Sirah 2:1")
        #expect(BibleBookLocalization.localizedReference("Geneza", language: "en") == "Geneza")
        #expect(BibleBookLocalization.localizedReference("", language: "en") == "")
    }

    @Test func theProjectedReferenceFollowsTheTranslationNotTheFile() {
        // The published KJV module carries ROMANIAN book names, so it projected
        // „Geneza 1:6" over English verses. The module declares its language;
        // that is what the congregation is reading, so that is what wins.
        let kjv = BibleModule(name: "King James Version", abbreviation: "KJV",
                              language: "en", sourceFormat: "toppresenter")
        let genesis = BibleBook(name: "Geneza", bookNumber: 1, testament: "OT")
        genesis.module = kjv
        #expect(genesis.presentationName == "Genesis")

        let cornilescu = BibleModule(name: "Cornilescu", abbreviation: "VDC",
                                     language: "ro", sourceFormat: "toppresenter")
        let geneza = BibleBook(name: "Genesis", bookNumber: 1, testament: "OT")
        geneza.module = cornilescu
        #expect(geneza.presentationName == "Geneza")
    }

    @Test func aTranslationInALanguageWeHaveNoTableForKeepsItsOwnNames() {
        // 17 languages ship in the Bible library; six have a table. Answering
        // "Genesis" for a Dutch module would be worse than leaving it alone.
        let hetBoek = BibleModule(name: "Het Boek", abbreviation: "HTB",
                                  language: "nl", sourceFormat: "zefania")
        let genesis = BibleBook(name: "Genesis", bookNumber: 1, testament: "OT")
        genesis.module = hetBoek
        #expect(genesis.presentationName == "Genesis")

        let dutch = BibleBook(name: "Spreuken", bookNumber: 20, testament: "OT")
        dutch.module = hetBoek
        #expect(dutch.presentationName == "Spreuken")
        // …while the operator's own list still reads in the app's language,
        // because the book is identifiable even though Dutch is not a UI option.
        #expect(dutch.displayName(language: "en") == "Proverbs")
    }

    @Test func aBookWithNoModuleFallsBackRatherThanCrashing() {
        // Verses reached through a broken relationship still have to render.
        let orphan = BibleBook(name: "Geneza", bookNumber: 1, testament: "OT")
        #expect(orphan.presentationName == "Geneza")
    }

    /// One test, not two, and deliberately so: both halves drive the SAME
    /// `UserDefaults` key, and Swift Testing runs tests in parallel — as two
    /// tests they raced and one read the other's value.
    @Test func theLibraryNameLanguageIsASettingWithASafeDefault() {
        let key = BibleBookLocalization.NameMode.settingKey
        let stored = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(stored, forKey: key) }

        // Default is the translation's own language: the list then matches the
        // text beside it and the reference on the projector.
        UserDefaults.standard.removeObject(forKey: key)
        #expect(BibleBookLocalization.nameMode == .translation)

        // Junk in the slot must not leave the library nameless.
        UserDefaults.standard.set("nonsense", forKey: key)
        #expect(BibleBookLocalization.nameMode == .translation)

        UserDefaults.standard.set("app", forKey: key)
        #expect(BibleBookLocalization.nameMode == .app)

        // A Romanian module whose file happens to name its books in English.
        let cornilescu = BibleModule(name: "Cornilescu", abbreviation: "VDC",
                                     language: "ro", sourceFormat: "toppresenter")
        let book = BibleBook(name: "Genesis", bookNumber: 1, testament: "OT")
        book.module = cornilescu

        #expect(book.displayName == book.displayName(language: BibleBookLocalization.uiLanguage))

        UserDefaults.standard.set("translation", forKey: key)
        #expect(book.displayName == "Geneza")

        // Either way the projector follows the translation.
        #expect(book.presentationName == "Geneza")
    }

    @Test func theUILanguageIsAlwaysOneWeHaveATableFor() {
        // A Catalan or Polish system localization must not leave book names nil.
        #expect(BibleBookLocalization.name(number: 1,
                                           language: BibleBookLocalization.uiLanguage) != nil)
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

    // MARK: Cross-language queries

    @Test func aRomanianModuleAnswersToEnglishNames() {
        // The operator reads "John" in the book list, so "john 3:16" has to work
        // even though the module says "Ioan".
        let match = BibleReferenceParser.parse("john 3:16", books: books)
        #expect(match?.bookNumber == 43)
        // The MODULE's name is what goes to the output — the audience is reading
        // this translation.
        #expect(match?.bookName == "Ioan")
        // …and the app's name is what the palette row shows.
        #expect(match?.bookDisplayName == BibleBookLocalization.localizedName(for: "Ioan"))

        #expect(BibleReferenceParser.parse("1 corinthians 13:4", books: books)?.bookNumber == 46)
        #expect(BibleReferenceParser.parse("salmos 23", books: books)?.bookNumber == 19)
        #expect(BibleReferenceParser.parse("psalmen 23", books: books)?.bookNumber == 19)
    }

    @Test func standardAbbreviationsWorkWithoutTheModuleDeclaringThem() {
        // Most source formats carry no abbreviation at all, so these come from
        // the shared table rather than the file.
        let untagged: [BookIndexEntry] = [
            .init(moduleID: UUID(), bookNumber: 44, name: "Faptele Apostolilor",
                  folded: "faptele apostolilor", abbreviationFolded: "", chapterCount: 28)
        ]
        #expect(BibleReferenceParser.parse("fap 2:1", books: untagged)?.bookNumber == 44)
        #expect(BibleReferenceParser.parse("acts 2:1", books: untagged)?.bookNumber == 44)
        #expect(BibleReferenceParser.parse("hechos 2", books: untagged)?.bookNumber == 44)
    }

    @Test func germanOrdinalReferencesParse() {
        // "1. Mose 1" used to fall through the regex to the bare-book path and
        // match nothing at all.
        let german: [BookIndexEntry] = [
            .init(moduleID: UUID(), bookNumber: 1, name: "1. Mose", folded: "1. mose",
                  abbreviationFolded: "", chapterCount: 50)
        ]
        #expect(BibleReferenceParser.parse("1. mose 1:1", books: german)?.bookNumber == 1)
        #expect(BibleReferenceParser.parse("genesis 1:1", books: german)?.bookNumber == 1)
    }

    @Test func shortAliasesNeedAChapterToCountAsAReference() {
        // With a chapter number the intent is unambiguous; bare, a two-letter
        // alias would turn ordinary palette queries into Bible references.
        let amos: [BookIndexEntry] = [
            .init(moduleID: UUID(), bookNumber: 30, name: "Amos", folded: "amos",
                  abbreviationFolded: "", chapterCount: 9)
        ]
        #expect(BibleReferenceParser.parse("am 5", books: amos)?.bookNumber == 30)
        #expect(BibleReferenceParser.parse("am", books: amos) == nil)
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


// MARK: - Media Profile Tests

@MainActor struct MediaProfileTests {
    @Test func mediaIsAFourthProfileWithEverythingHiddenByDefault() {
        #expect(PresentationManager.profileKeys == ["bible", "song", "text", "media"])

        let profile = PresentationManager.LayoutProfile.defaultProfile(for: "media")
        // The media IS the content — no built-in text box may cover it until the
        // operator turns one on.
        #expect(profile.visibility.values.allSatisfy { $0 == false })

        // The same three generic casete every presenter gets. Media used to offer
        // a caption alone, so two thirds of the common source core had nowhere to
        // live and the presenter behaved unlike every other one.
        #expect(PresentationManager.relevantSections(for: "media") == [.verseContent, .reference, .subtitle])
    }

    @Test func showingMediaSwitchesTheOutputProfile() {
        let pm = makeTestManager()

        pm.showBibleVerse(text: "Test", reference: "Gen 1:1")
        #expect(pm.outputProfileKey == "bible")

        pm.showMedia(kind: "video", url: nil)
        // Before this, media left the previous presenter's profile live, so a
        // song's boxes stayed on screen over a full-screen video.
        #expect(pm.outputProfileKey == "media")

        pm.clearOutput()
    }
}

// MARK: - Granular Layout Observation
//
// `PresentationManager.profiles` is @ObservationIgnored; every read path
// declares which tier it depends on and every write path declares which tier it
// dirties. That classification is by hand, so it gets tested by hand: a wrong
// tier means a view that never refreshes, which no behavioural test would catch.
@MainActor struct LayoutObservationTests {

    private func ticks(_ pm: PresentationManager, _ key: String) -> (UInt32, UInt32, UInt32) {
        (pm.observationTick(profile: key),
         pm.observationTick(structureIn: key),
         pm.observationTick(chromeIn: key))
    }

    @Test func movingOneBoxLeavesItsSiblingsAlone() {
        let pm = makeTestManager()
        let verse = PresentationManager.sectionToken(.verseContent)
        let reference = PresentationManager.sectionToken(.reference)

        let siblingBefore = pm.observationTick(box: reference, in: "bible")
        let selfBefore = pm.observationTick(box: verse, in: "bible")
        let (profileBefore, structureBefore, chromeBefore) = ticks(pm, "bible")

        pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.2, y: 0.2, width: 0.3, height: 0.3),
                       for: .verseContent, in: "bible")

        // The whole point: the dragged box invalidates, the one next to it does not.
        #expect(pm.observationTick(box: verse, in: "bible") != selfBefore)
        #expect(pm.observationTick(box: reference, in: "bible") == siblingBefore)
        // Nor does the stacking order or the background change underneath.
        #expect(pm.observationTick(structureIn: "bible") == structureBefore)
        #expect(pm.observationTick(chromeIn: "bible") == chromeBefore)
        // The coarse tier still fires, so anything reading profile() stays correct.
        #expect(pm.observationTick(profile: "bible") != profileBefore)
    }

    @Test func editingOneProfileLeavesTheOthersAlone() {
        let pm = makeTestManager()
        let before = ticks(pm, "song")

        pm.setStaticText("hello", for: .reference, in: "bible")

        #expect(ticks(pm, "song") == before)
    }

    @Test func backgroundEditsDoNotInvalidateBoxes() {
        let pm = makeTestManager()
        let verse = PresentationManager.sectionToken(.verseContent)
        let boxBefore = pm.observationTick(box: verse, in: "bible")
        let structureBefore = pm.observationTick(structureIn: "bible")

        var config = pm.backgroundConfig(for: "bible")
        config.colorHex = "#123456"
        pm.setBackgroundConfig(config, for: "bible")

        #expect(pm.backgroundConfig(for: "bible").colorHex == "#123456")
        #expect(pm.observationTick(box: verse, in: "bible") == boxBefore)
        #expect(pm.observationTick(structureIn: "bible") == structureBefore)
    }

    @Test func addingABoxIsAStructuralChange() {
        let pm = makeTestManager()
        let before = pm.observationTick(structureIn: "bible")

        let box = pm.addCustomTextBox(in: "bible")

        // The container reading orderedBoxTokens has to hear about this one.
        #expect(pm.observationTick(structureIn: "bible") != before)
        #expect(pm.orderedBoxTokens(in: "bible").contains(PresentationManager.customToken(box.id)))

        // Editing that box afterwards is box-scoped again, not structural.
        let structureAfterAdd = pm.observationTick(structureIn: "bible")
        var edited = box
        edited.text = "changed"
        pm.updateCustomTextBox(edited, in: "bible")
        #expect(pm.customTextBox(id: box.id, in: "bible")?.text == "changed")
        #expect(pm.observationTick(structureIn: "bible") == structureAfterAdd)

        // ...and removing it is structural, and wakes the box's own readers so a
        // view still holding that token stops rendering a box that is gone.
        let boxTick = pm.observationTick(box: PresentationManager.customToken(box.id), in: "bible")
        pm.removeCustomTextBox(id: box.id, in: "bible")
        #expect(pm.observationTick(structureIn: "bible") != structureAfterAdd)
        #expect(pm.observationTick(box: PresentationManager.customToken(box.id), in: "bible") != boxTick)
    }

    @Test func reorderingIsAStructuralChange() {
        let pm = makeTestManager()
        let before = pm.observationTick(structureIn: "bible")
        let token = pm.orderedBoxTokens(in: "bible").first ?? ""

        pm.moveBoxTokenToEdge(token, front: true, in: "bible")

        #expect(pm.observationTick(structureIn: "bible") != before)
        #expect(pm.orderedBoxTokens(in: "bible").last == token)
    }

    @Test func undoInvalidatesEverything() {
        let pm = makeTestManager()
        let verse = PresentationManager.sectionToken(.verseContent)
        let original = pm.boxFrame(for: .verseContent, in: "bible")

        // registerLayoutUndo coalesces bursts, but a fresh manager has never
        // registered, so this first mutation always captures a snapshot.
        pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
                       for: .verseContent, in: "bible")
        #expect(pm.canUndoLayout)

        let boxBefore = pm.observationTick(box: verse, in: "bible")
        let structureBefore = pm.observationTick(structureIn: "bible")
        let chromeBefore = pm.observationTick(chromeIn: "bible")

        pm.undoLayout()

        // A snapshot restore can move anything, so every tier has to fire.
        #expect(pm.observationTick(box: verse, in: "bible") != boxBefore)
        #expect(pm.observationTick(structureIn: "bible") != structureBefore)
        #expect(pm.observationTick(chromeIn: "bible") != chromeBefore)
        #expect(pm.boxFrame(for: .verseContent, in: "bible") == original)
    }

    @Test func narrowReadsStillSeeWholesaleReplacement() {
        let pm = makeTestManager()
        let source = "bible"
        let target = "song"
        let marker = "copied"
        pm.setStaticText(marker, for: .reference, in: source)

        pm.copyProfile(from: source, to: target)

        // The box-scoped getter must not serve a stale value after the profile
        // was replaced out from under it.
        #expect(pm.staticText(for: .reference, in: target) == marker)
    }
}

// MARK: - Observation Dependencies (the real contract)
//
// The tick tests above check the bookkeeping. These check what actually matters:
// given a read, does a given edit invalidate it? `withObservationTracking` sees
// exactly what SwiftUI sees, so a getter filed under the wrong tier fails here
// even if every tick is bumped correctly.
@MainActor struct LayoutObservationDependencyTests {

    /// `onChange` is a non-isolated @Sendable closure, so the flag needs a box.
    /// It fires synchronously on whichever thread mutates — here always the main
    /// actor — so a bare Bool behind @unchecked is honest.
    private final class Flag: @unchecked Sendable { var fired = false }

    /// Runs `read`, then `edit`, and reports whether the read was invalidated.
    private func invalidates(read: () -> Void, edit: () -> Void) -> Bool {
        let flag = Flag()
        withObservationTracking { read() } onChange: { flag.fired = true }
        edit()
        return flag.fired
    }

    @Test func movingABoxDoesNotInvalidateItsSiblingsStyle() {
        let pm = makeTestManager()
        let fired = invalidates {
            _ = pm.resolvedStyle(for: .reference, in: "bible")
        } edit: {
            pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.3, y: 0.3, width: 0.2, height: 0.2),
                           for: .verseContent, in: "bible")
        }
        // resolvedStyle inherits the profile's transform. While that inheritance
        // read the whole profile, every box's style re-resolved on every drag
        // delta — the entire canvas, tens of times a second.
        #expect(fired == false)
    }

    @Test func movingABoxDoesNotInvalidateTheStackingOrder() {
        let pm = makeTestManager()
        let fired = invalidates {
            _ = pm.orderedBoxTokens(in: "bible")
        } edit: {
            pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.4, y: 0.4, width: 0.2, height: 0.2),
                           for: .verseContent, in: "bible")
        }
        // The overlay that draws every handle reads this. If it invalidates, the
        // whole box list rebuilds mid-drag and per-box granularity buys nothing.
        #expect(fired == false)
    }

    @Test func movingABoxDoesNotInvalidateTheBackground() {
        let pm = makeTestManager()
        let fired = invalidates {
            _ = pm.backgroundConfig(for: "bible")
        } edit: {
            pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                           for: .verseContent, in: "bible")
        }
        #expect(fired == false)
    }

    @Test func aBoxStillHearsAboutItsOwnEdits() {
        let pm = makeTestManager()

        // Without this, every expectation above would pass by simply never
        // observing anything.
        let ownFrame = invalidates {
            _ = pm.boxFrame(for: .verseContent, in: "bible")
        } edit: {
            pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.6, y: 0.6, width: 0.2, height: 0.2),
                           for: .verseContent, in: "bible")
        }
        #expect(ownFrame)

        let ownStyle = invalidates {
            _ = pm.resolvedStyle(for: .verseContent, in: "bible")
        } edit: {
            var style = pm.boxStyle(for: .verseContent, in: "bible")
            style.fontSize = style.fontSize + 3
            pm.setBoxStyle(style, for: .verseContent, in: "bible")
        }
        #expect(ownStyle)
    }

    @Test func chromeEditsStillReachTheBoxesThatInheritThem() {
        let pm = makeTestManager()

        // Boxes inherit the profile transform, so a chrome change MUST reach a
        // box's resolved style — the mirror image of the first test, and the
        // half that a too-narrow classification would break.
        let fired = invalidates {
            _ = pm.resolvedStyle(for: .reference, in: "bible")
        } edit: {
            var options = pm.contentOptions(for: "bible")
            options.referenceUppercase = !options.referenceUppercase
            pm.setContentOptions(options, for: "bible")
        }
        #expect(fired)
    }

    @Test func addingABoxInvalidatesTheStackingOrder() {
        let pm = makeTestManager()
        let fired = invalidates {
            _ = pm.orderedBoxTokens(in: "bible")
        } edit: {
            _ = pm.addCustomTextBox(in: "bible")
        }
        #expect(fired)
    }
}

// MARK: - Test isolation
@MainActor struct TestIsolationTests {

    /// The guard on the whole arrangement. The test host runs inside the real app
    /// bundle, so a manager built on `.standard` writes the operator's actual
    /// settings — running the suite used to overwrite real saved layouts. If
    /// someone reintroduces `UserDefaults.standard` inside PresentationManager,
    /// or builds one with `PresentationManager()` in a test, this fails.
    @Test func aTestManagerNeverWritesTheRealDefaults() {
        let key = "pm_fontSize"
        let real = UserDefaults.standard
        let before = real.object(forKey: key) as? Double

        let pm = makeTestManager()
        pm.fontSize = 123.456
        pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.5, y: 0.5, width: 0.2, height: 0.2),
                       for: .verseContent, in: "bible")
        pm.persistProfilesNow()

        #expect(real.object(forKey: key) as? Double == before)
        #expect(pm.defaults.double(forKey: key) == 123.456)
        #expect(pm.defaults.data(forKey: "pm_layoutProfiles") != nil)
    }

    /// Two managers must not see each other — that independence is what makes the
    /// suite order-insensitive.
    @Test func separateTestManagersDoNotShareState() {
        let a = makeTestManager()
        let b = makeTestManager()

        a.setStaticText("only-in-a", for: .reference, in: "bible")

        #expect(a.staticText(for: .reference, in: "bible") == "only-in-a")
        #expect(b.staticText(for: .reference, in: "bible") != "only-in-a")
    }
}

// MARK: - Font picker laziness
//
// There are ~200 installed font families and the Text tab holds two pickers over
// them. A SwiftUI Picker builds every item the moment it appears, which is what
// made switching to that tab lag. These lock the deferral in: if someone swaps
// the control back for an eager Picker, or stops collapsing after close, the
// item counts here change.
@MainActor struct FontFamilyPickerTests {

    private final class Box: @unchecked Sendable { var value: String; init(_ v: String) { value = v } }

    private func makePicker(_ box: Box) -> FontFamilyPicker {
        FontFamilyPicker(
            leading: [("", "Global"), ("System", "System")],
            selection: Binding(get: { box.value }, set: { box.value = $0 })
        )
    }

    private func attached(_ picker: FontFamilyPicker) -> (FontFamilyPicker.Coordinator, NSPopUpButton, NSMenu) {
        let coordinator = picker.makeCoordinator()
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        let menu = NSMenu()
        menu.delegate = coordinator
        button.menu = menu
        coordinator.attach(button)
        return (coordinator, button, menu)
    }

    @Test func theMenuHoldsOnlyTheVisibleItemUntilItIsOpened() {
        let box = Box("Helvetica")
        let (coordinator, button, menu) = attached(makePicker(box))

        // Closed: exactly the one item the control shows. This is the whole
        // point — enumerating the families costs ~268 ms on first call, so it
        // must not happen just because the Text tab appeared.
        #expect(menu.numberOfItems == 1)
        #expect(menu.item(at: 0)?.title == "Helvetica")

        // Opening builds the lot: the 2 leading options + every family.
        coordinator.menuWillOpen(menu)
        coordinator.menuNeedsUpdate(menu)
        #expect(menu.numberOfItems == 2 + FontFamilies.all.count)
        #expect(button.indexOfSelectedItem >= 0)
    }

    @Test func pickingAFamilyWritesThroughTheBinding() throws {
        let box = Box("Helvetica")
        let (coordinator, button, menu) = attached(makePicker(box))

        coordinator.menuWillOpen(menu)
        coordinator.menuNeedsUpdate(menu)
        let family = try #require(FontFamilies.all.first)
        button.selectItem(at: 2)          // the first real family
        coordinator.selectionChanged(button)

        #expect(box.value == family)
    }

    @Test func anInheritedSelectionShowsItsLeadingTitle() {
        // "" is the inherit sentinel — the closed control must read "Global",
        // not an empty button.
        let box = Box("")
        let (_, _, menu) = attached(makePicker(box))

        #expect(menu.numberOfItems == 1)
        #expect(menu.item(at: 0)?.title == "Global")
    }
}

// MARK: - Font family enumeration
@MainActor struct FontFamiliesTests {

    /// ~268 ms on the first call, 0.1 ms after — so it must be computed once and
    /// never from a view initialiser. This asserts the shape, not the timing.
    @Test func theListIsNonEmptyStableAndSorted() {
        let first = FontFamilies.all
        #expect(!first.isEmpty)
        #expect(first == first.sorted())
        // System-internal families (".AppleSystemUIFont") are hidden, matching
        // what NSFontManager.availableFontFamilies used to return.
        #expect(first.allSatisfy { !$0.hasPrefix(".") })
        // Same array object semantics on a second read: computed once.
        #expect(FontFamilies.all == first)
    }

    @Test func warmingIsSafeToCallRepeatedly() {
        FontFamilies.warm()
        FontFamilies.warm()
        #expect(!FontFamilies.all.isEmpty)
    }
}

// MARK: - Slider snapping
//
// `Slider(value:in:step:)` renders an NSSlider with one tick mark PER STEP, and
// that dominated the Theme Editor: eight sliders cost ~2400 ms with `step:` and
// ~60 ms with the value snapped in the binding instead. A `0...1 step: 0.01`
// slider asks AppKit for a hundred tick marks. These lock the replacement's
// behaviour, since the whole point is that it snaps exactly like `step:` did.
@MainActor struct SnappedBindingTests {

    private final class Box: @unchecked Sendable { var v: Double; init(_ x: Double) { v = x } }

    private func binding(_ box: Box) -> Binding<Double> {
        Binding(get: { box.v }, set: { box.v = $0 })
    }

    @Test func itRoundsToTheNearestMultiple() {
        let box = Box(0)
        let b = binding(box).snapped(2)

        b.wrappedValue = 31.4
        #expect(box.v == 32)
        b.wrappedValue = 30.9
        #expect(box.v == 30)
        b.wrappedValue = 61
        #expect(box.v == 62)
    }

    @Test func itHandlesFractionalStepsAndNegatives() {
        let box = Box(0)
        #expect(binding(box).snapped(0.5).wrappedValue == 0)

        binding(box).snapped(0.5).wrappedValue = -1.7
        #expect(box.v == -1.5)

        // The per-box styles use -1 as the "inherit" sentinel; snapping must not
        // drift it, or a customised box would silently stop inheriting.
        binding(box).snapped(0.1).wrappedValue = -1.0
        #expect(box.v == -1.0)
    }

    @Test func aZeroStepIsAPassthroughRatherThanADivideByZero() {
        let box = Box(0)
        binding(box).snapped(0).wrappedValue = 3.7
        #expect(box.v == 3.7)
    }

    @Test func anUnchangedValueIsNotWrittenBack() {
        // These bindings sit on properties that persist in didSet, so a redundant
        // write is a redundant UserDefaults hit on every drag frame.
        let box = Box(10)
        var writes = 0
        let counting = Binding<Double>(get: { box.v }, set: { box.v = $0; writes += 1 })

        counting.snapped(2).wrappedValue = 10.4   // snaps to 10, already 10
        #expect(writes == 0)

        counting.snapped(2).wrappedValue = 11.4   // snaps to 12
        #expect(writes == 1)
        #expect(box.v == 12)
    }
}

// MARK: - Auto-fit cache
//
// The fit key quantises geometry so a gesture's worth of near-identical requests
// collapses onto one entry: measured 4.4 ms per delta while resizing a box before,
// 1.6 ms after, and a whole resize drag from 177 ms to 65 ms. Quantisation is only
// sound because it rounds in the SAFE direction — box and cap DOWN, padding and
// line spacing UP — so a reused fit always belongs to a box at least as tight as
// the real one. These tests hold that property.
@MainActor struct AutoFitCacheTests {

    private let verse = """
    Fiindcă atât de mult a iubit Dumnezeu lumea, că a dat pe singurul Lui Fiu, \
    pentru ca oricine crede în El să nu piară, ci să aibă viața veșnică.
    """

    private func fit(_ pm: PresentationManager, w: Double, h: Double,
                     max: CGFloat = 60, padding: CGFloat = 20) -> CGFloat {
        pm.fittedVerseFontSize(text: verse, boxSize: CGSize(width: w, height: h),
                               maxSize: max, padding: padding,
                               fontName: "System", lineSpacing: 1.2)
    }

    @Test func itIsDeterministic() {
        let pm = makeTestManager()
        pm.autoFitVerseFont = true
        let a = fit(pm, w: 900, h: 240)

        // A second manager has a cold cache: the answer must come from the inputs,
        // not from whichever real size happened to populate the entry first.
        let other = makeTestManager()
        other.autoFitVerseFont = true
        #expect(fit(other, w: 900, h: 240) == a)
        #expect(fit(pm, w: 900, h: 240) == a)
    }

    @Test func subPointDifferencesShareOneAnswer() {
        let pm = makeTestManager()
        pm.autoFitVerseFont = true
        let base = fit(pm, w: 900, h: 240)

        // Within one point of box: the same entry, which is what makes a resize
        // gesture cheap.
        #expect(fit(pm, w: 900, h: 240.4) == base)
        #expect(fit(pm, w: 900.9, h: 240.9) == base)
    }

    @Test func aTighterBoxNeverYieldsALargerFont() {
        let pm = makeTestManager()
        pm.autoFitVerseFont = true

        // Monotonic in height, which is what "safe direction" means in practice:
        // rounding the box down can only ever shrink the answer.
        var previous = fit(pm, w: 900, h: 120)
        for h in stride(from: 140.0, through: 400.0, by: 20.0) {
            let current = fit(pm, w: 900, h: h)
            #expect(current >= previous)
            previous = current
        }
    }

    @Test func theResultStaysWithinItsBounds() {
        let pm = makeTestManager()
        pm.autoFitVerseFont = true

        // Never above the cap, never below the 10 pt floor.
        #expect(fit(pm, w: 900, h: 240, max: 60) <= 60)
        #expect(fit(pm, w: 200, h: 30, max: 60) >= 10)
        // A box with room to spare returns the cap untouched.
        #expect(fit(pm, w: 3000, h: 2000, max: 40) == 40)
    }

    @Test func autoFitOffIsAPassthrough() {
        let pm = makeTestManager()
        pm.autoFitVerseFont = false
        #expect(fit(pm, w: 100, h: 20, max: 72) == 72)
    }

    @Test func aHotEntrySurvivesAFloodOfNewOnes() {
        let pm = makeTestManager()
        pm.autoFitVerseFont = true
        let hot = fit(pm, w: 900, h: 240)

        // Eviction used to be removeAll, so one resize gesture's junk keys threw
        // away the entries the live output was using. Oldest-first keeps this one.
        for i in 0..<600 { _ = fit(pm, w: 900, h: 300 + Double(i)) }

        #expect(fit(pm, w: 900, h: 240) == hot)
    }
}

// MARK: - Module → layout profile
//
// Media became a layout profile long after the two switches that mapped module to
// profile were written, and neither picked it up — so opening the Theme Editor
// from Media edited whichever profile happened to be last touched. The mapping now
// lives on SidebarItem, and these hold it exhaustively so the next module added
// cannot slip through the same way.
@MainActor struct SidebarProfileMappingTests {

    @Test func everyContentModuleWithAProfileMapsToARealOne() {
        for item in AppState.SidebarItem.contentItems {
            guard let key = item.layoutProfileKey else { continue }
            #expect(PresentationManager.profileKeys.contains(key),
                    "\(item.rawValue) maps to '\(key)', which is not a profile")
        }
    }

    @Test func mediaEditsTheMediaProfile() {
        #expect(AppState.SidebarItem.media.layoutProfileKey == "media")
        #expect(AppState.SidebarItem.bible.layoutProfileKey == "bible")
        #expect(AppState.SidebarItem.songs.layoutProfileKey == "song")
        #expect(AppState.SidebarItem.customSlides.layoutProfileKey == "text")
    }

    @Test func scheduleAndUtilitiesOwnNoProfile() {
        // Schedule mixes content types — each item renders with its own profile, so
        // entering it must NOT repoint the editor.
        #expect(AppState.SidebarItem.schedule.layoutProfileKey == nil)
        for item in AppState.SidebarItem.utilityItems {
            #expect(item.layoutProfileKey == nil)
        }
    }

    @Test func everyProfileIsReachableFromSomeModule() {
        // The other direction: a profile no module opens would be unreachable in
        // the editor except through the header picker.
        let reachable = Set(AppState.SidebarItem.allCases.compactMap(\.layoutProfileKey))
        for key in PresentationManager.profileKeys {
            #expect(reachable.contains(key), "no module opens the '\(key)' profile")
        }
    }

    @Test func theMediaProfileShipsItsTextBoxesHidden() {
        // The media is the content, so every built-in TEXT box starts hidden —
        // they are overlays. It does carry one media casetă: the live one, full
        // bleed, which is what the module's media renders into.
        let profile = PresentationManager.LayoutProfile.defaultProfile(for: "media")
        for section in TextBoxSection.allCases {
            #expect(profile.visibility[section.rawValue] != true,
                    "\(section.rawValue) should start hidden in the media profile")
        }
        #expect(profile.mediaBoxes.count == 1)
        #expect(profile.mediaBoxes.first?.sourceRaw == "live")
        #expect(PresentationManager.relevantSections(for: "media") == [.verseContent, .reference, .subtitle])
    }
}

/// What a presenter LOOKS like, read off the manager rather than off a payload.
///
/// Deliberately a second, independent listing of the same fields
/// `captureThemePayload` reads. That duplication is the point: comparing two
/// payloads only proves the file survived the trip, while comparing two managers
/// proves capture and apply are BOTH complete. A field that capture writes and
/// apply forgets is invisible to the first and caught by the second.
@MainActor struct ThemeLookSnapshot: Equatable {
    var fontSize = 0.0, fontName = "", textColorHex = "", textAlignmentRaw = ""
    var lineSpacing = 0.0, padding = 0.0
    var shadowEnabled = false, shadowRadius = 0.0, shadowColorHex = ""
    var letterTracking = 0.0
    var wocStyleEnabled = false, wocColorHex = ""
    var autoFitVerseFont = false
    var globalWeightRaw = "", globalVAlignRaw = "", globalTextOpacity = 0.0
    var backgroundEnabled = false, backgroundStaysOnHide = false
    var backgroundColorHex = "", backgroundOpacity = 0.0
    var useBackgroundImage = false, backgroundMediaTypeRaw = ""
    var profiles: [String: PresentationManager.LayoutProfile] = [:]

    init(_ pm: PresentationManager) {
        fontSize = pm.fontSize; fontName = pm.fontName
        textColorHex = pm.textColorHex
        textAlignmentRaw = "\(pm.textAlignment)"
        lineSpacing = pm.lineSpacing; padding = pm.padding
        shadowEnabled = pm.shadowEnabled; shadowRadius = pm.shadowRadius
        shadowColorHex = pm.shadowColorHex
        letterTracking = pm.letterTracking
        wocStyleEnabled = pm.wocStyleEnabled; wocColorHex = pm.wocColorHex
        autoFitVerseFont = pm.autoFitVerseFont
        globalWeightRaw = pm.globalWeightRaw; globalVAlignRaw = pm.globalVAlignRaw
        globalTextOpacity = pm.globalTextOpacity
        backgroundEnabled = pm.backgroundEnabled
        backgroundStaysOnHide = pm.backgroundStaysOnHide
        backgroundColorHex = pm.backgroundColorHex
        backgroundOpacity = pm.backgroundOpacity
        useBackgroundImage = pm.useBackgroundImage
        backgroundMediaTypeRaw = pm.backgroundMediaTypeRaw
        // Bookmarks legitimately differ: export strips them and import rebuilds
        // them against the copied files, so a bookmark comparison would fail on
        // a difference that is the format working correctly.
        profiles = pm.profiles.mapValues { profile in
            var stripped = profile
            stripped.background.imageBookmark = nil
            for index in stripped.mediaBoxes.indices { stripped.mediaBoxes[index].bookmarkData = nil }
            return stripped
        }
    }
}

// MARK: - Theme export / import round trip
//
// "Exports fully and imports fully" is a claim that has to be demonstrated, not
// asserted: a theme carries all four presenters' profiles, every box, every style,
// backgrounds, transitions, colours and scopes. A field added to LayoutProfile and
// forgotten in ThemePayload would vanish silently on export.
@MainActor struct ThemeRoundTripTests {

    private func tempPackage() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-roundtrip-\(UUID().uuidString).tptheme")
    }

    /// Every payload-level global set away from its default.
    ///
    /// `decorate` only ever touched the per-presenter profiles, which left all
    /// twenty-four globals sitting at their defaults on BOTH sides of the
    /// comparison — the payload test passed them for free. `assertFullyCustomized`
    /// in `theFixtureLeavesNothingAtItsDefault` now keeps this honest.
    private func decorateGlobals(_ pm: PresentationManager) {
        pm.fontSize = 96
        pm.fontName = "Georgia"
        pm.textColorHex = "FFEEDD"
        pm.textAlignment = .leading
        pm.lineSpacing = 14
        pm.padding = 72
        pm.shadowEnabled = false
        pm.shadowRadius = 9
        pm.shadowColorHex = "112233"
        pm.letterTracking = 1.5
        pm.wocStyleEnabled = false
        pm.wocColorHex = "CC2200"
        pm.autoFitVerseFont = true
        pm.globalWeightRaw = "bold"
        pm.globalVAlignRaw = "top"
        pm.globalTextOpacity = 0.85
        pm.backgroundEnabled = true
        pm.backgroundStaysOnHide = false
        pm.backgroundColorHex = "0A0B0C"
        pm.backgroundOpacity = 0.55   // NOT 0.7 — that is PresentationDefaults.backgroundOpacity
        pm.useBackgroundImage = true
        pm.backgroundMediaTypeRaw = "video"
    }

    /// Marks every profile distinctly so a cross-profile mix-up cannot pass.
    private func decorate(_ pm: PresentationManager) {
        for (i, key) in PresentationManager.profileKeys.enumerated() {
            pm.mutateProfile(key) { p in
                p.frames[TextBoxSection.verseContent.rawValue] =
                    PresentationManager.TextBoxFrame(x: 0.1 + Double(i) / 20.0, y: 0.2,
                                                     width: 0.5, height: 0.3)
                p.staticTexts[TextBoxSection.reference.rawValue] = "static-\(key)"
                p.sources[TextBoxSection.reference.rawValue] = "static"
                p.displayOn[TextBoxSection.reference.rawValue] = "first"
                p.boxColors["section:" + TextBoxSection.reference.rawValue] = "#A1B2C\(i)"
                p.transitionInRaw = "zoomIn"
                p.transitionChangeRaw = "blur"
                p.transitionOutRaw = "fall"
                p.transitionInDuration = 0.4 + Double(i) / 10.0
                p.background.enabled = true
                p.background.showColor = true
                p.background.colorHex = "11223\(i)"
                p.background.opacity = 0.5
                p.options.textTransformRaw = "upper"

                var custom = PresentationManager.CustomTextBox()
                custom.text = "custom-\(key)"
                custom.frame = PresentationManager.TextBoxFrame(x: 0.3, y: 0.4, width: 0.2, height: 0.1)
                custom.style.isCustomized = true
                custom.style.fontSize = 44
                p.customTextBoxes = [custom]

                var media = PresentationManager.MediaBox()
                media.fileName = "clip-\(key).mp4"
                media.mediaTypeRaw = "video"
                media.frame = PresentationManager.TextBoxFrame(x: 0.05, y: 0.05, width: 0.3, height: 0.2)
                media.opacity = 0.8
                p.mediaBoxes = [media]

                p.boxOrder = ["media:" + media.id.uuidString,
                              "section:" + TextBoxSection.reference.rawValue,
                              "custom:" + custom.id.uuidString]

                // The remaining LayoutProfile fields, which nothing set before.
                p.visibility[TextBoxSection.subtitle.rawValue] = false
                var style = PresentationManager.BoxTextStyle()
                style.isCustomized = true
                style.fontSize = 30 + Double(i)
                p.styles[TextBoxSection.verseContent.rawValue] = style
                p.sourceFormats[TextBoxSection.reference.rawValue] = "short"
                p.transitionDurationOverride = 0.7
                p.transitionChangeDuration = 0.25 + Double(i) / 10.0
                p.transitionOutDuration = 0.9
                var boxTransition = PresentationManager.BoxTransition()
                boxTransition.isCustomized = true
                boxTransition.inRaw = "slideUp"
                boxTransition.changeRaw = "fade"
                boxTransition.outRaw = "fall"
                boxTransition.delay = 0.2
                boxTransition.duration = 0.6
                p.boxTransitionOverrides["section:" + TextBoxSection.reference.rawValue] = boxTransition
                p.removedSections = [TextBoxSection.chords.rawValue]
                // Deliberately removed, which is the ONLY thing that stops
                // `ensureLiveMediaBox` re-seeding the casetă when the theme is
                // applied. Without it the media profile legitimately gains a box
                // on apply and the comparison would be about healing, not about
                // whether the flag itself survived.
                p.liveMediaRemoved = true
            }
        }
    }

    @Test func everyProfileSurvivesExportAndImport() throws {
        let source = makeTestManager()
        decorate(source)
        _ = source.saveCurrentAsTheme(named: "RoundTrip")
        let saved = try #require(source.themes.first(where: { $0.name == "RoundTrip" }))

        let package = tempPackage()
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        // A DIFFERENT manager, so nothing can leak through shared state.
        let target = makeTestManager()
        let imported = try target.importTheme(from: package)

        #expect(imported.name == "RoundTrip")
        for key in PresentationManager.profileKeys {
            let a = try #require(saved.payload.profiles[key], "exported \(key)")
            let b = try #require(imported.payload.profiles[key], "imported \(key)")

            #expect(a.frames == b.frames, "frames differ for \(key)")
            #expect(a.staticTexts == b.staticTexts, "static texts differ for \(key)")
            #expect(a.sources == b.sources, "sources differ for \(key)")
            #expect(a.displayOn == b.displayOn, "slide scopes differ for \(key)")
            #expect(a.boxColors == b.boxColors, "box colours differ for \(key)")
            #expect(a.boxOrder == b.boxOrder, "stacking order differs for \(key)")
            #expect(a.options == b.options, "content options differ for \(key)")
            #expect(a.transitionInRaw == b.transitionInRaw, "in transition differs for \(key)")
            #expect(a.transitionChangeRaw == b.transitionChangeRaw)
            #expect(a.transitionOutRaw == b.transitionOutRaw)
            #expect(a.transitionInDuration == b.transitionInDuration)

            // Backgrounds: everything but the bookmark, which is re-made on import
            // against the file copied into the container.
            #expect(a.background.enabled == b.background.enabled)
            #expect(a.background.showColor == b.background.showColor)
            #expect(a.background.colorHex == b.background.colorHex, "bg colour differs for \(key)")
            #expect(a.background.opacity == b.background.opacity)

            #expect(a.customTextBoxes.count == b.customTextBoxes.count, "custom box count for \(key)")
            let ca = try #require(a.customTextBoxes.first), cb = try #require(b.customTextBoxes.first)
            #expect(ca.id == cb.id, "custom box identity must survive — boxOrder refers to it")
            #expect(ca.text == cb.text)
            #expect(ca.frame == cb.frame)
            #expect(ca.style.fontSize == cb.style.fontSize)

            #expect(a.mediaBoxes.count == b.mediaBoxes.count, "media box count for \(key)")
            let ma = try #require(a.mediaBoxes.first), mb = try #require(b.mediaBoxes.first)
            #expect(ma.id == mb.id, "media box identity must survive")
            #expect(ma.fileName == mb.fileName)
            #expect(ma.mediaTypeRaw == mb.mediaTypeRaw)
            #expect(ma.frame == mb.frame)
            #expect(ma.opacity == mb.opacity)
        }
    }

    /// What a theme actually promises: the presenter ends up LOOKING the same on
    /// the other machine.
    ///
    /// `theWholePayloadIsPreserved` stops one step short of that — it compares
    /// the saved payload with the imported payload and never applies either, so
    /// `applyPayload` is not under test at all. A field that `captureThemePayload`
    /// writes and `applyPayload` forgets to read back passes it every time.
    /// Going manager → capture → export → import → apply → manager closes both
    /// halves at once.
    @Test func applyingAnImportedThemeRestoresTheManagerItCameFrom() throws {
        let source = makeTestManager()
        decorateGlobals(source)
        decorate(source)
        _ = source.saveCurrentAsTheme(named: "Exact")
        let saved = try #require(source.themes.first(where: { $0.name == "Exact" }))
        let before = ThemeLookSnapshot(source)

        let package = tempPackage()
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        let target = makeTestManager()
        let imported = try target.importTheme(from: package)
        target.applyTheme(id: imported.id)

        #expect(ThemeLookSnapshot(target) == before)
    }

    /// G3 — the fixture itself. Without this, the two tests above keep passing as
    /// `ThemePayload` and `LayoutProfile` grow fields nobody decorates.
    @Test func theFixtureLeavesNothingAtItsDefault() throws {
        let pm = makeTestManager()
        decorateGlobals(pm)
        decorate(pm)
        _ = pm.saveCurrentAsTheme(named: "Fixture")
        let payload = try #require(pm.themes.first(where: { $0.name == "Fixture" })).payload

        assertFullyCustomized(
            payload, comparedTo: PresentationManager.ThemePayload(),
            // The bookmark is UserDefaults state, not a look; the theme tests
            // deliberately reference no image, and `importReportsAssetsItCouldNotFind`
            // covers the asset path.
            exempt: ["backgroundImageBookmark"],
            label: "ThemePayload")

        for key in PresentationManager.profileKeys {
            let profile = try #require(payload.profiles[key], "profile \(key)")
            assertFullyCustomized(
                profile, comparedTo: PresentationManager.LayoutProfile(),
                label: "LayoutProfile[\(key)]")
        }
    }

    /// G4 — plan §4.4. `importTheme` has no identity check at all, so the same
    /// package opened twice is two themes. §4.2 settles what it should do: the
    /// payload already carries a stable theme `id`, so same id means Replace —
    /// re-importing a package IS updating it.
    @Test
    func importingTheSameThemeTwiceIsANoOp() throws {
        let source = makeTestManager()
        decorate(source)
        _ = source.saveCurrentAsTheme(named: "Galaxie")
        let saved = try #require(source.themes.first(where: { $0.name == "Galaxie" }))
        let package = tempPackage()
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        let target = makeTestManager()
        let baseline = target.themes.count
        _ = try target.importTheme(from: package)
        _ = try target.importTheme(from: package)

        #expect(target.themes.count == baseline + 1,
                "the same package imported twice produced \(target.themes.map(\.name).suffix(3))")
    }

    @Test func theWholePayloadIsPreserved() throws {
        // The blunt instrument, and the one that catches a NEW LayoutProfile field
        // nobody wired into the archive: compare the encoded payloads outright.
        let source = makeTestManager()
        decorate(source)
        _ = source.saveCurrentAsTheme(named: "Exact")
        let saved = try #require(source.themes.first(where: { $0.name == "Exact" }))

        let package = tempPackage()
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        let target = makeTestManager()
        let imported = try target.importTheme(from: package)

        // Bookmarks legitimately differ: export strips them, import re-creates them
        // against the copied files. Clear them and everything else must match.
        func normalised(_ p: PresentationManager.ThemePayload) -> Data? {
            var payload = p
            payload.backgroundImageBookmark = nil
            for (key, var prof) in payload.profiles {
                prof.background.imageBookmark = nil
                for i in prof.mediaBoxes.indices { prof.mediaBoxes[i].bookmarkData = nil }
                payload.profiles[key] = prof
            }
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            return try? enc.encode(payload)
        }

        let a = try #require(normalised(saved.payload))
        let b = try #require(normalised(imported.payload))
        #expect(a == b, "payload changed across export/import")
    }

    @Test func importReportsAssetsItCouldNotFind() throws {
        let source = makeTestManager()
        _ = source.saveCurrentAsTheme(named: "NoAssets")
        let saved = try #require(source.themes.first(where: { $0.name == "NoAssets" }))
        let package = tempPackage()
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        let target = makeTestManager()
        _ = try target.importTheme(from: package)
        // Nothing was referenced, so nothing may be reported missing — the list
        // must not accumulate stale entries from an earlier import either.
        #expect(target.lastThemeImportSkippedAssets.isEmpty)
    }
}

// MARK: - Copy layout between presenters
@MainActor struct CopyProfileTests {

    @Test func sectionsTheTargetCannotShowAreDropped() {
        let pm = makeTestManager()
        // Bible has a translation box; Songs does not.
        pm.setStaticText("translation", for: .translationName, in: "bible")
        pm.setBoxFrame(PresentationManager.TextBoxFrame(x: 0.4, y: 0.4, width: 0.2, height: 0.1),
                       for: .translationName, in: "bible")

        pm.copyProfile(from: "bible", to: "song")

        // Carried across, it would sit in the theme and reappear if that layout
        // were copied onward to a presenter that DOES have the section.
        let song = pm.profile("song")
        #expect(song.staticTexts[TextBoxSection.translationName.rawValue] == nil)
        #expect(song.frames[TextBoxSection.translationName.rawValue] == nil)
        #expect(!song.boxOrder.contains("section:" + TextBoxSection.translationName.rawValue))
    }

    @Test func sectionsTheTargetDoesHaveComeAcross() {
        let pm = makeTestManager()
        pm.setStaticText("carried", for: .reference, in: "bible")
        pm.copyProfile(from: "bible", to: "song")
        #expect(pm.staticText(for: .reference, in: "song") == "carried")
    }

    @Test func customAndMediaBoxesAlwaysCarry() {
        let pm = makeTestManager()
        let custom = pm.addCustomTextBox(in: "bible")
        pm.copyProfile(from: "bible", to: "media")
        // They belong to no fixed slot, so no presenter can reject them.
        #expect(pm.customTextBox(id: custom.id, in: "media") != nil)
    }

    @Test func theTargetKeepsItsOwnDefaultsForWhatItDidNotReceive() {
        let pm = makeTestManager()
        pm.copyProfile(from: "bible", to: "media")
        // Media ships every text box hidden; copying a Bible layout onto it must not
        // silently un-hide boxes by leaving their visibility unset.
        for section in PresentationManager.relevantSections(for: "media") {
            #expect(pm.profile("media").visibility[section.rawValue] != nil,
                    "\(section.rawValue) lost its visibility entry")
        }
    }

    @Test func copyingOntoItselfIsANoOp() {
        let pm = makeTestManager()
        pm.setStaticText("keep", for: .reference, in: "bible")
        pm.copyProfile(from: "bible", to: "bible")
        #expect(pm.staticText(for: .reference, in: "bible") == "keep")
    }
}

// MARK: - Deleting and restoring built-in casetes
//
// Built-ins used to only ever hide, so the trash on them was a lie. They delete
// now, which is only safe because they come back with their layout intact — these
// hold both halves of that bargain.
@MainActor struct RemovableSectionTests {

    @Test func aDeletedSectionLeavesThePresentersList() {
        let pm = makeTestManager()
        let token = PresentationManager.sectionToken(.reference)
        #expect(pm.orderedBoxTokens(in: "bible").contains(token))

        pm.removeSection(.reference, in: "bible")

        #expect(!pm.orderedBoxTokens(in: "bible").contains(token))
        #expect(pm.isSectionRemoved(.reference, in: "bible"))
    }

    @Test func deletedIsNotTheSameAsHidden() {
        let pm = makeTestManager()
        pm.setSectionVisible(false, for: .reference, in: "bible")

        // Hidden: still a casetă, still listed, the eye brings it back.
        #expect(pm.orderedBoxTokens(in: "bible").contains(PresentationManager.sectionToken(.reference)))
        #expect(!pm.isSectionRemoved(.reference, in: "bible"))
        #expect(pm.restorableSections(in: "bible").isEmpty)
    }

    @Test func restoringBringsTheLayoutBackRatherThanResettingIt() {
        let pm = makeTestManager()
        let frame = PresentationManager.TextBoxFrame(x: 0.33, y: 0.44, width: 0.2, height: 0.1)
        pm.setBoxFrame(frame, for: .reference, in: "bible")
        pm.setStaticText("keep me", for: .reference, in: "bible")

        pm.removeSection(.reference, in: "bible")
        pm.restoreSection(.reference, in: "bible")

        #expect(pm.boxFrame(for: .reference, in: "bible") == frame)
        #expect(pm.staticText(for: .reference, in: "bible") == "keep me")
        // And visible, or it would return looking broken.
        #expect(pm.isSectionVisible(.reference, in: "bible"))
    }

    @Test func onlyDeletedSectionsAreOfferedBack() {
        let pm = makeTestManager()
        #expect(pm.restorableSections(in: "bible").isEmpty)

        pm.removeSection(.subtitle, in: "bible")
        #expect(pm.restorableSections(in: "bible") == [.subtitle])

        pm.restoreSection(.subtitle, in: "bible")
        #expect(pm.restorableSections(in: "bible").isEmpty)
    }

    @Test func aPresenterNeverOffersASectionItDoesNotHave() {
        let pm = makeTestManager()
        // Songs has no Bible translation box, so removing it must not make it
        // appear in Songs' restore menu.
        pm.removeSection(.translationName, in: "song")
        #expect(!pm.restorableSections(in: "song").contains(.translationName))
    }

    @Test func removalIsPerPresenter() {
        let pm = makeTestManager()
        pm.removeSection(.reference, in: "bible")
        #expect(pm.orderedBoxTokens(in: "song")
            .contains(PresentationManager.sectionToken(.reference)))
    }

    @Test func removalSurvivesAThemeRoundTrip() throws {
        let source = makeTestManager()
        source.removeSection(.subtitle, in: "bible")
        _ = source.saveCurrentAsTheme(named: "Removed")
        let saved = try #require(source.themes.first(where: { $0.name == "Removed" }))

        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-removed-\(UUID().uuidString).tptheme")
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        let target = makeTestManager()
        let imported = try target.importTheme(from: package)
        #expect(imported.payload.profiles["bible"]?.removedSections == [TextBoxSection.subtitle.rawValue])
    }
}

// MARK: - Per-presenter themes (B1)
//
// Off by default so nothing changes for anyone who does not ask for it. On, each
// presenter resolves its own theme and anything unassigned still falls back to the
// global one — turning the switch on is never a cliff.
@MainActor struct PerPresenterThemeTests {

    private func twoThemes(_ pm: PresentationManager) -> (UUID, UUID) {
        pm.setStaticText("look-A", for: .reference, in: "bible")
        pm.setStaticText("look-A", for: .reference, in: "song")
        let a = pm.saveCurrentAsTheme(named: "A").id
        pm.setStaticText("look-B", for: .reference, in: "bible")
        pm.setStaticText("look-B", for: .reference, in: "song")
        let b = pm.saveCurrentAsTheme(named: "B").id
        return (a, b)
    }

    @Test func unifiedIsTheDefaultAndBehavesAsBefore() {
        let pm = makeTestManager()
        #expect(pm.usesPerPresenterThemes == false)
        let (a, _) = twoThemes(pm)

        pm.applyTheme(id: a)

        // One theme dressed every presenter, and it is the global one.
        #expect(pm.activeThemeID == a)
        #expect(pm.staticText(for: .reference, in: "bible") == "look-A")
        #expect(pm.staticText(for: .reference, in: "song") == "look-A")
        #expect(pm.themeAssignments.isEmpty)
    }

    @Test func unassignedPresentersFallBackToTheGlobalTheme() {
        let pm = makeTestManager()
        let (a, b) = twoThemes(pm)
        pm.activeThemeID = a
        pm.usesPerPresenterThemes = true
        pm.themeAssignments["song"] = b

        #expect(pm.resolvedThemeID(for: "song") == b)
        #expect(pm.resolvedThemeID(for: "bible") == a)   // no assignment → global
        #expect(pm.resolvedThemeID(for: "media") == a)
    }

    @Test func theSwitchOnlyChangesResolutionNotStoredState() {
        let pm = makeTestManager()
        let (a, b) = twoThemes(pm)
        pm.activeThemeID = a
        pm.themeAssignments["song"] = b

        // Off: assignments are remembered but ignored, so flipping back and forth
        // cannot lose a mixed setup.
        pm.usesPerPresenterThemes = false
        #expect(pm.resolvedThemeID(for: "song") == a)
        pm.usesPerPresenterThemes = true
        #expect(pm.resolvedThemeID(for: "song") == b)
    }

    // 1a
    @Test func inPerPresenterModeApplyingDressesOnlyTheActivePresenter() {
        let pm = makeTestManager()
        let (a, b) = twoThemes(pm)
        pm.applyTheme(id: a)                 // unified: everyone on A
        pm.usesPerPresenterThemes = true
        pm.activeProfileKey = "song"

        pm.applyTheme(id: b)

        #expect(pm.staticText(for: .reference, in: "song") == "look-B")
        #expect(pm.staticText(for: .reference, in: "bible") == "look-A", "Bible must not move")
        #expect(pm.themeAssignments["song"] == b)
        #expect(pm.themeAssignments["bible"] == nil)
        #expect(pm.activeThemeID == a, "the global theme is unchanged")
    }

    @Test func aMixedLookIsWhatTheFeatureIsFor() {
        let pm = makeTestManager()
        let (a, b) = twoThemes(pm)
        pm.usesPerPresenterThemes = true

        pm.applyTheme(id: a, toProfileOnly: "bible")
        pm.applyTheme(id: b, toProfileOnly: "song")

        #expect(pm.staticText(for: .reference, in: "bible") == "look-A")
        #expect(pm.staticText(for: .reference, in: "song") == "look-B")
    }

    @Test func applyingAThemeThatLacksThePresenterLeavesItAlone() {
        let pm = makeTestManager()
        pm.setStaticText("mine", for: .reference, in: "media")
        var partial = pm.saveCurrentAsTheme(named: "Partial")
        partial.payload.profiles["media"] = nil
        if let i = pm.themes.firstIndex(where: { $0.id == partial.id }) { pm.themes[i] = partial }

        pm.applyTheme(id: partial.id, toProfileOnly: "media")

        #expect(pm.staticText(for: .reference, in: "media") == "mine")
        #expect(pm.themeAssignments["media"] == nil, "a no-op must not claim the pin")
    }

    @Test func clearingAnAssignmentReturnsToTheGlobalTheme() {
        let pm = makeTestManager()
        let (a, b) = twoThemes(pm)
        pm.activeThemeID = a
        pm.usesPerPresenterThemes = true
        pm.themeAssignments["song"] = b

        pm.clearThemeAssignment(for: "song")
        #expect(pm.resolvedThemeID(for: "song") == a)
    }

    // 4b
    @Test func aThemeAPresenterIsPinnedToCannotBeDeleted() {
        let pm = makeTestManager()
        let (a, b) = twoThemes(pm)
        pm.usesPerPresenterThemes = true
        pm.themeAssignments["song"] = b
        pm.themeAssignments["text"] = b

        let blockers = pm.deleteTheme(id: b)

        #expect(blockers == ["song", "text"], "must name who is using it")
        #expect(pm.themes.contains { $0.id == b }, "and must not delete it")

        // An unpinned one still deletes.
        #expect(pm.deleteTheme(id: a).isEmpty)
        #expect(!pm.themes.contains { $0.id == a })
    }

    // 2b
    @Test func importFillsMissingPresentersFromTheirDefaults() throws {
        let source = makeTestManager()
        _ = source.saveCurrentAsTheme(named: "Partial")
        guard var saved = source.themes.first(where: { $0.name == "Partial" }) else { return }
        saved.payload.profiles["media"] = nil
        saved.payload.profiles["text"] = nil
        if let i = source.themes.firstIndex(where: { $0.id == saved.id }) { source.themes[i] = saved }

        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-partial-\(UUID().uuidString).tptheme")
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        let target = makeTestManager()
        let imported = try target.importTheme(from: package)

        // Absent reads as "nothing configured" downstream and would blank the
        // presenter, so the gap is filled with that presenter's own defaults.
        for key in PresentationManager.profileKeys {
            #expect(imported.payload.profiles[key] != nil, "\(key) missing after import")
        }
        #expect(imported.payload.profiles["media"]?.visibility[TextBoxSection.reference.rawValue] == false,
                "media must come back with MEDIA's defaults, not another presenter's")
    }
}

// MARK: - Combining themes
//
// A combination IS a theme — a plain, full-fledged one. It COPIES the chosen
// profiles, so editing a source afterwards leaves it alone, and it exports,
// imports, applies and deletes like any other. There is no separate pack entity
// and no second file extension.
@MainActor struct CombinedThemeTests {

    private func sourceThemes(_ pm: PresentationManager) -> (UUID, UUID) {
        for key in PresentationManager.profileKeys {
            pm.setStaticText("galaxie-\(key)", for: .reference, in: key)
        }
        let galaxie = pm.saveCurrentAsTheme(named: "Galaxie").id
        for key in PresentationManager.profileKeys {
            pm.setStaticText("default-\(key)", for: .reference, in: key)
        }
        let standard = pm.saveCurrentAsTheme(named: "Default").id
        return (galaxie, standard)
    }

    @Test func itTakesEachPresenterFromItsChosenSource() throws {
        let pm = makeTestManager()
        let (galaxie, standard) = sourceThemes(pm)

        let combined = try #require(pm.combineThemes(picks: ["bible": galaxie, "song": standard]))

        #expect(combined.payload.profiles["bible"]?.staticTexts[TextBoxSection.reference.rawValue] == "galaxie-bible")
        #expect(combined.payload.profiles["song"]?.staticTexts[TextBoxSection.reference.rawValue] == "default-song")
    }

    @Test func itIsANormalThemeInTheLibrary() throws {
        let pm = makeTestManager()
        let (galaxie, standard) = sourceThemes(pm)
        let combined = try #require(pm.combineThemes(picks: ["bible": galaxie, "song": standard]))

        #expect(pm.themes.contains { $0.id == combined.id })
        #expect(combined.id != galaxie && combined.id != standard, "a new theme gets a new id")
        // Applies and deletes like any other.
        pm.applyTheme(id: combined.id)
        #expect(pm.activeThemeID == combined.id)
        #expect(pm.deleteTheme(id: combined.id).isEmpty)
    }

    @Test func itCopiesRatherThanReferences() throws {
        let pm = makeTestManager()
        let (galaxie, standard) = sourceThemes(pm)
        let combined = try #require(pm.combineThemes(picks: ["bible": galaxie, "song": standard]))

        // Edit the SOURCE afterwards. A reference would follow; a copy must not.
        let i = try #require(pm.themes.firstIndex(where: { $0.id == galaxie }))
        pm.themes[i].payload.profiles["bible"]?.staticTexts[TextBoxSection.reference.rawValue] = "edited"

        let stored = try #require(pm.themes.first(where: { $0.id == combined.id }))
        #expect(stored.payload.profiles["bible"]?.staticTexts[TextBoxSection.reference.rawValue] == "galaxie-bible")
    }

    @Test func theNameIsBuiltFromItsSourcesAndStaysUnique() throws {
        let pm = makeTestManager()
        let (galaxie, standard) = sourceThemes(pm)

        let first = try #require(pm.combineThemes(picks: ["bible": galaxie, "song": standard]))
        #expect(first.name == "Galaxie + Default")

        // Combining the same pair again must not leave two identical cards.
        let second = try #require(pm.combineThemes(picks: ["bible": galaxie, "song": standard]))
        #expect(second.name == "Galaxie + Default 2")

        // And it can be renamed like any theme.
        pm.renameTheme(id: second.id, to: "Duminică")
        #expect(pm.themes.first(where: { $0.id == second.id })?.name == "Duminică")
    }

    @Test func presentersNotChosenKeepTheirCurrentLook() throws {
        let pm = makeTestManager()
        let (galaxie, _) = sourceThemes(pm)
        pm.setStaticText("live-media", for: .reference, in: "media")

        let combined = try #require(pm.combineThemes(picks: ["bible": galaxie]))

        // Combining two presenters must not silently reset the other two.
        #expect(combined.payload.profiles["media"]?.staticTexts[TextBoxSection.reference.rawValue] == "live-media")
    }

    @Test func theGlobalsComeFromAnExplicitBase() throws {
        let pm = makeTestManager()
        pm.fontSize = 40
        let a = pm.saveCurrentAsTheme(named: "Big").id
        pm.fontSize = 18
        let b = pm.saveCurrentAsTheme(named: "Small").id

        // Shared text globals can only come from one source, so it is stated
        // rather than left to dictionary ordering.
        let fromA = try #require(pm.combineThemes(picks: ["bible": a, "song": b], base: a))
        #expect(fromA.payload.fontSize == 40)
        let fromB = try #require(pm.combineThemes(picks: ["bible": a, "song": b], base: b))
        #expect(fromB.payload.fontSize == 18)
    }

    @Test func itSurvivesExportAndImportLikeAnyTheme() throws {
        let pm = makeTestManager()
        let (galaxie, standard) = sourceThemes(pm)
        let combined = try #require(pm.combineThemes(picks: ["bible": galaxie, "song": standard]))

        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-combined-\(UUID().uuidString).tptheme")
        defer { try? FileManager.default.removeItem(at: package) }
        try pm.exportTheme(id: combined.id, to: package)

        let target = makeTestManager()
        let imported = try target.importTheme(from: package)
        #expect(imported.payload.profiles["bible"]?.staticTexts[TextBoxSection.reference.rawValue] == "galaxie-bible")
        #expect(imported.payload.profiles["song"]?.staticTexts[TextBoxSection.reference.rawValue] == "default-song")
    }

    @Test func nonsensicalInputIsRefusedRatherThanGuessed() {
        let pm = makeTestManager()
        #expect(pm.combineThemes(picks: [:]) == nil)
        #expect(pm.combineThemes(picks: ["bible": UUID()]) == nil, "unknown source theme")
        #expect(pm.combineThemes(picks: ["nope": UUID()]) == nil, "unknown profile key")
    }
}

// MARK: - Media sources
//
// Media used to fall through to `default` in sourceOptions and offer the Bible's
// entire list — verse text, Strong's numbers, cross-references — none of which a
// media caption can ever resolve.
@MainActor struct MediaSourceTests {

    @Test func mediaNoLongerOffersBibleOnlySources() {
        let raws = Set(PresentationManager.sourceOptions(for: "media").map(\.raw))
        // mainText/reference/subtitle are COMMON now — every presenter carries
        // them. What must stay out is what only a Bible can supply.
        for bibleOnly in ["translation", "strongs", "crossReference", "gloss", "heading"] {
            #expect(!raws.contains(bibleOnly), "media must not offer '\(bibleOnly)'")
        }
    }

    @Test func mediaOffersItsOwnAndTheGenericOnes() {
        let raws = Set(PresentationManager.sourceOptions(for: "media").map(\.raw))
        for own in ["mediaFile", "mediaName", "mediaKind", "mediaExtension"] {
            #expect(raws.contains(own), "media should offer '\(own)'")
        }
        for generic in ["static", "date", "time", "slideNumber"] {
            #expect(raws.contains(generic), "every presenter keeps '\(generic)'")
        }
    }

    @Test func theOtherPresentersAreUnchanged() {
        let bible = Set(PresentationManager.sourceOptions(for: "bible").map(\.raw))
        #expect(bible.contains("mainText") && bible.contains("strongs"))
        #expect(!bible.contains("mediaFile"), "media specifics stay out of Bible")

        let song = Set(PresentationManager.sourceOptions(for: "song").map(\.raw))
        #expect(song.contains("songKey") && !song.contains("translation"))
    }

    @Test func mediaSourcesResolveFromTheLiveFile() {
        let url = URL(fileURLWithPath: "/tmp/Worship Loop.MP4")
        func resolve(_ raw: String) -> String {
            PresentationManager.resolveBoxSource(
                raw, autoValue: "", staticText: "",
                main: "", reference: "", translation: "", subtitle: "",
                mediaURL: url, mediaKind: "video"
            )
        }
        #expect(resolve("mediaFile") == "Worship Loop.MP4")
        #expect(resolve("mediaName") == "Worship Loop")
        #expect(resolve("mediaExtension") == "MP4")
        #expect(resolve("mediaKind") == "Video")
    }

    @Test func mediaSourcesAreEmptyWithNothingLiveRatherThanWrong() {
        func resolve(_ raw: String) -> String {
            PresentationManager.resolveBoxSource(
                raw, autoValue: "fallback", staticText: "",
                main: "", reference: "", translation: "", subtitle: ""
            )
        }
        // Empty, not the auto fallback: a caption bound to the file name must go
        // blank when nothing is playing, not show unrelated content.
        #expect(resolve("mediaFile").isEmpty)
        #expect(resolve("mediaKind").isEmpty)
    }
}

// MARK: - The media presenter's own casete
//
// Every source the media presenter offers was reachable in the editor and dead on
// the projector: `setMedia` blanked the text fields the common sources read from,
// and the output refused to draw text boxes at all while media was live. An
// operator could configure a title, a countdown or a slide timer over a clip, see
// it in the box list, and never see it on screen.
@MainActor struct MediaPresenterSourceTests {

    @Test func goingLiveWithMediaCarriesItsTitle() {
        let pm = makeTestManager()
        pm.showMedia(kind: "video", url: URL(fileURLWithPath: "/tmp/Worship Loop.MP4"))

        // „Titlu media (live)" reads `reference`. It used to be blanked, so every
        // box bound to it resolved empty and never mounted.
        #expect(pm.liveContent.reference == "Worship Loop")
        #expect(pm.liveContent.contentType == .media)
    }

    @Test func theTitleCaseteResolvesAgainstTheLiveClip() {
        let pm = makeTestManager()
        pm.showMedia(kind: "image", url: URL(fileURLWithPath: "/tmp/Anunț.png"))

        pm.setSourceRaw("reference", for: .reference, in: "media")
        let text = pm.sectionText(
            .reference,
            main: pm.liveContent.mainText, reference: pm.liveContent.reference,
            translation: "", subtitle: "", in: "media"
        )
        #expect(text == "Anunț")
    }

    @Test func aPreviewResolvesMediaSourcesBeforeTheClipGoesLive() {
        let pm = makeTestManager()
        pm.setSourceRaw("mediaName", for: .reference, in: "media")

        // Nothing live: without the override the box would describe whatever is on
        // the projector, so the panel could never preview what it is about to show.
        let pending = URL(fileURLWithPath: "/tmp/Intro Bumper.mov")
        let previewed = pm.sectionText(
            .reference, main: "", reference: "", translation: "", subtitle: "",
            mediaURL: pending, mediaKind: "video", in: "media"
        )
        #expect(previewed == "Intro Bumper")

        // Omitted, it still falls back to the live values — the output's path.
        #expect(pm.sectionText(.reference, main: "", reference: "", translation: "", subtitle: "",
                               in: "media").isEmpty)
    }

    @Test func theGenericSourcesAllHaveSomewhereToLiveInMedia() {
        // The common core is main text / title / subtitle. Every one of them needs
        // a built-in casetă to be bound to, or the presenter is not "like the
        // others" no matter what the source picker offers.
        let sections = PresentationManager.relevantSections(for: "media")
        #expect(sections.contains(.verseContent))
        #expect(sections.contains(.reference))
        #expect(sections.contains(.subtitle))

        let sources = PresentationManager.sourceOptions(for: "media").map(\.raw)
        for generic in ["static", "date", "time", "slideNumber", "countdown", "elapsed", "slideTimer"] {
            #expect(sources.contains(generic), "media lost the generic '\(generic)' source")
        }
        for common in ["mainText", "reference", "subtitle"] {
            #expect(sources.contains(common), "media lost the common '\(common)' source")
        }
    }

    @Test func mediaSourcesNeverResolveToBibleContent() {
        // The editor canvas and the right panel both fed these boxes the
        // operator's BIBLE selection, because "media" fell into the `default:`
        // arm of their sample switches. The Media theme showed a verse in its
        // main box and "Geneza 1:1" in its title — text the media presenter can
        // never actually produce. Nothing in the media presenter's own resolution
        // may read a Bible field.
        let pm = makeTestManager()
        let clip = URL(fileURLWithPath: "/tmp/Intro Bumper.mov")

        // Whatever a Bible box would have supplied is passed as empty here, which
        // is what a media host now sends: the sources must stand on media alone.
        for raw in ["mainText", "reference", "subtitle", "translation"] {
            pm.setSourceRaw(raw, for: .verseContent, in: "media")
            let text = pm.sectionText(
                .verseContent, main: "", reference: "", translation: "", subtitle: "",
                mediaURL: clip, mediaKind: "video", in: "media"
            )
            #expect(text.isEmpty, "'\(raw)' invented content for a media box")
        }

        // The media-specific ones DO resolve — against the file, not the Bible.
        pm.setSourceRaw("mediaName", for: .verseContent, in: "media")
        #expect(pm.sectionText(.verseContent, main: "", reference: "", translation: "",
                               subtitle: "", mediaURL: clip, mediaKind: "video",
                               in: "media") == "Intro Bumper")
    }

    @Test func withNoMediaSelectedTheBoxesAreEmpty() {
        // "…or nothing if no file is selected" — an empty box does not mount, so
        // an idle media presenter projects a clean screen rather than stale text.
        let pm = makeTestManager()
        for raw in ["mediaFile", "mediaName", "mediaKind", "mediaExtension", "reference"] {
            pm.setSourceRaw(raw, for: .reference, in: "media")
            let text = pm.sectionText(.reference, main: "", reference: "", translation: "",
                                      subtitle: "", in: "media")
            #expect(text.isEmpty, "'\(raw)' showed something with no media selected")
        }
    }

    @Test func theMediaProfileStillOptsOutOfBibleOnlyBoxes() {
        // Widening the list must not hand media a translation-name box: nothing
        // ever fills it, so it would be a permanently empty casetă in the list.
        #expect(!PresentationManager.relevantSections(for: "media").contains(.translationName))
        #expect(!PresentationManager.relevantSections(for: "media").contains(.chords))
    }
}

// MARK: - Live media as a casetă
//
// Full-screen media used to be two hard-coded layers in the output that bypassed
// the box system, so it could not be moved, resized, reordered, hidden or given a
// transition. It is an ordinary media casetă now, shipped full-bleed.
@MainActor struct LiveMediaBoxTests {

    @Test func theMediaProfileShipsAFullBleedLiveBox() {
        let profile = PresentationManager.LayoutProfile.defaultProfile(for: "media")
        let live = profile.mediaBoxes.first { $0.sourceRaw == "live" }
        let box = try? #require(live)
        #expect(box != nil, "media should ship a live casetă")
        #expect(box?.frame.x == 0 && box?.frame.y == 0)
        #expect(box?.frame.width == 1 && box?.frame.height == 1, "full bleed to start")
        #expect(profile.boxOrder.contains("media:" + (box?.id.uuidString ?? "")))
    }

    @Test func itIsAnOrdinaryCaseteInEveryWay() throws {
        let pm = makeTestManager()
        let box = try #require(pm.profile("media").mediaBoxes.first { $0.sourceRaw == "live" })
        let token = PresentationManager.mediaToken(box.id)

        // Listed, so it appears in the casete list and on the canvas.
        #expect(pm.orderedBoxTokens(in: "media").contains(token))

        // Movable and resizable like anything else.
        var moved = box
        moved.frame = PresentationManager.TextBoxFrame(x: 0.1, y: 0.1, width: 0.5, height: 0.4)
        pm.updateMediaBox(moved, in: "media")
        #expect(pm.mediaBox(id: box.id, in: "media")?.frame.width == 0.5)

        // Hideable, and colourable — both keyed by the same token as any box.
        pm.setBoxColorHex("#123456", forToken: token, in: "media")
        #expect(pm.boxColorHex(forToken: token, in: "media") == "#123456")
    }

    @Test func theOutputsHardCodedLayerStandsDownForIt() {
        let pm = makeTestManager()
        // Media has the casetă, so the old full-screen layer must not also draw.
        #expect(pm.hasLiveMediaBox(in: "media"))
        // Bible has none, so nothing changes for it.
        #expect(!pm.hasLiveMediaBox(in: "bible"))
    }

    @Test func hidingTheCaseteHandsRenderingBackToTheOldPath() throws {
        let pm = makeTestManager()
        var box = try #require(pm.profile("media").mediaBoxes.first { $0.sourceRaw == "live" })
        box.isVisible = false
        pm.updateMediaBox(box, in: "media")

        // Otherwise hiding the casetă would black out the projector rather than
        // falling back — the operator would have no way to recover mid-service.
        #expect(!pm.hasLiveMediaBox(in: "media"))
    }

    @Test func aProfileSavedBeforeTheCaseteExistedStillRenders() {
        let pm = makeTestManager()
        pm.mutateProfile("media") { $0.mediaBoxes = [] }
        // No casetă → the hard-coded layer stays in charge, so old themes and old
        // saved profiles do not go blank.
        #expect(!pm.hasLiveMediaBox(in: "media"))
    }

    @Test func aFileBackedBoxIsUnaffected() {
        let pm = makeTestManager()
        var file = PresentationManager.MediaBox()
        file.fileName = "logo.png"
        #expect(file.sourceRaw == "file", "existing boxes keep their own file")
        pm.mutateProfile("bible") { $0.mediaBoxes = [file] }
        #expect(!pm.hasLiveMediaBox(in: "bible"))
    }

    @Test func theLiveBoxSurvivesAThemeRoundTrip() throws {
        let source = makeTestManager()
        _ = source.saveCurrentAsTheme(named: "WithLive")
        let saved = try #require(source.themes.first(where: { $0.name == "WithLive" }))
        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-live-\(UUID().uuidString).tptheme")
        defer { try? FileManager.default.removeItem(at: package) }
        try source.exportTheme(id: saved.id, to: package)

        let target = makeTestManager()
        let imported = try target.importTheme(from: package)
        let live = imported.payload.profiles["media"]?.mediaBoxes.first { $0.sourceRaw == "live" }
        #expect(live != nil, "the live casetă must survive export/import")
    }
}

// MARK: - Dynamic casetes: clock, countdown, elapsed (G2)
//
// Configuration rides in the box's EXISTING sourceFormat slot rather than new
// LayoutProfile fields — that slot exists to configure a source, and it already
// flows through themes, export/import and undo, so a countdown survives all of
// that with no schema change.
@MainActor struct ClockOptionsTests {

    typealias Options = PresentationManager.ClockOptions

    @Test func theEncodingRoundTrips() {
        let target = ISO8601DateFormatter().date(from: "2026-12-25T10:30:00Z")!
        let original = Options(style: "hms", timeZoneID: "Europe/Madrid", target: target)
        let decoded = Options(raw: original.raw)
        #expect(decoded == original)
    }

    @Test func aBareStyleStillParses() {
        // Every format string written before this existed is just a style, and has
        // to keep meaning exactly what it meant.
        #expect(Options(raw: "hms").style == "hms")
        #expect(Options(raw: "hms").timeZoneID.isEmpty)
        #expect(Options(raw: "hms").target == nil)
        #expect(Options(raw: "").style.isEmpty)
    }

    @Test func unknownSegmentsAreIgnoredRatherThanBreaking() {
        // So a theme written by a newer build degrades to its style here instead
        // of failing to parse.
        let o = Options(raw: "hms|tz=UTC|somethingNew=42")
        #expect(o.style == "hms")
        #expect(o.timeZoneID == "UTC")
    }

    @Test func anUnknownTimeZoneFallsBackToTheCurrentOne() {
        #expect(Options(raw: "hm|tz=Not/AZone").timeZone == .current)
    }

    @Test func theClockHonoursItsTimeZone() {
        let noon = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
        let utc = PresentationManager.formattedClock(source: "time", format: "hm|tz=UTC", now: noon)
        let tokyo = PresentationManager.formattedClock(source: "time", format: "hm|tz=Asia/Tokyo", now: noon)

        #expect(utc != tokyo, "a zone must actually change the reading")

        // Derive the expected hour instead of hard-coding it: on a 12-hour locale
        // 21:00 renders as "09", so an assertion on "21" passes locally and fails
        // on a US-locale CI runner. This asserts the CONTRACT — the reading matches
        // that zone's wall clock — in whatever form the locale writes it.
        func hour(_ zone: String) -> Int {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: zone)!
            return cal.component(.hour, from: noon)
        }
        #expect(hour("Asia/Tokyo") - hour("UTC") == 9, "sanity: the zones differ by nine hours")
        #expect(utc.contains(String(format: "%02d", hour("UTC"))) || utc.contains("\(hour("UTC"))"))
    }

    @Test func countdownCountsTowardsItsTarget() {
        // A whole second: the encoding is second-precision on purpose — a
        // countdown has no use for milliseconds — so a fractional `now` would
        // shift the difference by that fraction.
        let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
        let raw = Options(style: "", timeZoneID: "", target: now.addingTimeInterval(3661)).raw
        #expect(PresentationManager.formattedClock(source: "countdown", format: raw, now: now) == "1:01:01")

        let soon = Options(style: "", timeZoneID: "", target: now.addingTimeInterval(65)).raw
        #expect(PresentationManager.formattedClock(source: "countdown", format: soon, now: now) == "1:05")
    }

    @Test func aPassedTargetClampsToZeroRatherThanGoingNegative() {
        let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
        let raw = Options(style: "", timeZoneID: "", target: now.addingTimeInterval(-90)).raw
        // "-1:30" on a projector is worse than "0:00".
        #expect(PresentationManager.formattedClock(source: "countdown", format: raw, now: now) == "0:00")
    }

    @Test func elapsedCountsAwayFromItsTarget() {
        let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
        let raw = Options(style: "", timeZoneID: "", target: now.addingTimeInterval(-125)).raw
        #expect(PresentationManager.formattedClock(source: "elapsed", format: raw, now: now) == "2:05")
    }

    @Test func anUnconfiguredCountdownReadsAsZero() {
        // Not a stale or absurd number: an unconfigured box should read "not
        // started", not "wrong".
        #expect(PresentationManager.formattedClock(source: "countdown", format: "", now: Date()) == "0:00")
    }

    @Test func spanStylesKeepAStableWidth() {
        #expect(PresentationManager.formattedSpan(59, style: "") == "0:59")
        #expect(PresentationManager.formattedSpan(3600, style: "") == "1:00:00")
        #expect(PresentationManager.formattedSpan(3661, style: "mmss") == "61:01")
        #expect(PresentationManager.formattedSpan(3661, style: "hm") == "1:01")
    }

    @Test func everyPresenterOffersTheNewSources() {
        for key in PresentationManager.profileKeys {
            let raws = Set(PresentationManager.sourceOptions(for: key).map(\.raw))
            #expect(raws.contains("countdown"), "\(key) should offer a countdown")
            #expect(raws.contains("elapsed"), "\(key) should offer elapsed time")
        }
    }
}

// MARK: - Clock refresh cadence
//
// Decision (c): tick only when a time-based casetă actually exists, and only as
// fast as that casetă needs.
@MainActor struct ClockTickTests {

    private func useReference(_ pm: PresentationManager, source: String, format: String) {
        pm.activeProfileKey = "bible"
        pm.setSectionVisible(true, for: .reference, in: "bible")
        pm.setSourceRaw(source, for: .reference, in: "bible")
        pm.setSourceFormat(format, for: .reference, in: "bible")
        pm.showBibleVerse(text: "x", reference: "y")
    }

    @Test func noTimeBoxMeansNoTicking() {
        let pm = makeTestManager()
        useReference(pm, source: "static", format: "")
        #expect(pm.clockTickInterval == nil, "nothing to refresh for")
        pm.clearOutput()
    }

    @Test func minutePrecisionTicksEveryMinute() {
        let pm = makeTestManager()
        useReference(pm, source: "time", format: "hm")
        #expect(pm.clockTickInterval == 60)
        pm.clearOutput()
    }

    @Test func secondsForceTheFastTick() {
        let pm = makeTestManager()
        useReference(pm, source: "time", format: "hms")
        #expect(pm.clockTickInterval == 1)
        pm.clearOutput()
    }

    @Test func aCountdownTicksEverySecond() {
        let pm = makeTestManager()
        useReference(pm, source: "countdown", format: "")
        #expect(pm.clockTickInterval == 1)
        pm.clearOutput()
    }

    @Test func aCountdownShowingOnlyMinutesDoesNot() {
        let pm = makeTestManager()
        useReference(pm, source: "countdown", format: "hm")
        // Asking for 1 s here would wake the whole output sixty times a minute to
        // redraw a number that cannot have changed.
        #expect(pm.clockTickInterval == 60)
        pm.clearOutput()
    }

    @Test func aHiddenTimeBoxDoesNotKeepTheClockRunning() {
        let pm = makeTestManager()
        useReference(pm, source: "time", format: "hms")
        pm.setSectionVisible(false, for: .reference, in: "bible")
        #expect(pm.clockTickInterval == nil)
        pm.clearOutput()
    }
}

// MARK: - Saving a theme for one presenter (3c)
//
// In per-presenter mode the four may be wearing four different themes, so "save
// the current look" is ambiguous — a full snapshot would bottle the mix, which is
// rarely what someone editing one presenter means. The editor asks; these hold
// what each answer does.
@MainActor struct SingleProfileThemeTests {

    @Test func savingOnePresenterKeepsOnlyThatProfile() {
        let pm = makeTestManager()
        for key in PresentationManager.profileKeys {
            pm.setStaticText("look-\(key)", for: .reference, in: key)
        }

        let theme = pm.saveCurrentAsTheme(named: "Just songs", onlyProfile: "song")

        #expect(theme.payload.profiles.keys.sorted() == ["song"])
        #expect(theme.payload.profiles["song"]?.staticTexts[TextBoxSection.reference.rawValue] == "look-song")
    }

    @Test func itIsTaggedWithThePresenterItCameFrom() {
        let pm = makeTestManager()
        let theme = pm.saveCurrentAsTheme(named: "Only bible", onlyProfile: "bible")
        #expect(theme.formatRaw == "bible", "so the gallery can badge it")
    }

    @Test func savingEverythingStillDoes() {
        let pm = makeTestManager()
        let theme = pm.saveCurrentAsTheme(named: "All four")
        #expect(theme.payload.profiles.count == PresentationManager.profileKeys.count)
        #expect(theme.formatRaw == "all")
    }

    @Test func theMissingPresentersComeBackAsTheirOwnDefaults() throws {
        // 2b applies: the absent three are filled from THEIR defaults on import,
        // not from whatever the operator who saved it had on screen.
        let pm = makeTestManager()
        pm.setStaticText("mine", for: .reference, in: "bible")
        let theme = pm.saveCurrentAsTheme(named: "Bible only", onlyProfile: "bible")

        let package = FileManager.default.temporaryDirectory
            .appendingPathComponent("tp-single-\(UUID().uuidString).tptheme")
        defer { try? FileManager.default.removeItem(at: package) }
        try pm.exportTheme(id: theme.id, to: package)

        let target = makeTestManager()
        let imported = try target.importTheme(from: package)

        #expect(imported.payload.profiles["bible"]?.staticTexts[TextBoxSection.reference.rawValue] == "mine")
        for key in PresentationManager.profileKeys {
            #expect(imported.payload.profiles[key] != nil, "\(key) must not be absent")
        }
        // Media's own defaults, which ship the live casetă and hidden text boxes.
        #expect(imported.payload.profiles["media"]?.mediaBoxes.contains { $0.sourceRaw == "live" } == true)
    }

    @Test func applyingItInPerPresenterModeTouchesOnlyThatPresenter() {
        let pm = makeTestManager()
        pm.setStaticText("bible-look", for: .reference, in: "bible")
        pm.setStaticText("song-look", for: .reference, in: "song")
        let theme = pm.saveCurrentAsTheme(named: "Bible only", onlyProfile: "bible")

        pm.usesPerPresenterThemes = true
        pm.setStaticText("changed", for: .reference, in: "bible")
        pm.applyTheme(id: theme.id, toProfileOnly: "bible")

        #expect(pm.staticText(for: .reference, in: "bible") == "bible-look")
        #expect(pm.staticText(for: .reference, in: "song") == "song-look", "untouched")
    }
}

// MARK: - Clock legibility
@MainActor struct ClockAmPmTests {

    @Test func aTwelveHourLocaleKeepsAmPm() {
        // Dropping it rendered 21:00 as a bare "09" — indistinguishable from nine
        // in the morning on a projector. Found because a CI runner on a US locale
        // failed a test that passed on a 24-hour machine.
        let evening = ISO8601DateFormatter().date(from: "2026-06-15T21:00:00Z")!
        let text = PresentationManager.formattedClock(source: "time", format: "hm|tz=UTC", now: evening)

        if PresentationManager.usesTwentyFourHourClock {
            #expect(text.contains("21"), "a 24-hour locale writes the hour plainly")
        } else {
            // Either the marker is present, or the hour is unambiguous on its own.
            let marked = text.uppercased().contains("PM") || text.uppercased().contains("P.M")
            #expect(marked, "a 12-hour locale must not drop the marker: \(text)")
        }
    }

    @Test func middayAndMidnightStayDistinct() {
        let noon = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
        let midnight = ISO8601DateFormatter().date(from: "2026-06-15T00:00:00Z")!
        let a = PresentationManager.formattedClock(source: "time", format: "hm|tz=UTC", now: noon)
        let b = PresentationManager.formattedClock(source: "time", format: "hm|tz=UTC", now: midnight)
        #expect(a != b, "12:00 and 00:00 must not render identically")
    }
}

// MARK: - Slide timer
@MainActor struct SlideTimerTests {

    @Test func itCountsFromWhenTheContentWentLive() {
        let shown = Date().addingTimeInterval(-95)
        let text = PresentationManager.resolveBoxSource(
            "slideTimer", autoValue: "", staticText: "",
            main: "", reference: "", translation: "", subtitle: "",
            slideShownAt: shown
        )
        #expect(text == "1:35")
    }

    @Test func itResetsOnEverySlide() {
        let pm = makeTestManager()
        pm.showBibleVerse(text: "one", reference: "Gen 1:1")
        let first = pm.slideShownAt
        pm.showBibleVerse(text: "two", reference: "Gen 1:2")
        // Unlike `elapsed`, which needs a target, this restarts by itself.
        #expect(pm.slideShownAt > first)
        pm.clearOutput()
    }

    @Test func withNothingLiveItReadsZero() {
        let text = PresentationManager.resolveBoxSource(
            "slideTimer", autoValue: "", staticText: "",
            main: "", reference: "", translation: "", subtitle: ""
        )
        #expect(text == "0:00")
    }

    @Test func everyPresenterOffersIt() {
        for key in PresentationManager.profileKeys {
            let raws = Set(PresentationManager.sourceOptions(for: key).map(\.raw))
            #expect(raws.contains("slideTimer"), "\(key) should offer the slide timer")
        }
    }

    @Test func itDrivesTheClockLikeAnyOtherSpan() {
        let pm = makeTestManager()
        pm.activeProfileKey = "bible"
        pm.setSectionVisible(true, for: .reference, in: "bible")
        pm.setSourceRaw("slideTimer", for: .reference, in: "bible")
        pm.setSourceFormat("", for: .reference, in: "bible")
        pm.showBibleVerse(text: "x", reference: "y")
        #expect(pm.clockTickInterval == 1, "seconds are visible, so it ticks every second")

        // Minutes only: no reason to wake the output every second.
        pm.setSourceFormat("hm", for: .reference, in: "bible")
        #expect(pm.clockTickInterval == 60)
        pm.clearOutput()
    }
}

// MARK: - The common source core
//
// A casetă used to behave differently depending on which presenter you happened
// to be editing: four disjoint source lists, so a media caption could not show
// the main text and a slide could not show a subtitle, for no reason the operator
// could see. The choices are shared now; only the LABELS follow the presenter.
@MainActor struct CommonSourceCoreTests {

    @Test func everyPresenterCarriesTheSameCore() {
        for key in PresentationManager.profileKeys {
            let raws = Set(PresentationManager.sourceOptions(for: key).map(\.raw))
            for core in ["mainText", "reference", "subtitle"] {
                #expect(raws.contains(core), "\(key) is missing the common '\(core)'")
            }
        }
    }

    @Test func everyPresenterCarriesTheSameGenerics() {
        let generic = Set(PresentationManager.genericSourceOptions().map(\.raw))
        #expect(generic == ["static", "date", "time", "slideNumber",
                            "countdown", "elapsed", "slideTimer"])
        for key in PresentationManager.profileKeys {
            let raws = Set(PresentationManager.sourceOptions(for: key).map(\.raw))
            #expect(generic.isSubset(of: raws), "\(key) is missing a generic source")
        }
    }

    @Test func theLabelsStillFollowThePresenter() {
        func label(_ key: String, _ raw: String) -> String? {
            PresentationManager.sourceOptions(for: key).first { $0.raw == raw }?.label
        }
        // Same field, different meaning: the choice is shared, the wording is not.
        #expect(label("song", "mainText") != label("bible", "mainText"))
        #expect(label("text", "reference") != label("bible", "reference"))
    }

    @Test func specificsStayWithTheirPresenter() {
        func raws(_ key: String) -> Set<String> {
            Set(PresentationManager.sourceOptions(for: key).map(\.raw))
        }
        #expect(raws("song").contains("ccli") && !raws("bible").contains("ccli"))
        #expect(raws("bible").contains("strongs") && !raws("song").contains("strongs"))
        #expect(raws("media").contains("mediaFile") && !raws("text").contains("mediaFile"))
    }

    @Test func nothingIsListedTwice() {
        for key in PresentationManager.profileKeys {
            let all = PresentationManager.sourceOptions(for: key).map(\.raw)
            #expect(all.count == Set(all).count, "\(key) lists a source twice")
        }
    }

    @Test func everyOfferedSourceResolves() {
        // A source in the menu that resolves to nothing would be a dead choice.
        for key in PresentationManager.profileKeys {
            for option in PresentationManager.sourceOptions(for: key) where option.raw != "static" {
                let value = PresentationManager.resolveBoxSource(
                    option.raw, autoValue: "AUTO", staticText: "STATIC",
                    main: "M", reference: "R", translation: "T", subtitle: "S",
                    slideNumber: "1 / 2",
                    footnote: "F", crossReference: "X", heading: "H",
                    gloss: "G", strongs: "N",
                    songAuthor: "A", songCopyright: "C", songCCLI: "CC",
                    songbook: "B", songStyle: "ST", songKey: "K", songTempo: "TE",
                    mediaURL: URL(fileURLWithPath: "/tmp/a.mp4"), mediaKind: "video",
                    slideShownAt: Date()
                )
                #expect(!value.isEmpty, "'\(option.raw)' in \(key) resolved to nothing")
            }
        }
    }
}

// MARK: - Seeding the live media casetă into an existing profile
@MainActor struct LiveMediaMigrationTests {

    @Test func anOldProfileWithoutTheCaseteGetsOne() throws {
        let store = makeTestDefaults()
        // A media profile as it looked before the casetă existed.
        var old = PresentationManager.LayoutProfile.defaultProfile(for: "media")
        old.mediaBoxes = []
        old.boxOrder = []
        let blob = try JSONEncoder().encode(["media": old])
        store.set(blob, forKey: "pm_layoutProfiles")

        let pm = makeTestManager(store)

        // Without this the output kept falling back to the hard-coded full-screen
        // layer, which is exactly what the casetă replaces.
        #expect(pm.hasLiveMediaBox(in: "media"))
        let live = try #require(pm.profile("media").mediaBoxes.first { $0.sourceRaw == "live" })
        #expect(live.frame.width == 1 && live.frame.height == 1)
        #expect(pm.orderedBoxTokens(in: "media").first == PresentationManager.mediaToken(live.id))
    }

    @Test func aDeliberateDeleteSticksAcrossRelaunch() throws {
        let store = makeTestDefaults()
        var old = PresentationManager.LayoutProfile.defaultProfile(for: "media")
        old.mediaBoxes = []
        store.set(try JSONEncoder().encode(["media": old]), forKey: "pm_layoutProfiles")

        let first = makeTestManager(store)
        let live = try #require(first.profile("media").mediaBoxes.first { $0.sourceRaw == "live" })
        first.removeMediaBox(id: live.id, in: "media")
        #expect(first.profile("media").liveMediaRemoved, "the delete must be recorded, not inferred")
        first.persistProfilesNow()

        // Relaunch: it must NOT come back, or removing it would be impossible.
        // The intent lives on the PROFILE now — a one-shot UserDefaults flag could
        // only say "seeding already happened", which is a different claim, and it
        // left a theme that predates the casetă unable to ever get one.
        let second = makeTestManager(store)
        #expect(!second.hasLiveMediaBox(in: "media"))
    }

    @Test func addingItBackClearsTheDelete() throws {
        let pm = makeTestManager()
        let live = try #require(pm.profile("media").mediaBoxes.first { $0.sourceRaw == "live" })
        pm.removeMediaBox(id: live.id, in: "media")
        #expect(pm.canAddLiveMediaBox(in: "media"))

        let added = try #require(pm.addLiveMediaBox(in: "media"))
        #expect(pm.hasLiveMediaBox(in: "media"))
        #expect(!pm.profile("media").liveMediaRemoved, "asking for it back is consent")
        #expect(pm.orderedBoxTokens(in: "media").contains(PresentationManager.mediaToken(added.id)))
        // Twice would give the module two surfaces fighting over one clip.
        #expect(pm.addLiveMediaBox(in: "media") == nil)
    }

    @Test func aProfileThatAlreadyHasOneIsLeftAlone() throws {
        let store = makeTestDefaults()
        let seeded = PresentationManager.LayoutProfile.defaultProfile(for: "media")
        store.set(try JSONEncoder().encode(["media": seeded]), forKey: "pm_layoutProfiles")

        let pm = makeTestManager(store)
        #expect(pm.profile("media").mediaBoxes.filter { $0.sourceRaw == "live" }.count == 1,
                "must not end up with two")
    }

    @Test func existingOverlaysStayOnTop() throws {
        let store = makeTestDefaults()
        var old = PresentationManager.LayoutProfile.defaultProfile(for: "media")
        old.mediaBoxes = []
        var logo = PresentationManager.CustomTextBox()
        logo.text = "logo"
        old.customTextBoxes = [logo]
        old.boxOrder = ["custom:" + logo.id.uuidString]
        store.set(try JSONEncoder().encode(["media": old]), forKey: "pm_layoutProfiles")

        let pm = makeTestManager(store)
        let order = pm.orderedBoxTokens(in: "media")
        let liveIdx = try #require(order.firstIndex { $0.hasPrefix("media:") })
        let logoIdx = try #require(order.firstIndex(of: "custom:" + logo.id.uuidString))
        // Earlier in the list = further back, so the media must sit behind.
        #expect(liveIdx < logoIdx)
    }

    // The failure the operator actually hit: the box list showed four text casete
    // and no media at all, with no way to get one back. Seeding was a one-shot
    // launch migration, so anything that REPLACED the media profile afterwards —
    // applying a theme, importing one, copying another presenter's layout — left
    // the presenter unable to show media, permanently.

    @Test func applyingAThemeThatPredatesTheCaseteStillLeavesOne() throws {
        let pm = makeTestManager()
        // A theme saved before the casetă existed: its media profile has none.
        let theme = pm.saveCurrentAsTheme(named: "Legacy")
        let idx = try #require(pm.themes.firstIndex { $0.id == theme.id })
        pm.themes[idx].payload.profiles["media"]?.mediaBoxes = []
        pm.themes[idx].payload.profiles["media"]?.boxOrder = []

        pm.applyTheme(id: theme.id)
        #expect(pm.hasLiveMediaBox(in: "media"), "the media presenter must never end up unable to show media")
    }

    @Test func copyingAnotherPresentersLayoutKeepsTheMediaCasete() {
        let pm = makeTestManager()
        // Bible has no live casetă, and copyProfile replaces the target wholesale.
        pm.copyProfile(from: "bible", to: "media")
        #expect(pm.hasLiveMediaBox(in: "media"))
    }

    @Test func healingRespectsADeliberateDeleteEvenAcrossAThemeApply() throws {
        let pm = makeTestManager()
        let live = try #require(pm.profile("media").mediaBoxes.first { $0.sourceRaw == "live" })
        pm.removeMediaBox(id: live.id, in: "media")

        // The intent rides along in the saved profile, so re-applying the theme
        // the operator saved WITHOUT the casetă must not hand it back.
        let theme = pm.saveCurrentAsTheme(named: "NoLiveOnPurpose")
        pm.applyTheme(id: theme.id)
        #expect(!pm.hasLiveMediaBox(in: "media"))
    }
}

// MARK: - Round-trip guards
//
// Two mechanisms, and BOTH are needed. A round-trip test alone can be satisfied
// by never updating the snapshot; a coverage test alone proves a field is listed
// but not that its value survives. Together they form a ratchet: add a field to
// a model and the coverage test fails by name; add it to the snapshot and the
// round-trip test fails until the exporter and importer carry it.
//
// The third leg is fixture completeness — a fixture that leaves fields at their
// defaults makes every round-trip test using it pass for free, which is exactly
// how `theWholePayloadIsPreserved` passed while ~15 theme fields went unchecked.

/// Every persisted property name of a SwiftData model.
///
/// `schemaMetadata` is synthesised by the `@Model` macro, so a newly added `var`
/// appears here with no hand-maintained list to forget. `PropertyMetadata.name`
/// is not an accessible member in this SDK, so it is read via `Mirror` over the
/// metadata value — verified stable: `PropertyMetadata(name:keypath:defaultValue:metadata:)`.
enum PersistedFieldNames {
    static func of<T: PersistentModel>(_ type: T.Type) -> Set<String> {
        Set(type.schemaMetadata.compactMap { property -> String? in
            guard let name = Mirror(reflecting: property).children
                .first(where: { $0.label == "name" })
                .map({ "\($0.value)" }) else { return nil }
            // `#Index<Song>(…)` shows up in schemaMetadata as a pseudo-property.
            // It is a database index, not a field anything could export.
            return name.hasPrefix("SwiftData.Schema.") ? nil : name
        })
    }
}

/// Field names of a plain value type, and which of them are still at default.
///
/// The SwiftData models get their field list from `schemaMetadata`; the payload
/// structs that travel inside those files (`SessionItemPayload`, `ThemePayload`,
/// `LayoutProfile`) have no such macro, so they are reflected instead.
nonisolated enum ReflectedFields {
    static func names<T>(of value: T) -> Set<String> {
        Set(Mirror(reflecting: value).children.compactMap(\.label))
    }

    /// Fields that look untouched. Conservative on purpose: calling a set field
    /// unset is a loud failure someone fixes in a minute, while the opposite
    /// would quietly bless a vacuous fixture — which is the whole failure mode
    /// this exists to catch.
    static func unset<T>(in value: T) -> Set<String> {
        let defaults: Set<String> = ["", "0", "false", "[]", "{}", "nil", "Optional(\"\")", "[:]"]
        return Set(Mirror(reflecting: value).children.compactMap { child in
            guard let label = child.label else { return nil }
            return defaults.contains(String(describing: child.value)) ? label : nil
        })
    }

    /// Fields still holding exactly what a freshly-constructed value holds.
    ///
    /// Strictly stronger than `unset`, and the only one that works on types with
    /// non-empty defaults: `LayoutProfile.transitionInDuration` defaults to -1
    /// and `ThemePayload.globalTextOpacity` to 1.0, so no amount of looking for
    /// empties and zeroes would ever notice a fixture that never touched them.
    static func unchanged<T>(in value: T, from blueprint: T) -> Set<String> {
        let base = Dictionary(
            Mirror(reflecting: blueprint).children.compactMap { child in
                child.label.map { ($0, String(describing: child.value)) }
            },
            uniquingKeysWith: { a, _ in a })
        return Set(Mirror(reflecting: value).children.compactMap { child in
            guard let label = child.label, let original = base[label] else { return nil }
            return String(describing: child.value) == original ? label : nil
        })
    }
}

/// Fails naming any field left at its type's default value.
///
/// Guards the fixtures, not the code. A fixture that stops being exhaustive
/// silently weakens every test built on it, and the failure looks like success.
@MainActor
func assertFullyPopulated<T>(
    _ value: T,
    exempt: Set<String> = [],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let unset = ReflectedFields.unset(in: value).subtracting(exempt)
    #expect(unset.isEmpty,
            "fixture leaves \(unset.sorted()) at default — tests built on it would pass vacuously",
            sourceLocation: sourceLocation)
}

/// Fails naming any field that still holds what a fresh value holds.
///
/// The version to reach for on types whose defaults are not empty — a theme
/// payload full of `1.0`s and `-1`s looks thoroughly populated to
/// `assertFullyPopulated` and proves nothing.
@MainActor
func assertFullyCustomized<T>(
    _ value: T,
    comparedTo blueprint: T,
    exempt: Set<String> = [],
    label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let untouched = ReflectedFields.unchanged(in: value, from: blueprint).subtracting(exempt)
    #expect(untouched.isEmpty, """
        the \(label) fixture leaves \(untouched.sorted()) at their default values, \
        so every test built on it passes those fields for free.
        """, sourceLocation: sourceLocation)
}

/// Fails unless the given values, taken TOGETHER, touch every field of `blueprint`.
///
/// For fixtures where no single value can be exhaustive: a session item is
/// either a Bible reference or a song or a media clip, so all twelve payload
/// fields are only reachable across a set of items. Without this, adding a
/// thirteenth field would leave every session test passing.
@MainActor
func assertCollectivelyPopulated<Element, Blueprint>(
    _ values: [Element],
    covering blueprint: Blueprint,
    exempt: Set<String> = [],
    label: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let everyField = ReflectedFields.names(of: blueprint).subtracting(exempt)
    let touched = values.reduce(into: Set<String>()) { acc, value in
        acc.formUnion(ReflectedFields.names(of: value).subtracting(ReflectedFields.unset(in: value)))
    }
    let never = everyField.subtracting(touched)
    #expect(never.isEmpty,
            "no \(label) in the fixture sets \(never.sorted()) — those fields are carried by nothing and proved by nothing",
            sourceLocation: sourceLocation)
}

/// The three-way coverage contract for one model, in one place.
///
/// All three directions are needed. *Missing* catches a field added to the model
/// and forgotten everywhere else. *Stale* catches a snapshot still listing a
/// field the model renamed or dropped — without it, the missing-check keeps
/// passing while the snapshot describes a model that no longer exists. And an
/// exemption is a claim that losing a field is CORRECT, so it has to name a real
/// field and carry a reason someone can argue with.
@MainActor
func assertFieldCoverage<T: PersistentModel>(
    _ type: T.Type,
    snapshot: String,
    covered: Set<String>,
    exempt: [String: String],
    relationships: Set<String> = [],
    carriedBy: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    let model = PersistedFieldNames.of(type)

    let missing = model.subtracting(covered).subtracting(exempt.keys).subtracting(relationships)
    #expect(missing.isEmpty, """
        \(type) gained \(missing.sorted()). Add each to \(snapshot) and to \(carriedBy) \
        — or list it in \(snapshot).exemptFields with the reason losing it is correct.
        """, sourceLocation: sourceLocation)

    let stale = covered.union(relationships).subtracting(model)
    #expect(stale.isEmpty, "\(snapshot) still lists \(stale.sorted()), which \(type) no longer has",
            sourceLocation: sourceLocation)

    for (field, reason) in exempt.sorted(by: { $0.key < $1.key }) {
        #expect(model.contains(field),
                "\(snapshot) exempts '\(field)', a field \(type) does not have",
                sourceLocation: sourceLocation)
        #expect(reason.count > 20,
                "the exemption for '\(type).\(field)' needs a real reason, not '\(reason)'",
                sourceLocation: sourceLocation)
    }
}

/// A `Song`'s exportable state, for whole-object comparison across a round trip.
///
/// Equatable so a failure names the differing field rather than saying "not
/// equal". Relationships are covered by their own suites; the exemptions below
/// each carry a reason, because an unexplained exemption is how a real loss
/// gets normalised.
@MainActor struct SongSnapshot: Equatable {
    var title = "", author = "", copyright = "", ccliNumber = ""
    var key = "", tempo = "", songNumber = "", tags = ""
    var titlesJSON = "", language = "", themesJSON = "", style = ""
    var songbookNumber = "", authorWords = "", authorMusic = "", authorTranslation = ""
    var notes = ""
    /// Decoded, for the same reason as `SongSectionSnapshot.lines`: the two
    /// sides use different encoders and the strings differ by key order alone.
    var media: [SongMediaRef] = []
    var extensionsJSON = ""
    var verified = false, sourceFile = ""
    /// The POSITION of the original version, not its UUID.
    ///
    /// A real import mints new version ids, so the raw string always differs and
    /// would report a loss on every import. What actually has to survive is
    /// which arrangement is the original — and E5 covers the id itself, on the
    /// revert path where it genuinely must not change.
    var originalVersionIndex = -1

    init(_ song: Song) {
        title = song.title; author = song.author; copyright = song.copyright
        ccliNumber = song.ccliNumber; key = song.key; tempo = song.tempo
        songNumber = song.songNumber; tags = song.tags
        titlesJSON = song.titlesJSON; language = song.language
        themesJSON = song.themesJSON; style = song.style
        songbookNumber = song.songbookNumber
        authorWords = song.authorWords; authorMusic = song.authorMusic
        authorTranslation = song.authorTranslation
        notes = song.notes; media = song.media
        extensionsJSON = song.extensionsJSON
        verified = song.verified; sourceFile = song.sourceFile
        originalVersionIndex = song.versions.sorted { $0.order < $1.order }
            .firstIndex { $0.id.uuidString == song.originalVersionID } ?? -1
    }

    /// Names this snapshot claims to cover — checked against the model.
    static let coveredFields: Set<String> = [
        "title", "author", "copyright", "ccliNumber", "key", "tempo",
        "songNumber", "tags", "titlesJSON", "language", "themesJSON", "style",
        "songbookNumber", "authorWords", "authorMusic", "authorTranslation",
        "notes", "mediaJSON", "extensionsJSON", "verified", "sourceFile",
        "originalVersionID",
    ]

    /// Deliberately outside the round trip. Each entry is a claim that losing
    /// this field is CORRECT — not that we forgot it.
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; identity is re-established by the duplicate resolver",
        "searchText": "denormalized cache rebuilt from title/aliases/author/lyrics",
        "editLogJSON": "internal change log, documented as never exported (SongModels.swift:153)",
        "modifiedDate": "a real import must NOT adopt a stranger's timestamp; editor-revert preserves it via preservesTimestamps",
    ]

    static let relationshipFields: Set<String> = ["collection", "songbook", "versions", "verses"]
}

/// A `SongVersion` and its sections — where the lyrics actually live.
///
/// `SongSnapshot` covers only the song's own scalars, so until now the entire
/// version graph crossed the round trip unasserted: an arrangement, its chords,
/// its per-line translations and its override metadata could all have vanished
/// without a single test noticing.
@MainActor struct SongVersionSnapshot: Equatable {
    var name = "", displayTitle = "", author = "", language = "", key = ""
    var capo = 0, tempo = "", timeSignature = "", copyright = "", ccliNumber = ""
    var source = "", repeatStyle = "", titlesJSON = ""
    var authorWords = "", authorMusic = "", authorTranslation = ""
    var style = "", songbookNumber = "", themesJSON = "", notes = "", songbookName = ""
    var overridesMetadata = false, arrangementJSON = "", order = 0
    var sections: [SongSectionSnapshot] = []

    init(_ v: SongVersion) {
        name = v.name; displayTitle = v.displayTitle; author = v.author
        language = v.language; key = v.key; capo = v.capo; tempo = v.tempo
        timeSignature = v.timeSignature; copyright = v.copyright
        ccliNumber = v.ccliNumber; source = v.source; repeatStyle = v.repeatStyle
        titlesJSON = v.titlesJSON
        authorWords = v.authorWords; authorMusic = v.authorMusic
        authorTranslation = v.authorTranslation
        style = v.style; songbookNumber = v.songbookNumber
        themesJSON = v.themesJSON; notes = v.notes; songbookName = v.songbookName
        overridesMetadata = v.overridesMetadata
        arrangementJSON = v.arrangementJSON; order = v.order
        sections = v.sections.sorted { $0.order < $1.order }.map(SongSectionSnapshot.init)
    }

    static let coveredFields: Set<String> = [
        "name", "displayTitle", "author", "language", "key", "capo", "tempo",
        "timeSignature", "copyright", "ccliNumber", "source", "repeatStyle",
        "titlesJSON", "authorWords", "authorMusic", "authorTranslation", "style",
        "songbookNumber", "themesJSON", "notes", "songbookName",
        "overridesMetadata", "arrangementJSON", "order", "sections",
    ]
    static let exemptFields: [String: String] = [
        "id": "regenerated by applyResult, which is exactly the defect E5 fixes — asserted on its own in the session suite",
    ]
    static let relationshipFields: Set<String> = ["song"]
}

@MainActor struct SongSectionSnapshot: Equatable {
    var sectionKey = "", type = "", label = ""
    var order = 0, repeatCount = 0
    /// Decoded, never the raw `linesJSON`. The two sides serialize through
    /// different encoders, so the strings differ by KEY ORDER on identical
    /// content — comparing them reports a data loss that did not happen.
    var lines: [SongLine] = []
    var plainText = ""

    init(_ s: SongSection) {
        sectionKey = s.sectionKey; type = s.type; label = s.label
        order = s.order; repeatCount = s.repeatCount
        lines = s.lines; plainText = s.plainText
    }

    static let coveredFields: Set<String> = [
        "sectionKey", "type", "label", "order", "repeatCount", "linesJSON", "plainText",
    ]
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; a section's identity is its sectionKey within its version",
    ]
    static let relationshipFields: Set<String> = ["version"]
}

@MainActor struct ModelFieldCoverageTests {

    @Test func songSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            Song.self, snapshot: "SongSnapshot",
            covered: SongSnapshot.coveredFields,
            exempt: SongSnapshot.exemptFields,
            relationships: SongSnapshot.relationshipFields,
            carriedBy: "ExportService.songDictV2 and TopPresenterSongImporter")
    }

    @Test func bibleModuleSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            BibleModule.self, snapshot: "BibleModuleSnapshot",
            covered: BibleModuleSnapshot.coveredFields,
            exempt: BibleModuleSnapshot.exemptFields,
            carriedBy: "ExportService.exportToTopPresenterJSON and TopPresenterBibleImporter")
    }

    @Test func bibleBookSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            BibleBook.self, snapshot: "BibleBookSnapshot",
            covered: BibleBookSnapshot.coveredFields,
            exempt: BibleBookSnapshot.exemptFields,
            relationships: BibleBookSnapshot.relationshipFields,
            carriedBy: "ExportService.exportToTopPresenterJSON and TopPresenterBibleImporter")
    }

    @Test func bibleChapterSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            BibleChapter.self, snapshot: "BibleChapterSnapshot",
            covered: BibleChapterSnapshot.coveredFields,
            exempt: BibleChapterSnapshot.exemptFields,
            relationships: BibleChapterSnapshot.relationshipFields,
            carriedBy: "ExportService.exportToTopPresenterJSON and TopPresenterBibleImporter")
    }

    @Test func bibleVerseSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            BibleVerse.self, snapshot: "BibleVerseSnapshot",
            covered: BibleVerseSnapshot.coveredFields,
            exempt: BibleVerseSnapshot.exemptFields,
            relationships: BibleVerseSnapshot.relationshipFields,
            carriedBy: "ExportService.exportToTopPresenterJSON and TopPresenterBibleImporter")
    }

    @Test func songVersionSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            SongVersion.self, snapshot: "SongVersionSnapshot",
            covered: SongVersionSnapshot.coveredFields,
            exempt: SongVersionSnapshot.exemptFields,
            relationships: SongVersionSnapshot.relationshipFields,
            carriedBy: "ExportService.songDictV2 and TopPresenterSongImporter")
    }

    @Test func songSectionSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            SongSection.self, snapshot: "SongSectionSnapshot",
            covered: SongSectionSnapshot.coveredFields,
            exempt: SongSectionSnapshot.exemptFields,
            relationships: SongSectionSnapshot.relationshipFields,
            carriedBy: "ExportService.songDictV2 and TopPresenterSongImporter")
    }

    @Test func presentationSlideSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            PresentationSlide.self, snapshot: "PresentationSlideSnapshot",
            covered: PresentationSlideSnapshot.coveredFields,
            exempt: PresentationSlideSnapshot.exemptFields,
            carriedBy: "SlideDeckArchive (.tpslides, Phase 6)")
    }

    @Test func serviceScheduleSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            ServiceSchedule.self, snapshot: "ServiceScheduleSnapshot",
            covered: ServiceScheduleSnapshot.coveredFields,
            exempt: ServiceScheduleSnapshot.exemptFields,
            carriedBy: "SessionArchive and SessionArchiveService")
    }

    @Test func scheduleItemSnapshotAccountsForEveryStoredField() {
        assertFieldCoverage(
            ScheduleItem.self, snapshot: "ScheduleItemSnapshot",
            covered: ScheduleItemSnapshot.coveredFields,
            exempt: ScheduleItemSnapshot.exemptFields,
            relationships: ScheduleItemSnapshot.relationshipFields,
            carriedBy: "SessionArchive.Item and SessionArchiveService")
    }
}

// MARK: - Song round trip (GOAT)
//
// The song exporter is not only a file format — it is the song editor's undo
// snapshot (`SongsView.swift:1519`), and Cancel rebuilds the song from it
// (`:2184-2187`) through `applyResult`, which assigns key/tempo/tags
// unconditionally (`ImportService.swift:771-774`). So a field the exporter
// forgets is destroyed for operators who never export anything at all.
@MainActor struct SongRoundTripTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Every exportable field set to a distinctive non-default value.
    /// `assertFullyPopulated` keeps it honest as the model grows.
    private func fullyPopulatedSong(in ctx: ModelContext) -> Song {
        let song = Song(title: "Mare ești Tu", author: "Anon",
                        copyright: "© 1953", ccliNumber: "7104200", songNumber: "7")
        ctx.insert(song)
        // Deliberately DISCRIMINATING values. An earlier version of this fixture
        // used song.key == the version's key and tags == themes.joined(", "),
        // so three of the losses below reconstructed by accident and the test
        // under-reported the bug. A fixture whose values can be re-derived from
        // elsewhere proves nothing.
        song.key = "D"                    // version's key is G — must not be re-derived
        song.tempo = "72"
        song.tags = "botez, seara"        // themes are worship/easter — must not be re-derived
        song.titles = ["How Great Thou Art"]
        song.language = "ro"
        song.themes = ["worship", "easter"]
        song.style = "imn"
        song.songbookNumber = "42"
        song.authorWords = "Carl Boberg"
        song.authorMusic = "Trad."
        song.authorTranslation = "N. Moldoveanu"
        song.notes = "verificat 2026"
        song.media = [SongMediaRef(role: "audio", kind: "mp3", filename: "mare.mp3", bookmark: nil)]
        song.extensionsJSON = #"{"anatomiaEvangheliei":"da"}"#
        song.verified = true
        song.sourceFile = "mare-esti-tu.tpsong"
        // With a songbook present, songDictV2 takes the branch that drops
        // songNumber; without one it drops songbookNumber. Both must survive.
        let book = Songbook(name: "Cântările Evangheliei", publisher: "X", language: "ro", year: "1990")
        ctx.insert(book)
        song.songbook = book

        let v = SongVersion(name: "Clasică", order: 0, language: "ro",
                            key: "G", capo: 2, tempo: "72", timeSignature: "4/4",
                            copyright: "© 1953 v", ccliNumber: "7104201", source: "eBiblia")
        v.displayTitle = "Mare ești Tu (clasică)"
        v.author = "Anon (v)"
        v.repeatStyle = "bracket"
        v.titles = ["How Great Thou Art (v)"]
        v.authorWords = "Carl Boberg (v)"
        v.authorMusic = "Trad. (v)"
        v.authorTranslation = "N. Moldoveanu (v)"
        v.style = "imn (v)"
        v.songbookNumber = "43"
        v.themes = ["worship (v)"]
        v.notes = "note de versiune"
        v.songbookName = "Cântările Evangheliei (v)"
        v.overridesMetadata = true
        v.arrangement = ["v1", "c"]
        v.song = song
        ctx.insert(v)
        let s1 = SongSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0,
                             repeatCount: 2, lines: [
            SongLine(text: "Mare ești Tu", chords: [SongChord(sym: "G", pos: 0)],
                     translations: ["en": "How great Thou art"])
        ])
        s1.version = v
        ctx.insert(s1)
        song.originalVersionID = v.id.uuidString
        return song
    }

    @Test func theFixtureIsExhaustive() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        // The only version IS the original, so its index is 0 — the same
        // structural reason `order` is exempt below, not a gap in the fixture.
        assertFullyPopulated(SongSnapshot(song), exempt: ["originalVersionIndex"])
        let version = try #require(song.versions.first)
        // `order` is 0 on both because this is the first (and only) version, and
        // its first section. That is what a real one-arrangement song looks
        // like, so ordering gets its own test below rather than a fixture value
        // that could not occur.
        assertFullyPopulated(SongVersionSnapshot(version), exempt: ["order"])
        assertFullyPopulated(SongSectionSnapshot(try #require(version.sections.first)),
                             exempt: ["order"])
    }

    /// The version graph, which `SongSnapshot` does not reach: an arrangement,
    /// its chords, its per-line translations and its override metadata all
    /// crossed the round trip unasserted until now.
    @Test
    func theVersionGraphSurvivesAGoatRoundTrip() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        let before = song.versions.sorted { $0.order < $1.order }.map(SongVersionSnapshot.init)

        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: json))
        let rebuilt = Song(title: "")
        ctx.insert(rebuilt)
        ImportService.applyResult(result, to: rebuilt, modelContext: ctx)

        let after = rebuilt.versions.sorted { $0.order < $1.order }.map(SongVersionSnapshot.init)
        #expect(after == before)
    }

    /// An eighth lost field, and one the plan did not list: `versionDictV2`
    /// (`ExportService.swift:382-408`) emits every version field EXCEPT its
    /// alternate titles. A version exists to be a different rendition — a
    /// translation, a songbook variant — so the name it goes by is not
    /// incidental to it.
    @Test
    func theVersionsAlternateTitlesSurvive() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: json))
        let rebuilt = Song(title: "")
        ctx.insert(rebuilt)
        ImportService.applyResult(result, to: rebuilt, modelContext: ctx)

        let version = try #require(rebuilt.versions.first)
        #expect(version.titles == ["How Great Thou Art (v)"],
                "the version's alternate titles are lost — versionDictV2 emits no `titles` key")
    }

    /// Ordering across several arrangements, which one version cannot show.
    /// A song with three renditions is the app's headline case, and the running
    /// order of its arrangements is what the operator picks from.
    @Test func severalArrangementsKeepTheirOrder() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        for (index, name) in ["Tineret", "Instrumentală"].enumerated() {
            let extra = SongVersion(name: name, order: index + 1, language: "ro", key: "A")
            extra.song = song
            ctx.insert(extra)
            let section = SongSection(sectionKey: "v1", type: "verse", label: "Strofa 1",
                                      order: 0, lines: [SongLine(text: "linie \(name)")])
            section.version = extra
            ctx.insert(section)
        }

        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: json))
        let rebuilt = Song(title: "")
        ctx.insert(rebuilt)
        ImportService.applyResult(result, to: rebuilt, modelContext: ctx)

        let names = rebuilt.versions.sorted { $0.order < $1.order }.map(\.name)
        #expect(names == ["Clasică", "Tineret", "Instrumentală"])
        #expect(rebuilt.versions.sorted { $0.order < $1.order }.map(\.order) == [0, 1, 2])
    }

    @Test
    func everyFieldSurvivesAGoatRoundTrip() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        let before = SongSnapshot(song)

        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: json))
        let rebuilt = Song(title: "")
        ctx.insert(rebuilt)
        ImportService.applyResult(result, to: rebuilt, modelContext: ctx)

        #expect(SongSnapshot(rebuilt) == before)
    }

    @Test
    func theSevenLostFieldsAreNamedIndividually() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: json))
        let rebuilt = Song(title: "")
        ctx.insert(rebuilt)
        ImportService.applyResult(result, to: rebuilt, modelContext: ctx)

        #expect(rebuilt.key == "D", "key lost — re-derived from the version instead")
        #expect(rebuilt.tempo == "72", "tempo lost")
        #expect(rebuilt.tags == "botez, seara", "tags lost — rewritten from themes")
        #expect(rebuilt.songNumber == "7", "songNumber lost — emitted only when songbook == nil")
        #expect(rebuilt.sourceFile == "mare-esti-tu.tpsong", "sourceFile lost")
        // songbookNumber is NOT asserted here — see the companion test below.
    }

    /// `songDictV2` emits `songbook` **or** `songNumber` in an if/else
    /// (`ExportService.swift:362-369`), so exactly one of the pair is always
    /// lost and no single fixture can demonstrate both: with a songbook you lose
    /// `songNumber`, without one you lose `songbookNumber`.
    @Test
    func theSongbookPairIsMutuallyExclusiveAndOneIsAlwaysLost() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        song.songbook = nil               // take the OTHER branch
        song.songbookNumber = "42"

        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: json))
        let rebuilt = Song(title: "")
        ctx.insert(rebuilt)
        ImportService.applyResult(result, to: rebuilt, modelContext: ctx)

        #expect(rebuilt.songbookNumber == "42",
                "songbookNumber lost — emitted only inside the songbook dict")
    }

    /// THE bug: no file, no export, no import — just open the editor and cancel.
    @Test
    func openingTheEditorAndCancellingChangesNothing() throws {
        let ctx = try makeContext()
        let song = fullyPopulatedSong(in: ctx)
        let before = SongSnapshot(song)

        // Exactly what SongEditor does: snapshot on open, rebuild on Cancel —
        // including the two flags that make a revert a revert rather than an
        // import of a stranger's file.
        let snapshot = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: snapshot))
        ImportService.applyResult(result, to: song, modelContext: ctx,
                                  preservesTimestamps: true, preservingVersionIDs: true)

        #expect(SongSnapshot(song) == before, "Cancel must be a no-op")
    }
}

// MARK: - Bible round trip (GOAT)
//
// The native Bible format had ZERO round-trip coverage: every existing Bible
// test either parses a foreign format or hand-builds a small JSON literal, so
// nothing ever asserted that what `ExportService` writes is what
// `TopPresenterBibleImporter` reads back. That is the format shipping 70
// translations in `bibles-1`.

/// `_extensions` compared as a decoded dictionary.
///
/// The two sides re-serialize through different code paths (`JSONSerialization`
/// on export, `JSONSerialization` again on import, neither with sorted keys), so
/// comparing the raw strings would fail on key order rather than on content.
nonisolated enum ExtensionPayload {
    static func decoded(_ json: String?) -> [String: String] {
        guard let json, let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return obj.compactMapValues { $0 as? String }
    }
}

/// A whole `BibleModule` tree, for comparison across a round trip.
///
/// Nested rather than flat: a book that loses its introduction and a verse that
/// loses its gloss are both losses *of the module*, and one comparison finds
/// either — naming the level it happened at.
struct BibleModuleSnapshot: Equatable {
    var name = "", abbreviation = "", language = "", sourceFormat = ""
    var moduleDescription = "", versification = "", canon = "", contentID = ""
    var nameLocal = "", languageName = "", copyright = "", aboutText = "", textSource = ""
    var year = 0, direction = ""
    var hasWordsOfChrist = false, hasStrongs = false, incomplete = false
    var extensions: [String: String] = [:]
    var books: [BibleBookSnapshot] = []

    init(_ m: BibleModule) {
        name = m.name; abbreviation = m.abbreviation; language = m.language
        sourceFormat = m.sourceFormat; moduleDescription = m.moduleDescription
        versification = m.versification ?? ""; canon = m.canon ?? ""
        contentID = m.contentID
        nameLocal = m.nameLocal; languageName = m.languageName
        copyright = m.copyright; aboutText = m.aboutText; textSource = m.textSource
        year = m.year ?? 0; direction = m.direction
        hasWordsOfChrist = m.hasWordsOfChrist; hasStrongs = m.hasStrongs
        incomplete = m.incomplete
        extensions = ExtensionPayload.decoded(m.extensionsJSON)
        books = m.books.sorted { $0.bookNumber < $1.bookNumber }.map(BibleBookSnapshot.init)
    }

    static let coveredFields: Set<String> = [
        "name", "abbreviation", "language", "sourceFormat", "moduleDescription",
        "versification", "canon", "nameLocal", "languageName", "copyright",
        "aboutText", "textSource", "year", "direction", "hasWordsOfChrist",
        "hasStrongs", "incomplete", "extensionsJSON", "contentID", "books",
    ]

    static let exemptFields: [String: String] = [
        "id": "regenerated on import; identity is re-established by the duplicate resolver (plan §4.2)",
        "importDate": "means 'when THIS library imported it' — adopting the exporter's date would be a lie",
    ]
}

struct BibleBookSnapshot: Equatable {
    var name = "", bookNumber = 0, testament = ""
    var nameEnglish = "", abbreviation = "", abbreviationEnglish = ""
    var expectedChapters = 0, introduction = ""
    var extensions: [String: String] = [:]
    var chapters: [BibleChapterSnapshot] = []

    init(_ b: BibleBook) {
        name = b.name; bookNumber = b.bookNumber; testament = b.testament
        nameEnglish = b.nameEnglish; abbreviation = b.abbreviation
        abbreviationEnglish = b.abbreviationEnglish
        expectedChapters = b.expectedChapters; introduction = b.introduction
        extensions = ExtensionPayload.decoded(b.extensionsJSON)
        chapters = b.sortedChapters.map(BibleChapterSnapshot.init)
    }

    static let coveredFields: Set<String> = [
        "name", "bookNumber", "testament", "nameEnglish", "abbreviation",
        "abbreviationEnglish", "expectedChapters", "introduction",
        "extensionsJSON", "chapters",
    ]
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; a book's identity is its number within its module",
    ]
    /// Parent back-reference — structure, not content.
    static let relationshipFields: Set<String> = ["module"]
}

struct BibleChapterSnapshot: Equatable {
    var chapterNumber = 0
    var headings: [BibleHeading] = []
    var extensions: [String: String] = [:]
    var verses: [BibleVerseSnapshot] = []

    init(_ c: BibleChapter) {
        chapterNumber = c.chapterNumber
        headings = c.headings
        extensions = ExtensionPayload.decoded(c.extensionsJSON)
        verses = c.sortedVerses.map(BibleVerseSnapshot.init)
    }

    static let coveredFields: Set<String> = [
        "chapterNumber", "headingsJSON", "extensionsJSON", "verses",
    ]
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; a chapter's identity is its number within its book",
    ]
    static let relationshipFields: Set<String> = ["book"]
}

struct BibleVerseSnapshot: Equatable {
    var verseNumber = 0, text = ""
    var runs: [VerseRun] = []
    var footnotes: [BibleFootnote] = []
    var crossReferences: [BibleCrossRef] = []
    var hasWordsOfChrist = false
    var gloss = ""
    var poetryIndent = 0
    var extensions: [String: String] = [:]

    init(_ v: BibleVerse) {
        verseNumber = v.verseNumber; text = v.text
        runs = v.runs; footnotes = v.footnotes; crossReferences = v.crossReferences
        hasWordsOfChrist = v.hasWordsOfChrist; gloss = v.gloss
        poetryIndent = v.poetryIndent ?? 0
        extensions = ExtensionPayload.decoded(v.extensionsJSON)
    }

    static let coveredFields: Set<String> = [
        "verseNumber", "text", "runsJSON", "footnotesJSON", "crossRefsJSON",
        "hasWordsOfChrist", "gloss", "poetryIndent", "extensionsJSON",
    ]
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; a verse's identity is its number within its chapter",
    ]
    static let relationshipFields: Set<String> = ["chapter"]
}

@MainActor struct BibleRoundTripTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: BibleModule.self, BibleBook.self, BibleChapter.self, BibleVerse.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    /// A module whose every value the importer cannot re-derive from anything
    /// else in the file.
    ///
    /// It is deliberately NOT a plausible Bible. A plausible one would let
    /// several fields pass by reconstruction rather than by preservation:
    ///
    /// - `testament` is `"DC"` on book **46**, where the importer's fallback
    ///   (`bookNumber <= 39 ? "OT" : "NT"`) would say `"NT"`
    /// - `hasWordsOfChrist` is true on a verse whose runs contain **no** `woc`
    ///   run, because the importer ORs the flag with `runs.contains { woc }`
    /// - `moduleDescription` differs from `copyright`, which the importer falls
    ///   back to when `description` is absent
    /// - `name`, `nameLocal` and `abbreviation` all differ, because the module
    ///   name falls back through all three
    /// - `direction` is `"rtl"`, since `"ltr"` is what the importer defaults to
    ///   and the exporter skips — a `"ltr"` fixture proves nothing about it
    /// - `sourceFormat` is `"osis"`, not `"topPresenter"`: this module came from
    ///   somewhere else, and where it came from is part of what has to survive
    /// - heading `beforeVerse`/`level` are 2, not the decoder's defaults of 1
    /// - footnote `marker` is non-empty and cross-ref `label` is non-nil, both
    ///   of which the decoders happily default
    fileprivate func fullyPopulatedModule(in ctx: ModelContext) -> BibleModule {
        let module = BibleModule(
            name: "Biblia Ortodoxă Sinodală",
            abbreviation: "BOS",
            language: "ro",
            sourceFormat: "osis",
            moduleDescription: "Ediția sinodală, cu deuterocanonice",
            versification: "lxx",
            canon: "orthodox",
            nameLocal: "Sfânta Scriptură",
            languageName: "Română",
            copyright: "© 1988 Institutul Biblic",
            aboutText: "CUVÂNT ÎNAINTE — despre această ediție.",
            textSource: "Ediția tipărită 1988",
            year: 1988,
            direction: "rtl",
            hasWordsOfChrist: true,
            hasStrongs: true,
            incomplete: true,
            extensionsJSON: #"{"tpModuleNote":"extensii la nivel de modul"}"#
        )
        ctx.insert(module)

        let book = BibleBook(
            name: "Înțelepciunea lui Solomon",
            bookNumber: 46,
            testament: "DC",
            nameEnglish: "Wisdom of Solomon",
            abbreviation: "Înț",
            abbreviationEnglish: "Wis",
            expectedChapters: 19,
            introduction: "Introducere la cartea Înțelepciunii.",
            extensionsJSON: #"{"tpBookNote":"extensii la nivel de carte"}"#
        )
        book.module = module

        let chapter = BibleChapter(
            chapterNumber: 3,
            headingsJSON: BibleRichData.encode([
                BibleHeading(beforeVerse: 2, level: 2, text: "Soarta celor drepți")
            ]),
            extensionsJSON: #"{"tpChapterNote":"extensii la nivel de capitol"}"#
        )
        chapter.book = book

        // Verse 1 carries every rich field at once — and its runs are `add`,
        // never `woc`, so the words-of-Christ flag has to survive on its own.
        let v1 = BibleVerse(
            verseNumber: 1,
            text: "Sufletele drepților sunt în mâna lui Dumnezeu.",
            runsJSON: BibleRichData.encode([
                VerseRun(text: "Sufletele drepților", kind: "add",
                         strong: "H5315", morph: "N-NSF", gloss: "souls-of-the-righteous"),
                VerseRun(text: " sunt în mâna lui Dumnezeu.", kind: "plain")
            ]),
            footnotesJSON: BibleRichData.encode([
                BibleFootnote(marker: "a", text: "Sau: în puterea lui Dumnezeu.")
            ]),
            crossRefsJSON: BibleRichData.encode([
                BibleCrossRef(label: "cf.", targets: ["Deut 33:3", "Ioan 10:28"])
            ]),
            hasWordsOfChrist: true,
            gloss: "the souls of the righteous are in God's hand",
            poetryIndent: 2,
            extensionsJSON: #"{"tpVerseNote":"extensii la nivel de verset"}"#
        )
        v1.chapter = chapter

        // Verse 2 is deliberately narrow: it exists to exercise a `woc` run and
        // verse ordering. `theFixtureIsExhaustive` checks verse 1 only.
        let v2 = BibleVerse(
            verseNumber: 2,
            text: "Eu sunt lumina lumii.",
            runsJSON: BibleRichData.encode([VerseRun(text: "Eu sunt lumina lumii.", kind: "woc")]),
            hasWordsOfChrist: true
        )
        v2.chapter = chapter

        return module
    }

    /// Round trip through a real file, into a SEPARATE store.
    ///
    /// A separate store matters: re-importing into the same one hits the
    /// same-abbreviation duplicate path, and `.keepBoth` would rename the module
    /// to "… (2)" — a rename that has nothing to do with format integrity would
    /// show up as a name loss and obscure the real ones.
    private func roundTrip(_ module: BibleModule) async throws -> BibleModule {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rt_bible_\(UUID().uuidString).tpbible")
        try await ExportService.exportBible(module: module, format: .topPresenter, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let fresh = try makeContext()
        return try await ImportService.importBible(
            fileURL: url, format: .topPresenter, modelContext: fresh, resolution: .keepBoth).module
    }

    @Test func theFixtureIsExhaustive() throws {
        let ctx = try makeContext()
        let snapshot = BibleModuleSnapshot(fullyPopulatedModule(in: ctx))
        assertFullyPopulated(snapshot)
        let book = try #require(snapshot.books.first)
        assertFullyPopulated(book)
        let chapter = try #require(book.chapters.first)
        assertFullyPopulated(chapter)
        let verse = try #require(chapter.verses.first)
        assertFullyPopulated(verse)
    }

    @Test
    func everyFieldSurvivesAGoatRoundTrip() async throws {
        let ctx = try makeContext()
        let module = fullyPopulatedModule(in: ctx)
        let before = BibleModuleSnapshot(module)

        let rebuilt = try await roundTrip(module)

        #expect(BibleModuleSnapshot(rebuilt) == before)
    }

    /// E1 — the asymmetry is one level deep and invisible from either side alone:
    /// `ExportService.swift:155` writes `translationDict["_extensions"]`, and
    /// `TopPresenterBibleImporter.swift:176` reads `json["_extensions"]` from the
    /// ROOT. Book, chapter and verse extensions round-trip correctly, which is
    /// exactly why nobody noticed the module's do not.
    @Test
    func moduleExtensionsSurviveWhileTheOtherThreeLevelsAlreadyDo() async throws {
        let ctx = try makeContext()
        let rebuilt = try await roundTrip(fullyPopulatedModule(in: ctx))
        let snapshot = BibleModuleSnapshot(rebuilt)

        // The control: these three prove the mechanism works and isolate the bug
        // to the module level rather than to `_extensions` in general.
        let book = try #require(snapshot.books.first)
        let chapter = try #require(book.chapters.first)
        let verse = try #require(chapter.verses.first)
        #expect(book.extensions["tpBookNote"] == "extensii la nivel de carte")
        #expect(chapter.extensions["tpChapterNote"] == "extensii la nivel de capitol")
        #expect(verse.extensions["tpVerseNote"] == "extensii la nivel de verset")

        #expect(snapshot.extensions["tpModuleNote"] == "extensii la nivel de modul",
                "module _extensions lost — written under `translation`, read from the root")
    }

    /// E2 — `importBible` hardcodes `sourceFormat: format.rawValue`, so every
    /// module that passes through an export becomes "topPresenter" and forgets
    /// it was ever OSIS, Zefania or MySword. The exporter never writes the field
    /// at all, so there is nothing for the importer to preserve either.
    @Test
    func theOriginalSourceFormatSurvives() async throws {
        let ctx = try makeContext()
        let rebuilt = try await roundTrip(fullyPopulatedModule(in: ctx))

        #expect(rebuilt.sourceFormat == "osis",
                "sourceFormat became '\(rebuilt.sourceFormat)' — the module's provenance was overwritten by the format it happened to be re-imported from")
    }

    /// E3 — `TopPresenterBibleImporter.swift:118` parses `poetryIndent` into
    /// `BibleImportVerse`, `ImportService` never reads it back out, and no model
    /// has anywhere to put it. Parsed, carried one layer, dropped. This asserts
    /// the field exists before asserting any value survives it.
    @Test
    func poetryIndentHasSomewhereToLand() {
        #expect(PersistedFieldNames.of(BibleVerse.self).contains("poetryIndent"), """
            BibleImportVerse.poetryIndent is parsed from every TopPresenter Bible \
            and then discarded, because BibleVerse has no field for it.
            """)
    }

    /// G4 — the guarantee named in plan §4.4: importing the same file twice with
    /// default policies is a no-op. Today the default is `.keepBoth`, so the
    /// second import silently creates "Biblia Ortodoxă Sinodală (2)".
    @Test
    func importingTheSameFileTwiceIsANoOp() async throws {
        let source = try makeContext()
        let module = fullyPopulatedModule(in: source)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("idem_bible_\(UUID().uuidString).tpbible")
        try await ExportService.exportBible(module: module, format: .topPresenter, to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let target = try makeContext()
        _ = try await ImportService.importBible(fileURL: url, format: .topPresenter, modelContext: target)
        _ = try await ImportService.importBible(fileURL: url, format: .topPresenter, modelContext: target)

        let modules = try target.fetch(FetchDescriptor<BibleModule>())
        #expect(modules.count == 1,
                "the same file imported twice produced \(modules.map(\.name)) — identical content must be skipped, not duplicated")
    }
}

// MARK: - Session round trip (.tpschedule)
//
// `exportImportRoundTripPreservesEverything` does not preserve everything, and
// never claimed to in code: it asserts five fields across three item kinds and
// never builds a song or media item at all. A session's whole job is to survive
// leaving one library and arriving at another, so what it drops on the way is
// the one thing worth pinning down.

/// A `ScheduleItem`'s exportable state. The payload is compared as a decoded
/// struct, not as `payloadJSON`: both sides re-encode it, and comparing the
/// strings would turn a key-order difference into a phantom data loss.
@MainActor struct ScheduleItemSnapshot: Equatable {
    var title = "", itemType = "", content = "", subtitle = ""
    var order = 0
    var payload = SessionItemPayload()

    /// The blueprint `assertCollectivelyPopulated` reflects over.
    init() {}

    init(_ i: ScheduleItem) {
        title = i.title; itemType = i.itemType; content = i.content
        subtitle = i.subtitle; order = i.order
        payload = SessionService.payload(for: i)
    }

    static let coveredFields: Set<String> = [
        "title", "itemType", "content", "subtitle", "order", "payloadJSON",
    ]
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; a session item's identity is its order within its session",
        "referenceID": "documented dead field (PresentationModels.swift:213) — kept only so old stores still open",
    ]
    static let relationshipFields: Set<String> = ["schedule"]
}

@MainActor struct ServiceScheduleSnapshot: Equatable {
    var name = "", notes = ""
    var date = Date.distantPast
    var items: [ScheduleItemSnapshot] = []

    init(_ s: ServiceSchedule) {
        name = s.name; notes = s.notes; date = s.date
        items = s.sortedItems.map(ScheduleItemSnapshot.init)
    }

    static let coveredFields: Set<String> = ["name", "notes", "date", "items"]
    /// Not compared across a round trip: a locally-authored session has none
    /// until it is exported, and one that arrived carries the sender's. Its
    /// behaviour is asserted directly by the idempotency test instead.
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; identity comes from sourceSessionID instead",
        "sourceSessionID": "the SENDER's identity, deliberately not the local id — asserted by importingTheSameSessionTwiceIsANoOp",
    ]
}

@MainActor struct SessionRoundTripTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// A session holding one of every item kind, built through `SessionService`
    /// rather than by hand — a fixture that writes payloads directly would test
    /// the archive against itself and skip the code that fills them in.
    ///
    /// The date is a whole second on purpose: `dateISO` is written by
    /// `ISO8601DateFormatter`, which has no sub-second precision, so a `.now`
    /// fixture would fail on milliseconds and say nothing about the format.
    private func fullyPopulatedSession(in ctx: ModelContext) -> ServiceSchedule {
        let date = ISO8601DateFormatter().date(from: "2026-08-09T08:30:00Z") ?? .now
        let schedule = ServiceSchedule(name: "Duminică dimineața", date: date, notes: "Cu botez")
        ctx.insert(schedule)

        SessionService.append(.bible(translation: "EDC100", bookNumber: 43, bookName: "Ioan",
                                     chapter: 3, verseStart: 16, verseEnd: 17,
                                     displayReference: "Ioan 3:16-17", snapshotText: "Fiindcă atât de mult…"),
                              to: schedule, context: ctx)

        // A song item, which nothing has ever round-tripped.
        let song = Song(title: "Mare ești Tu", author: "Anon", ccliNumber: "7104200")
        ctx.insert(song)
        let version = SongVersion(name: "Clasică", order: 0, language: "ro", key: "G")
        version.song = song
        ctx.insert(version)
        // The version needs a section: a version with no sections does not
        // survive an export/rebuild at all, and a test about version IDENTITY
        // would then be failing for the unrelated reason that it vanished.
        let section = SongSection(sectionKey: "v1", type: "verse", label: "Strofa 1", order: 0, lines: [
            SongLine(text: "Mare ești Tu", chords: [], translations: [:])
        ])
        section.version = version
        ctx.insert(section)
        SessionService.append(.song(song, version: version), to: schedule, context: ctx)

        let media = MediaItem(name: "intro.mp4", filePath: "/a/intro.mp4", mediaType: "video")
        ctx.insert(media)
        SessionService.append(.media(media), to: schedule, context: ctx)

        SessionService.append(.text(title: "Anunțuri", content: "Program de vară"), to: schedule, context: ctx)
        SessionService.append(.blank, to: schedule, context: ctx)
        return schedule
    }

    /// Import into a library that already holds the same media, so the media
    /// re-link succeeds and the comparison is about the format rather than about
    /// a deliberately unresolvable reference.
    private func roundTrip(_ schedule: ServiceSchedule) throws -> ServiceSchedule {
        let data = try SessionArchiveService.export(schedule)
        let dest = try makeContext()
        for item in schedule.sortedItems where item.itemType == "media" {
            let payload = SessionService.payload(for: item)
            let local = MediaItem(name: payload.mediaName, filePath: "/b/\(payload.mediaName)",
                                  mediaType: item.subtitle.lowercased())
            dest.insert(local)
        }
        try dest.save()
        return try SessionArchiveService.importSession(data, context: dest).schedule
    }

    @Test func theFixtureExercisesEveryItemKindAndEveryPayloadField() throws {
        let ctx = try makeContext()
        let items = ServiceScheduleSnapshot(fullyPopulatedSession(in: ctx)).items

        #expect(Set(items.map(\.itemType)) == ["bible", "song", "media", "text", "blank"],
                "a kind with no fixture item is a kind with no coverage")

        // No single item can be exhaustive — a Bible reference has no songKey —
        // so the twelve payload fields are only reachable across the whole set.
        assertCollectivelyPopulated(items.map(\.payload), covering: SessionItemPayload(),
                                    label: "session item payload")
        assertCollectivelyPopulated(items, covering: ScheduleItemSnapshot(),
                                    exempt: ["payload"], label: "session item")
    }

    @Test func everySessionFieldSurvivesTheArchive() throws {
        let ctx = try makeContext()
        let schedule = fullyPopulatedSession(in: ctx)
        var before = ServiceScheduleSnapshot(schedule)

        let imported = try roundTrip(schedule)

        // The media item is deliberately re-linked to the destination library's
        // own copy, so its id legitimately changes; the NAME is what has to
        // survive, and it is what the re-link matched on.
        for index in before.items.indices where before.items[index].itemType == "media" {
            before.items[index].payload.mediaID = ""
        }
        var after = ServiceScheduleSnapshot(imported)
        for index in after.items.indices where after.items[index].itemType == "media" {
            after.items[index].payload.mediaID = ""
        }

        #expect(after == before)
    }

    /// The song payload specifically — four fields, none of them ever asserted
    /// before, and the two that matter (`songKey`, `versionID`) are what makes a
    /// shared running order point at the right arrangement on arrival.
    @Test func theSongItemArrivesWithItsStableReferenceIntact() throws {
        let ctx = try makeContext()
        let schedule = fullyPopulatedSession(in: ctx)
        let sent = try #require(schedule.sortedItems.first { $0.itemType == "song" })
        let sentPayload = SessionService.payload(for: sent)

        let imported = try roundTrip(schedule)
        let arrived = try #require(imported.sortedItems.first { $0.itemType == "song" })
        let payload = SessionService.payload(for: arrived)

        #expect(payload.songKey == sentPayload.songKey)
        #expect(payload.songTitle == "Mare ești Tu")
        #expect(payload.versionID == sentPayload.versionID)
        #expect(payload.versionName == "Clasică")
        #expect(arrived.subtitle == "Anon · Clasică", "the display snapshot is what shows when the song is not in the destination library")
    }

    /// G4 — plan §4.4. `SessionArchive.swift:135` inserts unconditionally, with
    /// no identity check of any kind, so a `.tpschedule` opened twice is simply
    /// there twice.
    @Test
    func importingTheSameSessionTwiceIsANoOp() throws {
        let ctx = try makeContext()
        let data = try SessionArchiveService.export(fullyPopulatedSession(in: ctx))

        let dest = try makeContext()
        _ = try SessionArchiveService.importSession(data, context: dest)
        _ = try SessionArchiveService.importSession(data, context: dest)

        let sessions = try dest.fetch(FetchDescriptor<ServiceSchedule>())
        #expect(sessions.count == 1,
                "the same session imported twice produced \(sessions.count) copies")
    }

    /// E5, seen from the session side. `ImportService.applyResult` rebuilds a
    /// song's versions with fresh UUIDs, so every session that pointed at one is
    /// left pointing at nothing — including sessions in this same library, since
    /// the song editor's Cancel path runs exactly this code.
    ///
    /// Today the `versionName` fallback (`SessionService.swift:184`) hides it,
    /// which is why it has gone unnoticed: rename an arrangement after sharing a
    /// running order and the reference is simply gone.
    @Test
    func aSessionsVersionReferenceSurvivesReimportingTheSong() throws {
        let ctx = try makeContext()
        let schedule = fullyPopulatedSession(in: ctx)
        let item = try #require(schedule.sortedItems.first { $0.itemType == "song" })
        let payload = SessionService.payload(for: item)
        let song = try #require(ctx.fetch(FetchDescriptor<Song>()).first)
        #expect(song.versions.contains { $0.id.uuidString == payload.versionID })

        // Exactly what pressing Cancel in the song editor does. The save matters:
        // before it, the deleted versions are still sitting in the relationship
        // array and the reference looks intact when it is already gone.
        let json = try ExportService.exportSongToTopPresenterJSON(song)
        let result = try #require(TopPresenterSongImporter.result(fromJSON: json))
        ImportService.applyResult(result, to: song, modelContext: ctx,
                                  preservesTimestamps: true, preservingVersionIDs: true)
        try ctx.save()

        #expect(song.versions.count == 1, "the arrangement should have been rebuilt, not multiplied")
        #expect(song.versions.contains { $0.id.uuidString == payload.versionID }, """
            the session points at version \(payload.versionID), which no longer exists. \
            Only the versionName fallback still resolves it, and that fails the \
            moment an arrangement is renamed.
            """)
    }
}

// MARK: - Custom slides — the format that does not exist yet
//
// Custom Slides can neither import nor export, so there is nothing to
// round-trip. The snapshot is written now anyway, as the CONTRACT `.tpslides`
// has to meet in Phase 6: a field added to PresentationSlide between now and
// then fails the coverage test and gets carried, instead of being discovered
// missing after the format ships.

struct PresentationSlideSnapshot: Equatable {
    var title = "", content = "", subtitle = "", slideType = ""
    var order = 0

    init(_ s: PresentationSlide) {
        title = s.title; content = s.content; subtitle = s.subtitle
        slideType = s.slideType; order = s.order
    }

    static let coveredFields: Set<String> = ["title", "content", "subtitle", "slideType", "order"]
    static let exemptFields: [String: String] = [
        "id": "regenerated on import; a slide's identity is its content digest (plan §4.2)",
        "createdDate": "means 'when THIS library made it' — a slide arriving from elsewhere is new here",
    ]
}

// MARK: - What the folder walk can see
//
// Three defects, all in `expandToImportableFiles`, all invisible to the
// operator: the drop simply does nothing and nothing says why.

@MainActor struct ImportScannerTests {

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("scan-\(UUID().uuidString)")
        for (relativePath, contents) in files {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        return root
    }

    private static let openSongXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <song><title>Mare ești Tu</title><author>Anon</author>
        <lyrics>[V1]
        Mare ești Tu</lyrics></song>
        """

    /// Dropping a folder of photos imports nothing. The filter is Bible/Song
    /// extensions only (`DragDropImportHandler.swift:95-97`), and media is
    /// excluded on purpose — the comment cites multi-GB drone footage
    /// beach-balling the app, which is a real risk. So the fix is not "drop the
    /// filter" but "widen it to every kind we can import", which still never
    /// opens a file it cannot use.
    @Test
    func aFolderOfPhotosYieldsItsPhotos() throws {
        let root = try makeTree([
            "poze/fundal.jpg": "not really a jpeg",
            "poze/logo.png": "not really a png",
            "poze/clip.mp4": "not really a video",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ImportScanner.scan([root]).files
        #expect(found.count == 3,
                "a folder of photos yielded \(found.map(\.lastPathComponent)) — dropping it does nothing at all")
    }

    /// OpenSong files have NO extension, which `isImportableFile` requires — even
    /// though `SongImportProtocol.swift:34-48` explicitly accepts extensionless
    /// files when handed them directly. Drop the file: it imports. Drop the
    /// folder containing it: nothing happens.
    @Test
    func aFolderOfExtensionlessOpenSongFilesYieldsThem() throws {
        let root = try makeTree([
            "cantari/MareEstiTu": Self.openSongXML,
            "cantari/CeMareEsti": Self.openSongXML,
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ImportScanner.scan([root]).files
        #expect(found.count == 2,
                "extensionless OpenSong files were skipped by the folder walk, though dropping one directly imports it")
    }

    /// The depth cap is 3, and a real songbook tree is deeper than that —
    /// `Cântări/Tineret/2026/Vara/…` is four before a single file. The cap
    /// exists as beach-ball protection, which the extension filter already
    /// provides; Phase 2 replaces it with a budget that REPORTS truncation
    /// instead of silently stopping.
    @Test
    func theWalkReachesPastTheThirdLevel() throws {
        let root = try makeTree([
            "Cantari/Tineret/2026/Vara/cantec.chordpro": "{title: Mare ești Tu}\nMare ești Tu",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        let found = ImportScanner.scan([root]).files
        #expect(found.count == 1,
                "a file four folders deep is invisible to the walk, and nothing tells the operator it was skipped")
    }

    /// Two media extension lists that do not agree, in a codebase where which
    /// one you happen to ask decides whether a file is importable at all.
    ///
    /// `DragDropImportHandler.MediaExtensions` knows svg, ico and flv;
    /// `MediaKind.classify` knows none of them and answers `.image` for all
    /// three via its fallback — so an `.flv` classified as video by one is an
    /// image to the other. Plan §6.A collapses them into `MediaKind`.
    @Test
    func bothMediaListsAgreeOnEveryExtension() throws {
        let root = try makeTree([
            "a.svg": "<svg/>", "b.ico": "icon", "c.flv": "flash", "d.mp4": "video", "e.jpg": "photo",
        ])
        defer { try? FileManager.default.removeItem(at: root) }

        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            guard case let .media(kindRaw) = DragDropImportHandler.classify(url) else { continue }
            let kind = MediaKind.classify(extension: url.pathExtension)
            #expect(kind?.rawValue == kindRaw,
                    "\(url.lastPathComponent): the drop handler says \(kindRaw), MediaKind says \(kind?.rawValue ?? "not media")")
        }
    }

    /// `MediaKind.classify` cannot say "this is not media" — it answers `.image`
    /// for anything it does not recognise. Harmless while only a media picker
    /// calls it; the moment the folder walk recurses (Phase 2) it would turn a
    /// stray `.docx` into a media item.
    @Test
    func anUnknownExtensionIsNotSilentlyAnImage() {
        #expect(MediaKind.classify(extension: "docx") != .image,
                "an unrecognised extension answers .image, so recursing a folder would import documents as photos")
    }
}

// MARK: - The format registry
//
// `ImportCatalog` is only worth having if it cannot drift from the enums it
// describes. These check that it is genuinely derived rather than a fourth
// hand-maintained list that happens to agree today.

@MainActor struct ImportCatalogTests {

    @Test func everyFormatEnumIsRepresented() {
        let bible = Set(ImportCatalog.all.filter { $0.kind == .bible }.map(\.displayName))
        for format in SupportedBibleFormat.allCases {
            #expect(bible.contains(format.displayName), "\(format) is missing from the catalog")
        }
        let song = Set(ImportCatalog.all.filter { $0.kind == .song }.map(\.displayName))
        for format in SupportedSongFormat.allCases {
            #expect(song.contains(format.displayName), "\(format) is missing from the catalog")
        }
        let media = Set(ImportCatalog.all.filter { $0.kind == .media }.map(\.displayName))
        for kind in MediaKind.allCases {
            #expect(media.contains(kind.filterLabel), "\(kind) is missing from the catalog")
        }
    }

    /// The regression that started all of this: media extensions were absent
    /// from the walk's filter, so a folder of photos yielded nothing.
    @Test func mediaExtensionsAreImportable() {
        for ext in ["jpg", "png", "heic", "svg", "mp4", "mov", "mp3", "wav"] {
            #expect(ImportCatalog.importableExtensions.contains(ext), "\(ext) is not importable")
        }
        #expect(!ImportCatalog.importableExtensions.contains("flv"),
                "flv is listed as importable, but AVPlayer cannot play it")
    }

    @Test func candidacyOpensOnlyWhatItMust() {
        func candidacy(_ name: String) -> ImportCatalog.Candidacy {
            ImportCatalog.candidacy(of: URL(fileURLWithPath: "/tmp/\(name)"))
        }
        #expect(candidacy("biblia.tpbible") == .accept)
        #expect(candidacy("cantec.tpsong") == .accept)
        #expect(candidacy("fundal.jpg") == .accept)
        // .json is no longer ours. It is refused rather than guessed at, and
        // the sheet answers with what to DO about it — see
        // `ImportPlanModel.reason(unsupported:)`.
        #expect(candidacy("biblia.json") == .reject)
        #expect(candidacy("raport.docx") == .reject)      // never opened
        #expect(candidacy("MareEstiTu") == .probe)        // extensionless OpenSong
    }

    /// `.xml` and `.txt` are genuinely ambiguous — four formats claim `.xml`
    /// across two libraries — so the catalog answers with a SET and leaves the
    /// decision to a content probe. A single-answer lookup would have to guess.
    @Test func ambiguousExtensionsReportEveryPossibility() {
        let xml = ImportCatalog.possibleKinds(for: URL(fileURLWithPath: "/tmp/a.xml"))
        #expect(xml == [.bible, .song])
        let txt = ImportCatalog.possibleKinds(for: URL(fileURLWithPath: "/tmp/a.txt"))
        #expect(txt == [.bible, .song])
        let jpg = ImportCatalog.possibleKinds(for: URL(fileURLWithPath: "/tmp/a.jpg"))
        #expect(jpg == [.media])
    }

    /// Directory sources are documents, not folders to walk into.
    @Test func packageAndFolderFormatsAreMarked() {
        #expect(ImportCatalog.directoryExtensions.contains("tptheme"))
        let usfm = ImportCatalog.all.first { $0.id == "bible.usfm" }
        #expect(usfm?.isDirectorySource == true)
    }

    /// Custom Slides could neither import nor export until v1 — the one library
    /// whose contents existed on exactly one machine.
    @Test func customSlidesAreAFormatNow() {
        let slides = ImportCatalog.all.first { $0.kind == .slides }
        #expect(slides?.canImport == true)
        #expect(slides?.canExport == true)
        #expect(ImportCatalog.importableExtensions.contains("tpslides"))
    }

    /// The native formats own their extensions, and `.json` is not one of them.
    @Test func theNativeFormatsClaimTheirOwnExtensions() {
        for format in TopPresenterFormat.allCases {
            #expect(ImportCatalog.importableExtensions.contains(format.fileExtension),
                    "\(format) is not importable under .\(format.fileExtension)")
        }
        #expect(!ImportCatalog.importableExtensions.contains("json"),
                "a .json is refused with an actionable message, not imported")
    }

    /// An open panel scoped to one library must not offer another's files.
    @Test func panelTypesCanBeScopedToOneLibrary() {
        let bibleOnly = ImportCatalog.contentTypes(for: [.bible])
            .compactMap(\.preferredFilenameExtension)
        #expect(!bibleOnly.contains("jpg"))
        #expect(ImportCatalog.contentTypes(for: [.media])
            .compactMap(\.preferredFilenameExtension).contains("mp4"))
    }
}

// MARK: - "Have I already got this?"
//
// The resolver is a pure function over value types, on purpose: the batch path
// and the interactive path both call it, which is what stopped them agreeing
// last time. These are the cases the answers have to get right.

@MainActor struct DuplicateResolverTests {

    // MARK: Bible

    private func kjv(_ mutate: (inout BibleIdentity) -> Void = { _ in }) -> BibleIdentity {
        var identity = BibleIdentity(contentID: "", abbreviation: "KJV", language: "en",
                                     name: "King James Version", bookCount: 66,
                                     verseCount: 31_102, contentDigest: "aaa")
        mutate(&identity)
        return identity
    }

    @Test func theSameModuleTwiceIsIdentical() {
        let verdict = DuplicateResolver.verdict(for: kjv(), against: [kjv()])
        guard case .identical(let match) = verdict else {
            Issue.record("expected .identical, got \(verdict)"); return
        }
        #expect(match.differences.isEmpty)
        #expect(match.confidence == .strong)   // matched on abbreviation + language
    }

    /// The distinction the whole design rests on: same name is not same content.
    @Test func sameAbbreviationDifferentEditionSaysHowTheyDiffer() {
        let revised = kjv { $0.verseCount = 31_086; $0.contentDigest = "bbb" }
        let verdict = DuplicateResolver.verdict(for: revised, against: [kjv()])
        guard case .sameIdentityDifferentContent(let match) = verdict else {
            Issue.record("expected .sameIdentityDifferentContent, got \(verdict)"); return
        }
        #expect(match.differences.count == 1)
        // Digits only: the message is localized and groups them ("31.086"), and
        // what matters is that BOTH counts reach the operator — they can only
        // choose well if they can see what was compared.
        let digits = String(match.differences[0].filter(\.isNumber))
        #expect(digits.contains("31086"), "the incoming count is missing from \(match.differences[0])")
        #expect(digits.contains("31102"), "the existing count is missing from \(match.differences[0])")
        #expect(DuplicatePolicy.suggested(for: verdict, kind: .bible) == .ask)
    }

    /// A Romanian and an English module can legitimately share an abbreviation.
    /// Matching on the code alone merged them.
    @Test func sameAbbreviationInAnotherLanguageIsNotTheSameModule() {
        let romanian = kjv { $0.language = "ro"; $0.name = "Versiunea King James"; $0.contentDigest = "ccc" }
        #expect(DuplicateResolver.verdict(for: romanian, against: [kjv()]) == .unique)
    }

    /// A module with no abbreviation was never matched at all, so every
    /// re-import of one silently duplicated it.
    @Test func aModuleWithNoAbbreviationFallsBackToItsName() {
        let anonymous = kjv { $0.abbreviation = "" }
        let verdict = DuplicateResolver.verdict(for: anonymous, against: [anonymous])
        guard case .identical(let match) = verdict else {
            Issue.record("expected .identical, got \(verdict)"); return
        }
        #expect(match.confidence == .weak)
    }

    /// contentID outranks everything: a module renamed after export is still
    /// that module.
    @Test func contentIDWinsOverEveryOtherRule() {
        let original = kjv { $0.contentID = "ID-1" }
        let renamed = kjv { $0.contentID = "ID-1"; $0.abbreviation = "KJ21"; $0.name = "Renamed" }
        let verdict = DuplicateResolver.verdict(for: renamed, against: [original])
        #expect(verdict.match?.confidence == .certain)
    }

    // MARK: Song

    private func song(_ mutate: (inout SongIdentity) -> Void = { _ in }) -> SongIdentity {
        var identity = SongIdentity(ccliNumber: "7104200", normalizedTitle: "mare esti tu",
                                    normalizedFirstLine: "mare esti tu doamne",
                                    versionCount: 1, sectionCount: 4, lyricsDigest: "aaa")
        mutate(&identity)
        return identity
    }

    @Test func sameCCLIWithADifferentTitleIsStillTheSameSong() {
        let translated = song { $0.normalizedTitle = "how great thou art"
                                $0.normalizedFirstLine = "o lord my god"
                                $0.lyricsDigest = "bbb" }
        let verdict = DuplicateResolver.verdict(for: translated, against: [song()])
        #expect(verdict.match?.confidence == .certain)
        #expect(verdict.match?.matchedOn.contains("7104200") == true)
        #expect(DuplicatePolicy.suggested(for: verdict, kind: .song) == .addAsVersion)
    }

    /// Titles vary across translations and songbooks; first lines do not. This
    /// is the upgrade over matching on the title alone.
    @Test func sameTitleButADifferentFirstLineIsOnlyProbable() {
        let other = song { $0.ccliNumber = ""
                           $0.normalizedFirstLine = "cat de mare esti tu"
                           $0.lyricsDigest = "bbb" }
        let existing = song { $0.ccliNumber = "" }
        let verdict = DuplicateResolver.verdict(for: other, against: [existing])
        guard case .probable(let match) = verdict else {
            Issue.record("expected .probable, got \(verdict)"); return
        }
        #expect(match.confidence == .weak)
        // Two different songs that happen to share a title must NOT be merged.
        #expect(DuplicatePolicy.suggested(for: verdict, kind: .song) == .keepBoth)
    }

    @Test func sameTitleAndFirstLineIsStrongEnoughToBeAnArrangement() {
        let incoming = song { $0.ccliNumber = ""; $0.versionCount = 2; $0.lyricsDigest = "bbb" }
        let existing = song { $0.ccliNumber = "" }
        let verdict = DuplicateResolver.verdict(for: incoming, against: [existing])
        #expect(verdict.match?.confidence == .strong)
        #expect(DuplicatePolicy.suggested(for: verdict, kind: .song) == .addAsVersion)
    }

    // MARK: Media

    @Test func mediaMatchesByPathAndThenByNameAndSize() {
        let onDisk = MediaIdentity(resolvedPath: "/Users/x/fundal.jpg", filename: "fundal.jpg", byteSize: 2048)
        #expect(DuplicateResolver.verdict(for: onDisk, against: [onDisk]).match?.confidence == .certain)

        // The same file reached by a different path — a copied library folder.
        let moved = MediaIdentity(resolvedPath: "/Volumes/Stick/fundal.jpg", filename: "fundal.jpg", byteSize: 2048)
        #expect(DuplicateResolver.verdict(for: moved, against: [onDisk]).match?.confidence == .strong)

        // Same name, different size: a different picture.
        let different = MediaIdentity(resolvedPath: "/Volumes/Stick/fundal.jpg", filename: "fundal.jpg", byteSize: 9999)
        #expect(DuplicateResolver.verdict(for: different, against: [onDisk]) == .unique)
    }

    /// The stated limit: no content hash, because hashing multi-GB video on
    /// import beach-balls. Two different clips with the same name and byte size
    /// are taken for one, and that is written down rather than hidden.
    @Test func mediaAtTheSamePathThatChangedSizeIsFlaggedNotSkipped() {
        let before = MediaIdentity(resolvedPath: "/a/clip.mp4", filename: "clip.mp4", byteSize: 100)
        let after = MediaIdentity(resolvedPath: "/a/clip.mp4", filename: "clip.mp4", byteSize: 200)
        let verdict = DuplicateResolver.verdict(for: after, against: [before])
        guard case .sameIdentityDifferentContent(let match) = verdict else {
            Issue.record("expected .sameIdentityDifferentContent, got \(verdict)"); return
        }
        #expect(!match.differences.isEmpty)
    }

    // MARK: Within one batch

    /// The scanner drops the same PATH picked twice. It cannot see that
    /// `Biblia.tpbible` and `Biblia copy.tpbible` are the same file.
    @Test func identicalFilesInOneBatchKeepOnlyTheFirst() {
        let a = ContentFingerprint(byteSize: 1000, digest: "aaa")
        let b = ContentFingerprint(byteSize: 2000, digest: "bbb")
        let duplicates = DuplicateResolver.duplicatesWithinBatch([a, b, a, a, nil, b])
        #expect(duplicates == [2: 0, 3: 0, 5: 1])
        #expect(duplicates[0] == nil, "the first of each group is the one that is kept")
        #expect(duplicates[4] == nil, "a file with no fingerprint is never called a duplicate")
    }

    // MARK: Policy

    @Test func eachKindOffersOnlyThePoliciesThatMeanSomethingForIt() {
        #expect(DuplicatePolicy.allowed(for: .bible).contains(.merge))
        #expect(!DuplicatePolicy.allowed(for: .song).contains(.merge),
                "merging two songs is not a thing the app can do")
        #expect(DuplicatePolicy.allowed(for: .song).contains(.addAsVersion))
        #expect(!DuplicatePolicy.allowed(for: .bible).contains(.addAsVersion))
        #expect(!DuplicatePolicy.allowed(for: .media).contains(.ask),
                "asking per photo would make a 200-file import unusable")
    }

    /// The guarantee the whole feature is judged by (plan §4.4).
    @Test func identicalContentIsAlwaysSkippedWhateverTheKind() {
        let match = DuplicateMatch(existingIndex: 0, confidence: .certain, matchedOn: "x", differences: [])
        for kind in ImportKind.allCases {
            #expect(DuplicatePolicy.suggested(for: .identical(match), kind: kind) == .skip,
                    "\(kind) would not skip an exact duplicate")
        }
    }
}

// MARK: - Media import
//
// Media was the only kind with NO duplicate check of any sort, so the same
// photo could be imported without limit and the grid filled with identical
// tiles. There were also two import paths that disagreed about what importing
// media means — one made thumbnails for images only and never read a duration.

@MainActor struct MediaImportServiceTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func makeFiles(_ names: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("media-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names {
            try Data("pretend \(name)".utf8).write(to: root.appendingPathComponent(name))
        }
        return root
    }

    /// G4 for media — plan §4.4.
    @Test func importingTheSamePhotoTwiceIsANoOp() throws {
        let ctx = try makeContext()
        let root = try makeFiles(["fundal.jpg", "clip.mp4"])
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = ["fundal.jpg", "clip.mp4"].map { root.appendingPathComponent($0) }

        let first = MediaImportService.importMedia(urls: urls, modelContext: ctx)
        #expect(first.imported.count == 2)
        #expect(first.skipped.isEmpty)

        let second = MediaImportService.importMedia(urls: urls, modelContext: ctx)
        #expect(second.imported.isEmpty)
        #expect(second.skipped.count == 2)
        #expect(try ctx.fetch(FetchDescriptor<MediaItem>()).count == 2,
                "the same files imported twice produced a second copy of each")
        // The row has to say WHAT it matched, or a skip is indistinguishable
        // from a failure.
        #expect(second.skipped.allSatisfy { !$0.matchedOn.isEmpty })
    }

    /// The classifier can say "not media" now, so a stray document in a picked
    /// folder is reported rather than filed as a photo.
    @Test func aNonMediaFileIsReportedNotImportedAsAnImage() throws {
        let ctx = try makeContext()
        let root = try makeFiles(["notes.docx", "fundal.png"])
        defer { try? FileManager.default.removeItem(at: root) }

        let outcome = MediaImportService.importMedia(
            urls: ["notes.docx", "fundal.png"].map { root.appendingPathComponent($0) },
            modelContext: ctx)
        #expect(outcome.imported.count == 1)
        #expect(outcome.unsupported.map(\.lastPathComponent) == ["notes.docx"])
    }

    /// `.keepBoth` is a real choice for media — the same picture under two
    /// names is sometimes deliberate — so the policy has to be honoured.
    @Test func keepBothImportsTheDuplicateAnyway() throws {
        let ctx = try makeContext()
        let root = try makeFiles(["fundal.jpg"])
        defer { try? FileManager.default.removeItem(at: root) }
        let urls = [root.appendingPathComponent("fundal.jpg")]

        _ = MediaImportService.importMedia(urls: urls, modelContext: ctx)
        let again = MediaImportService.importMedia(urls: urls, modelContext: ctx, policy: .keepBoth)
        #expect(again.imported.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<MediaItem>()).count == 2)
    }
}

// MARK: - The coordinator

@MainActor struct ImportCoordinatorTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    /// Media before sessions is a correctness rule, not a preference:
    /// `importSession` re-links media against the library AS IT STANDS, so a
    /// session imported first arrives with everything reported missing.
    @Test func mediaRunsBeforeSessions() {
        let order = ImportCoordinator.kindOrder
        let media = try? #require(order.firstIndex(of: .media))
        let session = try? #require(order.firstIndex(of: .session))
        #expect(media != nil && session != nil)
        #expect(media! < session!, "a session imported before its media resolves to nothing")
    }

    @Test func theSummaryDistinguishesImportedFromAlreadyThere() async throws {
        let ctx = try makeContext()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("coord-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let photo = root.appendingPathComponent("fundal.jpg")
        try Data("x".utf8).write(to: photo)

        let files = [PendingImportFile(url: photo, category: .media("image"))]
        let coordinator = ImportCoordinator(modelContext: ctx)

        let first = await coordinator.run(files, songCollectionName: "Test")
        #expect(first.imported == 1)
        #expect(first.skipped == 0)

        let second = await coordinator.run(files, songCollectionName: "Test")
        #expect(second.imported == 0)
        #expect(second.skipped == 1)
        // A bare count cannot tell these two runs apart, which is exactly how a
        // silent double-import goes unnoticed.
        #expect(first.headline != second.headline)
        #expect(second.report.contains("fundal.jpg"))
    }

    @Test func anEmptyRunSaysSoRatherThanReportingZeroes() async throws {
        let summary = await ImportCoordinator(modelContext: try makeContext())
            .run([], songCollectionName: "Test")
        #expect(summary.isEmpty)
        #expect(summary.headline == String(localized: "Nothing to import", comment: "Import summary"))
    }
}

// MARK: - The import plan
//
// The rules about what gets selected, what counts as a duplicate within one
// batch, and when the advanced mode is worth showing — tested without driving
// a sheet, which is why they live on the model rather than in the view.

@MainActor struct ImportPlanTests {

    private func makeTree(_ files: [String: String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plan-\(UUID().uuidString)")
        for (relativePath, contents) in files {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
        }
        return root
    }

    private static func bibleJSON(_ code: String) -> String {
        """
        {"format":"TopPresenter Bible","translation":{"code":"\(code)","name":"\(code)"},
         "books":[{"number":1,"name":"Genesis","testament":"OT",
         "chapters":[{"number":1,"verses":[{"number":1,"text":"la început"}]}]}]}
        """
    }

    /// A three-photo drop should not open a control panel; a mixed folder
    /// should, because there is something to decide.
    @Test func advancedModeAppearsOnlyWhenThereIsSomethingToDecide() async throws {
        let simple = try makeTree(["a.jpg": "x", "b.jpg": "y"])
        defer { try? FileManager.default.removeItem(at: simple) }
        let plan = ImportPlanModel()
        await plan.load([simple])
        #expect(plan.mode == .simple)

        let mixed = try makeTree(["a.jpg": "x", "biblia.tpbible": Self.bibleJSON("MIX")])
        defer { try? FileManager.default.removeItem(at: mixed) }
        let other = ImportPlanModel()
        await other.load([mixed])
        #expect(other.mode == .advanced, "two kinds at once is a decision")
    }

    /// `Biblia.tpbible` and `Biblia copy.tpbible` in one folder. The scanner
    /// drops the same PATH twice; it cannot see this.
    @Test func identicalFilesInOneFolderAreDeselectedWithAReason() async throws {
        let json = Self.bibleJSON("DUP")
        let root = try makeTree(["biblia.tpbible": json, "biblia copy.tpbible": json, "alta.tpbible": Self.bibleJSON("ALT")])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = ImportPlanModel()
        await plan.load([root])
        #expect(plan.rows.count == 3)
        let deselected = plan.rows.filter { !$0.isSelected }
        #expect(deselected.count == 1, "one of the identical pair is kept, the other is not")
        // "Deselected, no reason given" is indistinguishable from a bug.
        #expect(deselected.first?.duplicateOf != nil)
        #expect(plan.selectedRows.count == 2)
    }

    /// Opening from the Songs tab must not silently import the Bibles that
    /// happened to share the folder — but it must still SHOW them.
    @Test func preselectionNarrowsTheSelectionWithoutHidingAnything() async throws {
        let root = try makeTree(["cantec.chordpro": "{title: T}\nlinie", "biblia.tpbible": Self.bibleJSON("PRE")])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = ImportPlanModel()
        plan.preselectedKinds = [.song]
        await plan.load([root])
        #expect(plan.rows.count == 2, "the Bible is still listed")
        #expect(plan.selectedRows.count == 1)
        #expect(plan.selectedRows.first?.kind == .song)
    }

    /// A file the operator NAMED gets an answer. The old drop path showed one
    /// alert reciting a hardcoded format list and said nothing about the file.
    @Test func aFileYouDroppedYourselfIsAnsweredForByName() async throws {
        let root = try makeTree(["notes.docx": "x", "a.jpg": "y"])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = ImportPlanModel()
        await plan.load([root.appendingPathComponent("notes.docx"),
                         root.appendingPathComponent("a.jpg")])
        #expect(plan.rows.count == 1)
        #expect(plan.unsupported.map(\.fileName) == ["notes.docx"])
        #expect(plan.unsupported.first?.reason.isEmpty == false)
    }

    /// A FOLDER is a request to find what is usable inside it, so the four
    /// hundred unrelated files in a Documents tree are not listed one by one.
    /// But a folder that yielded nothing has to say so — otherwise the sheet
    /// just bounces back to its drop zone and the operator is left guessing.
    @Test func aFolderWithNothingUsableSaysSoInsteadOfGoingQuiet() async throws {
        let empty = try makeTree(["notes.docx": "x", "raport.xlsx": "y"])
        defer { try? FileManager.default.removeItem(at: empty) }

        let plan = ImportPlanModel()
        await plan.load([empty])
        #expect(plan.rows.isEmpty)
        #expect(plan.unsupported.count == 1, "the FOLDER is named, not each file inside it")
        #expect(plan.unsupported.first?.fileName == empty.lastPathComponent)
        #expect(plan.stage == .planning, "bouncing back to the drop zone would explain nothing")
    }

    /// The mirror of the rule above: a folder that DID yield something says
    /// nothing about the unrelated files beside them.
    @Test func aFolderThatYieldedSomethingDoesNotListItsOtherFiles() async throws {
        let root = try makeTree(["notes.docx": "x", "a.jpg": "y"])
        defer { try? FileManager.default.removeItem(at: root) }

        let plan = ImportPlanModel()
        await plan.load([root])
        #expect(plan.rows.count == 1)
        #expect(plan.unsupported.isEmpty)
    }

    @Test func selectingNothingDisablesTheImportButton() async throws {
        let root = try makeTree(["a.jpg": "x"])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = ImportPlanModel()
        await plan.load([root])
        #expect(plan.canImport)
        plan.setSelected(false, forKind: .media)
        #expect(!plan.canImport)
    }

    /// A `.tpschedule` and a `.tptheme` are documents the sheet handles now.
    /// They used to have their own panels, each with its own folder walk and
    /// its own (absent) duplicate behaviour.
    @Test func sessionsAndThemesAreFirstClassCategories() {
        #expect(DragDropImportHandler.classify(URL(fileURLWithPath: "/tmp/a.tpschedule")).kind == .session)
        #expect(DragDropImportHandler.classify(URL(fileURLWithPath: "/tmp/a.tptheme")).kind == .theme)
    }
}

// MARK: - Native formats, naming, and the slide deck

@MainActor struct ExportNamingTests {

    /// `<Name>[_<Qualifier>]_TopPresenter_<Type>.<ext>` — the redundancy is
    /// deliberate. On Windows, on Android, in a WhatsApp attachment list, the
    /// extension stops being shown and the name is all that is left.
    /// The name stays the operator's — the extension already says what the file
    /// is and whose it is.
    @Test func filenamesKeepTheNameTheOperatorGaveThem() {
        #expect(ExportNaming.filename("EDC100", qualifier: "RO", format: .bible) == "EDC100_RO.tpbible")
        #expect(ExportNaming.filename("Ce mare ești Tu", format: .song) == "Ce mare ești Tu.tpsong")
        #expect(ExportNaming.filename("Anunțuri", format: .slides) == "Anunțuri.tpslides")
    }

    /// A song title can contain anything a person can type, and the result has
    /// to survive a filesystem, a shell and an email client.
    @Test func namesThatWouldBreakAPathAreMadeSafe() {
        let name = ExportNaming.filename("AC/DC: \"Live\"? *maybe*", format: .song)
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(!name.contains("\""))
        #expect(name.hasSuffix(".tpsong"))
    }

    @Test func everyNativeFormatHasItsOwnExtensionAndMarker() {
        let extensions = TopPresenterFormat.allCases.map(\.fileExtension)
        #expect(Set(extensions).count == extensions.count, "two formats share an extension")
        let markers = TopPresenterFormat.allCases.map(\.marker)
        #expect(Set(markers).count == markers.count, "two formats share a format marker")
        for format in TopPresenterFormat.allCases {
            #expect(TopPresenterFormat.matching(extension: format.fileExtension.uppercased()) == format)
        }
    }

    /// The header is what makes a file recognisable as ours before anything
    /// tries to parse it.
    @Test func theSharedHeaderCarriesTheFormatAndTheIdentity() {
        let header = TopPresenterHeader.fields(for: .bible, contentID: "ID-1")
        #expect(header["format"] as? String == "TopPresenter Bible")
        #expect(header["contentID"] as? String == "ID-1")
        #expect(header["schemaVersion"] as? Int == 1)
        // An empty contentID is omitted rather than written as "": a
        // meaningless value in the header is worse than an absent one.
        #expect(TopPresenterHeader.fields(for: .bible)["contentID"] == nil)
    }
}

@MainActor struct SlideDeckRoundTripTests {

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return ModelContext(container)
    }

    private func deck(in ctx: ModelContext) -> [PresentationSlide] {
        let slides = [
            PresentationSlide(title: "Anunțuri", content: "Program de vară",
                              subtitle: "Duminică", slideType: "text", order: 0),
            PresentationSlide(title: "Botez", content: "La ora 18",
                              subtitle: "Seara", slideType: "text", order: 1),
        ]
        for slide in slides { ctx.insert(slide) }
        return slides
    }

    @Test func everySlideFieldSurvivesTheRoundTrip() throws {
        let source = try makeContext()
        let before = deck(in: source).map(PresentationSlideSnapshot.init)
        let data = try SlideDeckArchiveService.export(deck(in: source))

        let target = try makeContext()
        let result = try SlideDeckArchiveService.importDeck(data, context: target)
        #expect(result.imported.count == 2)

        let after = try target.fetch(FetchDescriptor<PresentationSlide>())
            .sorted { $0.order < $1.order }.map(PresentationSlideSnapshot.init)
        #expect(after == before)
    }

    /// Identity is per SLIDE, not per deck: a deck is a loose collection
    /// someone adds to over months, so re-importing one you extended elsewhere
    /// should bring in what is new and leave the rest alone.
    @Test func reimportingADeckBringsInOnlyWhatIsNew() throws {
        let ctx = try makeContext()
        let original = deck(in: ctx)
        let data = try SlideDeckArchiveService.export(original)

        let target = try makeContext()
        _ = try SlideDeckArchiveService.importDeck(data, context: target)

        let again = try SlideDeckArchiveService.importDeck(data, context: target)
        #expect(again.imported.isEmpty)
        #expect(again.skipped.count == 2)
        #expect(try target.fetch(FetchDescriptor<PresentationSlide>()).count == 2)

        // One new slide added elsewhere, the rest unchanged.
        let extended = deck(in: ctx) + [PresentationSlide(title: "Nou", content: "text nou",
                                                          subtitle: "", slideType: "text", order: 2)]
        let third = try SlideDeckArchiveService.importDeck(
            try SlideDeckArchiveService.export(extended), context: target)
        #expect(third.imported.map(\.title) == ["Nou"])
        #expect(third.skipped.count == 2)
    }

    /// The resilient decoder defaults every missing key, so it would happily
    /// "decode" a stranger's JSON into an empty deck and report success. The
    /// format marker is checked first, strictly.
    @Test func foreignJSONIsRejectedRatherThanDecodedIntoNothing() throws {
        let ctx = try makeContext()
        #expect(throws: (any Error).self) {
            try SlideDeckArchiveService.importDeck(Data(#"{"hello":1}"#.utf8), context: ctx)
        }
        #expect(try ctx.fetch(FetchDescriptor<PresentationSlide>()).isEmpty)
    }
}


// MARK: - Bulk delete: does the SQL path honour cascade?

/// The delete of seventy Bibles beach-balled even after it moved to its own
/// actor, and the CoreData log said why: a `wal_checkpoint(TRUNCATE)` and an
/// `incremental_vacuum` after EVERY save, each taking an exclusive store lock
/// that stalls the main thread's next read.
///
/// The cure is to stop faulting two million objects into memory to delete them.
/// `modelContext.delete(model:where:)` is an `NSBatchDeleteRequest` — it runs
/// as SQL and never builds the objects. The question this suite answers, before
/// any of it is relied on, is whether that SQL path still honours the
/// `.cascade` delete rules four levels deep. If it does not, batch-deleting a
/// module leaves 31 000 orphaned verses per Bible — a silently growing store,
/// which is far worse than being slow.
@Suite("Bulk delete")
struct BulkDeleteSpike {

    /// On DISK deliberately: batch delete is a store-level operation and an
    /// in-memory store is not the thing being shipped.
    private func makeDiskContainer() throws -> (ModelContainer, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tp-bulk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let container = try ModelContainer(
            for: Schema(versionedSchema: SchemaV2.self),
            configurations: [ModelConfiguration(url: dir.appendingPathComponent("store.sqlite"))]
        )
        return (container, dir)
    }

    private func seedModule(_ ctx: ModelContext, name: String,
                           books: Int = 3, chapters: Int = 4, verses: Int = 25) {
        let module = BibleModule(name: name, abbreviation: name, sourceFormat: "test")
        ctx.insert(module)
        for b in 0..<books {
            let book = BibleBook(name: "\(name) B\(b)", bookNumber: b, testament: "OT")
            book.module = module
            for c in 0..<chapters {
                let chapter = BibleChapter(chapterNumber: c)
                chapter.book = book
                for v in 0..<verses {
                    let verse = BibleVerse(verseNumber: v, text: "\(name) \(b):\(c):\(v)")
                    verse.chapter = chapter
                }
            }
        }
    }

    @Test func batchDeletingAModuleCascadesAllTheWayDownToVerses() throws {
        let (container, dir) = try makeDiskContainer()
        defer { try? FileManager.default.removeItem(at: dir) }
        let ctx = ModelContext(container)

        seedModule(ctx, name: "GONE")
        seedModule(ctx, name: "KEPT")
        try ctx.save()

        #expect(try ctx.fetchCount(FetchDescriptor<BibleVerse>()) == 600)

        let doomed = try #require(
            try ctx.fetch(FetchDescriptor<BibleModule>(predicate: #Predicate { $0.name == "GONE" })).first
        ).id
        try ctx.delete(model: BibleModule.self, where: #Predicate { $0.id == doomed })
        try ctx.save()

        // A batch delete does not update the in-memory graph, so read through a
        // context that never saw the rows.
        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<BibleModule>()) == 1)
        #expect(try fresh.fetchCount(FetchDescriptor<BibleBook>()) == 3,
                "cascade stopped before books")
        #expect(try fresh.fetchCount(FetchDescriptor<BibleChapter>()) == 12,
                "cascade stopped before chapters")
        #expect(try fresh.fetchCount(FetchDescriptor<BibleVerse>()) == 300,
                "cascade stopped before verses — batch delete would orphan them")
    }

    /// Documented finding, not a live test: the bottom-up fallback is IMPOSSIBLE.
    ///
    /// `#Predicate<BibleVerse> { $0.chapter?.book?.module?.id == id }` compiles
    /// and then **aborts the process** at fetch time — a three-hop optional
    /// traversal is more than SwiftData's predicate backend can lower to SQL.
    /// It is left written down because the obvious reaction to a cascade that
    /// did not reach far enough would be to reach up from the leaves, and that
    /// road ends in a crash rather than in a wrong number.

    /// Does a context that is ALREADY holding a module notice the SQL delete?
    ///
    /// It does, and that is worth knowing precisely, because the two obvious
    /// remedies are both unavailable or harmful: `ModelContext` has no
    /// `reset()` (that is an NSManagedObjectContext API), and a blanket
    /// `rollback()` would throw away any unsaved edit the user had in flight.
    ///
    /// Neither is needed. FETCHES go to the store, so `@Query` and every
    /// descriptor-based read return the truth the moment the delete commits.
    ///
    /// What does NOT fix itself is a strong reference someone already holds —
    /// `LibraryManager.selectedBibleModule` and friends. Those point at rows
    /// that are gone, and clearing them is the caller's job. That is why
    /// `LibraryTaskRunner` tears the selection down rather than trusting the
    /// context to do it.
    @Test func fetchesSeeTheBatchDeleteImmediately() throws {
        let (container, dir) = try makeDiskContainer()
        defer { try? FileManager.default.removeItem(at: dir) }

        let writer = ModelContext(container)
        seedModule(writer, name: "GONE")
        seedModule(writer, name: "KEPT")
        try writer.save()

        // Stand in for the main context: fetch both, so both are materialized.
        let live = ModelContext(container)
        let before = try live.fetch(FetchDescriptor<BibleModule>(sortBy: [SortDescriptor(\.name)]))
        #expect(before.count == 2)

        let doomed = try #require(before.first).id      // "GONE" sorts before "KEPT"
        try writer.delete(model: BibleModule.self, where: #Predicate { $0.id == doomed })
        try writer.save()

        #expect(try live.fetchCount(FetchDescriptor<BibleModule>()) == 1,
                "the live context is still serving a module that no longer exists")
        #expect(try live.fetch(FetchDescriptor<BibleModule>()).map(\.name) == ["KEPT"])
        #expect(try live.fetchCount(FetchDescriptor<BibleVerse>()) == 300,
                "the survivor's verses went with it, or the doomed module's did not")
    }

    /// What the fix is actually worth, on a Bible the size of a real one.
    ///
    /// Measured when this landed: **7.97 s via the object graph, 0.17 s via the
    /// batch delete** — 47x, for one module. Seventy of them is the difference
    /// between nine minutes and twelve seconds, which is exactly the complaint.
    ///
    /// The ratio is asserted rather than an absolute time, so the guard means
    /// the same thing on a slower machine. It exists to catch a REGRESSION —
    /// someone reinstating `context.delete(module)` — not to police the number.
    @Test func batchDeleteIsOrdersOfMagnitudeFasterThanTheObjectGraph() throws {
        let (container, dir) = try makeDiskContainer()
        defer { try? FileManager.default.removeItem(at: dir) }

        // ~31 000 verses: the size of an actual Bible.
        let ctx = ModelContext(container)
        seedModule(ctx, name: "GRAPH", books: 66, chapters: 20, verses: 24)
        seedModule(ctx, name: "BATCH", books: 66, chapters: 20, verses: 24)
        try ctx.save()

        let graphStart = Date()
        let viaGraph = try #require(
            try ctx.fetch(FetchDescriptor<BibleModule>(predicate: #Predicate { $0.name == "GRAPH" })).first)
        ctx.delete(viaGraph)
        try ctx.save()
        let graphSeconds = Date().timeIntervalSince(graphStart)

        let batchStart = Date()
        let doomed = try #require(
            try ctx.fetch(FetchDescriptor<BibleModule>(predicate: #Predicate { $0.name == "BATCH" })).first).id
        try ctx.delete(model: BibleModule.self, where: #Predicate { $0.id == doomed })
        try ctx.save()
        let batchSeconds = Date().timeIntervalSince(batchStart)

        let fresh = ModelContext(container)
        #expect(try fresh.fetchCount(FetchDescriptor<BibleVerse>()) == 0)
        #expect(batchSeconds * 5 < graphSeconds,
                "batch \(String(format: "%.2f", batchSeconds))s vs graph \(String(format: "%.2f", graphSeconds))s — expected far faster, so the bulk path has probably fallen back to faulting the whole graph again")
    }
}

// MARK: - PDF as media

/// PDF is the one page-based format macOS renders natively, so it is the one
/// TopPresenter accepts. These tests draw a REAL PDF and rasterise it, because
/// "it compiled" says nothing about whether a page arrives as a visible image
/// or as a blank rectangle.
@Suite("PDF media")
struct PDFMediaTests {

    /// A two-page PDF: page 1 portrait, page 2 landscape, each filled with a
    /// solid colour so the render can be checked by sampling a pixel.
    private func makePDF(at url: URL) throws {
        let portrait = CGRect(x: 0, y: 0, width: 200, height: 400)
        let landscape = CGRect(x: 0, y: 0, width: 400, height: 200)
        var box = portrait
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for (rect, color) in [(portrait, CGColor(red: 1, green: 0, blue: 0, alpha: 1)),
                              (landscape, CGColor(red: 0, green: 0, blue: 1, alpha: 1))] {
            var pageBox = rect
            ctx.beginPage(mediaBox: &pageBox)
            ctx.setFillColor(color)
            ctx.fill(rect)
            ctx.endPage()
        }
        ctx.closePDF()
    }

    private func withPDF<T>(_ body: (URL) throws -> T) throws -> T {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tp-\(UUID().uuidString).pdf")
        try makePDF(at: url)
        defer { try? FileManager.default.removeItem(at: url) }
        return try body(url)
    }

    @Test func countsPages() throws {
        try withPDF { url in
            #expect(PDFPageRenderer.pageCount(of: url) == 2)
        }
    }

    @Test func nonPDFReportsNoPagesRatherThanCrashing() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tp-\(UUID().uuidString).pdf")
        try Data("this is not a pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PDFPageRenderer.pageCount(of: url) == 0)
        #expect(PDFPageRenderer.render(url: url, page: 0) == nil)
    }

    @Test func rendersAPageAsAnImageOfTheRightShape() throws {
        try withPDF { url in
            let page = try #require(PDFPageRenderer.render(url: url, page: 0, maxPixels: 800))
            // Portrait 200x400 → taller than wide, whatever the scale.
            #expect(page.size.height > page.size.width)

            let landscape = try #require(PDFPageRenderer.render(url: url, page: 1, maxPixels: 800))
            #expect(landscape.size.width > landscape.size.height,
                    "page 2 is 400x200 and came back \(landscape.size) — the render is not following page geometry")
        }
    }

    /// The failure this guards is invisible in a unit test that only checks
    /// sizes: a PDF page has no background, so drawing it without filling white
    /// first gives a transparent bitmap that projects as black.
    @Test func pageContentIsActuallyDrawnAndNotTransparent() throws {
        try withPDF { url in
            let image = try #require(PDFPageRenderer.render(url: url, page: 0, maxPixels: 200))
            let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cg)
            let middle = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2,
                                                     y: bitmap.pixelsHigh / 2))
            #expect(middle.alphaComponent > 0.99, "the page came out transparent")
            // The fixture's page one is solid red.
            #expect(middle.redComponent > 0.8 && middle.greenComponent < 0.2,
                    "expected the page's red fill, got \(middle)")
        }
    }

    @Test func outOfRangePagesAreRefused() throws {
        try withPDF { url in
            #expect(PDFPageRenderer.render(url: url, page: -1) == nil)
            #expect(PDFPageRenderer.render(url: url, page: 2) == nil)
        }
    }

    /// The import side has to file a `.pdf` as media, and must not have started
    /// claiming anything else along the way.
    @Test func pdfClassifiesAsDocumentMedia() {
        #expect(MediaKind.classify(extension: "pdf") == .document)
        #expect(MediaKind.classify(extension: "PDF") == .document)
        #expect(MediaKind.document.isPaged)
        #expect(!MediaKind.image.isPaged)
        // .pptx stays a SONG import — text only. Taking it as media would be a
        // promise to render DrawingML.
        #expect(MediaKind.classify(extension: "pptx") == nil)
        #expect(ImportCatalog.importable.contains { $0.fileExtensions.contains("pdf") })
    }
}

// MARK: - Scanning a folder of .tptheme packages

/// Selecting the unzipped theme pack must find the themes inside it.
///
/// This is what the themes-1 release tells people to do — "unzip, then Import →
/// choose the folder" — and it came back with nothing when tried by hand.
@Suite("Theme folder scanning")
struct ThemeFolderScanTests {

    /// A `.tptheme` is a DIRECTORY, so the fixture has to be one too.
    private func makePack(at root: URL, names: [String]) throws {
        for name in names {
            let pkg = root.appendingPathComponent("\(name).tptheme")
            try FileManager.default.createDirectory(at: pkg.appendingPathComponent("media"),
                                                    withIntermediateDirectories: true)
            let payload: [String: Any] = [
                "name": name, "format": "all", "version": 1,
                "themeID": UUID().uuidString, "assets": [], "payload": [:],
            ]
            try JSONSerialization.data(withJSONObject: payload)
                .write(to: pkg.appendingPathComponent("theme.json"))
        }
    }

    @Test func scanningTheParentFolderFindsEveryThemePackage() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tp-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makePack(at: root, names: ["Grafit", "Indigo", "Cer înstelat"])

        let result = ImportScanner.scan([root])
        let found = result.files.filter { $0.pathExtension == "tptheme" }
        #expect(found.count == 3,
                "found \(found.count) themes instead of 3; all files = \(result.files.map(\.lastPathComponent))")
    }

    /// And the package must be taken WHOLE, never walked into: its theme.json
    /// and its media are parts of one document, not loose importable files.
    @Test func aThemePackageIsNotWalkedIntoAsLooseFiles() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tp-themes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try makePack(at: root, names: ["Grafit"])

        let result = ImportScanner.scan([root])
        #expect(!result.files.contains { $0.lastPathComponent == "theme.json" },
                "the package was walked into and its theme.json picked up as a loose file")
    }

    /// `tptheme` has to be in the directory-source set, or the walk treats the
    /// package as an ordinary folder.
    @Test func themeIsRegisteredAsADirectorySource() {
        #expect(ImportCatalog.directoryExtensions.contains("tptheme"),
                "directoryExtensions = \(ImportCatalog.directoryExtensions.sorted())")
    }
}
