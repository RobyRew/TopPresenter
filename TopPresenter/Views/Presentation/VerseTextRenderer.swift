//
//  VerseTextRenderer.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 05/04/2026.
//

import SwiftUI
import AppKit

// MARK: - Text Box Section

/// Identifies which section (text box) a renderer targets.
enum TextBoxSection: String, CaseIterable, Identifiable {
    case verseContent = "verseContent"
    case reference = "reference"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .verseContent: return String(localized: "Conținut Verset", comment: "Edit mode tab")
        case .reference: return String(localized: "Referință / Titlu", comment: "Edit mode tab")
        }
    }

    var icon: String {
        switch self {
        case .verseContent: return "text.quote"
        case .reference: return "bookmark.fill"
        }
    }

    var boxColor: Color {
        switch self {
        case .verseContent: return .cyan
        case .reference: return .orange
        }
    }
}

// MARK: - VerseTextRenderer

/// A custom `TextRenderer` that draws a single bounding box around the ENTIRE
/// text content — not per-line or per-run. In edit mode, it draws:
/// - A rounded rect around the full text block
/// - Corner handles for visual reference
/// - An optional section label
struct VerseTextRenderer: TextRenderer {

    /// When `false`, the renderer is a passthrough (draws text normally, no debug overlays).
    var isEditMode: Bool = false

    /// Which text box section this renderer targets.
    var section: TextBoxSection = .verseContent

    /// Multiplies the resolved font size for quick optical scaling.
    var fontSizeMultiplier: CGFloat = 1.0

    /// An additive offset applied to the entire text block before drawing.
    var alignmentOffset: CGSize = .zero

    /// Opacity control for the text within this section.
    var textOpacity: CGFloat = 1.0

    // MARK: - TextRenderer conformance

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        var ctx = context
        ctx.translateBy(x: alignmentOffset.width, y: alignmentOffset.height)

        if fontSizeMultiplier != 1.0 {
            ctx.scaleBy(x: fontSizeMultiplier, y: fontSizeMultiplier)
        }

        // Draw debug overlay BEHIND text when edit mode is on
        if isEditMode {
            drawTextBoxOverlay(layout: layout, in: &ctx)
        }

        // Draw the actual text
        ctx.opacity = textOpacity
        for line in layout {
            ctx.draw(line)
        }
    }

    // MARK: - Full Text Box Overlay

    /// Computes the union bounding rect of ALL lines, then draws a single box around the entire text.
    private func drawTextBoxOverlay(layout: Text.Layout, in context: inout GraphicsContext) {
        var unionRect: CGRect? = nil

        for line in layout {
            let tb = line.typographicBounds
            let lineRect = CGRect(
                x: tb.origin.x,
                y: tb.origin.y - tb.ascent,
                width: tb.width,
                height: tb.ascent + tb.descent + tb.leading
            )
            if let existing = unionRect {
                unionRect = existing.union(lineRect)
            } else {
                unionRect = lineRect
            }
        }

        guard let fullRect = unionRect else { return }

        // Expand slightly for visual breathing room
        let boxRect = fullRect.insetBy(dx: -4, dy: -3)
        let cornerRadius: CGFloat = 4
        let boxColor = section.boxColor

        // Fill: very faint tint
        context.fill(
            Path(roundedRect: boxRect, cornerRadius: cornerRadius),
            with: .color(boxColor.opacity(0.06))
        )

        // Stroke: section-colored border
        context.stroke(
            Path(roundedRect: boxRect, cornerRadius: cornerRadius),
            with: .color(boxColor.opacity(0.5)),
            lineWidth: 1.5
        )

        // Corner handles (small squares at each corner)
        let handleSize: CGFloat = 5
        let corners = [
            CGPoint(x: boxRect.minX, y: boxRect.minY),
            CGPoint(x: boxRect.maxX, y: boxRect.minY),
            CGPoint(x: boxRect.minX, y: boxRect.maxY),
            CGPoint(x: boxRect.maxX, y: boxRect.maxY),
        ]
        for corner in corners {
            let handleRect = CGRect(
                x: corner.x - handleSize / 2,
                y: corner.y - handleSize / 2,
                width: handleSize,
                height: handleSize
            )
            context.fill(Path(handleRect), with: .color(boxColor.opacity(0.7)))
        }

        // Section label at top-left
        let labelText = Text(section.label)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(boxColor)
        context.draw(
            context.resolve(labelText),
            at: CGPoint(x: boxRect.minX + 2, y: boxRect.minY - 12),
            anchor: .topLeading
        )

        // Dimensions label at bottom-right
        let dimsText = Text("\(Int(fullRect.width))×\(Int(fullRect.height))")
            .font(.system(size: 7, weight: .medium, design: .monospaced))
            .foregroundStyle(boxColor.opacity(0.6))
        context.draw(
            context.resolve(dimsText),
            at: CGPoint(x: boxRect.maxX - 2, y: boxRect.maxY + 2),
            anchor: .topTrailing
        )
    }
}

