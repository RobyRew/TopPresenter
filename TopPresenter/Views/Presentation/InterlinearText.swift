//
//  InterlinearText.swift
//  TopPresenter
//
//  Renders a Bible verse as an interlinear "stacked grid": each word becomes a
//  vertical column — the word on top, then (per theme) its gloss/meaning, Strong's
//  number, and morphology — flowing left-to-right and wrapping to the box width.
//
//  Driven entirely by the rich `VerseRun { text, kind, strong, morph, gloss }` data
//  the verse already carries (Strong's-tagged / interlinear modules). It engages
//  only when runs actually carry annotations, so plain translations are unaffected.
//

import SwiftUI

/// One word column of the interlinear grid. Annotation rows are present only when
/// the source run carried that field.
struct InterlinearColumn: Equatable {
    var word: String
    var kind: String          // "plain" | "woc" | "add" | "divineName" | "quote"
    var gloss: String?
    var strong: String?
    var morph: String?
}

/// Pure mapping of rich runs → per-word columns. Annotated runs (interlinear /
/// Strong's words) become one column carrying their annotations; plain runs are
/// split into bare word columns so the whole verse still reads as a grid.
func interlinearColumns(from runs: [VerseRun]) -> [InterlinearColumn] {
    var cols: [InterlinearColumn] = []
    for run in runs {
        let words = run.text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
        let hasAnno = (run.strong?.isEmpty == false) || (run.morph?.isEmpty == false) || (run.gloss?.isEmpty == false)
        if words.isEmpty { continue }
        if hasAnno {
            // Annotation belongs to the run (a single word in interlinear/Strong's
            // mode); if it spans words, keep it on the first.
            for (i, w) in words.enumerated() {
                cols.append(InterlinearColumn(
                    word: w, kind: run.kind,
                    gloss: i == 0 ? run.gloss : nil,
                    strong: i == 0 ? run.strong : nil,
                    morph: i == 0 ? run.morph : nil))
            }
        } else {
            for w in words { cols.append(InterlinearColumn(word: w, kind: run.kind, gloss: nil, strong: nil, morph: nil)) }
        }
    }
    return cols
}

/// True when interlinear should actually engage for these runs (something to show).
func interlinearHasContent(_ runs: [VerseRun], options: PresentationManager.ContentOptions) -> Bool {
    guard options.interlinearModeRaw != "off" else { return false }
    let full = options.interlinearModeRaw == "full"
    return runs.contains { r in
        (options.interlinearShowGloss && (r.gloss?.isEmpty == false))
            || (full && options.interlinearShowStrong && (r.strong?.isEmpty == false))
            || (full && options.interlinearShowMorph && (r.morph?.isEmpty == false))
    }
}

/// The stacked interlinear grid for a verse. Frames + positions itself in `rect`
/// like the paragraph renderer so the output hook is a one-liner.
struct InterlinearText: View {
    let columns: [InterlinearColumn]
    let style: PresentationManager.ResolvedBoxStyle
    let options: PresentationManager.ContentOptions
    let wocColor: Color
    let rect: CGRect
    let fontScale: CGFloat
    var fittedSize: CGFloat? = nil

    private var baseSize: CGFloat { fittedSize ?? CGFloat(style.fontSize) * fontScale }
    private var isFull: Bool { options.interlinearModeRaw == "full" }

    private var glossColor: Color {
        options.interlinearGlossColorHex.isEmpty
            ? style.color.opacity(0.82)
            : (Color(hex: options.interlinearGlossColorHex) ?? style.color)
    }
    private var strongColor: Color {
        options.interlinearStrongColorHex.isEmpty
            ? (Color(hex: "D9A441") ?? .orange)
            : (Color(hex: options.interlinearStrongColorHex) ?? .orange)
    }
    private var morphColor: Color {
        options.interlinearMorphColorHex.isEmpty
            ? style.color.opacity(0.55)
            : (Color(hex: options.interlinearMorphColorHex) ?? style.color)
    }

    var body: some View {
        let showGloss = options.interlinearShowGloss
        let showStrong = isFull && options.interlinearShowStrong
        let showMorph = isFull && options.interlinearShowMorph

        FlowLayout(hSpacing: CGFloat(options.interlinearColumnSpacing) * fontScale,
                   vSpacing: CGFloat(options.interlinearRowSpacing) * fontScale * 6) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                VStack(spacing: CGFloat(options.interlinearRowSpacing) * fontScale) {
                    Text(style.display(col.word))
                        .font(style.font(at: baseSize))
                        .foregroundColor((col.kind == "woc" ? wocColor : style.color).opacity(style.opacity))
                    if showGloss, let g = col.gloss, !g.isEmpty {
                        Text(g).font(style.font(at: baseSize * CGFloat(options.interlinearGlossScale))).foregroundColor(glossColor)
                    }
                    if showStrong, let s = col.strong, !s.isEmpty {
                        Text(s).font(style.font(at: baseSize * CGFloat(options.interlinearStrongScale))).foregroundColor(strongColor)
                    }
                    if showMorph, let m = col.morph, !m.isEmpty {
                        Text(m).font(style.font(at: baseSize * CGFloat(options.interlinearMorphScale))).foregroundColor(morphColor)
                    }
                }
                .fixedSize()
            }
        }
        .shadow(color: style.shadowEnabled ? style.shadowColor : .clear,
                radius: style.shadowEnabled ? style.shadowRadius * fontScale : 0,
                x: 0, y: style.shadowEnabled ? 2 * fontScale : 0)
        .padding(.horizontal, CGFloat(style.padding) * fontScale)
        .frame(width: rect.width, height: rect.height, alignment: style.frameAlignment)
        .position(x: rect.midX, y: rect.midY)
    }
}

/// A simple wrapping flow layout: lays children left-to-right, wrapping to the
/// proposed width; each wrapped row is centered horizontally.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 8
    var vSpacing: CGFloat = 6

    struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(maxWidth: CGFloat, sizes: [CGSize]) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, size) in sizes.enumerated() {
            let add = row.indices.isEmpty ? size.width : row.width + hSpacing + size.width
            if !row.indices.isEmpty && add > maxWidth {
                rows.append(row); row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + hSpacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let maxWidth = proposal.width ?? sizes.map { $0.width }.reduce(0, +)
        let rs = rows(maxWidth: maxWidth, sizes: sizes)
        let height = rs.map { $0.height }.reduce(0, +) + vSpacing * CGFloat(max(0, rs.count - 1))
        let width = rs.map { $0.width }.max() ?? 0
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rs = rows(maxWidth: bounds.width, sizes: sizes)
        var y = bounds.minY
        for row in rs {
            var x = bounds.minX + max(0, (bounds.width - row.width) / 2)
            for idx in row.indices {
                let size = sizes[idx]
                subviews[idx].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
                x += size.width + hSpacing
            }
            y += row.height + vSpacing
        }
    }
}
