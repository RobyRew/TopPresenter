//
//  SlideDeckArchive.swift
//  TopPresenter
//
//  .tpslides — the format Custom Slides never had.
//
//  Custom Slides could neither import nor export: the announcements someone
//  spent an evening writing existed on exactly one machine, and moving them
//  meant retyping them. Structurally identical to SessionArchive, and for the
//  same reasons — flat JSON, a schemaVersion, `decodeIfPresent` everywhere so
//  a file written by a newer build still opens in an older one.
//
//  Identity is per SLIDE, not per deck. A deck is a loose collection someone
//  adds to over months, so "I already have this deck" is rarely the question;
//  "I already have this slide" is. Re-importing a deck you extended elsewhere
//  brings in what is new and leaves the rest alone.
//

import Foundation
import SwiftData

struct SlideDeckArchive: Codable {
    var schemaVersion = TopPresenterHeader.schemaVersion
    var format = TopPresenterFormat.slides.marker
    var appVersion = ""
    var exportedAt = ""
    var slides: [Slide] = []

    struct Slide: Codable {
        var title = ""
        var content = ""
        var subtitle = ""
        var slideType = "text"
        var order = 0

        init() {}

        init(_ slide: PresentationSlide) {
            title = slide.title
            content = slide.content
            subtitle = slide.subtitle
            slideType = slide.slideType
            order = slide.order
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
            content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
            subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
            slideType = try c.decodeIfPresent(String.self, forKey: .slideType) ?? "text"
            order = try c.decodeIfPresent(Int.self, forKey: .order) ?? 0
        }

        /// What makes two slides the same slide. Not the id — a slide arriving
        /// from another library has one of its own — and not the title, since
        /// a deck is full of slides called "Anunțuri".
        var contentDigest: String {
            ContentFingerprint.digest(of: [title, subtitle, content, slideType].joined(separator: "\u{1}"))
        }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? TopPresenterHeader.schemaVersion
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? TopPresenterFormat.slides.marker
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion) ?? ""
        exportedAt = try c.decodeIfPresent(String.self, forKey: .exportedAt) ?? ""
        slides = try c.decodeIfPresent([Slide].self, forKey: .slides) ?? []
    }
}

enum SlideDeckArchiveService {
    static let fileExtension = TopPresenterFormat.slides.fileExtension

    struct ImportResult {
        var imported: [PresentationSlide] = []
        /// Slides already in the library, by title — reported, not swallowed.
        var skipped: [String] = []
    }

    static func export(_ slides: [PresentationSlide]) throws -> Data {
        var archive = SlideDeckArchive()
        archive.appVersion = TopPresenterHeader.appVersion
        archive.exportedAt = ISO8601DateFormatter().string(from: Date())
        archive.slides = slides.sorted { $0.order < $1.order }.map(SlideDeckArchive.Slide.init)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(archive)
    }

    @discardableResult
    static func importDeck(_ data: Data, context: ModelContext) throws -> ImportResult {
        // Identity check FIRST and strictly: the resilient decoder defaults
        // every missing key, so it would happily "decode" a stranger's JSON
        // into an empty deck and report success.
        struct FormatProbe: Codable { var format: String? }
        let probe = try JSONDecoder().decode(FormatProbe.self, from: data)
        guard probe.format == TopPresenterFormat.slides.marker else {
            throw NSError(domain: "TopPresenter.SlideDeckArchive", code: 1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "This file is not a TopPresenter slide deck.",
                                                  comment: "Import error"),
            ])
        }
        let archive = try JSONDecoder().decode(SlideDeckArchive.self, from: data)

        let existing = (try? context.fetch(FetchDescriptor<PresentationSlide>())) ?? []
        var existingDigests = Set(existing.map {
            SlideDeckArchive.Slide($0).contentDigest
        })
        var nextOrder = (existing.map(\.order).max() ?? -1) + 1

        var result = ImportResult()
        for archived in archive.slides.sorted(by: { $0.order < $1.order }) {
            guard existingDigests.insert(archived.contentDigest).inserted else {
                result.skipped.append(archived.title)
                continue
            }
            let slide = PresentationSlide(
                title: archived.title, content: archived.content,
                subtitle: archived.subtitle, slideType: archived.slideType,
                order: nextOrder
            )
            nextOrder += 1
            context.insert(slide)
            result.imported.append(slide)
        }
        try context.save()
        return result
    }
}
