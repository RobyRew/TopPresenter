//
//  TextBoxLayout.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 10/06/2026.
//
//  Fixed text box layout editing:
//  - TextBoxSection / BoxIdentity: built-in sections, custom text boxes, media boxes
//  - TextBoxEditOverlay: drag/resize overlay with right-click menus (rename, z-order…)
//  - LayoutEditorSheet: the design studio — canvas + tabbed inspector
//    (Layout / Text / Fundal / Ieșire); selecting a box shows ALL its settings
//    grouped clearly (Poziție și Dimensiune / Conținut / Text)
//  - ThemeMenuControl: switch / save / manage themes (named looks)
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Text Box Section

/// Identifies one of the four built-in fixed text boxes.
enum TextBoxSection: String, CaseIterable, Identifiable {
    case verseContent = "verseContent"
    case reference = "reference"
    case translationName = "translationName"
    case subtitle = "subtitle"
    case chords = "chords"            // song-only: chord chart over the lyrics

    var id: String { rawValue }

    var label: String { label(for: "bible") }

    /// PER-PRESENTER names — in Songs the main box holds lyrics, the
    /// reference box holds the song title, the subtitle box the strofă label.
    func label(for key: String) -> String {
        switch (self, key) {
        case (.verseContent, "song"): return String(localized: "Versuri", comment: "Text box name — song lyrics")
        case (.verseContent, "text"): return String(localized: "Conținut Slide", comment: "Text box name — slide body")
        case (.verseContent, _): return String(localized: "Conținut Verset", comment: "Text box name")
        case (.reference, "song"): return String(localized: "Titlu Cântec", comment: "Text box name — song title")
        case (.reference, "text"): return String(localized: "Titlu Slide", comment: "Text box name — slide title")
        case (.reference, _): return String(localized: "Referință", comment: "Text box name — Bible reference")
        case (.translationName, _): return String(localized: "Traducere", comment: "Text box name — Bible translation name")
        case (.subtitle, "song"): return String(localized: "Etichetă Strofă", comment: "Text box name — Strofa 1 / Refren / Cor")
        case (.subtitle, _): return String(localized: "Subtitlu", comment: "Text box name — verse label / subtitle")
        case (.chords, _): return String(localized: "Acorduri", comment: "Text box name — chord chart")
        }
    }

    /// Where this box's content comes from by default ("auto" source).
    var sourceDescription: String {
        switch self {
        case .verseContent:
            return String(localized: "Biblie: textul versetelor • Cântece: strofa • Slide: conținutul", comment: "Box source description")
        case .reference:
            return String(localized: "Biblie: referința (ex. Ioan 3:16) • Cântece/Slide: titlul", comment: "Box source description")
        case .translationName:
            return String(localized: "Numele/abrevierea traducerii Bibliei (ex. VDC)", comment: "Box source description")
        case .subtitle:
            return String(localized: "Eticheta strofei la cântece (ex. Strofa 1, Refren)", comment: "Box source description")
        case .chords:
            return String(localized: "Acordurile cântecului peste versuri (transpozabile)", comment: "Box source description")
        }
    }

    var icon: String {
        switch self {
        case .verseContent: return "text.quote"
        case .reference: return "bookmark.fill"
        case .translationName: return "character.book.closed.fill"
        case .subtitle: return "text.line.last.and.arrowtriangle.forward"
        case .chords: return "guitars.fill"
        }
    }

    var boxColor: Color {
        switch self {
        case .verseContent: return .cyan
        case .reference: return .orange
        case .translationName: return .purple
        case .subtitle: return .green
        case .chords: return .pink
        }
    }
}

// MARK: - Box Identity (built-in section, custom text box, or media box)

enum BoxIdentity: Hashable {
    case section(TextBoxSection)
    case custom(UUID)
    case media(UUID)
}

extension PresentationManager {
    func boxFrame(for identity: BoxIdentity) -> TextBoxFrame {
        switch identity {
        case .section(let section):
            return boxFrame(for: section)
        case .custom(let id):
            return customTextBox(id: id)?.frame ?? CustomTextBox().frame
        case .media(let id):
            return mediaBox(id: id)?.frame ?? MediaBox().frame
        }
    }

    func setBoxFrame(_ frame: TextBoxFrame, for identity: BoxIdentity) {
        switch identity {
        case .section(let section):
            setBoxFrame(frame, for: section)
        case .custom(let id):
            guard var box = customTextBox(id: id) else { return }
            box.frame = frame.clamped()
            updateCustomTextBox(box)
        case .media(let id):
            guard var box = mediaBox(id: id) else { return }
            box.frame = frame.clamped()
            updateMediaBox(box)
        }
    }

    func resetBox(for identity: BoxIdentity) {
        switch identity {
        case .section(let section):
            resetBoxFrame(for: section)
        case .custom(let id):
            guard var box = customTextBox(id: id) else { return }
            box.frame = CustomTextBox().frame
            updateCustomTextBox(box)
        case .media(let id):
            guard var box = mediaBox(id: id) else { return }
            box.frame = MediaBox().frame
            updateMediaBox(box)
        }
    }

    /// Visibility for any box kind.
    func isBoxVisible(_ identity: BoxIdentity) -> Bool {
        switch identity {
        case .section(let section): return isSectionVisible(section)
        case .custom(let id): return customTextBox(id: id)?.isVisible ?? true
        case .media(let id): return mediaBox(id: id)?.isVisible ?? true
        }
    }

    func toggleBoxVisibility(_ identity: BoxIdentity) {
        switch identity {
        case .section(let section):
            setSectionVisible(!isSectionVisible(section), for: section)
        case .custom(let id):
            guard var box = customTextBox(id: id) else { return }
            box.isVisible.toggle()
            updateCustomTextBox(box)
        case .media(let id):
            guard var box = mediaBox(id: id) else { return }
            box.isVisible.toggle()
            updateMediaBox(box)
        }
    }

    func renameBox(_ identity: BoxIdentity, to name: String) {
        switch identity {
        case .section:
            break // built-in names are fixed (semantic)
        case .custom(let id):
            guard var box = customTextBox(id: id) else { return }
            box.name = name
            updateCustomTextBox(box)
        case .media(let id):
            guard var box = mediaBox(id: id) else { return }
            box.name = name
            updateMediaBox(box)
        }
    }

    // Quick-align actions (Layout Editor toolbar + context menus)
    func centerBoxHorizontally(_ identity: BoxIdentity) {
        var frame = boxFrame(for: identity)
        frame.x = (1.0 - frame.width) / 2.0
        setBoxFrame(frame, for: identity)
    }

    func centerBoxVertically(_ identity: BoxIdentity) {
        var frame = boxFrame(for: identity)
        frame.y = (1.0 - frame.height) / 2.0
        setBoxFrame(frame, for: identity)
    }

    func makeBoxFullWidth(_ identity: BoxIdentity) {
        var frame = boxFrame(for: identity)
        frame.x = 0
        frame.width = 1
        setBoxFrame(frame, for: identity)
    }

    func makeBoxFullHeight(_ identity: BoxIdentity) {
        var frame = boxFrame(for: identity)
        frame.y = 0
        frame.height = 1
        setBoxFrame(frame, for: identity)
    }
}

// MARK: - Z-order token mapping

func boxToken(for identity: BoxIdentity) -> String {
    switch identity {
    case .section(let section): return "section:" + section.rawValue
    case .custom(let id): return "custom:" + id.uuidString
    case .media(let id): return "media:" + id.uuidString
    }
}

func boxIdentity(fromToken token: String) -> BoxIdentity? {
    let parts = token.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    switch String(parts[0]) {
    case "section":
        guard let section = TextBoxSection(rawValue: String(parts[1])) else { return nil }
        return .section(section)
    case "custom":
        guard let id = UUID(uuidString: String(parts[1])) else { return nil }
        return .custom(id)
    case "media":
        guard let id = UUID(uuidString: String(parts[1])) else { return nil }
        return .media(id)
    default:
        return nil
    }
}

// MARK: - Box display helpers

func defaultBoxColor(for identity: BoxIdentity) -> Color {
    switch identity {
    case .section(let section): return section.boxColor
    case .custom: return .mint
    case .media: return .pink
    }
}

/// The box's accent color — the user's custom pick, else the kind's default.
func boxColor(for identity: BoxIdentity, pm: PresentationManager) -> Color {
    if let hex = pm.boxColorHex(forToken: boxToken(for: identity)),
       let custom = Color(hex: hex) {
        return custom
    }
    return defaultBoxColor(for: identity)
}

func boxIcon(for identity: BoxIdentity, pm: PresentationManager) -> String {
    switch identity {
    case .section(let section): return section.icon
    case .custom: return "textbox"
    case .media(let id):
        switch pm.mediaBox(id: id)?.mediaTypeRaw {
        case "video": return "film"
        case "gif": return "photo.stack"
        default: return "photo"
        }
    }
}

func boxLabel(for identity: BoxIdentity, pm: PresentationManager) -> String {
    switch identity {
    case .section(let section):
        return section.label(for: pm.activeProfileKey)
    case .custom(let id):
        guard let box = pm.customTextBox(id: id) else {
            return String(localized: "Casetă text", comment: "Generic custom text box name")
        }
        if !box.name.isEmpty { return box.name }
        if box.sourceRaw != "static" { return box.sourceLabel }
        let text = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return String(localized: "Casetă text", comment: "Generic custom text box name") }
        return text.count > 16 ? String(text.prefix(16)) + "…" : text
    case .media(let id):
        guard let box = pm.mediaBox(id: id) else {
            return String(localized: "Media", comment: "Generic media box name")
        }
        if !box.name.isEmpty { return box.name }
        if box.fileName.isEmpty { return String(localized: "Media", comment: "Generic media box name") }
        return box.fileName.count > 16 ? String(box.fileName.prefix(16)) + "…" : box.fileName
    }
}

/// The little color square of a box row — CLICK it to recolor the box
/// (editor chrome only: list swatch + canvas border). Hover shows a ring.
struct BoxColorSwatch: View {
    @Environment(PresentationManager.self) private var pm
    let identity: BoxIdentity

    @State private var showsPicker = false
    @State private var hovering = false

    var body: some View {
        let token = boxToken(for: identity)

        Button {
            showsPicker = true
        } label: {
            RoundedRectangle(cornerRadius: 2)
                .fill(boxColor(for: identity, pm: pm).opacity(0.85))
                .frame(width: 10, height: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(.white.opacity(hovering ? 0.9 : 0), lineWidth: 1)
                )
                .scaleEffect(hovering ? 1.25 : 1.0)
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        .help(String(localized: "Schimbă culoarea casetei (doar în editor)", comment: "Tooltip"))
        .popover(isPresented: $showsPicker, arrowEdge: .bottom) {
            VStack(spacing: 10) {
                ColorPicker(
                    String(localized: "Culoarea casetei", comment: "Color picker label"),
                    selection: Binding(
                        get: { boxColor(for: identity, pm: pm) },
                        set: { pm.setBoxColorHex($0.toHex(), forToken: token) }
                    ),
                    supportsOpacity: false
                )
                .controlSize(.small)

                Button(String(localized: "Culoarea implicită", comment: "Button")) {
                    pm.setBoxColorHex(nil, forToken: token)
                }
                .controlSize(.small)
            }
            .padding(12)
        }
    }
}

/// Small media preview row used in the Fundal tab (image/GIF/video aware).
struct BackgroundMediaThumb: View {
    let bookmark: Data?
    let mediaType: String
    let opacity: Double

    @State private var thumb: NSImage?

    var body: some View {
        HStack {
            Spacer()
            ZStack(alignment: .bottomTrailing) {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(opacity)
                        .frame(maxHeight: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                if mediaType != "image" {
                    Image(systemName: mediaType == "video" ? "video.fill" : "photo.stack")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(3)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(3)
                }
            }
            Spacer()
        }
        .task(id: bookmark) {
            thumb = await MediaThumbnailer.thumbnail(forBookmark: bookmark, mediaType: mediaType)
        }
    }
}

/// Where the box pulls its content from — shown in the inspector and context menu.
func boxSourceDescription(for identity: BoxIdentity, pm: PresentationManager) -> String {
    switch identity {
    case .section(let section):
        let raw = pm.sourceRaw(for: section)
        return raw == "auto" ? section.sourceDescription : PresentationManager.sourceOptionLabel(raw, for: pm.activeProfileKey)
    case .custom(let id):
        return pm.customTextBox(id: id)?.sourceLabel ?? ""
    case .media(let id):
        guard let box = pm.mediaBox(id: id) else { return "" }
        let type: String
        switch box.mediaTypeRaw {
        case "video": type = String(localized: "Video (buclă, fără sunet)", comment: "Media type")
        case "gif": type = "GIF"
        default: type = String(localized: "Imagine", comment: "Media type")
        }
        return "\(type) — \(box.fileName)"
    }
}

// MARK: - Edit Overlay (drag + resize directly on a canvas)

/// Overlay that draws every fixed box (built-in, custom text, media) and lets
/// the user move and resize them by direct manipulation, with right-click menus.
struct TextBoxEditOverlay: View {
    @Environment(PresentationManager.self) private var pm

    let canvasSize: CGSize
    /// When false (preview card), hidden boxes are not drawn at all — no dashed
    /// border ghosts in the previewer. The editor keeps them visible for editing.
    var showsHiddenBoxes: Bool = true
    /// Optional selection — the Layout Editor binds this; the preview card doesn't.
    var selection: Binding<BoxIdentity?> = .constant(nil)

    /// Stable coordinate space for drag math — translations measured here don't
    /// feed back into the gesture when the box moves under the cursor (no jitter).
    static let canvasSpace = "textBoxEditCanvas"

    /// The ACTIVE profile's boxes — already restricted to the sections relevant
    /// to that presenter (Songs has no Bible translation box, etc.).
    private var identities: [BoxIdentity] {
        var result = pm.orderedBoxTokens().compactMap { boxIdentity(fromToken: $0) }
        if !showsHiddenBoxes {
            result = result.filter { pm.isBoxVisible($0) }
        }
        return result
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(identities, id: \.self) { identity in
                TextBoxHandle(identity: identity, canvasSize: canvasSize, selection: selection)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .coordinateSpace(name: Self.canvasSpace)
    }
}

/// One interactive box: drag the body to move, drag a corner handle to resize,
/// click to select, right-click for the full action menu.
private struct TextBoxHandle: View {
    @Environment(PresentationManager.self) private var pm

    let identity: BoxIdentity
    let canvasSize: CGSize
    var selection: Binding<BoxIdentity?>

    /// Frame at the start of the current gesture (move or resize).
    @State private var gestureStartFrame: PresentationManager.TextBoxFrame?
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private var isSelected: Bool { selection.wrappedValue == identity }
    private var isHidden: Bool { !pm.isBoxVisible(identity) }

