#!/usr/bin/env swift
//
//  make_theme_backgrounds.swift
//  TopPresenter
//
//  Renders the theme pack's generated backgrounds at 4K.
//
//  WHY GENERATE THEM AT ALL
//
//  A photo library gives you drama but not CONTROL. A worship background's job
//  is to sit behind text and lose — it has to be quiet where the words are, and
//  it has to stay legible in a room whose projector is washed out by daylight.
//  Stock photography is the opposite: interesting everywhere, brightest in the
//  middle, and licensed by somebody else.
//
//  These are built to lose. Every one is darkest (or lightest, for the daylight
//  themes) through the central band where the lyric sits, and carries a vignette
//  so the edges fall away. They are also a few hundred KB each instead of a few
//  MB, they are unambiguously ours to redistribute, and they share one palette
//  so the pack reads as a set rather than a folder of downloads.
//
//  Run: swift scripts/make_theme_backgrounds.swift <output-dir>
//

import AppKit
import CoreGraphics
import Foundation

let W = 3840, H = 2160

// MARK: - Small helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue)!
}

/// A soft radial "light", drawn additively-ish by layering translucent stops.
func glow(_ ctx: CGContext, at p: CGPoint, radius: CGFloat, color: CGColor, strength: CGFloat) {
    let space = CGColorSpaceCreateDeviceRGB()
    let comps = color.components ?? [0, 0, 0, 1]
    let inner = CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: strength)
    let outer = CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: 0)
    guard let g = CGGradient(colorsSpace: space, colors: [inner, outer] as CFArray,
                             locations: [0, 1]) else { return }
    ctx.drawRadialGradient(g, startCenter: p, startRadius: 0,
                           endCenter: p, endRadius: radius, options: [])
}

func linear(_ ctx: CGContext, from: CGPoint, to: CGPoint, stops: [(CGFloat, CGColor)]) {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let g = CGGradient(colorsSpace: space,
                             colors: stops.map(\.1) as CFArray,
                             locations: stops.map(\.0)) else { return }
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

/// Darkens the edges so the frame reads as one object and text keeps its ground.
func vignette(_ ctx: CGContext, strength: CGFloat = 0.55) {
    let space = CGColorSpaceCreateDeviceRGB()
    let mid = CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2)
    guard let g = CGGradient(colorsSpace: space,
                             colors: [rgb(0x000000, 0), rgb(0x000000, strength)] as CFArray,
                             locations: [0.45, 1]) else { return }
    ctx.drawRadialGradient(g, startCenter: mid, startRadius: 0,
                           endCenter: mid, endRadius: CGFloat(W) * 0.72, options: [])
}

/// Film grain. Without it a wide gradient BANDS on a projector — 8-bit output
/// over a 3840px sweep steps visibly, and a little noise dithers it away.
func grain(_ ctx: CGContext, amount: CGFloat = 0.018) {
    var seed: UInt64 = 0x9E3779B97F4A7C15
    func rnd() -> CGFloat {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return CGFloat(seed % 1000) / 1000
    }
    let step = 3
    for y in stride(from: 0, to: H, by: step) {
        for x in stride(from: 0, to: W, by: step) {
            let v = rnd()
            guard v > 0.6 else { continue }
            ctx.setFillColor(rgb(0xFFFFFF, amount * v))
            ctx.fill(CGRect(x: x, y: y, width: step, height: step))
        }
    }
}

/// Scattered stars, brighter near the top where sky belongs.
func stars(_ ctx: CGContext, count: Int) {
    var seed: UInt64 = 0xD1B54A32D192ED03
    func rnd() -> CGFloat {
        seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
        return CGFloat(seed % 10000) / 10000
    }
    for _ in 0..<count {
        let x = rnd() * CGFloat(W)
        let y = CGFloat(H) * (0.35 + rnd() * 0.65)
        let r = 1 + rnd() * 2.6
        let a = 0.25 + rnd() * 0.6
        ctx.setFillColor(rgb(0xFFFFFF, a))
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
    }
}

