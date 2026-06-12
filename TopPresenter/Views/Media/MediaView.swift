//
//  MediaView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVKit

/// Media management view for images, audio, and video files.
struct MediaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AudioPlayerManager.self) private var audioPlayerManager

    @Query(sort: \MediaItem.importDate, order: .reverse) private var mediaItems: [MediaItem]

    @AppStorage("mediaTypeFilter") private var mediaTypeFilterRaw: String = "all"
    @State private var selectedItem: MediaItem?
    @State private var videoService = VideoPlayerService()

    enum MediaTypeFilter: String, CaseIterable {
        case all = "All"
        case image = "Images"
        case audio = "Audio"
        case video = "Video"

        var localizedName: String {
            switch self {
            case .all: return String(localized: "All", comment: "Media filter")
            case .image: return String(localized: "Images", comment: "Media filter")
            case .audio: return String(localized: "Audio", comment: "Media filter")
            case .video: return String(localized: "Video", comment: "Media filter")
            }
        }
    }

    // Driven by the TOOLBAR filter (shared @AppStorage key)
    private var filteredItems: [MediaItem] {
        switch mediaTypeFilterRaw {
        case "image": return mediaItems.filter { $0.mediaType == "image" }
        case "audio": return mediaItems.filter { $0.mediaType == "audio" }
        case "video": return mediaItems.filter { $0.mediaType == "video" }
        default: return mediaItems
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filtering + Add Media live in the WINDOW TOOLBAR (shared filter key)

            if filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "No media files", comment: "Empty state"))
                        .font(.title2)
                    Text(String(localized: "Import images, audio, or video files.", comment: "Empty state message"))
                        .foregroundStyle(.secondary)
                    Button {
                        importMedia()
                    } label: {
                        Label(
                            String(localized: "Add Media", comment: "Button"),
                            systemImage: "plus.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // Media grid
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 120, maximum: 180), spacing: 12)
                        ], spacing: 12) {
                            ForEach(filteredItems) { item in
                                MediaGridItem(item: item, isSelected: selectedItem?.id == item.id)
                                    .onTapGesture {
                                        selectedItem = item
                                        NotificationCenter.default.post(name: .mediaItemSelected, object: item)
                                    }
                                    .onTapGesture(count: 2) {
                                        useMedia(item)
                                    }
                                    .contextMenu {
                                        Button(String(localized: "Use as Background", comment: "Context menu")) {
                            if item.mediaType == "image", let url = item.resolvedURL {
                                let accessing = url.startAccessingSecurityScopedResource()
                                presentationManager.setBackgroundImage(from: url)
                                if accessing { url.stopAccessingSecurityScopedResource() }
                            }
                        }
                                        Divider()

                                        Button(String(localized: "Delete", comment: "Context menu"), role: .destructive) {
                                            deleteMedia(item)
                                        }
                                    }
                            }
                        }
                        .padding()
                    }
                    .frame(minWidth: 300)

                    // Detail panel
                    if let item = selectedItem {
                        MediaDetailPanel(item: item, videoService: videoService)
                            .frame(minWidth: 250, maxWidth: 350)
                    }
                }
            }
        }
        .onKeyWindowNotification(.importMedia) { _ in
            importMedia()
        }
    }

    private func importMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .audio, .movie, .mpeg4Movie, .mpeg4Audio, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                let mediaType = classifyMediaType(url)
                let item = MediaItem(
                    name: url.lastPathComponent,
                    filePath: url.path,
                    mediaType: mediaType
                )

                // Generate thumbnail for images
                if mediaType == "image", let image = NSImage(contentsOf: url) {
                    let thumbnailSize = NSSize(width: 200, height: 200)
                    let thumbnail = image.resized(to: thumbnailSize)
                    item.thumbnailData = thumbnail?.tiffRepresentation
                }

                modelContext.insert(item)

                // Create security-scoped bookmark for persistent access
                item.createBookmark(from: url)
            }
            try? modelContext.save()
        }
    }

    private func classifyMediaType(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        let imageExts = ["jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp"]
        let audioExts = ["mp3", "wav", "aac", "m4a", "flac", "aiff", "ogg", "wma"]
        let videoExts = ["mp4", "mov", "avi", "mkv", "m4v", "wmv", "webm"]

        if imageExts.contains(ext) { return "image" }
        if audioExts.contains(ext) { return "audio" }
        if videoExts.contains(ext) { return "video" }
        return "image"
    }

    private func useMedia(_ item: MediaItem) {
        guard let url = item.resolvedURL else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        switch item.mediaType {
        case "image":
            presentationManager.setBackgroundImage(from: url)
        case "audio":
            audioPlayerManager.loadAudio(url: url)
            audioPlayerManager.play()
        case "video":
            videoService.loadVideo(url: url)
            videoService.play()
        default:
            break
        }
    }

    private func deleteMedia(_ item: MediaItem) {
        if selectedItem?.id == item.id {
            selectedItem = nil
        }
        modelContext.delete(item)
        try? modelContext.save()
    }
}

// MARK: - Media Grid Item
struct MediaGridItem: View {
    let item: MediaItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)

                if item.mediaType == "image" {
                    if let data = item.thumbnailData, let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
                } else if item.mediaType == "audio" {
                    Image(systemName: "waveform")
                        .font(.title)
                        .foregroundStyle(.secondary)
                } else if item.mediaType == "video" {
                    Image(systemName: "film")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            )

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Media Detail Panel
struct MediaDetailPanel: View {
    let item: MediaItem
    let videoService: VideoPlayerService

    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AudioPlayerManager.self) private var audioPlayerManager

    var body: some View {
        VStack(spacing: 12) {
            Text(item.name)
                .font(.headline)
                .lineLimit(2)

            Text(item.mediaType.capitalized)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // Preview
            if item.mediaType == "image" {
                if let url = item.resolvedURL,
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else if item.mediaType == "video" {
                if let player = videoService.player {
                    VideoPlayer(player: player)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            Spacer()

            // Actions
            VStack(spacing: 8) {
                if item.mediaType == "image" {
                    Button {
                        if let url = item.resolvedURL {
                            let accessing = url.startAccessingSecurityScopedResource()
                            presentationManager.setBackgroundImage(from: url)
                            if accessing { url.stopAccessingSecurityScopedResource() }
                        }
                    } label: {
                        Label(
                            String(localized: "Set as Background", comment: "Button"),
                            systemImage: "photo.fill"
                        )
                        .frame(maxWidth: .infinity)
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
                    }
                    .buttonStyle(.borderedProminent)
                }

                if item.mediaType == "video" {
                    Button {
                        if let url = item.resolvedURL {
                            let accessing = url.startAccessingSecurityScopedResource()
                            videoService.loadVideo(url: url)
                            videoService.play()
                            if accessing { url.stopAccessingSecurityScopedResource() }
                        }
                    } label: {
                        Label(
                            String(localized: "Play Video", comment: "Button"),
                            systemImage: "play.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
    }
}

// MARK: - NSImage Extension
extension NSImage {
    func resized(to targetSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: targetSize)
        newImage.lockFocus()
        self.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: self.size),
            operation: .copy,
            fraction: 1.0
        )
        newImage.unlockFocus()
        return newImage
    }
}