// MARK: - Rendered Size Preference Key

struct RenderedTextSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Edit Mode Controls Section (Tabbed)

/// Inline controls shown in the preview panel when Edit Mode is active.
/// Two tabs: "Conținut Verset" (verse content box) and "Referință / Titlu" (reference box).
struct EditModeControlsSection: View {
    @Environment(PresentationManager.self) private var pm

    @State private var isExpanded: Bool = true
    @State private var selectedTab: TextBoxSection = .verseContent
    @State private var availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 10) {
                // Tab picker
                Picker("", selection: $selectedTab) {
                    ForEach(TextBoxSection.allCases) { section in
                        Label(section.label, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Tab content
                switch selectedTab {
                case .verseContent:
                    verseContentTab
                case .reference:
                    referenceTab
                }

                Divider()

                // Legend
                HStack(spacing: 12) {
                    ForEach(TextBoxSection.allCases) { section in
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(section.boxColor.opacity(0.7), lineWidth: 1.5)
                                .frame(width: 12, height: 8)
                            Text(section.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()

                // Reset all
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        // Verse section
                        pm.editVerseMultiplier = 1.0
                        pm.editVerseOffsetX = 0
                        pm.editVerseOffsetY = 0
                        pm.editVersePadding = 0
                        pm.editVerseOpacity = 1.0
                        pm.verseFontName = ""
                        pm.verseFontSizeOverride = 0
                        pm.verseTextColorHex = ""
                        pm.verseAlignmentRaw = ""
                        pm.verseLineSpacing = -1
                        // Reference section
                        pm.editRefMultiplier = 1.0
                        pm.editRefOffsetX = 0
                        pm.editRefOffsetY = 0
                        pm.editRefPadding = 0
                        pm.editRefOpacity = 1.0
                        pm.refFontName = ""
                        pm.refFontSizeOverride = 0
                        pm.refTextColorHex = ""
                        pm.refAlignmentRaw = ""
                        pm.refFontWeight = "semibold"
                    }
                } label: {
                    Label(
                        String(localized: "Resetează Tot", comment: "Edit mode button"),
                        systemImage: "arrow.counterclockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 8)
        } label: {
            Label {
                Text(String(localized: "Edit Mode", comment: "Section title"))
                    .font(.headline)
            } icon: {
                Image(systemName: "rectangle.dashed.badge.record")
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Verse Content Tab
    @ViewBuilder
    private var verseContentTab: some View {
        VStack(spacing: 8) {
            // -- Text Settings --
            sectionLabel(String(localized: "Text", comment: "Edit section"))

            // Font family override
            HStack(spacing: 6) {
                Text(String(localized: "Font:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { pm.verseFontName },
                    set: { pm.verseFontName = $0 }
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

            // Font size override
            HStack(spacing: 6) {
                Text(String(localized: "Size:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { pm.verseFontSizeOverride },
                        set: { pm.verseFontSizeOverride = $0 }
                    ),
                    in: 0...200, step: 2
                )
                .controlSize(.small)
                Text(pm.verseFontSizeOverride > 0 ? "\(Int(pm.verseFontSizeOverride)) pt" : String(localized: "Global", comment: "Value label"))
                    .font(.caption.monospacedDigit())
                    .frame(width: 45)
            }

            // Text color override
            HStack(spacing: 6) {
                Text(String(localized: "Color:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                ColorPicker("", selection: Binding(
                    get: { pm.resolvedVerseTextColor },
                    set: { pm.verseTextColorHex = $0.toHex() }
                ))
                .labelsHidden()
                .controlSize(.small)
                Spacer()
                Button(String(localized: "Global", comment: "Button")) {
                    pm.verseTextColorHex = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            // Alignment override
            HStack(spacing: 6) {
                Text(String(localized: "Align:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { pm.verseAlignmentRaw },
                    set: { pm.verseAlignmentRaw = $0 }
                )) {
                    Text(String(localized: "Global", comment: "Alignment option")).tag("")
                    Label(String(localized: "Left", comment: "Alignment"), systemImage: "text.alignleft").tag("leading")
                    Label(String(localized: "Center", comment: "Alignment"), systemImage: "text.aligncenter").tag("center")
                    Label(String(localized: "Right", comment: "Alignment"), systemImage: "text.alignright").tag("trailing")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            // Line spacing override
            HStack(spacing: 6) {
                Text(String(localized: "Spacing:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { pm.verseLineSpacing },
                        set: { pm.verseLineSpacing = $0 }
                    ),
                    in: -1...20, step: 0.5
                )
                .controlSize(.small)
                Text(pm.verseLineSpacing >= 0 ? String(format: "%.1f", pm.verseLineSpacing) : String(localized: "Global", comment: "Value label"))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)
            }

            Divider()

            // -- Position & Scale --
            sectionLabel(String(localized: "Position & Scale", comment: "Edit section"))

            editSlider(
                label: String(localized: "Scale", comment: "Edit slider"),
                value: Binding(get: { pm.editVerseMultiplier }, set: { pm.editVerseMultiplier = $0 }),
                range: 0.5...2.0, step: 0.05,
                format: "%.2f×"
            )

            editSlider(
                label: String(localized: "Offset X", comment: "Edit slider"),
                value: Binding(get: { pm.editVerseOffsetX }, set: { pm.editVerseOffsetX = $0 }),
                range: -300...300, step: 1,
                format: "%.0f px"
            )

            editSlider(
                label: String(localized: "Offset Y", comment: "Edit slider"),
                value: Binding(get: { pm.editVerseOffsetY }, set: { pm.editVerseOffsetY = $0 }),
                range: -300...300, step: 1,
                format: "%.0f px"
            )

            editSlider(
                label: String(localized: "Padding", comment: "Edit slider"),
                value: Binding(get: { pm.editVersePadding }, set: { pm.editVersePadding = $0 }),
                range: -50...100, step: 1,
                format: "%.0f px"
            )

            editSlider(
                label: String(localized: "Opacity", comment: "Edit slider"),
                value: Binding(get: { pm.editVerseOpacity }, set: { pm.editVerseOpacity = $0 }),
                range: 0.1...1.0, step: 0.05,
                format: "%.0f%%",
                displayMultiplier: 100
            )
        }
    }

    // MARK: - Reference Tab
    @ViewBuilder
    private var referenceTab: some View {
        VStack(spacing: 8) {
            // -- Text Settings --
            sectionLabel(String(localized: "Text", comment: "Edit section"))

            // Font family override
            HStack(spacing: 6) {
                Text(String(localized: "Font:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { pm.refFontName },
                    set: { pm.refFontName = $0 }
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

            // Font size override
            HStack(spacing: 6) {
                Text(String(localized: "Size:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Slider(
                    value: Binding(
                        get: { pm.refFontSizeOverride },
                        set: { pm.refFontSizeOverride = $0 }
                    ),
                    in: 0...150, step: 1
                )
                .controlSize(.small)
                Text(pm.refFontSizeOverride > 0 ? "\(Int(pm.refFontSizeOverride)) pt" : "55%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 40)
            }

            // Font weight
            HStack(spacing: 6) {
                Text(String(localized: "Weight:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { pm.refFontWeight },
                    set: { pm.refFontWeight = $0 }
                )) {
                    Text(String(localized: "Regular", comment: "Weight")).tag("regular")
                    Text(String(localized: "Semibold", comment: "Weight")).tag("semibold")
                    Text(String(localized: "Bold", comment: "Weight")).tag("bold")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            // Text color override
            HStack(spacing: 6) {
                Text(String(localized: "Color:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                ColorPicker("", selection: Binding(
                    get: { pm.resolvedRefTextColor },
                    set: { pm.refTextColorHex = $0.toHex() }
                ))
                .labelsHidden()
                .controlSize(.small)
                Spacer()
                Button(String(localized: "Global", comment: "Button")) {
                    pm.refTextColorHex = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            // Alignment override
            HStack(spacing: 6) {
                Text(String(localized: "Align:", comment: "Setting label"))
                    .font(.caption)
                    .frame(width: 50, alignment: .trailing)
                Picker("", selection: Binding(
                    get: { pm.refAlignmentRaw },
                    set: { pm.refAlignmentRaw = $0 }
                )) {
                    Text(String(localized: "Global", comment: "Alignment option")).tag("")
                    Label(String(localized: "Left", comment: "Alignment"), systemImage: "text.alignleft").tag("leading")
                    Label(String(localized: "Center", comment: "Alignment"), systemImage: "text.aligncenter").tag("center")
                    Label(String(localized: "Right", comment: "Alignment"), systemImage: "text.alignright").tag("trailing")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
            }

            Divider()

            // -- Position & Scale --
            sectionLabel(String(localized: "Position & Scale", comment: "Edit section"))

            editSlider(
                label: String(localized: "Scale", comment: "Edit slider"),
                value: Binding(get: { pm.editRefMultiplier }, set: { pm.editRefMultiplier = $0 }),
                range: 0.3...2.0, step: 0.05,
                format: "%.2f×"
            )

            editSlider(
                label: String(localized: "Offset X", comment: "Edit slider"),
                value: Binding(get: { pm.editRefOffsetX }, set: { pm.editRefOffsetX = $0 }),
                range: -300...300, step: 1,
                format: "%.0f px"
            )

            editSlider(
                label: String(localized: "Offset Y", comment: "Edit slider"),
                value: Binding(get: { pm.editRefOffsetY }, set: { pm.editRefOffsetY = $0 }),
                range: -300...300, step: 1,
                format: "%.0f px"
            )

            editSlider(
                label: String(localized: "Padding", comment: "Edit slider"),
                value: Binding(get: { pm.editRefPadding }, set: { pm.editRefPadding = $0 }),
                range: -50...100, step: 1,
                format: "%.0f px"
            )

            editSlider(
                label: String(localized: "Opacity", comment: "Edit slider"),
                value: Binding(get: { pm.editRefOpacity }, set: { pm.editRefOpacity = $0 }),
                range: 0.1...1.0, step: 0.05,
                format: "%.0f%%",
                displayMultiplier: 100
            )
        }
    }

    // MARK: - Section Label
    @ViewBuilder
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
    }

    // MARK: - Reusable Slider
    @ViewBuilder
    private func editSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        format: String,
        displayMultiplier: Double = 1.0
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value.wrappedValue * displayMultiplier))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }
}
