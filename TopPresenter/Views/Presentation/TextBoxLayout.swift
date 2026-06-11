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

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verseContent: return String(localized: "Conținut Verset", comment: "Text box name")
        case .reference: return String(localized: "Referință / Titlu", comment: "Text box name")
        case .translationName: return String(localized: "Traducere", comment: "Text box name — Bible translation name")
        case .subtitle: return String(localized: "Subtitlu", comment: "Text box name — verse label / subtitle")
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
        }
    }

    var icon: String {
        switch self {
        case .verseContent: return "text.quote"
        case .reference: return "bookmark.fill"
        case .translationName: return "character.book.closed.fill"
        case .subtitle: return "text.line.last.and.arrowtriangle.forward"
        }
    }

    var boxColor: Color {
        switch self {
        case .verseContent: return .cyan
        case .reference: return .orange
        case .translationName: return .purple
        case .subtitle: return .green
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

func boxColor(for identity: BoxIdentity) -> Color {
    switch identity {
    case .section(let section): return section.boxColor
    case .custom: return .mint
    case .media: return .pink
    }
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
        return section.label
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
        return raw == "auto" ? section.sourceDescription : PresentationManager.sourceOptionLabel(raw)
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
    /// Show the translation box (only meaningful for Bible content).
    var showsBibleBoxes: Bool = true
    /// When false (preview card), hidden boxes are not drawn at all — no dashed
    /// border ghosts in the previewer. The editor keeps them visible for editing.
    var showsHiddenBoxes: Bool = true
    /// Optional selection — the Layout Editor binds this; the preview card doesn't.
    var selection: Binding<BoxIdentity?> = .constant(nil)

    /// Stable coordinate space for drag math — translations measured here don't
    /// feed back into the gesture when the box moves under the cursor (no jitter).
    static let canvasSpace = "textBoxEditCanvas"

    private var identities: [BoxIdentity] {
        var result = pm.orderedBoxTokens().compactMap { boxIdentity(fromToken: $0) }
        if !showsBibleBoxes {
            result.removeAll { $0 == .section(.translationName) }
        }
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
        let color = boxColor(for: identity)

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
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(boxColor(for: identity), lineWidth: 1.5))
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

    private var visibleThemes: [PresentationManager.Theme] {
        pm.themes(forFormat: format)
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
                Text(String(localized: "Nicio temă încă — apasă + pentru a salva aspectul curent.", comment: "Theme gallery empty state"))
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
        panel.message = String(localized: "Alege pachete .tptheme de importat", comment: "Import panel message")
        if panel.runModal() == .OK {
            for url in panel.urls {
                _ = try? pm.importTheme(from: url)
            }
        }
    }
}

/// One theme card: background thumbnail + miniature layout sketch + name.
private struct ThemeCard: View {
    @Environment(PresentationManager.self) private var pm

    let theme: PresentationManager.Theme
    let isActive: Bool
    let onRename: () -> Void

    @State private var thumbnail: NSImage?

    private var payload: PresentationManager.ThemePayload { theme.payload }

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
                        ForEach(TextBoxSection.allCases) { section in
                            if payload.visibility[section.rawValue] ?? true {
                                let frame = payload.frames[section.rawValue] ?? PresentationManager.TextBoxFrame.defaultVerse
                                let rect = frame.rect(in: geo.size)
                                if section == .verseContent {
                                    Text("Aa")
                                        .font(.system(size: max(rect.height * 0.42, 7), weight: .semibold))
                                        .foregroundStyle(
                                            (Color(hex: payload.styles[section.rawValue]?.colorHex ?? "") ?? (Color(hex: payload.textColorHex) ?? .white))
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
            pm.applyTheme(id: theme.id)
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
    /// Quick-align toggle memory: pressing the same action again restores the
    /// frame from before the action was applied.
    @State private var quickActionMemory: [BoxIdentity: [String: PresentationManager.TextBoxFrame]] = [:]
    @State private var availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()
    @State private var renameTarget: BoxIdentity?
    @State private var renameText = ""

    private enum EditorTab: String, CaseIterable, Identifiable {
        case layout, text, background, output

        var id: String { rawValue }

        var title: String {
            switch self {
            case .layout: return String(localized: "Layout", comment: "Editor tab")
            case .text: return String(localized: "Text", comment: "Editor tab")
            case .background: return String(localized: "Fundal", comment: "Editor tab")
            case .output: return String(localized: "Ieșire", comment: "Editor tab")
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
            quickActionsBar
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
        HStack {
            Label(
                String(localized: "Editor de Teme", comment: "Theme editor title"),
                systemImage: "paintbrush.pointed.fill"
            )
            .font(.headline)

            ThemeMenuControl()
                .padding(.leading, 8)

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

    private var quickActionsBar: some View {
        HStack(spacing: 10) {
            Button {
                let box = pm.addCustomTextBox()
                selection = .custom(box.id)
                activeTab = .layout
            } label: {
                Label(
                    String(localized: "Casetă Text", comment: "Add text box button"),
                    systemImage: "plus.rectangle"
                )
            }
            .buttonStyle(.bordered)
            .help(String(localized: "Adaugă o casetă de text nouă (text static sau sursă live)", comment: "Tooltip"))

            Button {
                addMediaFromPanel()
            } label: {
                Label(
                    String(localized: "Casetă Media", comment: "Add media box button"),
                    systemImage: "photo.badge.plus"
                )
            }
            .buttonStyle(.bordered)
            .help(String(localized: "Adaugă o imagine, un GIF sau un video (logo, decor…)", comment: "Tooltip"))

            Divider().frame(height: 16)

            // Quick-align toggles for the selected box — press again to undo
            Group {
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

                Button {
                    if let selection {
                        pm.resetBox(for: selection)
                        quickActionMemory[selection] = nil
                    }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help(String(localized: "Resetează caseta la poziția implicită", comment: "Quick align tooltip"))
            }
            .buttonStyle(.bordered)
            .disabled(selection == nil)

            Spacer()

            if let selection {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(boxColor(for: selection).opacity(0.8))
                        .frame(width: 10, height: 10)
                    Text(boxLabel(for: selection, pm: pm))
                        .font(.caption.bold())
                }
                .foregroundStyle(.secondary)
                .help(boxSourceDescription(for: selection, pm: pm))
            }

            Button(String(localized: "Resetează Layout", comment: "Reset layout button"), role: .destructive) {
                pm.resetAllBoxFrames()
                quickActionMemory = [:]
            }
            .buttonStyle(.bordered)
            .help(String(localized: "Readuce toate casetele la pozițiile implicite", comment: "Tooltip"))
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                        let bg = pm.activeBackground(for: pm.liveContent.contentType, frozen: false)
                        if bg.showColor {
                            bg.color
                        }
                        if bg.useMedia {
                            BackgroundMediaView(background: bg, plays: true)
                                .frame(width: size.width, height: size.height)
                                .clipped()
                        }

                        // Content + media rendered in the unified stacking order
                        sampleContent(size: size)

                        // Interactive box overlay — always on in the editor
                        TextBoxEditOverlay(canvasSize: size, showsBibleBoxes: true, showsHiddenBoxes: false, selection: $selection)
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

    private var sampleVerse: String {
        if pm.liveContent.isLive, !pm.liveContent.mainText.isEmpty {
            return pm.liveContent.mainText
        }
        if !libraryManager.selectedVerses.isEmpty {
            return libraryManager.selectedVersesText
        }
        return String(localized: "Fiindcă atât de mult a iubit Dumnezeu lumea, că a dat pe singurul Lui Fiu, pentru ca oricine crede în El să nu piară, ci să aibă viața veșnică.", comment: "Layout editor sample verse")
    }

    private var sampleReference: String {
        if pm.liveContent.isLive, !pm.liveContent.reference.isEmpty {
            return pm.liveContent.reference
        }
        if !libraryManager.selectedVerses.isEmpty {
            return libraryManager.selectedVersesReference
        }
        return String(localized: "Ioan 3:16", comment: "Layout editor sample reference")
    }

    private var sampleTranslation: String {
        pm.liveContent.translationName.isEmpty
            ? (libraryManager.selectedBibleModule?.abbreviation ?? "VDC")
            : pm.liveContent.translationName
    }

    private var sampleSubtitle: String {
        pm.liveContent.subtitle.isEmpty
            ? String(localized: "Strofa 1", comment: "Layout editor sample subtitle")
            : pm.liveContent.subtitle
    }

    @ViewBuilder
    private func sampleContent(size: CGSize) -> some View {
        let targetScale = pm.targetFontScale
        let canvasScale = size.width / max(metrics.points.width, 1)
        let fontScale = targetScale * canvasScale
        let scaledPadding = pm.padding * fontScale

        ZStack(alignment: .topLeading) {
            // Unified stacking order — exactly what the output renders
            ForEach(pm.orderedBoxTokens(), id: \.self) { token in
                switch boxIdentity(fromToken: token) {
                case .section(let section):
                    if pm.isSectionVisible(section) {
                        let text = pm.sectionText(
                            section,
                            main: sampleVerse, reference: sampleReference,
                            translation: sampleTranslation, subtitle: sampleSubtitle
                        )
                        if !text.isEmpty {
                            let rect = pm.boxFrame(for: section).rect(in: size)
                            let style = pm.resolvedStyle(for: section)
                            let fitted: CGFloat? = (section == .verseContent)
                                ? pm.fittedVerseFontSize(
                                    text: text,
                                    boxSize: pm.boxFrame(for: section).rect(in: metrics.points).size,
                                    maxSize: CGFloat(style.fontSize) * targetScale,
                                    padding: pm.padding * targetScale,
                                    fontName: style.fontName,
                                    lineSpacing: style.lineSpacing
                                  ) * canvasScale
                                : nil
                            sampleBoxText(text, style: style, rect: rect, fontScale: fontScale, scaledPadding: scaledPadding, fittedSize: fitted)
                        }
                    }
                case .custom(let id):
                    if let box = pm.customTextBox(id: id), box.isVisible {
                        let resolved = box.resolvedText(
                            main: sampleVerse, reference: sampleReference,
                            translation: sampleTranslation, subtitle: sampleSubtitle
                        )
                        let text = resolved.isEmpty ? box.sourceLabel : resolved
                        let rect = box.frame.rect(in: size)
                        let style = pm.resolvedCustomStyle(box)
                        sampleBoxText(text, style: style, rect: rect, fontScale: fontScale, scaledPadding: scaledPadding, fittedSize: nil)
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

    @ViewBuilder
    private func sampleBoxText(
        _ text: String,
        style: PresentationManager.ResolvedBoxStyle,
        rect: CGRect, fontScale: CGFloat, scaledPadding: CGFloat,
        fittedSize: CGFloat?
    ) -> some View {
        let size = fittedSize ?? CGFloat(style.fontSize) * fontScale
        Text(text)
            .font(style.font(at: size))
            .foregroundStyle(style.color.opacity(style.opacity))
            .multilineTextAlignment(style.hAlign)
            .lineSpacing(style.lineSpacing * size * 0.1)
            .minimumScaleFactor(fittedSize == nil ? 0.2 : 1.0)
            .padding(.horizontal, scaledPadding)
            .frame(width: rect.width, height: rect.height, alignment: style.frameAlignment)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    // MARK: Inspector

    private var inspector: some View {
        VStack(spacing: 0) {
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
                case .output:
                    outputTab
                }
            }
        }
    }

    // MARK: Layout Tab

    @ViewBuilder
    private var layoutTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                VStack(spacing: 2) {
                    // Unified stacking order — first row = on top of the screen.
                    // Drag any row to reorder; right-click for layer actions.
                    ForEach(pm.orderedBoxTokens().reversed(), id: \.self) { token in
                        if let identity = boxIdentity(fromToken: token) {
                            boxListRow(identity: identity)
                        }
                    }

                    HStack(spacing: 6) {
                        Button {
                            let box = pm.addCustomTextBox()
                            selection = .custom(box.id)
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

            if let selection {
                selectedBoxDetail(for: selection)
            } else {
                Text(String(localized: "Selectează o casetă din listă sau de pe canvas.", comment: "Inspector hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
        let canDelete: Bool = {
            if case .section(let section) = identity {
                // Translation & subtitle are optional decorations — the side
                // button "removes" them (hides; built-ins can't be deleted)
                return section == .translationName || section == .subtitle
            }
            return true
        }()

        let row = HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .help(String(localized: "Trage pentru a reordona (primul = deasupra pe ecran)", comment: "Tooltip"))
            RoundedRectangle(cornerRadius: 2)
                .fill(boxColor(for: identity).opacity(0.8))
                .frame(width: 10, height: 10)
            Text(boxLabel(for: identity, pm: pm))
                .font(.caption)
                .lineLimit(1)
            Spacer()

            Button {
                pm.toggleBoxVisibility(identity)
            } label: {
                Image(systemName: isVisible ? "eye" : "eye.slash")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Afișează / ascunde caseta", comment: "Tooltip"))

            if canDelete {
                Button(role: .destructive) {
                    removeOrHide(identity)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
                .help({
                    if case .section = identity {
                        return String(localized: "Elimină caseta (o poți reactiva cu ochiul)", comment: "Tooltip")
                    }
                    return String(localized: "Șterge caseta", comment: "Tooltip")
                }())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            isSelected ? Color.accentColor.opacity(0.15) : Color.clear,
            in: RoundedRectangle(cornerRadius: 5)
        )
        .contentShape(Rectangle())
        .onTapGesture { selection = identity }
        .help(boxSourceDescription(for: identity, pm: pm))
        .opacity(isVisible ? 1.0 : 0.55)
        .contextMenu { listRowMenu(identity: identity) }

        // EVERY row is draggable — list order = unified z-order
        row
            .draggable(boxToken(for: identity))
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

        if case .custom = identity {
            Divider()
            Button(role: .destructive) {
                removeOrHide(identity)
            } label: {
                Label(String(localized: "Șterge", comment: "Context menu"), systemImage: "trash")
            }
        }
        if case .media = identity {
            Divider()
            Button(role: .destructive) {
                removeOrHide(identity)
            } label: {
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
            }
        } label: {
            Label(String(localized: "Poziție și Dimensiune", comment: "Inspector group"), systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.caption.bold())
        }

        switch identity {
        case .section(let section):
            sectionContentGroup(section)
            textStyleGroup(
                style: Binding(
                    get: { pm.boxStyle(for: section) },
                    set: { pm.setBoxStyle($0, for: section) }
                ),
                onEnable: { pm.enableStyleCustomization(for: section) }
            )
        case .custom(let id):
            if let box = pm.customTextBox(id: id) {
                customContentGroup(box)
                textStyleGroup(
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
        case .media(let id):
            if let box = pm.mediaBox(id: id) {
                mediaFileGroup(box)
                mediaAspectGroup(box)
                mediaBehaviorGroup(box)
            }
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
                        Text(String(localized: "Text verset (live)", comment: "Box source option")).tag("mainText")
                        Text(String(localized: "Referință (live)", comment: "Box source option")).tag("reference")
                        Text(String(localized: "Traducere (live)", comment: "Box source option")).tag("translation")
                        Text(String(localized: "Subtitlu (live)", comment: "Box source option")).tag("subtitle")
                        Divider()
                        Text(String(localized: "Text static", comment: "Box source option")).tag("static")
                        Text(String(localized: "Data curentă", comment: "Box source option")).tag("date")
                        Text(String(localized: "Ora curentă", comment: "Box source option")).tag("time")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "De unde vine conținutul casetei — Implicit = câmpul ei natural", comment: "Tooltip"))

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
                        Text(String(localized: "Text verset (live)", comment: "Box source option")).tag("mainText")
                        Text(String(localized: "Referință (live)", comment: "Box source option")).tag("reference")
                        Text(String(localized: "Traducere (live)", comment: "Box source option")).tag("translation")
                        Text(String(localized: "Subtitlu (live)", comment: "Box source option")).tag("subtitle")
                        Divider()
                        Text(String(localized: "Data curentă", comment: "Box source option")).tag("date")
                        Text(String(localized: "Ora curentă", comment: "Box source option")).tag("time")
                    }
                    .labelsHidden()
                    .controlSize(.small)
                }
                .help(String(localized: "De unde vine textul: scris de tine sau preluat live", comment: "Tooltip"))

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
                            in: 8...220, step: 2
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

                    labeledRow(String(localized: "Spațiere:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { style.wrappedValue.lineSpacing },
                                set: { style.wrappedValue.lineSpacing = $0 }
                            ),
                            in: -1...20, step: 0.5
                        )
                        .controlSize(.small)
                        Text(style.wrappedValue.lineSpacing >= 0 ? String(format: "%.1f", style.wrappedValue.lineSpacing) : String(localized: "Global", comment: "Value label"))
                            .font(.caption.monospacedDigit())
                            .frame(width: 42)
                    }
                    .help(String(localized: "Spațierea dintre rânduri — Global = setarea generală", comment: "Tooltip"))

                    labeledRow(String(localized: "Opacitate:", comment: "Setting label")) {
                        Slider(
                            value: Binding(
                                get: { style.wrappedValue.opacity },
                                set: { style.wrappedValue.opacity = $0 }
                            ),
                            in: 0.05...1.0, step: 0.05
                        )
                        .controlSize(.small)
                        Text("\(Int(style.wrappedValue.opacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 35)
                    }
                }
            }
        } label: {
            Label(String(localized: "Text", comment: "Inspector group"), systemImage: "textformat")
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
                        Spacer()
                        Picker("", selection: pmBinding.textAlignment) {
                            Image(systemName: "text.alignleft").tag(TextAlignment.leading)
                            Image(systemName: "text.aligncenter").tag(TextAlignment.center)
                            Image(systemName: "text.alignright").tag(TextAlignment.trailing)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .frame(width: 100)
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
                        Slider(value: pmBinding.globalTextOpacity, in: 0.05...1.0, step: 0.05)
                            .controlSize(.small)
                        Text("\(Int(pm.globalTextOpacity * 100))%")
                            .font(.caption.monospacedDigit())
                            .frame(width: 35)
                    }
                    .help(String(localized: "Opacitatea de bază a textului — se combină cu opacitatea fiecărei casete", comment: "Tooltip"))

                    labeledRow(String(localized: "Spațiere:", comment: "Setting label")) {
                        Slider(value: pmBinding.lineSpacing, in: 0.8...3.0, step: 0.1)
                            .controlSize(.small)
                        Text(String(format: "%.1f", pm.lineSpacing))
                            .font(.caption.monospacedDigit())
                            .frame(width: 28)
                    }

                    labeledRow(String(localized: "Padding:", comment: "Setting label")) {
                        Slider(value: pmBinding.padding, in: 10...100, step: 5)
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
                            Slider(value: pmBinding.shadowRadius, in: 0...20, step: 0.5)
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
            } label: {
                Label(String(localized: "Text Global", comment: "Inspector group"), systemImage: "textformat")
                    .font(.caption.bold())
            }

            Text(String(localized: "Stilul individual al fiecărei casete se editează în tab-ul Layout: selectează caseta și activează „Personalizează textul”.", comment: "Inspector hint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
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

            // Per-content overrides — only the one relevant to the module you're
            // in (Bible module → just the Biblie override), all three otherwise.
            ForEach(relevantBackgroundKeys, id: \.self) { key in
                contentBackgroundGroup(key: key)
            }
        }
        .padding(12)
    }

    /// Which per-presenter background overrides to show, based on the module
    /// the editor was opened from.
    private var relevantBackgroundKeys: [String] {
        switch appState.selectedSidebarItem {
        case .bible: return ["bible"]
        case .songs: return ["song"]
        case .customSlides: return ["text"]
        default: return ["bible", "song", "text"]
        }
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

    // MARK: Output Tab

    @ViewBuilder
    private var outputTab: some View {
        let pmBinding = Bindable(pm)

        VStack(alignment: .leading, spacing: 10) {
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    labeledRow(String(localized: "Ecran:", comment: "Setting label")) {
                        Picker("", selection: pmBinding.presentationScreenIndex) {
                            Text(String(localized: "Auto", comment: "Picker option"))
                                .tag(nil as Int?)
                            ForEach(Array(pm.availableScreens.enumerated()), id: \.offset) { index, screen in
                                Text(screen.localizedName).tag(index as Int?)
                            }
                        }
                        .labelsHidden()
                        .controlSize(.small)

                        Button {
                            pm.refreshScreens()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "Reîmprospătează lista de ecrane", comment: "Button tooltip"))
                    }
                    .help(String(localized: "Pe ce ecran se proiectează — Auto alege ecranul extern", comment: "Tooltip"))

                    labeledRow(String(localized: "Fereastră:", comment: "Setting label")) {
                        Picker("", selection: pmBinding.windowLevel) {
                            Text(String(localized: "Normal", comment: "Window level option")).tag("normal")
                            Text(String(localized: "Floating", comment: "Window level option")).tag("floating")
                            Text(String(localized: "Always on Top", comment: "Window level option")).tag("alwaysOnTop")
                            Text(String(localized: "Behind Desktop", comment: "Window level option")).tag("behindDesktop")
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Nivelul ferestrei de proiecție față de alte ferestre", comment: "Tooltip"))

                    labeledRow(String(localized: "Tranziție:", comment: "Setting label")) {
                        Slider(value: pmBinding.transitionDuration, in: 0...2, step: 0.1)
                            .controlSize(.small)
                        Text(String(format: "%.1fs", pm.transitionDuration))
                            .font(.caption.monospacedDigit())
                            .frame(width: 30)
                    }
                    .help(String(localized: "Durata tranziției între versete/slide-uri", comment: "Tooltip"))

                    labeledRow(String(localized: "Deconectare:", comment: "Setting label")) {
                        Picker("", selection: Binding(
                            get: { pm.screenDisconnectAction.rawValue },
                            set: { pm.screenDisconnectAction = PresentationManager.ScreenDisconnectAction(rawValue: $0) ?? .ask }
                        )) {
                            Text(String(localized: "Întreabă", comment: "Disconnect option")).tag("ask")
                            Text(String(localized: "Mută pe alt ecran", comment: "Disconnect option")).tag("moveToAvailable")
                            Text(String(localized: "Ecran negru", comment: "Disconnect option")).tag("goBlack")
                            Text(String(localized: "Nu face nimic", comment: "Disconnect option")).tag("doNothing")
                        }
                        .labelsHidden()
                        .controlSize(.small)
                    }
                    .help(String(localized: "Ce se întâmplă dacă ecranul de proiecție se deconectează", comment: "Tooltip"))
                }
            } label: {
                Label(String(localized: "Ecran de Proiecție", comment: "Inspector group"), systemImage: "display")
                    .font(.caption.bold())
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Layout-ul se adaptează automat la orice rezoluție, raport de aspect sau PPI: casetele sunt definite procentual, iar fonturile se scalează față de o înălțime de referință de 1080p.", comment: "Adaptive layout explanation"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    let m = pm.targetScreenMetrics
                    HStack(spacing: 6) {
                        Image(systemName: "display")
                            .font(.caption2)
                        Text("\(Int(m.resolution.width))×\(Int(m.resolution.height))")
                            .font(.caption2.monospacedDigit())
                        Text("•")
                        Text(m.aspectRatioLabel)
                            .font(.caption2.bold())
                        Text("•")
                        Text("\(Int(m.ppi)) PPI")
                            .font(.caption2.monospacedDigit())
                        Text("•")
                        Text(String(format: "×%.2f font", pm.targetFontScale))
                            .font(.caption2.monospacedDigit())
                    }
                    .foregroundStyle(.secondary)
                }
            } label: {
                Label(String(localized: "Adaptare Automată", comment: "Inspector group"), systemImage: "arrow.up.left.and.down.right.magnifyingglass")
                    .font(.caption.bold())
            }
        }
        .padding(12)
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
