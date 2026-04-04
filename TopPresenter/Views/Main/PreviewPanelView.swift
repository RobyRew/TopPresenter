//
//  PreviewPanelView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Right-side panel router — switches between dedicated panels based on the active sidebar item.
struct PreviewPanelView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.selectedSidebarItem {
            case .bible:
                BiblePreviewPanel()
            case .songs:
                SongsPreviewPanel()
            case .media:
                MediaPreviewPanel()
            case .schedule:
                SchedulePreviewPanel()
            case .customSlides:
                CustomSlidesPreviewPanel()
            }
        }
    }
}

// MARK: - Shared Panel Header
/// Reusable header showing the panel title, content type icon, and live indicator.
struct PanelHeader: View {
    let contentType: AppState.SidebarItem
    @Environment(PresentationManager.self) private var pm

    var body: some View {
        HStack {
            Image(systemName: contentType.systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(contentType.localizedName)
                .font(.headline)
            Spacer()

            // Live indicator
            if pm.liveContent.isLive && !pm.isBlackScreen {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text(String(localized: "LIVE", comment: "Live indicator"))
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview Card
struct PresentationPreviewCard: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager
    @AppStorage("multiVerseLayout") private var multiVerseLayout: String = "inline"
    @AppStorage("showVerseNumberPrefix") private var showVerseNumberPrefix: Bool = false

    /// Text to preview: when frozen show the current selection (what will go live next),
    /// when live show the live content, otherwise show the selected verses preview.
    private var previewText: String {
        // When frozen, show what the user is preparing (selected verses), not the frozen output
        if pm.isFrozen && !libraryManager.selectedVerses.isEmpty {
            return libraryManager.formattedSelectedVersesText(
                layout: multiVerseLayout, showPrefix: showVerseNumberPrefix
            )
        }
        if pm.liveContent.isLive, !pm.liveContent.mainText.isEmpty {
            return pm.liveContent.mainText
        }
        if !libraryManager.selectedVerses.isEmpty {
            return libraryManager.formattedSelectedVersesText(
                layout: multiVerseLayout, showPrefix: showVerseNumberPrefix
            )
        }
        return ""
    }

    private var previewReference: String {
        if pm.isFrozen && !libraryManager.selectedVerses.isEmpty {
            return libraryManager.selectedVersesReference
        }
        if pm.liveContent.isLive, !pm.liveContent.reference.isEmpty {
            return pm.liveContent.reference
        }
        if !libraryManager.selectedVerses.isEmpty {
            return libraryManager.selectedVersesReference
        }
        return ""
    }

    private var previewSubtitle: String {
        if pm.liveContent.isLive {
            return pm.liveContent.subtitle
        }
        return ""
    }

    private var hasContent: Bool {
        !previewText.isEmpty
    }

    /// True when showing selected but not-yet-live content, or when frozen (preparing next slide).
    private var isPreviewOnly: Bool {
        let notLiveYet = !pm.liveContent.isLive && !libraryManager.selectedVerses.isEmpty
        let frozenAndPreparing = pm.isFrozen && !libraryManager.selectedVerses.isEmpty
        return notLiveYet || frozenAndPreparing
    }

    /// Aspect ratio of the target presentation screen.
    private var targetAspectRatio: CGFloat {
        let size = pm.presentationScreenSize
        guard size.height > 0 else { return 16.0 / 9.0 }
        return size.width / size.height
    }

    var body: some View {
        ZStack {
            // Preview always has a black background so text is legible
            Color.black

            // Background
            if pm.isBlackScreen {
                // Already black — just show nothing
            } else {
                // Solid background color (when user enabled it)
                if pm.backgroundEnabled {
                    pm.backgroundColor
                }

                // Background image
                if pm.useBackgroundImage, let bgImage = pm.backgroundImage {
                    Image(nsImage: bgImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(pm.backgroundOpacity)
                }

                // Content (live OR selected preview)
                if hasContent {
                    VStack(spacing: 8) {
                        Text(previewText)
                            .font(.system(size: pm.fontSize * 0.25))
                            .foregroundStyle(pm.textColor.opacity(isPreviewOnly ? 0.5 : 1.0))
                            .multilineTextAlignment(pm.textAlignment)
                            .shadow(
                                radius: pm.shadowEnabled ? pm.shadowRadius * 0.25 : 0
                            )

                        if !previewReference.isEmpty {
                            Text(previewReference)
                                .font(.system(size: pm.fontSize * 0.15, weight: .medium))
                                .foregroundStyle(pm.textColor.opacity(isPreviewOnly ? 0.4 : 0.8))
                        }

                        if !previewSubtitle.isEmpty {
                            Text(previewSubtitle)
                                .font(.system(size: pm.fontSize * 0.12))
                                .foregroundStyle(pm.textColor.opacity(0.6))
                        }
                    }
                    .padding(pm.padding * 0.25)
                }
            }

            // "PREVIEW" / "FROZEN" badge when showing non-live selection
            if isPreviewOnly && !pm.isBlackScreen {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            if pm.isFrozen {
                                Text("FROZEN")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.8), in: Capsule())
                            }
                            Text("PREVIEW")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.7), in: Capsule())
                        }
                        .padding(6)
                    }
                    Spacer()
                }
            }

