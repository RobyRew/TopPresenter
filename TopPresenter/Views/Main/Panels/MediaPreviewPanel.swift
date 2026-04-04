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

            // Minimal settings: just background opacity + screen selector
            StyleQuickSettings(sections: [.background, .displayOutput])
        }
        .background(.background)
        .onReceive(NotificationCenter.default.publisher(for: .mediaItemSelected)) { notification in
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
                            // Video playback placeholder — would show in output window
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
