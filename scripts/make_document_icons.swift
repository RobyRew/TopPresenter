#!/usr/bin/env swift
//
//  make_document_icons.swift
//  TopPresenter
//
//  Draws the six document icons and writes them as .icns into
//  TopPresenter/Resources/, where Info.plist's `UTTypeIconFile` picks them up.
//
//      swift scripts/make_document_icons.swift
//
//  EVERYTHING HERE IS ORIGINAL ARTWORK, and it has to be. SF Symbols are
//  licensed for use inside an app's interface and explicitly NOT for icons, and
//  Apple's own document icons are not ours to copy — so the page, the fold and
//  every glyph below are drawn from primitives. That also means the icons are
//  reproducible: change a colour here, re-run, done. No binary nobody can edit.
//
//  The shape follows the macOS convention because that convention is what makes
//  a file read as a document at 16pt: a portrait page, a folded top-right
//  corner showing the sheet's underside, a hairline edge, and one tinted glyph.
//  The tints are hue-shifted from the app icon's violet so the six read as a
//  family rather than six unrelated stickers.
//

import AppKit
import Foundation

// MARK: - The family

struct DocumentIcon {
    let fileName: String        // matches UTTypeIconFile in Info.plist
    let tint: NSColor
    let glyph: (CGContext, CGRect, NSColor) -> Void
}

/// Hue-shifted around the app icon's violet (#6E63FF → #7A3DD8).
private func tint(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
}

// MARK: - Glyphs (all drawn, none borrowed)

/// A closed book seen face-on, with a spine band and a ribbon — the Bible.
private func drawBook(_ ctx: CGContext, _ r: CGRect, _ color: NSColor) {
    let w = r.width, h = r.height
    let body = CGRect(x: r.minX + w * 0.10, y: r.minY + h * 0.06,
                      width: w * 0.80, height: h * 0.88)
    ctx.setFillColor(color.cgColor)
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: w * 0.07, cornerHeight: w * 0.07, transform: nil))
    ctx.fillPath()

    // Spine: a darker band down the left edge.
    ctx.setFillColor(color.blended(withFraction: 0.35, of: .black)!.cgColor)
    let spine = CGRect(x: body.minX, y: body.minY, width: w * 0.13, height: body.height)
    ctx.addPath(CGPath(roundedRect: spine, cornerWidth: w * 0.06, cornerHeight: w * 0.06, transform: nil))
    ctx.fillPath()
    ctx.fill(CGRect(x: spine.maxX - w * 0.06, y: body.minY, width: w * 0.06, height: body.height))

    // Ribbon marker hanging past the bottom edge.
    ctx.setFillColor(NSColor(srgbRed: 1, green: 0.81, blue: 0.39, alpha: 1).cgColor)
    // Near the fore-edge, where a real bookmark sits — and, more practically,
    // clear of the cross, which it was sitting on top of.
    let ribbonX = body.minX + w * 0.60
    let ribbonW = w * 0.13
    ctx.move(to: CGPoint(x: ribbonX, y: body.maxY))
    ctx.addLine(to: CGPoint(x: ribbonX + ribbonW, y: body.maxY))
    ctx.addLine(to: CGPoint(x: ribbonX + ribbonW, y: body.minY - h * 0.10))
    ctx.addLine(to: CGPoint(x: ribbonX + ribbonW / 2, y: body.minY - h * 0.02))
    ctx.addLine(to: CGPoint(x: ribbonX, y: body.minY - h * 0.10))
    ctx.closePath()
    ctx.fillPath()

    // Cross, cut out of the cover.
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    let cx = body.minX + body.width * 0.36
    let cy = body.midY
    let arm = w * 0.075, len = h * 0.30
    ctx.fill(CGRect(x: cx - arm / 2, y: cy - len / 2, width: arm, height: len))
    ctx.fill(CGRect(x: cx - len * 0.34, y: cy + len * 0.06, width: len * 0.68, height: arm))
}

/// One note: a beam and a filled head, no stave.
private func drawNote(_ ctx: CGContext, _ r: CGRect, _ color: NSColor) {
    let w = r.width, h = r.height
    ctx.setFillColor(color.cgColor)

    let stemW = w * 0.10
    let stemX = r.minX + w * 0.58
    ctx.fill(CGRect(x: stemX, y: r.minY + h * 0.22, width: stemW, height: h * 0.66))

    // Flag, as a filled curve off the stem top.
    ctx.move(to: CGPoint(x: stemX + stemW, y: r.minY + h * 0.88))
    ctx.addCurve(to: CGPoint(x: stemX + stemW + w * 0.30, y: r.minY + h * 0.50),
                 control1: CGPoint(x: stemX + stemW + w * 0.30, y: r.minY + h * 0.84),
                 control2: CGPoint(x: stemX + stemW + w * 0.30, y: r.minY + h * 0.66))
    ctx.addLine(to: CGPoint(x: stemX + stemW + w * 0.12, y: r.minY + h * 0.56))
    ctx.addCurve(to: CGPoint(x: stemX + stemW, y: r.minY + h * 0.70),
                 control1: CGPoint(x: stemX + stemW + w * 0.14, y: r.minY + h * 0.64),
                 control2: CGPoint(x: stemX + stemW, y: r.minY + h * 0.66))
    ctx.closePath()
    ctx.fillPath()

    // Head: an ellipse, tilted the way a real notehead is.
    ctx.saveGState()
    let headCentre = CGPoint(x: stemX - w * 0.10, y: r.minY + h * 0.22)
    ctx.translateBy(x: headCentre.x, y: headCentre.y)
    ctx.rotate(by: -.pi / 9)
    ctx.fillEllipse(in: CGRect(x: -w * 0.22, y: -h * 0.145, width: w * 0.44, height: h * 0.29))
    ctx.restoreGState()
}

