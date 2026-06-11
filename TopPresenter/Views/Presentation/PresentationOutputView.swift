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

    var body: some View {
        ZStack {
            if !pm.isBlackScreen {
                // Background layer — per-content override or global
                backgroundLayer

                // Unified box layer: media + text boxes in ONE user-controlled
                // stacking order (pm.orderedBoxTokens). Always mounted — media
                // marked "always" shows even when nothing is live.
                unifiedLayer
                    .animation(.easeInOut(duration: pm.transitionDuration), value: pm.liveContent.mainText)
            }

            // Full-screen video layer (Media module → Play Video).
            // Stays mounted during black screen — the overlay covers it — so
            // toggling black doesn't tear down the player view mid-playback.
            if pm.liveContent.isLive,
               pm.liveContent.contentType == .media,
               let player = videoService.player {
                OutputVideoView(player: player)
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
            let scaledPadding = pm.outputPadding * fontScale
            let live = pm.liveContent
            // Text boxes only render with live (non-video) content; "always"
            // media renders even when idle.
            let textVisible = live.isLive && live.contentType != .media

            ZStack(alignment: .topLeading) {
                ForEach(pm.orderedBoxTokens(), id: \.self) { token in
                    orderedBox(token: token, now: now, textVisible: textVisible, canvasSize: geo.size, fontScale: fontScale, scaledPadding: scaledPadding)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func orderedBox(
        token: String, now: Date, textVisible: Bool,
        canvasSize: CGSize, fontScale: CGFloat, scaledPadding: CGFloat
    ) -> some View {
        let live = pm.liveContent
        switch boxIdentity(fromToken: token) {
        case .section(let section):
            if textVisible, pm.outputSectionVisible(section) {
                let text = pm.sectionText(
                    section,
                    main: live.mainText, reference: live.reference,
                    translation: live.translationName, subtitle: live.subtitle,
                    now: now
                )
                if !text.isEmpty {
                    sectionBox(section, text: text, canvasSize: canvasSize, fontScale: fontScale, scaledPadding: scaledPadding)
                }
            }
        case .custom(let id):
            if textVisible, let box = pm.outputCustomTextBoxes.first(where: { $0.id == id }), box.isVisible {
                let text = box.resolvedText(live: live, now: now)
                if !text.isEmpty {
                    let rect = box.frame.rect(in: canvasSize)
                    let style = pm.resolvedCustomStyle(box)
                    boxText(text, style: style, rect: rect, fontScale: fontScale, scaledPadding: scaledPadding, fittedSize: nil)
                }
            }
        case .media(let id):
            if let box = pm.outputMediaBoxes.first(where: { $0.id == id }),
               box.isVisible,
               box.showsFor(contentType: live.contentType, isLive: live.isLive) {
                MediaBoxContent(box: box, canvasSize: canvasSize, playsVideo: true)
                    .allowsHitTesting(false)
            }
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sectionBox(
        _ section: TextBoxSection, text: String,
        canvasSize: CGSize, fontScale: CGFloat, scaledPadding: CGFloat
    ) -> some View {
        let rect = pm.outputBoxFrame(for: section).rect(in: canvasSize)
        let style = pm.outputStyle(for: section)

        // Auto-fit shrinks the VERSE font so the text fits its box.
        let fitted: CGFloat? = (section == .verseContent)
            ? pm.fittedVerseFontSize(
                text: text,
                boxSize: rect.size,
                maxSize: CGFloat(style.fontSize) * fontScale,
                padding: scaledPadding,
                fontName: style.fontName,
                lineSpacing: style.lineSpacing
              )
            : nil

        boxText(text, style: style, rect: rect, fontScale: fontScale, scaledPadding: scaledPadding, fittedSize: fitted)
    }

    @ViewBuilder
    private func boxText(
        _ text: String,
        style: PresentationManager.ResolvedBoxStyle,
        rect: CGRect, fontScale: CGFloat, scaledPadding: CGFloat,
        fittedSize: CGFloat?
    ) -> some View {
        let size = fittedSize ?? CGFloat(style.fontSize) * fontScale
        Text(text)
            .font(style.font(at: size))
            .foregroundStyle(style.color.opacity(style.opacity))
            .multilineTextAlignment(style.hAlign)
            .lineSpacing(style.lineSpacing * size * 0.1)
            .minimumScaleFactor(fittedSize == nil ? 0.3 : 1.0)
            .shadow(
                color: pm.outputShadowEnabled ? .black.opacity(0.7) : .clear,
                radius: pm.outputShadowEnabled ? pm.outputShadowRadius * fontScale : 0,
                x: 0,
                y: pm.outputShadowEnabled ? 2 * fontScale : 0
            )
            .padding(.horizontal, scaledPadding)
            .frame(width: rect.width, height: rect.height, alignment: style.frameAlignment)
            .position(x: rect.midX, y: rect.midY)
    }
}

// MARK: - Output Video View
/// Chromeless video surface for the presentation output — AVPlayerView with all
/// controls hidden (the operator controls playback from the Media panel).
struct OutputVideoView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
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