    private var canRename: Bool {
        if case .section = identity { return false }
        return true
    }

    private enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var resizePosition: FrameResizePosition {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }

    var body: some View {
        let frame = pm.boxFrame(for: identity)
        let rect = frame.rect(in: canvasSize)
        let color = boxColor(for: identity, pm: pm)

        ZStack {
            // Box body — faint fill + colored border; drag to move, click to select
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(isSelected ? 0.14 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            color.opacity(isSelected ? 1.0 : 0.7),
                            style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, dash: isHidden ? [4, 3] : [])
                        )
                )
                .contentShape(Rectangle())
                .pointerStyle(.grabIdle)
                .onTapGesture { selection.wrappedValue = identity }
                .gesture(moveGesture)
                .help(boxSourceDescription(for: identity, pm: pm))

            // Box label (top-leading)
            VStack {
                HStack {
                    Label(boxLabel(for: identity, pm: pm), systemImage: boxIcon(for: identity, pm: pm))
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(color.opacity(0.85), in: Capsule())
                        .allowsHitTesting(false)
                    if isHidden {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.8))
                            .allowsHitTesting(false)
                    }
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer()
                    Text("\(Int(frame.width * 100))×\(Int(frame.height * 100))%")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(color.opacity(0.7), in: Capsule())
                        .allowsHitTesting(false)
                }
            }
            .padding(3)

            // Corner resize handles
            ForEach(Array(Corner.allCases.enumerated()), id: \.offset) { _, corner in
                handleView(for: corner, in: rect)
            }
        }
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .opacity(isHidden ? 0.45 : 1.0)
        .contextMenu { contextMenuItems }
        .alert(
            String(localized: "Redenumește caseta", comment: "Rename alert title"),
            isPresented: $showRenameAlert
        ) {
            TextField(String(localized: "Nume", comment: "Rename field"), text: $renameText)
            Button(String(localized: "Salvează", comment: "Save button")) {
                pm.renameBox(identity, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            Button(String(localized: "Anulează", comment: "Cancel button"), role: .cancel) { }
        }
    }

    // MARK: Context Menu

    @ViewBuilder
    private var contextMenuItems: some View {
        // Source info header
        Text(boxSourceDescription(for: identity, pm: pm))

        Divider()

        Button {
            pm.toggleBoxVisibility(identity)
        } label: {
            if isHidden {
                Label(String(localized: "Afișează", comment: "Context menu"), systemImage: "eye")
            } else {
                Label(String(localized: "Ascunde", comment: "Context menu"), systemImage: "eye.slash")
            }
        }

        if canRename {
            Button {
                renameText = boxLabel(for: identity, pm: pm)
                showRenameAlert = true
            } label: {
                Label(String(localized: "Redenumește…", comment: "Context menu"), systemImage: "pencil")
            }
        }

        if case .custom(let id) = identity {
            Button {
                if let copy = pm.duplicateCustomTextBox(id: id) {
                    selection.wrappedValue = .custom(copy.id)
                }
            } label: {
                Label(String(localized: "Duplică", comment: "Context menu"), systemImage: "plus.square.on.square")
            }

            Button(role: .destructive) {
                pm.removeCustomTextBox(id: id)
                if selection.wrappedValue == identity { selection.wrappedValue = nil }
            } label: {
                Label(String(localized: "Șterge", comment: "Context menu"), systemImage: "trash")
            }
        }

        if case .media(let id) = identity {
            Button(role: .destructive) {
                pm.removeMediaBox(id: id)
                if selection.wrappedValue == identity { selection.wrappedValue = nil }
            } label: {
                Label(String(localized: "Șterge", comment: "Context menu"), systemImage: "trash")
            }
        }

        if case .section(let section) = identity {
            Button(role: .destructive) {
                pm.setSectionVisible(false, for: section)
            } label: {
                Label(String(localized: "Elimină", comment: "Context menu"), systemImage: "trash")
            }
        }

        // Z-order — available for EVERY box (sections, custom, media)
        Menu {
            Button(String(localized: "Adu în față", comment: "Z-order")) { pm.moveBoxTokenToEdge(boxToken(for: identity), front: true) }
            Button(String(localized: "Mai în față", comment: "Z-order")) { pm.moveBoxToken(boxToken(for: identity), offset: 1) }
            Button(String(localized: "Mai în spate", comment: "Z-order")) { pm.moveBoxToken(boxToken(for: identity), offset: -1) }
            Button(String(localized: "Trimite în spate", comment: "Z-order")) { pm.moveBoxTokenToEdge(boxToken(for: identity), front: false) }
        } label: {
            Label(String(localized: "Ordonare", comment: "Context menu"), systemImage: "square.3.layers.3d")
        }

        Divider()

        Button {
            pm.centerBoxHorizontally(identity)
        } label: {
            Label(String(localized: "Centrează orizontal", comment: "Context menu"), systemImage: "align.horizontal.center")
        }

        Button {
            pm.centerBoxVertically(identity)
        } label: {
            Label(String(localized: "Centrează vertical", comment: "Context menu"), systemImage: "align.vertical.center")
        }

        Button {
            pm.makeBoxFullWidth(identity)
        } label: {
            Label(String(localized: "Lățime completă", comment: "Context menu"), systemImage: "arrow.left.and.right")
        }

        Button {
            pm.makeBoxFullHeight(identity)
        } label: {
            Label(String(localized: "Înălțime completă", comment: "Context menu"), systemImage: "arrow.up.and.down")
        }

        Divider()

        Button {
            pm.resetBox(for: identity)
        } label: {
            Label(String(localized: "Resetează poziția", comment: "Context menu"), systemImage: "arrow.counterclockwise")
        }
    }

    // MARK: Move

    private var moveGesture: some Gesture {
        // Translation measured in the overlay's stable coordinate space —
        // measuring in the box's own (moving) space causes jitter/shaking.
        DragGesture(minimumDistance: 1, coordinateSpace: .named(TextBoxEditOverlay.canvasSpace))
            .onChanged { value in
                let start = gestureStartFrame ?? pm.boxFrame(for: identity)
                if gestureStartFrame == nil {
                    gestureStartFrame = start
                    selection.wrappedValue = identity
                }

                var frame = start
                frame.x = start.x + value.translation.width / canvasSize.width
                frame.y = start.y + value.translation.height / canvasSize.height
                pm.setBoxFrame(frame, for: identity)
            }
            .onEnded { _ in gestureStartFrame = nil }
    }

    // MARK: Resize

    @ViewBuilder
    private func handleView(for corner: Corner, in rect: CGRect) -> some View {
        let handleSize: CGFloat = 9
        RoundedRectangle(cornerRadius: 2)
            .fill(.white)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(boxColor(for: identity, pm: pm), lineWidth: 1.5))
            .frame(width: handleSize, height: handleSize)
            .contentShape(Rectangle().inset(by: -5))
            .pointerStyle(.frameResize(position: corner.resizePosition))
            .gesture(resizeGesture(for: corner))
            .offset(handleOffset(for: corner, in: rect))
    }

    private func handleOffset(for corner: Corner, in rect: CGRect) -> CGSize {
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        switch corner {
        case .topLeading: return CGSize(width: -halfW, height: -halfH)
        case .topTrailing: return CGSize(width: halfW, height: -halfH)
        case .bottomLeading: return CGSize(width: -halfW, height: halfH)
        case .bottomTrailing: return CGSize(width: halfW, height: halfH)
        }
    }

    private func resizeGesture(for corner: Corner) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(TextBoxEditOverlay.canvasSpace))
            .onChanged { value in
                let start = gestureStartFrame ?? pm.boxFrame(for: identity)
                if gestureStartFrame == nil {
                    gestureStartFrame = start
                    selection.wrappedValue = identity
                }

                let dx = value.translation.width / canvasSize.width
                let dy = value.translation.height / canvasSize.height
                let minSize = PresentationManager.TextBoxFrame.minSize
                var frame = start

                switch corner {
                case .topLeading:
                    frame.x = min(start.x + dx, start.x + start.width - minSize)
                    frame.y = min(start.y + dy, start.y + start.height - minSize)
                    frame.width = start.width - (frame.x - start.x)
                    frame.height = start.height - (frame.y - start.y)
                case .topTrailing:
                    frame.y = min(start.y + dy, start.y + start.height - minSize)
                    frame.width = max(start.width + dx, minSize)
                    frame.height = start.height - (frame.y - start.y)
                case .bottomLeading:
                    frame.x = min(start.x + dx, start.x + start.width - minSize)
                    frame.width = start.width - (frame.x - start.x)
                    frame.height = max(start.height + dy, minSize)
                case .bottomTrailing:
                    frame.width = max(start.width + dx, minSize)
                    frame.height = max(start.height + dy, minSize)
                }
                pm.setBoxFrame(frame, for: identity)
            }
            .onEnded { _ in gestureStartFrame = nil }
    }
}

// MARK: - Theme Menu Control

/// Compact theme switcher — shown in the right panel above the Layout Editor
/// button and in the editor header. Themes are named snapshots of the whole look.
struct ThemeMenuControl: View {
    @Environment(PresentationManager.self) private var pm

    @State private var showNewThemeAlert = false
    @State private var showRenameAlert = false
    @State private var newThemeName = ""

    private var activeName: String {
        if let id = pm.activeThemeID, let theme = pm.themes.first(where: { $0.id == id }) {
            return theme.name
        }
        return String(localized: "Fără temă", comment: "No active theme")
    }

