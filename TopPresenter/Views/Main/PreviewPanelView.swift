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

// MARK: - Preview Card (1:1 representation of the output screen)
struct PresentationPreviewCard: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager
    @AppStorage("multiVerseLayout") private var multiVerseLayout: String = "inline"
    @AppStorage("showVerseNumberPrefix") private var showVerseNumberPrefix: Bool = false

    /// Pass `true` when rendering Bible content so the translation name is populated.
    var isBibleContent: Bool = false

    /// Content key of the hosting panel ("bible"/"song"/"text") — used to apply
    /// the right per-presenter options when previewing pending (not live) content.
    var formatHint: String? = nil

    private var activeContentKey: String {
        if pm.liveContent.isLive {
            return PresentationManager.contentKey(for: pm.liveContent.contentType)
        }
        return formatHint ?? (isBibleContent ? "bible" : "text")
    }

    /// Content a non-Bible panel (songs, slides, schedule) wants previewed before it
    /// goes live. When nil, the card falls back to the Bible verse selection.
    struct PendingContent {
        var text: String
        var reference: String
        var subtitle: String = ""
    }
    var pendingContent: PendingContent? = nil

    /// What would go live next: the panel-supplied content, or the Bible selection.
    private var pendingText: String {
        if let pendingContent { return pendingContent.text }
        guard !libraryManager.selectedVerses.isEmpty else { return "" }
        return libraryManager.formattedSelectedVersesText(
            layout: multiVerseLayout, showPrefix: showVerseNumberPrefix
        )
    }

    private var pendingReference: String {
        if let pendingContent { return pendingContent.reference }
        guard !libraryManager.selectedVerses.isEmpty else { return "" }
        return libraryManager.selectedVersesReference
    }

    /// Text to preview: when frozen show the pending content (what will go live next),
    /// when live show the live content, otherwise show the pending content.
    private var previewText: String {
        if pm.isFrozen && !pendingText.isEmpty {
            return pendingText
        }
        if pm.liveContent.isLive, !pm.liveContent.mainText.isEmpty {
            return pm.liveContent.mainText
        }
        return pendingText
    }

    private var previewReference: String {
        if pm.isFrozen && !pendingText.isEmpty {
            return pendingReference
        }
        if pm.liveContent.isLive, !pm.liveContent.reference.isEmpty {
            return pm.liveContent.reference
        }
        return pendingReference
    }

    private var previewSubtitle: String {
        if pm.isFrozen, let pendingContent, !pendingContent.text.isEmpty {
            return pendingContent.subtitle
        }
        if pm.liveContent.isLive {
            return pm.liveContent.subtitle
        }
        return pendingContent?.subtitle ?? ""
    }

    /// Translation name shown in the preview: live value when live, module abbrev otherwise.
    private var previewTranslationName: String {
        guard isBibleContent else { return "" }
        if pm.liveContent.isLive { return pm.liveContent.translationName }
        return libraryManager.selectedBibleModule?.abbreviation ?? ""
    }

    // Rich Bible casete sources for the preview (mirror the live values when
    // live, else derive from the current selection so they show before going live).
    private var previewFootnote: String {
        pm.liveContent.isLive ? pm.liveContent.footnote : (isBibleContent ? libraryManager.selectedVersesFootnotes : "")
    }
    private var previewCrossReference: String {
        pm.liveContent.isLive ? pm.liveContent.crossReference : (isBibleContent ? libraryManager.selectedVersesCrossRefs : "")
    }
    private var previewHeading: String {
        pm.liveContent.isLive ? pm.liveContent.heading : (isBibleContent ? libraryManager.selectedVersesHeading : "")
    }
    private var previewGloss: String {
        pm.liveContent.isLive ? pm.liveContent.gloss : (isBibleContent ? libraryManager.selectedVersesGloss : "")
    }
    private var previewStrongs: String {
        pm.liveContent.isLive ? pm.liveContent.strongs : (isBibleContent ? libraryManager.selectedVersesStrongs : "")
    }
    /// Red-letter runs for the main verse box (woc styling). Empty unless the
    /// theme has it enabled and the verse carries words-of-Christ.
    private var previewRuns: [VerseRun] {
        guard pm.wocStyleEnabled, isBibleContent else { return [] }
        return pm.liveContent.isLive ? pm.liveContent.mainRuns : libraryManager.selectedVersesRuns
    }

    private var hasContent: Bool { !previewText.isEmpty }

    private var isPreviewOnly: Bool {
        let notLiveYet = !pm.liveContent.isLive && !pendingText.isEmpty
        let frozenAndPreparing = pm.isFrozen && !pendingText.isEmpty
        return notLiveYet || frozenAndPreparing
    }

    /// The metrics of the target screen.
    private var metrics: PresentationManager.ScreenMetrics {
        pm.targetScreenMetrics
    }

    var body: some View {
        // Outer frame: let SwiftUI determine the width, then constrain height via aspectRatio.
        Color.clear
            .aspectRatio(metrics.aspectRatio, contentMode: .fit)
            .overlay(
                GeometryReader { geo in
                    cardContent(size: geo.size)
                }
            )
    }

    @ViewBuilder
    private func cardContent(size: CGSize) -> some View {
        ZStack {
                // Black bg (stands in for transparent on projector)
                Color.black

                // Background layers — per-content override or global
                if pm.isBlackScreen {
                    // Full black — nothing else rendered
                } else {
                    let bg = pm.activeBackground(forKey: activeContentKey, frozen: false)
                    if bg.showColor {
                        bg.color
                    }
                    if bg.useMedia {
                        BackgroundMediaView(background: bg, plays: false)
                    }

                    // Content + media — same unified stacking order as the output, scaled.
                    previewBoxes(size: size)
                }

                // Edit Mode: box overlays — drag to move, corner handles to resize
                if pm.isEditMode {
                    TextBoxEditOverlay(canvasSize: size, showsHiddenBoxes: false)
                }

                // Badges overlay
                badges(size: size)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isPreviewOnly ? Color.blue.opacity(0.5) : Color.gray.opacity(0.3),
                        lineWidth: isPreviewOnly ? 1.5 : 1
                    )
            )
            .shadow(radius: 2)
    }

    @ViewBuilder
    private func previewBoxes(size: CGSize) -> some View {
        // `targetScale` = the 1080p-reference font scale of the target screen;
        // `canvasScale` shrinks everything down to preview size.
        let targetScale = pm.targetFontScale
        let canvasScale = size.width / max(metrics.points.width, 1)
        let dim = isPreviewOnly ? 0.6 : 1.0

        // Transforms (MAJUSCULE etc.) are part of each box's resolved style.
        let fields = (main: previewText, reference: previewReference,
                      translation: previewTranslationName, subtitle: previewSubtitle)

        // Render with the PANEL'S profile — the Songs panel previews the song
        // layout even while a Bible verse is live on the output.
        let key = activeContentKey

        ZStack(alignment: .topLeading) {
            // Unified stacking order — exactly what the output renders
            ForEach(pm.orderedBoxTokens(in: key), id: \.self) { token in
                switch boxIdentity(fromToken: token) {
                case .section(let section):
                    if pm.isSectionVisible(section, in: key),
                       !pm.liveContent.isLive || pm.scopeMatchesLiveSlide(pm.displayScope(for: section, in: key)) {
                        let text = pm.sectionText(
                            section,
                            main: fields.main, reference: fields.reference,
                            translation: fields.translation, subtitle: fields.subtitle,
                            slideNumber: pm.liveContent.slideNumberText,
                            in: key
                        )
                        if !text.isEmpty {
                            let rect = pm.boxFrame(for: section, in: key).rect(in: size)
                            let style = pm.resolvedStyle(for: section, in: key)

                            // Auto-fit: computed at FULL resolution then scaled — same math as output
                            let fitted: CGFloat? = style.autoFit
                                ? pm.fittedVerseFontSize(
                                    text: text,
                                    boxSize: pm.boxFrame(for: section, in: key).rect(in: metrics.points).size,
                                    maxSize: CGFloat(style.fontSize) * targetScale,
                                    padding: CGFloat(style.padding) * targetScale,
                                    fontName: style.fontName,
                                    lineSpacing: style.lineSpacing
                                  ) * canvasScale
                                : nil

                            previewBoxText(text, style: style, rect: rect, fontScale: targetScale * canvasScale, fittedSize: fitted, dim: dim,
                                           runs: section == .verseContent ? previewRuns : [])
                        }
                    }
                case .custom(let id):
                    if let box = pm.customTextBox(id: id, in: key), box.isVisible,
                       !pm.liveContent.isLive || pm.scopeMatchesLiveSlide(box.displayOnRaw) {
                        let text = box.resolvedText(
                            main: fields.main, reference: fields.reference,
                            translation: fields.translation, subtitle: fields.subtitle,
                            slideNumber: pm.liveContent.slideNumberText,
                            footnote: previewFootnote, crossReference: previewCrossReference,
                            heading: previewHeading, gloss: previewGloss, strongs: previewStrongs
                        )
                        if !text.isEmpty {
                            let rect = box.frame.rect(in: size)
                            let style = pm.resolvedCustomStyle(box, in: key)
                            let fitted: CGFloat? = style.autoFit
                                ? pm.fittedVerseFontSize(
                                    text: text,
                                    boxSize: box.frame.rect(in: metrics.points).size,
                                    maxSize: CGFloat(style.fontSize) * targetScale,
                                    padding: CGFloat(style.padding) * targetScale,
                                    fontName: style.fontName,
                                    lineSpacing: style.lineSpacing
                                  ) * canvasScale
                                : nil
                            previewBoxText(text, style: style, rect: rect, fontScale: targetScale * canvasScale, fittedSize: fitted, dim: dim)
                        }
                    }
                case .media(let id):
                    if let box = pm.mediaBox(id: id, in: key),
                       box.isVisible,
                       box.showsFor(contentType: pm.liveContent.contentType, isLive: pm.liveContent.isLive) {
                        MediaBoxContent(box: box, canvasSize: size, playsVideo: false)
                            .allowsHitTesting(false)
                    }
                case nil:
                    EmptyView()
                }
            }
        }
    }

    private func previewBoxText(
        _ text: String,
        style: PresentationManager.ResolvedBoxStyle,
        rect: CGRect, fontScale: CGFloat,
        fittedSize: CGFloat?, dim: Double,
        runs: [VerseRun] = []
    ) -> some View {
        let size = fittedSize ?? CGFloat(style.fontSize) * fontScale
        // Red-letter: compose from runs (coloring woc) whenever the run stream
        // carries words-of-Christ. Runs reconstruct the verse, so the text stays
        // correct; an exact string match was too strict (prefix/whitespace).
        let useRuns = runs.contains { $0.kind == "woc" }
        let composed: Text = useRuns
            ? runs.reduce(Text("")) { acc, run in
                let c = (run.kind == "woc") ? pm.wocColor : style.color
                return acc + Text(style.display(run.text)).foregroundColor(c.opacity(style.opacity * dim))
              }
            : Text(style.display(text)).foregroundColor(style.color.opacity(style.opacity * dim))
        return composed
            .font(style.font(at: size))
            .multilineTextAlignment(style.hAlign)
            .lineSpacing(style.lineSpacing * size * 0.1)
            .tracking(style.tracking * fontScale)
            .minimumScaleFactor(fittedSize == nil ? 0.3 : 1.0)
            .shadow(
                color: style.shadowEnabled ? style.shadowColor : .clear,
                radius: style.shadowEnabled ? style.shadowRadius * fontScale : 0,
                x: 0,
                y: style.shadowEnabled ? 2 * fontScale : 0
            )
            .padding(.horizontal, CGFloat(style.padding) * fontScale)
            .frame(width: rect.width, height: rect.height, alignment: style.frameAlignment)
            .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func badges(size: CGSize) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    if pm.isFrozen && isPreviewOnly {
                        Text("FROZEN")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.8), in: Capsule())
                    }
                    if isPreviewOnly {
                        Text("PREVIEW")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.7), in: Capsule())
                    }
                }
                .padding(6)
            }
            Spacer()

            HStack(spacing: 6) {
                if !pm.backgroundEnabled && !pm.isBlackScreen {
                    HStack(spacing: 3) {
                        Image(systemName: "checkerboard.rectangle")
                            .font(.system(size: 8))
                        Text(String(localized: "Transparent", comment: "Preview badge"))
                            .font(.system(size: 8, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.5), in: Capsule())
                }

                Spacer()

                HStack(spacing: 3) {
                    Image(systemName: "display")
                        .font(.system(size: 7))
                    Text("\(Int(metrics.resolution.width))×\(Int(metrics.resolution.height))")
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                    Text(metrics.aspectRatioLabel)
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(.black.opacity(0.5), in: Capsule())
            }
            .padding(6)
        }
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

    /// How many verses can fit in the verse text box from the current starting verse.
    /// Font and padding are scaled to the target screen (1080p reference) so the
    /// count matches what the output actually renders.
    private var maxFittingCount: Int {
        libraryManager.versesCountThatFits(
            fontSize: pm.fontSize * pm.targetFontScale,
            fontName: pm.fontName,
            lineSpacing: pm.lineSpacing,
            padding: pm.padding * pm.targetFontScale,
            screenSize: pm.verseBoxPointSize,
            layout: multiVerseLayout,
            showPrefix: showVerseNumberPrefix
        )
    }

    private func runAutoFill() {
        libraryManager.autoFillVerses(
            fontSize: pm.fontSize * pm.targetFontScale,
            fontName: pm.fontName,
            lineSpacing: pm.lineSpacing,
            padding: pm.padding * pm.targetFontScale,
            screenSize: pm.verseBoxPointSize,
            layout: multiVerseLayout,
            showPrefix: showVerseNumberPrefix
        )
    }

    /// Push the current selection to live output.
    private func updateLiveOutput() {
        guard pm.liveContent.isLive else { return }
        pm.showBibleVerse(
            text: formattedText,
            reference: libraryManager.selectedVersesReference,
            translationName: libraryManager.selectedBibleModule?.abbreviation ?? "",
            runs: libraryManager.selectedVersesRuns,
            footnote: libraryManager.selectedVersesFootnotes,
            crossReference: libraryManager.selectedVersesCrossRefs,
            heading: libraryManager.selectedVersesHeading,
            gloss: libraryManager.selectedVersesGloss,
            strongs: libraryManager.selectedVersesStrongs
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

                // Show button — sends the current selection to the live output
                Button {
                    pm.showBibleVerse(
                        text: formattedText,
                        reference: libraryManager.selectedVersesReference,
                        translationName: libraryManager.selectedBibleModule?.abbreviation ?? "",
                        runs: libraryManager.selectedVersesRuns,
                        footnote: libraryManager.selectedVersesFootnotes,
                        crossReference: libraryManager.selectedVersesCrossRefs,
                        heading: libraryManager.selectedVersesHeading,
                        gloss: libraryManager.selectedVersesGloss,
                        strongs: libraryManager.selectedVersesStrongs
                    )
                } label: {
                    Label(
                        String(localized: "Show", comment: "Control button"),
                        systemImage: "play.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(libraryManager.selectedVerses.isEmpty)

                // Hide button — clears the live output
                Button {
                    pm.clearOutput()
                } label: {
                    Label(
                        String(localized: "Hide", comment: "Control button"),
                        systemImage: "eye.slash.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(height: 36)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!isLive)

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
        // Re-fill when the verse text box is moved/resized in Edit Mode
        .onChange(of: pm.boxFrame(for: .verseContent, in: "bible")) {
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
/// Detects a Force Touch (deep press) over its bounds via a local event monitor.
/// A monitor is required because the view passes clicks through to the button
/// underneath (hitTest returns nil), so it never receives pressure events directly.
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

    static func dismantleNSView(_ nsView: ForceTouchNSView, coordinator: ()) {
        nsView.removeMonitor()
    }

    class ForceTouchNSView: NSView {
        var onForceTouch: (() -> Void)?
        private var didTrigger = false
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
            } else if monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .pressure) { [weak self] event in
                    self?.handlePressure(event)
                    return event
                }
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        private func handlePressure(_ event: NSEvent) {
            guard event.window === window else { return }
            let location = convert(event.locationInWindow, from: nil)

            // Stage 2 = Force Touch (deep press) within our bounds
            if event.stage == 2, !didTrigger, bounds.contains(location) {
                didTrigger = true
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

        deinit {
            removeMonitor()
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
        case multiVerse, general, songOptions, output

        static let allSet: Set<SettingsSection> = [.multiVerse, .general, .output]
    }

    @Environment(\.openSettings) private var openSettings
    @Environment(PresentationManager.self) private var pm

    @AppStorage("settingsExpanded_multiVerse") private var multiVerseExpanded: Bool = false
    @AppStorage("settingsExpanded_general") private var generalExpanded: Bool = false
    @AppStorage("settingsExpanded_songOptions") private var songOptionsExpanded: Bool = true
    @AppStorage("settingsExpanded_output") private var outputExpanded: Bool = false

    // Song options
    @AppStorage("song_maxLinesPerSlide") private var songMaxLines: Int = 6
    @AppStorage("song_bilingual") private var songBilingual: Bool = false
    @AppStorage("song_repeatStyle") private var songRepeatStyle: String = "none"

    // General settings
    @AppStorage("showVerseNumbers") private var showVerseNumbers: Bool = true
    @AppStorage("showCrossReferences") private var showCrossReferences: Bool = false
    @AppStorage("showFootnotes") private var showFootnotes: Bool = false
    @AppStorage("multiVerseLayout") private var multiVerseLayout: String = "inline"
    @AppStorage("showVerseNumberPrefix") private var showVerseNumberPrefix: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
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

                if sections.contains(.songOptions) {
                    // ─── Cântece (song presentation options) ───
                    settingsSection(
                        title: String(localized: "Cântece", comment: "Settings section"),
                        icon: "music.note",
                        isExpanded: $songOptionsExpanded
                    ) {
                        songOptionsSection
                    }
                }

                if sections.contains(.output) {
                    // ─── Ieșire (output hardware) ───
                    settingsSection(
                        title: String(localized: "Ieșire", comment: "Settings section"),
                        icon: "tv",
                        isExpanded: $outputExpanded
                    ) {
                        outputSection
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

    // MARK: - Cântece Section (song presentation options)

    @ViewBuilder
    private var songOptionsSection: some View {
        HStack {
            Text(String(localized: "Linii/slide:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 70, alignment: .trailing)
            Stepper(value: $songMaxLines, in: 0...20) {
                Text(songMaxLines == 0
                     ? String(localized: "Nelimitat", comment: "Setting value")
                     : "\(songMaxLines)")
                    .font(.caption)
            }
            .controlSize(.small)
        }

        Toggle(String(localized: "Linie de traducere (bilingv)", comment: "Setting label"), isOn: $songBilingual)
            .font(.caption)
            .controlSize(.small)

        HStack {
            Text(String(localized: "Repetare:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 70, alignment: .trailing)
            Picker("", selection: $songRepeatStyle) {
                Text(String(localized: "Fără", comment: "Repeat style")).tag("none")
                Text("/: :/").tag("slash")
                Text("‖: :‖").tag("bar")
                Text("|: :|").tag("pipe")
                Text("(×N)").tag("times")
                Text("bis/ter").tag("bister")
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }

    // MARK: - Ieșire Section (output screen, compact)

    @ViewBuilder
    private var outputSection: some View {
        @Bindable var pmBinding = pm

        HStack {
            Text(String(localized: "Ecran:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: $pmBinding.presentationScreenIndex) {
                Text(String(localized: "Auto", comment: "Picker option")).tag(nil as Int?)
                ForEach(Array(pm.availableScreens.enumerated()), id: \.offset) { index, screen in
                    Text(screen.localizedName).tag(index as Int?)
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .help(String(localized: "Ecranul pe care se proiectează", comment: "Tooltip"))

        HStack {
            Text(String(localized: "Nivel:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: $pmBinding.windowLevel) {
                Text(String(localized: "Normal", comment: "Window level option")).tag("normal")
                Text(String(localized: "Floating", comment: "Window level option")).tag("floating")
                Text(String(localized: "Always on Top", comment: "Window level option")).tag("alwaysOnTop")
                Text(String(localized: "Behind Desktop", comment: "Window level option")).tag("behindDesktop")
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .help(String(localized: "Nivelul ferestrei de proiecție", comment: "Tooltip"))

        HStack {
            Text(String(localized: "Deconect.:", comment: "Setting label"))
                .font(.caption)
                .frame(width: 55, alignment: .trailing)
            Picker("", selection: Binding(
                get: { pm.screenDisconnectAction.rawValue },
                set: { pm.screenDisconnectAction = PresentationManager.ScreenDisconnectAction(rawValue: $0) ?? .ask }
            )) {
                Text(String(localized: "Întreabă", comment: "Disconnect option")).tag("ask")
                Text(String(localized: "Mută pe alt ecran", comment: "Disconnect option")).tag("moveToAvailable")
                Text(String(localized: "Ecran negru", comment: "Disconnect option")).tag("goBlack")
                Text(String(localized: "Nu face nimic", comment: "Disconnect option")).tag("doNothing")
            }
            .labelsHidden()
            .controlSize(.small)
        }
        .help(String(localized: "Ce se întâmplă când ecranul de proiecție se deconectează", comment: "Tooltip"))

        // Link to full projection settings
        HStack {
            Spacer()
            Button {
                openSettings()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tv")
                        .font(.caption2)
                    Text(String(localized: "Toate setările de proiecție...", comment: "Button"))
                        .font(.caption)
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
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
                openSettings()
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

}
