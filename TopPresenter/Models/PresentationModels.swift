//
//  PresentationModels.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Presentation Slide
@Model
final class PresentationSlide {
    @Attribute(.unique) var id: UUID
    var title: String
    var content: String
    var subtitle: String
    var slideType: String  // "bible", "song", "text", "media", "blank"
    var order: Int
    var createdDate: Date

    init(
        title: String = "",
        content: String = "",
        subtitle: String = "",
        slideType: String = "text",
        order: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.subtitle = subtitle
        self.slideType = slideType
        self.order = order
        self.createdDate = Date()
    }
}

// MARK: - Media Item
@Model
final class MediaItem {
    @Attribute(.unique) var id: UUID
    var name: String
    var filePath: String
    var mediaType: String  // "image", "video", "audio"
    var importDate: Date
    @Attribute(.externalStorage) var thumbnailData: Data?
    /// Security-scoped bookmark data for persistent file access
    @Attribute(.externalStorage) var bookmarkData: Data?

    init(name: String, filePath: String, mediaType: String) {
        self.id = UUID()
        self.name = name
        self.filePath = filePath
        self.mediaType = mediaType
        self.importDate = Date()
    }

    /// Resolves the file URL, preferring the security-scoped bookmark.
    /// Falls back to the stored filePath if bookmark resolution fails.
    var resolvedURL: URL? {
        if let data = bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    // Bookmark is stale — try to refresh it
                    refreshBookmark(from: url)
                }
                return url
            }
        }
        // Fallback to raw path
        let url = URL(fileURLWithPath: filePath)
        return FileManager.default.fileExists(atPath: filePath) ? url : nil
    }

    /// Creates a security-scoped bookmark from a URL.
    func createBookmark(from url: URL) {
        do {
            bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            // Bookmark creation can fail in sandboxed contexts — fall back to filePath
        }
    }

    /// Refreshes a stale bookmark.
    private func refreshBookmark(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        createBookmark(from: url)
    }
}

// MARK: - Presentation Style
@Model
final class PresentationStyle {
    @Attribute(.unique) var id: UUID
    var name: String
    var fontName: String
    var fontSize: Double
    var textColorHex: String
    var backgroundColorHex: String
    var backgroundImagePath: String?
    var backgroundOpacity: Double
    var textAlignment: String  // "leading", "center", "trailing"
    var lineSpacing: Double
    var padding: Double
    var shadowEnabled: Bool
    var shadowRadius: Double
    var isDefault: Bool

    init(
        name: String = "Default",
        fontName: String = PresentationDefaults.fontName,
        fontSize: Double = PresentationDefaults.fontSize,
        textColorHex: String = PresentationDefaults.textColor,
        backgroundColorHex: String = PresentationDefaults.backgroundColor,
        backgroundImagePath: String? = nil,
        backgroundOpacity: Double = PresentationDefaults.backgroundOpacity,
        textAlignment: String = "center",
        lineSpacing: Double = PresentationDefaults.lineSpacing,
        padding: Double = PresentationDefaults.padding,
        shadowEnabled: Bool = true,
        shadowRadius: Double = 3.0,
        isDefault: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColorHex = textColorHex
        self.backgroundColorHex = backgroundColorHex
        self.backgroundImagePath = backgroundImagePath
        self.backgroundOpacity = backgroundOpacity
        self.textAlignment = textAlignment
        self.lineSpacing = lineSpacing
        self.padding = padding
        self.shadowEnabled = shadowEnabled
        self.shadowRadius = shadowRadius
        self.isDefault = isDefault
    }

    var textColor: Color {
        Color(hex: textColorHex) ?? .white
    }

    var backgroundColor: Color {
        Color(hex: backgroundColorHex) ?? .black
    }

    var alignment: TextAlignment {
        switch textAlignment {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }

    var horizontalAlignment: HorizontalAlignment {
        switch textAlignment {
        case "leading": return .leading
        case "trailing": return .trailing
        default: return .center
        }
    }
}

// MARK: - Service Schedule
@Model
final class ServiceSchedule {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: Date
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \ScheduleItem.schedule)
    var items: [ScheduleItem] = []

    init(name: String, date: Date = Date(), notes: String = "") {
        self.id = UUID()
        self.name = name
        self.date = date
        self.notes = notes
    }

    var sortedItems: [ScheduleItem] {
        items.sorted { $0.order < $1.order }
    }
}

// MARK: - Schedule Item
@Model
final class ScheduleItem {
    @Attribute(.unique) var id: UUID
    var title: String
    var itemType: String  // "bible", "song", "text", "media", "blank"
    var content: String
    var subtitle: String
    var order: Int
    var referenceID: String?  // UUID string of the referenced Bible verse or song

    var schedule: ServiceSchedule?

    init(
        title: String,
        itemType: String,
        content: String = "",
        subtitle: String = "",
        order: Int = 0,
        referenceID: String? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.itemType = itemType
        self.content = content
        self.subtitle = subtitle
        self.order = order
        self.referenceID = referenceID
    }
}

