//
//  ImportCatalog.swift
//  TopPresenter
//
//  The one answer to "what can TopPresenter import?".
//
//  Before this, that question had four different answers depending on who you
//  asked: the open panel's allowed content types, the folder walk's extension
//  filter, the drop classifier's switch, and whatever the Help text happened to
//  say. They drifted — a folder of photos imported nothing, and an .flv was a
//  video to one classifier and an image to another.
//
//  Everything here is DERIVED from the format enums and `MediaKind`, so adding a
//  format in one place adds it to the panel, the walk, the classifier and the
//  "what can I import?" list at once. Nothing is listed twice.
//

import Foundation
import UniformTypeIdentifiers

/// The library a file lands in.
nonisolated enum ImportKind: String, CaseIterable, Sendable, Identifiable {
    case bible, song, media, session, theme, slides

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bible: return String(localized: "Bibles", comment: "Import kind")
        case .song: return String(localized: "Songs", comment: "Import kind")
        case .media: return String(localized: "Media", comment: "Import kind")
        case .session: return String(localized: "Sessions", comment: "Import kind")
        case .theme: return String(localized: "Themes", comment: "Import kind")
        case .slides: return String(localized: "Slides", comment: "Import kind")
        }
    }

    var systemImage: String {
        switch self {
        case .bible: return "book.closed"
        case .song: return "music.note.list"
        case .media: return "photo.on.rectangle"
        case .session: return "calendar"
        case .theme: return "paintpalette"
        case .slides: return "rectangle.on.rectangle"
        }
    }
}

/// One importable (and sometimes exportable) file format.
nonisolated struct ImportFormatDescriptor: Sendable, Identifiable {
    let id: String
    let kind: ImportKind
    let displayName: String
    let summary: String
    let fileExtensions: [String]
    /// This format is recognised by CONTENT on files with no extension at all.
    /// OpenSong is the only one: its files are routinely saved without any.
    var matchesExtensionless = false
    /// The source is a folder, not a file (a USFM book set, a `.tptheme`
    /// package). The scanner stops at it rather than walking into it.
    var isDirectorySource = false
    var isNative = false
    var canImport = true
    var canExport = false
}

