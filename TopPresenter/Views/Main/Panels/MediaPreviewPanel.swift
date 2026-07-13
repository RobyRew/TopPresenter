//
//  MediaPreviewPanel.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftUI
import SwiftData
import AVKit

/// Right-side panel for Media — mirrors the Bible/Songs panel anatomy:
/// header → preview card → navigation/present controls → transport → quick
/// settings → theme footer. Selection lives on LibraryManager, and prev/next
/// steps the SAME filtered ordering the grid shows (MediaLibrary.filter).
struct MediaPreviewPanel: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService
    @Environment(LibraryManager.self) private var libraryManager

    @Query(sort: \MediaItem.importDate, order: .reverse) private var allMedia: [MediaItem]
    @AppStorage("mediaTypeFilter") private var kindFilterRaw: String = "all"

    private var selectedItem: MediaItem? { libraryManager.selectedMediaItem }

    /// The grid's exact ordering — stepping can never disagree with what's shown.
    private var orderedItems: [MediaItem] {
        MediaLibrary.filter(allMedia, kindRaw: kindFilterRaw, query: libraryManager.mediaLibraryQuery)
    }

    private var pendingMedia: PresentationPreviewCard.PendingMedia? {
        guard let item = selectedItem else { return nil }
        let thumb = item.thumbnailData.flatMap { NSImage(data: $0) }
        return .init(thumbnail: thumb, kindRaw: item.mediaType, name: item.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .media)

            Divider()

            // Preview: pending media letterboxed; live media mirrored.
            PresentationPreviewCard(formatHint: "text", pendingMedia: pendingMedia)
                .padding()

            Divider()

            // Prev / Present / Next — the media counterpart of the verse controls.
            MediaControlsBar(orderedItems: orderedItems)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            // Presentation controls (Black, Freeze, Clear)
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

            // Media output prefs (loop, fit/fill) + output hardware
            StyleQuickSettings(sections: [.media, .output])

            Divider()

            // Theme switcher + Layout Editor access
            PanelFooter(format: "media")
        }
        .background(.background)
    }
}

// MARK: - Media Controls Bar (prev / present / next)

struct MediaControlsBar: View {
    let orderedItems: [MediaItem]

    @Environment(PresentationManager.self) private var pm
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService
    @Environment(LibraryManager.self) private var libraryManager

    private var selectedItem: MediaItem? { libraryManager.selectedMediaItem }
    private var liveMediaShowing: Bool {
        pm.liveContent.isLive && pm.liveContent.contentType == .media
    }

    var body: some View {
        VStack(spacing: 6) {
            if let item = selectedItem {
                HStack(spacing: 6) {
                    Image(systemName: (MediaKind(rawValue: item.mediaType) ?? .image).systemImage)
                        .font(.caption)
                        .foregroundStyle(appAccent)
                    Text(item.name)
                        .font(.caption.bold())
                        .foregroundStyle(appAccent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    if let badge = item.durationBadge {
                        Text(badge)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 8) {
                Button { step(-1) } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 34, height: 34)
                }
                .disabled(orderedItems.isEmpty)
                .help(String(localized: "Media anterioară", comment: "Tooltip"))

                if liveMediaShowing {
                    Button { pm.clearOutput() } label: {
                        Label(String(localized: "Ascunde", comment: "Button — hide live media"),
                              systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button { presentSelected() } label: {
                        Label(String(localized: "Proiectează", comment: "Button — present media"),
                              systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedItem == nil)
                }

                Button { step(+1) } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 34, height: 34)
                }
                .disabled(orderedItems.isEmpty)
                .help(String(localized: "Media următoare", comment: "Tooltip"))
            }
            .buttonStyle(.bordered)
            .lineLimit(1)

            if selectedItem == nil {
                Text(String(localized: "Selectează un fișier media în galerie.", comment: "Placeholder"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Step selection through the grid ordering; while media is live, stepping
    /// presents the new item immediately (mirrors verse navigation while live).
    private func step(_ direction: Int) {
        guard let next = MediaLibrary.neighbor(of: selectedItem, in: orderedItems, direction: direction),
              next.id != selectedItem?.id else { return }
        libraryManager.selectedMediaItem = next
        if liveMediaShowing, next.mediaType != "audio" {
            presentSelected()
        }
    }

    private func presentSelected() {
        guard let item = selectedItem else { return }
        MediaPresenter.present(item, pm: pm, video: videoPlayerService, audio: audioPlayerManager)
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
