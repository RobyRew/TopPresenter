//
//  PresentationManager.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import Observation
import AppKit

/// View modifier backing the blur-family transitions (blur, blurZoom, fall).
struct BlurFadeModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double
    var scale: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
            .scaleEffect(scale)
    }
}

/// View modifier backing the "flip" (3D rotation) transition.
struct FlipFadeModifier: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .opacity(opacity)
    }
}

@Observable
// Explicit, not inherited from SWIFT_DEFAULT_ACTOR_ISOLATION: the `isolated
// deinit` below REQUIRES the class to be actor-isolated, and relying on the
// build setting made that true only in some configurations. Building with
// ENABLE_TESTABILITY=YES under Release failed with "deinit is marked isolated,
// but containing class 'PresentationManager' is not isolated to an actor".
@MainActor
final class PresentationManager {
    /// Where this manager's settings live.
    ///
    /// Injected rather than reaching for `.standard`, because the test host runs
    /// inside the real app bundle: every `PresentationManager()` a test built read
    /// and then WROTE the operator's actual saved layouts, themes and settings.
    /// That both corrupted real data and made tests depend on the previous run.
    /// Tests pass a throwaway suite; the app passes nothing.
    @ObservationIgnored let defaults: UserDefaults

    // MARK: - Live Content
    var liveContent = LiveContent()

    /// Video playback service — set once at app start so clearOutput() can stop playback.
    @ObservationIgnored weak var videoService: VideoPlayerService?

    // MARK: - Presentation history (recorded into a separate store)
    /// Set once at app start. Live shows are recorded here (dwell-gated + sessioned).
    @ObservationIgnored var historyStore: HistoryStore?
    @ObservationIgnored private var pendingHistory: HistoryItem?
    @ObservationIgnored private var pendingShownAt: Date = .now
    @ObservationIgnored private var currentSessionID = UUID()
    @ObservationIgnored private var currentSessionKey = ""
    @ObservationIgnored private var lastHistoryShowAt: Date = .distantPast
    /// A verse/slide is only logged once it's been live this long (ignore scrubbing).
    @ObservationIgnored private let historyDwellSeconds: Double = 4
    /// A gap longer than this starts a new presentation session.
    @ObservationIgnored private let historySessionGapSeconds: Double = 1800

    /// Identity of the currently-live item, held until it's recorded (on the next
    /// show or clear, if it dwelled long enough).
    struct HistoryItem {
        var contentType: String
        var sessionKey: String
        var sessionID = UUID()
        var songKey = "", songTitle = "", versionName = "", verseLabel = ""
        var slideIndex = 0
        var translation = "", translationName = "", bookName = "", reference = ""
        var bookNumber = 0, chapter = 0, verseStart = 0, verseEnd = 0
    }

    /// Begin tracking a newly-live item: flush the previous one, then open this one
    /// (assigning it to the current or a fresh session).
    private func beginHistory(_ item: HistoryItem) {
        flushHistory()
        var item = item
        let now = Date()
        if item.sessionKey != currentSessionKey || now.timeIntervalSince(lastHistoryShowAt) > historySessionGapSeconds {
            currentSessionID = UUID()
            currentSessionKey = item.sessionKey
        }
        item.sessionID = currentSessionID
        pendingHistory = item
        pendingShownAt = now
        lastHistoryShowAt = now
    }

    /// Record the pending item iff it was on screen long enough (dwell filter).
    private func flushHistory() {
        guard let p = pendingHistory else { return }
        pendingHistory = nil
        let dwell = Date().timeIntervalSince(pendingShownAt)
        guard dwell >= historyDwellSeconds, let store = historyStore else { return }
        store.record(PresentationEvent(
            timestamp: pendingShownAt, sessionID: p.sessionID, dwellSeconds: dwell, contentType: p.contentType,
            songKey: p.songKey, songTitle: p.songTitle, versionName: p.versionName,
            verseLabel: p.verseLabel, slideIndex: p.slideIndex,
            translation: p.translation, translationName: p.translationName, bookNumber: p.bookNumber,
            bookName: p.bookName, chapter: p.chapter, verseStart: p.verseStart, verseEnd: p.verseEnd,
            reference: p.reference))
    }

    // MARK: - Style
    var currentStyle: PresentationStyle?

