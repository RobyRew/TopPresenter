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

    // MARK: - Presentation State
    var isBlackScreen: Bool = false
    var isFrozen: Bool = false

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
    }

    func clearOutput() {
        liveContent.clear()
        isBlackScreen = false
        isFrozen = false
    }

    func showBibleVerse(text: String, reference: String) {
        guard !isFrozen else { return }
        liveContent.setBibleVerse(text: text, reference: reference)
        liveContent.isLive = true
        isBlackScreen = false
    }

    func showSongVerse(text: String, title: String, verseLabel: String) {
        guard !isFrozen else { return }
        liveContent.setSongVerse(text: text, title: title, verseLabel: verseLabel)
        liveContent.isLive = true
        isBlackScreen = false
    }

    func showCustomText(text: String, title: String) {
        guard !isFrozen else { return }
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

    /// The size of the target presentation screen (or main screen as fallback).
    var presentationScreenSize: CGSize {
        let screens = NSScreen.screens
        if let idx = presentationScreenIndex, idx < screens.count {
            return screens[idx].frame.size
        }
        return screens.last?.frame.size ?? CGSize(width: 1920, height: 1080)
    }

    /// Positions the presentation window on the specified screen
    func positionOnScreen(_ screen: NSScreen) {
        presentationScreenIndex = NSScreen.screens.firstIndex(of: screen)
        movePresentationWindow(to: screen)
    }

    /// Moves the presentation window to fill the given screen.
    func movePresentationWindow(to screen: NSScreen) {
        // Find the presentation window by its identifier
        guard let window = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == WindowIdentifiers.presentation
        }) else { return }

        let frame = screen.frame
        window.setFrame(frame, display: true, animate: false)
        window.level = .statusBar  // Keep above other windows during presentation
    }

    /// Moves the presentation window to the currently selected screen.
    func applyScreenPosition() {
        let screens = NSScreen.screens
        guard let idx = presentationScreenIndex, idx < screens.count else {
            // Default: use last screen (external display) or main screen
            if let lastScreen = screens.last, screens.count > 1 {
                movePresentationWindow(to: lastScreen)
            }
            return
        }
        movePresentationWindow(to: screens[idx])
    }
}