    var body: some View {
        Menu {
            if pm.themes.isEmpty {
                Text(String(localized: "Nicio temă salvată", comment: "Themes menu"))
            } else {
                ForEach(pm.themes) { theme in
                    Button {
                        pm.applyTheme(id: theme.id)
                    } label: {
                        if pm.activeThemeID == theme.id {
                            Label(theme.name, systemImage: "checkmark")
                        } else {
                            Text(theme.name)
                        }
                    }
                }
            }

            Divider()

            Button {
                newThemeName = ""
                showNewThemeAlert = true
            } label: {
                Label(String(localized: "Salvează ca temă nouă…", comment: "Themes menu"), systemImage: "plus")
            }

            if let activeID = pm.activeThemeID, pm.themes.contains(where: { $0.id == activeID }) {
                Button {
                    pm.updateTheme(id: activeID)
                } label: {
                    Label(String(localized: "Actualizează tema curentă", comment: "Themes menu"), systemImage: "square.and.arrow.down")
                }

                Button {
                    newThemeName = activeName
                    showRenameAlert = true
                } label: {
                    Label(String(localized: "Redenumește tema…", comment: "Themes menu"), systemImage: "pencil")
                }

                Button(role: .destructive) {
                    pm.deleteTheme(id: activeID)
                } label: {
                    Label(String(localized: "Șterge tema", comment: "Themes menu"), systemImage: "trash")
                }
            }
        } label: {
            Label(activeName, systemImage: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        .controlSize(.small)
        .help(String(localized: "Teme: salvează și comută între layout-uri complete (casete, stiluri, fundal, media)", comment: "Tooltip"))
        .alert(
            String(localized: "Temă nouă", comment: "New theme alert title"),
            isPresented: $showNewThemeAlert
        ) {
            TextField(String(localized: "Numele temei", comment: "Theme name field"), text: $newThemeName)
            Button(String(localized: "Salvează", comment: "Save button")) {
                let name = newThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
                pm.saveCurrentAsTheme(named: name.isEmpty ? String(localized: "Temă fără nume", comment: "Default theme name") : name)
            }
            Button(String(localized: "Anulează", comment: "Cancel button"), role: .cancel) { }
        } message: {
            Text(String(localized: "Salvează aspectul curent (casete, stiluri, fundal, media) ca temă.", comment: "New theme alert message"))
        }
        .alert(
            String(localized: "Redenumește tema", comment: "Rename theme alert title"),
            isPresented: $showRenameAlert
        ) {
            TextField(String(localized: "Numele temei", comment: "Theme name field"), text: $newThemeName)
            Button(String(localized: "Salvează", comment: "Save button")) {
                if let id = pm.activeThemeID {
                    pm.renameTheme(id: id, to: newThemeName.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            Button(String(localized: "Anulează", comment: "Cancel button"), role: .cancel) { }
        }
    }
}

// MARK: - Panel Footer (right bar: theme gallery + Theme Editor button)

/// Footer of every preview panel: a visual THEME GALLERY (thumbnail cards,
/// filtered by the panel's format) and the Theme Editor button.
struct PanelFooter: View {
    /// Presenter format of the hosting panel ("bible"/"song"/"text") — the
    /// gallery shows that format's themes plus universal ("all") themes.
    var format: String? = nil

    var body: some View {
        VStack(spacing: 6) {
            ThemeGalleryView(format: format)
            LayoutEditorButton()
        }
        .padding(.top, 6)
    }
}

/// The Theme Editor button — the one place for boxes, text, backgrounds, output.
struct LayoutEditorButton: View {
    var body: some View {
        Button {
            NotificationCenter.default.post(name: .openLayoutEditor, object: nil)
        } label: {
            Label(
                String(localized: "Editor de Teme", comment: "Open theme editor button"),
                systemImage: "paintbrush.pointed.fill"
            )
            .font(.callout.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .help(String(localized: "Deschide Editorul de Teme — casete, text, fundal, ieșire", comment: "Tooltip"))
    }
}

// MARK: - Theme Gallery (thumbnail cards)

/// Horizontal gallery of theme cards with live thumbnails. Click applies the
/// theme; right-click manages it (update, rename, format, export, delete).
struct ThemeGalleryView: View {
    @Environment(PresentationManager.self) private var pm

    var format: String? = nil

    @State private var showNewThemeAlert = false
    @State private var newThemeName = ""
    @State private var renameThemeID: UUID?
    @State private var renameText = ""
    @State private var importResultMessage: String?
    /// Click-drag panning state (mouse users don't have trackpad side-scroll).
    @State private var scrollPosition = ScrollPosition(x: 0)
    @State private var scrollOffsetX: CGFloat = 0
    @State private var dragStartOffsetX: CGFloat?

    /// UNIVERSAL: a theme carries every presenter's profile, so every panel
    /// shows the whole gallery; `format` only pre-tags newly saved themes.
    private var visibleThemes: [PresentationManager.Theme] {
        pm.themes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(String(localized: "Teme", comment: "Theme gallery title"), systemImage: "paintpalette")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    importThemes()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Importă teme (.tptheme)", comment: "Tooltip"))

                Button {
                    newThemeName = ""
                    showNewThemeAlert = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Salvează aspectul curent ca temă nouă", comment: "Tooltip"))
            }
            .padding(.horizontal, 12)

            if visibleThemes.isEmpty {
                Text(String(localized: "Nicio temă încă — importă pachete .tptheme cu ⤓ sau salvează aspectul curent cu +.", comment: "Theme gallery empty state"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(visibleThemes) { theme in
                            ThemeCard(
                                theme: theme,
                                isActive: pm.activeThemeID == theme.id,
                                onRename: {
                                    renameText = theme.name
                                    renameThemeID = theme.id
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 2)
                    // Click-drag pans the gallery; ≥12pt before it kicks in so
                    // card taps and hover-previews keep working.
                    .gesture(
                        DragGesture(minimumDistance: 12)
                            .onChanged { value in
                                if dragStartOffsetX == nil { dragStartOffsetX = scrollOffsetX }
                                scrollPosition.scrollTo(x: (dragStartOffsetX ?? 0) - value.translation.width)
                            }
                            .onEnded { _ in dragStartOffsetX = nil }
                    )
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.x }) { _, new in
                    scrollOffsetX = new
                }
            }
        }
        .alert(
            String(localized: "Temă nouă", comment: "New theme alert title"),
            isPresented: $showNewThemeAlert
        ) {
            TextField(String(localized: "Numele temei", comment: "Theme name field"), text: $newThemeName)
            Button(String(localized: "Salvează", comment: "Save button")) {
                let name = newThemeName.trimmingCharacters(in: .whitespacesAndNewlines)
                pm.saveCurrentAsTheme(
                    named: name.isEmpty ? String(localized: "Temă fără nume", comment: "Default theme name") : name,
                    formatRaw: format ?? "all"
                )
            }
            Button(String(localized: "Anulează", comment: "Cancel button"), role: .cancel) { }
        } message: {
            Text(String(localized: "Salvează aspectul curent (casete, stiluri, fundal, media) ca temă.", comment: "New theme alert message"))
        }
        .alert(
            importResultMessage ?? "",
            isPresented: Binding(
                get: { importResultMessage != nil },
                set: { if !$0 { importResultMessage = nil } }
            )
        ) {
            Button(String(localized: "OK", comment: "Alert button")) { importResultMessage = nil }
        }
        .alert(
            String(localized: "Redenumește tema", comment: "Rename theme alert title"),
            isPresented: Binding(
                get: { renameThemeID != nil },
                set: { if !$0 { renameThemeID = nil } }
            )
        ) {
            TextField(String(localized: "Numele temei", comment: "Theme name field"), text: $renameText)
            Button(String(localized: "Salvează", comment: "Save button")) {
                if let id = renameThemeID {
                    pm.renameTheme(id: id, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                renameThemeID = nil
            }
            Button(String(localized: "Anulează", comment: "Cancel button"), role: .cancel) {
                renameThemeID = nil
            }
        }
    }

    private func importThemes() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = String(localized: "Alege pachete .tptheme — sau un folder care le conține", comment: "Import panel message")
        guard panel.runModal() == .OK else { return }

        // Selecting a plain folder imports every .tptheme found inside it.
        var packages: [URL] = []
        let fm = FileManager.default
        for url in panel.urls {
            if url.pathExtension == "tptheme" {
                packages.append(url)
            } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                let accessing = url.startAccessingSecurityScopedResource()
                let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
                packages.append(contentsOf: children.filter { $0.pathExtension == "tptheme" })
                if accessing { url.stopAccessingSecurityScopedResource() }
            } else {
                packages.append(url)
            }
        }

        var imported = 0
        for url in packages {
            if (try? pm.importTheme(from: url)) != nil { imported += 1 }
        }
        importResultMessage = imported > 0
            ? String(localized: "S-au importat \(imported) teme.", comment: "Import result")
            : String(localized: "Niciun pachet .tptheme valid în selecție.", comment: "Import result")
    }
}

/// One theme card: background thumbnail + miniature layout sketch + name.
private struct ThemeCard: View {
    @Environment(PresentationManager.self) private var pm

    let theme: PresentationManager.Theme
    let isActive: Bool
    let onRename: () -> Void

    @State private var thumbnail: NSImage?
    /// Hover-preview trigger — fires after a short rest so scanning the
    /// gallery doesn't thrash the live look.
    @State private var hoverTask: Task<Void, Never>?

    private var payload: PresentationManager.ThemePayload { theme.payload }

    /// The profile this card sketches: the theme's own format, else Bible.
    private var sketchKey: String {
        PresentationManager.profileKeys.contains(theme.formatRaw) ? theme.formatRaw : "bible"
    }
    private var sketch: PresentationManager.LayoutProfile {
        payload.profiles[sketchKey] ?? .defaultProfile(for: sketchKey)
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                // Background: theme color, then media thumbnail
                Color(hex: payload.backgroundEnabled ? payload.backgroundColorHex : "000000") ?? .black
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .opacity(payload.backgroundOpacity)
                }

                // Miniature layout sketch from the payload's frames
                GeometryReader { geo in
                    ZStack(alignment: .topLeading) {
                        ForEach(PresentationManager.relevantSections(for: sketchKey)) { section in
                            if sketch.visibility[section.rawValue] ?? true {
                                let frame = sketch.frames[section.rawValue] ?? PresentationManager.TextBoxFrame.defaultVerse
                                let rect = frame.rect(in: geo.size)
                                if section == .verseContent {
                                    Text("Aa")
                                        .font(.system(size: max(rect.height * 0.42, 7), weight: .semibold))
                                        .foregroundStyle(
                                            (Color(hex: sketch.styles[section.rawValue]?.colorHex ?? "") ?? (Color(hex: payload.textColorHex) ?? .white))
                                        )
                                        .frame(width: rect.width, height: rect.height)
                                        .position(x: rect.midX, y: rect.midY)
                                } else {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(.white.opacity(0.35))
                                        .frame(width: rect.width, height: max(rect.height * 0.45, 2))
                                        .position(x: rect.midX, y: rect.midY)
                                }
                            }
                        }
                    }
                }

                // Media-type badge
                if payload.useBackgroundImage && payload.backgroundMediaTypeRaw != "image" {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: payload.backgroundMediaTypeRaw == "video" ? "video.fill" : "photo.stack")
                                .font(.system(size: 7))
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(2)
                                .background(.black.opacity(0.5), in: Capsule())
                        }
                        Spacer()
                    }
                    .padding(3)
                }
            }
            .frame(width: 108, height: 61)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        isActive ? Color.accentColor : Color.gray.opacity(0.35),
                        lineWidth: isActive ? 2 : 1
                    )
            )

            HStack(spacing: 3) {
                if theme.formatRaw != "all" {
                    Circle()
                        .fill(formatColor)
                        .frame(width: 5, height: 5)
                }
                Text(theme.name)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
            }
            .frame(width: 108)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            hoverTask?.cancel()
            pm.applyTheme(id: theme.id)
        }
        // Rest the cursor on a card → the preview shows that theme; move away
        // → the real look comes back. Disabled while live (no projector flicker).
        .onHover { hovering in
            hoverTask?.cancel()
            if hovering {
                hoverTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    pm.beginThemeHoverPreview(id: theme.id)
                }
            } else {
                pm.endThemeHoverPreview()
            }
        }
        .onDisappear {
            hoverTask?.cancel()
            pm.endThemeHoverPreview()
        }
        .help("\(theme.name) — \(PresentationManager.Theme.formatLabel(theme.formatRaw))")
        .task(id: payload.backgroundImageBookmark) {
            thumbnail = await MediaThumbnailer.thumbnail(
                forBookmark: payload.backgroundImageBookmark,
                mediaType: payload.backgroundMediaTypeRaw
            )
        }
        .contextMenu {
            Button {
                pm.applyTheme(id: theme.id)
            } label: {
                Label(String(localized: "Aplică tema", comment: "Context menu"), systemImage: "checkmark.circle")
            }

            Button {
                pm.updateTheme(id: theme.id)
            } label: {
                Label(String(localized: "Actualizează din aspectul curent", comment: "Context menu"), systemImage: "square.and.arrow.down")
            }

            Button {
                onRename()
            } label: {
                Label(String(localized: "Redenumește…", comment: "Context menu"), systemImage: "pencil")
            }

            Menu {
                ForEach(["all", "bible", "song", "text"], id: \.self) { raw in
                    Button {
                        pm.setThemeFormat(id: theme.id, formatRaw: raw)
                    } label: {
                        if theme.formatRaw == raw {
                            Label(PresentationManager.Theme.formatLabel(raw), systemImage: "checkmark")
                        } else {
                            Text(PresentationManager.Theme.formatLabel(raw))
                        }
                    }
                }
            } label: {
                Label(String(localized: "Format", comment: "Context menu"), systemImage: "tag")
            }

            Divider()

            Button {
                exportTheme()
            } label: {
                Label(String(localized: "Exportă…", comment: "Context menu"), systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive) {
                pm.deleteTheme(id: theme.id)
            } label: {
                Label(String(localized: "Șterge", comment: "Context menu"), systemImage: "trash")
            }
        }
    }

    private var formatColor: Color {
        switch theme.formatRaw {
        case "bible": return .cyan
        case "song": return .orange
        case "text": return .green
        default: return .gray
        }
    }

    private func exportTheme() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = theme.name + ".tptheme"
        panel.message = String(localized: "Exportă tema ca pachet .tptheme (include toate fișierele media)", comment: "Export panel message")
        if panel.runModal() == .OK, let url = panel.url {
            try? pm.exportTheme(id: theme.id, to: url)
        }
    }
}

// MARK: - Layout Editor Sheet

