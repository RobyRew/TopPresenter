//
//  PresentationManager.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import Observation
import AppKit

@Observable
final class PresentationManager {
    // MARK: - Live Content
    var liveContent = LiveContent()

    /// Video playback service — set once at app start so clearOutput() can stop playback.
    @ObservationIgnored weak var videoService: VideoPlayerService?

    // MARK: - Style
    var currentStyle: PresentationStyle?

    // MARK: - Global Background
    var backgroundImage: NSImage?
    var backgroundImagePath: String? {
        didSet { UserDefaults.standard.set(backgroundImagePath, forKey: "pm_backgroundImagePath") }
    }
    var backgroundOpacity: Double {
        didSet { UserDefaults.standard.set(backgroundOpacity, forKey: "pm_backgroundOpacity") }
    }
    var useBackgroundImage: Bool {
        didSet { UserDefaults.standard.set(useBackgroundImage, forKey: "pm_useBackgroundImage") }
    }
    /// When false (default), the output window is fully transparent — no solid background.
    /// Enable this to show the background color behind content.
    var backgroundEnabled: Bool {
        didSet { UserDefaults.standard.set(backgroundEnabled, forKey: "pm_backgroundEnabled") }
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
    }

    var contentBackgrounds: [String: BackgroundConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(contentBackgrounds) {
                UserDefaults.standard.set(data, forKey: "pm_contentBackgrounds")
            }
        }
    }
    /// Decoded images for per-content backgrounds (loaded from bookmarks).
    var contentBackgroundImages: [String: NSImage] = [:]

    static func contentKey(for type: LiveContent.ContentType) -> String {
        switch type {
        case .bible: return "bible"
        case .song: return "song"
        default: return "text"
        }
    }

    static func contentKeyLabel(_ key: String) -> String {
        switch key {
        case "bible": return String(localized: "Biblie", comment: "Content type")
        case "song": return String(localized: "Cântece", comment: "Content type")
        default: return String(localized: "Slide-uri", comment: "Content type")
        }
    }

    func backgroundConfig(for key: String) -> BackgroundConfig {
        contentBackgrounds[key] ?? BackgroundConfig()
    }

    func setBackgroundConfig(_ config: BackgroundConfig, for key: String) {
        contentBackgrounds[key] = config
    }

    func setContentBackgroundImage(url: URL, for key: String) {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ), let image = NSImage(contentsOf: url) else { return }
        var config = backgroundConfig(for: key)
        config.imageBookmark = bookmark
        config.imageName = url.lastPathComponent
        config.useImage = true
        contentBackgrounds[key] = config
        contentBackgroundImages[key] = image
    }

    func removeContentBackgroundImage(for key: String) {
        var config = backgroundConfig(for: key)
        config.imageBookmark = nil
        config.imageName = ""
        config.useImage = false
        contentBackgrounds[key] = config
        contentBackgroundImages[key] = nil
    }

    private func loadContentBackgroundImages() {
        for (key, config) in contentBackgrounds {
            guard let bookmark = config.imageBookmark else { continue }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }
            let accessing = url.startAccessingSecurityScopedResource()
            if let image = NSImage(contentsOf: url) {
                contentBackgroundImages[key] = image
            }
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
    }

    /// The effective background for a content type: the per-content override when
    /// enabled, otherwise the global background (frozen-aware via the output accessors).
    struct ActiveBackground {
        var showColor: Bool
        var color: Color
        var opacity: Double
        var useImage: Bool
        var image: NSImage?
    }

    func activeBackground(for type: LiveContent.ContentType, frozen: Bool) -> ActiveBackground {
        let key = Self.contentKey(for: type)
        if let config = contentBackgrounds[key], config.enabled {
            return ActiveBackground(
                showColor: config.showColor,
                color: Color(hex: config.colorHex) ?? .black,
                opacity: config.opacity,
                useImage: config.useImage,
                image: contentBackgroundImages[key]
            )
        }
        if frozen {
            return ActiveBackground(
                showColor: frozenBackgroundEnabled,
                color: Color(hex: frozenBackgroundColorHex) ?? .black,
                opacity: frozenBackgroundOpacity,
                useImage: frozenUseBackgroundImage,
                image: frozenBackgroundImage
            )
        }
        return ActiveBackground(
            showColor: backgroundEnabled,
            color: backgroundColor,
            opacity: backgroundOpacity,
            useImage: useBackgroundImage,
            image: backgroundImage
        )
    }

    // MARK: - Global Text Settings
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: "pm_fontSize") }
    }
    var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: "pm_fontName") }
    }
    var textColorHex: String {
        didSet { UserDefaults.standard.set(textColorHex, forKey: "pm_textColorHex") }
    }
    var backgroundColorHex: String {
        didSet { UserDefaults.standard.set(backgroundColorHex, forKey: "pm_backgroundColorHex") }
    }
    var textAlignment: TextAlignment {
        didSet { UserDefaults.standard.set(Self.alignmentRaw(textAlignment), forKey: "pm_textAlignmentRaw") }
    }
    var lineSpacing: Double {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: "pm_lineSpacing") }
    }
    var padding: Double {
        didSet { UserDefaults.standard.set(padding, forKey: "pm_padding") }
    }
    var shadowEnabled: Bool {
        didSet { UserDefaults.standard.set(shadowEnabled, forKey: "pm_shadowEnabled") }
    }
    var shadowRadius: Double {
        didSet { UserDefaults.standard.set(shadowRadius, forKey: "pm_shadowRadius") }
    }
    var transitionDuration: Double {
        didSet { UserDefaults.standard.set(transitionDuration, forKey: "pm_transitionDuration") }
    }
    /// Global font weight baseline — applied to every box whose section default
    /// is regular (reference keeps its semibold design default unless customized).
    var globalWeightRaw: String {
        didSet { UserDefaults.standard.set(globalWeightRaw, forKey: "pm_globalWeightRaw") }
    }
    /// Global vertical alignment — inherited by every box that hasn't set its own.
    var globalVAlignRaw: String {
        didSet { UserDefaults.standard.set(globalVAlignRaw, forKey: "pm_globalVAlignRaw") }
    }
    /// Global text opacity — multiplied into every non-customized box's opacity.
    var globalTextOpacity: Double {
        didSet { UserDefaults.standard.set(globalTextOpacity, forKey: "pm_globalTextOpacity") }
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
        didSet { UserDefaults.standard.set(windowLevel, forKey: "pm_windowLevel") }
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
    var screenDisconnectAction: ScreenDisconnectAction {
        get {
            ScreenDisconnectAction(rawValue: UserDefaults.standard.string(forKey: "pm_screenDisconnectAction") ?? "ask") ?? .ask
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "pm_screenDisconnectAction")
        }
    }

    /// Whether the "screen disconnected" alert should be shown.
    var showScreenDisconnectedAlert: Bool = false

    /// Monitors screen configuration changes.
    private var screenObserver: (any NSObjectProtocol)?

    func startScreenMonitoring() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleScreenConfigurationChange()
        }
    }

    func stopScreenMonitoring() {
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
    }

    deinit {
        stopScreenMonitoring()
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

        guard wasTargetLost && isPresentationWindowOpen else {
            // Screen added or target still valid — just reposition
            if let idx = presentationScreenIndex, idx < availableScreens.count {
                movePresentationWindow(to: availableScreens[idx])
            }
            return
        }

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
            if let builtIn = builtInScreen {
                presentationScreenIndex = 0
                movePresentationWindow(to: builtIn)
            }
            showScreenDisconnectedAlert = true
        }
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
        didSet { UserDefaults.standard.set(autoFitVerseFont, forKey: "pm_autoFitVerseFont") }
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

        func font(at scaledSize: CGFloat) -> Font {
            (fontName.isEmpty || fontName == "System")
                ? .system(size: scaledSize, weight: weight)
                : .custom(fontName, size: scaledSize)
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
        }
    }

    static let customBoxSizeFactor: Double = 0.5

    var verseStyle: BoxTextStyle {
        didSet { persistStyle(verseStyle, key: "pm_verseStyle") }
    }
    var refStyle: BoxTextStyle {
        didSet { persistStyle(refStyle, key: "pm_refStyle") }
    }
    var translationStyle: BoxTextStyle {
        didSet { persistStyle(translationStyle, key: "pm_translationStyle") }
    }
    var subtitleStyle: BoxTextStyle {
        didSet { persistStyle(subtitleStyle, key: "pm_subtitleStyle") }
    }

    private func persistStyle(_ style: BoxTextStyle, key: String) {
        if let data = try? JSONEncoder().encode(style) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func decodeStyle(from defaults: UserDefaults, key: String) -> BoxTextStyle {
        guard let data = defaults.data(forKey: key),
              let style = try? JSONDecoder().decode(BoxTextStyle.self, from: data) else {
            return BoxTextStyle()
        }
        return style
    }

    func boxStyle(for section: TextBoxSection) -> BoxTextStyle {
        switch section {
        case .verseContent: return verseStyle
        case .reference: return refStyle
        case .translationName: return translationStyle
        case .subtitle: return subtitleStyle
        }
    }

    func setBoxStyle(_ style: BoxTextStyle, for section: TextBoxSection) {
        registerLayoutUndo()
        switch section {
        case .verseContent: verseStyle = style
        case .reference: refStyle = style
        case .translationName: translationStyle = style
        case .subtitle: subtitleStyle = style
        }
    }

    /// Resolves a BoxTextStyle against the globals + the given defaults.
    private func resolve(_ style: BoxTextStyle, sizeFactor: Double, defaultWeight: Font.Weight, defaultOpacity: Double) -> ResolvedBoxStyle {
        let globalFontName = (fontName == "System") ? "" : fontName
        // Section defaults of .regular inherit the global weight baseline;
        // design defaults (reference = semibold) stay unless customized.
        let inheritedWeight: Font.Weight = (defaultWeight == .regular)
            ? BoxTextStyle.weight(fromRaw: globalWeightRaw, fallback: .regular)
            : defaultWeight
        guard style.isCustomized else {
            return ResolvedBoxStyle(
                fontName: globalFontName,
                fontSize: fontSize * sizeFactor,
                weight: inheritedWeight,
                color: textColor,
                opacity: defaultOpacity * globalTextOpacity,
                hAlign: textAlignment,
                vAlignRaw: style.vAlignRaw.isEmpty ? globalVAlignRaw : style.vAlignRaw,
                lineSpacing: lineSpacing
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
            lineSpacing: style.lineSpacing >= 0 ? style.lineSpacing : lineSpacing
        )
    }

    func resolvedStyle(for section: TextBoxSection) -> ResolvedBoxStyle {
        let defaults = Self.styleDefaults(for: section)
        return resolve(boxStyle(for: section), sizeFactor: defaults.sizeFactor, defaultWeight: defaults.weight, defaultOpacity: defaults.opacity)
    }

    func resolvedCustomStyle(_ box: CustomTextBox) -> ResolvedBoxStyle {
        resolve(box.style, sizeFactor: Self.customBoxSizeFactor, defaultWeight: .regular, defaultOpacity: 1.0)
    }

    /// Turns customization on and seeds the editable fields with the current
    /// effective values, so the controls show reality instead of zeros.
    func enableStyleCustomization(for section: TextBoxSection) {
        var style = boxStyle(for: section)
        guard !style.isCustomized else { return }
        let resolved = resolvedStyle(for: section)
        style.isCustomized = true
        style.fontSize = resolved.fontSize
        style.weightRaw = BoxTextStyle.weightRaw(resolved.weight)
        style.opacity = resolved.opacity
        style.vAlignRaw = resolved.vAlignRaw
        setBoxStyle(style, for: section)
    }

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
        /// "static" | "mainText" | "reference" | "translation" | "subtitle" | "date" | "time"
        var sourceRaw: String = "static"
        /// Format for date/time sources (see formattedClock).
        var sourceFormatRaw: String = ""

        func resolvedText(main: String, reference: String, translation: String, subtitle: String, now: Date = .now) -> String {
            PresentationManager.resolveBoxSource(
                sourceRaw, format: sourceFormatRaw, autoValue: text, staticText: text,
                main: main, reference: reference, translation: translation, subtitle: subtitle, now: now
            )
        }

        func resolvedText(live: LiveContent, now: Date = .now) -> String {
            resolvedText(
                main: live.mainText, reference: live.reference,
                translation: live.translationName, subtitle: live.subtitle, now: now
            )
        }

        var sourceLabel: String { PresentationManager.sourceOptionLabel(sourceRaw) }
    }

    var customTextBoxes: [CustomTextBox] {
        didSet {
            if let data = try? JSONEncoder().encode(customTextBoxes) {
                UserDefaults.standard.set(data, forKey: "pm_customTextBoxes")
            }
        }
    }

    func addCustomTextBox() -> CustomTextBox {
        registerLayoutUndo()
        var box = CustomTextBox()
        box.text = String(localized: "Text nou", comment: "Default text of a newly added custom text box")
        let offset = Double(customTextBoxes.count % 5) * 0.04
        box.frame = TextBoxFrame(x: 0.30 + offset, y: 0.42 + offset, width: 0.40, height: 0.12).clamped()
        customTextBoxes.append(box)
        return box
    }

    func removeCustomTextBox(id: UUID) {
        registerLayoutUndo()
        customTextBoxes.removeAll { $0.id == id }
    }

    func customTextBox(id: UUID) -> CustomTextBox? {
        customTextBoxes.first { $0.id == id }
    }

    func updateCustomTextBox(_ box: CustomTextBox) {
        guard let idx = customTextBoxes.firstIndex(where: { $0.id == box.id }) else { return }
        registerLayoutUndo()
        var clamped = box
        clamped.frame = box.frame.clamped()
        customTextBoxes[idx] = clamped
    }

    /// Duplicates a custom text box (new id, slightly offset frame).
    func duplicateCustomTextBox(id: UUID) -> CustomTextBox? {
        guard var copy = customTextBox(id: id) else { return nil }
        registerLayoutUndo()
        copy.id = UUID()
        copy.frame = TextBoxFrame(
            x: copy.frame.x + 0.03, y: copy.frame.y + 0.03,
            width: copy.frame.width, height: copy.frame.height
        ).clamped()
        customTextBoxes.append(copy)
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
        /// When to show: "always" | "bible" | "song" | "text"
        var showOnRaw: String = "always"
        var isVisible: Bool = true

        func resolvedURL() -> URL? {
            guard let data = bookmarkData else { return nil }
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
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

    var mediaBoxes: [MediaBox] {
        didSet {
            if let data = try? JSONEncoder().encode(mediaBoxes) {
                UserDefaults.standard.set(data, forKey: "pm_mediaBoxes")
            }
        }
    }

    @discardableResult
    func addMediaBox(url: URL) -> MediaBox? {
        guard let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }

        registerLayoutUndo()
        var box = MediaBox()
        box.fileName = url.lastPathComponent
        box.bookmarkData = bookmark
        let ext = url.pathExtension.lowercased()
        if ext == "gif" {
            box.mediaTypeRaw = "gif"
        } else if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) {
            box.mediaTypeRaw = "video"
        } else {
            box.mediaTypeRaw = "image"
        }
        let offset = Double(mediaBoxes.count % 4) * 0.04
        box.frame = TextBoxFrame(x: 0.74 - offset, y: 0.05 + offset, width: 0.20, height: 0.18).clamped()
        mediaBoxes.append(box)
        return box
    }

    func removeMediaBox(id: UUID) {
        registerLayoutUndo()
        mediaBoxes.removeAll { $0.id == id }
    }

    func mediaBox(id: UUID) -> MediaBox? {
        mediaBoxes.first { $0.id == id }
    }

    func updateMediaBox(_ box: MediaBox) {
        guard let idx = mediaBoxes.firstIndex(where: { $0.id == box.id }) else { return }
        registerLayoutUndo()
        var clamped = box
        clamped.frame = box.frame.clamped()
        mediaBoxes[idx] = clamped
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

    // MARK: - Box Frames
    var verseBoxFrame: TextBoxFrame {
        didSet { verseBoxFrame.persist(to: UserDefaults.standard, key: "pm_verseBoxFrame") }
    }
    var refBoxFrame: TextBoxFrame {
        didSet { refBoxFrame.persist(to: UserDefaults.standard, key: "pm_refBoxFrame") }
    }
    var translationBoxFrame: TextBoxFrame {
        didSet { translationBoxFrame.persist(to: UserDefaults.standard, key: "pm_translationBoxFrame") }
    }
    var subtitleBoxFrame: TextBoxFrame {
        didSet { subtitleBoxFrame.persist(to: UserDefaults.standard, key: "pm_subtitleBoxFrame") }
    }

    // MARK: - Box Content Sources
    /// Per-section content source override. "auto" (default) = the box's natural field.
    var verseSourceRaw: String {
        didSet { UserDefaults.standard.set(verseSourceRaw, forKey: "pm_verseSourceRaw") }
    }
    var refSourceRaw: String {
        didSet { UserDefaults.standard.set(refSourceRaw, forKey: "pm_refSourceRaw") }
    }
    var translationSourceRaw: String {
        didSet { UserDefaults.standard.set(translationSourceRaw, forKey: "pm_translationSourceRaw") }
    }
    var subtitleSourceRaw: String {
        didSet { UserDefaults.standard.set(subtitleSourceRaw, forKey: "pm_subtitleSourceRaw") }
    }
    /// Static text per section (used when the section's source is "static").
    var verseStaticText: String {
        didSet { UserDefaults.standard.set(verseStaticText, forKey: "pm_verseStaticText") }
    }
    var refStaticText: String {
        didSet { UserDefaults.standard.set(refStaticText, forKey: "pm_refStaticText") }
    }
    var translationStaticText: String {
        didSet { UserDefaults.standard.set(translationStaticText, forKey: "pm_translationStaticText") }
    }
    var subtitleStaticText: String {
        didSet { UserDefaults.standard.set(subtitleStaticText, forKey: "pm_subtitleStaticText") }
    }
    /// Date/time display format per section (when source is "date"/"time").
    var verseSourceFormat: String {
        didSet { UserDefaults.standard.set(verseSourceFormat, forKey: "pm_verseSourceFormat") }
    }
    var refSourceFormat: String {
        didSet { UserDefaults.standard.set(refSourceFormat, forKey: "pm_refSourceFormat") }
    }
    var translationSourceFormat: String {
        didSet { UserDefaults.standard.set(translationSourceFormat, forKey: "pm_translationSourceFormat") }
    }
    var subtitleSourceFormat: String {
        didSet { UserDefaults.standard.set(subtitleSourceFormat, forKey: "pm_subtitleSourceFormat") }
    }

    /// Formats the date/time sources. Date formats: "" (long) | "short" | "weekday".
    /// Time formats: "" (HH:MM) | "hms" (HH:MM:SS).
    static func formattedClock(source: String, format: String, now: Date) -> String {
        switch source {
        case "date":
            switch format {
            case "short": return now.formatted(date: .numeric, time: .omitted)
            case "weekday": return now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
            default: return now.formatted(date: .long, time: .omitted)
            }
        case "time":
            switch format {
            case "hms":
                return now.formatted(
                    .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)
                )
            default:
                return now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
            }
        default:
            return ""
        }
    }

    /// Shared source resolution for built-in sections and custom boxes.
    static func resolveBoxSource(
        _ raw: String, format: String = "", autoValue: String, staticText: String,
        main: String, reference: String, translation: String, subtitle: String, now: Date = .now
    ) -> String {
        switch raw {
        case "mainText": return main
        case "reference": return reference
        case "translation": return translation
        case "subtitle": return subtitle
        case "static": return staticText
        case "date", "time": return formattedClock(source: raw, format: format, now: now)
        default: return autoValue // "auto"
        }
    }

    static func sourceOptionLabel(_ raw: String) -> String {
        switch raw {
        case "mainText": return String(localized: "Text verset (live)", comment: "Box source")
        case "reference": return String(localized: "Referință (live)", comment: "Box source")
        case "translation": return String(localized: "Traducere (live)", comment: "Box source")
        case "subtitle": return String(localized: "Subtitlu (live)", comment: "Box source")
        case "date": return String(localized: "Data curentă", comment: "Box source")
        case "time": return String(localized: "Ora curentă", comment: "Box source")
        case "static": return String(localized: "Text static", comment: "Box source")
        default: return String(localized: "Implicit (auto)", comment: "Box source")
        }
    }

    /// How often the output needs to re-render for live clocks:
    /// nil = no clock boxes, 60 = minute precision, 1 = seconds shown.
    var clockTickInterval: TimeInterval? {
        var interval: TimeInterval? = nil
        func consider(source: String, format: String) {
            if source == "time" && format == "hms" { interval = 1 }
            else if (source == "time" || source == "date") && interval == nil { interval = 60 }
        }
        for section in TextBoxSection.allCases where isSectionVisible(section) {
            consider(source: sourceRaw(for: section), format: sourceFormat(for: section))
        }
        for box in customTextBoxes where box.isVisible {
            consider(source: box.sourceRaw, format: box.sourceFormatRaw)
        }
        return interval
    }

    // MARK: - Per-Section Visibility
    var verseBoxVisible: Bool {
        didSet { UserDefaults.standard.set(verseBoxVisible, forKey: "pm_verseBoxVisible") }
    }
    var refBoxVisible: Bool {
        didSet { UserDefaults.standard.set(refBoxVisible, forKey: "pm_refBoxVisible") }
    }
    var translationBoxVisible: Bool {
        didSet { UserDefaults.standard.set(translationBoxVisible, forKey: "pm_translationBoxVisible") }
    }
    var subtitleBoxVisible: Bool {
        didSet { UserDefaults.standard.set(subtitleBoxVisible, forKey: "pm_subtitleBoxVisible") }
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
    var boxOrder: [String] {
        didSet { UserDefaults.standard.set(boxOrder, forKey: "pm_boxOrder") }
    }

    /// All valid tokens for the current boxes, in canonical default order
    /// (media at the back, then the four sections, then custom boxes).
    private var canonicalTokens: [String] {
        mediaBoxes.map { "media:" + $0.id.uuidString }
            + TextBoxSection.allCases.map { "section:" + $0.rawValue }
            + customTextBoxes.map { "custom:" + $0.id.uuidString }
    }

    /// The reconciled render order: stored order minus stale tokens, plus any
    /// new boxes appended on top. Pure — never mutates state (safe in view body).
    func orderedBoxTokens() -> [String] {
        let valid = Set(canonicalTokens)
        var result = boxOrder.filter { valid.contains($0) }
        let present = Set(result)
        for token in canonicalTokens where !present.contains(token) {
            result.append(token)
        }
        return result
    }

    private func normalizeBoxOrder() {
        let ordered = orderedBoxTokens()
        if ordered != boxOrder { boxOrder = ordered }
    }

    func moveBoxToken(_ token: String, offset: Int) {
        registerLayoutUndo()
        normalizeBoxOrder()
        guard let idx = boxOrder.firstIndex(of: token) else { return }
        let newIdx = min(max(idx + offset, 0), boxOrder.count - 1)
        guard newIdx != idx else { return }
        boxOrder.remove(at: idx)
        boxOrder.insert(token, at: newIdx)
    }

    func moveBoxTokenToEdge(_ token: String, front: Bool) {
        registerLayoutUndo()
        normalizeBoxOrder()
        guard let idx = boxOrder.firstIndex(of: token) else { return }
        boxOrder.remove(at: idx)
        if front { boxOrder.append(token) } else { boxOrder.insert(token, at: 0) }
    }

    /// Places `token` directly ABOVE `target` in the stacking order
    /// (list drops: the dragged row takes the visual slot above the target).
    func reorderBoxToken(_ token: String, above target: String) {
        guard token != target else { return }
        registerLayoutUndo()
        normalizeBoxOrder()
        guard let from = boxOrder.firstIndex(of: token) else { return }
        boxOrder.remove(at: from)
        let to = boxOrder.firstIndex(of: target).map { $0 + 1 } ?? boxOrder.count
        boxOrder.insert(token, at: to)
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
        var payload: ThemePayload
    }

    struct ThemePayload: Codable, Equatable {
        // Global text
        var fontSize: Double
        var fontName: String
        var textColorHex: String
        var textAlignmentRaw: String
        var lineSpacing: Double
        var padding: Double
        var shadowEnabled: Bool
        var shadowRadius: Double
        var autoFitVerseFont: Bool
        var globalWeightRaw: String
        var globalVAlignRaw: String
        var globalTextOpacity: Double
        // Global background
        var backgroundEnabled: Bool
        var backgroundColorHex: String
        var backgroundOpacity: Double
        var useBackgroundImage: Bool
        var backgroundImageBookmark: Data?
        var contentBackgrounds: [String: BackgroundConfig]
        // Boxes
        var frames: [String: TextBoxFrame]
        var visibility: [String: Bool]
        var styles: [String: BoxTextStyle]
        var sources: [String: String]
        var sourceFormats: [String: String]
        var staticTexts: [String: String]
        var customTextBoxes: [CustomTextBox]
        var mediaBoxes: [MediaBox]
        var boxOrder: [String]
    }

    var themes: [Theme] {
        didSet {
            if let data = try? JSONEncoder().encode(themes) {
                UserDefaults.standard.set(data, forKey: "pm_themes")
            }
        }
    }
    var activeThemeID: UUID? {
        didSet { UserDefaults.standard.set(activeThemeID?.uuidString ?? "", forKey: "pm_activeThemeID") }
    }

    /// Captures the entire current look into a payload.
    private func captureThemePayload() -> ThemePayload {
        var frames: [String: TextBoxFrame] = [:]
        var visibility: [String: Bool] = [:]
        var styles: [String: BoxTextStyle] = [:]
        var sources: [String: String] = [:]
        var formats: [String: String] = [:]
        var statics: [String: String] = [:]
        for section in TextBoxSection.allCases {
            frames[section.rawValue] = boxFrame(for: section)
            visibility[section.rawValue] = isSectionVisible(section)
            styles[section.rawValue] = boxStyle(for: section)
            sources[section.rawValue] = sourceRaw(for: section)
            formats[section.rawValue] = sourceFormat(for: section)
            statics[section.rawValue] = staticText(for: section)
        }
        return ThemePayload(
            fontSize: fontSize,
            fontName: fontName,
            textColorHex: textColorHex,
            textAlignmentRaw: Self.alignmentRaw(textAlignment),
            lineSpacing: lineSpacing,
            padding: padding,
            shadowEnabled: shadowEnabled,
            shadowRadius: shadowRadius,
            autoFitVerseFont: autoFitVerseFont,
            globalWeightRaw: globalWeightRaw,
            globalVAlignRaw: globalVAlignRaw,
            globalTextOpacity: globalTextOpacity,
            backgroundEnabled: backgroundEnabled,
            backgroundColorHex: backgroundColorHex,
            backgroundOpacity: backgroundOpacity,
            useBackgroundImage: useBackgroundImage,
            backgroundImageBookmark: UserDefaults.standard.data(forKey: "pm_backgroundImageBookmark"),
            contentBackgrounds: contentBackgrounds,
            frames: frames,
            visibility: visibility,
            styles: styles,
            sources: sources,
            sourceFormats: formats,
            staticTexts: statics,
            customTextBoxes: customTextBoxes,
            mediaBoxes: mediaBoxes,
            boxOrder: orderedBoxTokens()
        )
    }

    @discardableResult
    func saveCurrentAsTheme(named name: String) -> Theme {
        let theme = Theme(name: name, payload: captureThemePayload())
        themes.append(theme)
        activeThemeID = theme.id
        return theme
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

    func deleteTheme(id: UUID) {
        themes.removeAll { $0.id == id }
        if activeThemeID == id { activeThemeID = nil }
    }

    func applyTheme(id: UUID) {
        guard let theme = themes.first(where: { $0.id == id }) else { return }
        registerLayoutUndo()
        applyPayload(theme.payload)
        activeThemeID = id
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
        autoFitVerseFont = p.autoFitVerseFont
        globalWeightRaw = p.globalWeightRaw
        globalVAlignRaw = p.globalVAlignRaw
        globalTextOpacity = p.globalTextOpacity
        backgroundEnabled = p.backgroundEnabled
        backgroundColorHex = p.backgroundColorHex
        backgroundOpacity = p.backgroundOpacity
        useBackgroundImage = p.useBackgroundImage
        if let bookmark = p.backgroundImageBookmark {
            UserDefaults.standard.set(bookmark, forKey: "pm_backgroundImageBookmark")
            restoreBackgroundImage(from: bookmark)
        } else {
            backgroundImage = nil
            backgroundImagePath = nil
            UserDefaults.standard.removeObject(forKey: "pm_backgroundImageBookmark")
        }
        contentBackgrounds = p.contentBackgrounds
        loadContentBackgroundImages()
        for section in TextBoxSection.allCases {
            if let frame = p.frames[section.rawValue] { setBoxFrame(frame, for: section) }
            if let visible = p.visibility[section.rawValue] { setSectionVisible(visible, for: section) }
            if let style = p.styles[section.rawValue] { setBoxStyle(style, for: section) }
            if let source = p.sources[section.rawValue] { setSourceRaw(source, for: section) }
            if let format = p.sourceFormats[section.rawValue] { setSourceFormat(format, for: section) }
            if let text = p.staticTexts[section.rawValue] { setStaticText(text, for: section) }
        }
        customTextBoxes = p.customTextBoxes
        mediaBoxes = p.mediaBoxes
        boxOrder = p.boxOrder
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
        isFrozen ? (frozenFrames[section.rawValue] ?? boxFrame(for: section)) : boxFrame(for: section)
    }

    func outputStyle(for section: TextBoxSection) -> ResolvedBoxStyle {
        isFrozen ? (frozenStyles[section.rawValue] ?? resolvedStyle(for: section)) : resolvedStyle(for: section)
    }

    var outputCustomTextBoxes: [CustomTextBox] { isFrozen ? frozenCustomBoxes : customTextBoxes }
    var outputMediaBoxes: [MediaBox] { isFrozen ? frozenMediaBoxes : mediaBoxes }
    // Visibility (not frozen — hiding a box mid-freeze is an operator action)
    func outputSectionVisible(_ section: TextBoxSection) -> Bool { isSectionVisible(section) }

    // MARK: - Init (restore from UserDefaults)
    init() {
        let d = UserDefaults.standard
        self.fontSize = d.object(forKey: "pm_fontSize") as? Double ?? PresentationDefaults.fontSize
        self.fontName = d.string(forKey: "pm_fontName") ?? PresentationDefaults.fontName
        self.textColorHex = d.string(forKey: "pm_textColorHex") ?? PresentationDefaults.textColor
        self.backgroundColorHex = d.string(forKey: "pm_backgroundColorHex") ?? PresentationDefaults.backgroundColor
        self.textAlignment = Self.alignment(fromRaw: d.string(forKey: "pm_textAlignmentRaw") ?? "center")
        self.lineSpacing = d.object(forKey: "pm_lineSpacing") as? Double ?? PresentationDefaults.lineSpacing
        self.padding = d.object(forKey: "pm_padding") as? Double ?? PresentationDefaults.padding
        self.shadowEnabled = d.object(forKey: "pm_shadowEnabled") as? Bool ?? true
        self.shadowRadius = d.object(forKey: "pm_shadowRadius") as? Double ?? 3.0
        self.transitionDuration = d.object(forKey: "pm_transitionDuration") as? Double ?? PresentationDefaults.transitionDuration
        self.globalWeightRaw = d.string(forKey: "pm_globalWeightRaw") ?? "regular"
        self.globalVAlignRaw = d.string(forKey: "pm_globalVAlignRaw") ?? "center"
        self.globalTextOpacity = d.object(forKey: "pm_globalTextOpacity") as? Double ?? 1.0
        self.backgroundOpacity = d.object(forKey: "pm_backgroundOpacity") as? Double ?? PresentationDefaults.backgroundOpacity
        self.useBackgroundImage = d.bool(forKey: "pm_useBackgroundImage")
        self.backgroundEnabled = d.bool(forKey: "pm_backgroundEnabled") // defaults to false = transparent
        self.windowLevel = d.string(forKey: "pm_windowLevel") ?? "alwaysOnTop"
        self.autoFitVerseFont = d.bool(forKey: "pm_autoFitVerseFont")
        self.boxOrder = d.stringArray(forKey: "pm_boxOrder") ?? []
        // Custom text boxes
        if let data = d.data(forKey: "pm_customTextBoxes"),
           let boxes = try? JSONDecoder().decode([CustomTextBox].self, from: data) {
            self.customTextBoxes = boxes
        } else {
            self.customTextBoxes = []
        }
        // Media boxes
        if let data = d.data(forKey: "pm_mediaBoxes"),
           let boxes = try? JSONDecoder().decode([MediaBox].self, from: data) {
            self.mediaBoxes = boxes
        } else {
            self.mediaBoxes = []
        }
        // Per-content backgrounds
        if let data = d.data(forKey: "pm_contentBackgrounds"),
           let configs = try? JSONDecoder().decode([String: BackgroundConfig].self, from: data) {
            self.contentBackgrounds = configs
        } else {
            self.contentBackgrounds = [:]
        }
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
        // Section visibility — translation & subtitle hidden by default
        self.verseBoxVisible = d.object(forKey: "pm_verseBoxVisible") as? Bool ?? true
        self.refBoxVisible = d.object(forKey: "pm_refBoxVisible") as? Bool ?? true
        self.translationBoxVisible = d.object(forKey: "pm_translationBoxVisible") as? Bool ?? false
        self.subtitleBoxVisible = d.object(forKey: "pm_subtitleBoxVisible") as? Bool ?? false
        // Section content sources ("auto" = natural field)
        self.verseSourceRaw = d.string(forKey: "pm_verseSourceRaw") ?? "auto"
        self.refSourceRaw = d.string(forKey: "pm_refSourceRaw") ?? "auto"
        self.translationSourceRaw = d.string(forKey: "pm_translationSourceRaw") ?? "auto"
        self.subtitleSourceRaw = d.string(forKey: "pm_subtitleSourceRaw") ?? "auto"
        self.verseStaticText = d.string(forKey: "pm_verseStaticText") ?? ""
        self.refStaticText = d.string(forKey: "pm_refStaticText") ?? ""
        self.translationStaticText = d.string(forKey: "pm_translationStaticText") ?? ""
        self.subtitleStaticText = d.string(forKey: "pm_subtitleStaticText") ?? ""
        self.verseSourceFormat = d.string(forKey: "pm_verseSourceFormat") ?? ""
        self.refSourceFormat = d.string(forKey: "pm_refSourceFormat") ?? ""
        self.translationSourceFormat = d.string(forKey: "pm_translationSourceFormat") ?? ""
        self.subtitleSourceFormat = d.string(forKey: "pm_subtitleSourceFormat") ?? ""
        // Fixed text boxes
        self.verseBoxFrame = TextBoxFrame.decode(from: d, key: "pm_verseBoxFrame", fallback: .defaultVerse)
        self.refBoxFrame = TextBoxFrame.decode(from: d, key: "pm_refBoxFrame", fallback: .defaultReference)
        self.translationBoxFrame = TextBoxFrame.decode(from: d, key: "pm_translationBoxFrame", fallback: .defaultTranslation)
        self.subtitleBoxFrame = TextBoxFrame.decode(from: d, key: "pm_subtitleBoxFrame", fallback: .defaultSubtitle)
        // Uniform box styles
        self.verseStyle = Self.decodeStyle(from: d, key: "pm_verseStyle")
        self.refStyle = Self.decodeStyle(from: d, key: "pm_refStyle")
        self.translationStyle = Self.decodeStyle(from: d, key: "pm_translationStyle")
        self.subtitleStyle = Self.decodeStyle(from: d, key: "pm_subtitleStyle")

        // Restore background image — security-scoped bookmark first (required in the
        // sandbox after relaunch), raw path as fallback for pre-bookmark installs.
        if let bookmark = d.data(forKey: "pm_backgroundImageBookmark") {
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
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        if let image = NSImage(contentsOf: url) {
            self.backgroundImagePath = url.path
            self.backgroundImage = image
            if isStale, let fresh = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: "pm_backgroundImageBookmark")
            }
        }
        if accessing { url.stopAccessingSecurityScopedResource() }
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
        for section in TextBoxSection.allCases {
            frozenFrames[section.rawValue] = boxFrame(for: section)
            frozenStyles[section.rawValue] = resolvedStyle(for: section)
        }
        frozenCustomBoxes = customTextBoxes
        frozenMediaBoxes = mediaBoxes
    }

    func clearOutput() {
        liveContent.clear()
        isBlackScreen = false
        isFrozen = false
        videoService?.stop()
        if isSingleScreenMode {
            hidePresentationWindow()
        }
    }

    func showBibleVerse(text: String, reference: String, translationName: String = "") {
        guard !isFrozen else { return }
        showPresentationWindow()
        liveContent.setBibleVerse(text: text, reference: reference, translationName: translationName)
        liveContent.isLive = true
        isBlackScreen = false
    }

    func showSongVerse(text: String, title: String, verseLabel: String) {
        guard !isFrozen else { return }
        showPresentationWindow()
        liveContent.setSongVerse(text: text, title: title, verseLabel: verseLabel)
        liveContent.isLive = true
        isBlackScreen = false
    }

    func showCustomText(text: String, title: String) {
        guard !isFrozen else { return }
        showPresentationWindow()
        liveContent.setCustomText(text: text, title: title)
        liveContent.isLive = true
        isBlackScreen = false
    }

    /// Marks the output as showing full-screen video.
    func showVideo() {
        guard !isFrozen else { return }
        showPresentationWindow()
        liveContent.setVideo()
        liveContent.isLive = true
        isBlackScreen = false
    }

    func setBackgroundImage(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            backgroundImage = image
            backgroundImagePath = url.path
            useBackgroundImage = true
            if let bookmark = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmark, forKey: "pm_backgroundImageBookmark")
            }
        }
    }

    func removeBackgroundImage() {
        backgroundImage = nil
        backgroundImagePath = nil
        useBackgroundImage = false
        UserDefaults.standard.removeObject(forKey: "pm_backgroundImageBookmark")
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

    /// Positions the presentation window on the specified screen
    func positionOnScreen(_ screen: NSScreen) {
        presentationScreenIndex = NSScreen.screens.firstIndex(of: screen)
        movePresentationWindow(to: screen)
    }

    /// The presentation NSWindow, found by its identifier.
    private var presentationWindow: NSWindow? {
        NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == WindowIdentifiers.presentation
        })
    }

    /// Hides the presentation window (used when clearing output on the built-in screen).
    func hidePresentationWindow() {
        presentationWindow?.orderOut(nil)
    }

    /// Shows the presentation window if it is not visible.
    func showPresentationWindow() {
        guard let window = presentationWindow, !window.isVisible else { return }
        window.orderFront(nil)
    }

    /// Moves the presentation window to fill the given screen.
    func movePresentationWindow(to screen: NSScreen) {
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

    /// Cache key for the last auto-fit computation. The binary search below measures
    /// text up to 17 times — without this, every SwiftUI body evaluation of the output
    /// AND the preview card would redo all that text layout work.
    private struct FitCacheKey: Equatable {
        let text: String
        let boxSize: CGSize
        let maxSize: Double
        let fontName: String
        let lineSpacing: Double
        let padding: Double
    }
    @ObservationIgnored private var fitCacheKey: FitCacheKey?
    @ObservationIgnored private var fitCacheValue: CGFloat = 0

    /// Returns the largest font size ≤ `maxSize` at which the verse text fits inside
    /// the given box. Pass `maxSize`/`padding` already scaled by the screen's font
    /// scale, and the style's fontName/lineSpacing, so the computation matches what
    /// gets rendered. Falls back to `maxSize` when autoFitVerseFont is off.
    func fittedVerseFontSize(
        text: String, boxSize: CGSize, maxSize: CGFloat, padding: CGFloat,
        fontName: String, lineSpacing: Double
    ) -> CGFloat {
        guard autoFitVerseFont, !text.isEmpty else { return maxSize }

        let key = FitCacheKey(
            text: text, boxSize: boxSize, maxSize: maxSize,
            fontName: fontName, lineSpacing: lineSpacing, padding: padding
        )
        if key == fitCacheKey { return fitCacheValue }

        let minSize: CGFloat = 10.0
        var result = maxSize
        if !verseFits(text: text, size: maxSize, boxSize: boxSize, padding: padding, fontName: fontName, lineSpacing: lineSpacing) {
            var lo = minSize
            var hi = maxSize
            var best = minSize
            for _ in 0..<16 {
                let mid = (lo + hi) / 2.0
                if verseFits(text: text, size: mid, boxSize: boxSize, padding: padding, fontName: fontName, lineSpacing: lineSpacing) {
                    best = mid
                    lo = mid
                } else {
                    hi = mid
                }
            }
            result = max(best, minSize)
        }

        fitCacheKey = key
        fitCacheValue = result
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
        let box = outputBoxFrame(for: .verseContent)
        return CGSize(width: screen.width * box.width, height: screen.height * box.height)
    }

    // MARK: - Box Frame / Source / Visibility Access (by section)

    func boxFrame(for section: TextBoxSection) -> TextBoxFrame {
        switch section {
        case .verseContent: return verseBoxFrame
        case .reference: return refBoxFrame
        case .translationName: return translationBoxFrame
        case .subtitle: return subtitleBoxFrame
        }
    }

    func setBoxFrame(_ frame: TextBoxFrame, for section: TextBoxSection) {
        registerLayoutUndo()
        let clamped = frame.clamped()
        switch section {
        case .verseContent: verseBoxFrame = clamped
        case .reference: refBoxFrame = clamped
        case .translationName: translationBoxFrame = clamped
        case .subtitle: subtitleBoxFrame = clamped
        }
    }

    func sourceRaw(for section: TextBoxSection) -> String {
        switch section {
        case .verseContent: return verseSourceRaw
        case .reference: return refSourceRaw
        case .translationName: return translationSourceRaw
        case .subtitle: return subtitleSourceRaw
        }
    }

    func setSourceRaw(_ raw: String, for section: TextBoxSection) {
        registerLayoutUndo()
        switch section {
        case .verseContent: verseSourceRaw = raw
        case .reference: refSourceRaw = raw
        case .translationName: translationSourceRaw = raw
        case .subtitle: subtitleSourceRaw = raw
        }
    }

    func sourceFormat(for section: TextBoxSection) -> String {
        switch section {
        case .verseContent: return verseSourceFormat
        case .reference: return refSourceFormat
        case .translationName: return translationSourceFormat
        case .subtitle: return subtitleSourceFormat
        }
    }

    func setSourceFormat(_ format: String, for section: TextBoxSection) {
        registerLayoutUndo()
        switch section {
        case .verseContent: verseSourceFormat = format
        case .reference: refSourceFormat = format
        case .translationName: translationSourceFormat = format
        case .subtitle: subtitleSourceFormat = format
        }
    }

    func staticText(for section: TextBoxSection) -> String {
        switch section {
        case .verseContent: return verseStaticText
        case .reference: return refStaticText
        case .translationName: return translationStaticText
        case .subtitle: return subtitleStaticText
        }
    }

    func setStaticText(_ text: String, for section: TextBoxSection) {
        registerLayoutUndo()
        switch section {
        case .verseContent: verseStaticText = text
        case .reference: refStaticText = text
        case .translationName: translationStaticText = text
        case .subtitle: subtitleStaticText = text
        }
    }

    /// Resolved text for a built-in section, honoring its source override.
    /// Callers pass the four candidate field values (live, preview, or sample).
    func sectionText(
        _ section: TextBoxSection,
        main: String, reference: String, translation: String, subtitle: String,
        now: Date = .now
    ) -> String {
        let autoValue: String
        switch section {
        case .verseContent: autoValue = main
        case .reference: autoValue = reference
        case .translationName: autoValue = translation
        case .subtitle: autoValue = subtitle
        }
        return Self.resolveBoxSource(
            sourceRaw(for: section),
            format: sourceFormat(for: section),
            autoValue: autoValue,
            staticText: staticText(for: section),
            main: main, reference: reference, translation: translation, subtitle: subtitle,
            now: now
        )
    }

    func isSectionVisible(_ section: TextBoxSection) -> Bool {
        switch section {
        case .verseContent: return verseBoxVisible
        case .reference: return refBoxVisible
        case .translationName: return translationBoxVisible
        case .subtitle: return subtitleBoxVisible
        }
    }

    func setSectionVisible(_ visible: Bool, for section: TextBoxSection) {
        registerLayoutUndo()
        switch section {
        case .verseContent: verseBoxVisible = visible
        case .reference: refBoxVisible = visible
        case .translationName: translationBoxVisible = visible
        case .subtitle: subtitleBoxVisible = visible
        }
    }

    func resetBoxFrame(for section: TextBoxSection) {
        registerLayoutUndo()
        switch section {
        case .verseContent: verseBoxFrame = .defaultVerse
        case .reference: refBoxFrame = .defaultReference
        case .translationName: translationBoxFrame = .defaultTranslation
        case .subtitle: subtitleBoxFrame = .defaultSubtitle
        }
    }

    func resetAllBoxFrames() {
        registerLayoutUndo()
        for section in TextBoxSection.allCases {
            resetBoxFrame(for: section)
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
