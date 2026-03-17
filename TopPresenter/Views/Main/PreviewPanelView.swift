//
//  PreviewPanelView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Right-side panel showing a live preview of the presentation output and controls.
struct PreviewPanelView: View {
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 0) {
            // Preview header
            HStack {
                Text(String(localized: "Preview", comment: "Panel title"))
                    .font(.headline)
                Spacer()

                // Live indicator
                if presentationManager.liveContent.isLive && !presentationManager.isBlackScreen {
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

            Divider()

            // Preview display (16:9 aspect ratio)
            PresentationPreviewCard()
                .padding()

            Divider()

            // Verse / Slide navigation controls (context-aware)
            VerseSlideControlsBar()
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            // Presentation controls (Black, Freeze, Clear, Open Output)
            PresentationControlsBar()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Audio player (if audio is loaded)
            if !audioPlayerManager.currentFileName.isEmpty {
                AudioControlsView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
            }

            // All settings (collapsible sections)
            StyleQuickSettings()
        }
        .background(.background)
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

    var body: some View {
        ZStack {
            // Background
            if pm.isBlackScreen {
                Color.black
            } else {
                // Background color
                pm.backgroundColor

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
        }
        .aspectRatio(16/9, contentMode: .fit)
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
    @Environment(\.openWindow) private var openWindow

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

            Button {
                openWindow(id: WindowIdentifiers.presentation, value: "main")
                pm.isPresentationWindowOpen = true
            } label: {
                Label(
                    String(localized: "Open Output", comment: "Control button"),
                    systemImage: "rectangle.on.rectangle"
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
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
/// Contains all presentation settings except Import/Export (which stays in Settings window).
struct StyleQuickSettings: View {
    @Environment(PresentationManager.self) private var pm

    @AppStorage("settingsExpanded_text") private var textExpanded: Bool = true
    @AppStorage("settingsExpanded_background") private var backgroundExpanded: Bool = false
    @AppStorage("settingsExpanded_display") private var displayExpanded: Bool = false
    @AppStorage("settingsExpanded_multiVerse") private var multiVerseExpanded: Bool = false
    @AppStorage("settingsExpanded_general") private var generalExpanded: Bool = false

    // General settings
    @AppStorage("startupSection") private var startupSection: String = "bible"
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    @AppStorage("showVerseNumbers") private var showVerseNumbers: Bool = true
    @AppStorage("autoSelectFirstModule") private var autoSelectFirstModule: Bool = true
    @AppStorage("showCrossReferences") private var showCrossReferences: Bool = false
    @AppStorage("showFootnotes") private var showFootnotes: Bool = false
    @AppStorage("rememberLastModule") private var rememberLastModule: Bool = true
    @AppStorage("multiVerseLayout") private var multiVerseLayout: String = "inline"
    @AppStorage("showVerseNumberPrefix") private var showVerseNumberPrefix: Bool = false

    @State private var availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        let pmBinding = Bindable(pm)

        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                // ─── Text & Font ───
                settingsSection(
                    title: String(localized: "Text & Font", comment: "Settings section"),
                    icon: "textformat",
                    isExpanded: $textExpanded
                ) {
                    textAndFontSection(pmBinding: pmBinding)
                }

                // ─── Background ───
                settingsSection(
                    title: String(localized: "Background", comment: "Settings section"),
                    icon: "photo.artframe",
                    isExpanded: $backgroundExpanded
                ) {
                    backgroundSection(pmBinding: pmBinding)
                }

                // ─── Display & Output ───
                settingsSection(
                    title: String(localized: "Display & Output", comment: "Settings section"),
                    icon: "display",
                    isExpanded: $displayExpanded
                ) {
                    displaySection(pmBinding: pmBinding)
                }

                // ─── Multi-Verse ───
                settingsSection(
                    title: String(localized: "Multi-Verse", comment: "Settings section"),
                    icon: "text.justify.leading",
                    isExpanded: $multiVerseExpanded
                ) {
                    multiVerseSection
                }

                // ─── General ───
                settingsSection(
                    title: String(localized: "General", comment: "Settings section"),
                    icon: "gearshape",
                    isExpanded: $generalExpanded
                ) {
                    generalSection
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
        // Background color
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
        // Startup section
        HStack {
            Text(String(localized: "Startup:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: $startupSection) {
                Text(String(localized: "Bible", comment: "Option")).tag("bible")
                Text(String(localized: "Songs", comment: "Option")).tag("songs")
                Text(String(localized: "Schedule", comment: "Option")).tag("schedule")
            }
            .labelsHidden()
            .controlSize(.small)
        }

        // Toggles
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("")
                    .frame(width: 55)
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(String(localized: "Auto-select first Bible module", comment: "Setting label"), isOn: $autoSelectFirstModule)
                    Toggle(String(localized: "Remember last Bible module", comment: "Setting label"), isOn: $rememberLastModule)
                    Toggle(String(localized: "Confirm before deleting", comment: "Setting label"), isOn: $confirmBeforeDelete)
                    Toggle(String(localized: "Show verse numbers", comment: "Setting label"), isOn: $showVerseNumbers)
                    Toggle(String(localized: "Show cross-references", comment: "Setting label"), isOn: $showCrossReferences)
                    Toggle(String(localized: "Show footnotes", comment: "Setting label"), isOn: $showFootnotes)
                }
                .font(.caption)
                .controlSize(.small)
            }
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
