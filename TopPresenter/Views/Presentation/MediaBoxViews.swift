//
//  MediaBoxViews.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 11/06/2026.
//
//  Rendering for MediaBox overlays (logo / picture / GIF / looping video):
//  - MediaBoxContent: one box — clip, edge feather, opacity, fit/fill
//    (rendered inside the unified z-order loop of output/preview/editor)
//  - AnimatedGIFView: NSImageView-backed so GIFs actually animate
//  - MediaBoxVideoView: muted, looping AVPlayerView without controls
//

import SwiftUI
import AppKit
import AVKit

// MARK: - Media Box Content

/// One media box: resolves the file, renders it inside its fixed frame with
/// corner radius, edge feather (soft border fade), and opacity applied.
struct MediaBoxContent: View {
    let box: PresentationManager.MediaBox
    let canvasSize: CGSize
    var playsVideo: Bool = false

    @State private var image: NSImage?
    @State private var resolvedURL: URL?

    var body: some View {
        let rect = box.frame.rect(in: canvasSize)
        let scale = PresentationManager.fontScale(forHeight: canvasSize.height)
        let cornerRadius = box.cornerRadius * scale
        let feather = box.edgeFeather * scale

        content
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .mask(
                // Edge feather: blur an inset mask so the borders fade out softly.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .padding(feather)
                    .blur(radius: feather * 0.7)
            )
            .opacity(box.opacity)
            .position(x: rect.midX, y: rect.midY)
            .task(id: box.bookmarkData) {
                resolvedURL = box.resolvedURL()
                if box.mediaTypeRaw == "image", let url = resolvedURL {
                    image = NSImage(contentsOf: url)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch box.mediaTypeRaw {
        case "gif":
            if let url = resolvedURL {
                AnimatedGIFView(url: url)
            } else {
                placeholder(icon: "photo.badge.exclamationmark")
            }
        case "video":
            if playsVideo, let url = resolvedURL {
                MediaBoxVideoView(url: url, fills: box.contentModeRaw == "fill")
            } else {
                placeholder(icon: "film")
            }
        default:
            if let image {
                if box.contentModeRaw == "fill" {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                }
            } else {
                placeholder(icon: "photo.badge.exclamationmark")
            }
        }
    }

    @ViewBuilder
    private func placeholder(icon: String) -> some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.5))
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                Text(box.fileName)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 4)
            }
        }
    }
}

// MARK: - Animated GIF View

/// NSImageView with `animates = true` — SwiftUI's Image shows only the first
/// frame of a GIF; AppKit's image view plays it.
struct AnimatedGIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.image = NSImage(contentsOf: url)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        // URL changes are handled by SwiftUI identity (task(id:) re-creates the view)
    }
}

// MARK: - Media Box Video View

/// Chromeless, muted, looping video for a media box (decorative overlay).
struct MediaBoxVideoView: NSViewRepresentable {
    let url: URL
    var fills: Bool = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = fills ? .resizeAspectFill : .resizeAspect
        view.allowsPictureInPicturePlayback = false

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer()
        player.isMuted = true
        context.coordinator.looper = AVPlayerLooper(player: player, templateItem: item)
        view.player = player
        player.play()
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.videoGravity = fills ? .resizeAspectFill : .resizeAspect
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        nsView.player?.pause()
        coordinator.looper = nil
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var looper: AVPlayerLooper?
    }
}
