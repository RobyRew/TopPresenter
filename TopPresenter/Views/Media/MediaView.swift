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
    @Environment(AppState.self) private var appState

    @Query(sort: \MediaItem.importDate, order: .reverse) private var mediaItems: [MediaItem]

    /// Kind filter — same storage key the old toolbar filter used ("all" | kind raw).
    @AppStorage("mediaTypeFilter") private var kindFilterRaw: String = "all"
    @AppStorage("mediaViewMode") private var viewModeRaw: String = LibraryViewMode.grid.rawValue

    private var viewMode: Binding<LibraryViewMode> {
        Binding(get: { LibraryViewMode(rawValue: viewModeRaw) ?? .grid },
                set: { viewModeRaw = $0.rawValue })
    }
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
                } else if viewMode.wrappedValue == .grid {
                    grid
                } else {
                    list
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
        LibraryHeader(
            query: queryBinding,
            placeholder: String(localized: "Caută media…", comment: "Media search placeholder"),
            viewMode: viewMode,
            count: String(localized: "\(filteredItems.count) media", comment: "Media count")
        ) {
            LibraryHeaderButton(systemImage: "plus",
                                help: String(localized: "Importă imagini, audio sau video", comment: "Tooltip"),
                                prominent: true) { importMedia() }
        } filters: {
            LibraryChip(label: String(localized: "Toate", comment: "Media kind filter — all"),
                        icon: "square.grid.2x2",
                        count: mediaItems.count,
                        isActive: kindFilterRaw == "all",
                        isEmpty: mediaItems.isEmpty) { kindFilterRaw = "all" }
            ForEach(MediaKind.allCases) { kind in
                let n = mediaItems.filter { $0.mediaType == kind.rawValue }.count
                LibraryChip(label: kind.filterLabel,
                            icon: kind.systemImage,
                            count: n,
                            isActive: kindFilterRaw == kind.rawValue,
                            isEmpty: n == 0) { kindFilterRaw = kind.rawValue }
            }
        }
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
        // The grid has to be focusable to receive that key, but AppKit then draws
        // a focus ring around the WHOLE scroll view, which read as a border on the
        // media container and competed with the ring marking the selected tile.
        // The Bible grid and the editor canvas suppress it the same way.
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.return) {
            guard let item = libraryManager.selectedMediaItem else { return .ignored }
            present(item)
            return .handled
        }
    }

    // MARK: - List
    //
    // The grid is right for choosing a picture; the list is right for a long
    // library where the FILE NAME is what you are scanning for, and it fits
    // roughly three times as many rows in the same column.
    private var list: some View {
        List(filteredItems, selection: Binding(
            get: { libraryManager.selectedMediaItem?.id },
            set: { newID in
                if let id = newID, let item = filteredItems.first(where: { $0.id == id }) {
                    libraryManager.selectedMediaItem = item
                }
            }
        )) { item in
            MediaListRow(item: item)
                .tag(item.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { present(item) }
                .onTapGesture { libraryManager.selectedMediaItem = item }
                .contextMenu { itemMenu(item) }
        }
        .listStyle(.inset)
        .focusable()
        .focusEffectDisabled()
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
        // Media is REFERENCED, never copied, so "where is this actually?" is a
        // question the app could not answer at all. It is also the only in-app
        // signal that a file has moved or been deleted: the item disables.
        Button {
            guard let url = item.resolvedURL else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Label(String(localized: "Show in Finder", comment: "Menu"), systemImage: "folder")
        }
        .disabled(item.resolvedURL == nil)
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

    /// Media imports through the ONE sheet, so a folder of photos, a mixed
    /// drop and a picked file all behave the same and all report the same way.
    private func importMedia() {
        NotificationCenter.default.post(name: .importFiles, object: nil,
                                        userInfo: ["kinds": [ImportKind.media.rawValue]])
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

/// One tile in the media grid.
///
/// Every tile is the SAME height. It used to be `lineLimit(2)` over a name that
/// might occupy one line or two, and a LazyVGrid row is as tall as its tallest
/// cell — so a single two-line filename stretched the whole row, every other
/// tile in it gained a band of empty background, and the selection fill painted
/// that band. Selecting one clip looked like selecting the row.
///
/// So the caption reserves two lines whether it needs them or not, and the
/// thumbnail is a fixed 16:10 crop. Uniform tiles, no dead space, and selection
/// can be a ring on the artwork instead of a slab behind it.
/// One row of the media list — a small fixed thumbnail, the name, and the facts
/// the grid puts on badges.
struct MediaListRow: View {
    let item: MediaItem

    private var kind: MediaKind { MediaKind(rawValue: item.mediaType) ?? .image }

    var body: some View {
        HStack(spacing: 9) {
            Color.clear
                .frame(width: 44, height: 28)
                .overlay {
                    if let data = item.thumbnailData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFill()
                    } else {
                        ZStack {
                            kind.placeholderTint.opacity(0.22)
                            Image(systemName: kind.systemImage)
                                .font(.system(size: 11))
                                .foregroundStyle(kind.placeholderTint)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))

            Text(item.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            if let badge = item.durationBadge {
                Text(badge)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: kind.systemImage)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

struct MediaCard: View {
    let item: MediaItem
    let isSelected: Bool
    let isHovered: Bool

    private var kind: MediaKind { MediaKind(rawValue: item.mediaType) ?? .image }

    /// Two lines of `.caption` plus its leading. Reserved, never measured.
    private let captionHeight: CGFloat = 30

    var body: some View {
        VStack(spacing: 6) {
            // `Color.clear` is what carries the 16:10, NOT the artwork.
            //
            // Sizing the ZStack itself left the resizable image free to drive the
            // height — a portrait clip made a taller tile than a landscape one,
            // so rows stayed ragged. A flexible spacer takes the aspect ratio,
            // the artwork rides along in an overlay (which never affects layout)
            // and gets cropped. Every tile is then identical by construction.
            Color.clear
                .aspectRatio(16.0 / 10.0, contentMode: .fit)
                .overlay { thumbnail }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) { durationBadge }
                .overlay(alignment: .topLeading) { kindBadge }
                .overlay {
                    // Selection reads on the ARTWORK — the thing you picked —
                    // rather than as a panel behind the tile.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? appHighlight : .clear, lineWidth: 2.5)
                }
                .shadow(color: .black.opacity(isHovered ? 0.22 : 0.10), radius: isHovered ? 7 : 3, y: 2)

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .foregroundStyle(isSelected ? AnyShapeStyle(appHighlight) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity, minHeight: captionHeight, alignment: .top)
                .padding(.horizontal, 2)
        }
        .padding(6)
        .background(
            isHovered && !isSelected ? AnyShapeStyle(.quaternary.opacity(0.45)) : AnyShapeStyle(Color.clear),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            if let data = item.thumbnailData, let image = NSImage(data: data) {
                // scaledToFill inside a FIXED overlay: the artwork covers the
                // 16:10 rectangle and the excess is cropped by the caller's
                // clipShape, so a portrait photo and a landscape video occupy
                // the same tile.
                Color.black.opacity(0.35)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [kind.placeholderTint.opacity(0.34),
                                        kind.placeholderTint.opacity(0.14)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: kind.systemImage)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(kind.placeholderTint.opacity(0.9))
            }

            if kind == .video, item.thumbnailData != nil {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(isHovered ? 0.95 : 0.75))
                    .shadow(radius: 3)
            }
        }
    }

    @ViewBuilder
    private var durationBadge: some View {
        if let badge = item.durationBadge {
            Text(badge)
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(.black.opacity(0.65), in: Capsule())
                .foregroundStyle(.white)
                .padding(5)
        }
    }

    @ViewBuilder
    private var kindBadge: some View {
        // The chip only earns its place over a REAL thumbnail — the placeholder
        // already IS the kind glyph.
        if item.thumbnailData != nil {
            Image(systemName: kind.systemImage)
                .font(.system(size: 9, weight: .semibold))
                .padding(4)
                .background(.black.opacity(0.55), in: Circle())
                .foregroundStyle(.white)
                .padding(5)
        }
    }
}

private extension MediaKind {
    /// Soft placeholder tint per kind (cards without a thumbnail).
    var placeholderTint: Color {
        switch self {
        case .image: return .teal
        case .video: return .indigo
        case .audio: return .pink
        case .document: return .orange
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
        case .document:
            return PDFPageRenderer.thumbnail(url: url)?.tiffRepresentation
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
    /// Page count of the selected PDF, so the panel can say "1 / 12" before it
    /// is live (once live, `PresentationManager` is the authority).
    @State private var previewPageCount = 0
    @State private var isScrubbing = false
    /// The video the scrub frames come from. The URL and not a stored
    /// `AVAssetImageGenerator`: the generator is not `Sendable`, and one held in
    /// view state cannot be handed to the async extraction without Swift 6
    /// flagging it. Built fresh per extraction, uniquely owned, exactly like
    /// `MediaThumbnailer` does.
    @State private var frameSourceURL: URL?

    var body: some View {
        if let item = libraryManager.selectedMediaItem {
            let kind = MediaKind(rawValue: item.mediaType) ?? .image
            VStack(spacing: 12) {
                preview(item: item, kind: kind)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if kind == .video { videoTransport }
                if kind == .audio { audioTransport }
                if kind == .document { documentTransport(item) }

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

                // No „Prezintă" button here. Every other module presents from the
                // right panel, and this pane had its own next to the panel's
                // „Proiectează" — two prominent buttons, a step apart, doing the
                // same thing. Framing stays here because it is spatial and needs
                // the big preview; presenting belongs where presenting always is.
            }
            .padding(18)
            // Rebuild the preview whenever the selection changes; the tracking
            // loop lives in the same task so cancellation stops it too.
            .task(id: item.id) {
                await loadPreview(item: item, kind: kind)
                await trackPreviewTime(item: item, kind: kind)
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
            // A PDF page is already a still image by the time it reaches here,
            // so it previews through the same card as a photo.
            case .video, .image, .document:
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
                        image: kind == .video ? nil : fullImage,
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

    /// Page controls for a PDF.
    ///
    /// A video's transport scrubs the PREVIEW and leaves the output alone. This
    /// one is the opposite on purpose: a document has no audition to scrub, and
    /// the only thing anyone wants from it mid-service is "next page, on the
    /// screen, now". So the arrows drive the LIVE output — and they are disabled
    /// until this document is the thing that is live, so they can never turn a
    /// page nobody is looking at.
    @ViewBuilder
    private func documentTransport(_ item: MediaItem) -> some View {
        let isLive = pm.isPresentingDocument && pm.documentURL == item.resolvedURL
        let pageCount = isLive ? pm.documentPageCount : previewPageCount
        let page = isLive ? pm.documentPage : 0

        HStack(spacing: 10) {
            Button { pm.turnDocumentPage(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!isLive || page <= 0)
            .keyboardShortcut(.leftArrow, modifiers: [])
            .help(String(localized: "Previous page", comment: "PDF control"))

            VStack(spacing: 1) {
                Text(verbatim: "\(page + 1) / \(max(pageCount, 1))")
                    .font(.callout.weight(.medium)).monospacedDigit()
                if !isLive {
                    Text(String(localized: "not live", comment: "PDF control state"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 76)

            Button { pm.turnDocumentPage(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!isLive || page >= pageCount - 1)
            .keyboardShortcut(.rightArrow, modifiers: [])
            .help(String(localized: "Next page", comment: "PDF control"))

            Divider().frame(height: 16)

            Button {
                if let url = item.resolvedURL { pm.showDocument(url: url, page: 0) }
            } label: {
                Label(isLive
                      ? String(localized: "First page", comment: "PDF control")
                      : String(localized: "Present", comment: "PDF control"),
                      systemImage: isLive ? "backward.end" : "play.rectangle")
            }
            .disabled(item.resolvedURL == nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
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
            // Bound to the casetă that actually renders the media, not to the
            // legacy full-screen flag it used to write to.
            Picker("", selection: $pmBinding.liveMediaFillRaw) {
                Text(String(localized: "Încadrează", comment: "Media fit")).tag("fit")
                Text(String(localized: "Umple", comment: "Media fill")).tag("fill")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help(String(localized: "Încadrează arată tot fișierul; Umple acoperă caseta și taie surplusul. Zoom-ul de mai jos se aplică peste această alegere.", comment: "Tooltip — fit/fill"))

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
            let asset = AVURLAsset(url: url)
            if let duration = try? await asset.load(.duration) {
                let seconds = CMTimeGetSeconds(duration)
                previewDuration = seconds.isFinite ? seconds : 0
            }
            frameSourceURL = url
            await refreshScrubFrame(at: 0)
        case .audio:
            previewPlayer = AVPlayer(url: url)
        case .document:
            // Page one at preview size. Rasterising happens off-main because a
            // dense page is real work and this runs on selection — NSImage is
            // not Sendable, so the CGImage crosses back and is wrapped here.
            let rendered = await Task.detached(priority: .userInitiated) {
                PDFPageRenderer.render(url: url, page: 0, maxPixels: 1400)?
                    .cgImage(forProposedRect: nil, context: nil, hints: nil)
            }.value
            fullImage = rendered.map { NSImage(cgImage: $0, size: .zero) }
            previewPageCount = await Task.detached(priority: .utility) {
                PDFPageRenderer.pageCount(of: url)
            }.value
        }
    }

    /// Drives the scrubber for as long as this item is selected, and keeps the
    /// right panel's preview on the same frame.
    ///
    /// A polling loop rather than `addPeriodicTimeObserver`: the observer's
    /// callback is `@Sendable` and would have to reach back into this view's
    /// `@State`, and it needs explicit teardown. `.task(id:)` cancels this on its
    /// own. The scrubber itself is skipped while the operator is dragging, so the
    /// thumb doesn't fight them — the PREVIEW still follows, which is the whole
    /// point of dragging.
    private func trackPreviewTime(item: MediaItem, kind: MediaKind) async {
        guard kind == .video else { return }
        var lastFrameAt: Double = -1
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            guard let player = previewPlayer else { continue }
            let seconds = CMTimeGetSeconds(player.currentTime())
            guard seconds.isFinite else { continue }
            if !isScrubbing { previewTime = seconds }

            // Frame extraction is far too costly per tick. Refresh only when the
            // position has actually moved by something the eye would notice.
            let target = isScrubbing ? previewTime : seconds
            if abs(target - lastFrameAt) >= 0.4 {
                lastFrameAt = target
                await refreshScrubFrame(at: target)
            }
        }
    }

    /// One still at `seconds`, handed to the panel through LibraryManager.
    ///
    /// Generous tolerance on purpose: an exact frame means decoding from the
    /// preceding keyframe, which is an order of magnitude slower and buys
    /// nothing at preview size.
    private func refreshScrubFrame(at seconds: Double) async {
        guard let url = frameSourceURL else { return }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 400)
        // Snap to the nearest available frame instead of decoding forward from a
        // keyframe — at preview size the difference is invisible, the cost is not.
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        guard let cg = try? await generator.image(at: time).image else { return }
        libraryManager.mediaScrubFrame = NSImage(cgImage: cg, size: .zero)
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
        frameSourceURL = nil
        // Leaving the last frame behind would have the panel previewing a clip
        // that is no longer selected.
        libraryManager.mediaScrubFrame = nil
        fullImage = nil
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
    }
}
