//
//  TopPresenterTests.swift
//  TopPresenterTests
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Testing
import Foundation
import SwiftUI
@testable import TopPresenter

// MARK: - TopPresenter JSON Importer Tests

struct TopPresenterImporterTests {
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

    // MARK: - Helpers

    private func writeJSON(_ json: [String: Any], filename: String) throws -> URL {
        let data = try JSONSerialization.data(withJSONObject: json, options: .prettyPrinted)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}

// MARK: - Zefania XML Importer Tests

struct ZefaniaImporterTests {
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

// MARK: - Bible Import Result Validation Tests

struct BibleImportResultTests {
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

struct ColorExtensionTests {
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

struct LiveContentTests {
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

// MARK: - PresentationManager Tests

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
}
