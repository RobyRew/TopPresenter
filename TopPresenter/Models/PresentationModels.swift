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
    }

    func setBibleVerse(text: String, reference: String, translationName: String = "") {
        self.mainText = text
        self.reference = reference
        self.translationName = translationName
        self.subtitle = ""
        self.contentType = .bible
    }

    func setSongVerse(text: String, title: String, verseLabel: String) {
        self.mainText = text
        self.reference = title
        self.subtitle = verseLabel
        self.contentType = .song
    }

    func setCustomText(text: String, title: String) {
        self.mainText = text
        self.reference = title
        self.subtitle = ""
        self.contentType = .text
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
        let nsColor = NSColor(self)
        guard let components = nsColor.cgColor.components else { return "FFFFFF" }
        let r = Int((components[0] * 255).rounded())
        let g = Int(((components.count > 1 ? components[1] : components[0]) * 255).rounded())
        let b = Int(((components.count > 2 ? components[2] : components[0]) * 255).rounded())
        return String(format: "%02X%02X%02X", r, g, b)
    }
}
