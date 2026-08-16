//
//  PDFPageRenderer.swift
//  TopPresenter
//
//  Turning a PDF page into something the output can show.
//
//  WHY PDF AND NOT POWERPOINT
//
//  There is no macOS API that renders a .pptx slide. Quick Look gives one
//  thumbnail of the first page with no per-slide control; driving Keynote over
//  AppleScript needs Keynote installed and is hostile to the sandbox; rendering
//  DrawingML properly is a graphics engine, not a feature. PDF, by contrast, is
//  PDFKit — a system framework, no dependency, and every one of those tools
//  exports to it in two clicks.
//
//  HOW IT DRAWS
//
//  Into a raw CGContext rather than via `NSImage.lockFocus()`, because focus
//  locking is an AppKit drawing session that does not belong on a background
//  thread — and thumbnails are generated off the main thread on purpose.
//
//  The page is filled WHITE first. PDF pages have no background of their own,
//  so a page whose text is black composites onto transparency and arrives at
//  the projector as black-on-black.
//

import Foundation
import PDFKit

nonisolated enum PDFPageRenderer {

    /// How many pages, or 0 if the file will not open as a PDF.
    static func pageCount(of url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    /// Render one page, scaled so its LONG edge is `maxPixels`.
    ///
    /// - Parameter page: zero-based.
    /// - Returns: nil when the file is not a PDF, the page does not exist, or
    ///   the bitmap could not be allocated.
    static func render(url: URL, page index: Int, maxPixels: CGFloat = 2400) -> NSImage? {
        guard let document = PDFDocument(url: url),
              index >= 0, index < document.pageCount,
              let page = document.page(at: index) else { return nil }
        return render(page: page, maxPixels: maxPixels)
    }

    static func render(page: PDFPage, maxPixels: CGFloat) -> NSImage? {
        let box = PDFDisplayBox.cropBox   // what a reader shows, not the full sheet
        let bounds = page.bounds(for: box)
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        // A rotated page reports its UNROTATED bounds, so the output size has to
        // swap width and height itself — otherwise landscape scans come out
        // squashed into a portrait bitmap.
        let quarterTurned = abs(page.rotation / 90) % 2 == 1
        let visible = quarterTurned
            ? CGSize(width: bounds.height, height: bounds.width)
            : bounds.size

        let scale = min(maxPixels / max(visible.width, visible.height), 4)
        let pixelWidth = Int((visible.width * scale).rounded())
        let pixelHeight = Int((visible.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.scaleBy(x: scale, y: scale)
        // `drawPage` applies the page's own rotation and box origin; the context
        // just has to be the right size and scale for it.
        page.draw(with: box, to: context)

        guard let cgImage = context.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: visible.width, height: visible.height))
    }

    /// Grid-sized render of page one, for the library tile.
    static func thumbnail(url: URL) -> NSImage? {
        render(url: url, page: 0, maxPixels: 640)
    }
}
