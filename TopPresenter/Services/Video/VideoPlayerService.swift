//
//  VideoPlayerService.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import AVKit
import Observation

@Observable
final class VideoPlayerService {
    var player: AVPlayer?
    var isPlaying: Bool = false
    var isMuted: Bool = false
    var volume: Float = 1.0
    var playbackSpeed: Float = 1.0
    var isLooping: Bool = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentFileName: String = ""

    private var timeObserver: Any?
    private var endObserver: (any NSObjectProtocol)?
    /// URL we hold security-scoped access on for the duration of playback (sandbox).
    private var scopedURL: URL?

    // MARK: - Computed
    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var formattedCurrentTime: String {
        formatTime(currentTime)
    }

    var formattedDuration: String {
        formatTime(duration)
    }

    // MARK: - Controls

    func loadVideo(url: URL) {
        stop()

        // Keep security-scoped access alive while the player streams from the file.
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = isMuted ? 0 : volume
        currentFileName = url.lastPathComponent

        // Observe duration
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let loadedDuration = try? await playerItem.asset.load(.duration) {
                self.duration = loadedDuration.seconds.isNaN ? 0 : loadedDuration.seconds
            }
        }

        // Time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds
            }
        }

        // Loop notification
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isLooping {
                    self.player?.seek(to: .zero)
                    self.player?.play()
                } else {
                    self.isPlaying = false
                }
            }
        }
    }

    func play() {
        player?.playImmediately(atRate: playbackSpeed)
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func stop() {
        player?.pause()
        player?.seek(to: .zero)
        isPlaying = false
        currentTime = 0
        duration = 0
        currentFileName = ""

        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }

        player = nil

        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
    }

    // isolated deinit (SE-0371): main-actor teardown may read isolated state.
    isolated deinit {
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        scopedURL?.stopAccessingSecurityScopedResource()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        if !isMuted {
            player?.volume = volume
        }
    }

    func toggleMute() {
        isMuted.toggle()
        player?.volume = isMuted ? 0 : volume
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = max(0.25, min(2.0, speed))
        if isPlaying {
            player?.rate = playbackSpeed
        }
    }

    // MARK: - Private

    private func formatTime(_ time: TimeInterval) -> String {
        guard !time.isNaN && !time.isInfinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