    // MARK: - Global Background
    var backgroundImage: NSImage?
    /// Resolved URL of the background media (needed for gif/video playback).
    var backgroundMediaURL: URL?
    /// "image" | "gif" | "video" — backgrounds support the full media trio.
    var backgroundMediaTypeRaw: String {
        didSet { defaults.set(backgroundMediaTypeRaw, forKey: "pm_backgroundMediaTypeRaw") }
    }
    var backgroundImagePath: String? {
        didSet { defaults.set(backgroundImagePath, forKey: "pm_backgroundImagePath") }
    }
    var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: "pm_backgroundOpacity") }
    }
    var useBackgroundImage: Bool {
        didSet { defaults.set(useBackgroundImage, forKey: "pm_useBackgroundImage") }
    }
    /// When false (default), the output window is fully transparent — no solid background.
    /// Enable this to show the background color behind content.
    var backgroundEnabled: Bool {
        didSet { defaults.set(backgroundEnabled, forKey: "pm_backgroundEnabled") }
    }
    /// Ascunde/Clear hides only the CONTENT — the theme background stays up.
    /// Part of the look (theme-persisted); default ON, toggleable in Fundal.
    var backgroundStaysOnHide: Bool {
        didSet { defaults.set(backgroundStaysOnHide, forKey: "pm_backgroundStaysOnHide") }
    }

    // MARK: - Media Helpers (bookmarks + type detection)

    /// Creates a bookmark, preferring security-scoped (user-selected files);
    /// falls back to a plain bookmark (app-container files don't need scope).
    static func makeBookmark(for url: URL) -> Data? {
        if let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            return data
        }
        return try? url.bookmarkData()
    }

    /// Where the global background's security-scoped bookmark lives. Spelled out
    /// in seven places across two files before this; a typo in any of them fails
    /// silently, because UserDefaults just returns nil for a key nobody wrote.
    static let backgroundBookmarkKey = "pm_backgroundImageBookmark"

    /// A resolved bookmark plus, when the stored one had gone stale, a rebuilt
    /// bookmark for whoever owns the storage to write back.
    struct BookmarkResolution {
        let url: URL
        /// Non-nil ⇒ the stored bookmark was stale and MUST be replaced with this.
        let refreshed: Data?
    }

    /// Resolves a bookmark, trying security-scoped first, then plain.
    /// Opens scoped access when applicable (kept open — media renders continuously).
    ///
    /// A stale bookmark still resolves *today* but is living on borrowed time: once
    /// it stops resolving, the background or media box silently renders nothing and
    /// the user is told nothing. So rebuild it here, while access is open, and hand
    /// it back — the caller knows where the bookmark lives, this function doesn't.
    static func resolveBookmarkRefreshing(_ data: Data) -> BookmarkResolution? {
        var isStale = false
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            _ = url.startAccessingSecurityScopedResource()
            return BookmarkResolution(url: url, refreshed: isStale ? makeBookmark(for: url) : nil)
        }
        if let url = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            return BookmarkResolution(url: url, refreshed: isStale ? makeBookmark(for: url) : nil)
        }
        return nil
    }

    /// Resolution for callers that don't own the bookmark's storage.
    static func resolveBookmark(_ data: Data) -> URL? {
        resolveBookmarkRefreshing(data)?.url
    }

    /// Resolves for ONE synchronous use and releases the scope afterwards.
    /// Use this for copies/exports — the long-lived `resolveBookmark` deliberately
    /// keeps its scope open for continuously rendering media, which would otherwise
    /// leak one open scope per exported asset.
    static func withScopedBookmark<T>(_ data: Data, _ body: (URL) throws -> T) rethrows -> T? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            guard let plain = try? URL(resolvingBookmarkData: data, options: [],
                                       relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
            return try body(plain)
        }
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }
        return try body(url)
    }

    /// "image" | "gif" | "video" from a file extension.
    static func mediaType(forExtension ext: String) -> String {
        let lower = ext.lowercased()
        if lower == "gif" { return "gif" }
        if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(lower) { return "video" }
        return "image"
    }

    /// App-container directory where imported theme media lives.
    static func themeMediaDirectory(for themeID: UUID) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ThemeMedia", isDirectory: true)
            .appendingPathComponent(themeID.uuidString, isDirectory: true)
    }

    // MARK: - Per-Content Backgrounds
    /// Optional background override per presenter type ("bible" / "song" / "text").
    /// When a config exists and is enabled, it replaces the global background for
    /// that content type — e.g. a dedicated background only for Bible verses.
    struct BackgroundConfig: Codable, Equatable {
        var enabled: Bool = false
        var showColor: Bool = false
        var colorHex: String = "000000"
        var opacity: Double = 1.0
        var useImage: Bool = false
        var imageBookmark: Data? = nil
        var imageName: String = ""
        /// "image" | "gif" | "video" — backgrounds support the full media trio.
        var mediaTypeRaw: String = "image"

        init() {}

        // Resilient decoding: missing keys fall back to defaults so stored
        // configs and imported themes survive future model growth.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
            showColor = try c.decodeIfPresent(Bool.self, forKey: .showColor) ?? false
            colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "000000"
            opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
            useImage = try c.decodeIfPresent(Bool.self, forKey: .useImage) ?? false
            imageBookmark = try c.decodeIfPresent(Data.self, forKey: .imageBookmark)
            imageName = try c.decodeIfPresent(String.self, forKey: .imageName) ?? ""
            mediaTypeRaw = try c.decodeIfPresent(String.self, forKey: .mediaTypeRaw) ?? "image"
        }
    }

    /// Compat view over the per-profile backgrounds.
    var contentBackgrounds: [String: BackgroundConfig] {
        var result: [String: BackgroundConfig] = [:]
        for key in Self.profileKeys {
            result[key] = readChrome(in: key) { $0.background }
        }
        return result
    }
    /// Decoded still images for per-content backgrounds (image type only).
    var contentBackgroundImages: [String: NSImage] = [:]
    /// Resolved media URLs for per-content backgrounds (gif/video playback).
    var contentBackgroundURLs: [String: URL] = [:]

    static func contentKey(for type: LiveContent.ContentType) -> String {
        switch type {
        case .bible: return "bible"
        case .song: return "song"
        case .media: return "media"
        default: return "text"
        }
    }

    static func contentKeyLabel(_ key: String) -> String {
        switch key {
        case "bible": return String(localized: "Biblie", comment: "Content type")
        case "song": return String(localized: "Cântece", comment: "Content type")
        case "media": return String(localized: "Media", comment: "Content type")
        default: return String(localized: "Slide-uri proprii", comment: "Content type — the Custom Slides profile")
        }
    }

    func backgroundConfig(for key: String) -> BackgroundConfig {
        readChrome(in: key) { $0.background }
    }

    func setBackgroundConfig(_ config: BackgroundConfig, for key: String) {
        mutateChrome(key) { $0.background = config }
    }

    func setContentBackgroundMedia(url: URL, for key: String) {
        guard let bookmark = Self.makeBookmark(for: url) else { return }
        var config = backgroundConfig(for: key)
        config.imageBookmark = bookmark
        config.imageName = url.lastPathComponent
        config.useImage = true
        config.mediaTypeRaw = Self.mediaType(forExtension: url.pathExtension)
        setBackgroundConfig(config, for: key)
        contentBackgroundURLs[key] = url
        contentBackgroundImages[key] = config.mediaTypeRaw == "image" ? NSImage(contentsOf: url) : nil
    }

    func removeContentBackgroundImage(for key: String) {
        var config = backgroundConfig(for: key)
        config.imageBookmark = nil
        config.imageName = ""
        config.useImage = false
        config.mediaTypeRaw = "image"
        setBackgroundConfig(config, for: key)
        contentBackgroundImages[key] = nil
        contentBackgroundURLs[key] = nil
    }

    private func loadContentBackgroundImages() {
        for key in Self.profileKeys {
            let config = readChrome(in: key) { $0.background }
            guard let bookmark = config.imageBookmark,
                  let resolved = Self.resolveBookmarkRefreshing(bookmark) else { continue }
            if let fresh = resolved.refreshed {
                var updated = config
                updated.imageBookmark = fresh
                setBackgroundConfig(updated, for: key)
            }
            let url = resolved.url
            contentBackgroundURLs[key] = url
            contentBackgroundImages[key] = config.mediaTypeRaw == "image" ? NSImage(contentsOf: url) : nil
        }
    }

    /// The effective background for a content type: the per-content override when
    /// enabled, otherwise the global background (frozen-aware via the output accessors).
    struct ActiveBackground {
        var showColor: Bool
        var color: Color
        var opacity: Double
        var useMedia: Bool
        var mediaType: String   // image | gif | video
        var mediaURL: URL?
        var image: NSImage?     // decoded still (image type)
    }

    func activeBackground(for type: LiveContent.ContentType, frozen: Bool) -> ActiveBackground {
        activeBackground(forKey: Self.contentKey(for: type), frozen: frozen)
    }

    func activeBackground(forKey key: String, frozen: Bool) -> ActiveBackground {
        let config = readChrome(in: key) { $0.background }
        if config.enabled {
            return ActiveBackground(
                showColor: config.showColor,
                color: Color(hex: config.colorHex) ?? .black,
                opacity: config.opacity,
                useMedia: config.useImage,
                mediaType: config.mediaTypeRaw,
                mediaURL: contentBackgroundURLs[key],
                image: contentBackgroundImages[key]
            )
        }
        if frozen {
            return ActiveBackground(
                showColor: frozenBackgroundEnabled,
                color: Color(hex: frozenBackgroundColorHex) ?? .black,
                opacity: frozenBackgroundOpacity,
                useMedia: frozenUseBackgroundImage,
                mediaType: backgroundMediaTypeRaw,
                mediaURL: backgroundMediaURL,
                image: frozenBackgroundImage
            )
        }
        return ActiveBackground(
            showColor: backgroundEnabled,
            color: backgroundColor,
            opacity: backgroundOpacity,
            useMedia: useBackgroundImage,
            mediaType: backgroundMediaTypeRaw,
            mediaURL: backgroundMediaURL,
            image: backgroundImage
        )
    }

    // MARK: - Per-Presenter Content Options
    /// Presentation behavior per content type ("bible"/"song"/"text") — travels
    /// with themes. Extend here when a presenter needs a new option.
    struct ContentOptions: Codable, Equatable {
        /// "none" | "upper" | "lower" — applied to the main text at render time.
        var textTransformRaw: String = "none"
        /// Render the reference/title in uppercase (e.g. "IOAN 3:16").
        var referenceUppercase: Bool = false

        // MARK: Interlinear (Bible) — render each word as a stacked column.
        /// "off" | "gloss" (word + meaning) | "full" (word + gloss + Strong's + morph).
        var interlinearModeRaw: String = "off"
        var interlinearShowGloss: Bool = true
        var interlinearShowStrong: Bool = true
        var interlinearShowMorph: Bool = true
        /// Empty = renderer default colour. Per-annotation-row colours.
        var interlinearGlossColorHex: String = ""
        var interlinearStrongColorHex: String = ""
        var interlinearMorphColorHex: String = ""
        /// Annotation font size as a fraction of the verse font.
        var interlinearGlossScale: Double = 0.55
        var interlinearStrongScale: Double = 0.42
        var interlinearMorphScale: Double = 0.38
        /// Gap between word columns and between stacked rows.
        var interlinearColumnSpacing: Double = 12
        var interlinearRowSpacing: Double = 2

        // MARK: Multi-verse (Bible) — how several selected verses render together.
        /// "inline" (one flowing paragraph) | "newLine" (each verse on its own line).
        var multiVerseLayoutRaw: String = "inline"
        /// Prefix each verse with its number, e.g. "(3) For God so loved…".
        var multiVerseShowNumbers: Bool = false
        /// Wrap the joined verses in a custom template when 2+ verses show.
        var multiVerseCustomEnabled: Bool = false
        /// Template used when `multiVerseCustomEnabled`. Tokens: {verses} {ref} {n}.
        /// If it omits {verses}, the verses are appended after the template.
        var multiVerseCustomText: String = ""

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            textTransformRaw = try c.decodeIfPresent(String.self, forKey: .textTransformRaw) ?? "none"
            referenceUppercase = try c.decodeIfPresent(Bool.self, forKey: .referenceUppercase) ?? false
            interlinearModeRaw = try c.decodeIfPresent(String.self, forKey: .interlinearModeRaw) ?? "off"
            interlinearShowGloss = try c.decodeIfPresent(Bool.self, forKey: .interlinearShowGloss) ?? true
            interlinearShowStrong = try c.decodeIfPresent(Bool.self, forKey: .interlinearShowStrong) ?? true
            interlinearShowMorph = try c.decodeIfPresent(Bool.self, forKey: .interlinearShowMorph) ?? true
            interlinearGlossColorHex = try c.decodeIfPresent(String.self, forKey: .interlinearGlossColorHex) ?? ""
            interlinearStrongColorHex = try c.decodeIfPresent(String.self, forKey: .interlinearStrongColorHex) ?? ""
            interlinearMorphColorHex = try c.decodeIfPresent(String.self, forKey: .interlinearMorphColorHex) ?? ""
            interlinearGlossScale = try c.decodeIfPresent(Double.self, forKey: .interlinearGlossScale) ?? 0.55
            interlinearStrongScale = try c.decodeIfPresent(Double.self, forKey: .interlinearStrongScale) ?? 0.42
            interlinearMorphScale = try c.decodeIfPresent(Double.self, forKey: .interlinearMorphScale) ?? 0.38
            interlinearColumnSpacing = try c.decodeIfPresent(Double.self, forKey: .interlinearColumnSpacing) ?? 12
            interlinearRowSpacing = try c.decodeIfPresent(Double.self, forKey: .interlinearRowSpacing) ?? 2
            multiVerseLayoutRaw = try c.decodeIfPresent(String.self, forKey: .multiVerseLayoutRaw) ?? "inline"
            multiVerseShowNumbers = try c.decodeIfPresent(Bool.self, forKey: .multiVerseShowNumbers) ?? false
            multiVerseCustomEnabled = try c.decodeIfPresent(Bool.self, forKey: .multiVerseCustomEnabled) ?? false
            multiVerseCustomText = try c.decodeIfPresent(String.self, forKey: .multiVerseCustomText) ?? ""
        }
    }

    /// Compat view over the per-profile options.
    var contentOptions: [String: ContentOptions] {
        get {
            var result: [String: ContentOptions] = [:]
            for key in Self.profileKeys {
                result[key] = readChrome(in: key) { $0.options }
            }
            return result
        }
        set {
            for (key, options) in newValue where Self.profileKeys.contains(key) {
                mutateChrome(key) { $0.options = options }
            }
        }
    }

    func contentOptions(for key: String) -> ContentOptions {
        readChrome(in: key) { $0.options }
    }

    func setContentOptions(_ options: ContentOptions, for key: String) {
        mutateChrome(key) { $0.options = options }
    }

    /// Multi-verse rendering settings for the active Bible theme — the single
    /// source of truth now that these live in the theme (not global defaults).
    /// Read by the preview card, the verse controls (live push), and BibleView.
    var bibleMultiVerse: (layout: String, showNumbers: Bool, customEnabled: Bool, customText: String) {
        let o = contentOptions(for: "bible")
        return (o.multiVerseLayoutRaw, o.multiVerseShowNumbers, o.multiVerseCustomEnabled, o.multiVerseCustomText)
    }

    static func transformText(_ text: String, raw: String) -> String {
        switch raw {
        case "upper": return text.uppercased()
        case "lower": return text.lowercased()
        default: return text
        }
    }


    // MARK: - Media Module Output Preferences
    /// Whether "Play Video" loops by default (Media module).
    var videoLoopsByDefault: Bool {
        didSet { defaults.set(videoLoopsByDefault, forKey: "pm_videoLoopsByDefault") }
    }
    /// Full-screen video gravity: "fit" | "fill".
    var fullscreenVideoFillRaw: String {
        didSet { defaults.set(fullscreenVideoFillRaw, forKey: "pm_fullscreenVideoFillRaw") }
    }
    /// LIVE framing of full-screen media (image AND video), driven from the
    /// Media panel while something is on screen: zoom 1.0…3.0 plus a pan
    /// offset in FRACTIONS of the output size (resolution-independent, so the
    /// same framing looks identical on any projector).
    var mediaZoom: Double {
        didSet { defaults.set(mediaZoom, forKey: "pm_mediaZoom") }
    }
    var mediaPanX: Double {
        didSet { defaults.set(mediaPanX, forKey: "pm_mediaPanX") }
    }
    var mediaPanY: Double {
        didSet { defaults.set(mediaPanY, forKey: "pm_mediaPanY") }
    }

    /// Back to 100%, centered (the „Resetează" button + every new present).
    func resetMediaFraming() {
        mediaZoom = 1
        mediaPanX = 0
        mediaPanY = 0
    }

    /// Per-box transition override: OFF = the box follows the profile's
    /// transitions; ON = its own effects, delay (stagger) and duration.
    struct BoxTransition: Codable, Equatable {
        var isCustomized: Bool = false
        var inRaw: String = ""        // "" = profile effect
        var changeRaw: String = ""
        var outRaw: String = ""
        var delay: Double = 0         // seconds after the others (stagger)
        var duration: Double = -1     // -1 = phase/profile duration

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isCustomized = try c.decodeIfPresent(Bool.self, forKey: .isCustomized) ?? false
            inRaw = try c.decodeIfPresent(String.self, forKey: .inRaw) ?? ""
            changeRaw = try c.decodeIfPresent(String.self, forKey: .changeRaw) ?? ""
            outRaw = try c.decodeIfPresent(String.self, forKey: .outRaw) ?? ""
            delay = try c.decodeIfPresent(Double.self, forKey: .delay) ?? 0
            duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? -1
        }
    }

    // MARK: - Layout Profiles (PER-PRESENTER layouts)
    /// EVERYTHING layout-related is per presenter: Bible, Songs and Slides each
    /// have their own boxes, styles, sources, order, background, options and
    /// transitions. The editor edits ONE profile; the output renders the live
    /// content's profile. Keys: "bible" | "song" | "text".
    struct LayoutProfile: Codable, Equatable {
        var frames: [String: TextBoxFrame] = [:]
        var visibility: [String: Bool] = [:]
        var styles: [String: BoxTextStyle] = [:]
        var sources: [String: String] = [:]
        var sourceFormats: [String: String] = [:]
        var staticTexts: [String: String] = [:]
        var customTextBoxes: [CustomTextBox] = []
        var mediaBoxes: [MediaBox] = []
        var boxOrder: [String] = []
        var background: BackgroundConfig = BackgroundConfig()
        var options: ContentOptions = ContentOptions()
        /// Text transitions (raw values from `transitionOptions`):
        /// in = first appearance, change = slide → slide, out = clear.
        var transitionInRaw: String = "fade"
        var transitionChangeRaw: String = "fade"
        var transitionOutRaw: String = "fade"
        /// -1 = use the global transition duration.
        var transitionDurationOverride: Double = -1
        /// Per-PHASE duration overrides; -1 = the profile/general duration.
        var transitionInDuration: Double = -1
        var transitionChangeDuration: Double = -1
        var transitionOutDuration: Double = -1
        /// Per-section slide scope: "all" | "first" | "last" (e.g. show the
        /// song title only on the first slide). Keyed by section rawValue.
        var displayOn: [String: String] = [:]
        /// Per-box transition overrides (general → personalizează, like text
        /// styles). Keyed by z-order token.
        var boxTransitionOverrides: [String: BoxTransition] = [:]
        /// Custom accent colors for the editor chrome (list swatch, canvas
        /// border). Keyed by z-order token; absent = the kind's default color.
        var boxColors: [String: String] = [:]
        /// Built-in sections the operator DELETED from this presenter, by rawValue.
        ///
        /// Distinct from `visibility`: hidden means "still a casetă, currently not
        /// drawn" (the eye toggles it), removed means "not in this presenter's list
        /// at all". Their frames/styles are deliberately KEPT, so restoring a
        /// section from the add menu brings its layout back rather than resetting it.
        var removedSections: [String] = []

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            frames = try c.decodeIfPresent([String: TextBoxFrame].self, forKey: .frames) ?? [:]
            visibility = try c.decodeIfPresent([String: Bool].self, forKey: .visibility) ?? [:]
            styles = try c.decodeIfPresent([String: BoxTextStyle].self, forKey: .styles) ?? [:]
            sources = try c.decodeIfPresent([String: String].self, forKey: .sources) ?? [:]
            sourceFormats = try c.decodeIfPresent([String: String].self, forKey: .sourceFormats) ?? [:]
            staticTexts = try c.decodeIfPresent([String: String].self, forKey: .staticTexts) ?? [:]
            customTextBoxes = try c.decodeIfPresent([CustomTextBox].self, forKey: .customTextBoxes) ?? []
            mediaBoxes = try c.decodeIfPresent([MediaBox].self, forKey: .mediaBoxes) ?? []
            boxOrder = try c.decodeIfPresent([String].self, forKey: .boxOrder) ?? []
            background = try c.decodeIfPresent(BackgroundConfig.self, forKey: .background) ?? BackgroundConfig()
            options = try c.decodeIfPresent(ContentOptions.self, forKey: .options) ?? ContentOptions()
            transitionInRaw = try c.decodeIfPresent(String.self, forKey: .transitionInRaw) ?? "fade"
            transitionChangeRaw = try c.decodeIfPresent(String.self, forKey: .transitionChangeRaw) ?? "fade"
            transitionOutRaw = try c.decodeIfPresent(String.self, forKey: .transitionOutRaw) ?? "fade"
            transitionDurationOverride = try c.decodeIfPresent(Double.self, forKey: .transitionDurationOverride) ?? -1
            transitionInDuration = try c.decodeIfPresent(Double.self, forKey: .transitionInDuration) ?? -1
            transitionChangeDuration = try c.decodeIfPresent(Double.self, forKey: .transitionChangeDuration) ?? -1
            transitionOutDuration = try c.decodeIfPresent(Double.self, forKey: .transitionOutDuration) ?? -1
            displayOn = try c.decodeIfPresent([String: String].self, forKey: .displayOn) ?? [:]
            boxTransitionOverrides = try c.decodeIfPresent([String: BoxTransition].self, forKey: .boxTransitionOverrides) ?? [:]
            boxColors = try c.decodeIfPresent([String: String].self, forKey: .boxColors) ?? [:]
            removedSections = try c.decodeIfPresent([String].self, forKey: .removedSections) ?? []
        }

        /// Sensible starting layout per presenter.
        static func defaultProfile(for key: String) -> LayoutProfile {
            var p = LayoutProfile()
            p.frames = [
                TextBoxSection.verseContent.rawValue: .defaultVerse,
                TextBoxSection.reference.rawValue: .defaultReference,
                TextBoxSection.translationName.rawValue: .defaultTranslation,
                TextBoxSection.subtitle.rawValue: .defaultSubtitle,
            ]
            switch key {
            case "song":
                // Songs: lyrics + title + verse label. No Bible translation.
                // The chord chart ships hidden — enable it for a stage/musician layout.
                p.frames[TextBoxSection.chords.rawValue] = .defaultChords
                p.visibility = [
                    TextBoxSection.verseContent.rawValue: true,
                    TextBoxSection.reference.rawValue: true,
                    TextBoxSection.translationName.rawValue: false,
                    TextBoxSection.subtitle.rawValue: true,
                    TextBoxSection.chords.rawValue: false,
                ]
            case "text":
                p.visibility = [
                    TextBoxSection.verseContent.rawValue: true,
                    TextBoxSection.reference.rawValue: true,
                    TextBoxSection.translationName.rawValue: false,
                    TextBoxSection.subtitle.rawValue: false,
                ]
            case "media":
                // The module's media arrives in a real casetă rather than as a
                // hard-coded full-screen layer: full bleed to start, and from there
                // movable, resizable, reorderable, hideable and transitionable like
                // any other box.
                var live = MediaBox()
                live.name = String(localized: "Media (live)", comment: "Default live media box name")
                live.sourceRaw = "live"
                live.frame = TextBoxFrame(x: 0, y: 0, width: 1, height: 1)
                live.contentModeRaw = "fit"
                p.mediaBoxes = [live]
                p.boxOrder = ["media:" + live.id.uuidString]

                // Every built-in text box still ships hidden so a photo or video is
                // never covered by default; the profile is for overlays.
                p.visibility = [
                    TextBoxSection.verseContent.rawValue: false,
                    TextBoxSection.reference.rawValue: false,
                    TextBoxSection.translationName.rawValue: false,
                    TextBoxSection.subtitle.rawValue: false,
                ]
            default: // bible
                p.visibility = [
                    TextBoxSection.verseContent.rawValue: true,
                    TextBoxSection.reference.rawValue: true,
                    TextBoxSection.translationName.rawValue: false,
                    TextBoxSection.subtitle.rawValue: false,
                ]
            }
            return p
        }
    }

    /// Which built-in boxes make sense per presenter — Songs has no Bible
    /// translation box, Slides has neither translation nor verse label.
    static func relevantSections(for key: String) -> [TextBoxSection] {
        switch key {
        case "song": return [.verseContent, .reference, .subtitle, .chords]
        case "text": return [.verseContent, .reference]
        case "media": return [.reference]      // an optional caption over the media
        default: return TextBoxSection.allCases.filter { $0 != .chords }
        }
    }

    static let profileKeys = ["bible", "song", "text", "media"]

    /// The layouts themselves. Deliberately NOT observed: `@Observable` has no
    /// per-key granularity, so one stored property holding every box of every
    /// presenter meant a single drag delta invalidated the entire editor.
    /// Observation is published explicitly instead — see the tiers below.
    ///
    /// Never read this directly from anything a view can reach: a raw read
    /// subscribes to nothing, and the view goes stale. Go through `profile(_:)`
    /// (coarse, always correct) or `readBox` / `readStructure` / `readChrome`.
    @ObservationIgnored var profiles: [String: LayoutProfile] {
        didSet { scheduleProfilesPersist() }
    }

    // MARK: - Granular Layout Observation
    //
    // Three tiers, coarse to fine. EVERY mutation bumps `profileTick`, so a
    // reader that goes through plain `profile(_:)` keeps exactly the behaviour
    // it had when `profiles` was observed directly. That is the safe default:
    // an accessor is coarse — correct but noisy — unless it deliberately opts
    // into a narrower tier, and a wrong opt-in shows up as a stale view rather
    // than as lost data.

    /// Bumped by every mutation of a profile. The fallback dependency.
    private var profileTick: [String: UInt32] = [:]
    /// Bumped when a profile's box SET or stacking order changes.
    private var structureTick: [String: UInt32] = [:]
    /// Bumped when a profile's background, content options or transitions change.
    private var chromeTick: [String: UInt32] = [:]
    /// Per-box tokens, keyed `"<profile>|<box token>"`. Ignored on purpose:
    /// handing out a token is bookkeeping, not a change worth re-rendering for.
    /// Entries for deleted boxes are left behind — each is a few bytes, and
    /// pruning them would mean invalidating during a read.
    @ObservationIgnored private var boxTokens: [String: BoxObservationToken] = [:]

    private func boxObservationToken(_ key: String, _ token: String) -> BoxObservationToken {
        let id = key + "|" + token
        if let existing = boxTokens[id] { return existing }
        let made = BoxObservationToken()
        boxTokens[id] = made
        return made
    }

    /// Reads a slice of a profile scoped to ONE box. The caller subscribes to
    /// that box alone — a sibling's drag will not invalidate it.
    func readBox<T>(_ token: String, in key: String? = nil, _ body: (LayoutProfile) -> T) -> T {
        let k = resolvedKey(key)
        _ = boxObservationToken(k, token).tick
        return body(profiles[k] ?? .defaultProfile(for: k))
    }

    /// Reads the box set / stacking order. Unaffected by edits *within* a box.
    func readStructure<T>(in key: String? = nil, _ body: (LayoutProfile) -> T) -> T {
        let k = resolvedKey(key)
        _ = structureTick[k]
        return body(profiles[k] ?? .defaultProfile(for: k))
    }

    /// Reads background / options / transitions. Unaffected by box edits.
    func readChrome<T>(in key: String? = nil, _ body: (LayoutProfile) -> T) -> T {
        let k = resolvedKey(key)
        _ = chromeTick[k]
        return body(profiles[k] ?? .defaultProfile(for: k))
    }

    /// Invalidates everything in one profile — correct whatever changed.
    private func invalidateProfile(_ key: String) {
        profileTick[key, default: 0] &+= 1
        structureTick[key, default: 0] &+= 1
        chromeTick[key, default: 0] &+= 1
        let prefix = key + "|"
        for (id, token) in boxTokens where id.hasPrefix(prefix) { token.tick &+= 1 }
    }

    /// Invalidates every profile. For wholesale replacement: undo/redo, applying
    /// a theme, importing a `.tptheme`.
    func invalidateAllProfiles() {
        for key in Set(Self.profileKeys).union(profiles.keys) {
            profileTick[key, default: 0] &+= 1
            structureTick[key, default: 0] &+= 1
            chromeTick[key, default: 0] &+= 1
        }
        for (_, token) in boxTokens { token.tick &+= 1 }
    }

    // Test hooks for the invalidation contract. Reading a tick from a view would
    // subscribe to it, which is why these are not used outside tests.
    func observationTick(profile key: String) -> UInt32 { profileTick[key] ?? 0 }
    func observationTick(structureIn key: String) -> UInt32 { structureTick[key] ?? 0 }
    func observationTick(chromeIn key: String) -> UInt32 { chromeTick[key] ?? 0 }
    func observationTick(box token: String, in key: String) -> UInt32 {
        boxObservationToken(key, token).tick
    }

    @ObservationIgnored private var profilesPersistWork: DispatchWorkItem?

    /// Coalesces profile writes. Every profile mutation reassigns `profiles`, and
    /// the high-frequency ones are brutal: a box drag calls `setBoxFrame` on every
    /// reported delta (tens per second) and the static-text field calls
    /// `setStaticText` on every keystroke — each one used to JSON-encode ALL three
    /// profiles (frames, styles, custom + media boxes, transitions, backgrounds)
    /// and write the whole blob to UserDefaults.
    private func scheduleProfilesPersist() {
        profilesPersistWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.persistProfilesNow() }
        profilesPersistWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// Writes the profiles blob RIGHT NOW. Call this anywhere the app could go
    /// away before the debounce fires — end of a drag, app termination,
    /// deactivation. Losing a layout edit because the operator quit 200 ms after
    /// nudging a box is not an acceptable trade for the write coalescing.
    func persistProfilesNow() {
        profilesPersistWork?.cancel()
        profilesPersistWork = nil
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: "pm_layoutProfiles")
        }
    }

    /// The profile currently being EDITED (editor, preview overlay, right bar).
    /// Follows the focused module; the OUTPUT always uses the live content's key.
    var activeProfileKey: String = "bible"

    // MARK: - Chord transpose / capo (display-only — NEVER mutates the stored song)
    /// Semitones the live chord chart is transposed by (−11…11). Reset per song.
    var chordTransposeSemitones: Int = 0
    /// Capo fret for the chord chart (0…11): the fingered shapes drop by this much.
    var chordCapo: Int = 0
    /// The song key the transpose/capo currently apply to — switching songs resets them.
    @ObservationIgnored private var chordTransposeSongKey: String = ""

    /// Flat/sharp flavour for the live chart: the song key shifted by the current
    /// transpose, then spelled per the resulting key.
    var chordPreferFlats: Bool {
        let base = liveContent.songKey.isEmpty ? "C" : liveContent.songKey
        let shifted = ChordTransposer.transpose(base, by: chordTransposeSemitones,
                                                 preferFlats: ChordTransposer.preferFlats(forKey: base))
        return ChordTransposer.preferFlats(forKey: shifted)
    }

    /// Apply the current transpose + capo (capo lowers the fingered shapes) to any
    /// chord lines — used for both the live output and not-yet-live previews.
    func applyChordTranspose(to lines: [SongLine]) -> [SongLine] {
        let net = chordTransposeSemitones - chordCapo
        guard net % 12 != 0 else { return lines }
        let flats = chordPreferFlats
        return lines.map { ChordTransposer.transpose(line: $0, by: net, preferFlats: flats) }
    }

    /// The live slide's chord lines after transpose + capo.
    func transposedSongLines() -> [SongLine] { applyChordTranspose(to: liveContent.songLines) }

    /// The chord chart already shows the lyrics, so when it's active the plain verse
    /// box is suppressed — otherwise two lyric blocks overlap at the verse position.
    /// `hasChartLines` = the chart will actually render content in this context.
    func chordsReplaceVerse(in key: String, hasChartLines: Bool) -> Bool {
        key == "song" && hasChartLines && isSectionVisible(.chords, in: key)
    }

    /// True when the live song slide carries at least one chord (the chart will draw).
    var liveHasChordLines: Bool { liveContent.songLines.contains { !$0.chords.isEmpty } }

    /// The sounding key after transpose (for the chart header); "" if unknown.
    var liveSoundingKey: String {
        let base = liveContent.songKey
        guard !base.isEmpty else { return "" }
        return ChordTransposer.transpose(base, by: chordTransposeSemitones,
                                         preferFlats: ChordTransposer.preferFlats(forKey: base))
    }

    /// Reset transpose/capo whenever a different song goes live (per-song state).
    func syncChordTranspose(forSongKey key: String) {
        guard key != chordTransposeSongKey else { return }
        chordTransposeSongKey = key
        chordTransposeSemitones = 0
        chordCapo = 0
    }

    /// Whether the current transpose/capo belong to this song (else it shows 0).
    func chordTransposeApplies(to songKey: String) -> Bool { chordTransposeSongKey == songKey }

    /// Set transpose/capo for a specific song and PIN it, so projecting that song
    /// keeps the operator's choice instead of resetting it.
    func setChordTranspose(semitones: Int? = nil, capo: Int? = nil, forSongKey key: String) {
        chordTransposeSongKey = key
        if let semitones { chordTransposeSemitones = max(-11, min(11, semitones)) }
        if let capo { chordCapo = max(0, min(11, capo)) }
    }

    private func resolvedKey(_ key: String?) -> String {
        let k = key ?? activeProfileKey
        return Self.profileKeys.contains(k) ? k : "bible"
    }

    /// The whole profile, with a COARSE dependency: the caller is invalidated by
    /// any change to it. Always correct; use a narrower `read…` on hot paths.
    func profile(_ key: String? = nil) -> LayoutProfile {
        let k = resolvedKey(key)
        _ = profileTick[k]
        return profiles[k] ?? .defaultProfile(for: k)
    }

    /// All profile mutations route through here: registers undo + persists.
    /// Assumes the worst and invalidates the whole profile.
    func mutateProfile(_ key: String? = nil, _ body: (inout LayoutProfile) -> Void) {
        registerLayoutUndo()
        let k = resolvedKey(key)
        var p = profiles[k] ?? .defaultProfile(for: k)
        body(&p)
        profiles[k] = p
        invalidateProfile(k)
    }

    /// A mutation confined to ONE box. Bumps that box and the coarse tick, and
    /// leaves its siblings, the stacking order and the chrome alone — this is
    /// what keeps a drag at one invalidated view instead of all of them.
    ///
    /// Only for bodies that cannot change the box set, the order, the
    /// background, the options or the transitions. When in doubt use
    /// `mutateProfile`: it is slower, never wrong.
    func mutateBox(_ token: String, in key: String? = nil, _ body: (inout LayoutProfile) -> Void) {
        registerLayoutUndo()
        let k = resolvedKey(key)
        var p = profiles[k] ?? .defaultProfile(for: k)
        body(&p)
        profiles[k] = p
        boxObservationToken(k, token).tick &+= 1
        profileTick[k, default: 0] &+= 1
    }

    /// A mutation confined to the profile chrome — background, content options,
    /// transitions. Leaves every box alone.
    func mutateChrome(_ key: String? = nil, _ body: (inout LayoutProfile) -> Void) {
        registerLayoutUndo()
        let k = resolvedKey(key)
        var p = profiles[k] ?? .defaultProfile(for: k)
        body(&p)
        profiles[k] = p
        chromeTick[k, default: 0] &+= 1
        profileTick[k, default: 0] &+= 1
    }

    /// Copies one presenter's layout onto another (undo-able).
    ///
    /// Sections the TARGET does not offer are dropped rather than carried across:
    /// Songs has no Bible translation box, Slides has neither translation nor verse
    /// label, Media offers only a caption. Copying them left entries keyed to boxes
    /// that presenter can never show — invisible in the editor (`orderedBoxTokens`
    /// filters by `relevantSections`) but still exported inside the theme and still
    /// resurrected if the same layout was copied onward to a presenter that DOES
    /// have that section.
    ///
    /// Custom and media boxes always come across: they are the operator's own and
    /// belong to no fixed slot.
    func copyProfile(from source: String, to target: String) {
        guard source != target else { return }
        let snapshot = profile(source)
        let allowed = Set(Self.relevantSections(for: target).map(\.rawValue))
        let dropped = Set(TextBoxSection.allCases.map(\.rawValue)).subtracting(allowed)

        mutateProfile(target) { p in
            p = snapshot
            for raw in dropped {
                p.frames[raw] = nil
                p.visibility[raw] = nil
                p.styles[raw] = nil
                p.sources[raw] = nil
                p.sourceFormats[raw] = nil
                p.staticTexts[raw] = nil
                p.displayOn[raw] = nil
                p.boxTransitionOverrides["section:" + raw] = nil
                p.boxColors["section:" + raw] = nil
            }
            p.boxOrder = p.boxOrder.filter { token in
                guard token.hasPrefix("section:") else { return true }
                return allowed.contains(String(token.dropFirst("section:".count)))
            }
            // Whatever the target does not carry falls back to its own defaults.
            let defaults = LayoutProfile.defaultProfile(for: target)
            for raw in allowed where p.visibility[raw] == nil {
                p.visibility[raw] = defaults.visibility[raw]
            }
        }
    }

    /// The profile that was last presented — after Hide/Clear/ESC the exit
    /// transition (and idle "always" media) must keep using IT, not whatever
    /// the operator is editing.
    private var lastLiveProfileKey: String?

    /// The output renders the LIVE content's profile.
    var outputProfileKey: String {
        if liveContent.isLive { return Self.contentKey(for: liveContent.contentType) }
        return lastLiveProfileKey ?? activeProfileKey
    }

    // MARK: - Global Text Settings
    var fontSize: Double {
        didSet { defaults.set(fontSize, forKey: "pm_fontSize") }
    }
    var fontName: String {
        didSet { defaults.set(fontName, forKey: "pm_fontName") }
    }
    var textColorHex: String {
        didSet { defaults.set(textColorHex, forKey: "pm_textColorHex") }
    }
    var backgroundColorHex: String {
        didSet { defaults.set(backgroundColorHex, forKey: "pm_backgroundColorHex") }
    }
    var textAlignment: TextAlignment {
        didSet { defaults.set(Self.alignmentRaw(textAlignment), forKey: "pm_textAlignmentRaw") }
    }
    var lineSpacing: Double {
        didSet { defaults.set(lineSpacing, forKey: "pm_lineSpacing") }
    }
    var padding: Double {
        didSet { defaults.set(padding, forKey: "pm_padding") }
    }
    var shadowEnabled: Bool {
        didSet { defaults.set(shadowEnabled, forKey: "pm_shadowEnabled") }
    }
    var shadowRadius: Double {
        didSet { defaults.set(shadowRadius, forKey: "pm_shadowRadius") }
    }
    /// Shadow color (RRGGBBAA — alpha carries the intensity).
    var shadowColorHex: String {
        didSet { defaults.set(shadowColorHex, forKey: "pm_shadowColorHex") }
    }
    /// Letter spacing in points at the 1080p reference height.
    var letterTracking: Double {
        didSet { defaults.set(letterTracking, forKey: "pm_letterTracking") }
    }
    /// Red-letter (words of Christ): when on, verse runs flagged `woc` render
    /// in `wocColorHex`. Travels with themes; applies to the Bible output.
    var wocStyleEnabled: Bool {
        didSet { defaults.set(wocStyleEnabled, forKey: "pm_wocStyleEnabled") }
    }
    var wocColorHex: String {
        didSet { defaults.set(wocColorHex, forKey: "pm_wocColorHex") }
    }
    var wocColor: Color { Color(hex: wocColorHex) ?? .red }
    var transitionDuration: Double {
        didSet { defaults.set(transitionDuration, forKey: "pm_transitionDuration") }
    }
    /// Global font weight baseline — applied to every box whose section default
    /// is regular (reference keeps its semibold design default unless customized).
    var globalWeightRaw: String {
        didSet { defaults.set(globalWeightRaw, forKey: "pm_globalWeightRaw") }
    }
    /// Global vertical alignment — inherited by every box that hasn't set its own.
    var globalVAlignRaw: String {
        didSet { defaults.set(globalVAlignRaw, forKey: "pm_globalVAlignRaw") }
    }
    /// Global text opacity — multiplied into every non-customized box's opacity.
    var globalTextOpacity: Double {
        didSet { defaults.set(globalTextOpacity, forKey: "pm_globalTextOpacity") }
    }

    static func alignmentRaw(_ alignment: TextAlignment) -> String {
        switch alignment {
        case .leading: return "leading"
        case .trailing: return "trailing"
        default: return "center"
        }
    }

    static func alignment(fromRaw raw: String, fallback: TextAlignment = .center) -> TextAlignment {
        switch raw {
        case "leading": return .leading
        case "trailing": return .trailing
        case "center": return .center
        default: return fallback
        }
    }

    // MARK: - Screen Management
    var availableScreens: [NSScreen] = NSScreen.screens
    var presentationScreenIndex: Int? = nil
    var isPresentationWindowOpen: Bool = false

    /// Window level for the presentation output window.
    /// Options: "normal", "floating", "alwaysOnTop", "behindDesktop"
    var windowLevel: String {
        didSet { defaults.set(windowLevel, forKey: "pm_windowLevel") }
    }

    /// Maps the windowLevel string to an NSWindow.Level.
    var resolvedWindowLevel: NSWindow.Level {
        switch windowLevel {
        case "floating": return .floating
        case "alwaysOnTop": return .statusBar
        case "behindDesktop": return NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) - 1)
        default: return .normal
        }
    }

    // MARK: - Screen Metrics
    /// The complete metrics of the target presentation screen.
    struct ScreenMetrics {
        let resolution: CGSize       // Native pixel resolution
        let points: CGSize           // Point-based size (resolution / backingScaleFactor)
        let backingScale: CGFloat    // Retina factor (1.0, 2.0, etc.)
        let ppi: CGFloat             // Effective PPI (based on physical size if available)
        let aspectRatio: CGFloat     // width / height
        let aspectRatioLabel: String // e.g. "16:9", "4:3", "21:9"
        let isRetina: Bool

        static let fallback = ScreenMetrics(
            resolution: CGSize(width: 1920, height: 1080),
            points: CGSize(width: 1920, height: 1080),
            backingScale: 1.0,
            ppi: 96,
            aspectRatio: 16.0 / 9.0,
            aspectRatioLabel: "16:9",
            isRetina: false
        )
    }

    /// Computes metrics for the target screen (or fallback).
    var targetScreenMetrics: ScreenMetrics {
        guard let screen = targetScreen else { return .fallback }
        let frame = screen.frame
        let scale = screen.backingScaleFactor
        let nativeW = frame.width * scale
        let nativeH = frame.height * scale
        let ratio = frame.width / frame.height

        // Approximate PPI from screen description (displayPixelsWide / physicalSize).
        let ppi: CGFloat
        if let desc = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            let mmW = CGDisplayScreenSize(desc).width
            if mmW > 0 {
                ppi = nativeW / (mmW / 25.4)
            } else {
                ppi = scale > 1.0 ? 144 : 96
            }
        } else {
            ppi = scale > 1.0 ? 144 : 96
        }

        return ScreenMetrics(
            resolution: CGSize(width: nativeW, height: nativeH),
            points: frame.size,
            backingScale: scale,
            ppi: ppi.rounded(),
            aspectRatio: ratio,
            aspectRatioLabel: Self.aspectRatioLabel(for: ratio),
            isRetina: scale > 1.0
        )
    }

    /// The actual NSScreen being targeted.
    var targetScreen: NSScreen? {
        let screens = NSScreen.screens
        if let idx = presentationScreenIndex, idx < screens.count {
            return screens[idx]
        }
        // Default: external screen if available, otherwise the main (built-in) screen
        return screens.count > 1 ? screens.last : screens.first
    }

    /// Whether we're presenting on the same screen as the main app window (single-display mode).
    var isSingleScreenMode: Bool {
        NSScreen.screens.count <= 1
    }

    /// The built-in display (if available), otherwise main screen.
    var builtInScreen: NSScreen? {
        NSScreen.screens.first
    }

    // MARK: - Operator Screen

    /// The `CGDirectDisplayID` behind a screen — NSScreen instances are recreated on
    /// every configuration change, so identity (`===`) is not safe to compare across one.
    private static func displayID(of screen: NSScreen?) -> CGDirectDisplayID? {
        screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    /// The window hosting the app's own UI.
    private var mainAppWindow: NSWindow? {
        NSApplication.shared.windows.first {
            $0.identifier?.rawValue.hasPrefix(WindowIdentifiers.main) == true
        }
    }

    /// The display the operator is actually looking at the app on.
    var operatorScreen: NSScreen? {
        mainAppWindow?.screen ?? NSScreen.main
    }

    /// True when the output covers the operator's own UI — either there is a single
    /// display, or the output is aimed at the very display the app window sits on.
    ///
    /// Everything that hides the output on "single screen" must key off THIS, not
    /// `isSingleScreenMode`: with a second display connected but the output aimed at
    /// the built-in one, the operator is just as blind, yet `screens.count == 2`.
    var isOutputOnOperatorScreen: Bool {
        if isSingleScreenMode { return true }
        guard let outID = Self.displayID(of: targetScreen),
              let uiID = Self.displayID(of: operatorScreen) else { return false }
        return outID == uiID
    }

    /// Human-readable aspect ratio label.
    private static func aspectRatioLabel(for ratio: CGFloat) -> String {
        let known: [(String, CGFloat)] = [
            ("32:9", 32.0/9.0), ("21:9", 21.0/9.0), ("16:9", 16.0/9.0),
            ("16:10", 16.0/10.0), ("3:2", 3.0/2.0), ("4:3", 4.0/3.0),
            ("5:4", 5.0/4.0), ("1:1", 1.0)
        ]
        for (label, r) in known {
            if abs(ratio - r) < 0.05 { return label }
        }
        return String(format: "%.2f:1", ratio)
    }

    // MARK: - Screen Disconnection Handling

    enum ScreenDisconnectAction: String {
        case doNothing = "doNothing"
        case moveToAvailable = "moveToAvailable"
        case goBlack = "goBlack"
        case ask = "ask"  // default — shows alert
    }

    /// What to do when the target screen is disconnected. Persisted.
    ///
    /// Stored + `didSet` like the other 33 persisted settings, deliberately: as a
    /// computed property over UserDefaults it was invisible to Observation, so a
    /// view reading it would not re-render when it changed elsewhere.
    var screenDisconnectAction: ScreenDisconnectAction {
        didSet { defaults.set(screenDisconnectAction.rawValue, forKey: "pm_screenDisconnectAction") }
    }

    /// Which display change the pending prompt is about.
    enum ScreenChangeKind: String {
        case disconnected
        case connected
    }

    /// Whether the screen-change prompt should be shown.
    var showScreenDisconnectedAlert: Bool = false

    /// What the pending prompt is asking about.
    var pendingScreenChange: ScreenChangeKind = .disconnected

    /// Index into `NSScreen.screens` of a display that just appeared, for the
    /// "move the presentation there?" prompt.
    var pendingConnectedScreenIndex: Int?

    /// Monitors screen configuration changes.
    private var screenObserver: (any NSObjectProtocol)?

    func startScreenMonitoring() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // queue: .main guarantees main-thread delivery; the closure is just
            // typed nonisolated @Sendable, so assert the isolation for Swift 6.
            MainActor.assumeIsolated {
                self?.handleScreenConfigurationChange()
            }
        }
    }

    func stopScreenMonitoring() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    /// Observers that force a pending profile write out before the app can vanish.
    @ObservationIgnored private var persistenceObservers: [any NSObjectProtocol] = []

    /// The debounce is only safe because these exist: quitting or switching away
    /// 200 ms after nudging a box must not lose the edit.
    func startPersistenceGuards() {
        guard persistenceObservers.isEmpty else { return }
        for name in [NSApplication.willTerminateNotification, NSApplication.didResignActiveNotification] {
            persistenceObservers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.persistProfilesNow() }
                }
            )
        }
    }

    func stopPersistenceGuards() {
        for observer in persistenceObservers { NotificationCenter.default.removeObserver(observer) }
        persistenceObservers = []
    }

    // isolated deinit (SE-0371): runs on the main actor — may touch isolated state.
    isolated deinit {
        stopScreenMonitoring()
        stopPersistenceGuards()
        persistProfilesNow()   // never let a queued write die with the object
    }

    func handleScreenConfigurationChange() {
        let oldScreens = availableScreens
        availableScreens = NSScreen.screens

        // Check if our target screen was disconnected
        let wasTargetLost: Bool
        if let idx = presentationScreenIndex {
            wasTargetLost = idx >= availableScreens.count
        } else {
            wasTargetLost = oldScreens.count > availableScreens.count
        }
        let screenAdded = availableScreens.count > oldScreens.count

        guard isPresentationWindowOpen else {
            // Nothing is being output — just keep the (hidden) window on its screen.
            if let idx = presentationScreenIndex, idx < availableScreens.count {
                movePresentationWindow(to: availableScreens[idx])
            }
            return
        }

        if wasTargetLost {
            // Target screen was disconnected — take action
            switch screenDisconnectAction {
            case .doNothing:
                break
            case .moveToAvailable:
                moveToNextAvailableScreen()
            case .goBlack:
                isBlackScreen = true
                if let builtIn = builtInScreen {
                    presentationScreenIndex = 0
                    movePresentationWindow(to: builtIn)
                }
            case .ask:
                // Ask FIRST, act second. Nothing is being projected anywhere at this
                // point, so the safe state is to show nothing until the operator
                // decides. Relocating the output onto the remaining display before
                // asking buries the app — and this very alert — under a full-screen
                // always-on-top overlay, leaving the operator with a projection they
                // cannot see past and a prompt they cannot read.
                hidePresentationWindow()
                pendingConnectedScreenIndex = nil
                pendingScreenChange = .disconnected
                showScreenDisconnectedAlert = true
            }
            return
        }

        if screenAdded, screenDisconnectAction == .ask,
           let newIndex = availableScreens.indices.last,
           newIndex != presentationScreenIndex {
            // A display appeared mid-service. Don't hijack a running output — ask,
            // and leave everything exactly where it is until told otherwise.
            pendingConnectedScreenIndex = newIndex
            pendingScreenChange = .connected
            showScreenDisconnectedAlert = true
            return
        }

        // Same displays, different geometry (resolution / arrangement) — just refit.
        if let idx = presentationScreenIndex, idx < availableScreens.count {
            movePresentationWindow(to: availableScreens[idx])
        }
    }

    /// Accepts the "a new screen appeared" prompt: retargets the output at it.
    func movePresentationToPendingScreen() {
        let screens = NSScreen.screens
        guard let idx = pendingConnectedScreenIndex, idx < screens.count else { return }
        presentationScreenIndex = idx
        movePresentationWindow(to: screens[idx])
        showPresentationWindow()
        pendingConnectedScreenIndex = nil
    }

    /// Moves the presentation to the next available external screen, or built-in screen as fallback.
    func moveToNextAvailableScreen() {
        let screens = NSScreen.screens
        if screens.count > 1, let external = screens.last {
            presentationScreenIndex = screens.count - 1
            movePresentationWindow(to: external)
        } else if let builtIn = screens.first {
            presentationScreenIndex = 0
            movePresentationWindow(to: builtIn)
        }
    }

    // MARK: - Presentation State
    var isBlackScreen: Bool = false
    var isFrozen: Bool = false

    // MARK: - Auto-Fit Verse Font
    /// When true, the verse font size is shrunk automatically to prevent overflow.
    var autoFitVerseFont: Bool {
        didSet { defaults.set(autoFitVerseFont, forKey: "pm_autoFitVerseFont") }
    }

    // MARK: - Fixed Text Boxes
    /// A text box frame in normalized screen coordinates (0…1 fractions).
    /// The box is FIXED: it never moves or resizes with its content — text is
    /// laid out inside it. Users edit boxes in Edit Mode / the Layout Editor.
    struct TextBoxFrame: Equatable, Codable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double

        static let minSize: Double = 0.05

        /// Clamps the frame so it stays fully on screen with a sane minimum size.
        func clamped() -> TextBoxFrame {
            var f = self
            f.width = min(max(f.width, Self.minSize), 1.0)
            f.height = min(max(f.height, Self.minSize), 1.0)
            f.x = min(max(f.x, 0), 1.0 - f.width)
            f.y = min(max(f.y, 0), 1.0 - f.height)
            return f
        }

        /// Pixel/point rect for a canvas of the given size.
        func rect(in canvasSize: CGSize) -> CGRect {
            CGRect(
                x: x * canvasSize.width,
                y: y * canvasSize.height,
                width: width * canvasSize.width,
                height: height * canvasSize.height
            )
        }

        // Defaults mirror the classic centered layout.
        // Translation defaults to the top-left corner (and hidden by default).
        static let defaultVerse = TextBoxFrame(x: 0.05, y: 0.15, width: 0.90, height: 0.55)
        static let defaultReference = TextBoxFrame(x: 0.05, y: 0.72, width: 0.90, height: 0.10)
        static let defaultTranslation = TextBoxFrame(x: 0.02, y: 0.03, width: 0.22, height: 0.07)
        static let defaultSubtitle = TextBoxFrame(x: 0.05, y: 0.90, width: 0.90, height: 0.06)
        /// Chords default to the lyrics area — "tied to the verse" out of the box.
        static let defaultChords = TextBoxFrame(x: 0.05, y: 0.15, width: 0.90, height: 0.55)

        static func decode(from defaults: UserDefaults, key: String, fallback: TextBoxFrame) -> TextBoxFrame {
            guard let data = defaults.data(forKey: key),
                  let frame = try? JSONDecoder().decode(TextBoxFrame.self, from: data) else {
                return fallback
            }
            return frame.clamped()
        }

        func persist(to defaults: UserDefaults, key: String) {
            if let data = try? JSONEncoder().encode(self) {
                defaults.set(data, forKey: key)
            }
        }
    }

    // MARK: - Box Text Style (uniform for every text box)
    /// The SAME style set applies to every text box — built-in or custom.
    /// `isCustomized == false` (default) means the box inherits the global text
    /// settings plus its section defaults; enabling customization seeds the
    /// fields with the current effective values so editing starts from reality.
    struct BoxTextStyle: Codable, Equatable {
        var isCustomized: Bool = false
        var fontName: String = ""       // "" = global font
        var fontSize: Double = 0        // 0 = section default (pt @1080p)
        var weightRaw: String = ""      // "" = section default
        var colorHex: String = ""       // "" = global color
        var opacity: Double = 1.0
        var hAlignRaw: String = ""      // "" = global alignment
        var vAlignRaw: String = ""      // "" = global vertical alignment
        var lineSpacing: Double = -1    // -1 = global
        var transformRaw: String = ""   // "" = global transform | none | upper | lower
        var padding: Double = -1        // -1 = global inner inset (pt @1080p)
        var shadowMode: String = ""     // "" = global | "on" | "off"
        var shadowRadius: Double = -1   // -1 = global radius
        var shadowColorHex: String = "" // "" = global shadow color (RRGGBBAA)
        var autoFitMode: String = ""    // "" = global behavior | "on" | "off"
        var tracking: Double? = nil     // nil = global letter spacing (pt @1080p)

        init() {}

        // Resilient decoding — stored styles survive new fields.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            isCustomized = try c.decodeIfPresent(Bool.self, forKey: .isCustomized) ?? false
            fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? ""
            fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 0
            weightRaw = try c.decodeIfPresent(String.self, forKey: .weightRaw) ?? ""
            colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? ""
            opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
            hAlignRaw = try c.decodeIfPresent(String.self, forKey: .hAlignRaw) ?? ""
            vAlignRaw = try c.decodeIfPresent(String.self, forKey: .vAlignRaw) ?? ""
            lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? -1
            transformRaw = try c.decodeIfPresent(String.self, forKey: .transformRaw) ?? ""
            padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? -1
            shadowMode = try c.decodeIfPresent(String.self, forKey: .shadowMode) ?? ""
            shadowRadius = try c.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? -1
            shadowColorHex = try c.decodeIfPresent(String.self, forKey: .shadowColorHex) ?? ""
            autoFitMode = try c.decodeIfPresent(String.self, forKey: .autoFitMode) ?? ""
            tracking = try c.decodeIfPresent(Double.self, forKey: .tracking)
        }

        static func weight(fromRaw raw: String, fallback: Font.Weight) -> Font.Weight {
            switch raw {
            case "regular": return .regular
            case "semibold": return .semibold
            case "bold": return .bold
            default: return fallback
            }
        }

        static func weightRaw(_ weight: Font.Weight) -> String {
            switch weight {
            case .bold: return "bold"
            case .semibold: return "semibold"
            default: return "regular"
            }
        }
    }

    /// Fully resolved style, ready to render.
    struct ResolvedBoxStyle {
        var fontName: String      // "" = system font
        var fontSize: Double      // pt at 1080p reference height
        var weight: Font.Weight
        var color: Color
        var opacity: Double
        var hAlign: TextAlignment
        var vAlignRaw: String
        var lineSpacing: Double
        var transformRaw: String = "none"  // none | upper | lower — applied at render
        var padding: Double = 0            // inner horizontal inset (pt @1080p)
        var shadowEnabled: Bool = true
        var shadowRadius: Double = 3
        var shadowColor: Color = Color.black.opacity(0.7)
        var autoFit: Bool = false          // shrink font until the text fits the box
        var tracking: Double = 0           // letter spacing (pt @1080p)

        /// The render-ready text: every box runs its resolved transform.
        func display(_ text: String) -> String {
            PresentationManager.transformText(text, raw: transformRaw)
        }

        func font(at scaledSize: CGFloat) -> Font {
            // .weight on the custom font too — otherwise Greutate is a no-op
            // for every non-System font.
            (fontName.isEmpty || fontName == "System")
                ? .system(size: scaledSize, weight: weight)
                : .custom(fontName, size: scaledSize).weight(weight)
        }

        var frameAlignment: Alignment {
            PresentationManager.boxAlignment(horizontal: hAlign, verticalRaw: vAlignRaw)
        }
    }

    /// Section defaults applied when a box is not customized (or a field is unset).
    static func styleDefaults(for section: TextBoxSection) -> (sizeFactor: Double, weight: Font.Weight, opacity: Double) {
        switch section {
        case .verseContent: return (1.0, .regular, 1.0)
        case .reference: return (0.55, .semibold, 0.9)
        case .translationName: return (0.35, .regular, 0.6)
        case .subtitle: return (0.4, .regular, 0.6)
        case .chords: return (0.5, .regular, 1.0)
        }
    }

    static let customBoxSizeFactor: Double = 0.5

    // Compat: ACTIVE profile styles
    var verseStyle: BoxTextStyle {
        get { boxStyle(for: .verseContent) }
        set { setBoxStyle(newValue, for: .verseContent) }
    }
    var refStyle: BoxTextStyle {
        get { boxStyle(for: .reference) }
        set { setBoxStyle(newValue, for: .reference) }
    }
    var translationStyle: BoxTextStyle {
        get { boxStyle(for: .translationName) }
        set { setBoxStyle(newValue, for: .translationName) }
    }
    var subtitleStyle: BoxTextStyle {
        get { boxStyle(for: .subtitle) }
        set { setBoxStyle(newValue, for: .subtitle) }
    }

    func boxStyle(for section: TextBoxSection, in key: String? = nil) -> BoxTextStyle {
        readBox(Self.sectionToken(section), in: key) { $0.styles[section.rawValue] } ?? BoxTextStyle()
    }

    func setBoxStyle(_ style: BoxTextStyle, for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.styles[section.rawValue] = style }
    }

    /// Resolves a BoxTextStyle against the globals + the given defaults.
    private func resolve(_ style: BoxTextStyle, sizeFactor: Double, defaultWeight: Font.Weight, defaultOpacity: Double, defaultTransform: String = "none", defaultAutoFit: Bool = false) -> ResolvedBoxStyle {
        let globalFontName = (fontName == "System") ? "" : fontName
        // Section defaults of .regular inherit the global weight baseline;
        // design defaults (reference = semibold) stay unless customized.
        let inheritedWeight: Font.Weight = (defaultWeight == .regular)
            ? BoxTextStyle.weight(fromRaw: globalWeightRaw, fallback: .regular)
            : defaultWeight
        let globalShadowColor = Color(hex: shadowColorHex) ?? Color.black.opacity(0.7)
        guard style.isCustomized else {
            // A NOT-customized box inherits EVERYTHING global — including the
            // vertical alignment (a stale seeded vAlignRaw used to stick here
            // and made the global Vertical picker look broken).
            return ResolvedBoxStyle(
                fontName: globalFontName,
                fontSize: fontSize * sizeFactor,
                weight: inheritedWeight,
                color: textColor,
                opacity: defaultOpacity * globalTextOpacity,
                hAlign: textAlignment,
                vAlignRaw: globalVAlignRaw,
                lineSpacing: lineSpacing,
                transformRaw: defaultTransform,
                padding: padding,
                shadowEnabled: shadowEnabled,
                shadowRadius: shadowRadius,
                shadowColor: globalShadowColor,
                autoFit: defaultAutoFit,
                tracking: letterTracking
            )
        }
        return ResolvedBoxStyle(
            fontName: style.fontName.isEmpty ? globalFontName : (style.fontName == "System" ? "" : style.fontName),
            fontSize: style.fontSize > 0 ? style.fontSize : fontSize * sizeFactor,
            weight: BoxTextStyle.weight(fromRaw: style.weightRaw, fallback: inheritedWeight),
            color: style.colorHex.isEmpty ? textColor : (Color(hex: style.colorHex) ?? textColor),
            opacity: style.opacity,
            hAlign: style.hAlignRaw.isEmpty ? textAlignment : Self.alignment(fromRaw: style.hAlignRaw, fallback: textAlignment),
            vAlignRaw: style.vAlignRaw.isEmpty ? globalVAlignRaw : style.vAlignRaw,
            lineSpacing: style.lineSpacing >= 0 ? style.lineSpacing : lineSpacing,
            transformRaw: style.transformRaw.isEmpty ? defaultTransform : style.transformRaw,
            padding: style.padding >= 0 ? style.padding : padding,
            shadowEnabled: style.shadowMode.isEmpty ? shadowEnabled : style.shadowMode == "on",
            shadowRadius: style.shadowRadius >= 0 ? style.shadowRadius : shadowRadius,
            shadowColor: style.shadowColorHex.isEmpty ? globalShadowColor : (Color(hex: style.shadowColorHex) ?? globalShadowColor),
            autoFit: style.autoFitMode.isEmpty ? defaultAutoFit : style.autoFitMode == "on",
            tracking: style.tracking ?? letterTracking
        )
    }

    /// The transform a box inherits when it has none of its own: the profile's
    /// global transform, plus the legacy "reference in caps" option.
    private func defaultTransform(for section: TextBoxSection?, in key: String?) -> String {
        let options = readChrome(in: key) { $0.options }
        if section == .reference && options.referenceUppercase { return "upper" }
        return options.textTransformRaw
    }

    func resolvedStyle(for section: TextBoxSection, in key: String? = nil) -> ResolvedBoxStyle {
        let defaults = Self.styleDefaults(for: section)
        return resolve(
            boxStyle(for: section, in: key),
            sizeFactor: defaults.sizeFactor, defaultWeight: defaults.weight, defaultOpacity: defaults.opacity,
            defaultTransform: defaultTransform(for: section, in: key),
            defaultAutoFit: autoFitVerseFont && section == .verseContent
        )
    }

    func resolvedCustomStyle(_ box: CustomTextBox, in key: String? = nil) -> ResolvedBoxStyle {
        resolve(
            box.style,
            sizeFactor: Self.customBoxSizeFactor, defaultWeight: .regular, defaultOpacity: 1.0,
            defaultTransform: defaultTransform(for: nil, in: key)
        )
    }

    /// Turns customization on and seeds the editable fields with the current
    /// effective values, so the controls show reality instead of zeros.
    func enableStyleCustomization(for section: TextBoxSection, in key: String? = nil) {
        var style = boxStyle(for: section, in: key)
        guard !style.isCustomized else { return }
        let resolved = resolvedStyle(for: section, in: key)
        style.isCustomized = true
        style.fontSize = resolved.fontSize
        style.weightRaw = BoxTextStyle.weightRaw(resolved.weight)
        style.opacity = resolved.opacity
        style.vAlignRaw = resolved.vAlignRaw
        setBoxStyle(style, for: section, in: key)
    }

    // MARK: - Chord-row style (the chord letters inside the Acorduri box)
    /// A SECOND, fully independent style for the chord letters — separate from the
    /// box's main style, which dresses the lyrics. Stored under a reserved key in the
    /// profile's style dict (never collides with a section rawValue).
    static let chordRowStyleKey = "chordRow"

    func chordRowStyle(in key: String? = nil) -> BoxTextStyle {
        readBox(Self.sectionToken(.chords), in: key) { $0.styles[Self.chordRowStyleKey] } ?? BoxTextStyle()
    }
    func setChordRowStyle(_ style: BoxTextStyle, in key: String? = nil) {
        mutateBox(Self.sectionToken(.chords), in: key) { $0.styles[Self.chordRowStyleKey] = style }
    }
    /// Chords default to ~0.55× the lyric size and semibold, until customized.
    func resolvedChordRowStyle(in key: String? = nil) -> ResolvedBoxStyle {
        resolve(chordRowStyle(in: key), sizeFactor: 0.55, defaultWeight: .semibold, defaultOpacity: 1.0)
    }
    func enableChordRowStyleCustomization(in key: String? = nil) {
        var style = chordRowStyle(in: key)
        guard !style.isCustomized else { return }
        let resolved = resolvedChordRowStyle(in: key)
        style.isCustomized = true
        style.fontSize = resolved.fontSize
        style.weightRaw = BoxTextStyle.weightRaw(resolved.weight)
        style.opacity = resolved.opacity
        style.vAlignRaw = resolved.vAlignRaw
        setChordRowStyle(style, in: key)
    }
    /// Output-profile resolved chord style (mirrors `outputStyle(for:)`).
    func outputChordRowStyle() -> ResolvedBoxStyle { resolvedChordRowStyle(in: outputProfileKey) }

    // MARK: - Custom Text Boxes
    /// A user-created text box — church name, CCLI line, a second reference, a
    /// clock… `sourceRaw` decides where the text comes from.
    struct CustomTextBox: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        /// Display name shown in lists and on the canvas label. Empty = derived.
        var name: String = ""
        var text: String = ""
        var frame: TextBoxFrame = TextBoxFrame(x: 0.30, y: 0.42, width: 0.40, height: 0.12)
        var style: BoxTextStyle = BoxTextStyle()
        var isVisible: Bool = true
        /// "static" | "mainText" | "reference" | "translation" | "subtitle"
        /// | "date" | "time" | "slideNumber"
        var sourceRaw: String = "static"
        /// Format for date/time sources (see formattedClock).
        var sourceFormatRaw: String = ""
        /// Slide scope: "all" | "first" | "last" (e.g. "Amin." only on the last slide).
        var displayOnRaw: String = "all"
        /// Static text wrapped around a LIVE source's value, e.g. prefix "Ref: "
        /// → "Ref: Ioan 3:16", or suffix " (NTR)". Ignored for the "static"/"auto"
        /// sources and when the live value is empty (so an empty box stays empty).
        var prefix: String = ""
        var suffix: String = ""

        init() {}

        // Resilient decoding — stored profiles survive new fields.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            frame = try c.decodeIfPresent(TextBoxFrame.self, forKey: .frame) ?? TextBoxFrame(x: 0.30, y: 0.42, width: 0.40, height: 0.12)
            style = try c.decodeIfPresent(BoxTextStyle.self, forKey: .style) ?? BoxTextStyle()
            isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
            sourceRaw = try c.decodeIfPresent(String.self, forKey: .sourceRaw) ?? "static"
            sourceFormatRaw = try c.decodeIfPresent(String.self, forKey: .sourceFormatRaw) ?? ""
            displayOnRaw = try c.decodeIfPresent(String.self, forKey: .displayOnRaw) ?? "all"
            prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
            suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        }

        /// Live sources support prefix/suffix; static/auto are used verbatim.
        var supportsAffixes: Bool { sourceRaw != "static" && sourceRaw != "auto" }

        func resolvedText(main: String, reference: String, translation: String, subtitle: String, now: Date = .now, slideNumber: String = "",
                          footnote: String = "", crossReference: String = "", heading: String = "", gloss: String = "", strongs: String = "",
                          songAuthor: String = "", songCopyright: String = "", songCCLI: String = "",
                          songbook: String = "", songStyle: String = "", songKey: String = "", songTempo: String = "",
                          mediaURL: URL? = nil, mediaKind: String = "") -> String {
            let value = PresentationManager.resolveBoxSource(
                sourceRaw, format: sourceFormatRaw, autoValue: text, staticText: text,
                main: main, reference: reference, translation: translation, subtitle: subtitle,
                now: now, slideNumber: slideNumber,
                footnote: footnote, crossReference: crossReference, heading: heading, gloss: gloss, strongs: strongs,
                songAuthor: songAuthor, songCopyright: songCopyright, songCCLI: songCCLI,
                songbook: songbook, songStyle: songStyle, songKey: songKey, songTempo: songTempo,
                mediaURL: mediaURL, mediaKind: mediaKind
            )
            // Wrap a non-empty live value with the static prefix/suffix.
            guard supportsAffixes, !value.isEmpty, !(prefix.isEmpty && suffix.isEmpty) else { return value }
            return prefix + value + suffix
        }

        func resolvedText(live: LiveContent, now: Date = .now) -> String {
            resolvedText(
                main: live.mainText, reference: live.reference,
                translation: live.translationName, subtitle: live.subtitle,
                now: now, slideNumber: live.slideNumberText,
                footnote: live.footnote, crossReference: live.crossReference,
                heading: live.heading, gloss: live.gloss, strongs: live.strongs,
                songAuthor: live.songAuthor, songCopyright: live.songCopyright, songCCLI: live.songCCLI,
                songbook: live.songbook, songStyle: live.songStyle, songKey: live.songKey, songTempo: live.songTempo,
                mediaURL: live.mediaURL, mediaKind: live.mediaKind
            )
        }

        var sourceLabel: String { PresentationManager.sourceOptionLabel(sourceRaw) }
    }

    // Compat: ACTIVE profile custom boxes
    var customTextBoxes: [CustomTextBox] {
        get { profile().customTextBoxes }
        set { mutateProfile { $0.customTextBoxes = newValue } }
    }

    @discardableResult
    func addCustomTextBox(in key: String? = nil) -> CustomTextBox {
        var box = CustomTextBox()
        box.text = String(localized: "Text nou", comment: "Default text of a newly added custom text box")
        let offset = Double(profile(key).customTextBoxes.count % 5) * 0.04
        box.frame = TextBoxFrame(x: 0.30 + offset, y: 0.42 + offset, width: 0.40, height: 0.12).clamped()
        mutateProfile(key) { $0.customTextBoxes.append(box) }
        return box
    }

    func removeCustomTextBox(id: UUID, in key: String? = nil) {
        mutateProfile(key) { $0.customTextBoxes.removeAll { $0.id == id } }
    }

    func customTextBox(id: UUID, in key: String? = nil) -> CustomTextBox? {
        readBox(Self.customToken(id), in: key) { $0.customTextBoxes.first { $0.id == id } }
    }

    func updateCustomTextBox(_ box: CustomTextBox, in key: String? = nil) {
        mutateBox(Self.customToken(box.id), in: key) { p in
            guard let idx = p.customTextBoxes.firstIndex(where: { $0.id == box.id }) else { return }
            var clamped = box
            clamped.frame = box.frame.clamped()
            p.customTextBoxes[idx] = clamped
        }
    }

    /// Duplicates a custom text box (new id, slightly offset frame).
    func duplicateCustomTextBox(id: UUID, in key: String? = nil) -> CustomTextBox? {
        guard var copy = customTextBox(id: id, in: key) else { return nil }
        copy.id = UUID()
        copy.frame = TextBoxFrame(
            x: copy.frame.x + 0.03, y: copy.frame.y + 0.03,
            width: copy.frame.width, height: copy.frame.height
        ).clamped()
        let snapshot = copy
        mutateProfile(key) { $0.customTextBoxes.append(snapshot) }
        return copy
    }

    // MARK: - Media Boxes (logo, picture, GIF, video overlays)
    struct MediaBox: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        /// Display name. Empty = file name.
        var name: String = ""
        var frame: TextBoxFrame = TextBoxFrame(x: 0.74, y: 0.05, width: 0.20, height: 0.18)
        var fileName: String = ""
        /// Security-scoped bookmark of the media file (sandbox-safe across launches).
        var bookmarkData: Data? = nil
        var mediaTypeRaw: String = "image"   // image | gif | video
        var opacity: Double = 1.0
        /// Corner radius in points at 1080p reference height.
        var cornerRadius: Double = 0
        /// Edge feather (soft border fade) in points at 1080p reference height.
        var edgeFeather: Double = 0
        var contentModeRaw: String = "fit"   // fit | fill
        /// "file" = this box's own bookmarked file (the original behaviour).
        /// "live" = whatever the Media module is showing right now.
        ///
        /// The live variant is what turns full-screen media into an ordinary
        /// casetă: it used to be two hard-coded layers in the output that bypassed
        /// the box system entirely, so it could not be moved, resized, reordered,
        /// given a transition or hidden like everything else.
        var sourceRaw: String = "file"
        /// When to show: "always" | "bible" | "song" | "text"
        var showOnRaw: String = "always"
        /// Slide scope: "all" | "first" | "last".
        var displayOnRaw: String = "all"
        var isVisible: Bool = true

        init() {}

        // Resilient decoding — stored profiles survive new fields.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            frame = try c.decodeIfPresent(TextBoxFrame.self, forKey: .frame) ?? TextBoxFrame(x: 0.74, y: 0.05, width: 0.20, height: 0.18)
            fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
            bookmarkData = try c.decodeIfPresent(Data.self, forKey: .bookmarkData)
            mediaTypeRaw = try c.decodeIfPresent(String.self, forKey: .mediaTypeRaw) ?? "image"
            opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
            cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
            edgeFeather = try c.decodeIfPresent(Double.self, forKey: .edgeFeather) ?? 0
            contentModeRaw = try c.decodeIfPresent(String.self, forKey: .contentModeRaw) ?? "fit"
            sourceRaw = try c.decodeIfPresent(String.self, forKey: .sourceRaw) ?? "file"
            showOnRaw = try c.decodeIfPresent(String.self, forKey: .showOnRaw) ?? "always"
            displayOnRaw = try c.decodeIfPresent(String.self, forKey: .displayOnRaw) ?? "all"
            isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        }

        func resolvedURL() -> URL? {
            guard let data = bookmarkData else { return nil }
            return PresentationManager.resolveBookmark(data)
        }

        func showsFor(contentType: LiveContent.ContentType, isLive: Bool) -> Bool {
            switch showOnRaw {
            case "bible": return isLive && contentType == .bible
            case "song": return isLive && contentType == .song
            case "text": return isLive && contentType == .text
            default: return true
            }
        }

        var showOnLabel: String {
            switch showOnRaw {
            case "bible": return String(localized: "Doar Biblie", comment: "Media visibility option")
            case "song": return String(localized: "Doar Cântece", comment: "Media visibility option")
            case "text": return String(localized: "Doar Slide-uri", comment: "Media visibility option")
            default: return String(localized: "Întotdeauna", comment: "Media visibility option")
            }
        }
    }

    // Compat: ACTIVE profile media boxes
    var mediaBoxes: [MediaBox] {
        get { profile().mediaBoxes }
        set { mutateProfile { $0.mediaBoxes = newValue } }
    }

    @discardableResult
    func addMediaBox(url: URL, in key: String? = nil) -> MediaBox? {
        guard let bookmark = Self.makeBookmark(for: url) else { return nil }

        var box = MediaBox()
        box.fileName = url.lastPathComponent
        box.bookmarkData = bookmark
        box.mediaTypeRaw = Self.mediaType(forExtension: url.pathExtension)
        let offset = Double(profile(key).mediaBoxes.count % 4) * 0.04
        box.frame = TextBoxFrame(x: 0.74 - offset, y: 0.05 + offset, width: 0.20, height: 0.18).clamped()
        let snapshot = box
        mutateProfile(key) { $0.mediaBoxes.append(snapshot) }
        return box
    }

    func removeMediaBox(id: UUID, in key: String? = nil) {
        mutateProfile(key) { $0.mediaBoxes.removeAll { $0.id == id } }
    }

    func mediaBox(id: UUID, in key: String? = nil) -> MediaBox? {
        readBox(Self.mediaToken(id), in: key) { $0.mediaBoxes.first { $0.id == id } }
    }

    func updateMediaBox(_ box: MediaBox, in key: String? = nil) {
        mutateBox(Self.mediaToken(box.id), in: key) { p in
            guard let idx = p.mediaBoxes.firstIndex(where: { $0.id == box.id }) else { return }
            var clamped = box
            clamped.frame = box.frame.clamped()
            p.mediaBoxes[idx] = clamped
        }
    }

    // MARK: - Resolution-Adaptive Font Scaling
    /// All font sizes are authored against a 1080-point-tall reference screen and
    /// scaled by the actual output height. Combined with the normalized box frames
    /// this makes the layout fully adaptive to resolution / aspect ratio / PPI.
    static let referenceScreenHeight: CGFloat = 1080

    static func fontScale(forHeight height: CGFloat) -> CGFloat {
        guard height > 0 else { return 1 }
        return height / referenceScreenHeight
    }

    /// Font scale for the currently targeted presentation screen.
    var targetFontScale: CGFloat {
        Self.fontScale(forHeight: targetScreenMetrics.points.height)
    }

    // MARK: - Box Frames (compat: ACTIVE profile)
    var verseBoxFrame: TextBoxFrame {
        get { boxFrame(for: .verseContent) }
        set { setBoxFrame(newValue, for: .verseContent) }
    }
    var refBoxFrame: TextBoxFrame {
        get { boxFrame(for: .reference) }
        set { setBoxFrame(newValue, for: .reference) }
    }
    var translationBoxFrame: TextBoxFrame {
        get { boxFrame(for: .translationName) }
        set { setBoxFrame(newValue, for: .translationName) }
    }
    var subtitleBoxFrame: TextBoxFrame {
        get { boxFrame(for: .subtitle) }
        set { setBoxFrame(newValue, for: .subtitle) }
    }

    // MARK: - Box Content Sources (stored in the profiles)

    /// Formats the date/time sources. Date formats: "" (long) | "short" | "weekday".
    /// Time formats: "" (HH:MM) | "hms" (HH:MM:SS).
    /// Configuration for a time-based casetă: which preset, which time zone, and
    /// for a countdown, what it counts towards.
    ///
    /// Encoded into the box's EXISTING `sourceFormat` slot rather than new fields
    /// on `LayoutProfile`. That slot exists precisely to configure a source, and it
    /// already flows through themes, export/import and undo — so a countdown
    /// survives all of that with no schema change. The encoding is
    /// `style|tz=<identifier>|target=<ISO8601>`, and unknown segments are ignored,
    /// so an older build reads a newer string as just its style. The target is
    /// second-precision — a countdown has no use for milliseconds — so a round
    /// trip drops any fraction.
    struct ClockOptions: Equatable {
        var style: String = ""
        var timeZoneID: String = ""
        var target: Date? = nil

        init(style: String = "", timeZoneID: String = "", target: Date? = nil) {
            self.style = style
            self.timeZoneID = timeZoneID
            self.target = target
        }

        init(raw: String) {
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            style = parts.first ?? ""
            for part in parts.dropFirst() {
                if part.hasPrefix("tz=") {
                    timeZoneID = String(part.dropFirst(3))
                } else if part.hasPrefix("target=") {
                    target = ISO8601DateFormatter().date(from: String(part.dropFirst(7)))
                }
            }
        }

        var raw: String {
            var out = [style]
            if !timeZoneID.isEmpty { out.append("tz=" + timeZoneID) }
            if let target { out.append("target=" + ISO8601DateFormatter().string(from: target)) }
            return out.joined(separator: "|")
        }

        var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
        /// True when the display changes every second rather than every minute.
        var needsSeconds: Bool { style == "hms" }
    }

    /// Renders a countdown/elapsed span. Always the same width family so the text
    /// does not jitter as digits change: h:mm:ss above an hour, m:ss below.
    static func formattedSpan(_ seconds: TimeInterval, style: String) -> String {
        let clamped = max(0, Int(seconds.rounded()))
        let h = clamped / 3600, m = (clamped % 3600) / 60, sec = clamped % 60
        switch style {
        case "mmss": return String(format: "%02d:%02d", h * 60 + m, sec)
        case "hm":   return String(format: "%d:%02d", h, m)
        default:     return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec)
                                  : String(format: "%d:%02d", m, sec)
        }
    }

    static func formattedClock(source: String, format: String, now: Date) -> String {
        let options = ClockOptions(raw: format)
        switch source {
        case "date":
            switch options.style {
            case "short":
                var s = Date.FormatStyle(date: .numeric, time: .omitted)
                s.timeZone = options.timeZone
                return now.formatted(s)
            case "weekday":
                var s = Date.FormatStyle().weekday(.wide).day().month(.wide).year()
                s.timeZone = options.timeZone
                return now.formatted(s)
            default:
                var s = Date.FormatStyle(date: .long, time: .omitted)
                s.timeZone = options.timeZone
                return now.formatted(s)
            }
        case "time":
            var s = Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
            if options.style == "hms" { s = s.second(.twoDigits) }
            s.timeZone = options.timeZone
            return now.formatted(s)
        case "countdown":
            // No target set yet: show zero rather than a stale or absurd number,
            // so an unconfigured box reads as "not started" instead of wrong.
            guard let target = options.target else { return formattedSpan(0, style: options.style) }
            return formattedSpan(target.timeIntervalSince(now), style: options.style)
        case "elapsed":
            guard let target = options.target else { return formattedSpan(0, style: options.style) }
            return formattedSpan(now.timeIntervalSince(target), style: options.style)
        default:
            return ""
        }
    }

    /// Shared source resolution for built-in sections and custom boxes.
    static func resolveBoxSource(
        _ raw: String, format: String = "", autoValue: String, staticText: String,
        main: String, reference: String, translation: String, subtitle: String,
        now: Date = .now, slideNumber: String = "",
        footnote: String = "", crossReference: String = "", heading: String = "",
        gloss: String = "", strongs: String = "",
        songAuthor: String = "", songCopyright: String = "", songCCLI: String = "",
        songbook: String = "", songStyle: String = "", songKey: String = "", songTempo: String = "",
        mediaURL: URL? = nil, mediaKind: String = ""
    ) -> String {
        switch raw {
        case "mainText": return main
        case "reference": return reference
        case "translation": return translation
        case "subtitle": return subtitle
        case "footnote": return footnote
        case "crossReference": return crossReference
        case "heading": return heading
        case "gloss": return gloss
        case "strongs": return strongs
        case "author": return songAuthor
        case "copyright": return songCopyright
        case "ccli": return songCCLI
        case "songbook": return songbook
        case "style": return songStyle
        case "songKey": return songKey
        case "songTempo": return songTempo
        case "static": return staticText
        case "date", "time", "countdown", "elapsed":
            return formattedClock(source: raw, format: format, now: now)
        case "slideNumber": return slideNumber
        case "mediaFile": return mediaURL?.lastPathComponent ?? ""
        case "mediaName": return mediaURL?.deletingPathExtension().lastPathComponent ?? ""
        case "mediaExtension": return mediaURL?.pathExtension.uppercased() ?? ""
        case "mediaKind": return mediaKindLabel(mediaKind)
        default: return autoValue // "auto"
        }
    }

    /// The source choices a presenter offers, with PER-PRESENTER labels —
    /// Songs pull from lyrics/title/strofă, Slides from content/title, etc.
    static func sourceOptions(for key: String) -> [(raw: String, label: String)] {
        var live: [(String, String)]
        switch key {
        case "song":
            live = [
                ("mainText", String(localized: "Versuri (live)", comment: "Box source")),
                ("reference", String(localized: "Titlu cântec (live)", comment: "Box source")),
                ("subtitle", String(localized: "Etichetă strofă (live)", comment: "Box source")),
                ("author", String(localized: "Autor (live)", comment: "Box source")),
                ("copyright", String(localized: "Copyright (live)", comment: "Box source")),
                ("ccli", String(localized: "Număr CCLI (live)", comment: "Box source")),
                ("songbook", String(localized: "Carte de cântări (live)", comment: "Box source")),
                ("style", String(localized: "Stil (live)", comment: "Box source")),
                ("songKey", String(localized: "Tonalitate (live)", comment: "Box source")),
                ("songTempo", String(localized: "Tempo (live)", comment: "Box source")),
            ]
        case "text":
            live = [
                ("mainText", String(localized: "Conținut slide (live)", comment: "Box source")),
                ("reference", String(localized: "Titlu slide (live)", comment: "Box source")),
            ]
        case "media":
            // Media used to fall through to `default` and offer the Bible's whole
            // list — verse text, Strong's numbers, cross-references — none of which
            // a media caption can ever resolve.
            live = [
                ("mediaFile", String(localized: "Nume fișier (live)", comment: "Box source — media")),
                ("mediaName", String(localized: "Nume fără extensie (live)", comment: "Box source — media")),
                ("mediaKind", String(localized: "Tip media (live)", comment: "Box source — media")),
                ("mediaExtension", String(localized: "Extensie fișier (live)", comment: "Box source — media")),
            ]
        default:
            live = [
                ("mainText", String(localized: "Text verset (live)", comment: "Box source")),
                ("reference", String(localized: "Referință (live)", comment: "Box source")),
                ("translation", String(localized: "Traducere (live)", comment: "Box source")),
                ("subtitle", String(localized: "Subtitlu (live)", comment: "Box source")),
                ("heading", String(localized: "Titlu secțiune (live)", comment: "Box source")),
                ("footnote", String(localized: "Notă de subsol (live)", comment: "Box source")),
                ("crossReference", String(localized: "Referințe încrucișate (live)", comment: "Box source")),
                ("gloss", String(localized: "Glosă interliniară (live)", comment: "Box source")),
                ("strongs", String(localized: "Numere Strong (live)", comment: "Box source")),
            ]
        }
        return live + [
            ("static", String(localized: "Text static", comment: "Box source")),
            ("date", String(localized: "Data curentă", comment: "Box source")),
            ("time", String(localized: "Ora curentă", comment: "Box source")),
            ("slideNumber", String(localized: "Număr slide (2 / 7)", comment: "Box source")),
            ("countdown", String(localized: "Cronometru invers", comment: "Box source")),
            ("elapsed", String(localized: "Timp scurs", comment: "Box source")),
        ]
    }

    static func mediaKindLabel(_ raw: String) -> String {
        switch raw {
        case "image": return String(localized: "Imagine", comment: "Media kind")
        case "gif": return String(localized: "GIF", comment: "Media kind")
        case "video": return String(localized: "Video", comment: "Media kind")
        default: return ""
        }
    }

    static func sourceOptionLabel(_ raw: String, for key: String = "bible") -> String {
        if raw == "auto" { return String(localized: "Implicit (auto)", comment: "Box source") }
        return sourceOptions(for: key).first { $0.raw == raw }?.label
            ?? String(localized: "Implicit (auto)", comment: "Box source")
    }

    /// How often the output needs to re-render for live clocks:
    /// nil = no clock boxes, 60 = minute precision, 1 = seconds shown.
    var clockTickInterval: TimeInterval? {
        let key = outputProfileKey
        var interval: TimeInterval? = nil
        func consider(source: String, format: String) {
            let options = ClockOptions(raw: format)
            switch source {
            case "countdown", "elapsed":
                // A span that shows seconds has to tick every second; one that
                // stops at minutes does not, and asking for 1 s there would wake
                // the whole output sixty times a minute for nothing.
                if options.style == "hm" { if interval == nil { interval = 60 } }
                else { interval = 1 }
            case "time":
                if options.needsSeconds { interval = 1 }
                else if interval == nil { interval = 60 }
            case "date":
                if interval == nil { interval = 60 }
            default:
                break
            }
        }
        for section in Self.relevantSections(for: key) where isSectionVisible(section, in: key) {
            consider(source: sourceRaw(for: section, in: key), format: sourceFormat(for: section, in: key))
        }
        for box in profile(key).customTextBoxes where box.isVisible {
            consider(source: box.sourceRaw, format: box.sourceFormatRaw)
        }
        return interval
    }

    // MARK: - Per-Section Visibility (compat: ACTIVE profile)
    var verseBoxVisible: Bool {
        get { isSectionVisible(.verseContent) }
        set { setSectionVisible(newValue, for: .verseContent) }
    }
    var refBoxVisible: Bool {
        get { isSectionVisible(.reference) }
        set { setSectionVisible(newValue, for: .reference) }
    }
    var translationBoxVisible: Bool {
        get { isSectionVisible(.translationName) }
        set { setSectionVisible(newValue, for: .translationName) }
    }
    var subtitleBoxVisible: Bool {
        get { isSectionVisible(.subtitle) }
        set { setSectionVisible(newValue, for: .subtitle) }
    }

    /// Maps a horizontal TextAlignment + vertical raw value to a frame Alignment.
    static func boxAlignment(horizontal: TextAlignment, verticalRaw: String) -> Alignment {
        let h: HorizontalAlignment = switch horizontal {
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
        let v: VerticalAlignment = switch verticalRaw {
        case "top": .top
        case "bottom": .bottom
        default: .center
        }
        return Alignment(horizontal: h, vertical: v)
    }

    // MARK: - Unified Z-Order
    /// ONE stacking order for every box — built-in sections, custom text boxes,
    /// and media boxes. Tokens: "section:<raw>" / "custom:<uuid>" / "media:<uuid>".
    /// Earlier in the list = further back; the last token renders on top.
    // Compat: ACTIVE profile stacking order
    var boxOrder: [String] {
        get { profile().boxOrder }
        set { mutateProfile { $0.boxOrder = newValue } }
    }

    // The z-order token for each kind of box. Also the observation key a box's
    // narrow reads and writes are filed under, so the two can never drift apart.
    static func sectionToken(_ section: TextBoxSection) -> String { "section:" + section.rawValue }
    static func customToken(_ id: UUID) -> String { "custom:" + id.uuidString }
    static func mediaToken(_ id: UUID) -> String { "media:" + id.uuidString }

    /// All valid tokens for a profile's boxes, in canonical default order
    /// (media at the back, then the RELEVANT sections, then custom boxes).
    private func canonicalTokens(in key: String?) -> [String] {
        let k = resolvedKey(key)
        return readStructure(in: k) { p in
            let removed = Set(p.removedSections)
            return p.mediaBoxes.map { Self.mediaToken($0.id) }
                + Self.relevantSections(for: k)
                    .filter { !removed.contains($0.rawValue) }
                    .map { Self.sectionToken($0) }
                + p.customTextBoxes.map { Self.customToken($0.id) }
        }
    }

    /// The reconciled render order: stored order minus stale tokens, plus any
    /// new boxes appended on top. Pure — never mutates state (safe in view body).
    func orderedBoxTokens(in key: String? = nil) -> [String] {
        let valid = Set(canonicalTokens(in: key))
        var result = readStructure(in: key) { $0.boxOrder }.filter { valid.contains($0) }
        let present = Set(result)
        for token in canonicalTokens(in: key) where !present.contains(token) {
            result.append(token)
        }
        return result
    }

    func moveBoxToken(_ token: String, offset: Int, in key: String? = nil) {
        let ordered = orderedBoxTokens(in: key)
        guard let idx = ordered.firstIndex(of: token) else { return }
        let newIdx = min(max(idx + offset, 0), ordered.count - 1)
        guard newIdx != idx else { return }
        var next = ordered
        next.remove(at: idx)
        next.insert(token, at: newIdx)
        mutateProfile(key) { $0.boxOrder = next }
    }

    func moveBoxTokenToEdge(_ token: String, front: Bool, in key: String? = nil) {
        var ordered = orderedBoxTokens(in: key)
        guard let idx = ordered.firstIndex(of: token) else { return }
        ordered.remove(at: idx)
        if front { ordered.append(token) } else { ordered.insert(token, at: 0) }
        let next = ordered
        mutateProfile(key) { $0.boxOrder = next }
    }

    /// Places `token` directly ABOVE `target` in the stacking order
    /// (list drops: the dragged row takes the visual slot above the target).
    func reorderBoxToken(_ token: String, above target: String, in key: String? = nil) {
        guard token != target else { return }
        var ordered = orderedBoxTokens(in: key)
        guard let from = ordered.firstIndex(of: token) else { return }
        ordered.remove(at: from)
        let to = ordered.firstIndex(of: target).map { $0 + 1 } ?? ordered.count
        ordered.insert(token, at: to)
        let next = ordered
        mutateProfile(key) { $0.boxOrder = next }
    }

    /// Whether this presenter routes the module's media through a casetă.
    ///
    /// The output's hard-coded full-screen layers defer to it, so both never draw
    /// at once — and a profile saved before the casetă existed still renders
    /// through the old path instead of going blank.
    func hasLiveMediaBox(in key: String? = nil) -> Bool {
        readStructure(in: key) { p in
            p.mediaBoxes.contains { $0.sourceRaw == "live" && $0.isVisible }
        }
    }

    // MARK: - Removing and restoring built-in sections

    /// Deletes a built-in section from this presenter.
    ///
    /// Built-ins used to only ever hide — the trash on them was a lie. They are
    /// deletable now because they are recoverable: `restorableSections(in:)` feeds
    /// the add menu, and the section's frame, style and source survive, so bringing
    /// it back restores the layout instead of resetting it.
    func removeSection(_ section: TextBoxSection, in key: String? = nil) {
        mutateProfile(key) { p in
            guard !p.removedSections.contains(section.rawValue) else { return }
            p.removedSections.append(section.rawValue)
        }
    }

    func restoreSection(_ section: TextBoxSection, in key: String? = nil) {
        mutateProfile(key) { p in
            p.removedSections.removeAll { $0 == section.rawValue }
            // Back visible, or it would return as an invisible row and look broken.
            p.visibility[section.rawValue] = true
        }
    }

    /// Sections this presenter offers that have been deleted — what the add menu
    /// lists. Ordered as the presenter declares them, not as they were removed.
    func restorableSections(in key: String? = nil) -> [TextBoxSection] {
        let k = resolvedKey(key)
        return readStructure(in: k) { p in
            let removed = Set(p.removedSections)
            return Self.relevantSections(for: k).filter { removed.contains($0.rawValue) }
        }
    }

    func isSectionRemoved(_ section: TextBoxSection, in key: String? = nil) -> Bool {
        readStructure(in: key) { $0.removedSections.contains(section.rawValue) }
    }

    // MARK: - Edit Mode
    /// Shows the fixed text box overlays (drag to move, handles to resize) in the preview.
    var isEditMode: Bool = false

    // MARK: - Themes
    /// A theme is a named snapshot of the entire look: boxes, styles, sources,
    /// backgrounds (global + per-content), custom text boxes, and media boxes.
    struct Theme: Identifiable, Codable, Equatable {
        var id: UUID = UUID()
        var name: String
        /// Which presenter this theme is designed for:
        /// "all" | "bible" | "song" | "text" — galleries filter on this.
        var formatRaw: String = "all"
        var payload: ThemePayload

        init(id: UUID = UUID(), name: String, formatRaw: String = "all", payload: ThemePayload) {
            self.id = id
            self.name = name
            self.formatRaw = formatRaw
            self.payload = payload
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? PresentationDefaults.themeName
            formatRaw = try c.decodeIfPresent(String.self, forKey: .formatRaw) ?? "all"
            payload = try c.decodeIfPresent(ThemePayload.self, forKey: .payload) ?? ThemePayload()
        }

        static func formatLabel(_ raw: String) -> String {
            switch raw {
            case "bible": return String(localized: "Biblie", comment: "Theme format")
            case "song": return String(localized: "Cântece", comment: "Theme format")
            case "text": return String(localized: "Slide-uri proprii", comment: "Theme format — the Custom Slides profile")
            case "media": return String(localized: "Media", comment: "Theme format")
            default: return String(localized: "Toate", comment: "Theme format")
            }
        }
    }

    /// A full-look snapshot. Every field has a default and decoding is
    /// resilient (decodeIfPresent) so stored themes, undo snapshots, and
    /// imported .tptheme files survive future model growth.
    struct ThemePayload: Codable, Equatable {
        // Global text
        var fontSize: Double = PresentationDefaults.fontSize
        var fontName: String = PresentationDefaults.fontName
        var textColorHex: String = PresentationDefaults.textColor
        var textAlignmentRaw: String = "center"
        var lineSpacing: Double = PresentationDefaults.lineSpacing
        var padding: Double = PresentationDefaults.padding
        var shadowEnabled: Bool = true
        var shadowRadius: Double = PresentationDefaults.shadowRadius
        var shadowColorHex: String = PresentationDefaults.shadowColor
        var letterTracking: Double = 0
        var wocStyleEnabled: Bool = true
        var wocColorHex: String = PresentationDefaults.wocColor
        var autoFitVerseFont: Bool = false
        var globalWeightRaw: String = "regular"
        var globalVAlignRaw: String = "center"
        var globalTextOpacity: Double = 1.0
        // Global background
        var backgroundEnabled: Bool = false
        var backgroundStaysOnHide: Bool = true
        var backgroundColorHex: String = PresentationDefaults.backgroundColor
        var backgroundOpacity: Double = PresentationDefaults.backgroundOpacity
        var useBackgroundImage: Bool = false
        var backgroundImageBookmark: Data? = nil
        var backgroundMediaTypeRaw: String = "image"
        /// All presenter layouts (bible/song/text) — the whole look travels.
        var profiles: [String: LayoutProfile] = [:]

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? PresentationDefaults.fontSize
            fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? PresentationDefaults.fontName
            textColorHex = try c.decodeIfPresent(String.self, forKey: .textColorHex) ?? PresentationDefaults.textColor
            textAlignmentRaw = try c.decodeIfPresent(String.self, forKey: .textAlignmentRaw) ?? "center"
            lineSpacing = try c.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? PresentationDefaults.lineSpacing
            padding = try c.decodeIfPresent(Double.self, forKey: .padding) ?? PresentationDefaults.padding
            shadowEnabled = try c.decodeIfPresent(Bool.self, forKey: .shadowEnabled) ?? true
            shadowRadius = try c.decodeIfPresent(Double.self, forKey: .shadowRadius) ?? PresentationDefaults.shadowRadius
            shadowColorHex = try c.decodeIfPresent(String.self, forKey: .shadowColorHex) ?? PresentationDefaults.shadowColor
            letterTracking = try c.decodeIfPresent(Double.self, forKey: .letterTracking) ?? 0
            wocStyleEnabled = try c.decodeIfPresent(Bool.self, forKey: .wocStyleEnabled) ?? true
            wocColorHex = try c.decodeIfPresent(String.self, forKey: .wocColorHex) ?? PresentationDefaults.wocColor
            autoFitVerseFont = try c.decodeIfPresent(Bool.self, forKey: .autoFitVerseFont) ?? false
            globalWeightRaw = try c.decodeIfPresent(String.self, forKey: .globalWeightRaw) ?? "regular"
            globalVAlignRaw = try c.decodeIfPresent(String.self, forKey: .globalVAlignRaw) ?? "center"
            globalTextOpacity = try c.decodeIfPresent(Double.self, forKey: .globalTextOpacity) ?? 1.0
            backgroundEnabled = try c.decodeIfPresent(Bool.self, forKey: .backgroundEnabled) ?? false
            backgroundStaysOnHide = try c.decodeIfPresent(Bool.self, forKey: .backgroundStaysOnHide) ?? true
            backgroundColorHex = try c.decodeIfPresent(String.self, forKey: .backgroundColorHex) ?? PresentationDefaults.backgroundColor
            backgroundOpacity = try c.decodeIfPresent(Double.self, forKey: .backgroundOpacity) ?? PresentationDefaults.backgroundOpacity
            useBackgroundImage = try c.decodeIfPresent(Bool.self, forKey: .useBackgroundImage) ?? false
            backgroundImageBookmark = try c.decodeIfPresent(Data.self, forKey: .backgroundImageBookmark)
            backgroundMediaTypeRaw = try c.decodeIfPresent(String.self, forKey: .backgroundMediaTypeRaw) ?? "image"
            profiles = try c.decodeIfPresent([String: LayoutProfile].self, forKey: .profiles) ?? [:]
            if profiles.isEmpty {
                // Legacy (pre-profiles) payloads stored ONE flat layout shared
                // by every presenter — rebuild it as per-presenter profiles.
                let l = try decoder.container(keyedBy: LegacyKeys.self)
                var base = LayoutProfile()
                base.frames = try l.decodeIfPresent([String: TextBoxFrame].self, forKey: .frames) ?? [:]
                base.visibility = try l.decodeIfPresent([String: Bool].self, forKey: .visibility) ?? [:]
                base.styles = try l.decodeIfPresent([String: BoxTextStyle].self, forKey: .styles) ?? [:]
                base.sources = try l.decodeIfPresent([String: String].self, forKey: .sources) ?? [:]
                base.sourceFormats = try l.decodeIfPresent([String: String].self, forKey: .sourceFormats) ?? [:]
                base.staticTexts = try l.decodeIfPresent([String: String].self, forKey: .staticTexts) ?? [:]
                base.customTextBoxes = try l.decodeIfPresent([CustomTextBox].self, forKey: .customTextBoxes) ?? []
                base.mediaBoxes = try l.decodeIfPresent([MediaBox].self, forKey: .mediaBoxes) ?? []
                base.boxOrder = try l.decodeIfPresent([String].self, forKey: .boxOrder) ?? []
                let backgrounds = try l.decodeIfPresent([String: BackgroundConfig].self, forKey: .contentBackgrounds) ?? [:]
                let contentOptions = try l.decodeIfPresent([String: ContentOptions].self, forKey: .contentOptions) ?? [:]
                if base != LayoutProfile() || !backgrounds.isEmpty || !contentOptions.isEmpty {
                    for key in PresentationManager.profileKeys {
                        var prof = base
                        if prof.visibility.isEmpty {
                            prof.visibility = LayoutProfile.defaultProfile(for: key).visibility
                        }
                        prof.background = backgrounds[key] ?? BackgroundConfig()
                        prof.options = contentOptions[key] ?? ContentOptions()
                        profiles[key] = prof
                    }
                }
            }
        }

        private enum LegacyKeys: String, CodingKey {
            case frames, visibility, styles, sources, sourceFormats, staticTexts
            case customTextBoxes, mediaBoxes, boxOrder, contentBackgrounds, contentOptions
        }
    }

    var themes: [Theme] {
        didSet {
            if let data = try? JSONEncoder().encode(themes) {
                defaults.set(data, forKey: "pm_themes")
            }
        }
    }
    var activeThemeID: UUID? {
        didSet { defaults.set(activeThemeID?.uuidString ?? "", forKey: "pm_activeThemeID") }
    }

    // MARK: - Per-presenter themes
    //
    // Off by default, so nothing changes for anyone who does not ask for it: one
    // theme dresses every presenter, exactly as before. On, each presenter resolves
    // its own, and anything unassigned still falls back to `activeThemeID` — so
    // turning the switch on is never a cliff.

    var usesPerPresenterThemes: Bool {
        didSet { defaults.set(usesPerPresenterThemes, forKey: "pm_usesPerPresenterThemes") }
    }

    /// Profile key → theme id. Only consulted while `usesPerPresenterThemes`.
    var themeAssignments: [String: UUID] {
        didSet {
            let raw = themeAssignments.mapValues(\.uuidString)
            if let data = try? JSONEncoder().encode(raw) {
                defaults.set(data, forKey: "pm_themeAssignments")
            }
        }
    }

    /// Which theme dresses `key` right now. The assignment wins, then the global
    /// one — a presenter is never themeless just because it has no assignment.
    func resolvedThemeID(for key: String? = nil) -> UUID? {
        let k = resolvedKey(key)
        guard usesPerPresenterThemes else { return activeThemeID }
        return themeAssignments[k] ?? activeThemeID
    }

    /// Presenters currently pinned to this theme. Non-empty means deletion is
    /// refused — the operator gets told who is using it instead of silently
    /// losing a presenter's look.
    func presentersUsing(themeID: UUID) -> [String] {
        themeAssignments.filter { $0.value == themeID }.keys.sorted()
    }

    /// Applies just ONE presenter's profile out of a theme, leaving the other three
    /// and the global text settings alone. This is what makes a mixed look possible:
    /// Bible from one theme, Songs from another.
    func applyTheme(id: UUID, toProfileOnly key: String) {
        endThemeHoverPreview()
        guard let theme = themes.first(where: { $0.id == id }) else { return }
        let k = resolvedKey(key)
        // A theme that never carried this presenter would blank it; leave it be.
        guard let incoming = theme.payload.profiles[k] else { return }
        registerLayoutUndo()
        profiles[k] = incoming
        invalidateAllProfiles()
        themeAssignments[k] = id
        loadContentBackgroundImages()
    }

    /// Builds ONE new theme out of several: Bible's look from Galaxie, Songs' from
    /// Default, and so on.
    ///
    /// The result is a plain `Theme` — a full-fledged one. It COPIES the chosen
    /// profiles rather than referencing them, so editing Galaxie afterwards leaves
    /// this theme alone, and it exports, imports, applies and deletes like any
    /// other. There is no separate "pack" entity and no second file extension:
    /// a combination IS a theme, saved as `.tptheme`.
    ///
    /// `picks` maps profile key → source theme. Keys left out take the CURRENT
    /// look for that presenter, so combining two presenters does not silently
    /// reset the other two.
    ///
    /// The payload-level globals (base font, size, shadow, tracking…) are shared by
    /// every presenter, so they can only come from one place: the `base` theme, or
    /// the first pick in `profileKeys` order. It matters visually — a box whose
    /// style is not customised inherits them — so it is explicit rather than
    /// whichever dictionary key happened to come first.
    @discardableResult
    func combineThemes(picks: [String: UUID], base: UUID? = nil, name: String? = nil) -> Theme? {
        let resolvedPicks = picks.filter { Self.profileKeys.contains($0.key) }
        guard !resolvedPicks.isEmpty else { return nil }

        let baseID = base
            ?? Self.profileKeys.compactMap { resolvedPicks[$0] }.first
        guard let baseID,
              let baseTheme = themes.first(where: { $0.id == baseID }) else { return nil }

        // Start from the base theme so the globals are its own, then swap in each
        // chosen presenter's profile.
        var payload = baseTheme.payload
        var sourceNames: [String] = []
        for key in Self.profileKeys {
            guard let sourceID = resolvedPicks[key] else {
                // Not chosen: keep what this presenter looks like right now.
                payload.profiles[key] = profile(key)
                continue
            }
            guard let source = themes.first(where: { $0.id == sourceID }) else { continue }
            payload.profiles[key] = source.payload.profiles[key] ?? .defaultProfile(for: key)
            if !sourceNames.contains(source.name) { sourceNames.append(source.name) }
        }

        let combined = Theme(
            name: uniqueThemeName(name ?? Self.combinedThemeName(from: sourceNames)),
            formatRaw: "all",
            payload: payload
        )
        themes.append(combined)
        return combined
    }

    /// "Galaxie + Default". One source means it is a copy, not a combination.
    static func combinedThemeName(from sources: [String]) -> String {
        switch sources.count {
        case 0: return String(localized: "Temă combinată", comment: "Default name for a combined theme")
        case 1: return sources[0] + " " + String(localized: "(copie)", comment: "Combined theme name — single source")
        default: return sources.joined(separator: " + ")
        }
    }

    /// Keeps names distinct without refusing the operation — a clashing name would
    /// otherwise leave two indistinguishable cards in the gallery.
    func uniqueThemeName(_ desired: String) -> String {
        let existing = Set(themes.map(\.name))
        guard existing.contains(desired) else { return desired }
        var n = 2
        while existing.contains("\(desired) \(n)") { n += 1 }
        return "\(desired) \(n)"
    }

    /// Clears a presenter's pin, sending it back to the global theme.
    func clearThemeAssignment(for key: String? = nil) {
        themeAssignments[resolvedKey(key)] = nil
    }

    /// Captures the entire current look into a payload.
    private func captureThemePayload() -> ThemePayload {
        var p = ThemePayload()
        p.fontSize = fontSize
        p.fontName = fontName
        p.textColorHex = textColorHex
        p.textAlignmentRaw = Self.alignmentRaw(textAlignment)
        p.lineSpacing = lineSpacing
        p.padding = padding
        p.shadowEnabled = shadowEnabled
        p.shadowRadius = shadowRadius
        p.shadowColorHex = shadowColorHex
        p.letterTracking = letterTracking
        p.wocStyleEnabled = wocStyleEnabled
        p.wocColorHex = wocColorHex
        p.autoFitVerseFont = autoFitVerseFont
        p.globalWeightRaw = globalWeightRaw
        p.globalVAlignRaw = globalVAlignRaw
        p.globalTextOpacity = globalTextOpacity
        p.backgroundEnabled = backgroundEnabled
        p.backgroundColorHex = backgroundColorHex
        p.backgroundOpacity = backgroundOpacity
        p.useBackgroundImage = useBackgroundImage
        p.backgroundImageBookmark = defaults.data(forKey: Self.backgroundBookmarkKey)
        p.backgroundMediaTypeRaw = backgroundMediaTypeRaw
        p.backgroundStaysOnHide = backgroundStaysOnHide
        p.profiles = profiles
        return p
    }

    /// Saves the current look, keeping only ONE presenter's profile.
    ///
    /// In per-presenter mode the four presenters may be wearing four different
    /// themes, so "save the current look" is ambiguous: a full snapshot would
    /// bottle the mix, which is rarely what someone editing one presenter means.
    /// The other three are simply absent, and import fills them from THEIR
    /// defaults (the 2b rule) rather than from whatever this operator happened to
    /// have on screen.
    @discardableResult
    func saveCurrentAsTheme(named name: String, onlyProfile key: String) -> Theme {
        let theme = saveCurrentAsTheme(named: name)
        guard let idx = themes.firstIndex(where: { $0.id == theme.id }) else { return theme }
        let k = resolvedKey(key)
        themes[idx].payload.profiles = [k: themes[idx].payload.profiles[k] ?? profile(k)]
        themes[idx].formatRaw = k
        return themes[idx]
    }

    @discardableResult
    func saveCurrentAsTheme(named name: String, formatRaw: String = "all") -> Theme {
        let theme = Theme(name: name, formatRaw: formatRaw, payload: captureThemePayload())
        themes.append(theme)
        activeThemeID = theme.id
        return theme
    }

    func setThemeFormat(id: UUID, formatRaw: String) {
        guard let idx = themes.firstIndex(where: { $0.id == id }) else { return }
        themes[idx].formatRaw = formatRaw
    }

    /// Themes relevant to a presenter format: its own + universal ("all").
    func themes(forFormat format: String?) -> [Theme] {
        guard let format else { return themes }
        return themes.filter { $0.formatRaw == "all" || $0.formatRaw == format }
    }

    /// Overwrites a theme with the current look.
    func updateTheme(id: UUID) {
        guard let idx = themes.firstIndex(where: { $0.id == id }) else { return }
        themes[idx].payload = captureThemePayload()
    }

    func renameTheme(id: UUID, to name: String) {
        guard let idx = themes.firstIndex(where: { $0.id == id }) else { return }
        themes[idx].name = name
    }

    /// Refuses when a presenter is pinned to this theme, and says which — deleting
    /// it would strip that presenter's look with no way to tell what happened.
    /// Returns the blocking presenters; empty means it was deleted.
    @discardableResult
    func deleteTheme(id: UUID) -> [String] {
        let blockers = presentersUsing(themeID: id)
        guard blockers.isEmpty else { return blockers }
        themes.removeAll { $0.id == id }
        if activeThemeID == id { activeThemeID = nil }
        return []
    }

    func applyTheme(id: UUID) {
        // Per-presenter mode: a click in the gallery dresses the presenter you are
        // editing and nobody else. Applying to all four is what unified mode is for,
        // and doing it here would quietly undo a carefully mixed look.
        if usesPerPresenterThemes {
            applyTheme(id: id, toProfileOnly: activeProfileKey)
            return
        }
        // A hover preview may be showing — fall back to the REAL look first so
        // the undo snapshot captures the true previous state.
        endThemeHoverPreview()
        guard let theme = themes.first(where: { $0.id == id }) else { return }
        registerLayoutUndo()
        applyPayload(theme.payload)
        activeThemeID = id
    }

    // MARK: - Theme Hover Preview
    // Resting the cursor on a theme card temporarily shows that theme in the
    // operator preview; moving away restores the real look. Never while LIVE —
    // the projector must not flicker — and never registers undo.
    @ObservationIgnored private var hoverPreviewSnapshot: ThemePayload?

    var isHoverPreviewingTheme: Bool { hoverPreviewSnapshot != nil }

    func beginThemeHoverPreview(id: UUID) {
        guard !liveContent.isLive,
              let theme = themes.first(where: { $0.id == id }) else { return }
        if hoverPreviewSnapshot == nil {
            hoverPreviewSnapshot = captureThemePayload()
        }
        applyPayload(theme.payload)
    }

    func endThemeHoverPreview() {
        guard let snapshot = hoverPreviewSnapshot else { return }
        hoverPreviewSnapshot = nil
        applyPayload(snapshot)
    }

    // MARK: - Theme Import / Export (.tptheme packages)
    // A .tptheme is a directory package: theme.json (ThemeArchive) + media/
    // with every referenced file embedded — themes travel between machines
    // with ALL their features. Import copies media into the app container,
    // so themes keep working even if the original package is deleted.

    /// One media asset inside a theme package. `slot` says where it plugs in:
    /// "background" | "contentBackground:<key>" | "mediaBox:<uuid>".
    struct ThemeAssetRef: Codable, Equatable {
        var slot: String
        var file: String
        var mediaType: String = "image"

        init(slot: String, file: String, mediaType: String) {
            self.slot = slot
            self.file = file
            self.mediaType = mediaType
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            slot = try c.decodeIfPresent(String.self, forKey: .slot) ?? ""
            file = try c.decodeIfPresent(String.self, forKey: .file) ?? ""
            mediaType = try c.decodeIfPresent(String.self, forKey: .mediaType) ?? "image"
        }
    }

    /// The portable theme file format (versioned for future evolution).
    struct ThemeArchive: Codable {
        var version: Int = 1
        var name: String = PresentationDefaults.themeName
        var format: String = "all"
        var payload: ThemePayload = ThemePayload()
        var assets: [ThemeAssetRef] = []

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? PresentationDefaults.themeName
            format = try c.decodeIfPresent(String.self, forKey: .format) ?? "all"
            payload = try c.decodeIfPresent(ThemePayload.self, forKey: .payload) ?? ThemePayload()
            assets = try c.decodeIfPresent([ThemeAssetRef].self, forKey: .assets) ?? []
        }
    }

    enum ThemeIOError: LocalizedError {
        case themeNotFound
        case invalidPackage

        var errorDescription: String? {
            switch self {
            case .themeNotFound:
                return String(localized: "Tema nu a fost găsită.", comment: "Theme IO error")
            case .invalidPackage:
                return String(localized: "Pachetul de temă este invalid (lipsește theme.json).", comment: "Theme IO error")
            }
        }
    }

    /// Exports a theme as a .tptheme package at `packageURL` (a directory).
    func exportTheme(id: UUID, to packageURL: URL) throws {
        guard let theme = themes.first(where: { $0.id == id }) else {
            throw ThemeIOError.themeNotFound
        }
        let fm = FileManager.default
        try? fm.removeItem(at: packageURL)
        let mediaDir = packageURL.appendingPathComponent("media", isDirectory: true)
        try fm.createDirectory(at: mediaDir, withIntermediateDirectories: true)

        var archive = ThemeArchive()
        archive.name = theme.name
        archive.format = theme.formatRaw
        var payload = theme.payload
        var assets: [ThemeAssetRef] = []
        var usedNames = Set<String>()

        func copyAsset(bookmark: Data?, slot: String, mediaType: String, preferredName: String) -> Bool {
            guard let bookmark else { return false }
            // One-shot copy: release the scope afterwards. The long-lived
            // resolveBookmark keeps its scope open for continuously rendering
            // media, which here would leak one open scope per exported asset.
            let copied = Self.withScopedBookmark(bookmark) { url -> Bool in
                var name = preferredName.isEmpty ? url.lastPathComponent : preferredName
                // Avoid duplicate file names inside the package
                var candidate = name
                var counter = 2
                while usedNames.contains(candidate) {
                    candidate = "\(counter)-\(name)"
                    counter += 1
                }
                name = candidate
                usedNames.insert(name)
                do {
                    try fm.copyItem(at: url, to: mediaDir.appendingPathComponent(name))
                } catch {
                    return false
                }
                assets.append(ThemeAssetRef(slot: slot, file: name, mediaType: mediaType))
                return true
            }
            return copied ?? false
        }

        // Global background
        if copyAsset(
            bookmark: payload.backgroundImageBookmark,
            slot: "background",
            mediaType: payload.backgroundMediaTypeRaw,
            preferredName: ""
        ) {
            payload.backgroundImageBookmark = nil
        }
        // Per-profile backgrounds + media boxes
        for (key, var prof) in payload.profiles {
            if copyAsset(
                bookmark: prof.background.imageBookmark,
                slot: "profileBackground:\(key)",
                mediaType: prof.background.mediaTypeRaw,
                preferredName: prof.background.imageName
            ) {
                prof.background.imageBookmark = nil
            }
            for idx in prof.mediaBoxes.indices {
                let box = prof.mediaBoxes[idx]
                if copyAsset(
                    bookmark: box.bookmarkData,
                    slot: "mediaBox:\(key):\(box.id.uuidString)",
                    mediaType: box.mediaTypeRaw,
                    preferredName: box.fileName
                ) {
                    prof.mediaBoxes[idx].bookmarkData = nil
                }
            }
            payload.profiles[key] = prof
        }

        archive.payload = payload
        archive.assets = assets

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        try data.write(to: packageURL.appendingPathComponent("theme.json"))
    }

    /// Assets the LAST `importTheme` could not copy — the caller reports them.
    /// Reset at the start of each import.
    var lastThemeImportSkippedAssets: [String] = []

    /// Imports a .tptheme package: media files are copied into the app
    /// container and re-bookmarked, then the theme is added to the library.
    @discardableResult
    func importTheme(from packageURL: URL) throws -> Theme {
        lastThemeImportSkippedAssets = []
        let accessing = packageURL.startAccessingSecurityScopedResource()
        defer { if accessing { packageURL.stopAccessingSecurityScopedResource() } }

        let jsonURL = packageURL.appendingPathComponent("theme.json")
        guard let data = try? Data(contentsOf: jsonURL) else {
            throw ThemeIOError.invalidPackage
        }
        let archive = try JSONDecoder().decode(ThemeArchive.self, from: data)

        let themeID = UUID()
        let fm = FileManager.default
        let containerDir = Self.themeMediaDirectory(for: themeID)
        try fm.createDirectory(at: containerDir, withIntermediateDirectories: true)

        var payload = archive.payload
        // A theme that only carries some presenters fills the rest from THEIR
        // defaults rather than leaving them absent — an absent profile reads as
        // "nothing configured" everywhere downstream and would blank that
        // presenter the moment the theme was applied.
        for key in Self.profileKeys where payload.profiles[key] == nil {
            payload.profiles[key] = .defaultProfile(for: key)
        }
        let packageMedia = packageURL.appendingPathComponent("media", isDirectory: true)

        for asset in archive.assets {
            let source = packageMedia.appendingPathComponent(asset.file)
            let destination = containerDir.appendingPathComponent(asset.file)
            guard (try? fm.copyItem(at: source, to: destination)) != nil,
                  let bookmark = Self.makeBookmark(for: destination) else {
                // A missing/corrupt asset used to be skipped in silence: the theme
                // imported "successfully" and the operator found a blank background
                // only when they went live with it.
                lastThemeImportSkippedAssets.append(asset.file)
                continue
            }

            if asset.slot == "background" {
                payload.backgroundImageBookmark = bookmark
                payload.backgroundMediaTypeRaw = asset.mediaType
                payload.useBackgroundImage = true
            } else if asset.slot.hasPrefix("profileBackground:") || asset.slot.hasPrefix("contentBackground:") {
                // "contentBackground:" is the legacy (v1) name for the same slot.
                let key = String(asset.slot.drop(while: { $0 != ":" }).dropFirst())
                var prof = payload.profiles[key] ?? .defaultProfile(for: key)
                prof.background.imageBookmark = bookmark
                prof.background.imageName = asset.file
                prof.background.mediaTypeRaw = asset.mediaType
                prof.background.useImage = true
                payload.profiles[key] = prof
            } else if asset.slot.hasPrefix("mediaBox:") {
                // "mediaBox:<key>:<uuid>" — legacy v1 had no profile key, so
                // fall back to searching every profile for the box id.
                let rest = String(asset.slot.dropFirst("mediaBox:".count))
                let parts = rest.split(separator: ":", maxSplits: 1).map(String.init)
                let keys = parts.count == 2 ? [parts[0]] : Array(payload.profiles.keys)
                guard let boxID = UUID(uuidString: parts.last ?? "") else { continue }
                for key in keys {
                    guard var prof = payload.profiles[key],
                          let idx = prof.mediaBoxes.firstIndex(where: { $0.id == boxID }) else { continue }
                    prof.mediaBoxes[idx].bookmarkData = bookmark
                    prof.mediaBoxes[idx].mediaTypeRaw = asset.mediaType
                    if prof.mediaBoxes[idx].fileName.isEmpty {
                        prof.mediaBoxes[idx].fileName = asset.file
                    }
                    payload.profiles[key] = prof
                }
            }
        }

        let theme = Theme(id: themeID, name: archive.name, formatRaw: archive.format, payload: payload)
        themes.append(theme)
        return theme
    }

    /// Restores a full look snapshot (used by themes AND layout undo/redo).
    /// Suppresses undo registration — the mutators it calls must not push new
    /// snapshots while we are restoring one.
    private func applyPayload(_ p: ThemePayload) {
        isRestoringLayout = true
        defer { isRestoringLayout = false }
        fontSize = p.fontSize
        fontName = p.fontName
        textColorHex = p.textColorHex
        textAlignment = Self.alignment(fromRaw: p.textAlignmentRaw)
        lineSpacing = p.lineSpacing
        padding = p.padding
        shadowEnabled = p.shadowEnabled
        shadowRadius = p.shadowRadius
        shadowColorHex = p.shadowColorHex
        letterTracking = p.letterTracking
        wocStyleEnabled = p.wocStyleEnabled
        wocColorHex = p.wocColorHex
        autoFitVerseFont = p.autoFitVerseFont
        globalWeightRaw = p.globalWeightRaw
        globalVAlignRaw = p.globalVAlignRaw
        globalTextOpacity = p.globalTextOpacity
        backgroundEnabled = p.backgroundEnabled
        backgroundColorHex = p.backgroundColorHex
        backgroundOpacity = p.backgroundOpacity
        useBackgroundImage = p.useBackgroundImage
        backgroundMediaTypeRaw = p.backgroundMediaTypeRaw
        backgroundStaysOnHide = p.backgroundStaysOnHide
        if let bookmark = p.backgroundImageBookmark {
            defaults.set(bookmark, forKey: Self.backgroundBookmarkKey)
            restoreBackgroundImage(from: bookmark)
        } else {
            backgroundImage = nil
            backgroundMediaURL = nil
            backgroundImagePath = nil
            defaults.removeObject(forKey: Self.backgroundBookmarkKey)
        }
        if !p.profiles.isEmpty {
            profiles = p.profiles
            // Wholesale replacement — undo/redo, applying a theme, importing a
            // .tptheme. Every box in every profile may have moved.
            invalidateAllProfiles()
        }
        loadContentBackgroundImages()
    }

    // MARK: - Layout Undo / Redo
    // Snapshot-based: every box mutation registers the prior state (coalesced,
    // so a continuous drag is ONE undo step). Snapshots reuse ThemePayload.
    private(set) var layoutUndoStack: [ThemePayload] = []
    private(set) var layoutRedoStack: [ThemePayload] = []
    @ObservationIgnored private var lastUndoRegistration: Date = .distantPast
    @ObservationIgnored private var isRestoringLayout = false

    var canUndoLayout: Bool { !layoutUndoStack.isEmpty }
    var canRedoLayout: Bool { !layoutRedoStack.isEmpty }

    /// Call BEFORE a box mutation. Registrations closer than 0.8s apart merge
    /// into one step (slider drags, box drags).
    func registerLayoutUndo() {
        guard !isRestoringLayout else { return }
        let now = Date.now
        let sinceLast = now.timeIntervalSince(lastUndoRegistration)
        lastUndoRegistration = now
        guard sinceLast > 0.8 else { return }
        layoutUndoStack.append(captureThemePayload())
        if layoutUndoStack.count > 30 {
            layoutUndoStack.removeFirst()
        }
        layoutRedoStack.removeAll()
    }

    func undoLayout() {
        guard let snapshot = layoutUndoStack.popLast() else { return }
        layoutRedoStack.append(captureThemePayload())
        applyPayload(snapshot)
        lastUndoRegistration = .distantPast
    }

    func redoLayout() {
        guard let snapshot = layoutRedoStack.popLast() else { return }
        layoutUndoStack.append(captureThemePayload())
        applyPayload(snapshot)
        lastUndoRegistration = .distantPast
    }

    // MARK: - Freeze Snapshot
    private(set) var frozenFontSize: Double = PresentationDefaults.fontSize
    private(set) var frozenFontName: String = PresentationDefaults.fontName
    private(set) var frozenTextColorHex: String = PresentationDefaults.textColor
    private(set) var frozenBackgroundColorHex: String = PresentationDefaults.backgroundColor
    private(set) var frozenLineSpacing: Double = PresentationDefaults.lineSpacing
    private(set) var frozenPadding: Double = PresentationDefaults.padding
    private(set) var frozenShadowEnabled: Bool = true
    private(set) var frozenShadowRadius: Double = 3.0
    private(set) var frozenBackgroundOpacity: Double = PresentationDefaults.backgroundOpacity
    private(set) var frozenUseBackgroundImage: Bool = false
    private(set) var frozenBackgroundImage: NSImage?
    private(set) var frozenTextAlignment: TextAlignment = .center
    private(set) var frozenBackgroundEnabled: Bool = false
    // Boxes frozen
    private(set) var frozenFrames: [String: TextBoxFrame] = [:]
    private(set) var frozenStyles: [String: ResolvedBoxStyle] = [:]
    private(set) var frozenCustomBoxes: [CustomTextBox] = []
    private(set) var frozenMediaBoxes: [MediaBox] = []

    // MARK: - Output Accessors (used by PresentationOutputView)
    var outputFontSize: Double { isFrozen ? frozenFontSize : fontSize }
    var outputFontName: String { isFrozen ? frozenFontName : fontName }
    var outputTextColorHex: String { isFrozen ? frozenTextColorHex : textColorHex }
    var outputBackgroundColorHex: String { isFrozen ? frozenBackgroundColorHex : backgroundColorHex }
    var outputLineSpacing: Double { isFrozen ? frozenLineSpacing : lineSpacing }
    var outputPadding: Double { isFrozen ? frozenPadding : padding }
    var outputShadowEnabled: Bool { isFrozen ? frozenShadowEnabled : shadowEnabled }
    var outputShadowRadius: Double { isFrozen ? frozenShadowRadius : shadowRadius }
    var outputBackgroundOpacity: Double { isFrozen ? frozenBackgroundOpacity : backgroundOpacity }
    var outputUseBackgroundImage: Bool { isFrozen ? frozenUseBackgroundImage : useBackgroundImage }
    var outputBackgroundImage: NSImage? { isFrozen ? frozenBackgroundImage : backgroundImage }
    var outputTextAlignment: TextAlignment { isFrozen ? frozenTextAlignment : textAlignment }
    var outputBackgroundEnabled: Bool { isFrozen ? frozenBackgroundEnabled : backgroundEnabled }
    var outputTextColor: Color { Color(hex: outputTextColorHex) ?? .white }
    var outputBackgroundColor: Color { Color(hex: outputBackgroundColorHex) ?? .black }

    func outputBoxFrame(for section: TextBoxSection) -> TextBoxFrame {
        isFrozen
            ? (frozenFrames[section.rawValue] ?? boxFrame(for: section, in: outputProfileKey))
            : boxFrame(for: section, in: outputProfileKey)
    }

    func outputStyle(for section: TextBoxSection) -> ResolvedBoxStyle {
        isFrozen
            ? (frozenStyles[section.rawValue] ?? resolvedStyle(for: section, in: outputProfileKey))
            : resolvedStyle(for: section, in: outputProfileKey)
    }

    var outputCustomTextBoxes: [CustomTextBox] { isFrozen ? frozenCustomBoxes : profile(outputProfileKey).customTextBoxes }
    var outputMediaBoxes: [MediaBox] { isFrozen ? frozenMediaBoxes : profile(outputProfileKey).mediaBoxes }
    /// The render order of the OUTPUT profile.
    func outputOrderedBoxTokens() -> [String] { orderedBoxTokens(in: outputProfileKey) }
    // Visibility (not frozen — hiding a box mid-freeze is an operator action)
    func outputSectionVisible(_ section: TextBoxSection) -> Bool { isSectionVisible(section, in: outputProfileKey) }

    // MARK: - Transitions (per-profile text enter/exit)

    func transitionInRaw(in key: String? = nil) -> String { readChrome(in: key) { $0.transitionInRaw } }
    func transitionChangeRaw(in key: String? = nil) -> String { readChrome(in: key) { $0.transitionChangeRaw } }
    func transitionOutRaw(in key: String? = nil) -> String { readChrome(in: key) { $0.transitionOutRaw } }
    func setTransitionIn(_ raw: String, in key: String? = nil) { mutateChrome(key) { $0.transitionInRaw = raw } }
    func setTransitionChange(_ raw: String, in key: String? = nil) { mutateChrome(key) { $0.transitionChangeRaw = raw } }
    func setTransitionOut(_ raw: String, in key: String? = nil) { mutateChrome(key) { $0.transitionOutRaw = raw } }

    /// How the last content change happened — picks which transition plays:
    /// "appear" (nothing → live), "change" (slide → slide), "clear" (live → nothing).
    private(set) var contentChangeKind: String = "appear"

    /// Per-PHASE duration: stored raw (-1 = inherit profile/general).
    func phaseDurationOverride(_ phase: String, in key: String? = nil) -> Double {
        let p = readChrome(in: key) { $0 }
        switch phase {
        case "change": return p.transitionChangeDuration
        case "clear": return p.transitionOutDuration
        default: return p.transitionInDuration
        }
    }

    func setPhaseDurationOverride(_ value: Double, _ phase: String, in key: String? = nil) {
        mutateChrome(key) {
            switch phase {
            case "change": $0.transitionChangeDuration = value
            case "clear": $0.transitionOutDuration = value
            default: $0.transitionInDuration = value
            }
        }
    }

    /// The duration that actually plays for a phase:
    /// phase override → profile override → global.
    func resolvedTransitionDuration(phase: String? = nil, in key: String? = nil) -> Double {
        let override = phaseDurationOverride(phase ?? contentChangeKind, in: key)
        return override >= 0 ? override : transitionDuration(in: key)
    }

    func boxColorHex(forToken token: String, in key: String? = nil) -> String? {
        readBox(token, in: key) { $0.boxColors[token] }
    }

    func setBoxColorHex(_ hex: String?, forToken token: String, in key: String? = nil) {
        mutateBox(token, in: key) { $0.boxColors[token] = (hex?.isEmpty == false) ? hex : nil }
    }

    func boxTransitionOverride(forToken token: String, in key: String? = nil) -> BoxTransition {
        readBox(token, in: key) { $0.boxTransitionOverrides[token] } ?? BoxTransition()
    }

    func setBoxTransitionOverride(_ override: BoxTransition, forToken token: String, in key: String? = nil) {
        mutateBox(token, in: key) {
            // A pristine override is noise — drop the entry entirely.
            $0.boxTransitionOverrides[token] = (override == BoxTransition()) ? nil : override
        }
    }
    func transitionDuration(in key: String? = nil) -> Double {
        let override = readChrome(in: key) { $0.transitionDurationOverride }
        return override >= 0 ? override : transitionDuration
    }
    func setTransitionDurationOverride(_ value: Double, in key: String? = nil) {
        mutateChrome(key) { $0.transitionDurationOverride = value }
    }

    static let transitionOptions: [(raw: String, label: String)] = [
        ("none", String(localized: "Fără", comment: "Transition")),
        ("fade", String(localized: "Estompare", comment: "Transition")),
        ("zoomIn", String(localized: "Zoom +", comment: "Transition")),
        ("zoomOut", String(localized: "Zoom −", comment: "Transition")),
        ("slideUp", String(localized: "Glisare sus", comment: "Transition")),
        ("slideDown", String(localized: "Glisare jos", comment: "Transition")),
        ("slideLeft", String(localized: "Glisare stânga", comment: "Transition")),
        ("slideRight", String(localized: "Glisare dreapta", comment: "Transition")),
        ("riseSoft", String(localized: "Ridicare fină", comment: "Transition")),
        ("dropSoft", String(localized: "Coborâre fină", comment: "Transition")),
        ("blur", String(localized: "Blur", comment: "Transition")),
        ("blurZoom", String(localized: "Blur + Zoom", comment: "Transition")),
        ("fall", String(localized: "Cădere", comment: "Transition")),
        ("flip", String(localized: "Rotire 3D", comment: "Transition")),
    ]

    static func transitionPart(_ raw: String) -> AnyTransition {
        switch raw {
        case "none": return .identity
        case "zoomIn": return .scale(scale: 0.85).combined(with: .opacity)
        case "zoomOut": return .scale(scale: 1.15).combined(with: .opacity)
        case "slideUp": return .move(edge: .bottom).combined(with: .opacity)
        case "slideDown": return .move(edge: .top).combined(with: .opacity)
        case "slideLeft": return .move(edge: .trailing).combined(with: .opacity)
        case "slideRight": return .move(edge: .leading).combined(with: .opacity)
        case "riseSoft": return .offset(y: 36).combined(with: .opacity)
        case "dropSoft": return .offset(y: -36).combined(with: .opacity)
        case "blur": return .modifier(
            active: BlurFadeModifier(radius: 12, opacity: 0),
            identity: BlurFadeModifier(radius: 0, opacity: 1)
        )
        case "blurZoom": return .modifier(
            active: BlurFadeModifier(radius: 14, opacity: 0, scale: 0.92),
            identity: BlurFadeModifier(radius: 0, opacity: 1, scale: 1)
        )
        case "fall": return .modifier(
            active: BlurFadeModifier(radius: 10, opacity: 0, scale: 1.25),
            identity: BlurFadeModifier(radius: 0, opacity: 1, scale: 1)
        )
        case "flip": return .modifier(
            active: FlipFadeModifier(angle: 75, opacity: 0),
            identity: FlipFadeModifier(angle: 0, opacity: 1)
        )
        default: return .opacity
        }
    }

    static func transitionLabel(_ raw: String) -> String {
        transitionOptions.first { $0.raw == raw }?.label ?? raw
    }

    /// The transition for the given profile, honoring HOW the content changed:
    /// slide → slide uses the Intermediar effect for both out and in; first
    /// appearance uses Intrare; clearing uses Ieșire.
    func boxTransition(in key: String? = nil, token: String? = nil) -> AnyTransition {
        let override = token.map { boxTransitionOverride(forToken: $0, in: key) } ?? BoxTransition()
        let custom = override.isCustomized

        func effective(_ own: String, _ profileRaw: String) -> String {
            custom && !own.isEmpty ? own : profileRaw
        }

        let base: AnyTransition
        if contentChangeKind == "change" {
            let part = Self.transitionPart(effective(override.changeRaw, transitionChangeRaw(in: key)))
            base = .asymmetric(insertion: part, removal: part)
        } else {
            base = .asymmetric(
                insertion: Self.transitionPart(effective(override.inRaw, transitionInRaw(in: key))),
                removal: Self.transitionPart(effective(override.outRaw, transitionOutRaw(in: key)))
            )
        }
        // A box with its own delay or duration carries its own animation clock.
        let delay = custom ? override.delay : 0
        let duration = (custom && override.duration >= 0)
            ? override.duration
            : resolvedTransitionDuration(in: key)
        if delay > 0 || (custom && override.duration >= 0) {
            return base.animation(.easeInOut(duration: duration).delay(delay))
        }
        return base
    }

    // MARK: - Init (restore from UserDefaults)
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        self.fontSize = d.object(forKey: "pm_fontSize") as? Double ?? PresentationDefaults.fontSize
        self.fontName = d.string(forKey: "pm_fontName") ?? PresentationDefaults.fontName
        self.textColorHex = d.string(forKey: "pm_textColorHex") ?? PresentationDefaults.textColor
        self.backgroundColorHex = d.string(forKey: "pm_backgroundColorHex") ?? PresentationDefaults.backgroundColor
        self.textAlignment = Self.alignment(fromRaw: d.string(forKey: "pm_textAlignmentRaw") ?? "center")
        self.lineSpacing = d.object(forKey: "pm_lineSpacing") as? Double ?? PresentationDefaults.lineSpacing
        self.padding = d.object(forKey: "pm_padding") as? Double ?? PresentationDefaults.padding
        self.shadowEnabled = d.object(forKey: "pm_shadowEnabled") as? Bool ?? true
        self.shadowRadius = d.object(forKey: "pm_shadowRadius") as? Double ?? PresentationDefaults.shadowRadius
        self.shadowColorHex = d.string(forKey: "pm_shadowColorHex") ?? PresentationDefaults.shadowColor
        self.letterTracking = d.object(forKey: "pm_letterTracking") as? Double ?? 0
        self.wocStyleEnabled = d.object(forKey: "pm_wocStyleEnabled") as? Bool ?? true
        self.wocColorHex = d.string(forKey: "pm_wocColorHex") ?? PresentationDefaults.wocColor
        self.transitionDuration = d.object(forKey: "pm_transitionDuration") as? Double ?? PresentationDefaults.transitionDuration
        self.globalWeightRaw = d.string(forKey: "pm_globalWeightRaw") ?? "regular"
        self.globalVAlignRaw = d.string(forKey: "pm_globalVAlignRaw") ?? "center"
        self.globalTextOpacity = d.object(forKey: "pm_globalTextOpacity") as? Double ?? 1.0
        self.backgroundOpacity = d.object(forKey: "pm_backgroundOpacity") as? Double ?? PresentationDefaults.backgroundOpacity
        self.useBackgroundImage = d.bool(forKey: "pm_useBackgroundImage")
        self.backgroundMediaTypeRaw = d.string(forKey: "pm_backgroundMediaTypeRaw") ?? "image" 
        self.backgroundEnabled = d.bool(forKey: "pm_backgroundEnabled") // defaults to false = transparent
        self.backgroundStaysOnHide = d.object(forKey: "pm_backgroundStaysOnHide") as? Bool ?? true
        self.windowLevel = d.string(forKey: "pm_windowLevel") ?? "alwaysOnTop"
        self.screenDisconnectAction = ScreenDisconnectAction(
            rawValue: d.string(forKey: "pm_screenDisconnectAction") ?? "ask") ?? .ask
        self.autoFitVerseFont = d.bool(forKey: "pm_autoFitVerseFont")
        self.videoLoopsByDefault = d.object(forKey: "pm_videoLoopsByDefault") as? Bool ?? true
        self.fullscreenVideoFillRaw = d.string(forKey: "pm_fullscreenVideoFillRaw") ?? "fit"
        self.mediaZoom = d.object(forKey: "pm_mediaZoom") as? Double ?? 1
        self.mediaPanX = d.object(forKey: "pm_mediaPanX") as? Double ?? 0
        self.mediaPanY = d.object(forKey: "pm_mediaPanY") as? Double ?? 0
        // Themes
        if let data = d.data(forKey: "pm_themes"),
           let decoded = try? JSONDecoder().decode([Theme].self, from: data) {
            self.themes = decoded
        } else {
            self.themes = []
        }
        if let idString = d.string(forKey: "pm_activeThemeID"), let id = UUID(uuidString: idString) {
            self.activeThemeID = id
        } else {
            self.activeThemeID = nil
        }
        self.usesPerPresenterThemes = d.bool(forKey: "pm_usesPerPresenterThemes")
        if let data = d.data(forKey: "pm_themeAssignments"),
           let raw = try? JSONDecoder().decode([String: String].self, from: data) {
            self.themeAssignments = raw.compactMapValues(UUID.init(uuidString:))
        } else {
            self.themeAssignments = [:]
        }

        // Layout profiles — per-presenter layouts. Migrate from the old flat
        // single-layout keys on first run so the existing look is preserved.
        if let data = d.data(forKey: "pm_layoutProfiles"),
           let decoded = try? JSONDecoder().decode([String: LayoutProfile].self, from: data),
           !decoded.isEmpty {
            self.profiles = decoded
        } else {
            var migrated: [String: LayoutProfile] = [:]
            // Legacy flat state (if any)
            var legacy = LayoutProfile()
            legacy.frames = [
                TextBoxSection.verseContent.rawValue: TextBoxFrame.decode(from: d, key: "pm_verseBoxFrame", fallback: .defaultVerse),
                TextBoxSection.reference.rawValue: TextBoxFrame.decode(from: d, key: "pm_refBoxFrame", fallback: .defaultReference),
                TextBoxSection.translationName.rawValue: TextBoxFrame.decode(from: d, key: "pm_translationBoxFrame", fallback: .defaultTranslation),
                TextBoxSection.subtitle.rawValue: TextBoxFrame.decode(from: d, key: "pm_subtitleBoxFrame", fallback: .defaultSubtitle),
            ]
            if let stylesData = d.data(forKey: "pm_verseStyle"),
               let style = try? JSONDecoder().decode(BoxTextStyle.self, from: stylesData) {
                legacy.styles[TextBoxSection.verseContent.rawValue] = style
            }
            if let stylesData = d.data(forKey: "pm_refStyle"),
               let style = try? JSONDecoder().decode(BoxTextStyle.self, from: stylesData) {
                legacy.styles[TextBoxSection.reference.rawValue] = style
            }
            if let boxesData = d.data(forKey: "pm_customTextBoxes"),
               let boxes = try? JSONDecoder().decode([CustomTextBox].self, from: boxesData) {
                legacy.customTextBoxes = boxes
            }
            if let mediaData = d.data(forKey: "pm_mediaBoxes"),
               let boxes = try? JSONDecoder().decode([MediaBox].self, from: mediaData) {
                legacy.mediaBoxes = boxes
            }
            legacy.boxOrder = d.stringArray(forKey: "pm_boxOrder") ?? []
            // Legacy per-content backgrounds fold into each profile
            var legacyBackgrounds: [String: BackgroundConfig] = [:]
            if let bgData = d.data(forKey: "pm_contentBackgrounds"),
               let configs = try? JSONDecoder().decode([String: BackgroundConfig].self, from: bgData) {
                legacyBackgrounds = configs
            }
            for key in Self.profileKeys {
                // Start from the presenter's OWN defaults and lay the legacy state
                // over the top. It used to be the other way round — a bare
                // LayoutProfile with only `visibility` copied from the defaults —
                // which meant anything a default profile provides beyond visibility
                // was silently dropped on a first run. Media's full-bleed live
                // casetă is exactly that, so a fresh install got a media presenter
                // with no media box at all.
                var p = LayoutProfile.defaultProfile(for: key)
                if !legacy.frames.isEmpty { p.frames = legacy.frames }
                if !legacy.styles.isEmpty { p.styles = legacy.styles }
                if !legacy.customTextBoxes.isEmpty { p.customTextBoxes = legacy.customTextBoxes }
                if !legacy.mediaBoxes.isEmpty { p.mediaBoxes += legacy.mediaBoxes }
                if !legacy.boxOrder.isEmpty { p.boxOrder = legacy.boxOrder + p.boxOrder }
                if let visible = d.object(forKey: "pm_verseBoxVisible") as? Bool {
                    p.visibility[TextBoxSection.verseContent.rawValue] = visible
                }
                if let bg = legacyBackgrounds[key] {
                    p.background = bg
                }
                migrated[key] = p
            }
            self.profiles = migrated
        }
        // Restore background image — security-scoped bookmark first (required in the
        // sandbox after relaunch), raw path as fallback for pre-bookmark installs.
        if let bookmark = d.data(forKey: Self.backgroundBookmarkKey) {
            restoreBackgroundImage(from: bookmark)
        } else if let path = d.string(forKey: "pm_backgroundImagePath"),
                  let image = NSImage(contentsOfFile: path) {
            self.backgroundImagePath = path
            self.backgroundImage = image
        }
        loadContentBackgroundImages()

        // Initialize frozen snapshot to current values
        snapshotForFreeze()
    }

    private func restoreBackgroundImage(from bookmark: Data) {
        guard let resolved = Self.resolveBookmarkRefreshing(bookmark) else { return }
        if let fresh = resolved.refreshed {
            defaults.set(fresh, forKey: Self.backgroundBookmarkKey)
        }
        let url = resolved.url
        backgroundMediaURL = url
        backgroundMediaTypeRaw = Self.mediaType(forExtension: url.pathExtension)
        backgroundImagePath = url.path
        backgroundImage = backgroundMediaTypeRaw == "image" ? NSImage(contentsOf: url) : nil
    }

    // MARK: - Computed Properties
    var textColor: Color {
        Color(hex: textColorHex) ?? .white
    }

    var backgroundColor: Color {
        Color(hex: backgroundColorHex) ?? .black
    }

    // MARK: - Methods

    func refreshScreens() {
        availableScreens = NSScreen.screens
    }

    func goLive() {
        liveContent.isLive = true
        isBlackScreen = false
    }

    func goBlack() {
        isBlackScreen = true
    }

    func toggleBlack() {
        isBlackScreen.toggle()
        if isBlackScreen {
            showPresentationWindow()
        }
    }

    func toggleFreeze() {
        if !isFrozen {
            snapshotForFreeze()
        }
        isFrozen.toggle()
    }

    /// Capture current display settings into the frozen snapshot.
    private func snapshotForFreeze() {
        frozenFontSize = fontSize
        frozenFontName = fontName
        frozenTextColorHex = textColorHex
        frozenBackgroundColorHex = backgroundColorHex
        frozenLineSpacing = lineSpacing
        frozenPadding = padding
        frozenShadowEnabled = shadowEnabled
        frozenShadowRadius = shadowRadius
        frozenBackgroundOpacity = backgroundOpacity
        frozenUseBackgroundImage = useBackgroundImage
        frozenBackgroundImage = backgroundImage
        frozenTextAlignment = textAlignment
        frozenBackgroundEnabled = backgroundEnabled
        let key = outputProfileKey
        for section in TextBoxSection.allCases {
            frozenFrames[section.rawValue] = boxFrame(for: section, in: key)
            frozenStyles[section.rawValue] = resolvedStyle(for: section, in: key)
        }
        frozenCustomBoxes = profile(key).customTextBoxes
        frozenMediaBoxes = profile(key).mediaBoxes
    }

    func clearOutput() {
        // Invalidate any staged show: without this, Show-while-hidden followed
        // immediately by Escape re-mounts the content 60 ms AFTER the clear.
        presentGeneration &+= 1
        cancelStagedShow()
        flushHistory()              // record the last-shown item (if it dwelled)
        currentSessionKey = ""      // a clear ends the presentation session
        contentChangeKind = "clear"
        bibleLiveAnchor = nil       // the presented flow ended — ←/→ re-follow selection
        // Resolve the exit duration BEFORE clearing (it needs the live profile).
        let exitDuration = resolvedTransitionDuration(phase: "clear", in: outputProfileKey)
        withAnimation(.easeInOut(duration: exitDuration)) {
            liveContent.clear()
            isBlackScreen = false
            isFrozen = false
        }
        videoService?.stop()
        if isOutputOnOperatorScreen {
            // Let the Ieșire transition play to transparency first — hiding the
            // window immediately would cut the animation (and leave the old
            // boxes uncommitted, so the next Show looked like an Intermediar).
            DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration + 0.15) { [weak self] in
                guard let self, !self.liveContent.isLive else { return }
                self.hidePresentationWindow()
            }
        }
    }

    /// Bumped by every show and every clear. A staged (60 ms) apply captures the
    /// value it was scheduled with and bails if it is no longer current.
    @ObservationIgnored private var presentGeneration = 0

    /// The pending staged show, when the output window had to commit a transparent
    /// frame first. Held so a newer show or a clear can cancel it outright.
    @ObservationIgnored private var stagedShow: DispatchWorkItem?

    /// True while a show is waiting on the staging frame — i.e. the output window
    /// was hidden when it was requested.
    var hasStagedShow: Bool { stagedShow != nil }

    /// Marks whether this show is a fresh appearance or a slide-to-slide change.
    private func registerContentChange() {
        contentChangeKind = (liveContent.isLive && !isBlackScreen) ? "change" : "appear"
    }

    /// Stages a content change so its transition actually renders: if the
    /// output window was hidden (single-screen idle), show it and let it
    /// commit one transparent frame FIRST — only then mount the content, so
    /// Intrare animates from transparency instead of popping fully formed.
    private func presentContent(_ apply: @escaping () -> Void) {
        let window = presentationWindow
        let wasHidden = !(window?.isVisible ?? true) // nil window (tests) = immediate
        showPresentationWindow()

        // Every show/clear takes the next generation. A staged apply belongs to the
        // generation it was scheduled in and is dropped if anything newer happened
        // meanwhile: orderFront() makes the window visible SYNCHRONOUSLY, so a second
        // Show 10 ms later takes the immediate path and lands first — without this,
        // the first (deferred) one would then overwrite the projector with stale
        // content 60 ms after the operator already moved on.
        presentGeneration &+= 1
        let generation = presentGeneration
        cancelStagedShow()

        let animated = { [weak self] in
            guard let self, generation == presentGeneration else { return }
            registerContentChange()
            let duration = resolvedTransitionDuration(phase: contentChangeKind, in: outputProfileKey)
            withAnimation(.easeInOut(duration: duration)) {
                apply()
            }
        }
        if wasHidden {
            let work = DispatchWorkItem { [weak self] in
                self?.stagedShow = nil
                animated()
            }
            stagedShow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: work)
        } else {
            animated()
        }
    }

    /// Drops a pending staged show, if any. Cancelling beats letting it run and
    /// no-op on the generation check — the work never happens at all.
    private func cancelStagedShow() {
        stagedShow?.cancel()
        stagedShow = nil
    }

    // MARK: - Live Bible Anchor (the PRESENTED flow, independent of browsing)

    /// What's on the projector: translation + book/chapter + verse range.
    /// ←/→ advance THIS — browsing/selecting in the Bible list never moves the
    /// live flow; Show / double-click re-anchor. Ephemeral (not persisted).
    struct BibleLiveAnchor: Equatable {
        var translation: String
        var bookNumber: Int
        var chapter: Int
        var verseStart: Int
        var verseEnd: Int
    }
    private(set) var bibleLiveAnchor: BibleLiveAnchor?

    /// Step the live anchor ±1 block (same range size), crossing chapter
    /// boundaries; `direction: 0` re-presents the anchor in place (used when
    /// display settings change). Pushes live + updates the anchor. Returns
    /// false when the anchor can't resolve or can't move further.
    @discardableResult
    func stepBibleAnchor(direction: Int, context: ModelContext) -> Bool {
        guard let anchor = bibleLiveAnchor else { return false }
        let wanted = anchor.translation.lowercased()
        let modules = (try? context.fetch(FetchDescriptor<BibleModule>())) ?? []
        guard let module = modules.first(where: { $0.abbreviation.lowercased() == wanted }),
              let book = module.books.first(where: { $0.bookNumber == anchor.bookNumber })
        else { return false }

        let chapters = book.chapters.sorted { $0.chapterNumber < $1.chapterNumber }
        guard let chapterIdx = chapters.firstIndex(where: { $0.chapterNumber == anchor.chapter }) else { return false }
        let block = max(anchor.verseEnd - anchor.verseStart + 1, 1)

        var targetChapter = chapters[chapterIdx]
        var verses = targetChapter.verses.sorted { $0.verseNumber < $1.verseNumber }
        guard let startIdx = verses.firstIndex(where: { $0.verseNumber >= anchor.verseStart }) else { return false }

        var newStart: Int
        switch direction {
        case 0:
            newStart = startIdx
        case let d where d > 0:
            newStart = startIdx + block
            if newStart >= verses.count {
                guard chapterIdx + 1 < chapters.count else { return false }
                targetChapter = chapters[chapterIdx + 1]
                verses = targetChapter.verses.sorted { $0.verseNumber < $1.verseNumber }
                newStart = 0
            }
        default:
            newStart = startIdx - block
            if newStart < 0 {
                guard chapterIdx > 0 else { return false }
                targetChapter = chapters[chapterIdx - 1]
                verses = targetChapter.verses.sorted { $0.verseNumber < $1.verseNumber }
                newStart = max(verses.count - block, 0)
            }
        }
        guard !verses.isEmpty, newStart >= 0, newStart < verses.count else { return false }
        let slice = Array(verses[newStart ..< min(newStart + block, verses.count)])
        guard let first = slice.first, let last = slice.last else { return false }

        // Text: same multi-verse settings as the Bible panel (theme-driven).
        let mv = bibleMultiVerse
        let separator = mv.layout == "newLine" ? "\n" : " "
        var joined = slice
            .map { mv.showNumbers ? "(\($0.verseNumber)) \($0.text)" : $0.text }
            .joined(separator: separator)
        let range = first.verseNumber == last.verseNumber
            ? "\(first.verseNumber)" : "\(first.verseNumber)-\(last.verseNumber)"
        let reference = "\(book.name) \(targetChapter.chapterNumber):\(range)"
        if mv.customEnabled, slice.count > 1 {
            let template = mv.customText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !template.isEmpty {
                var out = template
                    .replacingOccurrences(of: "{verses}", with: joined)
                    .replacingOccurrences(of: "{ref}", with: reference)
                    .replacingOccurrences(of: "{n}", with: "\(slice.count)")
                if !template.contains("{verses}") { out += separator + joined }
                joined = out
            }
        }

        // Rich casete sources — mirrors the selection-based accessors.
        let footnote = slice.flatMap { $0.footnotes }
            .map { $0.marker.isEmpty ? $0.text : "\($0.marker) \($0.text)" }
            .joined(separator: "\n")
        let crossRef = slice.flatMap { $0.crossReferences }
            .flatMap { ref in [ref.label].compactMap { $0 } + ref.targets }
            .joined(separator: "; ")
        let lo = first.verseNumber, hi = last.verseNumber
        let heading = targetChapter.headings
            .filter { $0.beforeVerse >= lo && $0.beforeVerse <= hi }
            .map { $0.text }.joined(separator: "\n")
        let gloss = slice.map { $0.gloss }.filter { !$0.isEmpty }.joined(separator: " ")
        let runs = slice.count == 1 ? first.runs : []
        let strongs = slice.count == 1 ? first.runs.compactMap { $0.strong }.joined(separator: " ") : ""

        showBibleVerse(text: joined, reference: reference, translationName: module.abbreviation,
                       runs: runs, footnote: footnote, crossReference: crossRef, heading: heading,
                       gloss: gloss, strongs: strongs,
                       bookNumber: book.bookNumber, bookName: book.name,
                       chapter: targetChapter.chapterNumber,
                       verseStart: first.verseNumber, verseEnd: last.verseNumber,
                       translation: module.abbreviation)
        return true
    }

    // MARK: - Show* — everything that puts content on the output

    func showBibleVerse(text: String, reference: String, translationName: String = "", runs: [VerseRun] = [],
                        footnote: String = "", crossReference: String = "", heading: String = "",
                        gloss: String = "", strongs: String = "",
                        bookNumber: Int = 0, bookName: String = "", chapter: Int = 0,
                        verseStart: Int = 0, verseEnd: Int = 0, translation: String = "",
                        slideIndex: Int = 0, slideCount: Int = 1) {
        guard !isFrozen else { return }
        // Re-anchor the LIVE flow whenever a presenter supplies real coordinates
        // (Show button, double-click, session runner). Browsing never gets here.
        if chapter > 0, verseStart > 0, !translation.isEmpty {
            bibleLiveAnchor = BibleLiveAnchor(translation: translation, bookNumber: bookNumber,
                                              chapter: chapter, verseStart: verseStart,
                                              verseEnd: max(verseEnd, verseStart))
        }
        beginHistory(HistoryItem(contentType: "bible", sessionKey: "\(translation):\(bookNumber):\(chapter)",
                                 translation: translation, translationName: translationName, bookName: bookName,
                                 reference: reference, bookNumber: bookNumber, chapter: chapter,
                                 verseStart: verseStart, verseEnd: verseEnd))
        presentContent { [self] in
            liveContent.setBibleVerse(text: text, reference: reference, translationName: translationName, runs: runs,
                                      footnote: footnote, crossReference: crossReference, heading: heading,
                                      gloss: gloss, strongs: strongs,
                                      slideIndex: slideIndex, slideCount: slideCount)
            lastLiveProfileKey = "bible"
            liveContent.isLive = true
            isBlackScreen = false
        }
    }

    func showSongVerse(text: String, title: String, verseLabel: String, slideIndex: Int = 0, slideCount: Int = 1,
                       song: Song? = nil, version: SongVersion? = nil, lines: [SongLine] = []) {
        guard !isFrozen else { return }
        let sKey = HistoryStore.songKey(ccli: song?.ccliNumber ?? "", title: song?.title ?? title,
                                        source: song?.collection?.sourceFormat ?? "")
        syncChordTranspose(forSongKey: sKey)
        beginHistory(HistoryItem(contentType: "song", sessionKey: sKey, songKey: sKey,
                                 songTitle: song?.title ?? title, versionName: version?.name ?? "",
                                 verseLabel: verseLabel, slideIndex: slideIndex))
        // A version uses its own metadata only when it overrides; otherwise it inherits the
        // original (first) version's. Song-level fields are the final fallback.
        let meta = (version?.overridesMetadata == true) ? version : (song?.activeVersion ?? version)
        func pick(_ versionValue: String?, _ songValue: String?) -> String {
            if let v = versionValue, !v.isEmpty { return v }
            return songValue ?? ""
        }
        presentContent { [self] in
            liveContent.setSongVerse(
                text: text,
                title: pick(meta?.displayTitle, title),
                verseLabel: verseLabel,
                slideIndex: slideIndex, slideCount: slideCount,
                author: pick(meta?.author, song?.author),
                copyright: pick(meta?.copyright, song?.copyright),
                ccli: pick(meta?.ccliNumber, song?.ccliNumber),
                songbook: pick(meta?.songbookName, song?.songbook?.name),
                style: pick(meta?.style, song?.style),
                key: pick(meta?.key, song?.key),
                tempo: pick(meta?.tempo, song?.tempo),
                lines: lines
            )
            lastLiveProfileKey = "song"
            liveContent.isLive = true
            isBlackScreen = false
        }
    }

    func showCustomText(text: String, title: String, slideIndex: Int = 0, slideCount: Int = 1) {
        guard !isFrozen else { return }
        beginHistory(HistoryItem(contentType: "custom", sessionKey: "custom:" + title,
                                 songTitle: title, slideIndex: slideIndex))
        presentContent { [self] in
            liveContent.setCustomText(text: text, title: title, slideIndex: slideIndex, slideCount: slideCount)
            lastLiveProfileKey = "text"
            liveContent.isLive = true
            isBlackScreen = false
        }
    }

    /// Marks the output as showing full-screen video.
    func showVideo() {
        showMedia(kind: "video", url: nil)
    }

    /// Marks the output as showing full-screen media (image or video). Images are
    /// decoded HERE — inside the caller's security scope — so the output window
    /// never re-opens the sandboxed file; video renders via the shared VideoPlayerService.
    func showMedia(kind: String, url: URL?) {
        guard !isFrozen else { return }
        let image: NSImage? = (kind == "image") ? url.flatMap { NSImage(contentsOf: $0) } : nil
        presentContent { [self] in
            liveContent.setMedia(kind: kind, url: url, image: image)
            lastLiveProfileKey = "media"
            liveContent.isLive = true
            isBlackScreen = false
        }
    }

    /// Sets the global background from any supported media: image, GIF, or video.
    func setBackgroundMedia(from url: URL) {
        registerLayoutUndo()
        backgroundMediaTypeRaw = Self.mediaType(forExtension: url.pathExtension)
        backgroundMediaURL = url
        backgroundImage = backgroundMediaTypeRaw == "image" ? NSImage(contentsOf: url) : nil
        backgroundImagePath = url.path
        useBackgroundImage = true
        if let bookmark = Self.makeBookmark(for: url) {
            defaults.set(bookmark, forKey: Self.backgroundBookmarkKey)
        }
    }

    /// Legacy name kept for callers that set a plain image background.
    func setBackgroundImage(from url: URL) {
        setBackgroundMedia(from: url)
    }

    func removeBackgroundImage() {
        registerLayoutUndo()
        backgroundImage = nil
        backgroundMediaURL = nil
        backgroundMediaTypeRaw = "image"
        backgroundImagePath = nil
        useBackgroundImage = false
        defaults.removeObject(forKey: Self.backgroundBookmarkKey)
    }

    func applyStyle(_ style: PresentationStyle) {
        currentStyle = style
        fontSize = style.fontSize
        fontName = style.fontName
        textColorHex = style.textColorHex
        backgroundColorHex = style.backgroundColorHex
        backgroundOpacity = style.backgroundOpacity
        textAlignment = style.alignment
        lineSpacing = style.lineSpacing
        padding = style.padding
        shadowEnabled = style.shadowEnabled
        shadowRadius = style.shadowRadius

        if let imagePath = style.backgroundImagePath,
           let image = NSImage(contentsOfFile: imagePath) {
            backgroundImage = image
            backgroundImagePath = imagePath
            useBackgroundImage = true
        } else {
            removeBackgroundImage()
        }
    }

    // MARK: - Output Window Management
    // NOTE: screen SELECTION and the disconnect/connect prompts live far above,
    // under "Screen Management" — these are the NSWindow mechanics only.

    /// Positions the presentation window on the specified screen
    func positionOnScreen(_ screen: NSScreen) {
        dedupePresentationWindows()
        presentationScreenIndex = NSScreen.screens.firstIndex(of: screen)
        movePresentationWindow(to: screen)
    }

    /// ALL windows carrying the presentation identifier. Normally one; more than one
    /// means a stale/duplicate (state restoration + auto-open) — see `dedupe…`.
    private var presentationWindows: [NSWindow] {
        NSApplication.shared.windows.filter { $0.identifier?.rawValue == WindowIdentifiers.presentation }
    }

    /// The presentation NSWindow, found by its identifier.
    private var presentationWindow: NSWindow? { presentationWindows.first }

    /// True when an output window already exists (so the launch auto-open can skip).
    var hasPresentationWindow: Bool { presentationWindow != nil }

    /// Close any EXTRA presentation windows — macOS window-state restoration can
    /// re-create one on relaunch, which the launch auto-open then doubles, leaving an
    /// unmanaged copy on the built-in screen overlapping the real output.
    func dedupePresentationWindows() {
        let windows = presentationWindows
        guard windows.count > 1 else { return }
        for extra in windows.dropFirst() {
            extra.orderOut(nil)
            extra.close()
        }
    }

    /// Hides the presentation window (used when clearing output on the built-in screen).
    func hidePresentationWindow() {
        presentationWindow?.orderOut(nil)
    }

    /// Panic hatch (⌘⎋): drops the output off the screen NOW — no exit transition,
    /// no conditions, whatever is live stays live. On a single display an
    /// always-on-top output covers the app itself, so the operator needs one key
    /// that is guaranteed to give the screen back even mid-animation or mid-video.
    func hideOutputNow() {
        videoService?.stop()
        hidePresentationWindow()
    }

    /// Shows the presentation window if it is not visible.
    func showPresentationWindow() {
        dedupePresentationWindows()
        guard let window = presentationWindow, !window.isVisible else { return }
        window.orderFront(nil)
    }

    /// Moves the presentation window to fill the given screen.
    func movePresentationWindow(to screen: NSScreen) {
        dedupePresentationWindows()
        guard let window = presentationWindow else { return }

        let frame = screen.frame
        window.setFrame(frame, display: true, animate: false)
        window.level = resolvedWindowLevel
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.styleMask = [.borderless]
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
    }

    // MARK: - Auto-Fit Font Size

    /// Cache key for an auto-fit computation. The binary search below measures text
    /// up to 17 times — without this, every SwiftUI body evaluation of the output AND
    /// the preview card would redo all that layout work.
    ///
    /// The geometry is QUANTISED, and that is the point. Continuous values made every
    /// frame of a gesture a fresh key: measured at **4.4 ms per delta** while resizing
    /// a box and **4.0 ms** while dragging the size slider, against 0.002 ms for a
    /// cache hit. Moving a box was always fine — `rect(in:).size` depends on
    /// width/height, not x/y — so this is specifically about resizing and sliders.
    ///
    /// Quantisation rounds in the SAFE direction: box smaller, cap smaller, padding
    /// and line spacing larger. A reused fit therefore always belongs to a box at
    /// least as tight as the real one, so text can never overflow because of it.
    /// Integers, in units of `quantum`, so hashing is cheap too.
    private struct FitCacheKey: Equatable, Hashable {
        let text: String
        let boxWidth: Int
        let boxHeight: Int
        let maxSize: Int
        let fontName: String
        let lineSpacing: Int
        let padding: Int
    }

    /// Granularity for the fit key. 1/4 pt for the cap and padding — far below what
    /// any eye can see in a fitted font size.
    private static let fitQuantum: Double = 0.25
    /// The BOX gets a whole point, because it is the value a resize gesture sweeps
    /// continuously: at 1/4 pt a drag still minted a fresh key almost every frame.
    /// One point of a ~240 pt box is 0.4%, so the fitted size lands within a
    /// fraction of a percent of optimal — and always on the safe side, since the
    /// box is rounded DOWN.
    private static let fitBoxQuantum: Double = 1.0

    private static func fitKey(
        text: String, boxSize: CGSize, maxSize: CGFloat, padding: CGFloat,
        fontName: String, lineSpacing: Double
    ) -> (key: FitCacheKey, boxSize: CGSize, maxSize: CGFloat, padding: CGFloat, lineSpacing: Double) {
        let q = fitQuantum
        let bq = fitBoxQuantum
        // Down for the box and the cap, up for padding and spacing: every rounding
        // makes the measured layout tighter than the real one, never looser.
        let w = (boxSize.width / bq).rounded(.down)
        let h = (boxSize.height / bq).rounded(.down)
        let m = (Double(maxSize) / q).rounded(.down)
        let p = (Double(padding) / q).rounded(.up)
        let ls = (lineSpacing / 0.01).rounded(.up)
        return (
            FitCacheKey(text: text, boxWidth: Int(w), boxHeight: Int(h),
                        maxSize: Int(m), fontName: fontName,
                        lineSpacing: Int(ls), padding: Int(p)),
            CGSize(width: w * bq, height: h * bq),
            CGFloat(m * q),
            CGFloat(p * q),
            ls * 0.01
        )
    }

    /// Keyed by request, NOT a single slot. As one slot it was worthless in exactly
    /// the case it was written for: with two auto-fit boxes on screen (the verse box
    /// plus an auto-fit custom box) every call saw a different key, missed, and
    /// overwrote the slot with its own — so both boxes re-ran the ≤17-measurement
    /// binary search on every single body evaluation.
    @ObservationIgnored private var fitCache: [FitCacheKey: CGFloat] = [:]

    /// Bounded so a long service (every verse of a chapter, every slide of a set)
    /// cannot grow it without limit. Eviction is oldest-first, NOT wholesale:
    /// clearing everything meant one resize gesture's junk keys evicted the entries
    /// the live output was using, and the very next frame re-measured them —
    /// measured at 2.17 ms to re-fit a key that had been hot moments earlier.
    private static let fitCacheLimit = 512
    /// Insertion order, for evicting the oldest quarter when the cache fills.
    @ObservationIgnored private var fitCacheOrder: [FitCacheKey] = []

    /// Returns the largest font size ≤ `maxSize` at which the verse text fits inside
    /// the given box. Pass `maxSize`/`padding` already scaled by the screen's font
    /// scale, and the style's fontName/lineSpacing, so the computation matches what
    /// gets rendered. Falls back to `maxSize` when autoFitVerseFont is off.
    func fittedVerseFontSize(
        text: String, boxSize: CGSize, maxSize: CGFloat, padding: CGFloat,
        fontName: String, lineSpacing: Double
    ) -> CGFloat {
        guard autoFitVerseFont, !text.isEmpty else { return maxSize }

        // Quantise, then measure against the QUANTISED geometry, so one key always
        // yields one answer regardless of which real size asked for it first.
        let q = Self.fitKey(text: text, boxSize: boxSize, maxSize: maxSize,
                            padding: padding, fontName: fontName, lineSpacing: lineSpacing)
        if let hit = fitCache[q.key] { return hit }

        let minSize: CGFloat = 10.0
        var result = q.maxSize
        if !verseFits(text: text, size: q.maxSize, boxSize: q.boxSize, padding: q.padding,
                      fontName: fontName, lineSpacing: q.lineSpacing) {
            var lo = minSize
            var hi = q.maxSize
            var best = minSize
            // Stop on PRECISION rather than a fixed 16 iterations: the answer is a
            // font size, and an eighth of a point is already invisible. Saves roughly
            // a third of the measurements on every miss.
            while hi - lo > 0.125 {
                let mid = (lo + hi) / 2.0
                if verseFits(text: text, size: mid, boxSize: q.boxSize, padding: q.padding,
                             fontName: fontName, lineSpacing: q.lineSpacing) {
                    best = mid
                    lo = mid
                } else {
                    hi = mid
                }
            }
            result = max(best, minSize)
        }

        if fitCache.count >= Self.fitCacheLimit {
            // Drop the oldest quarter, keeping whatever the live output is using.
            let drop = Self.fitCacheLimit / 4
            for old in fitCacheOrder.prefix(drop) { fitCache.removeValue(forKey: old) }
            fitCacheOrder.removeFirst(min(drop, fitCacheOrder.count))
        }
        fitCache[q.key] = result
        fitCacheOrder.append(q.key)
        return result
    }

    private func verseFits(
        text: String, size: CGFloat, boxSize: CGSize, padding: CGFloat,
        fontName: String, lineSpacing: Double
    ) -> Bool {
        let availWidth = max(boxSize.width - padding * 2.0, 50.0)
        let availHeight = max(boxSize.height * 0.98, 20.0)

        let nsFont: NSFont = (fontName == "System" || fontName.isEmpty)
            ? NSFont.systemFont(ofSize: size)
            : (NSFont(name: fontName, size: size) ?? NSFont.systemFont(ofSize: size))

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineSpacing = CGFloat(lineSpacing) * size * 0.1

        let textHeight = (text as NSString).boundingRect(
            with: CGSize(width: availWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: nsFont, .paragraphStyle: paraStyle]
        ).height

        return textHeight <= availHeight
    }

    /// Point size of the verse box on the target presentation screen
    /// (used by auto-fill to decide how many verses fit).
    var verseBoxPointSize: CGSize {
        let screen = targetScreenMetrics.points
        let box = boxFrame(for: .verseContent, in: "bible")
        return CGSize(width: screen.width * box.width, height: screen.height * box.height)
    }

    // MARK: - Box Frame / Source / Visibility Access (by section)

    static func defaultFrame(for section: TextBoxSection) -> TextBoxFrame {
        switch section {
        case .verseContent: return .defaultVerse
        case .reference: return .defaultReference
        case .translationName: return .defaultTranslation
        case .subtitle: return .defaultSubtitle
        case .chords: return .defaultChords
        }
    }

    // Built-in sections. All box-scoped: a drag or a keystroke here invalidates
    // that one box, not its siblings and not the stacking order.

    func boxFrame(for section: TextBoxSection, in key: String? = nil) -> TextBoxFrame {
        readBox(Self.sectionToken(section), in: key) { $0.frames[section.rawValue] }
            ?? Self.defaultFrame(for: section)
    }

    func setBoxFrame(_ frame: TextBoxFrame, for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.frames[section.rawValue] = frame.clamped() }
    }

    func sourceRaw(for section: TextBoxSection, in key: String? = nil) -> String {
        readBox(Self.sectionToken(section), in: key) { $0.sources[section.rawValue] } ?? "auto"
    }

    func setSourceRaw(_ raw: String, for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.sources[section.rawValue] = raw }
    }

    func sourceFormat(for section: TextBoxSection, in key: String? = nil) -> String {
        readBox(Self.sectionToken(section), in: key) { $0.sourceFormats[section.rawValue] } ?? ""
    }

    func setSourceFormat(_ format: String, for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.sourceFormats[section.rawValue] = format }
    }

    func staticText(for section: TextBoxSection, in key: String? = nil) -> String {
        readBox(Self.sectionToken(section), in: key) { $0.staticTexts[section.rawValue] } ?? ""
    }

    func setStaticText(_ text: String, for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.staticTexts[section.rawValue] = text }
    }

    /// Resolved text for a built-in section, honoring its source override.
    /// Callers pass the four candidate field values (live, preview, or sample).
    func sectionText(
        _ section: TextBoxSection,
        main: String, reference: String, translation: String, subtitle: String,
        now: Date = .now, slideNumber: String = "", in key: String? = nil
    ) -> String {
        let autoValue: String
        switch section {
        case .verseContent: autoValue = main
        case .reference: autoValue = reference
        case .translationName: autoValue = translation
        case .subtitle: autoValue = subtitle
        // The chords box renders from `liveContent.songLines` directly; this text
        // only gates whether the box mounts (non-empty == there is a slide to chart).
        case .chords: autoValue = liveContent.songLines.contains { !$0.chords.isEmpty } ? main : ""
        }
        return Self.resolveBoxSource(
            sourceRaw(for: section, in: key),
            format: sourceFormat(for: section, in: key),
            autoValue: autoValue,
            staticText: staticText(for: section, in: key),
            main: main, reference: reference, translation: translation, subtitle: subtitle,
            now: now, slideNumber: slideNumber,
            songAuthor: liveContent.songAuthor, songCopyright: liveContent.songCopyright,
            songCCLI: liveContent.songCCLI, songbook: liveContent.songbook,
            songStyle: liveContent.songStyle, songKey: liveContent.songKey, songTempo: liveContent.songTempo,
            mediaURL: liveContent.mediaURL, mediaKind: liveContent.mediaKind
        )
    }

    func isSectionVisible(_ section: TextBoxSection, in key: String? = nil) -> Bool {
        let k = resolvedKey(key)
        return readBox(Self.sectionToken(section), in: k) { $0.visibility[section.rawValue] }
            ?? LayoutProfile.defaultProfile(for: k).visibility[section.rawValue]
            ?? true
    }

    func setSectionVisible(_ visible: Bool, for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.visibility[section.rawValue] = visible }
    }

    // MARK: - Slide Display Scope ("Amin." only on the last slide, title on the first)
    static let displayScopeOptions: [(raw: String, label: String)] = [
        ("all", String(localized: "Toate", comment: "Slide scope")),
        ("first", String(localized: "Primul", comment: "Slide scope")),
        ("last", String(localized: "Ultimul", comment: "Slide scope")),
    ]

    /// Songs additionally scope by section kind: only on the chorus (Refren /
    /// Chorus / Cor labels) or only on the verses.
    static func displayScopeOptions(for key: String) -> [(raw: String, label: String)] {
        guard key == "song" else { return displayScopeOptions }
        return displayScopeOptions + [
            ("chorus", String(localized: "Refren", comment: "Slide scope")),
            ("verses", String(localized: "Strofe", comment: "Slide scope")),
        ]
    }

    func displayScope(for section: TextBoxSection, in key: String? = nil) -> String {
        readBox(Self.sectionToken(section), in: key) { $0.displayOn[section.rawValue] } ?? "all"
    }

    func setDisplayScope(_ raw: String, for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.displayOn[section.rawValue] = raw }
    }

    /// Whether a scope is satisfied by the CURRENT live slide position.
    func scopeMatchesLiveSlide(_ raw: String) -> Bool {
        switch raw {
        case "first": return liveContent.isFirstSlide
        case "last": return liveContent.isLastSlide
        case "chorus": return liveContent.isChorusSlide
        case "verses": return !liveContent.isChorusSlide
        default: return true
        }
    }

    func resetBoxFrame(for section: TextBoxSection, in key: String? = nil) {
        mutateBox(Self.sectionToken(section), in: key) { $0.frames[section.rawValue] = Self.defaultFrame(for: section) }
    }

    func resetAllBoxFrames(in key: String? = nil) {
        for section in TextBoxSection.allCases {
            resetBoxFrame(for: section, in: key)
        }
    }

    /// Moves the presentation window to the currently selected screen.
    func applyScreenPosition() {
        let screens = NSScreen.screens

        if let idx = presentationScreenIndex, idx < screens.count {
            movePresentationWindow(to: screens[idx])
        } else if screens.count > 1, let external = screens.last {
            presentationScreenIndex = screens.count - 1
            movePresentationWindow(to: external)
        } else if let builtIn = screens.first {
            presentationScreenIndex = 0
            movePresentationWindow(to: builtIn)
        }
    }
}
