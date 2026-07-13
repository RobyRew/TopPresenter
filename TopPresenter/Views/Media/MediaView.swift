//
//  MediaView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//
//  The Media tab is a PRESENTABLE view, not a storage browser: type tabs
//  (Toate | Foto | Video | Audio), a rich thumbnail grid (duration badges,
//  audio artwork), search, and present-first interactions — click selects
//  (preview in the right panel), double-click/Enter projects. All actions go
//  through MediaPresenter; selection lives on LibraryManager so the right
//  panel can step prev/next through the exact same filtered ordering.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AVFoundation

struct MediaView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService
    @Environment(LibraryManager.self) private var libraryManager

    @Query(sort: \MediaItem.importDate, order: .reverse) private var mediaItems: [MediaItem]

    /// Kind filter — same storage key the old toolbar filter used ("all" | kind raw).
    @AppStorage("mediaTypeFilter") private var kindFilterRaw: String = "all"
    /// Grid cell under the pointer (hover chrome).
    @State private var hoveredItemID: UUID?

    private var queryBinding: Binding<String> {
        Binding(get: { libraryManager.mediaLibraryQuery },
                set: { libraryManager.mediaLibraryQuery = $0 })
    }

    /// THE ordering — shared with the right panel via MediaLibrary.filter.
    private var filteredItems: [MediaItem] {
        MediaLibrary.filter(mediaItems, kindRaw: kindFilterRaw, query: libraryManager.mediaLibraryQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if filteredItems.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .onKeyWindowNotification(.importMedia) { _ in importMedia() }
    }

    // MARK: - Header (type tabs + search + add)

    private var header: some View {
        HStack(spacing: 10) {
            Picker("", selection: $kindFilterRaw) {
                Text(String(localized: "Toate", comment: "Media kind filter — all")).tag("all")
                ForEach(MediaKind.allCases) { kind in
                    Text(kind.filterLabel).tag(kind.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "Caută media…", comment: "Media search placeholder"),
                          text: queryBinding)
                    .textFieldStyle(.plain)
                    .frame(width: 170)
                if !libraryManager.mediaLibraryQuery.isEmpty {
                    Button { libraryManager.mediaLibraryQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5), in: Capsule())

            Button { importMedia() } label: {
                Label(String(localized: "Adaugă", comment: "Add media button"), systemImage: "plus")
            }
            .controlSize(.small)
            .help(String(localized: "Importă imagini, audio sau video", comment: "Tooltip"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "Niciun fișier media", comment: "Empty state"),
                  systemImage: "photo.on.rectangle.angled")
        } description: {
            Text(String(localized: "Importă imagini, audio sau video — sau ajustează filtrul/căutarea.", comment: "Empty state message"))
        } actions: {
            Button {
                importMedia()
            } label: {
                Label(String(localized: "Adaugă media", comment: "Button"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Grid

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 12)], spacing: 12) {
                ForEach(filteredItems) { item in
                    MediaCard(
                        item: item,
                        isSelected: libraryManager.selectedMediaItem?.id == item.id,
                        isHovered: hoveredItemID == item.id
                    )
                    .onTapGesture(count: 2) { present(item) }
                    .onTapGesture { libraryManager.selectedMediaItem = item }
                    .onHover { inside in
                        if inside { hoveredItemID = item.id }
                        else if hoveredItemID == item.id { hoveredItemID = nil }
                    }
                    .contextMenu { itemMenu(item) }
                }
            }
            .padding(12)
        }
        // Enter projects the selected item — present-first, like the song list.
        .focusable()
        .onKeyPress(.return) {
            guard let item = libraryManager.selectedMediaItem else { return .ignored }
            present(item)
            return .handled
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: MediaItem) -> some View {
        Button { present(item) } label: {
            Label(String(localized: "Proiectează", comment: "Menu"), systemImage: "play.fill")
        }
        if item.mediaType != "audio" {
            Button { MediaPresenter.setAsBackground(item, pm: presentationManager) } label: {
                Label(String(localized: "Folosește ca fundal", comment: "Menu"), systemImage: "photo.fill")
            }
        }
        AddToSessionMenu(draft: { .media(item) })
        Divider()
        Button(role: .destructive) { deleteMedia(item) } label: {
            Label(String(localized: "Șterge", comment: "Menu"), systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func present(_ item: MediaItem) {
        libraryManager.selectedMediaItem = item
        MediaPresenter.present(item, pm: presentationManager,
                               video: videoPlayerService, audio: audioPlayerManager)
    }

    private func importMedia() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .audio, .movie, .mpeg4Movie, .mpeg4Audio, .mp3, .wav, .aiff]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            let kind = MediaKind.classify(extension: url.pathExtension)
            let item = MediaItem(name: url.lastPathComponent, filePath: url.path, mediaType: kind.rawValue)
            modelContext.insert(item)
            item.createBookmark(from: url)
            // Thumbnail + duration are probed asynchronously so a big import
            // never blocks the UI; the grid updates as they land.
            Task { @MainActor in
                item.thumbnailData = await MediaThumbnailFactory.thumbnailData(for: url, kind: kind)
                try? modelContext.save()
            }
            MediaPresenter.backfillDurationIfNeeded(item, url: url)
        }
        try? modelContext.save()
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }

    private func deleteMedia(_ item: MediaItem) {
        if libraryManager.selectedMediaItem?.id == item.id {
            libraryManager.selectedMediaItem = nil
        }
        modelContext.delete(item)
        try? modelContext.save()
        NotificationCenter.default.post(name: .libraryDidChange, object: nil)
    }
}

// MARK: - Media Card (rich grid cell)

struct MediaCard: View {
    let item: MediaItem
    let isSelected: Bool
    let isHovered: Bool

    private var kind: MediaKind { MediaKind(rawValue: item.mediaType) ?? .image }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)

                if let data = item.thumbnailData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: kind.systemImage)
                        .font(.title)
                        .foregroundStyle(.secondary)
                }

                // Video gets a subtle play affordance over the thumbnail.
                if kind == .video, item.thumbnailData != nil {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.7))
                        .shadow(radius: 3)
                }
            }
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .bottomTrailing) {
                if let badge = item.durationBadge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(.black.opacity(0.65), in: Capsule())
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .overlay(alignment: .topLeading) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(4)
                    .background(.black.opacity(0.55), in: Circle())
                    .foregroundStyle(.white)
                    .padding(5)
            }

            HStack(spacing: 4) {
                Text(item.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .background(
            isSelected ? appAccent.opacity(0.18) : Color.secondary.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? appAccent : Color.clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Thumbnails (import-time)

enum MediaThumbnailFactory {
    /// Import-time thumbnail: image → resized bitmap; video → first-second frame;
    /// audio → embedded artwork if present. Returns nil when unavailable.
    static func thumbnailData(for url: URL, kind: MediaKind) async -> Data? {
        switch kind {
        case .image:
            guard let image = NSImage(contentsOf: url) else { return nil }
            return image.resized(to: NSSize(width: 320, height: 200))?.tiffRepresentation
        case .video:
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 400)
            guard let cg = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
            else { return nil }
            return NSImage(cgImage: cg, size: .zero).tiffRepresentation
        case .audio:
            let asset = AVURLAsset(url: url)
            guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
            for meta in metadata where meta.commonKey == .commonKeyArtwork {
                if let data = try? await meta.load(.dataValue) { return data }
            }
            return nil
        }
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
