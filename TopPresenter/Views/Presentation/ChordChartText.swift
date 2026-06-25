//
//  ChordChartText.swift
//  TopPresenter
//
//  Renders chord-over-lyric lines (a lead-sheet / chord chart) for the chords
//  casetá. The lyrics use the box's main style; the chord LETTERS use a second,
//  fully independent style (font, size, weight, color). Each chord is positioned by
//  the MEASURED width of the lyric prefix up to its character offset, so alignment
//  holds for ANY lyric font (proportional or monospaced) and any chord size.
//
//  Chords arrive ALREADY transposed/capo-adjusted (see PresentationManager.
//  applyChordTranspose); the whole chart auto-fits its box.
//

import SwiftUI
import AppKit

struct ChordChartText: View {
    let lines: [SongLine]
    let lyricStyle: PresentationManager.ResolvedBoxStyle
    let chordStyle: PresentationManager.ResolvedBoxStyle
    let rect: CGRect
    let fontScale: CGFloat

    private var lyricBase: CGFloat { CGFloat(lyricStyle.fontSize) * fontScale }
    private var chordBase: CGFloat { CGFloat(chordStyle.fontSize) * fontScale }
    private let lyricLineFactor: CGFloat = 1.18
    private let chordBandFactor: CGFloat = 1.1
    private let groupSpacingFactor: CGFloat = 0.22

    var body: some View {
        let fit = fitScale
        let lyricSize = max(lyricBase * fit, 5)
        let chordSize = max(chordBase * fit, 4)
        let lyricFont = nsFont(lyricStyle, size: lyricSize)

        VStack(alignment: .leading, spacing: lyricSize * groupSpacingFactor) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line, lyricSize: lyricSize, chordSize: chordSize, lyricFont: lyricFont)
            }
        }
        .padding(.horizontal, CGFloat(lyricStyle.padding) * fontScale)
        .frame(width: rect.width, height: rect.height, alignment: lyricStyle.frameAlignment)
        .position(x: rect.midX, y: rect.midY)
    }

    @ViewBuilder
    private func lineView(_ line: SongLine, lyricSize: CGFloat, chordSize: CGFloat, lyricFont: NSFont) -> some View {
        let lyric = line.text.isEmpty ? " " : line.text
        VStack(alignment: .leading, spacing: 0) {
            if !line.chords.isEmpty {
                // An invisible copy of the lyric sets the row width; chords float on top,
                // each offset by the measured width of the lyric up to its position.
                Text(lyric)
                    .font(Font(lyricFont))
                    .opacity(0)
                    .frame(height: chordSize * chordBandFactor, alignment: .topLeading)
                    .clipped()
                    .overlay(alignment: .topLeading) {
                        ZStack(alignment: .topLeading) {
                            ForEach(Array(line.chords.enumerated()), id: \.offset) { _, ch in
                                Text(ch.sym)
                                    .font(chordStyle.font(at: chordSize))
                                    .foregroundColor(chordStyle.color.opacity(chordStyle.opacity))
                                    .fixedSize()
                                    .offset(x: prefixWidth(line.text, ch.pos, font: lyricFont), y: 0)
                            }
                        }
                    }
            }
            Text(lyric)
                .font(Font(lyricFont))
                .foregroundColor(lyricStyle.color.opacity(lyricStyle.opacity))
        }
        .fixedSize(horizontal: false, vertical: true)
        .shadow(
            color: lyricStyle.shadowEnabled ? lyricStyle.shadowColor : .clear,
            radius: lyricStyle.shadowEnabled ? lyricStyle.shadowRadius * fontScale : 0,
            x: 0, y: lyricStyle.shadowEnabled ? 2 * fontScale : 0
        )
    }

    // MARK: Auto-fit

    /// Single scale factor (≤1) that makes the whole chart fit the box. Widths are
    /// measured at the base lyric size, so they scale linearly with `fit`.
    private var fitScale: CGFloat {
        guard !lines.isEmpty else { return 1 }
        let lyricFont = nsFont(lyricStyle, size: lyricBase)
        let chordFont = nsFont(chordStyle, size: chordBase)
        var widest: CGFloat = 1
        for line in lines {
            var w = (line.text as NSString).size(withAttributes: [.font: lyricFont]).width
            for ch in line.chords {
                let x = prefixWidth(line.text, ch.pos, font: lyricFont)
                let cw = (ch.sym as NSString).size(withAttributes: [.font: chordFont]).width
                w = max(w, x + cw)
            }
            widest = max(widest, w)
        }
        let rows = lines.reduce(CGFloat(0)) { acc, line in
            acc + (line.chords.isEmpty ? 0 : chordBase * chordBandFactor) + lyricBase * lyricLineFactor
        }
        let totalH = rows + CGFloat(max(lines.count - 1, 0)) * lyricBase * groupSpacingFactor
        let availW = max(rect.width - 2 * CGFloat(lyricStyle.padding) * fontScale, 1)
        let availH = max(rect.height, 1)
        return min(1, availW / widest, availH / max(totalH, 1))
    }

    // MARK: Measuring helpers

    /// Width of `text`'s first `pos` characters in `font` — the chord's x offset.
    private func prefixWidth(_ text: String, _ pos: Int, font: NSFont) -> CGFloat {
        let n = min(max(pos, 0), text.count)
        guard n > 0 else { return 0 }
        let prefix = String(text.prefix(n))
        return (prefix as NSString).size(withAttributes: [.font: font]).width
    }

    private func nsFont(_ style: PresentationManager.ResolvedBoxStyle, size: CGFloat) -> NSFont {
        if style.fontName.isEmpty || style.fontName == "System" {
            return NSFont.systemFont(ofSize: size, weight: nsWeight(style.weight))
        }
        return NSFont(name: style.fontName, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: nsWeight(style.weight))
    }

    private func nsWeight(_ w: Font.Weight) -> NSFont.Weight {
        switch w {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}