// MARK: - Live Presentation Content (non-persisted, used for real-time display)
@Observable
final class LiveContent {
    var mainText: String = ""
    var subtitle: String = ""
    var reference: String = ""
    var translationName: String = ""
    var contentType: ContentType = .blank
    var isLive: Bool = false
    /// Rich segments of the main text (red-letter / italic). Empty = plain.
    var mainRuns: [VerseRun] = []
    /// Rich Bible casete sources (populated for live verses; "" otherwise).
    var footnote: String = ""
    var crossReference: String = ""
    var heading: String = ""
    var gloss: String = ""
    var strongs: String = ""
    /// Position of this slide within its set (verse within song, slide within
    /// deck, item within schedule) — drives "show only on first/last slide".
    var slideIndex: Int = 0
    var slideCount: Int = 1

    var isFirstSlide: Bool { slideIndex <= 0 }
    var isLastSlide: Bool { slideIndex >= slideCount - 1 }
    /// Whether the current slide is a chorus, judged by its section label
    /// ("Refren", "Refren 2", "Chorus", "Cor" — case/diacritic-insensitive).
    var isChorusSlide: Bool {
        let label = subtitle
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
        return ["refren", "chorus", "cor"].contains { label.hasPrefix($0) }
    }
    /// "2 / 7" — the "slideNumber" box source.
    var slideNumberText: String { "\(min(slideIndex, slideCount - 1) + 1) / \(max(slideCount, 1))" }

    enum ContentType: String {
        case bible
        case song
        case text
        case media
        case blank
    }

    func clear() {
        mainText = ""
        subtitle = ""
        reference = ""
        translationName = ""
        contentType = .blank
        isLive = false
        mainRuns = []
        clearRichSources()
        slideIndex = 0
        slideCount = 1
    }

    private func clearRichSources() {
        footnote = ""; crossReference = ""; heading = ""; gloss = ""; strongs = ""
    }

    func setBibleVerse(text: String, reference: String, translationName: String = "", runs: [VerseRun] = [],
                       footnote: String = "", crossReference: String = "", heading: String = "",
                       gloss: String = "", strongs: String = "",
                       slideIndex: Int = 0, slideCount: Int = 1) {
        self.mainText = text
        self.reference = reference
        self.translationName = translationName
        self.subtitle = ""
        self.contentType = .bible
        self.mainRuns = runs
        self.footnote = footnote
        self.crossReference = crossReference
        self.heading = heading
        self.gloss = gloss
        self.strongs = strongs
        self.slideIndex = slideIndex
        self.slideCount = max(slideCount, 1)
    }

    func setSongVerse(text: String, title: String, verseLabel: String, slideIndex: Int = 0, slideCount: Int = 1) {
        self.mainText = text
        self.reference = title
        self.subtitle = verseLabel
        self.translationName = ""
        self.contentType = .song
        self.mainRuns = []
        clearRichSources()
        self.slideIndex = slideIndex
        self.slideCount = max(slideCount, 1)
    }

    func setCustomText(text: String, title: String, slideIndex: Int = 0, slideCount: Int = 1) {
        self.mainText = text
        self.reference = title
        self.subtitle = ""
        self.translationName = ""
        self.contentType = .text
        self.mainRuns = []
        clearRichSources()
        self.slideIndex = slideIndex
        self.slideCount = max(slideCount, 1)
    }

    func setVideo() {
        self.mainText = ""
        self.reference = ""
        self.subtitle = ""
        self.translationName = ""
        self.contentType = .media
        self.mainRuns = []
        clearRichSources()
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        switch hexSanitized.count {
        case 6:
            self.init(
                red: Double((rgb & 0xFF0000) >> 16) / 255.0,
                green: Double((rgb & 0x00FF00) >> 8) / 255.0,
                blue: Double(rgb & 0x0000FF) / 255.0
            )
        case 8:
            self.init(
                red: Double((rgb & 0xFF000000) >> 24) / 255.0,
                green: Double((rgb & 0x00FF0000) >> 16) / 255.0,
                blue: Double((rgb & 0x0000FF00) >> 8) / 255.0,
                opacity: Double(rgb & 0x000000FF) / 255.0
            )
        default:
            return nil
        }
    }

    func toHex() -> String {
        // Normalize to sRGB first — picker colors can be P3 or grayscale, whose raw
        // CGColor components would map to the wrong hex channels.
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return "FFFFFF" }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }

    /// 8-digit RRGGBBAA hex — used where the alpha matters (shadow color).
    func toHexWithAlpha() -> String {
        guard let nsColor = NSColor(self).usingColorSpace(.sRGB) else { return "000000B3" }
        let r = Int((nsColor.redComponent * 255).rounded())
        let g = Int((nsColor.greenComponent * 255).rounded())
        let b = Int((nsColor.blueComponent * 255).rounded())
        let a = Int((nsColor.alphaComponent * 255).rounded())
        return String(format: "%02X%02X%02X%02X", r, g, b, a)
    }
}
