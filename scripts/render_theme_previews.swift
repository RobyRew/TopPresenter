#!/usr/bin/env swift
//
//  render_theme_previews.swift
//  TopPresenter
//
//  Draws a representative 16:9 still for every theme in a pack, so the release
//  page can show what you are downloading instead of listing names.
//
//  It re-implements the output's TYPOGRAPHY, not its whole layout engine: the
//  background, then the verse in the theme's own font, size, weight, colour,
//  shadow and alignment, then the reference beneath it. That is what actually
//  differs between these themes and it is what someone is deciding between.
//  A pixel-exact reproduction would mean running the app.
//
//  Video themes are previewed on a frame from the clip, which is the honest
//  thing to show for a moving background in a still image.
//
//  Run: swift scripts/render_theme_previews.swift <pack-dir> <out-dir>
//

import AppKit
import AVFoundation
import Foundation

let W: CGFloat = 1600, H: CGFloat = 900

let packDir = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sampleVerse = "Domnul este păstorul meu:\nnu voi duce lipsă de nimic."
let sampleRef = "Psalmul 23:1"

func weight(_ raw: String) -> NSFont.Weight {
    switch raw {
    case "light": return .light
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    default: return .regular
    }
}

func color(hex: String) -> NSColor {
    var s = hex
    var a: CGFloat = 1
    if s.count == 8 {
        let alphaHex = String(s.suffix(2)); s = String(s.prefix(6))
        a = CGFloat(UInt8(alphaHex, radix: 16) ?? 255) / 255
    }
    let v = UInt32(s, radix: 16) ?? 0xFFFFFF
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                   green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

/// A frame from a clip, for video-backed themes.
func firstFrame(_ url: URL) -> NSImage? {
    let asset = AVURLAsset(url: url)
    let gen = AVAssetImageGenerator(asset: asset)
    gen.appliesPreferredTrackTransform = true
    gen.requestedTimeToleranceBefore = .zero
    gen.requestedTimeToleranceAfter = .positiveInfinity
    gen.maximumSize = CGSize(width: 1920, height: 1080)
    let sem = DispatchSemaphore(value: 0)
    var seconds: Double = 3
    Task { if let d = try? await asset.load(.duration) { seconds = CMTimeGetSeconds(d) * 0.5 }; sem.signal() }
    sem.wait()
    guard let cg = try? gen.copyCGImage(at: CMTime(seconds: max(seconds, 0.5), preferredTimescale: 600),
                                        actualTime: nil) else { return nil }
    return NSImage(cgImage: cg, size: .zero)
}

struct Theme {
    let name: String
    let background: NSImage?
    let fontName: String
    let fontSize: CGFloat
    let weightRaw: String
    let textColor: NSColor
    let shadowOn: Bool
    let shadowRadius: CGFloat
    let shadowColor: NSColor
    let lineSpacing: CGFloat
    /// Background media opacity over black — the pack's scrim. Shown here
    /// because a preview that omits it flatters the photo themes and misleads
    /// whoever is choosing one.
    let backgroundOpacity: CGFloat
}

func load(_ pkg: URL) -> Theme? {
    guard let data = try? Data(contentsOf: pkg.appendingPathComponent("theme.json")),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let payload = root["payload"] as? [String: Any] else { return nil }

    var bg: NSImage?
    if let assets = root["assets"] as? [[String: Any]], let first = assets.first,
       let file = first["file"] as? String {
        let url = pkg.appendingPathComponent("media").appendingPathComponent(file)
        bg = (first["mediaType"] as? String) == "video" ? firstFrame(url) : NSImage(contentsOf: url)
    }
    return Theme(
        name: root["name"] as? String ?? pkg.deletingPathExtension().lastPathComponent,
        background: bg,
        fontName: payload["fontName"] as? String ?? "SF Pro",
        fontSize: payload["fontSize"] as? CGFloat ?? 130,
        weightRaw: payload["globalWeightRaw"] as? String ?? "regular",
        textColor: color(hex: payload["textColorHex"] as? String ?? "FFFFFF"),
        shadowOn: payload["shadowEnabled"] as? Bool ?? true,
        shadowRadius: payload["shadowRadius"] as? CGFloat ?? 10,
        shadowColor: color(hex: payload["shadowColorHex"] as? String ?? "000000B3"),
        lineSpacing: payload["lineSpacing"] as? CGFloat ?? 0.8,
        backgroundOpacity: (payload["backgroundEnabled"] as? Bool ?? false)
            ? (payload["backgroundOpacity"] as? CGFloat ?? 1) : 1
    )
}

func render(_ t: Theme) -> NSImage {
    let img = NSImage(size: NSSize(width: W, height: H))
    img.lockFocus()
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    if let bg = t.background {
        // Fill, centre-cropped — what the output does with a background.
        let bs = bg.size
        let scale = max(W / bs.width, H / bs.height)
        let dw = bs.width * scale, dh = bs.height * scale
        bg.draw(in: NSRect(x: (W - dw) / 2, y: (H - dh) / 2, width: dw, height: dh),
                from: .zero, operation: .sourceOver, fraction: t.backgroundOpacity)
    }

    // The theme's fontSize is expressed against a 2160-high canvas.
    let scale = H / 2160
    let size = t.fontSize * scale
    let font = NSFont(name: t.fontName, size: size)
        ?? NSFont.systemFont(ofSize: size, weight: weight(t.weightRaw))

    let para = NSMutableParagraphStyle()
    para.alignment = .center
    para.lineHeightMultiple = max(t.lineSpacing, 0.6)

    var attrs: [NSAttributedString.Key: Any] = [
        .font: font, .foregroundColor: t.textColor, .paragraphStyle: para,
    ]
    if t.shadowOn {
        let sh = NSShadow()
        sh.shadowColor = t.shadowColor
        sh.shadowBlurRadius = t.shadowRadius * scale * 2.2
        sh.shadowOffset = .zero
        attrs[.shadow] = sh
    }

    let text = NSAttributedString(string: sampleVerse, attributes: attrs)
    let bounds = text.boundingRect(with: NSSize(width: W * 0.86, height: .greatestFiniteMagnitude),
                                  options: [.usesLineFragmentOrigin])
    text.draw(with: NSRect(x: W * 0.07, y: (H - bounds.height) / 2 + H * 0.05,
                           width: W * 0.86, height: bounds.height),
              options: [.usesLineFragmentOrigin])

    var refAttrs = attrs
    refAttrs[.font] = NSFont(name: t.fontName, size: size * 0.42)
        ?? NSFont.systemFont(ofSize: size * 0.42, weight: .regular)
    NSAttributedString(string: sampleRef, attributes: refAttrs)
        .draw(with: NSRect(x: W * 0.07, y: H * 0.11, width: W * 0.86, height: size),
              options: [.usesLineFragmentOrigin])

    // Name plate, so a contact sheet is readable. Not part of the theme.
    let plate: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 22, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]
    let label = NSAttributedString(string: t.name, attributes: plate)
    let lw = label.size().width + 26
    NSColor(white: 0, alpha: 0.55).setFill()
    NSBezierPath(roundedRect: NSRect(x: 18, y: H - 52, width: lw, height: 34),
                 xRadius: 8, yRadius: 8).fill()
    label.draw(at: NSPoint(x: 31, y: H - 44))

    img.unlockFocus()
    return img
}

let packages = ((try? FileManager.default.contentsOfDirectory(at: packDir, includingPropertiesForKeys: nil)) ?? [])
    .filter { $0.pathExtension == "tptheme" }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

var made = 0
for pkg in packages {
    guard let theme = load(pkg) else { print("skip \(pkg.lastPathComponent)"); continue }
    let img = render(theme)
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86])
    else { continue }
    let safe = theme.name.replacingOccurrences(of: " ", with: "-")
    try? data.write(to: outDir.appendingPathComponent("\(safe).jpg"))
    made += 1
}
print("rendered \(made) previews into \(outDir.path)")
