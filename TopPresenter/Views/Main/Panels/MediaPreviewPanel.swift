//
//  MediaPreviewPanel.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftUI
import SwiftData
import AVKit

/// Right-side panel for Media: media preview, playback controls, background/fullscreen actions.
struct MediaPreviewPanel: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService
    @Environment(\.openWindow) private var openWindow

    @Query(sort: \MediaItem.importDate, order: .reverse) private var allMedia: [MediaItem]

    /// The currently selected media item — passed from MediaView or tracked here.
    @State private var selectedItem: MediaItem?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .media)

            Divider()

            // Media preview area
            mediaPreview
                .padding()

            Divider()

            // Media action buttons
            MediaActionBar(selectedItem: selectedItem)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Presentation controls (Black, Open Output)
            PresentationControlsBar()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Audio controls (if audio playing)
            if !audioPlayerManager.currentFileName.isEmpty {
                AudioControlsView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
            }

            // Video controls (if a video is loaded)
            if videoPlayerService.player != nil {
                VideoControlsView()
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                Divider()
            }

            Spacer()

            Divider()

            // Theme switcher + Layout Editor access
            PanelFooter()
        }
        .background(.background)
        .onKeyWindowNotification(.mediaItemSelected) { notification in
            if let item = notification.object as? MediaItem {
                selectedItem = item
            }
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.black)
                .aspectRatio(16/9, contentMode: .fit)

            if let item = selectedItem {
                if item.mediaType == "image" {
                    if let data = item.thumbnailData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
                } else if item.mediaType == "video" {
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                } else if item.mediaType == "audio" {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(item.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                    Text(String(localized: "Select media to preview", comment: "Placeholder"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .shadow(radius: 2)
    }
}

// MARK: - Media Action Bar
struct MediaActionBar: View {
    let selectedItem: MediaItem?

    @Environment(PresentationManager.self) private var pm
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService

    var body: some View {
        VStack(spacing: 6) {
            if let item = selectedItem {
                HStack(spacing: 6) {
                    Image(systemName: iconForMediaType(item.mediaType))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(item.name)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                    Spacer()
                    Text(item.mediaType.capitalized)
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
            }

            HStack(spacing: 8) {
                if let item = selectedItem {
                    if item.mediaType == "image" {
                        Button {
                            if let url = item.resolvedURL {
                                let accessing = url.startAccessingSecurityScopedResource()
                                pm.setBackgroundImage(from: url)
                                if accessing { url.stopAccessingSecurityScopedResource() }
                            }
                        } label: {
                            Label(
                                String(localized: "Background", comment: "Button"),
                                systemImage: "rectangle.inset.filled"
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if item.mediaType == "audio" {
                        Button {
                            if let url = item.resolvedURL {
                                let accessing = url.startAccessingSecurityScopedResource()
                                audioPlayerManager.loadAudio(url: url)
                                audioPlayerManager.play()
                                if accessing { url.stopAccessingSecurityScopedResource() }
                            }
                        } label: {
                            Label(
                                String(localized: "Play Audio", comment: "Button"),
                                systemImage: "play.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if item.mediaType == "video" {
                        Button {
                            if let url = item.resolvedURL {
                                videoPlayerService.loadVideo(url: url)
                                videoPlayerService.play()
                                pm.showVideo()
                            }
                        } label: {
                            Label(
                                String(localized: "Play Video", comment: "Button"),
                                systemImage: "play.rectangle.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text(String(localized: "No media selected", comment: "Placeholder"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
            }
        }
    }

    private func iconForMediaType(_ type: String) -> String {
        switch type {
        case "image": return "photo"
        case "audio": return "waveform"
        case "video": return "film"
        default: return "doc"
        }
    }
}

// MARK: - Video Controls
/// Transport controls for the video playing on the output window.
struct VideoControlsView: View {
    @Environment(VideoPlayerService.self) private var video
    @Environment(PresentationManager.self) private var pm

    var body: some View {
        @Bindable var videoBinding = video

        VStack(spacing: 8) {
            HStack {
                Text(video.currentFileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(video.formattedCurrentTime) / \(video.formattedDuration)")
                    .font(.caption.monospacedDigit())
            }

            // Progress bar
            Slider(
                value: Binding(
                    get: { video.progress },
                    set: { video.seek(to: $0 * video.duration) }
                ),
                in: 0...1
            )
            .controlSize(.small)

            HStack(spacing: 12) {
                Button { video.togglePlayPause() } label: {
                    Image(systemName: video.isPlaying ? "pause.fill" : "play.fill")
                }
                .help(video.isPlaying
                    ? String(localized: "Pause", comment: "Video control tooltip")
                    : String(localized: "Play", comment: "Video control tooltip"))

                Button {
                    pm.clearOutput()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help(String(localized: "Stop and clear output", comment: "Video control tooltip"))

                Toggle(isOn: $videoBinding.isLooping) {
                    Image(systemName: "repeat")
                }
                .toggleStyle(.button)
                .help(String(localized: "Loop video", comment: "Video control tooltip"))

                Spacer()

                Button { video.toggleMute() } label: {
                    Image(systemName: video.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .help(String(localized: "Mute", comment: "Video control tooltip"))

                Slider(
                    value: Binding(
                        get: { video.volume },
                        set: { video.setVolume($0) }
                    ),
                    in: 0...1
                )
                .frame(width: 80)
                .controlSize(.small)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }
}
