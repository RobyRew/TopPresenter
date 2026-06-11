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

    @Test func setBoxFrameClampsAndPersistsRoundTrip() {
        let pm = PresentationManager()
        pm.setBoxFrame(.init(x: 0.95, y: 0.1, width: 0.3, height: 0.2), for: .verseContent)

        // x clamped so the box stays fully on screen
        #expect(pm.verseBoxFrame.x + pm.verseBoxFrame.width <= 1.0)

        // Persisted value decodes back to the same frame
        let decoded = PresentationManager.TextBoxFrame.decode(
            from: .standard, key: "pm_verseBoxFrame", fallback: .defaultVerse
        )
        #expect(decoded == pm.verseBoxFrame)
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
        let originalSource = pm.refSourceRaw
        let originalStatic = pm.refStaticText

        // Default "auto" → the box's natural field
        pm.refSourceRaw = "auto"
        #expect(pm.sectionText(.reference, main: "M", reference: "R", translation: "T", subtitle: "S") == "R")

        // Override to another live field
        pm.refSourceRaw = "translation"
        #expect(pm.sectionText(.reference, main: "M", reference: "R", translation: "T", subtitle: "S") == "T")

        // Static text
        pm.refSourceRaw = "static"
        pm.refStaticText = "Biserica Sion"
        #expect(pm.sectionText(.reference, main: "M", reference: "R", translation: "T", subtitle: "S") == "Biserica Sion")

        pm.refSourceRaw = originalSource
        pm.refStaticText = originalStatic
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
        #expect(payload.frames["verseContent"]?.width == 0.8)
        #expect(payload.fontName == PresentationDefaults.fontName) // default filled in
        #expect(payload.customTextBoxes.isEmpty)
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