            // Transparent indicator — always visible when output has no solid background
            if !pm.backgroundEnabled && !pm.isBlackScreen {
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        HStack(spacing: 4) {
                            // Mini checkerboard icon
                            Image(systemName: "checkerboard.rectangle")
                                .font(.system(size: 9))
                            Text(String(localized: "Transparent", comment: "Preview badge"))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.4), in: Capsule())
                        Spacer()
                    }
                    .padding(6)
                }
            }
        }
        .aspectRatio(targetAspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isPreviewOnly ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: isPreviewOnly ? 1.5 : 1)
        )
        .shadow(radius: 2)
    }
}

// MARK: - Verse / Slide Controls Bar
/// Shows the selected verse reference, Show/Hide toggle, ←→ navigation.
/// Appears between the preview card and the presentation controls.
struct VerseSlideControlsBar: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager
    @AppStorage("multiVerseLayout") private var multiVerseLayout: String = "inline"
    @AppStorage("showVerseNumberPrefix") private var showVerseNumberPrefix: Bool = false

    /// Whether there's anything live on screen.
    private var isLive: Bool {
        pm.liveContent.isLive && !pm.isBlackScreen
    }

    private var formattedText: String {
        libraryManager.formattedSelectedVersesText(layout: multiVerseLayout, showPrefix: showVerseNumberPrefix)
    }

    /// How many verses can fit on screen from the current starting verse.
    private var maxFittingCount: Int {
        libraryManager.versesCountThatFits(
            fontSize: pm.fontSize,
            fontName: pm.fontName,
            lineSpacing: pm.lineSpacing,
            padding: pm.padding,
            screenSize: pm.presentationScreenSize,
            layout: multiVerseLayout,
            showPrefix: showVerseNumberPrefix
        )
    }

    private func runAutoFill() {
        libraryManager.autoFillVerses(
            fontSize: pm.fontSize,
            fontName: pm.fontName,
            lineSpacing: pm.lineSpacing,
            padding: pm.padding,
            screenSize: pm.presentationScreenSize,
            layout: multiVerseLayout,
            showPrefix: showVerseNumberPrefix
        )
    }

    /// Push the current selection to live output.
    private func updateLiveOutput() {
        guard pm.liveContent.isLive else { return }
        pm.showBibleVerse(
            text: formattedText,
            reference: libraryManager.selectedVersesReference
        )
    }

    /// Navigate verse, re-fill if auto-fill active, and update live output.
    private func navigate(direction: Int) {
        let wasLive = pm.liveContent.isLive
        libraryManager.navigateVerse(direction: direction)
        if libraryManager.isAutoFillActive {
            runAutoFill()
        }
        if wasLive {
            updateLiveOutput()
        }
    }

    /// Cross-chapter navigation: advance to next chapter and re-fill.
    private func navigateCrossChapter(direction: Int) {
        let wasLive = pm.liveContent.isLive
        if direction > 0 {
            libraryManager.advanceToNextChapter()
        } else {
            libraryManager.returnToPreviousChapter()
        }
        if libraryManager.isAutoFillActive {
            runAutoFill()
        }
        if wasLive {
            updateLiveOutput()
        }
    }

    /// Whether the ← → buttons should be disabled, considering cross-chapter nav.
    private func canNavigate(direction: Int) -> Bool {
        if libraryManager.canNavigateVerse(direction: direction) {
            return true
        }
        // If auto-fill is active, we can also go to next/prev chapter
        if libraryManager.isAutoFillActive {
            return direction > 0
                ? libraryManager.canAdvanceToNextChapter
                : libraryManager.canReturnToPreviousChapter
        }
        return false
    }

    /// Whether pressing ← → at this point would cross a chapter boundary.
    private func wouldCrossChapter(direction: Int) -> Bool {
        !libraryManager.canNavigateVerse(direction: direction)
            && libraryManager.isAutoFillActive
            && (direction > 0 ? libraryManager.canAdvanceToNextChapter : libraryManager.canReturnToPreviousChapter)
    }

    /// Perform the correct navigation (in-chapter or cross-chapter).
    private func performNavigation(direction: Int) {
        if libraryManager.canNavigateVerse(direction: direction) {
            navigate(direction: direction)
        } else if wouldCrossChapter(direction: direction) {
            navigateCrossChapter(direction: direction)
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            // Selected verse reference (if any selected)
            if !libraryManager.selectedVerses.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "book.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)

                    Text(libraryManager.selectedVersesReference)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)

                    Spacer()

                    // Verse count badge + fitting indicator
                    if libraryManager.selectedVerses.count > 1 {
                        Text("\(libraryManager.selectedVerses.count) verses")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }

                    // Auto-fill active indicator
                    if libraryManager.isAutoFillActive {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .help(String(localized: "Auto-fill active — adjusts with font size", comment: "Tooltip"))
                    }

                    // Fitting warning: selected more than can fit
                    if libraryManager.selectedVerses.count > maxFittingCount && maxFittingCount > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help(String(localized: "Only \(maxFittingCount) verse(s) fit on screen at current size", comment: "Tooltip"))
                    }

                    // Clear selection
                    Button {
                        libraryManager.clearVerseSelection()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(String(localized: "Clear Selection", comment: "Button tooltip"))
                }
            }

            // Main controls row
            HStack(spacing: 8) {
                // ← Previous
                Button {
                    performNavigation(direction: -1)
                } label: {
                    Image(systemName: wouldCrossChapter(direction: -1) ? "chevron.left.2" : "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(wouldCrossChapter(direction: -1) ? .orange : nil)
                .disabled(!canNavigate(direction: -1))
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help(wouldCrossChapter(direction: -1)
                    ? String(localized: "Previous Chapter", comment: "Button tooltip")
                    : String(localized: "Previous Verse", comment: "Button tooltip")
                )

                // Show / Hide toggle — single big button
                Button {
                    if isLive {
                        pm.clearOutput()
                    } else if !libraryManager.selectedVerses.isEmpty {
                        pm.showBibleVerse(
                            text: formattedText,
                            reference: libraryManager.selectedVersesReference
                        )
                    }
                } label: {
                    Label(
                        isLive
                            ? String(localized: "Hide", comment: "Control button")
                            : String(localized: "Show", comment: "Control button"),
                        systemImage: isLive ? "eye.slash.fill" : "play.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(isLive ? .orange : .accentColor)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(!isLive && libraryManager.selectedVerses.isEmpty)

                // Auto-fill toggle — select max verses that fit / revert to single
                Button {
                    if libraryManager.isAutoFillActive {
                        // Toggle OFF — revert to first selected verse only
                        if let first = libraryManager.selectedVerses.first {
                            libraryManager.isAutoFillActive = false
                            libraryManager.selectedVerses = [first]
                        }
                    } else {
                        runAutoFill()
                    }
                } label: {
                    Image(systemName: libraryManager.isAutoFillActive ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(libraryManager.isAutoFillActive ? .green : nil)
                .disabled(libraryManager.selectedChapter == nil)
                .help(libraryManager.isAutoFillActive
                    ? String(localized: "Revert to single verse", comment: "Button tooltip")
                    : String(localized: "Auto-fill: select max verses that fit on screen", comment: "Button tooltip")
                )

                // → Next
                Button {
                    performNavigation(direction: 1)
                } label: {
                    Image(systemName: wouldCrossChapter(direction: 1) ? "chevron.right.2" : "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .tint(wouldCrossChapter(direction: 1) ? .orange : nil)
                .disabled(!canNavigate(direction: 1))
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help(wouldCrossChapter(direction: 1)
                    ? String(localized: "Next Chapter", comment: "Button tooltip")
                    : String(localized: "Next Verse", comment: "Button tooltip")
                )
            }

            // Max fitting info when auto-fill is active
            if libraryManager.isAutoFillActive && maxFittingCount <= 1 {
                Text(String(localized: "⚠️ Only 1 verse fits at current font size", comment: "Warning label"))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        // Re-run auto-fill when font size, line spacing, or padding changes
        // and also update live output if currently showing
        .onChange(of: pm.fontSize) {
            if libraryManager.isAutoFillActive { runAutoFill() }
            updateLiveOutput()
        }
        .onChange(of: pm.lineSpacing) {
            if libraryManager.isAutoFillActive { runAutoFill() }
            updateLiveOutput()
        }
        .onChange(of: pm.padding) {
            if libraryManager.isAutoFillActive { runAutoFill() }
            updateLiveOutput()
        }
        .onChange(of: pm.fontName) {
            if libraryManager.isAutoFillActive { runAutoFill() }
            updateLiveOutput()
        }
    }
}

// MARK: - Presentation Controls Bar
struct PresentationControlsBar: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(AppState.self) private var appState
    @Environment(LibraryManager.self) private var libraryManager

    var body: some View {
        HStack(spacing: 12) {
            // Go Live / Go Black
            Button {
                pm.toggleBlack()
            } label: {
                Label(
                    pm.isBlackScreen
                        ? String(localized: "Show", comment: "Control button")
                        : String(localized: "Black", comment: "Control button"),
                    systemImage: pm.isBlackScreen ? "sun.max.fill" : "moon.fill"
                )
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button {
                pm.toggleFreeze()
            } label: {
                Label(
                    pm.isFrozen
                        ? String(localized: "Unfreeze", comment: "Control button")
                        : String(localized: "Freeze", comment: "Control button"),
                    systemImage: pm.isFrozen ? "lock.open.fill" : "lock.fill"
                )
            }

            Spacer()

            // Unified split clear button
            SplitClearButton()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

// MARK: - Split Clear Button (unified: left = action, right = dropdown, right-click = menu, force touch = configurable)
struct SplitClearButton: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(AppState.self) private var appState
    @Environment(LibraryManager.self) private var libraryManager
    @AppStorage("forceTouchClearAction") private var forceTouchAction: String = "clearAll"
    @State private var isHoveringMain = false
    @State private var isHoveringChevron = false
    @State private var showMenu = false

    var body: some View {
        HStack(spacing: 0) {
            // Main clear action (left side)
            Button {
                pm.clearOutput()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.rectangle")
                        .font(.caption)
                    Text(String(localized: "Clear", comment: "Control button"))
                        .font(.caption)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHoveringMain ? Color.primary.opacity(0.08) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringMain = $0 }
            .overlay {
                ForceTouchDetector {
                    performForceTouchAction()
                }
            }

            // Divider line
            Rectangle()
                .fill(Color.primary.opacity(0.15))
                .frame(width: 1, height: 18)

            // Dropdown chevron (right side)
            Button {
                showMenu = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 20, height: 24)
                    .background(isHoveringChevron ? Color.primary.opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { isHoveringChevron = $0 }
            .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                clearMenuContent
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contextMenu { clearContextMenuItems }
        .help(String(localized: "Clear Output (Force Touch: \(forceTouchActionLabel))", comment: "Tooltip"))
    }

    // MARK: - Menu Content (used for both popover and context menu)

    @ViewBuilder
    private var clearMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ClearMenuItem(
                title: String(localized: "Golește Ecranul", comment: "Clear menu"),
                icon: "xmark.rectangle",
                shortcut: "⎋"
            ) {
                pm.clearOutput()
                showMenu = false
            }

            ClearMenuItem(
                title: String(localized: "Golește și Ecran Negru", comment: "Clear menu"),
                icon: "moon.fill",
                shortcut: "⌘B"
            ) {
                pm.clearOutput()
                pm.isBlackScreen = true
                showMenu = false
            }

            Divider().padding(.vertical, 4)

            ClearMenuItem(
                title: String(localized: "Golește și Mergi la Biblie", comment: "Clear menu"),
                icon: "book.closed",
                shortcut: nil
            ) {
                pm.clearOutput()
                appState.selectedSidebarItem = .bible
                showMenu = false
            }

            ClearMenuItem(
                title: String(localized: "Golește și Mergi la Cântece", comment: "Clear menu"),
                icon: "music.note.list",
                shortcut: nil
            ) {
                pm.clearOutput()
                appState.selectedSidebarItem = .songs
                showMenu = false
            }

            ClearMenuItem(
                title: String(localized: "Golește și Mergi la Media", comment: "Clear menu"),
                icon: "photo.on.rectangle",
                shortcut: nil
            ) {
                pm.clearOutput()
                appState.selectedSidebarItem = .media
                showMenu = false
            }

            Divider().padding(.vertical, 4)

            ClearMenuItem(
                title: String(localized: "Golește Tot (ecran + selecție)", comment: "Clear menu"),
                icon: "trash",
                shortcut: "⇧⌘⎋",
                isDestructive: true
            ) {
                pm.clearOutput()
                libraryManager.clearVerseSelection()
                libraryManager.isAutoFillActive = false
                showMenu = false
            }

            Divider().padding(.vertical, 4)

            // Force Touch action configurator
            HStack(spacing: 6) {
                Image(systemName: "hand.tap.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Force Touch:", comment: "Clear menu"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: Binding(
                    get: { forceTouchAction },
                    set: { forceTouchAction = $0; showMenu = false }
                )) {
                    Text(String(localized: "Golește Tot", comment: "Force touch option")).tag("clearAll")
                    Text(String(localized: "Ecran Negru", comment: "Force touch option")).tag("goBlack")
                    Text(String(localized: "Mergi la Biblie", comment: "Force touch option")).tag("gotoBible")
                    Text(String(localized: "Mergi la Cântece", comment: "Force touch option")).tag("gotoSongs")
                    Text(String(localized: "Îngheață", comment: "Force touch option")).tag("freeze")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 6)
        .frame(width: 260)
    }

    @ViewBuilder
    private var clearContextMenuItems: some View {
        Button {
            pm.clearOutput()
        } label: {
            Label(String(localized: "Golește Ecranul", comment: "Clear menu"), systemImage: "xmark.rectangle")
        }

        Button {
            pm.clearOutput()
            pm.isBlackScreen = true
        } label: {
            Label(String(localized: "Golește și Ecran Negru", comment: "Clear menu"), systemImage: "moon.fill")
        }

        Divider()

        Button {
            pm.clearOutput()
            appState.selectedSidebarItem = .bible
        } label: {
            Label(String(localized: "Golește și Mergi la Biblie", comment: "Clear menu"), systemImage: "book.closed")
        }

        Button {
            pm.clearOutput()
            appState.selectedSidebarItem = .songs
        } label: {
            Label(String(localized: "Golește și Mergi la Cântece", comment: "Clear menu"), systemImage: "music.note.list")
        }

        Button {
            pm.clearOutput()
            appState.selectedSidebarItem = .media
        } label: {
            Label(String(localized: "Golește și Mergi la Media", comment: "Clear menu"), systemImage: "photo.on.rectangle")
        }

        Divider()

        Button(role: .destructive) {
            pm.clearOutput()
            libraryManager.clearVerseSelection()
            libraryManager.isAutoFillActive = false
        } label: {
            Label(String(localized: "Golește Tot (ecran + selecție)", comment: "Clear menu"), systemImage: "trash")
        }
    }

    // MARK: - Force Touch Action

    private var forceTouchActionLabel: String {
        switch forceTouchAction {
        case "clearAll": return String(localized: "Golește Tot", comment: "Force touch label")
        case "goBlack": return String(localized: "Ecran Negru", comment: "Force touch label")
        case "gotoBible": return String(localized: "Mergi la Biblie", comment: "Force touch label")
        case "gotoSongs": return String(localized: "Mergi la Cântece", comment: "Force touch label")
        case "freeze": return String(localized: "Îngheață", comment: "Force touch label")
        default: return String(localized: "Golește Tot", comment: "Force touch label")
        }
    }

    private func performForceTouchAction() {
        switch forceTouchAction {
        case "clearAll":
            pm.clearOutput()
            libraryManager.clearVerseSelection()
            libraryManager.isAutoFillActive = false
        case "goBlack":
            pm.clearOutput()
            pm.isBlackScreen = true
        case "gotoBible":
            pm.clearOutput()
            appState.selectedSidebarItem = .bible
        case "gotoSongs":
            pm.clearOutput()
            appState.selectedSidebarItem = .songs
        case "freeze":
            pm.toggleFreeze()
        default:
            pm.clearOutput()
        }
    }
}

// MARK: - Clear Menu Item (custom row for the popover)
private struct ClearMenuItem: View {
    let title: String
    let icon: String
    var shortcut: String? = nil
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.body)
                    .frame(width: 20)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Text(title)
                    .font(.callout)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isHovering ? Color.accentColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Force Touch Detector (NSViewRepresentable)
struct ForceTouchDetector: NSViewRepresentable {
    let onForceTouch: () -> Void

    func makeNSView(context: Context) -> ForceTouchNSView {
        let view = ForceTouchNSView()
        view.onForceTouch = onForceTouch
        return view
    }

    func updateNSView(_ nsView: ForceTouchNSView, context: Context) {
        nsView.onForceTouch = onForceTouch
    }

    class ForceTouchNSView: NSView {
        var onForceTouch: (() -> Void)?
        private var didTrigger = false

        override var acceptsFirstResponder: Bool { true }

        override func pressureChange(with event: NSEvent) {
            // Stage 2 = Force Touch (deep press)
            if event.stage == 2 && !didTrigger {
                didTrigger = true
                // Haptic feedback
                NSHapticFeedbackManager.defaultPerformer.perform(
                    .alignment,
                    performanceTime: .now
                )
                onForceTouch?()
            }

            if event.stage == 0 {
                didTrigger = false
            }
        }

        // Pass through regular clicks to the button underneath
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }
}

// MARK: - Audio Controls
struct AudioControlsView: View {
    @Environment(AudioPlayerManager.self) private var audio

    var body: some View {
        @Bindable var audioBinding = audio

        VStack(spacing: 8) {
            HStack {
                Text(audio.currentFileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(audio.formattedCurrentTime) / \(audio.formattedDuration)")
                    .font(.caption.monospacedDigit())
            }

            // Progress bar
            Slider(
                value: Binding(
                    get: { audio.progress },
                    set: { audio.seekToProgress($0) }
                ),
                in: 0...1
            )
            .controlSize(.small)

            HStack(spacing: 12) {
                Button { audio.skipBackward() } label: {
                    Image(systemName: "gobackward.10")
                }

                Button { audio.togglePlayPause() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                }

                Button { audio.skipForward() } label: {
                    Image(systemName: "goforward.10")
                }

                Button { audio.stop() } label: {
                    Image(systemName: "stop.fill")
                }

                Spacer()

                Button { audio.toggleMute() } label: {
                    Image(systemName: audio.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }

                Slider(value: $audioBinding.volume, in: 0...1)
                    .frame(width: 80)
                    .controlSize(.small)
                    .onChange(of: audio.volume) { _, newValue in
                        audio.setVolume(newValue)
                    }
            }
            .buttonStyle(.borderless)
            .controlSize(.small)

            // Speed control
            HStack {
                Text(String(localized: "Speed:", comment: "Audio speed label"))
                    .font(.caption)
                Picker("", selection: Binding(
                    get: { audio.playbackSpeed },
                    set: { audio.setPlaybackSpeed($0) }
                )) {
                    Text("0.5x").tag(Float(0.5))
                    Text("0.75x").tag(Float(0.75))
                    Text("1x").tag(Float(1.0))
                    Text("1.25x").tag(Float(1.25))
                    Text("1.5x").tag(Float(1.5))
                    Text("2x").tag(Float(2.0))
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
        }
    }
}

// MARK: - Settings Panel
/// Comprehensive inline settings panel with collapsible sections.
/// Pass `sections` to control which sections are shown for each content type.
struct StyleQuickSettings: View {
    /// Which setting sections to display.
    var sections: Set<SettingsSection> = SettingsSection.allSet

    enum SettingsSection: Hashable {
        case textFont, background, displayOutput, multiVerse, general

        static let allSet: Set<SettingsSection> = [.textFont, .background, .displayOutput, .multiVerse, .general]
    }

    @Environment(PresentationManager.self) private var pm

    @AppStorage("settingsExpanded_text") private var textExpanded: Bool = true
    @AppStorage("settingsExpanded_background") private var backgroundExpanded: Bool = false
    @AppStorage("settingsExpanded_display") private var displayExpanded: Bool = false
    @AppStorage("settingsExpanded_multiVerse") private var multiVerseExpanded: Bool = false
    @AppStorage("settingsExpanded_general") private var generalExpanded: Bool = false

    // General settings
    @AppStorage("showVerseNumbers") private var showVerseNumbers: Bool = true
    @AppStorage("showCrossReferences") private var showCrossReferences: Bool = false
    @AppStorage("showFootnotes") private var showFootnotes: Bool = false
    @AppStorage("multiVerseLayout") private var multiVerseLayout: String = "inline"
    @AppStorage("showVerseNumberPrefix") private var showVerseNumberPrefix: Bool = false

    @State private var availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        let pmBinding = Bindable(pm)

        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if sections.contains(.textFont) {
                    // ─── Text & Font ───
                    settingsSection(
                        title: String(localized: "Text & Font", comment: "Settings section"),
                        icon: "textformat",
                        isExpanded: $textExpanded
                    ) {
                        textAndFontSection(pmBinding: pmBinding)
                    }
                }

                if sections.contains(.background) {
                    // ─── Background ───
                    settingsSection(
                        title: String(localized: "Background", comment: "Settings section"),
                        icon: "photo.artframe",
                        isExpanded: $backgroundExpanded
                    ) {
                        backgroundSection(pmBinding: pmBinding)
                    }
                }

                if sections.contains(.displayOutput) {
                    // ─── Display & Output ───
                    settingsSection(
                        title: String(localized: "Display & Output", comment: "Settings section"),
                        icon: "display",
                        isExpanded: $displayExpanded
                    ) {
                        displaySection(pmBinding: pmBinding)
                    }
                }

                if sections.contains(.multiVerse) {
                    // ─── Multi-Verse ───
                    settingsSection(
                        title: String(localized: "Multi-Verse", comment: "Settings section"),
                        icon: "text.justify.leading",
                        isExpanded: $multiVerseExpanded
                    ) {
                        multiVerseSection
                    }
                }

                if sections.contains(.general) {
                    // ─── General ───
                    settingsSection(
                        title: String(localized: "General", comment: "Settings section"),
                        icon: "gearshape",
                        isExpanded: $generalExpanded
                    ) {
                        generalSection
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Section Builder

    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(title)
                        .font(.caption.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .padding(.leading, 22)
                .padding(.bottom, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Divider()
        }
    }

    // MARK: - Text & Font Section

    @ViewBuilder
    private func textAndFontSection(pmBinding: Bindable<PresentationManager>) -> some View {
        // Font family
        HStack {
            Text(String(localized: "Font:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: pmBinding.fontName) {
                Text(String(localized: "System", comment: "Font option")).tag("System")
                ForEach(availableFonts, id: \.self) { font in
                    Text(font).tag(font)
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }

        // Font size
        HStack {
            Text(String(localized: "Size:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Slider(
                value: pmBinding.fontSize,
                in: PresentationDefaults.minFontSize...PresentationDefaults.maxFontSize,
                step: 2
            )
            .controlSize(.small)
            Text("\(Int(pm.fontSize)) pt")
                .font(.caption.monospacedDigit())
                .frame(width: 35)
        }

        // Text color + alignment
        HStack {
            Text(String(localized: "Color:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            ColorPicker(
                "",
                selection: Binding(
                    get: { pm.textColor },
                    set: { pm.textColorHex = $0.toHex() }
                )
            )
            .labelsHidden()

            Spacer()

            Text(String(localized: "Align:", comment: "Setting label"))
                .font(.caption)
            Picker("", selection: pmBinding.textAlignment) {
                Image(systemName: "text.alignleft").tag(TextAlignment.leading)
                Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                Image(systemName: "text.alignright").tag(TextAlignment.trailing)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 100)
        }

        // Line spacing
        HStack {
            Text(String(localized: "Spacing:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Slider(value: pmBinding.lineSpacing, in: 0.8...3.0, step: 0.1)
                .controlSize(.small)
            Text(String(format: "%.1f", pm.lineSpacing))
                .font(.caption.monospacedDigit())
                .frame(width: 25)
        }

        // Padding
        HStack {
            Text(String(localized: "Padding:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Slider(value: pmBinding.padding, in: 10...100, step: 5)
                .controlSize(.small)
            Text("\(Int(pm.padding))")
                .font(.caption.monospacedDigit())
                .frame(width: 25)
        }

        // Shadow
        HStack {
            Text(String(localized: "Shadow:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Toggle("", isOn: pmBinding.shadowEnabled)
                .labelsHidden()
                .controlSize(.small)

            if pm.shadowEnabled {
                Slider(value: pmBinding.shadowRadius, in: 0...20, step: 0.5)
                    .controlSize(.small)
                Text(String(format: "%.0f", pm.shadowRadius))
                    .font(.caption.monospacedDigit())
                    .frame(width: 20)
            }
        }
    }

    // MARK: - Background Section

    @ViewBuilder
    private func backgroundSection(pmBinding: Bindable<PresentationManager>) -> some View {
        // Enable background toggle
        Toggle(isOn: pmBinding.backgroundEnabled) {
            Text(String(localized: "Enable Background", comment: "Setting label"))
                .font(.caption)
        }
        .toggleStyle(.switch)
        .controlSize(.small)

        // Background color (only shown when background is enabled)
        if pm.backgroundEnabled {
            HStack {
                Text(String(localized: "Color:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 55, alignment: .trailing)
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { pm.backgroundColor },
                        set: { pm.backgroundColorHex = $0.toHex() }
                    )
                )
                .labelsHidden()
            }
        }

        // Background opacity
        HStack {
            Text(String(localized: "Opacity:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Slider(value: pmBinding.backgroundOpacity, in: 0...1)
                .controlSize(.small)
            Text("\(Int(pm.backgroundOpacity * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 35)
        }

        // Background image
        HStack {
            Text(String(localized: "Image:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)

            if pm.useBackgroundImage, let path = pm.backgroundImagePath {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    pm.removeBackgroundImage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            Button(String(localized: "Choose…", comment: "Button")) {
                selectBackgroundImage()
            }
            .controlSize(.small)
        }

        // Image preview
        if let bgImage = pm.backgroundImage, pm.useBackgroundImage {
            HStack {
                Spacer()
                Image(nsImage: bgImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(pm.backgroundOpacity)
                    .frame(maxHeight: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Spacer()
            }
        }
    }

    // MARK: - Display & Output Section

    @ViewBuilder
    private func displaySection(pmBinding: Bindable<PresentationManager>) -> some View {
        // Target screen
        HStack {
            Text(String(localized: "Screen:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: pmBinding.presentationScreenIndex) {
                Text(String(localized: "Auto", comment: "Picker option"))
                    .tag(nil as Int?)
                ForEach(Array(pm.availableScreens.enumerated()), id: \.offset) { index, screen in
                    Text(screen.localizedName).tag(index as Int?)
                }
            }
            .labelsHidden()
            .controlSize(.small)

            Button {
                pm.refreshScreens()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Refresh Screens", comment: "Button tooltip"))
        }

        // Window level / position
        HStack {
            Text(String(localized: "Window:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: pmBinding.windowLevel) {
                Text(String(localized: "Normal", comment: "Window level option")).tag("normal")
                Text(String(localized: "Floating", comment: "Window level option")).tag("floating")
                Text(String(localized: "Always on Top", comment: "Window level option")).tag("alwaysOnTop")
                Text(String(localized: "Behind Desktop", comment: "Window level option")).tag("behindDesktop")
            }
            .labelsHidden()
            .controlSize(.small)
        }

        // Transition duration
        HStack {
            Text(String(localized: "Transition:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Slider(value: pmBinding.transitionDuration, in: 0...2, step: 0.1)
                .controlSize(.small)
            Text(String(format: "%.1fs", pm.transitionDuration))
                .font(.caption.monospacedDigit())
                .frame(width: 30)
        }
    }

    // MARK: - Multi-Verse Section

    @ViewBuilder
    private var multiVerseSection: some View {
        // Layout
        HStack {
            Text(String(localized: "Layout:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: $multiVerseLayout) {
                Text(String(localized: "Inline", comment: "Layout option")).tag("inline")
                Text(String(localized: "New Line", comment: "Layout option")).tag("newLine")
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
        }

        // Verse prefix
        HStack {
            Text("")
                .frame(width: 55)
            Toggle(String(localized: "Show verse number prefix", comment: "Setting label"), isOn: $showVerseNumberPrefix)
                .font(.caption)
                .controlSize(.small)
        }
    }

    // MARK: - General Section

    @ViewBuilder
    private var generalSection: some View {
        // Quick-access toggles relevant during presentation
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("")
                    .frame(width: 55)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "Afișează numerele versetelor", comment: "Setting label"), isOn: $showVerseNumbers)
                    Toggle(String(localized: "Afișează referințe încrucișate", comment: "Setting label"), isOn: $showCrossReferences)
                    Toggle(String(localized: "Afișează note de subsol", comment: "Setting label"), isOn: $showFootnotes)
                }
                .font(.caption)
                .controlSize(.small)
            }
        }

        // Link to full settings
        HStack {
            Spacer()
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gearshape")
                        .font(.caption2)
                    Text(String(localized: "Mai multe setări...", comment: "Button"))
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            pm.setBackgroundImage(from: url)
        }
    }
}
