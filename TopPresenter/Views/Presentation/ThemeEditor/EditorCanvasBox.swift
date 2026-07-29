import SwiftUI

/// The sample text the editor canvas renders in each box.
struct EditorSampleFields: Equatable {
    var main: String
    var reference: String
    var translation: String
    var subtitle: String
}

/// ONE box on the Theme Editor canvas.
///
/// This lived inline in `LayoutEditorSheet.sampleContent(size:)`, which made it
/// part of the sheet's body — so every box's style resolution and, worse, its
/// auto-fit text measurement re-ran whenever anything in that 2400-line view
/// changed, including one drag delta of an unrelated box.
///
/// As its own `View` the work is per box: SwiftUI skips the body of a box whose
/// inputs are unchanged and whose observed layout state did not move. Every
/// stored property here is `Equatable` on purpose, so that comparison is exact.
///
/// Deliberately NOT wrapped in `.equatable()`: these bodies read observed layout
/// state that the inputs don't describe, and the cheap structural comparison
/// already gets the win without any risk of suppressing a real update.
struct EditorCanvasBox: View {
    @Environment(PresentationManager.self) private var pm

    let identity: BoxIdentity
    /// The canvas the box is drawn on.
    let canvasSize: CGSize
    /// The real output size, in points — auto-fit measures against THIS, never
    /// the shrunken canvas, or the fitted size would change with the window.
    let referenceSize: CGSize
    let targetScale: CGFloat
    let canvasScale: CGFloat
    let fields: EditorSampleFields
    let sampleRuns: [VerseRun]
    let interlinearRuns: [VerseRun]
    let interlinearEnabled: Bool
    let chordFallback: [SongLine]

    private var fontScale: CGFloat { targetScale * canvasScale }

    var body: some View {
        switch identity {
        case .section(let section): sectionBox(section)
        case .custom(let id): customBox(id)
        case .media(let id): mediaBox(id)
        }
    }

    @ViewBuilder
    private func sectionBox(_ section: TextBoxSection) -> some View {
        if section == .chords, pm.isSectionVisible(section) {
            // Chord chart preview: live song lines, else a sample chart.
            let rect = pm.boxFrame(for: section).rect(in: canvasSize)
            let style = pm.resolvedStyle(for: section)
            let lines = pm.liveContent.songLines.isEmpty ? chordFallback : pm.transposedSongLines()
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
                let frame = pm.boxFrame(for: section)
                let rect = frame.rect(in: canvasSize)
                let style = pm.resolvedStyle(for: section)
                let fitted: CGFloat? = style.autoFit
                    ? pm.fittedVerseFontSize(
                        text: text,
                        boxSize: frame.rect(in: referenceSize).size,
                        maxSize: CGFloat(style.fontSize) * targetScale,
                        padding: CGFloat(style.padding) * targetScale,
                        fontName: style.fontName,
                        lineSpacing: style.lineSpacing
                      ) * canvasScale
                    : nil
                let ilOpts = pm.contentOptions(for: pm.activeProfileKey)
                if section == .verseContent, pm.activeProfileKey == "bible",
                   interlinearEnabled, interlinearHasContent(interlinearRuns, options: ilOpts) {
                    InterlinearText(columns: interlinearColumns(from: interlinearRuns), style: style,
                                    options: ilOpts, wocColor: pm.wocColor, rect: rect, fontScale: fontScale)
                } else {
                    EditorCanvasText(text: text, style: style, rect: rect, fontScale: fontScale,
                                     fittedSize: fitted,
                                     runs: section == .verseContent ? sampleRuns : [])
                }
            }
        }
    }

    @ViewBuilder
    private func customBox(_ id: UUID) -> some View {
        if let box = pm.customTextBox(id: id), box.isVisible {
            let resolved = box.resolvedText(
                main: fields.main, reference: fields.reference,
                translation: fields.translation, subtitle: fields.subtitle,
                slideNumber: "1 / 4"
            )
            let text = resolved.isEmpty ? box.sourceLabel : resolved
            EditorCanvasText(text: text, style: pm.resolvedCustomStyle(box),
                             rect: box.frame.rect(in: canvasSize),
                             fontScale: fontScale, fittedSize: nil)
        }
    }

    @ViewBuilder
    private func mediaBox(_ id: UUID) -> some View {
        // The editor shows every visible media box, ignoring content filters.
        if let box = pm.mediaBox(id: id), box.isVisible {
            MediaBoxContent(box: box, canvasSize: canvasSize, playsVideo: false)
                .allowsHitTesting(false)
        }
    }
}

/// A styled run of canvas text, positioned in its box.
struct EditorCanvasText: View {
    @Environment(PresentationManager.self) private var pm

    let text: String
    let style: PresentationManager.ResolvedBoxStyle
    let rect: CGRect
    let fontScale: CGFloat
    let fittedSize: CGFloat?
    var runs: [VerseRun] = []

    var body: some View {
        let size = fittedSize ?? CGFloat(style.fontSize) * fontScale
        let composed: Text = runs.contains(where: { $0.kind == "woc" })
            ? runs.reduce(Text("")) { acc, run in
                let c = (run.kind == "woc") ? pm.wocColor : style.color
                return acc + Text(style.display(run.text)).foregroundColor(c.opacity(style.opacity))
              }
            : Text(style.display(text)).foregroundColor(style.color.opacity(style.opacity))
        composed
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
}
