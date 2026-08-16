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

// MARK: - Background Media View

/// Full-bleed background media: image, animated GIF, or looping muted video.
/// `plays == false` (preview card) shows a still thumbnail instead of playing.
struct BackgroundMediaView: View {
    let background: PresentationManager.ActiveBackground
    var plays: Bool = true

    @State private var videoThumb: NSImage?

    var body: some View {
        Group {
            switch background.mediaType {
            case "gif":
                if let url = background.mediaURL {
                    AnimatedGIFView(url: url)
                }
            case "video":
                if plays, let url = background.mediaURL {
                    MediaBoxVideoView(url: url, fills: true)
                } else if let videoThumb {
                    Image(nsImage: videoThumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            default:
                if let image = background.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
            }
        }
        .opacity(background.opacity)
        .task(id: background.mediaURL) {
            if !plays, background.mediaType == "video", let url = background.mediaURL {
                videoThumb = await MediaThumbnailer.thumbnail(for: url, mediaType: "video")
            }
        }
    }
}

// MARK: - Media Thumbnailer

/// Async thumbnails for media files (video first-frame via AVAssetImageGenerator),
/// cached by path. Used by the preview card and the theme gallery.
enum MediaThumbnailer {
    private static let cache = NSCache<NSString, NSImage>()

    static func thumbnail(for url: URL, mediaType: String) async -> NSImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let result: NSImage?
        switch mediaType {
        case "video":
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)
            if let cgImage = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image {
                result = NSImage(cgImage: cgImage, size: .zero)
            } else {
                result = nil
            }
        default:
            result = NSImage(contentsOf: url)
        }

        if let result {
            cache.setObject(result, forKey: key)
        }
        return result
    }

    /// Thumbnail straight from a bookmark (theme gallery cards).
    static func thumbnail(forBookmark bookmark: Data?, mediaType: String) async -> NSImage? {
        guard let bookmark, let url = PresentationManager.resolveBookmark(bookmark) else { return nil }
        return await thumbnail(for: url, mediaType: mediaType)
    }
}

// MARK: - Media Box Content

