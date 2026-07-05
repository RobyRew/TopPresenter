//
//  MediaPresenter.swift
//  TopPresenter
//
//  THE one way a MediaItem goes live — used by the Media grid (double-click/Enter),
//  the right panel's Proiectează button, and the session runner. Handles security
//  scope, the loop default, and kind dispatch: image/video claim the visual output;
//  audio plays through AudioPlayerManager and leaves the output untouched.
//

import Foundation
import AVFoundation

enum MediaPresenter {
    /// Present a media item on the live output (image/video) or play it (audio).
    static func present(_ item: MediaItem,
                        pm: PresentationManager,
                        video: VideoPlayerService,
                        audio: AudioPlayerManager) {
        guard let url = item.resolvedURL else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        switch MediaKind(rawValue: item.mediaType) ?? .image {
        case .image:
            pm.showMedia(kind: "image", url: url)
        case .video:
            video.loadVideo(url: url)
            video.isLooping = pm.videoLoopsByDefault
            video.play()
            pm.showMedia(kind: "video", url: url)
        case .audio:
            audio.loadAudio(url: url)
            audio.play()
        }
        backfillDurationIfNeeded(item, url: url)
    }

    /// Use an image (or GIF/video) as the global output background.
    static func setAsBackground(_ item: MediaItem, pm: PresentationManager) {
        guard let url = item.resolvedURL else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        pm.setBackgroundMedia(from: url)
    }

    /// Lazily fill `durationSeconds` for video/audio imported before the field
    /// existed (or when import-time probing failed). Fire-and-forget.
    static func backfillDurationIfNeeded(_ item: MediaItem, url: URL) {
        guard item.durationSeconds <= 0, item.mediaType != "image" else { return }
        Task { @MainActor in
            let asset = AVURLAsset(url: url)
            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite, seconds > 0 { item.durationSeconds = seconds }
            }
        }
    }
}
