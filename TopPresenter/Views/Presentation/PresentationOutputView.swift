//
//  PresentationOutputView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import AppKit
import AVKit

/// The presentation output window — displayed fullscreen on the target screen/projector.
/// Transparent by default: when nothing is being shown, the projector sees through it.
/// The NSWindow is configured as borderless, transparent, and always-on-top.
struct PresentationOutputView: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(VideoPlayerService.self) private var videoService
    /// Live master switch for the interlinear grid (theme holds the styling).
    @AppStorage("interlinearLiveEnabled") private var interlinearLiveEnabled = true

    var body: some View {
        ZStack {
            if !pm.isBlackScreen {
                // Background layer — part of the Intrare/Ieșire story: it fades
                // in from transparency with the first Show and fades back out on
                // Hide/Clear/ESC (the show/clear methods drive the animation).
                if pm.liveContent.isLive {
                    backgroundLayer
                        .transition(.opacity)
                }

                // Unified box layer: media + text boxes in ONE user-controlled
                // stacking order (pm.orderedBoxTokens). Always mounted — media
                // marked "always" shows even when nothing is live.
                unifiedLayer
                    .animation(
                        .easeInOut(duration: pm.resolvedTransitionDuration(in: pm.outputProfileKey)),
                        value: liveFingerprint
                    )
            }

            // Full-screen video layer (Media module → Play Video).
            // Stays mounted during black screen — the overlay covers it — so
            // toggling black doesn't tear down the player view mid-playback.
            if pm.liveContent.isLive,
               pm.liveContent.contentType == .media,
               let player = videoService.player {
                OutputVideoView(player: player, fills: pm.fullscreenVideoFillRaw == "fill")
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Black screen mode — full opaque black overlay on top
            if pm.isBlackScreen {
                Color.black
                    .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // NO .background(.black) — the window is transparent by default
        .background(TransparentWindowConfigurator())
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                pm.applyScreenPosition()
            }
        }
        .onChange(of: pm.presentationScreenIndex) { _, _ in
            pm.applyScreenPosition()
        }
    }

    /// One string that changes whenever the on-screen text should transition —
    /// drives the enter/exit animations of every box.
    private var liveFingerprint: String {
        let l = pm.liveContent
        return "\(l.isLive)|\(l.contentType)|\(l.mainText)|\(l.reference)|\(l.subtitle)|\(l.translationName)|\(l.slideIndex)/\(l.slideCount)"
    }

    // MARK: - Background Layer
    // Per-content backgrounds: an enabled override for the current content type
    // replaces the global background (e.g. a dedicated Bible background).
    @ViewBuilder
    private var backgroundLayer: some View {
        let bg = pm.activeBackground(for: pm.liveContent.contentType, frozen: pm.isFrozen)
        ZStack {
            if bg.showColor {
                bg.color
                    .ignoresSafeArea()
            }
            if bg.useMedia {
                BackgroundMediaView(background: bg, plays: true)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Unified Box Layer
    // Every box renders inside its FIXED frame with its resolved style, in the
    // user's unified stacking order. Font sizes are authored at 1080p reference
    // height and scaled to the actual screen — fully resolution/aspect adaptive.
    // A TimelineView drives live clock boxes (date/time sources).
    @ViewBuilder
    private var unifiedLayer: some View {
        if let tick = pm.clockTickInterval {
            TimelineView(.periodic(from: .now, by: tick)) { timeline in
                orderedBoxes(now: timeline.date)
            }
        } else {
            orderedBoxes(now: .now)
        }
    }

    @ViewBuilder
    private func orderedBoxes(now: Date) -> some View {
        GeometryReader { geo in
            let fontScale = PresentationManager.fontScale(forHeight: geo.size.height)
            let live = pm.liveContent
            // Text boxes only render with live (non-video) content; "always"
            // media renders even when idle.
            let textVisible = live.isLive && live.contentType != .media

            ZStack(alignment: .topLeading) {
                // The LIVE content's profile decides boxes, order and transitions
                ForEach(pm.outputOrderedBoxTokens(), id: \.self) { token in
                    orderedBox(token: token, now: now, textVisible: textVisible, canvasSize: geo.size, fontScale: fontScale)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func orderedBox(
        token: String, now: Date, textVisible: Bool,
        canvasSize: CGSize, fontScale: CGFloat
    ) -> some View {
        let live = pm.liveContent
        // Transforms (MAJUSCULE etc.) are part of each box's resolved style.
        let fields = (main: live.mainText, reference: live.reference,
                      translation: live.translationName, subtitle: live.subtitle)
        // Per-profile enter/exit effect; changing .id forces an out+in pair.
        // The token gives the box its own delay (stagger), if configured.
        let boxTransition = pm.boxTransition(in: pm.outputProfileKey, token: token)
        switch boxIdentity(fromToken: token) {
        case .section(let section):
            if textVisible, pm.outputSectionVisible(section),
               !(section == .verseContent && pm.chordsReplaceVerse(in: pm.outputProfileKey, hasChartLines: pm.liveHasChordLines)),
               pm.scopeMatchesLiveSlide(pm.displayScope(for: section, in: pm.outputProfileKey)) {
                let text = pm.sectionText(
                    section,
                    main: fields.main, reference: fields.reference,
                    translation: fields.translation, subtitle: fields.subtitle,
                    now: now, slideNumber: live.slideNumberText, in: pm.outputProfileKey
                )
                if !text.isEmpty {
                    sectionBox(section, text: text, canvasSize: canvasSize, fontScale: fontScale)
                        .id("\(token)|\(text)")
                        .transition(boxTransition)
                }
            }
        case .custom(let id):
            if textVisible, let box = pm.outputCustomTextBoxes.first(where: { $0.id == id }), box.isVisible,
               pm.scopeMatchesLiveSlide(box.displayOnRaw) {
                let text = box.resolvedText(live: live, now: now)
                if !text.isEmpty {
                    let rect = box.frame.rect(in: canvasSize)
                    let style = pm.resolvedCustomStyle(box, in: pm.outputProfileKey)
                    boxText(text, style: style, rect: rect, fontScale: fontScale, fittedSize: fittedSize(text, style: style, rect: rect, fontScale: fontScale))
                        .id("\(token)|\(text)")
                        .transition(boxTransition)
                }
            }
        case .media(let id):
            if let box = pm.outputMediaBoxes.first(where: { $0.id == id }),
               box.isVisible,
               box.showsFor(contentType: live.contentType, isLive: live.isLive),
               !live.isLive || pm.scopeMatchesLiveSlide(box.displayOnRaw) {
                MediaBoxContent(box: box, canvasSize: canvasSize, playsVideo: true)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        case nil:
            EmptyView()
        }
    }

    /// Auto-fit font size for any box whose style asks for it.
    private func fittedSize(
        _ text: String, style: PresentationManager.ResolvedBoxStyle,
        rect: CGRect, fontScale: CGFloat
    ) -> CGFloat? {
        guard style.autoFit else { return nil }
        return pm.fittedVerseFontSize(
            text: text,
            boxSize: rect.size,
            maxSize: CGFloat(style.fontSize) * fontScale,
            padding: CGFloat(style.padding) * fontScale,
            fontName: style.fontName,
            lineSpacing: style.lineSpacing
        )
    }

    @ViewBuilder
    private func sectionBox(
        _ section: TextBoxSection, text: String,
        canvasSize: CGSize, fontScale: CGFloat
    ) -> some View {
        let rect = pm.outputBoxFrame(for: section).rect(in: canvasSize)
        let style = pm.outputStyle(for: section)
        let isBibleVerse = section == .verseContent && pm.outputProfileKey == "bible"
        let allRuns = isBibleVerse ? pm.liveContent.mainRuns : []
        let options = pm.contentOptions(for: pm.outputProfileKey)

        if section == .chords {
            // Chord chart: lyrics (box style) with transposed/capo'd chords (own style) above.
            ChordChartText(lines: pm.transposedSongLines(), lyricStyle: style,
                           chordStyle: pm.outputChordRowStyle(), rect: rect, fontScale: fontScale)
        } else if isBibleVerse, interlinearLiveEnabled, interlinearHasContent(allRuns, options: options) {
            // Interlinear grid takes over the verse box (word-stack columns).
            InterlinearText(columns: interlinearColumns(from: allRuns), style: style,
                            options: options, wocColor: pm.wocColor, rect: rect, fontScale: fontScale)
        } else {
            // Red-letter: only the main verse box, only when enabled and the live
            // verse actually carries words-of-Christ runs.
            let runs: [VerseRun] = (isBibleVerse && pm.wocStyleEnabled
                                    && allRuns.contains { $0.kind == "woc" }) ? allRuns : []
            boxText(text, style: style, rect: rect, fontScale: fontScale,
                    fittedSize: fittedSize(text, style: style, rect: rect, fontScale: fontScale),
                    runs: runs)
        }
    }

    /// Composes a verse from rich runs, coloring `woc` segments with the
    /// theme's words-of-Christ color. Concatenation reproduces the full text.
    private func composedRunText(_ runs: [VerseRun], style: PresentationManager.ResolvedBoxStyle) -> Text {
        // Color EVERY run explicitly — an outer .foregroundColor over a
        // concatenated Text overrides per-segment colors, so woc would be lost.
        runs.reduce(Text("")) { acc, run in
            let c = (run.kind == "woc") ? pm.wocColor : style.color
            return acc + Text(style.display(run.text)).foregroundColor(c.opacity(style.opacity))
        }
    }

    @ViewBuilder
    private func boxText(
        _ text: String,
        style: PresentationManager.ResolvedBoxStyle,
        rect: CGRect, fontScale: CGFloat,
        fittedSize: CGFloat?,
        runs: [VerseRun] = []
    ) -> some View {
        // Padding + shadow are per-box resolved style — global by default.
        let size = fittedSize ?? CGFloat(style.fontSize) * fontScale
        // Build the Text first (tracking/foreground are Text-level); woc runs
        // carry their own color, the rest inherit the box color.
        let composed: Text = runs.isEmpty
            ? Text(style.display(text)).foregroundColor(style.color.opacity(style.opacity))
            : composedRunText(runs, style: style)   // each run already carries its color
        composed
            .tracking(style.tracking * fontScale)
            .font(style.font(at: size))
            .multilineTextAlignment(style.hAlign)
            .lineSpacing(style.lineSpacing * size * 0.1)
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
}

// MARK: - Output Video View
/// Chromeless video surface for the presentation output — AVPlayerView with all
/// controls hidden (the operator controls playback from the Media panel).
struct OutputVideoView: NSViewRepresentable {
    let player: AVPlayer
    var fills: Bool = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        nsView.videoGravity = fills ? .resizeAspectFill : .resizeAspect
    }
}

// MARK: - Transparent Window Configurator
/// An invisible NSView that configures its parent NSWindow to be truly transparent,
/// borderless, and always-on-top — ideal for a projector/external display overlay.
struct TransparentWindowConfigurator: NSViewRepresentable {
    @Environment(PresentationManager.self) private var pm

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = pm.resolvedWindowLevel
            window.styleMask = [.borderless]
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = true
            window.identifier = NSUserInterfaceItemIdentifier(WindowIdentifiers.presentation)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update window level when the user changes it
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            let newLevel = pm.resolvedWindowLevel
            if window.level != newLevel {
                window.level = newLevel
            }
        }
    }
}

#Preview {
    let pm = PresentationManager()
    pm.liveContent.setBibleVerse(
        text: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
        reference: "John 3:16"
    )
    pm.liveContent.isLive = true

    return PresentationOutputView()
        .environment(pm)
        .environment(VideoPlayerService())
        .frame(width: 800, height: 450)
}
