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
import AVKit

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
    /// Set by the context menu; raises the delete confirmation.
    @State private var mediaToDelete: MediaItem?

    private var queryBinding: Binding<String> {
        Binding(get: { libraryManager.mediaLibraryQuery },
                set: { libraryManager.mediaLibraryQuery = $0 })
    }

    /// THE ordering — shared with the right panel via MediaLibrary.filter.
    private var filteredItems: [MediaItem] {
        MediaLibrary.filter(mediaItems, kindRaw: kindFilterRaw, query: libraryManager.mediaLibraryQuery)
    }

    var body: some View {
        ResizableSplit(storageKey: "split_media", minLeading: 280, maxFraction: 0.55) {
            VStack(spacing: 0) {
                header
                Divider()
                if filteredItems.isEmpty {
                    emptyState
                } else {
                    grid
                }
            }
        } trailing: {
            MediaDetailPane()
        }
        .onKeyWindowNotification(.importMedia) { _ in importMedia() }
        .confirmDestructive(
            String(localized: "Delete Media", comment: "Alert title"),
            item: $mediaToDelete,
            name: { $0.name },
            perform: { deleteMedia($0) }
        )
    }

    // MARK: - Header (type tabs + search + add)

    private var header: some View {
        // Two rows — at a third of the window the old single row truncated
        // the segmented filter into "…e Foto Video Audio".
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField(String(localized: "Caută media…", comment: "Media search placeholder"),
                              text: queryBinding)
                        .textFieldStyle(.plain)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help(String(localized: "Importă imagini, audio sau video", comment: "Tooltip"))
            }

            Picker("", selection: $kindFilterRaw) {
                Text(String(localized: "Toate", comment: "Media kind filter — all")).tag("all")
                ForEach(MediaKind.allCases) { kind in
                    Text(kind.filterLabel).tag(kind.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 200), spacing: 10)], spacing: 10) {
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
        Button(role: .destructive) { mediaToDelete = item } label: {
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
                if let data = item.thumbnailData, let image = NSImage(data: data) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.black.opacity(0.3))
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // No thumbnail: a soft per-kind gradient with a BIG glyph —
                    // not the flat grey square with a tiny icon.
                    LinearGradient(colors: [kind.placeholderTint.opacity(0.34),
                                            kind.placeholderTint.opacity(0.14)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(kind.placeholderTint.opacity(0.9))
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
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                // The kind chip only earns its place over a REAL thumbnail —
                // the placeholder already IS the kind glyph.
                if item.thumbnailData != nil {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(4)
                        .background(.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .padding(4)

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
                .padding(.top, 2)
        }
        .background(
            isSelected ? AnyShapeStyle(appHighlight.opacity(0.16))
                : isHovered ? AnyShapeStyle(.quaternary.opacity(0.6))
                : AnyShapeStyle(Color.secondary.opacity(0.07)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? appHighlight : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(isHovered ? 0.18 : 0), radius: 6, y: 3)
    }
}

private extension MediaKind {
    /// Soft placeholder tint per kind (cards without a thumbnail).
    var placeholderTint: Color {
        switch self {
        case .image: return .teal
        case .video: return .indigo
        case .audio: return .pink
        }
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

// MARK: - Media Detail Pane (right two-thirds — LIVE preview + framing)

/// The selected item, previewed for REAL: video and audio play here through
/// their OWN AVPlayer (never the live `VideoPlayerService` — auditioning a
/// clip must not touch what the congregation sees), images render at full
/// resolution. Underneath, the FRAMING controls drive the live output:
/// fit/fill, a zoom slider and drag-to-pan, all applied to whatever media is
/// currently on screen.
///
/// The visual preview goes through the SAME card the projector and the right
/// panel use: the media theme's background, then the media profile's casete in
/// their stacking order, with this pane's own player inside the live casetă. It
/// used to be a bare full-bleed surface on a grey plate, which meant the one
/// place an operator sizes and frames media was the one place that showed
/// neither the theme nor the casetă the media actually lands in.
struct MediaDetailPane: View {
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(PresentationManager.self) private var pm
    @Environment(AudioPlayerManager.self) private var audioPlayerManager
    @Environment(VideoPlayerService.self) private var videoPlayerService

    /// Preview-only player (video + audio). Separate from the live services.
    @State private var previewPlayer: AVPlayer?
    @State private var isPreviewPlaying = false
    @State private var fullImage: NSImage?
    /// Security scope held while the preview player reads the file.
    @State private var scopedURL: URL?
    @State private var panBase: CGSize?

    // Transport state for the audition video — the casetă renders a chromeless
    // surface (it has to match the projector), so the scrubber lives out here.
    @State private var previewTime: Double = 0
    @State private var previewDuration: Double = 0
    @State private var isScrubbing = false

    var body: some View {
        if let item = libraryManager.selectedMediaItem {
            let kind = MediaKind(rawValue: item.mediaType) ?? .image
            VStack(spacing: 12) {
                preview(item: item, kind: kind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if kind == .video { videoTransport }
                if kind == .audio { audioTransport }

                VStack(spacing: 3) {
                    Text(item.name)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 6) {
                        Label(kind.filterLabel, systemImage: kind.systemImage)
                        if let badge = item.durationBadge {
                            Text(verbatim: "· " + badge)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if kind != .audio { framingControls }

                Button {
                    // A fresh present starts from a clean frame.
                    pm.resetMediaFraming()
                    MediaPresenter.present(item, pm: pm, video: videoPlayerService, audio: audioPlayerManager)
                } label: {
                    Label(String(localized: "Prezintă", comment: "Button"), systemImage: "play.fill")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(18)
            // Rebuild the preview whenever the selection changes; the tracking
            // loop lives in the same task so cancellation stops it too.
            .task(id: item.id) {
                await loadPreview(item: item, kind: kind)
                await trackPreviewTime(kind: kind)
            }
            .onDisappear(perform: teardownPreview)
        } else {
            ContentUnavailableView {
                Label(String(localized: "Nimic selectat", comment: "Media detail empty"),
                      systemImage: "photo.on.rectangle")
            } description: {
                Text(String(localized: "Alege un fișier din stânga pentru previzualizare.", comment: "Media detail empty message"))
            }
            .onDisappear(perform: teardownPreview)
        }
    }

    // MARK: Preview surfaces

    @ViewBuilder
    private func preview(item: MediaItem, kind: MediaKind) -> some View {
        ZStack {
            switch kind {
            case .video, .image:
                // The projector's own renderer. `playsVideo` is safe here because
                // the player handed over is this pane's, never the live one.
                PresentationPreviewCard(
                    formatHint: "media",
                    pendingMedia: .init(
                        thumbnail: item.thumbnailData.flatMap { NSImage(data: $0) },
                        kindRaw: item.mediaType,
                        name: item.name,
                        url: item.resolvedURL
                    ),
                    showsBadges: false,
                    playsVideo: true,
                    mediaOverride: .init(
                        image: kind == .image ? fullImage : nil,
                        player: kind == .video ? previewPlayer : nil,
                        url: item.resolvedURL,
                        kindRaw: item.mediaType
                    )
                )
            case .audio:
                // Audio never claims the visual output, so there is no casetă to
                // render it into — artwork on a plate is the honest preview.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.35))
                if let data = item.thumbnailData, let artwork = NSImage(data: data) {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 54))
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Drag anywhere on the preview to PAN the live output (only useful
        // once zoomed in — at 100% the frame already fills the screen).
        .gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .local)
                .onChanged { value in
                    guard pm.mediaZoom > 1.01 else { return }
                    let base = panBase ?? CGSize(width: pm.mediaPanX, height: pm.mediaPanY)
                    panBase = base
                    // Preview drag → output fraction (preview is ~1/3 the size).
                    let limit = (pm.mediaZoom - 1) / 2
                    pm.mediaPanX = min(max(base.width + value.translation.width / 400, -limit), limit)
                    pm.mediaPanY = min(max(base.height + value.translation.height / 300, -limit), limit)
                }
                .onEnded { _ in panBase = nil }
        )
    }

    /// Transport for the audition video: play/pause, a scrubber, and the clock.
    /// `AVPlayerView`'s built-in controls are unavailable now that the frames go
    /// through the casetă (the projector has no chrome, and the preview has to
    /// match it), so the transport is drawn here instead.
    private var videoTransport: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { previewTime },
                    set: { newValue in
                        previewTime = newValue
                        seekPreview(to: newValue)
                    }
                ),
                in: 0...max(previewDuration, 0.1),
                onEditingChanged: { editing in isScrubbing = editing }
            )
            .controlSize(.small)
            .disabled(previewPlayer == nil || previewDuration <= 0)

            HStack(spacing: 10) {
                Button {
                    togglePreviewPlayback()
                } label: {
                    Image(systemName: isPreviewPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(appAccent)
                }
                .buttonStyle(.plain)
                .disabled(previewPlayer == nil)
                .help(String(localized: "Redă local (nu iese pe ecran)", comment: "Tooltip"))

                Text(verbatim: "\(timecode(previewTime)) / \(timecode(previewDuration))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    seekPreview(to: 0)
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .controlSize(.small)
                .disabled(previewPlayer == nil)
                .help(String(localized: "Înapoi la început", comment: "Tooltip"))
            }
        }
    }

    private func timecode(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var audioTransport: some View {
        HStack(spacing: 10) {
            Button {
                togglePreviewPlayback()
            } label: {
                Image(systemName: isPreviewPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(appAccent)
            }
            .buttonStyle(.plain)
            .help(String(localized: "Ascultă local (nu iese pe ecran)", comment: "Tooltip"))

            Text(String(localized: "Previzualizare locală", comment: "Audio preview label"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Framing (drives the LIVE output)

    private var framingControls: some View {
        @Bindable var pmBinding = pm
        return VStack(spacing: 8) {
            Picker("", selection: $pmBinding.fullscreenVideoFillRaw) {
                Text(String(localized: "Încadrează", comment: "Media fit")).tag("fit")
                Text(String(localized: "Umple", comment: "Media fill")).tag("fill")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 8) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $pmBinding.mediaZoom.snapped(0.05), in: 1...3)
                Image(systemName: "plus.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(verbatim: "\(Int(pm.mediaZoom * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 42, alignment: .trailing)
                Button {
                    pm.resetMediaFraming()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .controlSize(.small)
                .help(String(localized: "Resetează încadrarea", comment: "Tooltip"))
                .disabled(pm.mediaZoom == 1 && pm.mediaPanX == 0 && pm.mediaPanY == 0)
            }

            Text(pm.mediaZoom > 1.01
                 ? String(localized: "Trage în previzualizare pentru a repoziționa imaginea pe ecran.", comment: "Framing hint")
                 : String(localized: "Încadrarea se aplică live pe ecranul de proiecție.", comment: "Framing hint"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Preview lifecycle

    private func loadPreview(item: MediaItem, kind: MediaKind) async {
        teardownPreview()
        guard let url = item.resolvedURL else { return }
        // Hold the security scope for as long as the preview reads the file.
        if url.startAccessingSecurityScopedResource() { scopedURL = url }

        switch kind {
        case .image:
            // Read bytes off-main (Data is Sendable — NSImage is NOT, so it
            // is decoded here on the main actor).
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value
            fullImage = data.flatMap { NSImage(data: $0) }
        case .video:
            let player = AVPlayer(url: url)
            player.isMuted = true          // auditioning must stay silent by default
            previewPlayer = player
            if let duration = try? await AVURLAsset(url: url).load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                previewDuration = seconds.isFinite ? seconds : 0
            }
        case .audio:
            previewPlayer = AVPlayer(url: url)
        }
    }

    /// Drives the scrubber for as long as this item is selected. A polling loop
    /// rather than `addPeriodicTimeObserver`: the observer's callback is
    /// `@Sendable` and would have to reach back into this view's `@State`, and it
    /// needs explicit teardown. `.task(id:)` cancels this on its own.
    /// Skipped while the operator is dragging, so the thumb doesn't fight them.
    private func trackPreviewTime(kind: MediaKind) async {
        guard kind == .video else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            guard !isScrubbing, let player = previewPlayer else { continue }
            let seconds = CMTimeGetSeconds(player.currentTime())
            if seconds.isFinite { previewTime = seconds }
        }
    }

    private func seekPreview(to seconds: Double) {
        previewPlayer?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePreviewPlayback() {
        guard let previewPlayer else { return }
        if isPreviewPlaying {
            previewPlayer.pause()
        } else {
            previewPlayer.play()
        }
        isPreviewPlaying.toggle()
    }

    private func teardownPreview() {
        previewPlayer?.pause()
        previewPlayer = nil
        isPreviewPlaying = false
        previewTime = 0
        previewDuration = 0
        isScrubbing = false
        fullImage = nil
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }
}
