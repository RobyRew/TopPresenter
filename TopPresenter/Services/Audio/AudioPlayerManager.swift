//
//  AudioPlayerManager.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import AVFoundation
import Observation

@Observable
final class AudioPlayerManager {
    // MARK: - State
    var isPlaying: Bool = false
    var isMuted: Bool = false
    var volume: Float = 1.0
    var playbackSpeed: Float = 1.0
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentFileName: String = ""

    // MARK: - Private
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

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

    var formattedRemaining: String {
        formatTime(max(0, duration - currentTime))
    }

    // MARK: - Playback Controls

    func loadAudio(url: URL) {
        stop()

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.prepareToPlay()
            audioPlayer?.volume = isMuted ? 0 : volume
            audioPlayer?.enableRate = true
            audioPlayer?.rate = playbackSpeed
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
            currentFileName = url.lastPathComponent
        } catch {
            print("Error loading audio: \(error.localizedDescription)")
        }
    }

    func play() {
        audioPlayer?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer?.currentTime = 0
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    func seekToProgress(_ progress: Double) {
        let time = progress * duration
        seek(to: time)
    }

    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        if !isMuted {
            audioPlayer?.volume = volume
        }
    }

    func toggleMute() {
        isMuted.toggle()
        audioPlayer?.volume = isMuted ? 0 : volume
    }

    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = max(0.5, min(2.0, speed))
        audioPlayer?.rate = playbackSpeed
    }

    func skipForward(seconds: TimeInterval = 10) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }

    func skipBackward(seconds: TimeInterval = 10) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    // MARK: - Private Methods

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let player = self.audioPlayer {
                    self.currentTime = player.currentTime
                    if !player.isPlaying && self.isPlaying {
                        self.isPlaying = false
                        self.stopTimer()
                    }
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // isolated deinit (SE-0371, native Swift 6.1+): runs ON the main actor so it
    // may touch the MainActor-isolated timer state safely.
    isolated deinit {
        stopTimer()
    }
}