/// Shafts of light fanning DOWNWARD from `origin`.
///
/// CoreGraphics puts the origin bottom-left and the shape below is built along
/// +y, so "down the screen" is a rotation of pi, not -pi/2. Getting that wrong
/// fans the rays out sideways like a paper hand-fan, which is exactly what the
/// first render did.
func rays(_ ctx: CGContext, origin: CGPoint, color: CGColor, count: Int, spread: CGFloat) {
    ctx.saveGState()
    for i in 0..<count {
        let t = CGFloat(i) / CGFloat(max(count - 1, 1))
        let angle = CGFloat.pi + (t - 0.5) * spread
        let length = CGFloat(H) * 2.2
        let width = CGFloat(W) * (0.012 + 0.03 * abs(sin(t * 7)))
        ctx.saveGState()
        ctx.translateBy(x: origin.x, y: origin.y)
        ctx.rotate(by: angle)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -width / 2, y: 0))
        path.addLine(to: CGPoint(x: width / 2, y: 0))
        path.addLine(to: CGPoint(x: width * 2.4, y: length))
        path.addLine(to: CGPoint(x: -width * 2.4, y: length))
        path.closeSubpath()
        ctx.addPath(path)
        ctx.clip()
        let comps = color.components ?? [1, 1, 1, 1]
        // Faint, and gone by a third of the way down. At 0.30 these read as a
        // hard-edged stage spotlight and fight the lyric instead of sitting
        // behind it; the shaft should be a suggestion, not a shape.
        linear(ctx, from: .zero, to: CGPoint(x: 0, y: length), stops: [
            (0, CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: 0.13)),
            (0.35, CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: 0.04)),
            (1, CGColor(red: comps[0], green: comps[1], blue: comps[2], alpha: 0)),
        ])
        ctx.restoreGState()
    }
    ctx.restoreGState()
}

func write(_ ctx: CGContext, to dir: URL, named name: String) {
    guard let image = ctx.makeImage() else { return }
    let rep = NSBitmapImageRep(cgImage: image)
    // JPEG at high quality: a 4K PNG of a smooth gradient is ~12 MB and the
    // pack ships a dozen of them. 0.92 is visually lossless here and ~600 KB.
    guard let data = rep.representation(using: .jpeg,
                                        properties: [.compressionFactor: 0.92]) else { return }
    let url = dir.appendingPathComponent("\(name).jpg")
    try? data.write(to: url)
    let kb = (try? Data(contentsOf: url).count) ?? 0
    print(String(format: "  %-22s %6.0f KB", (name as NSString).utf8String!, Double(kb) / 1024))
}

// MARK: - The backgrounds

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
print("Rendering 4K backgrounds into \(out.path)")

// 1 — Miezul nopții: deep navy, a horizon glow, stars.
do {
    let ctx = makeContext()
    linear(ctx, from: CGPoint(x: 0, y: CGFloat(H)), to: CGPoint(x: 0, y: 0), stops: [
        (0, rgb(0x05070F)), (0.55, rgb(0x0B1230)), (1, rgb(0x152A5E)),
    ])
    stars(ctx, count: 1400)
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.5, y: 0), radius: CGFloat(W) * 0.62,
         color: rgb(0x3E6BD0), strength: 0.42)
    vignette(ctx, strength: 0.5)
    grain(ctx)
    write(ctx, to: out, named: "Miezul-noptii")
}

// 2 — Răsărit: warm amber sweep with shafts of light.
do {
    let ctx = makeContext()
    // Bright at the TOP (y = H in CG coords), falling to near-black at the floor.
    linear(ctx, from: CGPoint(x: 0, y: CGFloat(H)), to: CGPoint(x: 0, y: 0), stops: [
        (0, rgb(0xC26516)), (0.5, rgb(0x4A2109)), (1, rgb(0x140A04)),
    ])
    // Off-centre: dead-centre symmetry reads as a logo, not as daylight.
    rays(ctx, origin: CGPoint(x: CGFloat(W) * 0.34, y: CGFloat(H) * 1.02),
         color: rgb(0xFFD9A0), count: 7, spread: 0.85)
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.34, y: CGFloat(H) * 0.97),
         radius: CGFloat(W) * 0.55, color: rgb(0xFFAE4D), strength: 0.45)
    vignette(ctx, strength: 0.6)
    grain(ctx)
    write(ctx, to: out, named: "Rasarit")
}

