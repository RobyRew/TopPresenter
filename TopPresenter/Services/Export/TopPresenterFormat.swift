//
//  TopPresenterFormat.swift
//  TopPresenter
//
//  The native document types: what they are called, what they start with, and
//  what they are named on disk.
//
//  WHY THEY ARE NOT .json ANY MORE
//
//  They still ARE JSON — every declaration below conforms to `public.json`, so
//  Quick Look renders them, `jq` parses them, git diffs them as text and any
//  editor opens them. What an own extension buys is everything the system does
//  with a file BEFORE anything reads it:
//
//    · a Finder icon of our own (`public.json` is system-owned; you cannot put
//      an icon on someone else's type)
//    · double-click opens TopPresenter instead of Xcode or TextEdit
//    · an open panel that offers our documents rather than every JSON on disk
//    · a Bible distinguishable from a song by its NAME, not by opening it
//
//  A package would buy nothing here and cost a lot: not emailable (Mail, Drive
//  and WhatsApp re-zip folders), corruptible by a half-finished cloud sync, no
//  atomic write, not diffable. `.tptheme` is a package because it carries
//  binary backgrounds; the text formats have no such reason.
//

import Foundation

nonisolated enum TopPresenterFormat: String, CaseIterable, Sendable, Identifiable {
    case bible, song, songCollection, slides, session, theme

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .bible: return "tpbible"
        case .song: return "tpsong"
        case .songCollection: return "tpsongcollection"
        case .slides: return "tpslides"
        case .session: return "tpschedule"
        case .theme: return "tptheme"
        }
    }

    /// The `format` field inside the file. Unchanged from before the extensions
    /// existed — files already in the wild stay readable.
    var marker: String {
        switch self {
        case .bible: return "TopPresenter Bible"
        case .song: return "TopPresenter Song"
        case .songCollection: return "TopPresenter Songs"
        case .slides: return "TopPresenter Slides"
        case .session: return "TopPresenter Session"
        case .theme: return "TopPresenter Theme"
        }
    }

    var utTypeIdentifier: String {
        switch self {
        case .bible: return "com.robyrew.toppresenter.bible"
        case .song: return "com.robyrew.toppresenter.song"
        case .songCollection: return "com.robyrew.toppresenter.songcollection"
        case .slides: return "com.robyrew.toppresenter.slides"
        case .session: return "com.robyrew.toppresenter.schedule"
        case .theme: return "com.robyrew.toppresenter.theme"
        }
    }

    /// The word in the filename. Deliberately spelled out rather than derived:
    /// it appears on other people's machines.
    var nameSuffix: String {
        switch self {
        case .bible: return "Bible"
        case .song: return "Song"
        case .songCollection: return "SongCollection"
        case .slides: return "Slides"
        case .session: return "Session"
        case .theme: return "Theme"
        }
    }

    static func matching(extension ext: String) -> TopPresenterFormat? {
        let needle = ext.lowercased()
        return allCases.first { $0.fileExtension == needle }
    }
}

// MARK: - The shared header

/// The first fields of every native file.
///
/// `contentID` is the load-bearing one: it is what lets a file be recognised as
/// something the library already has, instead of imported a second time.
nonisolated enum TopPresenterHeader {
    static let schemaVersion = 1

    static func fields(for format: TopPresenterFormat, contentID: String = "") -> [String: Any] {
        var header: [String: Any] = [
            "schemaVersion": schemaVersion,
            "format": format.marker,
            "appVersion": appVersion,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
        ]
        if !contentID.isEmpty { header["contentID"] = contentID }
        return header
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }
}

// MARK: - Naming

/// `<Name>[_<Qualifier>].<ext>`
///
/// The name stays the operator's. An earlier version stamped
/// `_TopPresenter_Bible` into every filename on the theory that the extension
/// is hidden on Windows and in attachment lists — but `.tpbible` already says
/// both what it is and whose it is, and paying for that twice turns
/// "EDC100" into "EDC100_RO_TopPresenter_Bible" in every file dialog the
/// operator ever sees.
nonisolated enum ExportNaming {
    static func filename(_ name: String, qualifier: String = "", format: TopPresenterFormat) -> String {
        var parts = [sanitize(name)]
        let cleanQualifier = sanitize(qualifier)
        if !cleanQualifier.isEmpty { parts.append(cleanQualifier) }
        return parts.joined(separator: "_") + "." + format.fileExtension
    }

    /// Removes only what a path cannot hold. Spaces are left alone — a
    /// filename is for a person to read, and "Ce mare ești Tu.tpsong" is a
    /// better name than "Ce-mare-ești-Tu.tpsong".
    static func sanitize(_ raw: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(90))
    }
}