nonisolated enum ImportCatalog {

    // MARK: - The registry

    static let all: [ImportFormatDescriptor] = bible + song + media + documents

    static var byKind: [ImportKind: [ImportFormatDescriptor]] {
        Dictionary(grouping: all, by: \.kind)
    }

    /// Only the formats that can actually be imported today.
    static var importable: [ImportFormatDescriptor] { all.filter(\.canImport) }

    // MARK: - Derived lookups

    /// Every extension any importable format claims, lowercased.
    static let importableExtensions: Set<String> = Set(
        importable.flatMap { $0.fileExtensions.map { $0.lowercased() } }
    )

    /// Whether ANY format accepts files with no extension by content probe.
    static let probesExtensionlessFiles: Bool = importable.contains { $0.matchesExtensionless }

    /// Extensions whose source is a folder rather than a file.
    static let directoryExtensions: Set<String> = Set(
        importable.filter(\.isDirectorySource)
            .flatMap { $0.fileExtensions.map { $0.lowercased() } }
    )

    /// UTTypes for an open panel, so it greys out what we cannot read.
    /// Pass `kinds` to narrow it to one library's formats.
    static func contentTypes(for kinds: Set<ImportKind> = Set(ImportKind.allCases)) -> [UTType] {
        let extensions = Set(importable.filter { kinds.contains($0.kind) }
            .flatMap { $0.fileExtensions.map { $0.lowercased() } })
        // `.item`, not the default. `UTType(filenameExtension:)` means
        // `conformingTo: .data`, and a `.tptheme` is a PACKAGE — it conforms to
        // `public.directory`, never to `public.data`. So the declared type was
        // skipped, the extension fell back to a dynamic `dyn.…` identifier that
        // matches nothing real, and the open panel greyed out every theme:
        // "Choose Files…" could not select one at all. `.item` is the root of
        // both branches and resolves files and packages alike.
        return extensions.compactMap { UTType(filenameExtension: $0, conformingTo: .item) }
    }

    /// What the scanner should do with a file it met.
    enum Candidacy: Sendable, Equatable {
        /// A known extension — take it without opening the file.
        case accept
        /// No extension at all. Only a content probe can tell, and only a
        /// format that opted in is worth probing for.
        case probe
        /// Nothing we can read. Never opened.
        case reject
    }

    static func candidacy(of url: URL) -> Candidacy {
        let ext = url.pathExtension.lowercased()
        if ext.isEmpty { return probesExtensionlessFiles ? .probe : .reject }
        if importableExtensions.contains(ext) { return .accept }
        // Compound extensions (`.bbl.mybible`) already match on their last
        // component, so this only needs the plain case.
        return .reject
    }

    /// The kinds a file's extension could belong to — several, for the
    /// ambiguous ones (`.xml` is OSIS, Zefania, OpenSong or OpenLyrics; `.txt`
    /// is USFM, Unbound or a plain-text song). Deciding between them is the
    /// classifier's job, from content.
    static func possibleKinds(for url: URL) -> Set<ImportKind> {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else {
            return Set(importable.filter(\.matchesExtensionless).map(\.kind))
        }
        return Set(importable.filter { $0.fileExtensions.contains(ext) }.map(\.kind))
    }

    // MARK: - Sources

    private static let bible: [ImportFormatDescriptor] = SupportedBibleFormat.allCases.map { format in
        ImportFormatDescriptor(
            id: "bible.\(format.rawValue)",
            kind: .bible,
            displayName: format.displayName,
            summary: format.formatDescription,
            fileExtensions: format.fileExtensions,
            isDirectorySource: format.isDirectoryFormat,
            isNative: format == .topPresenter,
            canExport: format == .topPresenter
        )
    }

    private static let song: [ImportFormatDescriptor] = SupportedSongFormat.allCases.map { format in
        ImportFormatDescriptor(
            id: "song.\(format.rawValue)",
            kind: .song,
            displayName: format.displayName,
            summary: Self.songSummary(format),
            fileExtensions: format.fileExtensions,
            // OpenSong files are routinely saved with no extension at all, and
            // the parser has always accepted them when handed one directly
            // (SongImportProtocol.swift:34-48). Only the folder walk disagreed.
            matchesExtensionless: format == .openSongXML,
            isNative: format == .topPresenterJSON,
            canExport: format == .topPresenterJSON
        )
    }

    private static let media: [ImportFormatDescriptor] = MediaKind.allCases.map { kind in
        ImportFormatDescriptor(
            id: "media.\(kind.rawValue)",
            kind: .media,
            displayName: kind.filterLabel,
            summary: Self.mediaSummary(kind),
            fileExtensions: kind.fileExtensions.sorted(),
            // Media is referenced in place, never copied, so there is nothing
            // to write back out. "Arată în Finder" is the answer instead.
            canExport: false
        )
    }

    /// The formats with no enum of their own.
    private static let documents: [ImportFormatDescriptor] = [
        ImportFormatDescriptor(
            id: "session.tpschedule",
            kind: .session,
            displayName: String(localized: "TopPresenter Session", comment: "Format name"),
            summary: String(localized: "A service running order, with stable references into the library.",
                            comment: "Format description"),
            fileExtensions: [SessionArchiveService.fileExtension],
            isNative: true,
            canExport: true
        ),
        ImportFormatDescriptor(
            id: "theme.tptheme",
            kind: .theme,
            displayName: String(localized: "TopPresenter Theme", comment: "Format name"),
            summary: String(localized: "The complete presentation look, with backgrounds embedded in the package.",
                            comment: "Format description"),
            fileExtensions: [TopPresenterFormat.theme.fileExtension],
            isDirectorySource: true,
            isNative: true,
            canExport: true
        ),
        ImportFormatDescriptor(
            id: "slides.tpslides",
            kind: .slides,
            displayName: String(localized: "TopPresenter Slides", comment: "Format name"),
            summary: String(localized: "Custom slides.", comment: "Format description"),
            fileExtensions: [TopPresenterFormat.slides.fileExtension],
            isNative: true,
            canExport: true
        ),
    ]

    private static func songSummary(_ format: SupportedSongFormat) -> String {
        switch format {
        case .topPresenterJSON:
            return String(localized: "The native format, with every arrangement, chord and translation.",
                          comment: "Format description")
        case .openSongXML:
            return String(localized: "OpenSong — including files with no extension.", comment: "Format description")
        case .openLyricsXML:
            return String(localized: "OpenLyrics XML.", comment: "Format description")
        case .chordPro:
            return String(localized: "ChordPro, with chords inline in the text.", comment: "Format description")
        case .plainText:
            return String(localized: "Plain text, with verses separated by blank lines.",
                          comment: "Format description")
        case .powerPoint:
            return String(localized: "PowerPoint — each slide's text becomes a verse.",
                          comment: "Format description")
        }
    }

    private static func mediaSummary(_ kind: MediaKind) -> String {
        switch kind {
        case .image: return String(localized: "Background images and graphics.", comment: "Format description")
        case .video: return String(localized: "Video clips.", comment: "Format description")
        case .audio: return String(localized: "Audio files.", comment: "Format description")
        case .document: return String(localized: "PDF documents, presented a page at a time. Export slides from Keynote or PowerPoint as PDF to show them here.",
                                      comment: "Format description")
        }
    }
}