// 3 — Lumină: near-white, for rooms the projector cannot beat. Text on this
//     theme is DARK, which is the only combination that survives daylight.
do {
    let ctx = makeContext()
    linear(ctx, from: CGPoint(x: 0, y: CGFloat(H)), to: CGPoint(x: 0, y: 0), stops: [
        (0, rgb(0xE8EAF0)), (0.5, rgb(0xF6F7FA)), (1, rgb(0xFFFFFF)),
    ])
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.5, y: CGFloat(H) * 0.85),
         radius: CGFloat(W) * 0.55, color: rgb(0xFFFFFF), strength: 0.9)
    let space = CGColorSpaceCreateDeviceRGB()
    if let g = CGGradient(colorsSpace: space,
                          colors: [rgb(0x9AA3B8, 0), rgb(0x9AA3B8, 0.22)] as CFArray,
                          locations: [0.5, 1]) {
        let mid = CGPoint(x: CGFloat(W) / 2, y: CGFloat(H) / 2)
        ctx.drawRadialGradient(g, startCenter: mid, startRadius: 0,
                               endCenter: mid, endRadius: CGFloat(W) * 0.72, options: [])
    }
    grain(ctx, amount: 0.012)
    write(ctx, to: out, named: "Lumina")
}

// 4 — Grafit: as close to off as a screen gets while still being a background.
//     Maximum contrast for text; the theme to reach for when nothing else works.
do {
    let ctx = makeContext()
    linear(ctx, from: CGPoint(x: 0, y: CGFloat(H)), to: CGPoint(x: 0, y: 0), stops: [
        (0, rgb(0x000000)), (0.6, rgb(0x0A0B0D)), (1, rgb(0x15171B)),
    ])
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.5, y: CGFloat(H) * 0.62),
         radius: CGFloat(W) * 0.55, color: rgb(0x2A2E36), strength: 0.5)
    vignette(ctx, strength: 0.4)
    grain(ctx, amount: 0.014)
    write(ctx, to: out, named: "Grafit")
}

// 5 — Indigo: violet mesh, three lights bled together.
do {
    let ctx = makeContext()
    ctx.setFillColor(rgb(0x0B0620)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.18, y: CGFloat(H) * 0.78),
         radius: CGFloat(W) * 0.55, color: rgb(0x5B2BC9), strength: 0.55)
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.85, y: CGFloat(H) * 0.30),
         radius: CGFloat(W) * 0.50, color: rgb(0x8E2C86), strength: 0.45)
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.55, y: CGFloat(H) * 0.05),
         radius: CGFloat(W) * 0.45, color: rgb(0x2360B8), strength: 0.35)
    vignette(ctx, strength: 0.55)
    grain(ctx)
    write(ctx, to: out, named: "Indigo")
}

// 6 — Smarald: deep green, calm.
do {
    let ctx = makeContext()
    ctx.setFillColor(rgb(0x02100C)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.5, y: CGFloat(H) * 0.72),
         radius: CGFloat(W) * 0.62, color: rgb(0x0E6B4F), strength: 0.55)
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.12, y: CGFloat(H) * 0.15),
         radius: CGFloat(W) * 0.40, color: rgb(0x0A4F6B), strength: 0.32)
    vignette(ctx, strength: 0.55)
    grain(ctx)
    write(ctx, to: out, named: "Smarald")
}

// 7 — Purpuriu: burgundy, for Communion and Good Friday.
do {
    let ctx = makeContext()
    ctx.setFillColor(rgb(0x150207)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.5, y: CGFloat(H) * 0.55),
         radius: CGFloat(W) * 0.6, color: rgb(0x7A0F2B), strength: 0.55)
    glow(ctx, at: CGPoint(x: CGFloat(W) * 0.82, y: CGFloat(H) * 0.88),
         radius: CGFloat(W) * 0.35, color: rgb(0xB8452F), strength: 0.28)
    vignette(ctx, strength: 0.6)
    grain(ctx)
    write(ctx, to: out, named: "Purpuriu")
}

// 8 — Auroră: cold green-and-violet bands over a night sky.
do {
    let ctx = makeContext()
    linear(ctx, from: CGPoint(x: 0, y: CGFloat(H)), to: CGPoint(x: 0, y: 0), stops: [
        (0, rgb(0x02040C)), (1, rgb(0x0A1430)),
    ])
    stars(ctx, count: 900)
    for (i, colour) in [rgb(0x1FBF8F), rgb(0x2E6BD6), rgb(0x8B3FD1)].enumerated() {
        let cx = CGFloat(W) * (0.28 + 0.22 * CGFloat(i))
        glow(ctx, at: CGPoint(x: cx, y: CGFloat(H) * (0.62 + 0.08 * CGFloat(i))),
             radius: CGFloat(W) * 0.34, color: colour, strength: 0.34)
    }
    vignette(ctx, strength: 0.55)
    grain(ctx)
    write(ctx, to: out, named: "Aurora")
}

print("done")