/// Three stacked cards with a note on the front — a collection of songs.
private func drawNoteStack(_ ctx: CGContext, _ r: CGRect, _ color: NSColor) {
    let w = r.width, h = r.height
    for (index, fraction) in [0.45, 0.25, 0.0].enumerated() {
        let inset = w * 0.055 * CGFloat(2 - index)
        let card = CGRect(x: r.minX + inset, y: r.minY + h * 0.06 + CGFloat(2 - index) * h * 0.11,
                          width: w - inset * 2, height: h * 0.60)
        ctx.setFillColor(color.blended(withFraction: fraction, of: .white)!.cgColor)
        ctx.addPath(CGPath(roundedRect: card, cornerWidth: w * 0.06, cornerHeight: w * 0.06, transform: nil))
        ctx.fillPath()
    }
    let front = CGRect(x: r.minX + w * 0.11, y: r.minY + h * 0.06, width: w * 0.78, height: h * 0.60)
    drawNote(ctx, front.insetBy(dx: front.width * 0.20, dy: front.height * 0.14), .white)
}

/// A slide on a slide — two overlapping frames.
private func drawSlides(_ ctx: CGContext, _ r: CGRect, _ color: NSColor) {
    let w = r.width, h = r.height
    ctx.setFillColor(color.blended(withFraction: 0.45, of: .white)!.cgColor)
    let back = CGRect(x: r.minX, y: r.minY + h * 0.24, width: w * 0.78, height: h * 0.60)
    ctx.addPath(CGPath(roundedRect: back, cornerWidth: w * 0.06, cornerHeight: w * 0.06, transform: nil))
    ctx.fillPath()

    ctx.setFillColor(color.cgColor)
    let front = CGRect(x: r.minX + w * 0.22, y: r.minY + h * 0.06, width: w * 0.78, height: h * 0.60)
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: w * 0.06, cornerHeight: w * 0.06, transform: nil))
    ctx.fillPath()

    // Two text lines on the front slide.
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
    let lineH = h * 0.075
    ctx.addPath(CGPath(roundedRect: CGRect(x: front.minX + w * 0.10, y: front.midY + lineH * 0.35,
                                           width: front.width * 0.62, height: lineH),
                       cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
    ctx.addPath(CGPath(roundedRect: CGRect(x: front.minX + w * 0.10, y: front.midY - lineH * 1.6,
                                           width: front.width * 0.40, height: lineH),
                       cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
    ctx.fillPath()
}

/// A running order: three rows, each a bullet and a rule.
private func drawRunningOrder(_ ctx: CGContext, _ r: CGRect, _ color: NSColor) {
    let w = r.width, h = r.height
    let rows = 3
    let rowH = h * 0.16
    let gap = (h - CGFloat(rows) * rowH) / CGFloat(rows - 1)
    for row in 0..<rows {
        let y = r.maxY - rowH - CGFloat(row) * (rowH + gap)
        ctx.setFillColor(color.cgColor)
        ctx.fillEllipse(in: CGRect(x: r.minX, y: y, width: rowH, height: rowH))
        ctx.setFillColor(color.blended(withFraction: 0.35, of: .white)!.cgColor)
        let barW = w * (row == 1 ? 0.56 : 0.72)
        ctx.addPath(CGPath(roundedRect: CGRect(x: r.minX + rowH * 1.6, y: y + rowH * 0.18,
                                               width: barW, height: rowH * 0.64),
                           cornerWidth: rowH * 0.32, cornerHeight: rowH * 0.32, transform: nil))
        ctx.fillPath()
    }
}

/// A theme: three overlapping colour discs.
private func drawPalette(_ ctx: CGContext, _ r: CGRect, _ color: NSColor) {
    let w = r.width, h = r.height
    let d = w * 0.52
    let discs: [(CGPoint, NSColor)] = [
        (CGPoint(x: r.minX + w * 0.02, y: r.minY + h * 0.06), color),
        (CGPoint(x: r.minX + w * 0.46, y: r.minY + h * 0.06), color.blended(withFraction: 0.45, of: .white)!),
        (CGPoint(x: r.minX + w * 0.24, y: r.minY + h * 0.44), color.blended(withFraction: 0.30, of: .black)!),
    ]
    ctx.setBlendMode(.normal)
    for (origin, discColor) in discs {
        ctx.setFillColor(discColor.withAlphaComponent(0.92).cgColor)
        ctx.fillEllipse(in: CGRect(origin: origin, size: CGSize(width: d, height: d)))
    }
}

let icons: [DocumentIcon] = [
    .init(fileName: "TopPresenterBible", tint: tint(0x4F57D6), glyph: drawBook),
    .init(fileName: "TopPresenterSong", tint: tint(0x8A3FD1), glyph: drawNote),
    .init(fileName: "TopPresenterSongCollection", tint: tint(0x6B2FB5), glyph: drawNoteStack),
    .init(fileName: "TopPresenterSlides", tint: tint(0x2C7BE5), glyph: drawSlides),
    .init(fileName: "TopPresenterSession", tint: tint(0x0E9F6E), glyph: drawRunningOrder),
    .init(fileName: "TopPresenterTheme", tint: tint(0xD6357F), glyph: drawPalette),
]

// MARK: - The page

/// Draw one icon at `size` points into a bitmap.
func render(_ icon: DocumentIcon, size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsCtx
    let ctx = nsCtx.cgContext

    let s = CGFloat(size) / 1024.0
    ctx.scaleBy(x: s, y: s)

    // Page geometry, in a 1024 canvas. Portrait, centred, with room for the
    // shadow — the proportions Finder expects at every size.
    let left: CGFloat = 148, right: CGFloat = 876
    let bottom: CGFloat = 52, top: CGFloat = 972
    let radius: CGFloat = 26
    let fold: CGFloat = 208

    let page = CGMutablePath()
    page.move(to: CGPoint(x: left + radius, y: top))
    page.addLine(to: CGPoint(x: right - fold, y: top))
    page.addLine(to: CGPoint(x: right, y: top - fold))
    page.addLine(to: CGPoint(x: right, y: bottom + radius))
    page.addArc(tangent1End: CGPoint(x: right, y: bottom), tangent2End: CGPoint(x: right - radius, y: bottom), radius: radius)
    page.addLine(to: CGPoint(x: left + radius, y: bottom))
    page.addArc(tangent1End: CGPoint(x: left, y: bottom), tangent2End: CGPoint(x: left, y: bottom + radius), radius: radius)
    page.addLine(to: CGPoint(x: left, y: top - radius))
    page.addArc(tangent1End: CGPoint(x: left, y: top), tangent2End: CGPoint(x: left + radius, y: top), radius: radius)
    page.closeSubpath()

    // Shadow, then the sheet.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 22,
                  color: NSColor.black.withAlphaComponent(0.20).cgColor)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(page)
    ctx.fillPath()
    ctx.restoreGState()

    // Hairline edge — what keeps a white sheet visible on a white background.
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.13).cgColor)
    ctx.setLineWidth(3)
    ctx.addPath(page)
    ctx.strokePath()

    // The fold: the sheet's underside, shaded so the corner reads as turned.
    let foldPath = CGMutablePath()
    foldPath.move(to: CGPoint(x: right - fold, y: top))
    foldPath.addLine(to: CGPoint(x: right, y: top - fold))
    foldPath.addLine(to: CGPoint(x: right - fold, y: top - fold))
    foldPath.closeSubpath()
    ctx.saveGState()
    ctx.addPath(foldPath)
    ctx.clip()
    let shades = [NSColor(white: 0.80, alpha: 1).cgColor, NSColor(white: 0.95, alpha: 1).cgColor]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: shades as CFArray, locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: right - fold, y: top),
                               end: CGPoint(x: right - fold * 0.35, y: top - fold),
                               options: [])
    }
    ctx.restoreGState()
    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.13).cgColor)
    ctx.setLineWidth(3)
    ctx.move(to: CGPoint(x: right - fold, y: top))
    ctx.addLine(to: CGPoint(x: right - fold, y: top - fold))
    ctx.addLine(to: CGPoint(x: right, y: top - fold))
    ctx.strokePath()

    // The glyph, in the lower two thirds — the top is where the fold lives, and
    // a glyph tucked under it reads as crowded at 16pt.
    let box = CGRect(x: left + 120, y: bottom + 130, width: (right - left) - 240, height: 400)
    icon.glyph(ctx, box, icon.tint)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// MARK: - Write

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let staging = root.appendingPathComponent("Logo/DocumentIcons", isDirectory: true)
let resources = root.appendingPathComponent("TopPresenter/Resources", isDirectory: true)
try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)

// The sizes Finder actually asks for. 16 and 32 matter most: that is the list
// view, and it is where a fussy icon turns to mud.
let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for icon in icons {
    let iconset = staging.appendingPathComponent("\(icon.fileName).iconset", isDirectory: true)
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

    for variant in variants {
        let rep = render(icon, size: variant.px)
        guard let data = rep.representation(using: .png, properties: [:]) else { continue }
        try data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconset.path,
                         "-o", resources.appendingPathComponent("\(icon.fileName).icns").path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        FileHandle.standardError.write(Data("iconutil failed for \(icon.fileName)\n".utf8))
        exit(1)
    }
    print("✓ \(icon.fileName).icns")
}
print("Wrote \(icons.count) document icons to TopPresenter/Resources/")
