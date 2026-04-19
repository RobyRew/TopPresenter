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

    // MARK: - Style
    var currentStyle: PresentationStyle?

    // MARK: - Background
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

    // MARK: - Display Settings
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
    var textAlignment: TextAlignment = .center
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
        // macOS doesn't expose physical dimensions directly, so we estimate:
        // Built-in Retina: ~220 PPI, External non-Retina: ~96 PPI, External Retina: ~110 PPI
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
        // The built-in display is typically the main screen on laptops
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
    private var screenObserver: Any?

    func startScreenMonitoring() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            handleScreenConfigurationChange()
        }
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
            // Still move to built-in screen so it's ready
            if let builtIn = builtInScreen {
                presentationScreenIndex = 0
                movePresentationWindow(to: builtIn)
            }
        case .ask:
            // Move to built-in immediately to keep presenting, then ask
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
        // Prefer an external screen (not the first/built-in one)
        if screens.count > 1, let external = screens.last {
            presentationScreenIndex = screens.count - 1
            movePresentationWindow(to: external)
        } else if let builtIn = screens.first {
            // Fallback to built-in — single-screen mode
            presentationScreenIndex = 0
            movePresentationWindow(to: builtIn)
        }
    }

    // MARK: - Presentation State
    var isBlackScreen: Bool = false
    var isFrozen: Bool = false

    // MARK: - Edit Mode (Layout Debug)
    /// Shows text box bounding boxes in the preview.
    var isEditMode: Bool = false

    // -- Verse Content Section --
    var editVerseMultiplier: Double {
        didSet { UserDefaults.standard.set(editVerseMultiplier, forKey: "pm_editVerseMultiplier") }
    }
    var editVerseOffsetX: Double {
        didSet { UserDefaults.standard.set(editVerseOffsetX, forKey: "pm_editVerseOffsetX") }
    }
    var editVerseOffsetY: Double {
        didSet { UserDefaults.standard.set(editVerseOffsetY, forKey: "pm_editVerseOffsetY") }
    }
    var editVersePadding: Double {
        didSet { UserDefaults.standard.set(editVersePadding, forKey: "pm_editVersePadding") }
    }
    var editVerseOpacity: Double {
        didSet { UserDefaults.standard.set(editVerseOpacity, forKey: "pm_editVerseOpacity") }
    }
    /// Per-section font override for verse content. Empty = use global font.
    var verseFontName: String {
        didSet { UserDefaults.standard.set(verseFontName, forKey: "pm_verseFontName") }
    }
    /// Per-section font size override. 0 = use global fontSize.
    var verseFontSizeOverride: Double {
        didSet { UserDefaults.standard.set(verseFontSizeOverride, forKey: "pm_verseFontSizeOverride") }
    }
    /// Per-section text color override. Empty = use global textColor.
    var verseTextColorHex: String {
        didSet { UserDefaults.standard.set(verseTextColorHex, forKey: "pm_verseTextColorHex") }
    }
    /// Per-section text alignment. nil = use global.
    var verseAlignmentRaw: String {
        didSet { UserDefaults.standard.set(verseAlignmentRaw, forKey: "pm_verseAlignmentRaw") }
    }
    /// Per-section line spacing override. -1 = use global.
    var verseLineSpacing: Double {
        didSet { UserDefaults.standard.set(verseLineSpacing, forKey: "pm_verseLineSpacing") }
    }
    var editVerseOffset: CGSize {
        get { CGSize(width: editVerseOffsetX, height: editVerseOffsetY) }
        set { editVerseOffsetX = newValue.width; editVerseOffsetY = newValue.height }
    }

    // Resolved verse text properties (per-section overrides OR fallback to global)
    var resolvedVerseFontName: String { verseFontName.isEmpty ? fontName : verseFontName }
    var resolvedVerseFontSize: Double { verseFontSizeOverride > 0 ? verseFontSizeOverride : fontSize }
    var resolvedVerseTextColor: Color { verseTextColorHex.isEmpty ? textColor : (Color(hex: verseTextColorHex) ?? textColor) }
    var resolvedVerseAlignment: TextAlignment {
        switch verseAlignmentRaw {
        case "leading": return .leading
        case "trailing": return .trailing
        case "center": return .center
        default: return textAlignment // global fallback
        }
    }
    var resolvedVerseLineSpacing: Double { verseLineSpacing >= 0 ? verseLineSpacing : lineSpacing }

    // -- Reference / Title Section --
    var editRefMultiplier: Double {
        didSet { UserDefaults.standard.set(editRefMultiplier, forKey: "pm_editRefMultiplier") }
    }
    var editRefOffsetX: Double {
        didSet { UserDefaults.standard.set(editRefOffsetX, forKey: "pm_editRefOffsetX") }
    }
    var editRefOffsetY: Double {
        didSet { UserDefaults.standard.set(editRefOffsetY, forKey: "pm_editRefOffsetY") }
    }
    var editRefPadding: Double {
        didSet { UserDefaults.standard.set(editRefPadding, forKey: "pm_editRefPadding") }
    }
    var editRefOpacity: Double {
        didSet { UserDefaults.standard.set(editRefOpacity, forKey: "pm_editRefOpacity") }
    }
    /// Per-section font override for reference. Empty = use global.
    var refFontName: String {
        didSet { UserDefaults.standard.set(refFontName, forKey: "pm_refFontName") }
    }
    /// Per-section font size override. 0 = use 55% of global fontSize.
    var refFontSizeOverride: Double {
        didSet { UserDefaults.standard.set(refFontSizeOverride, forKey: "pm_refFontSizeOverride") }
    }
    /// Per-section text color override. Empty = use global with 0.85 opacity.
    var refTextColorHex: String {
        didSet { UserDefaults.standard.set(refTextColorHex, forKey: "pm_refTextColorHex") }
    }
    /// Per-section alignment override. Empty = use global.
    var refAlignmentRaw: String {
        didSet { UserDefaults.standard.set(refAlignmentRaw, forKey: "pm_refAlignmentRaw") }
    }
    /// Per-section weight: "regular", "semibold", "bold"
    var refFontWeight: String {
        didSet { UserDefaults.standard.set(refFontWeight, forKey: "pm_refFontWeight") }
    }
    var editRefOffset: CGSize {
        get { CGSize(width: editRefOffsetX, height: editRefOffsetY) }
        set { editRefOffsetX = newValue.width; editRefOffsetY = newValue.height }
    }

    // Resolved reference text properties
    var resolvedRefFontName: String { refFontName.isEmpty ? fontName : refFontName }
    var resolvedRefFontSize: Double { refFontSizeOverride > 0 ? refFontSizeOverride : fontSize * 0.55 }
    var resolvedRefTextColor: Color { refTextColorHex.isEmpty ? textColor.opacity(0.85) : (Color(hex: refTextColorHex) ?? textColor.opacity(0.85)) }
    var resolvedRefAlignment: TextAlignment {
        switch refAlignmentRaw {
        case "leading": return .leading
        case "trailing": return .trailing
        case "center": return .center
        default: return textAlignment
        }
    }
    var resolvedRefWeight: Font.Weight {
        switch refFontWeight {
        case "regular": return .regular
        case "bold": return .bold
        default: return .semibold
        }
    }

    // Legacy compat accessors (redirect to verse section)
    var editFontSizeMultiplier: Double {
        get { editVerseMultiplier }
        set { editVerseMultiplier = newValue }
    }
    var editOffsetX: Double {
        get { editVerseOffsetX }
        set { editVerseOffsetX = newValue }
    }
    var editOffsetY: Double {
        get { editVerseOffsetY }
        set { editVerseOffsetY = newValue }
    }
    var editAlignmentOffset: CGSize {
        get { editVerseOffset }
        set { editVerseOffset = newValue }
    }

    // MARK: - Freeze Snapshot
    // When frozen, these hold the display settings at the moment of freeze,
    // so the output view keeps showing exactly what was on screen.
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
    // Verse section frozen
    private(set) var frozenVerseMultiplier: Double = 1.0
    private(set) var frozenVerseOffsetX: Double = 0
    private(set) var frozenVerseOffsetY: Double = 0
    private(set) var frozenVersePadding: Double = 0
    private(set) var frozenVerseOpacity: Double = 1.0
    private(set) var frozenVerseFontName: String = ""
    private(set) var frozenVerseFontSize: Double = 0
    private(set) var frozenVerseTextColorHex: String = ""
    private(set) var frozenVerseAlignmentRaw: String = ""
    private(set) var frozenVerseLineSpacing: Double = -1
    // Reference section frozen
    private(set) var frozenRefMultiplier: Double = 1.0
    private(set) var frozenRefOffsetX: Double = 0
    private(set) var frozenRefOffsetY: Double = 0
    private(set) var frozenRefPadding: Double = 0
    private(set) var frozenRefOpacity: Double = 1.0
    private(set) var frozenRefFontName: String = ""
    private(set) var frozenRefFontSize: Double = 0
    private(set) var frozenRefTextColorHex: String = ""
    private(set) var frozenRefAlignmentRaw: String = ""
    private(set) var frozenRefFontWeight: String = "semibold"

    // MARK: - Output Accessors (used by PresentationOutputView)
    // Return frozen values when frozen, live values otherwise.
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
    // Verse section output accessors
    var outputVerseMultiplier: Double { isFrozen ? frozenVerseMultiplier : editVerseMultiplier }
    var outputVerseOffsetX: Double { isFrozen ? frozenVerseOffsetX : editVerseOffsetX }
    var outputVerseOffsetY: Double { isFrozen ? frozenVerseOffsetY : editVerseOffsetY }
    var outputVersePadding: Double { isFrozen ? frozenVersePadding : editVersePadding }
    var outputVerseOpacity: Double { isFrozen ? frozenVerseOpacity : editVerseOpacity }
    var outputVerseOffset: CGSize { CGSize(width: outputVerseOffsetX, height: outputVerseOffsetY) }
    var outputVerseFontName: String { isFrozen ? frozenVerseFontName : resolvedVerseFontName }
    var outputVerseFontSize: Double { isFrozen ? frozenVerseFontSize : resolvedVerseFontSize }
    var outputVerseTextColor: Color { isFrozen ? (Color(hex: frozenVerseTextColorHex.isEmpty ? outputTextColorHex : frozenVerseTextColorHex) ?? .white) : resolvedVerseTextColor }
    var outputVerseAlignment: TextAlignment {
        if isFrozen {
            switch frozenVerseAlignmentRaw {
            case "leading": return .leading
            case "trailing": return .trailing
            case "center": return .center
            default: return outputTextAlignment
            }
        }
        return resolvedVerseAlignment
    }
    var outputVerseLineSpacing: Double { isFrozen ? (frozenVerseLineSpacing >= 0 ? frozenVerseLineSpacing : outputLineSpacing) : resolvedVerseLineSpacing }
    // Reference section output accessors
    var outputRefMultiplier: Double { isFrozen ? frozenRefMultiplier : editRefMultiplier }
    var outputRefOffsetX: Double { isFrozen ? frozenRefOffsetX : editRefOffsetX }
    var outputRefOffsetY: Double { isFrozen ? frozenRefOffsetY : editRefOffsetY }
    var outputRefPadding: Double { isFrozen ? frozenRefPadding : editRefPadding }
    var outputRefOpacity: Double { isFrozen ? frozenRefOpacity : editRefOpacity }
    var outputRefOffset: CGSize { CGSize(width: outputRefOffsetX, height: outputRefOffsetY) }
    var outputRefFontName: String { isFrozen ? frozenRefFontName : resolvedRefFontName }
    var outputRefFontSize: Double { isFrozen ? frozenRefFontSize : resolvedRefFontSize }
    var outputRefTextColor: Color { isFrozen ? (Color(hex: frozenRefTextColorHex.isEmpty ? outputTextColorHex : frozenRefTextColorHex) ?? .white.opacity(0.85)) : resolvedRefTextColor }
    var outputRefAlignment: TextAlignment {
        if isFrozen {
            switch frozenRefAlignmentRaw {
            case "leading": return .leading
            case "trailing": return .trailing
            case "center": return .center
            default: return outputTextAlignment
            }
        }
        return resolvedRefAlignment
    }
    var outputRefWeight: Font.Weight { isFrozen ? (frozenRefFontWeight == "regular" ? .regular : frozenRefFontWeight == "bold" ? .bold : .semibold) : resolvedRefWeight }
    // Legacy compat
    var outputEditFontSizeMultiplier: Double { outputVerseMultiplier }
    var outputEditAlignmentOffset: CGSize { outputVerseOffset }
    var outputTextColor: Color { Color(hex: outputTextColorHex) ?? .white }
    var outputBackgroundColor: Color { Color(hex: outputBackgroundColorHex) ?? .black }

    // MARK: - Init (restore from UserDefaults)
    init() {
        let d = UserDefaults.standard
        self.fontSize = d.object(forKey: "pm_fontSize") as? Double ?? PresentationDefaults.fontSize
        self.fontName = d.string(forKey: "pm_fontName") ?? PresentationDefaults.fontName
        self.textColorHex = d.string(forKey: "pm_textColorHex") ?? PresentationDefaults.textColor
        self.backgroundColorHex = d.string(forKey: "pm_backgroundColorHex") ?? PresentationDefaults.backgroundColor
        self.lineSpacing = d.object(forKey: "pm_lineSpacing") as? Double ?? PresentationDefaults.lineSpacing
        self.padding = d.object(forKey: "pm_padding") as? Double ?? PresentationDefaults.padding
        self.shadowEnabled = d.object(forKey: "pm_shadowEnabled") as? Bool ?? true
        self.shadowRadius = d.object(forKey: "pm_shadowRadius") as? Double ?? 3.0
        self.transitionDuration = d.object(forKey: "pm_transitionDuration") as? Double ?? PresentationDefaults.transitionDuration
        self.backgroundOpacity = d.object(forKey: "pm_backgroundOpacity") as? Double ?? PresentationDefaults.backgroundOpacity
        self.useBackgroundImage = d.bool(forKey: "pm_useBackgroundImage")
        self.backgroundEnabled = d.bool(forKey: "pm_backgroundEnabled") // defaults to false = transparent
        self.windowLevel = d.string(forKey: "pm_windowLevel") ?? "alwaysOnTop"
        // Verse section
        self.editVerseMultiplier = d.object(forKey: "pm_editVerseMultiplier") as? Double
            ?? d.object(forKey: "pm_editFontSizeMultiplier") as? Double ?? 1.0
        self.editVerseOffsetX = d.object(forKey: "pm_editVerseOffsetX") as? Double
            ?? d.object(forKey: "pm_editOffsetX") as? Double ?? 0
        self.editVerseOffsetY = d.object(forKey: "pm_editVerseOffsetY") as? Double
            ?? d.object(forKey: "pm_editOffsetY") as? Double ?? 0
        self.editVersePadding = d.object(forKey: "pm_editVersePadding") as? Double ?? 0
        self.editVerseOpacity = d.object(forKey: "pm_editVerseOpacity") as? Double ?? 1.0
        self.verseFontName = d.string(forKey: "pm_verseFontName") ?? ""
        self.verseFontSizeOverride = d.object(forKey: "pm_verseFontSizeOverride") as? Double ?? 0
        self.verseTextColorHex = d.string(forKey: "pm_verseTextColorHex") ?? ""
        self.verseAlignmentRaw = d.string(forKey: "pm_verseAlignmentRaw") ?? ""
        self.verseLineSpacing = d.object(forKey: "pm_verseLineSpacing") as? Double ?? -1
        // Reference section
        self.editRefMultiplier = d.object(forKey: "pm_editRefMultiplier") as? Double ?? 1.0
        self.editRefOffsetX = d.object(forKey: "pm_editRefOffsetX") as? Double ?? 0
        self.editRefOffsetY = d.object(forKey: "pm_editRefOffsetY") as? Double ?? 0
        self.editRefPadding = d.object(forKey: "pm_editRefPadding") as? Double ?? 0
        self.editRefOpacity = d.object(forKey: "pm_editRefOpacity") as? Double ?? 1.0
        self.refFontName = d.string(forKey: "pm_refFontName") ?? ""
        self.refFontSizeOverride = d.object(forKey: "pm_refFontSizeOverride") as? Double ?? 0
        self.refTextColorHex = d.string(forKey: "pm_refTextColorHex") ?? ""
        self.refAlignmentRaw = d.string(forKey: "pm_refAlignmentRaw") ?? ""
        self.refFontWeight = d.string(forKey: "pm_refFontWeight") ?? "semibold"

        // Restore background image from saved path
        if let path = d.string(forKey: "pm_backgroundImagePath"),
           let image = NSImage(contentsOfFile: path) {
            self.backgroundImagePath = path
            self.backgroundImage = image
        }

        // Initialize frozen snapshot to current values
        snapshotForFreeze()
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
            // Freezing — take a snapshot of current display settings
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
        // Verse section
        frozenVerseMultiplier = editVerseMultiplier
        frozenVerseOffsetX = editVerseOffsetX
        frozenVerseOffsetY = editVerseOffsetY
        frozenVersePadding = editVersePadding
        frozenVerseOpacity = editVerseOpacity
        frozenVerseFontName = resolvedVerseFontName
        frozenVerseFontSize = resolvedVerseFontSize
        frozenVerseTextColorHex = verseTextColorHex
        frozenVerseAlignmentRaw = verseAlignmentRaw
        frozenVerseLineSpacing = verseLineSpacing
        // Reference section
        frozenRefMultiplier = editRefMultiplier
        frozenRefOffsetX = editRefOffsetX
        frozenRefOffsetY = editRefOffsetY
        frozenRefPadding = editRefPadding
        frozenRefOpacity = editRefOpacity
        frozenRefFontName = resolvedRefFontName
        frozenRefFontSize = resolvedRefFontSize
        frozenRefTextColorHex = refTextColorHex
        frozenRefAlignmentRaw = refAlignmentRaw
        frozenRefFontWeight = refFontWeight
    }

    func clearOutput() {
        liveContent.clear()
        isBlackScreen = false
        isFrozen = false
        if isSingleScreenMode {
            hidePresentationWindow()
        }
    }

    func showBibleVerse(text: String, reference: String) {
        guard !isFrozen else { return }
        showPresentationWindow()
        liveContent.setBibleVerse(text: text, reference: reference)
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

    func setBackgroundImage(from url: URL) {
        if let image = NSImage(contentsOf: url) {
            backgroundImage = image
            backgroundImagePath = url.path
            useBackgroundImage = true
        }
    }

    func removeBackgroundImage() {
        backgroundImage = nil
        backgroundImagePath = nil
        useBackgroundImage = false
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

    /// The size of the target presentation screen in points (or main screen as fallback).
    var presentationScreenSize: CGSize {
        targetScreenMetrics.points
    }

    /// The native pixel resolution of the target screen.
    var presentationScreenResolution: CGSize {
        targetScreenMetrics.resolution
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
        // Find the presentation window by its identifier
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

    /// Moves the presentation window to the currently selected screen.
    /// In single-screen mode (laptop only), presents fullscreen on the built-in display.
    func applyScreenPosition() {
        let screens = NSScreen.screens

        if let idx = presentationScreenIndex, idx < screens.count {
            movePresentationWindow(to: screens[idx])
        } else if screens.count > 1, let external = screens.last {
            // Multi-screen: default to last (external) display
            presentationScreenIndex = screens.count - 1
            movePresentationWindow(to: external)
        } else if let builtIn = screens.first {
            // Single-screen: present fullscreen on built-in display
            presentationScreenIndex = 0
            movePresentationWindow(to: builtIn)
        }
    }
}