/// One media box: resolves the file, renders it inside its fixed frame with
/// corner radius, edge feather (soft border fade), and opacity applied.
struct MediaBoxContent: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager: LibraryManager?

    /// What a `sourceRaw == "live"` casetă should show INSTEAD of the live output.
    ///
    /// The Media tab auditions a clip through its OWN player — never the live
    /// `VideoPlayerService` — so it needs to hand that player to the casetă. Only
    /// one `AVPlayerLayer` per `AVPlayer` actually draws, so mirroring the live
    /// player into a second surface would steal the video off the projector.
    struct LiveOverride {
        var image: NSImage? = nil
        var player: AVPlayer? = nil
        var url: URL? = nil
        var kindRaw: String = "image"
    }

    let box: PresentationManager.MediaBox
    let canvasSize: CGSize
    var playsVideo: Bool = false
    var liveOverride: LiveOverride? = nil

    /// Draw the icon-and-filename plate when there is nothing to show.
    ///
    /// True everywhere you are ARRANGING a casetă — the editor canvas and the
    /// preview panel — where an empty box has to remain visible and grabbable,
    /// and where the file name is the only clue about what will land in it.
    ///
    /// False on the REAL output, always. A grey plate reading "photo ·
    /// Untitled.pdf" is a debugging affordance; projecting it in front of a
    /// congregation is just a glitch on the wall. The output shows the content
    /// or it shows nothing.
    var showsPlaceholder: Bool = true

    @State private var image: NSImage?
    @State private var resolvedURL: URL?
    /// First frame of a video this context cannot play (preview card, canvas) —
    /// what will be projected, rather than a grey rectangle with a file name.
    @State private var posterFrame: NSImage?

    var body: some View {
        let rect = box.frame.rect(in: canvasSize)
        let scale = PresentationManager.fontScale(forHeight: canvasSize.height)
        let cornerRadius = box.cornerRadius * scale
        let feather = box.edgeFeather * scale

        content
            .frame(width: rect.width, height: rect.height)
            // Zoom + pan from the Media panel's framing controls. They only ever
            // drove the old full-screen layer, so they went dead the moment the
            // casetă took over the rendering — the sliders were still there,
            // still said they applied live, and did nothing. Panning is a
            // fraction of the CASETĂ now, not of the screen, so it means the same
            // thing whatever size the box is.
            .scaleEffect(framingZoom)
            .offset(x: framingPan.width * rect.width, y: framingPan.height * rect.height)
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
            .task(id: posterSource) {
                guard let url = posterSource, !playsVideo else { return }
                posterFrame = await MediaThumbnailer.thumbnail(for: url, mediaType: "video")
            }
    }

    /// Framing applies to the LIVE casetă only — a decorative logo or a lower
    /// third is placed by its own frame, and must not move when the operator
    /// reframes the clip.
    private var framingZoom: CGFloat {
        box.sourceRaw == "live" ? pm.mediaZoom : 1
    }

    private var framingPan: CGSize {
        guard box.sourceRaw == "live" else { return .zero }
        return CGSize(width: pm.mediaPanX, height: pm.mediaPanY)
    }

    /// The video whose first frame should stand in here, if any.
    private var posterSource: URL? {
        guard box.sourceRaw == "live", !playsVideo else { return nil }
        if let liveOverride {
            return liveOverride.kindRaw == "video" ? liveOverride.url : nil
        }
        guard pm.liveContent.isLive, pm.liveContent.mediaKind == "video" else { return nil }
        return pm.liveContent.mediaURL
    }

    @ViewBuilder
    private var content: some View {
        // A "live" box shows whatever the Media module is playing, so the same
        // casetă serves every clip instead of being bound to one bookmarked file.
        if box.sourceRaw == "live" {
            liveContent
        } else {
            fileContent
        }
    }

    @ViewBuilder
    private var liveContent: some View {
        let isStill = MediaKind.rendersAsStillImage(rawValue: pm.liveContent.mediaKind)
        if let liveOverride {
            overrideContent(liveOverride)
        } else if let image = pm.liveContent.mediaImage, isStill {
            fitted { Image(nsImage: image) }
        } else if !isStill, let player = pm.videoService?.player, playsVideo {
            OutputVideoView(player: player, fills: box.contentModeRaw == "fill")
        } else if let posterFrame {
            // A video this surface cannot play: its own first frame, so the preview
            // shows what will be projected instead of a grey rectangle.
            fitted { Image(nsImage: posterFrame) }
        } else if let preview = editorPreviewImage {
            // Nothing live, but something is selected in the Media module: preview
            // it so the casetă can be sized against real content rather than a
            // placeholder. The Bible profile does the same with the selected verse.
            fitted { Image(nsImage: preview) }
        } else if let url = pm.liveContent.mediaURL {
            placeholder(icon: pm.liveContent.mediaKind == "video" ? "film" : "photo",
                        caption: url.lastPathComponent)
        } else {
            placeholder(icon: "play.rectangle",
                        caption: String(localized: "Media în direct", comment: "Live media box placeholder"))
        }
    }

    @ViewBuilder
    private func overrideContent(_ override: LiveOverride) -> some View {
        if let player = override.player, playsVideo, override.kindRaw == "video" {
            OutputVideoView(player: player, fills: box.contentModeRaw == "fill")
        } else if let image = override.image {
            fitted { Image(nsImage: image) }
        } else if let posterFrame {
            fitted { Image(nsImage: posterFrame) }
        } else {
            placeholder(icon: (MediaKind(rawValue: override.kindRaw) ?? .image).systemImage,
                        caption: override.url?.lastPathComponent ?? box.fileName)
        }
    }

    /// Fit/fill is a per-casetă setting; every image path honours the same one.
    private func fitted(_ image: () -> Image) -> some View {
        image()
            .resizable()
            .aspectRatio(contentMode: box.contentModeRaw == "fill" ? .fill : .fit)
    }

    /// The Media module's current selection, for previewing while editing. Only
    /// when nothing is live — what is on the projector always wins.
    private var editorPreviewImage: NSImage? {
        guard !pm.liveContent.isLive else { return nil }
        // A clip being auditioned reports the frame under its scrubber, so this
        // casetă tracks the video instead of showing frame zero throughout.
        if let scrubbed = libraryManager?.mediaScrubFrame { return scrubbed }
        guard let item = libraryManager?.selectedMediaItem,
              let url = item.resolvedURL else { return nil }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        if let data = item.thumbnailData, let image = NSImage(data: data) { return image }
        return NSImage(contentsOf: url)
    }

    @ViewBuilder
    private var fileContent: some View {
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
    private func placeholder(icon: String, caption: String? = nil) -> some View {
        if showsPlaceholder {
            ZStack {
                Rectangle().fill(.black.opacity(0.5))
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(caption ?? box.fileName)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 4)
                }
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
        // See OutputVideoView: a decorative looping overlay has even less use for
        // Live Text than the projector does.
        view.allowsVideoFrameAnalysis = false

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