/// The design studio: large canvas on the left (drag/resize boxes, click to
/// select, right-click for actions, arrow keys to nudge), tabbed inspector on
/// the right. Selecting a box shows ALL its settings, clearly grouped.
struct LayoutEditorSheet: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selection: BoxIdentity? = .section(.verseContent)
    @State private var activeTab: EditorTab = .layout
    /// Mirrors the output's interlinear master switch so the canvas preview matches.
    @AppStorage("interlinearLiveEnabled") private var interlinearLiveEnabled = true
    /// Quick-align toggle memory: pressing the same action again restores the
    /// frame from before the action was applied.
    @State private var quickActionMemory: [BoxIdentity: [String: PresentationManager.TextBoxFrame]] = [:]
    @State private var availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()
    @State private var renameTarget: BoxIdentity?
    @State private var renameText = ""
    /// Canvas demo of a transition effect: changing the tick re-inserts the
    /// sample content with `transitionPreviewRaw` as its transition.
    @State private var transitionPreviewTick = 0
    @State private var transitionPreviewRaw: String?

    private enum EditorTab: String, CaseIterable, Identifiable {
        case layout, text, background, presenter

        var id: String { rawValue }

        var title: String {
            switch self {
            case .layout: return String(localized: "Layout", comment: "Editor tab")
            case .text: return String(localized: "Text", comment: "Editor tab")
            case .background: return String(localized: "Fundal", comment: "Editor tab")
            case .presenter: return String(localized: "Tranziții", comment: "Editor tab")
            }
        }
    }

    private var metrics: PresentationManager.ScreenMetrics {
        pm.targetScreenMetrics
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                canvas
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
                    .padding(16)

                inspector
                    .frame(width: 310)
            }
        }
        .frame(minWidth: 1030, idealWidth: 1190, minHeight: 640, idealHeight: 720)
        .onAppear {
            // Open on the profile of the module the editor was launched from.
            switch appState.selectedSidebarItem {
            case .bible: pm.activeProfileKey = "bible"
            case .songs: pm.activeProfileKey = "song"
            case .customSlides: pm.activeProfileKey = "text"
            default: break
            }
        }
        .onChange(of: pm.activeProfileKey) {
            // Box ids are per-profile — the old selection means nothing here.
            selection = .section(.verseContent)
            quickActionMemory = [:]
        }
        .alert(
            String(localized: "Redenumește caseta", comment: "Rename alert title"),
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField(String(localized: "Nume", comment: "Rename field"), text: $renameText)
            Button(String(localized: "Salvează", comment: "Save button")) {
                if let target = renameTarget {
                    pm.renameBox(target, to: renameText.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                renameTarget = nil
            }
            Button(String(localized: "Anulează", comment: "Cancel button"), role: .cancel) {
                renameTarget = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        @Bindable var pmBinding = pm

        return HStack {
            Label(
                String(localized: "Editor de Teme", comment: "Theme editor title"),
                systemImage: "paintbrush.pointed.fill"
            )
            .font(.headline)

            // PER-PRESENTER profiles: the editor edits exactly one at a time.
            Picker("", selection: $pmBinding.activeProfileKey) {
                ForEach(PresentationManager.profileKeys, id: \.self) { key in
                    Text(PresentationManager.contentKeyLabel(key)).tag(key)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .padding(.leading, 8)
            .help(String(localized: "Fiecare prezentator (Biblie, Cântece, Slide-uri) are propriul layout: casete, fundal și tranziții", comment: "Tooltip"))

            Menu {
                ForEach(PresentationManager.profileKeys.filter { $0 != pm.activeProfileKey }, id: \.self) { source in
                    Button {
                        pm.copyProfile(from: source, to: pm.activeProfileKey)
                    } label: {
                        Text(PresentationManager.contentKeyLabel(source))
                    }
                }
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(String(localized: "Copiază layout-ul altui prezentator în cel curent", comment: "Tooltip"))

            ThemeMenuControl()
                .padding(.leading, 4)

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(metrics.resolution.width))×\(Int(metrics.resolution.height))")
                    .font(.caption.monospacedDigit())
                Text(metrics.aspectRatioLabel)
                    .font(.caption.bold())
                Text("\(Int(metrics.ppi)) PPI")
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(.secondary)
            .help(String(localized: "Ecranul țintă curent — layout-ul se adaptează automat la schimbarea lui", comment: "Tooltip"))

            Button(String(localized: "Gata", comment: "Done button")) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .help(String(localized: "Închide editorul (modificările se salvează automat)", comment: "Tooltip"))
        }
        .padding(12)
    }

    // MARK: Quick Actions Bar

    /// Applies a quick-align action as a TOGGLE: pressing the same button again
    /// restores the box to where it was before the action.
    private func toggleQuickAction(_ action: String, apply: (BoxIdentity) -> Void) {
        guard let selection else { return }
        if let saved = quickActionMemory[selection]?[action] {
            pm.setBoxFrame(saved, for: selection)
            quickActionMemory[selection]?[action] = nil
        } else {
            let current = pm.boxFrame(for: selection)
            quickActionMemory[selection, default: [:]][action] = current
            apply(selection)
        }
    }

    private func addMediaFromPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            if let box = pm.addMediaBox(url: url) {
                selection = .media(box.id)
                activeTab = .layout
            }
        }
    }

    // MARK: Canvas

    private var canvas: some View {
        Color.clear
            .aspectRatio(metrics.aspectRatio, contentMode: .fit)
            .overlay(
                GeometryReader { geo in
                    let size = geo.size

                    ZStack(alignment: .topLeading) {
                        // Background: black stand-in + the configured background
                        Rectangle().fill(.black)
                        let bg = pm.activeBackground(forKey: pm.activeProfileKey, frozen: false)
                        if bg.showColor {
                            bg.color
                        }
                        if bg.useMedia {
                            BackgroundMediaView(background: bg, plays: true)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                        }

                        // Content + media rendered in the unified stacking order.
                        // The id/transition pair powers the Tranziții demo.
                        sampleContent(size: size)
                            .id(transitionPreviewTick)
                            .transition(PresentationManager.transitionPart(transitionPreviewRaw ?? "fade"))

                        // Interactive box overlay — always on in the editor
                        TextBoxEditOverlay(canvasSize: size, showsHiddenBoxes: false, selection: $selection)
                    }
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )
                    .focusable()
                    .focusEffectDisabled()
                    .onKeyPress(phases: .down) { press in
                        handleCanvasKey(press)
                    }
                }
            )
    }

    /// Arrow keys nudge the selected box by 1% (⇧ = 5%); Escape deselects.
    private func handleCanvasKey(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            selection = nil
            return .handled
        }
        guard let selection else { return .ignored }
        let step: Double = press.modifiers.contains(.shift) ? 0.05 : 0.01
        var frame = pm.boxFrame(for: selection)
        switch press.key {
        case .leftArrow: frame.x -= step
        case .rightArrow: frame.x += step
        case .upArrow: frame.y -= step
        case .downArrow: frame.y += step
        default: return .ignored
        }
        pm.setBoxFrame(frame, for: selection)
        return .handled
    }

    // MARK: Sample content (mirrors the output rendering, scaled)

    /// Live content only stands in as sample when it matches the edited profile —
    /// editing the Songs layout while a Bible verse is live shows song samples.
    private var liveMatchesProfile: Bool {
        pm.liveContent.isLive
            && PresentationManager.contentKey(for: pm.liveContent.contentType) == pm.activeProfileKey
    }

    /// A small chord chart shown on the editor canvas when no song is live, so the
    /// Acorduri box can be positioned/styled.
    static let sampleChordLines: [SongLine] = [
        SongLine(text: "Ce mare ești Tu, Doamne!", chords: [SongChord(sym: "G", pos: 0), SongChord(sym: "D", pos: 11)]),
        SongLine(text: "Cât de minunate sunt lucrările Tale,", chords: [SongChord(sym: "Em", pos: 0), SongChord(sym: "C", pos: 17)]),
        SongLine(text: "Întreg pământul cântă slava Ta.", chords: [SongChord(sym: "G", pos: 0), SongChord(sym: "D", pos: 16), SongChord(sym: "G", pos: 23)]),
    ]

    private var sampleVerse: String {
        if liveMatchesProfile, !pm.liveContent.mainText.isEmpty {
            return pm.liveContent.mainText
        }
        switch pm.activeProfileKey {
        case "song":
            return String(localized: "Ce mare ești Tu, Doamne!\nCât de minunate sunt lucrările Tale,\nÎntreg pământul cântă slava Ta.", comment: "Layout editor sample song lyrics")
        case "text":
            return String(localized: "Bine ați venit!\nVă așteptăm duminică la ora 10:00.", comment: "Layout editor sample slide text")
        default:
            if !libraryManager.selectedVerses.isEmpty {
                return libraryManager.selectedVersesText
            }
            return String(localized: "Fiindcă atât de mult a iubit Dumnezeu lumea, că a dat pe singurul Lui Fiu, pentru ca oricine crede în El să nu piară, ci să aibă viața veșnică.", comment: "Layout editor sample verse")
        }
    }

    private var sampleReference: String {
        if liveMatchesProfile, !pm.liveContent.reference.isEmpty {
            return pm.liveContent.reference
        }
        switch pm.activeProfileKey {
        case "song":
            return String(localized: "Ce mare ești Tu", comment: "Layout editor sample song title")
        case "text":
            return String(localized: "Anunțuri", comment: "Layout editor sample slide title")
        default:
            if !libraryManager.selectedVerses.isEmpty {
                return libraryManager.selectedVersesReference
            }
            return String(localized: "Ioan 3:16", comment: "Layout editor sample reference")
        }
    }

    private var sampleTranslation: String {
        guard pm.activeProfileKey == "bible" else { return "" }
        if liveMatchesProfile, !pm.liveContent.translationName.isEmpty {
            return pm.liveContent.translationName
        }
        return libraryManager.selectedBibleModule?.abbreviation ?? "VDC"
    }

    private var sampleSubtitle: String {
        if liveMatchesProfile, !pm.liveContent.subtitle.isEmpty {
            return pm.liveContent.subtitle
        }
        return String(localized: "Strofa 1", comment: "Layout editor sample subtitle")
    }

    /// Red-letter runs for the verse box on the editor canvas, so the Cuvintele
    /// lui Isus color is visible while editing. Uses real runs from the live/
    /// selected verse; for the default placeholder (John 3:16 — Jesus speaking)
    /// it colors the whole sample.
    private var sampleRuns: [VerseRun] {
        guard pm.activeProfileKey == "bible", pm.wocStyleEnabled else { return [] }
        if liveMatchesProfile, pm.liveContent.mainRuns.contains(where: { $0.kind == "woc" }) {
            return pm.liveContent.mainRuns
        }
        if !libraryManager.selectedVerses.isEmpty {
            let runs = libraryManager.selectedVersesRuns
            return runs.contains(where: { $0.kind == "woc" }) ? runs : []
        }
        return [VerseRun(text: sampleVerse, kind: "woc")]
    }

    /// REAL runs for the interlinear canvas preview — the live or selected verse,
    /// never fabricated, so the editor matches the preview card and the output
    /// exactly (the grid appears only when the Bible actually carries the data).
    private var sampleInterlinearRuns: [VerseRun] {
        guard pm.activeProfileKey == "bible" else { return [] }
        return liveMatchesProfile ? pm.liveContent.mainRuns : libraryManager.selectedVersesRuns
    }

    /// Whether the current Bible selection actually carries interlinear annotations
    /// (Strong's / morph / gloss). Drives the editor's "no data" hint.
    private var currentBibleHasInterlinearData: Bool {
        sampleInterlinearRuns.contains {
            ($0.strong?.isEmpty == false) || ($0.gloss?.isEmpty == false) || ($0.morph?.isEmpty == false)
        }
    }

    /// Binding into the active profile's ContentOptions (interlinear fields etc.).
    private func ilBinding<T>(_ kp: WritableKeyPath<PresentationManager.ContentOptions, T>) -> Binding<T> {
        Binding(
            get: { pm.contentOptions(for: pm.activeProfileKey)[keyPath: kp] },
            set: { v in
                var o = pm.contentOptions(for: pm.activeProfileKey)
                o[keyPath: kp] = v
                pm.setContentOptions(o, for: pm.activeProfileKey)
            }
        )
    }

    /// One annotation-row control: visibility toggle + colour + relative size.
    @ViewBuilder
    private func interlinearRowControl(_ label: String, show: Binding<Bool>,
                                       colorHex: Binding<String>, scale: Binding<Double>) -> some View {
        HStack(spacing: 6) {
            Toggle(isOn: show) { Text(label).font(.caption) }
                .toggleStyle(.switch).controlSize(.mini)
            Spacer()
            if show.wrappedValue {
                ColorPicker("", selection: Binding(
                    get: { colorHex.wrappedValue.isEmpty ? Color.gray : (Color(hex: colorHex.wrappedValue) ?? .gray) },
                    set: { colorHex.wrappedValue = $0.toHex() }
                ))
                .labelsHidden().controlSize(.mini)
                Slider(value: scale, in: 0.25...1.0).frame(width: 70).controlSize(.mini)
            }
        }
    }

    @ViewBuilder
    private func sampleContent(size: CGSize) -> some View {
        let targetScale = pm.targetFontScale
        let canvasScale = size.width / max(metrics.points.width, 1)
        let fontScale = targetScale * canvasScale

        // Transforms (MAJUSCULE etc.) are part of each box's resolved style —
        // they show on the canvas the moment they're toggled in the Text tab.
        let fields = (main: sampleVerse, reference: sampleReference,
                      translation: sampleTranslation, subtitle: sampleSubtitle)

        ZStack(alignment: .topLeading) {
            // Unified stacking order — exactly what the output renders
            ForEach(pm.orderedBoxTokens(), id: \.self) { token in
                switch boxIdentity(fromToken: token) {
                case .section(let section):
                    if section == .chords, pm.isSectionVisible(section) {
                        // Chord chart preview: live song lines, else a sample chart.
                        let rect = pm.boxFrame(for: section).rect(in: size)
                        let style = pm.resolvedStyle(for: section)
                        let lines = pm.liveContent.songLines.isEmpty ? Self.sampleChordLines : pm.transposedSongLines()
                        ChordChartText(lines: lines, lyricStyle: style,
                                       chordStyle: pm.resolvedChordRowStyle(), rect: rect, fontScale: fontScale)
                    } else if section != .chords, pm.isSectionVisible(section),
                              !(section == .verseContent && pm.activeProfileKey == "song" && pm.isSectionVisible(.chords)) {
                        let text = pm.sectionText(
                            section,
                            main: fields.main, reference: fields.reference,
                            translation: fields.translation, subtitle: fields.subtitle,
                            slideNumber: "1 / 4"
                        )
                        if !text.isEmpty {
                            let rect = pm.boxFrame(for: section).rect(in: size)
                            let style = pm.resolvedStyle(for: section)
                            let fitted: CGFloat? = style.autoFit
                                ? pm.fittedVerseFontSize(
                                    text: text,
                                    boxSize: pm.boxFrame(for: section).rect(in: metrics.points).size,
                                    maxSize: CGFloat(style.fontSize) * targetScale,
                                    padding: CGFloat(style.padding) * targetScale,
                                    fontName: style.fontName,
                                    lineSpacing: style.lineSpacing
                                  ) * canvasScale
                                : nil
                            let ilOpts = pm.contentOptions(for: pm.activeProfileKey)
                            let ilRuns = sampleInterlinearRuns
                            if section == .verseContent, pm.activeProfileKey == "bible",
                               interlinearLiveEnabled, interlinearHasContent(ilRuns, options: ilOpts) {
                                InterlinearText(columns: interlinearColumns(from: ilRuns), style: style,
                                                options: ilOpts, wocColor: pm.wocColor, rect: rect, fontScale: fontScale)
                            } else {
                                sampleBoxText(text, style: style, rect: rect, fontScale: fontScale, fittedSize: fitted,
                                              runs: section == .verseContent ? sampleRuns : [])
                            }
                        }
                    }
                case .custom(let id):
                    if let box = pm.customTextBox(id: id), box.isVisible {
                        let resolved = box.resolvedText(
                            main: fields.main, reference: fields.reference,
                            translation: fields.translation, subtitle: fields.subtitle,
                            slideNumber: "1 / 4"
                        )
                        let text = resolved.isEmpty ? box.sourceLabel : resolved
                        let rect = box.frame.rect(in: size)
                        let style = pm.resolvedCustomStyle(box)
                        sampleBoxText(text, style: style, rect: rect, fontScale: fontScale, fittedSize: nil)
                    }
                case .media(let id):
                    // Editor shows every visible media box, ignoring content filters
                    if let box = pm.mediaBox(id: id), box.isVisible {
                        MediaBoxContent(box: box, canvasSize: size, playsVideo: false)
                            .allowsHitTesting(false)
                    }
                case nil:
                    EmptyView()
                }
            }
        }
    }

    private func sampleBoxText(
        _ text: String,
        style: PresentationManager.ResolvedBoxStyle,
        rect: CGRect, fontScale: CGFloat,
        fittedSize: CGFloat?,
        runs: [VerseRun] = []
    ) -> some View {
        let size = fittedSize ?? CGFloat(style.fontSize) * fontScale
        let composed: Text = runs.contains(where: { $0.kind == "woc" })
            ? runs.reduce(Text("")) { acc, run in
                let c = (run.kind == "woc") ? pm.wocColor : style.color
                return acc + Text(style.display(run.text)).foregroundColor(c.opacity(style.opacity))
              }
            : Text(style.display(text)).foregroundColor(style.color.opacity(style.opacity))
        return composed
            .font(style.font(at: size))
            .multilineTextAlignment(style.hAlign)
            .lineSpacing(style.lineSpacing * size * 0.1)
            .tracking(style.tracking * fontScale)
            .minimumScaleFactor(fittedSize == nil ? 0.2 : 1.0)
            .shadow(
                color: style.shadowEnabled ? style.shadowColor : .clear,
                radius: style.shadowEnabled ? style.shadowRadius * fontScale : 0,
                x: 0,
                y: style.shadowEnabled ? 2 * fontScale : 0
            )
            .padding(.horizontal, CGFloat(style.padding) * fontScale)
            .frame(width: rect.width, height: rect.height, alignment: style.frameAlignment)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(spacing: 0) {
            // Casete are THE working set — always visible, above the tabs.
            caseteGroup
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            Picker("", selection: $activeTab) {
                ForEach(EditorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            ScrollView {
                switch activeTab {
                case .layout:
                    layoutTab
                case .text:
                    textTab
                case .background:
                    backgroundTab
                case .presenter:
                    presenterTab
                }
            }
        }
    }

    // MARK: Casete Group (pinned above the inspector tabs)

    @ViewBuilder
    private var caseteGroup: some View {
        let tokens = pm.orderedBoxTokens()
        // The list shows ~3.5 rows and scrolls for the rest — no dead space
        // when there are few boxes.
        let rowHeight: CGFloat = 27
        let listHeight = min(CGFloat(tokens.count), 4) * rowHeight

        GroupBox {
            VStack(spacing: 2) {
                // Unified stacking order — first row = on top of the screen.
                // Drag any row to reorder; right-click for layer actions.
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tokens.reversed(), id: \.self) { token in
                            if let identity = boxIdentity(fromToken: token) {
                                boxListRow(identity: identity)
                                    .frame(height: rowHeight - 2)
                            }
                        }
                    }
                }
                .frame(height: listHeight)

                HStack(spacing: 6) {
                    Button {
                        let box = pm.addCustomTextBox()
                        selection = .custom(box.id)
                        activeTab = .layout
                    } label: {
                        Label(String(localized: "Casetă Text", comment: "Add box button"), systemImage: "plus.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .help(String(localized: "Adaugă o casetă de text nouă", comment: "Tooltip"))

                    Button {
                        addMediaFromPanel()
                    } label: {
                        Label(String(localized: "Casetă Media", comment: "Add media button"), systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .help(String(localized: "Adaugă imagine, GIF sau video", comment: "Tooltip"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 6)
            }
        } label: {
            HStack {
                Label(String(localized: "Casete", comment: "Inspector group"), systemImage: "square.3.layers.3d")
                    .font(.caption.bold())
                Spacer()
                Button {
                    pm.undoLayout()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!pm.canUndoLayout)
                .help(String(localized: "Anulează ultima modificare a casetelor", comment: "Tooltip"))

                Button {
                    pm.redoLayout()
                } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .disabled(!pm.canRedoLayout)
                .help(String(localized: "Refă modificarea anulată", comment: "Tooltip"))
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Layout Tab

    @ViewBuilder
    private var layoutTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selection {
                selectedBoxDetail(for: selection)
            } else {
                Text(String(localized: "Selectează o casetă din listă sau de pe canvas.", comment: "Inspector hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(String(localized: "Resetează Layout", comment: "Reset layout button"), role: .destructive) {
                pm.resetAllBoxFrames()
                quickActionMemory = [:]
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .help(String(localized: "Readuce toate casetele la pozițiile implicite", comment: "Tooltip"))
        }
        .padding(12)
    }

    /// Handles a list drag-reorder drop: any box onto any box — the dragged
    /// row takes the visual slot above the target (list shows front-first).
    private func handleReorderDrop(_ token: String, onto identity: BoxIdentity) -> Bool {
        guard boxIdentity(fromToken: token) != nil else { return false }
        pm.reorderBoxToken(token, above: boxToken(for: identity))
        return true
    }

    @ViewBuilder
    private func boxListRow(identity: BoxIdentity) -> some View {
        let isSelected = selection == identity
        let isVisible = pm.isBoxVisible(identity)

        // The LEADING area selects + drags; the eye/trash buttons live outside
        // the drag/tap surface so their clicks are never swallowed.
        let leading = HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .help(String(localized: "Trage pentru a reordona (primul = deasupra pe ecran)", comment: "Tooltip"))
            BoxColorSwatch(identity: identity)
            Text(boxLabel(for: identity, pm: pm))
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { selection = identity }
        .draggable(boxToken(for: identity))

        HStack(spacing: 6) {
            leading

            Button {
                pm.toggleBoxVisibility(identity)
            } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.caption2)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Afișează / ascunde caseta", comment: "Tooltip"))

            Button(role: .destructive) {
                removeOrHide(identity)
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help({
                if case .section = identity {
                    return String(localized: "Elimină caseta (o poți reactiva cu ochiul)", comment: "Tooltip")
                }
                return String(localized: "Șterge caseta", comment: "Tooltip")
            }())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .help(boxSourceDescription(for: identity, pm: pm))
        .opacity(isVisible ? 1.0 : 0.55)
        .contextMenu { listRowMenu(identity: identity) }
        .dropDestination(for: String.self) { items, _ in
            guard let dropped = items.first else { return false }
            return handleReorderDrop(dropped, onto: identity)
        }
    }

    /// "Remove" semantics: custom/media are deleted; translation & subtitle are hidden.
    private func removeOrHide(_ identity: BoxIdentity) {
        switch identity {
        case .section(let section):
            pm.setSectionVisible(false, for: section)
        case .custom(let id):
            pm.removeCustomTextBox(id: id)
            if selection == identity { selection = .section(.verseContent) }
        case .media(let id):
            pm.removeMediaBox(id: id)
            if selection == identity { selection = .section(.verseContent) }
        }
    }

    /// Right-click menu on a list row — same actions as the canvas menu.
    @ViewBuilder
    private func listRowMenu(identity: BoxIdentity) -> some View {
        Text(boxSourceDescription(for: identity, pm: pm))

        Divider()

        Button {
            pm.toggleBoxVisibility(identity)
        } label: {
            if pm.isBoxVisible(identity) {
                Label(String(localized: "Ascunde", comment: "Context menu"), systemImage: "eye.slash")
            } else {
                Label(String(localized: "Afișează", comment: "Context menu"), systemImage: "eye")
            }
        }

        if case .custom(let id) = identity {
            Button {
                renameText = boxLabel(for: identity, pm: pm)
                renameTarget = identity
            } label: {
                Label(String(localized: "Redenumește…", comment: "Context menu"), systemImage: "pencil")
            }

            Button {
                if let copy = pm.duplicateCustomTextBox(id: id) {
                    selection = .custom(copy.id)
                }
            } label: {
                Label(String(localized: "Duplică", comment: "Context menu"), systemImage: "plus.square.on.square")
            }
        }

        if case .media = identity {
            Button {
                renameText = boxLabel(for: identity, pm: pm)
                renameTarget = identity
            } label: {
                Label(String(localized: "Redenumește…", comment: "Context menu"), systemImage: "pencil")
            }
        }

        Divider()

        // Z-order — available for EVERY box
        Button(String(localized: "Adu în față", comment: "Z-order")) { pm.moveBoxTokenToEdge(boxToken(for: identity), front: true) }
        Button(String(localized: "Mai în față", comment: "Z-order")) { pm.moveBoxToken(boxToken(for: identity), offset: 1) }
        Button(String(localized: "Mai în spate", comment: "Z-order")) { pm.moveBoxToken(boxToken(for: identity), offset: -1) }
        Button(String(localized: "Trimite în spate", comment: "Z-order")) { pm.moveBoxTokenToEdge(boxToken(for: identity), front: false) }

        Divider()

        // EVERY box is removable — built-ins hide (the eye brings them back),
        // custom & media are deleted.
        Button(role: .destructive) {
            removeOrHide(identity)
        } label: {
            if case .section = identity {
                Label(String(localized: "Elimină", comment: "Context menu"), systemImage: "trash")
            } else {
                Label(String(localized: "Șterge", comment: "Context menu"), systemImage: "trash")
            }
        }
    }

    // MARK: Selected Box Detail (grouped)

    @ViewBuilder
    private func selectedBoxDetail(for identity: BoxIdentity) -> some View {
        // Group 1: Position & size — identical for every box kind
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                BoxFrameFields(identity: identity)

                Divider()

                // Quick aligns — toggles: pressing again restores the frame
                HStack(spacing: 6) {
                    Button {
                        toggleQuickAction("centerH") { pm.centerBoxHorizontally($0) }
                    } label: {
                        Image(systemName: "align.horizontal.center")
                    }
                    .help(String(localized: "Centrează orizontal (apasă din nou pentru a reveni)", comment: "Quick align tooltip"))

                    Button {
                        toggleQuickAction("centerV") { pm.centerBoxVertically($0) }
                    } label: {
                        Image(systemName: "align.vertical.center")
                    }
                    .help(String(localized: "Centrează vertical (apasă din nou pentru a reveni)", comment: "Quick align tooltip"))

                    Button {
                        toggleQuickAction("centerBoth") {
                            pm.centerBoxHorizontally($0)
                            pm.centerBoxVertically($0)
                        }
                    } label: {
                        Image(systemName: "plus.viewfinder")
                    }
                    .help(String(localized: "Centrează pe ecran (apasă din nou pentru a reveni)", comment: "Quick align tooltip"))

                    Button {
                        toggleQuickAction("fullW") { pm.makeBoxFullWidth($0) }
                    } label: {
                        Image(systemName: "arrow.left.and.right")
                    }
                    .help(String(localized: "Lățime completă (apasă din nou pentru a reveni)", comment: "Quick align tooltip"))

                    Button {
                        toggleQuickAction("fullH") { pm.makeBoxFullHeight($0) }
                    } label: {
                        Image(systemName: "arrow.up.and.down")
                    }
                    .help(String(localized: "Înălțime completă (apasă din nou pentru a reveni)", comment: "Quick align tooltip"))

                    Spacer()

                    Button {
                        pm.resetBox(for: identity)
                        quickActionMemory[identity] = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .help(String(localized: "Resetează caseta la poziția implicită", comment: "Quick align tooltip"))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } label: {
            Label(String(localized: "Poziție și Dimensiune", comment: "Inspector group"), systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.caption.bold())
        }

        switch identity {
        case .section(let section):
            sectionContentGroup(section)
            Text(String(localized: "Stilul textului (font, mărime, culoare…) se editează în tab-ul Text.", comment: "Inspector hint"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        case .custom(let id):
            if pm.customTextBox(id: id) != nil {
                customContentGroup(pm.customTextBox(id: id)!)
                Text(String(localized: "Stilul textului (font, mărime, culoare…) se editează în tab-ul Text.", comment: "Inspector hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        case .media(let id):
            if let box = pm.mediaBox(id: id) {
                mediaFileGroup(box)
                mediaAspectGroup(box)
                mediaBehaviorGroup(box)
            }
        }
    }

    /// The selected box's per-box text style — hosted in the TEXT tab.
    @ViewBuilder
    private func selectedBoxStyleGroup(_ identity: BoxIdentity) -> some View {
        switch identity {
        case .section(.chords):
            // The Acorduri box dresses lyrics + chord letters independently.
            VStack(alignment: .leading, spacing: 10) {
                textStyleGroup(
                    title: String(localized: "Versuri", comment: "Chord box — lyric style"),
                    style: Binding(
                        get: { pm.boxStyle(for: .chords) },
                        set: { pm.setBoxStyle($0, for: .chords) }
                    ),
                    onEnable: { pm.enableStyleCustomization(for: .chords) }
                )
                textStyleGroup(
                    title: String(localized: "Acorduri (litere)", comment: "Chord box — chord letters style"),
                    style: Binding(
                        get: { pm.chordRowStyle() },
                        set: { pm.setChordRowStyle($0) }
                    ),
                    onEnable: { pm.enableChordRowStyleCustomization() }
                )
            }
        case .section(let section):
            textStyleGroup(
                title: boxLabel(for: identity, pm: pm),
                style: Binding(
                    get: { pm.boxStyle(for: section) },
                    set: { pm.setBoxStyle($0, for: section) }
                ),
                onEnable: { pm.enableStyleCustomization(for: section) }
            )
        case .custom(let id):
            if let box = pm.customTextBox(id: id) {
                textStyleGroup(
                    title: boxLabel(for: identity, pm: pm),
                    style: Binding(
                        get: { (pm.customTextBox(id: id) ?? box).style },
                        set: { newStyle in
                            guard var current = pm.customTextBox(id: id) else { return }
                            current.style = newStyle
                            pm.updateCustomTextBox(current)
                        }
                    ),
                    onEnable: {
                        guard var current = pm.customTextBox(id: id) else { return }
                        let resolved = pm.resolvedCustomStyle(current)
                        current.style.isCustomized = true
                        current.style.fontSize = resolved.fontSize
                        current.style.weightRaw = PresentationManager.BoxTextStyle.weightRaw(resolved.weight)
                        current.style.opacity = resolved.opacity
                        pm.updateCustomTextBox(current)
                    }
                )
            }
        case .media:
            Text(String(localized: "Casetele media nu au setări de text.", comment: "Inspector hint"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Content group (built-in section)

    @ViewBuilder
    private func sectionContentGroup(_ section: TextBoxSection) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow(String(localized: "Sursă:", comment: "Setting label")) {
                    Picker("", selection: Binding(
                        get: { pm.sourceRaw(for: section) },
                        set: { pm.setSourceRaw($0, for: section) }
                    )) {
                        Text(String(localized: "Implicit (auto)", comment: "Box source option")).tag("auto")
                        Divider()
                        // Source choices + labels follow the EDITED presenter
                        ForEach(PresentationManager.sourceOptions(for: pm.activeProfileKey), id: \.raw) { option in
                            Text(option.label).tag(option.raw)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "De unde vine conținutul casetei — Implicit = câmpul ei natural", comment: "Tooltip"))

                labeledRow(String(localized: "Afișare:", comment: "Setting label")) {
                    Picker("", selection: Binding(
                        get: { pm.displayScope(for: section) },
                        set: { pm.setDisplayScope($0, for: section) }
                    )) {
                        ForEach(PresentationManager.displayScopeOptions(for: pm.activeProfileKey), id: \.raw) { option in
                            Text(option.label).tag(option.raw)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "Pe ce slide-uri apare caseta — ex. titlul cântecului doar pe primul, „Amin.” doar pe ultimul", comment: "Tooltip"))


                if pm.sourceRaw(for: section) == "static" {
                    TextField(
                        String(localized: "Text…", comment: "Static text placeholder"),
                        text: Binding(
                            get: { pm.staticText(for: section) },
                            set: { pm.setStaticText($0, for: section) }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                }

                clockFormatPicker(
                    source: pm.sourceRaw(for: section),
                    format: Binding(
                        get: { pm.sourceFormat(for: section) },
                        set: { pm.setSourceFormat($0, for: section) }
                    )
                )

                Text(boxSourceDescription(for: .section(section), pm: pm))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        } label: {
            Label(String(localized: "Conținut", comment: "Inspector group"), systemImage: "arrow.triangle.branch")
                .font(.caption.bold())
        }
    }

    // MARK: Content group (custom box)

    @ViewBuilder
    private func customContentGroup(_ box: PresentationManager.CustomTextBox) -> some View {
        let binding = Binding(
            get: { pm.customTextBox(id: box.id) ?? box },
            set: { pm.updateCustomTextBox($0) }
        )

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow(String(localized: "Nume:", comment: "Setting label")) {
                    TextField(
                        String(localized: "Numele casetei", comment: "Box name placeholder"),
                        text: Binding(
                            get: { binding.wrappedValue.name },
                            set: { binding.wrappedValue.name = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                }
                .help(String(localized: "Numele afișat în listă și pe canvas", comment: "Tooltip"))

                labeledRow(String(localized: "Sursă:", comment: "Setting label")) {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.sourceRaw },
                        set: { binding.wrappedValue.sourceRaw = $0 }
                    )) {
                        Text(String(localized: "Text static", comment: "Box source option")).tag("static")
                        Divider()
                        // Source choices + labels follow the EDITED presenter
                        ForEach(
                            PresentationManager.sourceOptions(for: pm.activeProfileKey).filter { $0.raw != "static" },
                            id: \.raw
                        ) { option in
                            Text(option.label).tag(option.raw)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "De unde vine textul: scris de tine sau preluat live", comment: "Tooltip"))

                labeledRow(String(localized: "Afișare:", comment: "Setting label")) {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.displayOnRaw },
                        set: { binding.wrappedValue.displayOnRaw = $0 }
                    )) {
                        ForEach(PresentationManager.displayScopeOptions(for: pm.activeProfileKey), id: \.raw) { option in
                            Text(option.label).tag(option.raw)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "Pe ce slide-uri apare caseta — ex. „Amin.” doar pe ultimul slide", comment: "Tooltip"))


                if binding.wrappedValue.sourceRaw == "static" {
                    TextField(
                        String(localized: "Text…", comment: "Custom box text placeholder"),
                        text: Binding(
                            get: { binding.wrappedValue.text },
                            set: { binding.wrappedValue.text = $0 }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                } else if binding.wrappedValue.supportsAffixes {
                    // Static text wrapped around the live value (e.g. "Ref: " + reference).
                    labeledRow(String(localized: "Înainte:", comment: "Box prefix label")) {
                        TextField(
                            String(localized: "ex. „Ref: ”", comment: "Box prefix placeholder"),
                            text: Binding(get: { binding.wrappedValue.prefix }, set: { binding.wrappedValue.prefix = $0 })
                        )
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    }
                    labeledRow(String(localized: "După:", comment: "Box suffix label")) {
                        TextField(
                            String(localized: "ex. „ (NTR)”", comment: "Box suffix placeholder"),
                            text: Binding(get: { binding.wrappedValue.suffix }, set: { binding.wrappedValue.suffix = $0 })
                        )
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                    }
                    .help(String(localized: "Text fix adăugat în jurul valorii live (gol când valoarea lipsește)", comment: "Tooltip"))
                }

                clockFormatPicker(
                    source: binding.wrappedValue.sourceRaw,
                    format: Binding(
                        get: { binding.wrappedValue.sourceFormatRaw },
                        set: { binding.wrappedValue.sourceFormatRaw = $0 }
                    )
                )
            }
        } label: {
            Label(String(localized: "Conținut", comment: "Inspector group"), systemImage: "arrow.triangle.branch")
                .font(.caption.bold())
        }
    }

    /// Date/time format picker — only shown for clock sources.
    @ViewBuilder
    private func clockFormatPicker(source: String, format: Binding<String>) -> some View {
        if source == "date" {
            labeledRow(String(localized: "Format:", comment: "Setting label")) {
                Picker("", selection: format) {
                    Text(String(localized: "Lung (11 iunie 2026)", comment: "Date format")).tag("")
                    Text(String(localized: "Scurt (11.06.2026)", comment: "Date format")).tag("short")
                    Text(String(localized: "Cu ziua săptămânii", comment: "Date format")).tag("weekday")
                }
                .labelsHidden()
                .controlSize(.small)
            }
            .help(String(localized: "Cum se afișează data", comment: "Tooltip"))
        } else if source == "time" {
            labeledRow(String(localized: "Format:", comment: "Setting label")) {
                Picker("", selection: format) {
                    Text(String(localized: "Oră : Minute", comment: "Time format")).tag("")
                    Text(String(localized: "Oră : Minute : Secunde", comment: "Time format")).tag("hms")
                }
                .labelsHidden()
                .controlSize(.small)
            }
            .help(String(localized: "Cum se afișează ora (se actualizează live pe ecran)", comment: "Tooltip"))
        }
    }

    // MARK: Text style group (uniform for every text box)

    /// The SAME text options for every box: a "Personalizează" switch gates the
    /// full set (font, size, weight, color, align H/V, spacing, opacity).
    /// Off = the box inherits the global text settings.
    @ViewBuilder
    private func textStyleGroup(
        title: String = String(localized: "Text", comment: "Inspector group"),
        style: Binding<PresentationManager.BoxTextStyle>,
        onEnable: @escaping () -> Void
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { style.wrappedValue.isCustomized },
                    set: { enabled in
                        if enabled {
                            onEnable()
                        } else {
                            style.wrappedValue.isCustomized = false
                        }
                    }
                )) {
                    Text(String(localized: "Personalizează textul", comment: "Customize toggle"))
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(String(localized: "Dezactivat = caseta moștenește setările globale de text", comment: "Tooltip"))

                if style.wrappedValue.isCustomized {
                    Divider()

                    // SAME options, SAME order as Text Global.
                    labeledRow(String(localized: "Font:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { style.wrappedValue.fontName },
                            set: { style.wrappedValue.fontName = $0 }
                        )) {
                            Text(String(localized: "Global", comment: "Font option")).tag("")
                            Text("System").tag("System")
                            ForEach(availableFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }

                    labeledRow(String(localized: "Mărime:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { style.wrappedValue.fontSize },
                                set: { style.wrappedValue.fontSize = $0 }
                            ),
                            in: 8...200, step: 2
                        )
                        .controlSize(.small)
                        Text("\(Int(style.wrappedValue.fontSize)) pt")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44)
                    }
                    .help(String(localized: "Mărimea fontului (la referința 1080p — se scalează automat)", comment: "Tooltip"))

                    labeledRow(String(localized: "Greutate:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { style.wrappedValue.weightRaw },
                            set: { style.wrappedValue.weightRaw = $0 }
                        )) {
                            Text(String(localized: "Regular", comment: "Weight")).tag("regular")
                            Text(String(localized: "Semibold", comment: "Weight")).tag("semibold")
                            Text(String(localized: "Bold", comment: "Weight")).tag("bold")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }

                    labeledRow(String(localized: "Culoare:", comment: "Setting label")) {
                        ColorPicker("", selection: Binding(
                            get: {
                                style.wrappedValue.colorHex.isEmpty
                                    ? pm.textColor
                                    : (Color(hex: style.wrappedValue.colorHex) ?? pm.textColor)
                            },
                            set: { style.wrappedValue.colorHex = $0.toHex() }
                        ))
                        .labelsHidden()
                        .controlSize(.small)
                        Spacer()
                        Button(String(localized: "Global", comment: "Button")) {
                            style.wrappedValue.colorHex = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(String(localized: "Revino la culoarea globală a textului", comment: "Tooltip"))
                    }

                    labeledRow(String(localized: "Aliniere:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { style.wrappedValue.hAlignRaw },
                            set: { style.wrappedValue.hAlignRaw = $0 }
                        )) {
                            Text(String(localized: "Global", comment: "Alignment option")).tag("")
                            Image(systemName: "text.alignleft").tag("leading")
                            Image(systemName: "text.aligncenter").tag("center")
                            Image(systemName: "text.alignright").tag("trailing")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }

                    labeledRow(String(localized: "Vertical:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { style.wrappedValue.vAlignRaw },
                            set: { style.wrappedValue.vAlignRaw = $0 }
                        )) {
                            Text(String(localized: "Global", comment: "Alignment option")).tag("")
                            Image(systemName: "arrow.up.to.line").tag("top")
                            Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up").tag("center")
                            Image(systemName: "arrow.down.to.line").tag("bottom")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Alinierea verticală în casetă — Global = setarea generală", comment: "Tooltip"))

                    labeledRow(String(localized: "Opacitate:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { style.wrappedValue.opacity },
                                set: { style.wrappedValue.opacity = $0 }
                            ),
                            in: 0...1, step: 0.01
                        )
                        .controlSize(.small)
                        Text("\(Int((style.wrappedValue.opacity * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 35)
                    }

                    labeledRow(String(localized: "Spațiere:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { style.wrappedValue.lineSpacing },
                                set: { style.wrappedValue.lineSpacing = $0 }
                            ),
                            in: -1...5, step: 0.1
                        )
                        .controlSize(.small)
                        Text(style.wrappedValue.lineSpacing >= 0 ? String(format: "%.1f", style.wrappedValue.lineSpacing) : String(localized: "Global", comment: "Value label"))
                            .font(.caption.monospacedDigit())
                            .frame(width: 42)
                    }
                    .help(String(localized: "Spațierea dintre rânduri — Global = setarea generală", comment: "Tooltip"))

                    labeledRow(String(localized: "Litere:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { style.wrappedValue.tracking ?? pm.letterTracking },
                                set: { style.wrappedValue.tracking = $0 }
                            ),
                            in: -2...30, step: 0.5
                        )
                        .controlSize(.small)
                        Text(style.wrappedValue.tracking != nil
                             ? String(format: "%.1f", style.wrappedValue.tracking!)
                             : String(localized: "Global", comment: "Value label"))
                            .font(.caption.monospacedDigit())
                            .frame(width: 42)
                        Button(String(localized: "G", comment: "Reset-to-global button")) {
                            style.wrappedValue.tracking = nil
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help(String(localized: "Revino la spațierea globală a literelor", comment: "Tooltip"))
                    }
                    .help(String(localized: "Spațierea dintre litere — Global = setarea generală", comment: "Tooltip"))

                    labeledRow(String(localized: "Transform.:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { style.wrappedValue.transformRaw },
                            set: { style.wrappedValue.transformRaw = $0 }
                        )) {
                            Text(String(localized: "Global", comment: "Text transform")).tag("")
                            Divider()
                            Text(String(localized: "Normal", comment: "Text transform")).tag("none")
                            Text(String(localized: "MAJUSCULE", comment: "Text transform")).tag("upper")
                            Text(String(localized: "minuscule", comment: "Text transform")).tag("lower")
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Transformarea textului acestei casete — Global = setarea generală a prezentatorului", comment: "Tooltip"))

                    labeledRow(String(localized: "Padding:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { style.wrappedValue.padding },
                                set: { style.wrappedValue.padding = $0 }
                            ),
                            in: -1...300, step: 1
                        )
                        .controlSize(.small)
                        Text(style.wrappedValue.padding >= 0 ? "\(Int(style.wrappedValue.padding))" : String(localized: "Global", comment: "Value label"))
                            .font(.caption.monospacedDigit())
                            .frame(width: 42)
                    }
                    .help(String(localized: "Spațiul interior orizontal al casetei — Global = setarea generală", comment: "Tooltip"))

                    labeledRow(String(localized: "Umbră:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { style.wrappedValue.shadowMode },
                            set: { style.wrappedValue.shadowMode = $0 }
                        )) {
                            Text(String(localized: "Global", comment: "Shadow option")).tag("")
                            Text(String(localized: "Pornită", comment: "Shadow option")).tag("on")
                            Text(String(localized: "Oprită", comment: "Shadow option")).tag("off")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Umbra textului acestei casete — Global = setarea generală", comment: "Tooltip"))

                    if style.wrappedValue.shadowMode == "on" {
                        labeledRow("") {
                            ColorPicker("", selection: Binding(
                                get: {
                                    let hex = style.wrappedValue.shadowColorHex.isEmpty
                                        ? pm.shadowColorHex
                                        : style.wrappedValue.shadowColorHex
                                    return Color(hex: hex) ?? Color.black.opacity(0.7)
                                },
                                set: { style.wrappedValue.shadowColorHex = $0.toHexWithAlpha() }
                            ), supportsOpacity: true)
                            .labelsHidden()
                            .controlSize(.small)
                            .help(String(localized: "Culoarea umbrei acestei casete — opacitatea ei dă intensitatea", comment: "Tooltip"))
                            Slider(
                                value: Binding(
                                    get: { style.wrappedValue.shadowRadius >= 0 ? style.wrappedValue.shadowRadius : pm.shadowRadius },
                                    set: { style.wrappedValue.shadowRadius = $0 }
                                ),
                                in: 0...50, step: 0.5
                            )
                            .controlSize(.small)
                            Text(String(format: "%.0f", style.wrappedValue.shadowRadius >= 0 ? style.wrappedValue.shadowRadius : pm.shadowRadius))
                                .font(.caption.monospacedDigit())
                                .frame(width: 24)
                        }
                    }

                    labeledRow(String(localized: "Auto-fit:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { style.wrappedValue.autoFitMode },
                            set: { style.wrappedValue.autoFitMode = $0 }
                        )) {
                            Text(String(localized: "Global", comment: "Auto-fit option")).tag("")
                            Text(String(localized: "Pornit", comment: "Auto-fit option")).tag("on")
                            Text(String(localized: "Oprit", comment: "Auto-fit option")).tag("off")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Micșorează automat fontul ca textul să încapă în casetă — Global = comportamentul general", comment: "Tooltip"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label(title, systemImage: "textformat")
                .font(.caption.bold())
        }
    }

    // MARK: Media groups

    @ViewBuilder
    private func mediaFileGroup(_ box: PresentationManager.MediaBox) -> some View {
        let binding = Binding(
            get: { pm.mediaBox(id: box.id) ?? box },
            set: { pm.updateMediaBox($0) }
        )

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow(String(localized: "Nume:", comment: "Setting label")) {
                    TextField(
                        String(localized: "Numele elementului", comment: "Box name placeholder"),
                        text: Binding(
                            get: { binding.wrappedValue.name },
                            set: { binding.wrappedValue.name = $0 }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                }

                HStack(spacing: 6) {
                    Image(systemName: boxIcon(for: .media(box.id), pm: pm))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(box.fileName)
                        .font(.caption2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(String(localized: "Înlocuiește…", comment: "Replace media button")) {
                        replaceMediaFile(boxID: box.id)
                    }
                    .controlSize(.mini)
                    .help(String(localized: "Alege alt fișier pentru această casetă", comment: "Tooltip"))
                }
            }
        } label: {
            Label(String(localized: "Fișier", comment: "Inspector group"), systemImage: "doc")
                .font(.caption.bold())
        }
    }

    @ViewBuilder
    private func mediaAspectGroup(_ box: PresentationManager.MediaBox) -> some View {
        let binding = Binding(
            get: { pm.mediaBox(id: box.id) ?? box },
            set: { pm.updateMediaBox($0) }
        )

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow(String(localized: "Mod:", comment: "Setting label")) {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.contentModeRaw },
                        set: { binding.wrappedValue.contentModeRaw = $0 }
                    )) {
                        Text(String(localized: "Încadrează", comment: "Content mode")).tag("fit")
                        Text(String(localized: "Umple", comment: "Content mode")).tag("fill")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "Încadrează = totul vizibil • Umple = acoperă caseta", comment: "Tooltip"))

                labeledRow(String(localized: "Opacitate:", comment: "Setting label")) {
                    Slider(
                        value: Binding(
                            get: { binding.wrappedValue.opacity },
                            set: { binding.wrappedValue.opacity = $0 }
                        ),
                        in: 0.05...1.0, step: 0.05
                    )
                    .controlSize(.small)
                    Text("\(Int(binding.wrappedValue.opacity * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 35)
                }

                labeledRow(String(localized: "Colțuri:", comment: "Setting label")) {
                    Slider(
                        value: Binding(
                            get: { binding.wrappedValue.cornerRadius },
                            set: { binding.wrappedValue.cornerRadius = $0 }
                        ),
                        in: 0...80, step: 2
                    )
                    .controlSize(.small)
                    Text("\(Int(binding.wrappedValue.cornerRadius))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 28)
                }
                .help(String(localized: "Rotunjirea colțurilor", comment: "Tooltip"))

                labeledRow(String(localized: "Estompare:", comment: "Setting label")) {
                    Slider(
                        value: Binding(
                            get: { binding.wrappedValue.edgeFeather },
                            set: { binding.wrappedValue.edgeFeather = $0 }
                        ),
                        in: 0...60, step: 2
                    )
                    .controlSize(.small)
                    Text("\(Int(binding.wrappedValue.edgeFeather))")
                        .font(.caption.monospacedDigit())
                        .frame(width: 28)
                }
                .help(String(localized: "Estompare la margini — opacitatea scade gradual spre bordură", comment: "Tooltip"))
            }
        } label: {
            Label(String(localized: "Aspect", comment: "Inspector group"), systemImage: "wand.and.stars")
                .font(.caption.bold())
        }
    }

    @ViewBuilder
    private func mediaBehaviorGroup(_ box: PresentationManager.MediaBox) -> some View {
        let binding = Binding(
            get: { pm.mediaBox(id: box.id) ?? box },
            set: { pm.updateMediaBox($0) }
        )

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                labeledRow(String(localized: "Vizibil:", comment: "Setting label")) {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.showOnRaw },
                        set: { binding.wrappedValue.showOnRaw = $0 }
                    )) {
                        Text(String(localized: "Întotdeauna", comment: "Media visibility option")).tag("always")
                        Text(String(localized: "Doar Biblie", comment: "Media visibility option")).tag("bible")
                        Text(String(localized: "Doar Cântece", comment: "Media visibility option")).tag("song")
                        Text(String(localized: "Doar Slide-uri", comment: "Media visibility option")).tag("text")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "Când apare pe ecran — ex. un decor doar pentru versetele biblice", comment: "Tooltip"))

                labeledRow(String(localized: "Afișare:", comment: "Setting label")) {
                    Picker("", selection: Binding(
                        get: { binding.wrappedValue.displayOnRaw },
                        set: { binding.wrappedValue.displayOnRaw = $0 }
                    )) {
                        ForEach(PresentationManager.displayScopeOptions(for: pm.activeProfileKey), id: \.raw) { option in
                            Text(option.label).tag(option.raw)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "Pe ce slide-uri apare — ex. un logo doar pe primul slide", comment: "Tooltip"))


                if box.mediaTypeRaw == "video" {
                    Text(String(localized: "Videoclipurile rulează în buclă, fără sunet, doar pe ecranul de proiecție.", comment: "Inspector hint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        } label: {
            Label(String(localized: "Comportament", comment: "Inspector group"), systemImage: "eye")
                .font(.caption.bold())
        }
    }

    private func replaceMediaFile(boxID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url,
           var box = pm.mediaBox(id: boxID),
           let bookmark = try? url.bookmarkData(
               options: .withSecurityScope,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            box.bookmarkData = bookmark
            box.fileName = url.lastPathComponent
            let ext = url.pathExtension.lowercased()
            if ext == "gif" {
                box.mediaTypeRaw = "gif"
            } else if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(ext) {
                box.mediaTypeRaw = "video"
            } else {
                box.mediaTypeRaw = "image"
            }
            pm.updateMediaBox(box)
        }
    }

    // MARK: Text Tab (GLOBAL settings only — per-box styling lives in Layout)

    @ViewBuilder
    private var textTab: some View {
        let pmBinding = Bindable(pm)

        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    labeledRow(String(localized: "Font:", comment: "Setting label")) {
                        Picker("", selection: pmBinding.fontName) {
                            Text(String(localized: "System", comment: "Font option")).tag("System")
                            ForEach(availableFonts, id: \.self) { font in
                                Text(font).tag(font)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Fontul de bază pentru tot textul", comment: "Tooltip"))

                    labeledRow(String(localized: "Mărime:", comment: "Setting label")) {
                        Slider(
                            value: pmBinding.fontSize,
                            in: PresentationDefaults.minFontSize...PresentationDefaults.maxFontSize,
                            step: 2
                        )
                        .controlSize(.small)
                        Text("\(Int(pm.fontSize)) pt")
                            .font(.caption.monospacedDigit())
                            .frame(width: 40)
                    }
                    .help(String(localized: "Mărimea de bază (la 1080p — se scalează automat cu ecranul)", comment: "Tooltip"))

                    labeledRow(String(localized: "Greutate:", comment: "Setting label")) {
                        Picker("", selection: pmBinding.globalWeightRaw) {
                            Text(String(localized: "Regular", comment: "Weight")).tag("regular")
                            Text(String(localized: "Semibold", comment: "Weight")).tag("semibold")
                            Text(String(localized: "Bold", comment: "Weight")).tag("bold")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Greutatea de bază a fontului (referința rămâne semibold)", comment: "Tooltip"))

                    labeledRow(String(localized: "Culoare:", comment: "Setting label")) {
                        ColorPicker("", selection: Binding(
                            get: { pm.textColor },
                            set: { pm.textColorHex = $0.toHex() }
                        ))
                        .labelsHidden()
                        .controlSize(.small)
                    }

                    labeledRow(String(localized: "Aliniere:", comment: "Setting label")) {
                        Picker("", selection: pmBinding.textAlignment) {
                            Image(systemName: "text.alignleft").tag(TextAlignment.leading)
                            Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                            Image(systemName: "text.alignright").tag(TextAlignment.trailing)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }

                    labeledRow(String(localized: "Vertical:", comment: "Setting label")) {
                        Picker("", selection: pmBinding.globalVAlignRaw) {
                            Image(systemName: "arrow.up.to.line").tag("top")
                            Image(systemName: "arrow.down.and.line.horizontal.and.arrow.up").tag("center")
                            Image(systemName: "arrow.down.to.line").tag("bottom")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Alinierea verticală implicită în interiorul casetelor", comment: "Tooltip"))

                    labeledRow(String(localized: "Opacitate:", comment: "Setting label")) {
                        Slider(value: pmBinding.globalTextOpacity, in: 0...1, step: 0.01)
                            .controlSize(.small)
                        Text("\(Int((pm.globalTextOpacity * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 35)
                    }
                    .help(String(localized: "Opacitatea de bază a textului — se combină cu opacitatea fiecărei casete", comment: "Tooltip"))

                    labeledRow(String(localized: "Spațiere:", comment: "Setting label")) {
                        Slider(value: pmBinding.lineSpacing, in: 0...5, step: 0.1)
                            .controlSize(.small)
                        Text(String(format: "%.1f", pm.lineSpacing))
                            .font(.caption.monospacedDigit())
                            .frame(width: 28)
                    }
                    .help(String(localized: "Spațiul dintre rânduri", comment: "Tooltip"))

                    labeledRow(String(localized: "Litere:", comment: "Setting label")) {
                        Slider(value: pmBinding.letterTracking, in: -2...30, step: 0.5)
                            .controlSize(.small)
                        Text(String(format: "%.1f", pm.letterTracking))
                            .font(.caption.monospacedDigit())
                            .frame(width: 28)
                    }
                    .help(String(localized: "Spațierea dintre litere (tracking, la referința 1080p)", comment: "Tooltip"))

                    labeledRow(String(localized: "Transform.:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { pm.contentOptions(for: pm.activeProfileKey).textTransformRaw },
                            set: { raw in
                                var o = pm.contentOptions(for: pm.activeProfileKey)
                                o.textTransformRaw = raw
                                pm.setContentOptions(o, for: pm.activeProfileKey)
                            }
                        )) {
                            Text(String(localized: "Normal", comment: "Text transform")).tag("none")
                            Text(String(localized: "MAJUSCULE", comment: "Text transform")).tag("upper")
                            Text(String(localized: "minuscule", comment: "Text transform")).tag("lower")
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Transformarea implicită a textului pentru TOATE casetele acestui prezentator — personalizabilă per casetă mai jos", comment: "Tooltip"))

                    labeledRow(String(localized: "Padding:", comment: "Setting label")) {
                        Slider(value: pmBinding.padding, in: 0...300, step: 5)
                            .controlSize(.small)
                        Text("\(Int(pm.padding))")
                            .font(.caption.monospacedDigit())
                            .frame(width: 28)
                    }
                    .help(String(localized: "Spațiul interior orizontal al fiecărei casete", comment: "Tooltip"))

                    labeledRow(String(localized: "Umbră:", comment: "Setting label")) {
                        Toggle("", isOn: pmBinding.shadowEnabled)
                            .labelsHidden()
                            .controlSize(.small)
                        if pm.shadowEnabled {
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: pm.shadowColorHex) ?? Color.black.opacity(0.7) },
                                set: { pm.shadowColorHex = $0.toHexWithAlpha() }
                            ), supportsOpacity: true)
                            .labelsHidden()
                            .controlSize(.small)
                            .help(String(localized: "Culoarea umbrei — opacitatea ei dă intensitatea", comment: "Tooltip"))
                            Slider(value: pmBinding.shadowRadius, in: 0...50, step: 0.5)
                                .controlSize(.small)
                            Text(String(format: "%.0f", pm.shadowRadius))
                                .font(.caption.monospacedDigit())
                                .frame(width: 20)
                        }
                    }

                    Toggle(isOn: pmBinding.autoFitVerseFont) {
                        Text(String(localized: "Auto-fit font size", comment: "Setting label"))
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(String(localized: "Micșorează automat fontul ca textul să încapă în caseta lui", comment: "Tooltip"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(String(localized: "Text Global", comment: "Inspector group"), systemImage: "textformat")
                    .font(.caption.bold())
            }

            // Red-letter — words of Jesus Christ (Bible presenter only).
            if pm.activeProfileKey == "bible" {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: pmBinding.wocStyleEnabled) {
                            Text(String(localized: "Evidențiază cuvintele lui Isus", comment: "Setting label"))
                                .font(.caption)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .help(String(localized: "Afișează cu altă culoare cuvintele rostite de Isus (red-letter). Funcționează cu Biblii care marchează aceste cuvinte — ex. OSIS / USFM.", comment: "Tooltip"))

                        if pm.wocStyleEnabled {
                            labeledRow(String(localized: "Culoare:", comment: "Setting label")) {
                                ColorPicker("", selection: Binding(
                                    get: { pm.wocColor },
                                    set: { pm.wocColorHex = $0.toHex() }
                                ))
                                .labelsHidden()
                                .controlSize(.small)
                                Spacer()
                                Button(String(localized: "Roșu clasic", comment: "Button")) {
                                    pm.wocColorHex = "C0392B"
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                            }
                            Text(String(localized: "Doar Bibliile care conțin marcajul „cuvinte ale lui Isus” vor fi colorate; celelalte rămân normale.", comment: "Inspector hint"))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(String(localized: "Cuvintele lui Isus", comment: "Inspector group"), systemImage: "quote.bubble")
                        .font(.caption.bold())
                }

                // Interlinear — stacked word columns (original + gloss + Strong's + morph).
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        labeledRow(String(localized: "Mod:", comment: "Setting label")) {
                            Picker("", selection: ilBinding(\.interlinearModeRaw)) {
                                Text(String(localized: "Dezactivat", comment: "Interlinear mode")).tag("off")
                                Text(String(localized: "Doar sens", comment: "Interlinear mode")).tag("gloss")
                                Text(String(localized: "Complet", comment: "Interlinear mode")).tag("full")
                            }
                            .pickerStyle(.segmented)
                            .controlSize(.small)
                        }
                        Toggle(isOn: $interlinearLiveEnabled) {
                            Text(String(localized: "Afișează pe ecran", comment: "Setting label")).font(.caption)
                        }
                        .toggleStyle(.switch).controlSize(.small)
                        .help(String(localized: "Comutator live pentru grila interliniară (stilul rămâne în temă).", comment: "Tooltip"))

                        if pm.contentOptions(for: pm.activeProfileKey).interlinearModeRaw != "off" {
                            interlinearRowControl(String(localized: "Sens", comment: "Annotation row"),
                                                  show: ilBinding(\.interlinearShowGloss),
                                                  colorHex: ilBinding(\.interlinearGlossColorHex),
                                                  scale: ilBinding(\.interlinearGlossScale))
                            if pm.contentOptions(for: pm.activeProfileKey).interlinearModeRaw == "full" {
                                interlinearRowControl(String(localized: "Strong", comment: "Annotation row"),
                                                      show: ilBinding(\.interlinearShowStrong),
                                                      colorHex: ilBinding(\.interlinearStrongColorHex),
                                                      scale: ilBinding(\.interlinearStrongScale))
                                interlinearRowControl(String(localized: "Morfologie", comment: "Annotation row"),
                                                      show: ilBinding(\.interlinearShowMorph),
                                                      colorHex: ilBinding(\.interlinearMorphColorHex),
                                                      scale: ilBinding(\.interlinearMorphScale))
                            }
                            labeledRow(String(localized: "Spațiere coloane:", comment: "Setting label")) {
                                Slider(value: ilBinding(\.interlinearColumnSpacing), in: 2...40).controlSize(.mini)
                            }
                            labeledRow(String(localized: "Spațiere rânduri:", comment: "Setting label")) {
                                Slider(value: ilBinding(\.interlinearRowSpacing), in: 0...14).controlSize(.mini)
                            }
                            // Tell the user exactly why the grid is (or isn't) showing.
                            if currentBibleHasInterlinearData {
                                Label(String(localized: "Date interliniare disponibile pentru selecția curentă.", comment: "Inspector hint"), systemImage: "checkmark.circle")
                                    .font(.caption2).foregroundStyle(.green)
                            } else {
                                Label(String(localized: "Biblia curentă nu are date interliniare — încarcă un modul cu Strong/interliniar (ex. ENINT, ASTL). Bibliile simple (EDC100) rămân normale.", comment: "Inspector hint"), systemImage: "exclamationmark.triangle")
                                    .font(.caption2).foregroundStyle(.orange)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label(String(localized: "Interliniar", comment: "Inspector group"), systemImage: "text.word.spacing")
                        .font(.caption.bold())
                }
            }

            // Per-box text style — select a box on the canvas, customize here.
            if let selection {
                selectedBoxStyleGroup(selection)
            } else {
                Text(String(localized: "Selectează o casetă pe canvas pentru a-i personaliza textul.", comment: "Inspector hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        }
        .padding(12)
    }

    // MARK: Background Tab (global + per-presenter overrides)

    @ViewBuilder
    private var backgroundTab: some View {
        let pmBinding = Bindable(pm)

        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: pmBinding.backgroundEnabled) {
                        Text(String(localized: "Culoare de fundal", comment: "Setting label"))
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(String(localized: "Dezactivat = fereastra de proiecție rămâne transparentă", comment: "Tooltip"))

                    if pm.backgroundEnabled {
                        labeledRow(String(localized: "Culoare:", comment: "Setting label")) {
                            ColorPicker("", selection: Binding(
                                get: { pm.backgroundColor },
                                set: { pm.backgroundColorHex = $0.toHex() }
                            ))
                            .labelsHidden()
                        }
                    }

                    labeledRow(String(localized: "Opacitate:", comment: "Setting label")) {
                        Slider(value: pmBinding.backgroundOpacity, in: 0...1)
                            .controlSize(.small)
                        Text("\(Int(pm.backgroundOpacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 35)
                    }
                    .help(String(localized: "Transparența imaginii de fundal", comment: "Tooltip"))

                    if pm.useBackgroundImage, let path = pm.backgroundImagePath {
                        HStack(spacing: 6) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                pm.removeBackgroundImage()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help(String(localized: "Elimină imaginea de fundal", comment: "Tooltip"))
                        }
                    }

                    Button(String(localized: "Alege imagine / video…", comment: "Button")) {
                        selectBackgroundImage()
                    }
                    .controlSize(.small)
                    .help(String(localized: "Fundal global: imagine, GIF animat sau video în buclă", comment: "Tooltip"))

                    if pm.useBackgroundImage {
                        BackgroundMediaThumb(
                            bookmark: UserDefaults.standard.data(forKey: "pm_backgroundImageBookmark"),
                            mediaType: pm.backgroundMediaTypeRaw,
                            opacity: pm.backgroundOpacity
                        )
                    }
                }
            } label: {
                Label(String(localized: "Global (toate prezentările)", comment: "Inspector group"), systemImage: "globe")
                    .font(.caption.bold())
            }

            // The EDITED profile's own background — switch profiles in the
            // header to set the others.
            contentBackgroundGroup(key: pm.activeProfileKey)
        }
        .padding(12)
    }

    @ViewBuilder
    private func contentBackgroundGroup(key: String) -> some View {
        let config = pm.backgroundConfig(for: key)

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { pm.backgroundConfig(for: key).enabled },
                    set: { enabled in
                        var c = pm.backgroundConfig(for: key)
                        c.enabled = enabled
                        pm.setBackgroundConfig(c, for: key)
                    }
                )) {
                    Text(String(localized: "Fundal personalizat", comment: "Setting label"))
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(String(localized: "Înlocuiește fundalul global doar pentru acest tip de prezentare", comment: "Tooltip"))

                if config.enabled {
                    Toggle(isOn: Binding(
                        get: { pm.backgroundConfig(for: key).showColor },
                        set: { v in
                            var c = pm.backgroundConfig(for: key)
                            c.showColor = v
                            pm.setBackgroundConfig(c, for: key)
                        }
                    )) {
                        Text(String(localized: "Culoare de fundal", comment: "Setting label"))
                            .font(.caption)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)

                    if config.showColor {
                        labeledRow(String(localized: "Culoare:", comment: "Setting label")) {
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: pm.backgroundConfig(for: key).colorHex) ?? .black },
                                set: { v in
                                    var c = pm.backgroundConfig(for: key)
                                    c.colorHex = v.toHex()
                                    pm.setBackgroundConfig(c, for: key)
                                }
                            ))
                            .labelsHidden()
                        }
                    }

                    labeledRow(String(localized: "Opacitate:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { pm.backgroundConfig(for: key).opacity },
                                set: { v in
                                    var c = pm.backgroundConfig(for: key)
                                    c.opacity = v
                                    pm.setBackgroundConfig(c, for: key)
                                }
                            ),
                            in: 0...1
                        )
                        .controlSize(.small)
                        Text("\(Int(config.opacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 35)
                    }

                    if config.useImage, !config.imageName.isEmpty {
                        HStack(spacing: 6) {
                            Text(config.imageName)
                                .font(.caption2)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                pm.removeContentBackgroundImage(for: key)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption2)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }

                    Button(String(localized: "Alege imagine / video…", comment: "Button")) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image, .movie]
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            pm.setContentBackgroundMedia(url: url, for: key)
                        }
                    }
                    .controlSize(.small)
                    .help(String(localized: "Fundal pentru acest prezentator: imagine, GIF sau video în buclă", comment: "Tooltip"))

                    if config.useImage {
                        BackgroundMediaThumb(
                            bookmark: config.imageBookmark,
                            mediaType: config.mediaTypeRaw,
                            opacity: config.opacity
                        )
                    }
                }
            }
        } label: {
            Label(PresentationManager.contentKeyLabel(key), systemImage: key == "bible" ? "book.closed.fill" : (key == "song" ? "music.note" : "rectangle.stack"))
                .font(.caption.bold())
        }
    }

    // MARK: Tranziții Tab (per-presenter enter / between-slides / exit effects)
    // Selecting any effect (or pressing play) demos it live on the canvas.

    @ViewBuilder
    private var presenterTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    // Intrare = transparență → conținut (prima afișare)
                    transitionRow(
                        label: String(localized: "Intrare:", comment: "Setting label"),
                        help: String(localized: "Efectul cu care textul APARE pe ecran — de la transparență la conținut", comment: "Tooltip"),
                        get: { pm.transitionInRaw() },
                        set: { pm.setTransitionIn($0) }
                    )
                    phaseDurationSlider(phase: "appear")

                    Divider()

                    transitionRow(
                        label: String(localized: "Intermediar:", comment: "Setting label"),
                        help: String(localized: "Efectul ÎNTRE slide-uri (verset → verset, strofă → strofă)", comment: "Tooltip"),
                        get: { pm.transitionChangeRaw() },
                        set: { pm.setTransitionChange($0) }
                    )
                    phaseDurationSlider(phase: "change")

                    Divider()

                    // Ieșire = conținut → transparență (Hide / Clear / ESC)
                    transitionRow(
                        label: String(localized: "Ieșire:", comment: "Setting label"),
                        help: String(localized: "Efectul cu care textul DISPARE — de la conținut la transparență (Hide, Clear, ESC)", comment: "Tooltip"),
                        get: { pm.transitionOutRaw() },
                        set: { pm.setTransitionOut($0) }
                    )
                    phaseDurationSlider(phase: "clear")
                }
            } label: {
                Label(String(localized: "Global", comment: "Inspector group"), systemImage: "wand.and.stars")
                    .font(.caption.bold())
            }

            // Per-casete override — General → Personalizează, like text styles.
            if let selection {
                boxTransitionGroup(selection)
            } else {
                Text(String(localized: "Selectează o casetă pentru a-i personaliza tranziția.", comment: "Inspector hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(String(
                localized: "Tranziții pentru \(PresentationManager.contentKeyLabel(pm.activeProfileKey)) — alege un efect și îl vezi imediat pe canvas.",
                comment: "Inspector hint"
            ))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
    }

    /// Direct duration slider per phase: 0.0 = instant, up to 3 s.
    @ViewBuilder
    private func phaseDurationSlider(phase: String) -> some View {
        labeledRow(String(localized: "Durată:", comment: "Setting label")) {
            Slider(
                value: Binding(
                    get: { pm.resolvedTransitionDuration(phase: phase) },
                    set: { pm.setPhaseDurationOverride($0, phase) }
                ),
                in: 0...3
            )
            .controlSize(.small)
            Text(String(format: "%.2fs", pm.resolvedTransitionDuration(phase: phase)))
                .font(.caption.monospacedDigit())
                .frame(width: 42)
        }
        .help(String(localized: "Durata acestei tranziții — 0 = instant", comment: "Tooltip"))
    }

    /// The selected box's own transition: effects, delay (stagger) and duration.
    @ViewBuilder
    private func boxTransitionGroup(_ identity: BoxIdentity) -> some View {
        let token = boxToken(for: identity)
        let override = Binding(
            get: { pm.boxTransitionOverride(forToken: token) },
            set: { pm.setBoxTransitionOverride($0, forToken: token) }
        )

        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { override.wrappedValue.isCustomized },
                    set: { override.wrappedValue.isCustomized = $0 }
                )) {
                    Text(String(localized: "Personalizează tranziția", comment: "Customize toggle"))
                        .font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(String(localized: "Dezactivat = caseta urmează tranzițiile generale ale prezentatorului", comment: "Tooltip"))

                if override.wrappedValue.isCustomized {
                    Divider()

                    boxTransitionPicker(
                        label: String(localized: "Intrare:", comment: "Setting label"),
                        raw: Binding(get: { override.wrappedValue.inRaw }, set: { override.wrappedValue.inRaw = $0 }),
                        fallback: pm.transitionInRaw()
                    )
                    boxTransitionPicker(
                        label: String(localized: "Intermediar:", comment: "Setting label"),
                        raw: Binding(get: { override.wrappedValue.changeRaw }, set: { override.wrappedValue.changeRaw = $0 }),
                        fallback: pm.transitionChangeRaw()
                    )
                    boxTransitionPicker(
                        label: String(localized: "Ieșire:", comment: "Setting label"),
                        raw: Binding(get: { override.wrappedValue.outRaw }, set: { override.wrappedValue.outRaw = $0 }),
                        fallback: pm.transitionOutRaw()
                    )

                    labeledRow(String(localized: "Întârziere:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { override.wrappedValue.delay },
                                set: { override.wrappedValue.delay = $0 }
                            ),
                            in: 0...3
                        )
                        .controlSize(.small)
                        Text(String(format: "%.2fs", override.wrappedValue.delay))
                            .font(.caption.monospacedDigit())
                            .frame(width: 42)
                    }
                    .help(String(localized: "Întârzie tranziția acestei casete față de celelalte — efect în cascadă (titlul intră primul, versurile după)", comment: "Tooltip"))

                    labeledRow(String(localized: "Durată:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: {
                                    override.wrappedValue.duration >= 0
                                        ? override.wrappedValue.duration
                                        : pm.resolvedTransitionDuration(phase: "appear")
                                },
                                set: { override.wrappedValue.duration = $0 }
                            ),
                            in: 0...3
                        )
                        .controlSize(.small)
                        Text(String(format: "%.2fs",
                                    override.wrappedValue.duration >= 0
                                        ? override.wrappedValue.duration
                                        : pm.resolvedTransitionDuration(phase: "appear")))
                            .font(.caption.monospacedDigit())
                            .frame(width: 42)
                    }
                    .help(String(localized: "Durata tranziției acestei casete — 0 = instant", comment: "Tooltip"))
                }
            }
        } label: {
            Label(boxLabel(for: identity, pm: pm), systemImage: "wand.and.rays")
                .font(.caption.bold())
        }
    }

    /// Effect picker with a Global option + canvas demo on change.
    @ViewBuilder
    private func boxTransitionPicker(label: String, raw: Binding<String>, fallback: String) -> some View {
        labeledRow(label) {
            Picker("", selection: Binding(
                get: { raw.wrappedValue },
                set: { newRaw in
                    raw.wrappedValue = newRaw
                    playTransitionPreview(newRaw.isEmpty ? fallback : newRaw)
                }
            )) {
                Text(String(localized: "Global", comment: "Transition option")).tag("")
                Divider()
                ForEach(PresentationManager.transitionOptions, id: \.raw) { option in
                    Text(option.label).tag(option.raw)
                }
            }
            .labelsHidden()
            .controlSize(.small)

            Button {
                playTransitionPreview(raw.wrappedValue.isEmpty ? fallback : raw.wrappedValue)
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(String(localized: "Previzualizează efectul pe canvas", comment: "Tooltip"))
        }
    }

    /// One transition picker row with a play button that demos the effect.
    @ViewBuilder
    private func transitionRow(
        label: String, help: String,
        get: @escaping () -> String, set: @escaping (String) -> Void
    ) -> some View {
        labeledRow(label) {
            Picker("", selection: Binding(
                get: get,
                set: { raw in
                    set(raw)
                    playTransitionPreview(raw)
                }
            )) {
                ForEach(PresentationManager.transitionOptions, id: \.raw) { option in
                    Text(option.label).tag(option.raw)
                }
            }
            .labelsHidden()
            .controlSize(.small)

            Button {
                playTransitionPreview(get())
            } label: {
                Image(systemName: "play.circle")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help(String(localized: "Previzualizează efectul pe canvas", comment: "Tooltip"))
        }
        .help(help)
    }

    /// Replays the sample content on the canvas with the given effect: the
    /// content is torn down and re-inserted so the transition actually runs.
    private func playTransitionPreview(_ raw: String) {
        transitionPreviewRaw = raw
        // Commit the new transition to the view tree FIRST, then animate the
        // identity change — otherwise the removal still uses the old effect.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: max(pm.resolvedTransitionDuration(phase: "appear"), 0.25))) {
                transitionPreviewTick += 1
            }
        }
    }

    // MARK: Shared inspector helpers

    @ViewBuilder
    private func labeledRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .frame(width: 62, alignment: .trailing)
            content()
        }
    }

    private func selectBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            pm.setBackgroundMedia(from: url)
        }
    }
}

// MARK: - Box Frame Numeric Fields

/// Compact X / Y / W / H fields (in % of screen) for one box.
struct BoxFrameFields: View {
    @Environment(PresentationManager.self) private var pm
    let identity: BoxIdentity

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                percentField(String(localized: "X", comment: "Box position field"), keyPath: \.x,
                             help: String(localized: "Poziția orizontală (% din lățimea ecranului)", comment: "Tooltip"))
                percentField(String(localized: "Y", comment: "Box position field"), keyPath: \.y,
                             help: String(localized: "Poziția verticală (% din înălțimea ecranului)", comment: "Tooltip"))
            }
            GridRow {
                percentField(String(localized: "W", comment: "Box size field"), keyPath: \.width,
                             help: String(localized: "Lățimea casetei (% din ecran)", comment: "Tooltip"))
                percentField(String(localized: "H", comment: "Box size field"), keyPath: \.height,
                             help: String(localized: "Înălțimea casetei (% din ecran)", comment: "Tooltip"))
            }
        }
    }

    @ViewBuilder
    private func percentField(
        _ label: String,
        keyPath: WritableKeyPath<PresentationManager.TextBoxFrame, Double>,
        help: String
    ) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            TextField(
                "",
                value: Binding(
                    get: { (pm.boxFrame(for: identity)[keyPath: keyPath] * 100).rounded() },
                    set: { newValue in
                        var frame = pm.boxFrame(for: identity)
                        frame[keyPath: keyPath] = newValue / 100
                        pm.setBoxFrame(frame, for: identity)
                    }
                ),
                format: .number.precision(.fractionLength(0))
            )
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(width: 44)
            Stepper(
                "",
                value: Binding(
                    get: { pm.boxFrame(for: identity)[keyPath: keyPath] * 100 },
                    set: { newValue in
                        var frame = pm.boxFrame(for: identity)
                        frame[keyPath: keyPath] = newValue / 100
                        pm.setBoxFrame(frame, for: identity)
                    }
                ),
                in: 0...100, step: 1
            )
            .labelsHidden()
            .controlSize(.small)
            Text("%")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .help(help)
    }
}

#Preview {
    LayoutEditorSheet()
        .environment(PresentationManager())
        .environment(LibraryManager())
}
