//
//  SessionRunner.swift
//  TopPresenter
//
//  THE one presenter for schedule sessions — ScheduleView and SchedulePreviewPanel
//  both drive this instead of calling pm.show* themselves. App-global: there is ONE
//  live output, so there is ONE running session, whichever tab controls it.
//
//  A session item expands into slides at PRESENT time (a song → its slides built
//  with the operator's current song options; bible/media/text → one slide), so
//  next/prev walk slide-by-slide through the whole service. Missing items (deleted
//  library content) are skipped by navigation but stay visible in the UI.
//

import Foundation
import SwiftData
import Observation

@Observable
final class SessionRunner {
    private(set) var activeScheduleID: UUID?
    private(set) var itemIndex = 0
    private(set) var slideIndex = 0
    var isRunning: Bool { activeScheduleID != nil }

    // Wired once in TopPresenterApp.init — weak where the object also owns us.
    @ObservationIgnored weak var pm: PresentationManager?
    @ObservationIgnored weak var video: VideoPlayerService?
    @ObservationIgnored weak var audio: AudioPlayerManager?
    /// For resolving `{{…}}` tokens in session TEXT items (dynamic slides).
    @ObservationIgnored weak var searchIndex: SearchIndex?

    // MARK: Lifecycle

    func start(_ schedule: ServiceSchedule, context: ModelContext) {
        activeScheduleID = schedule.id
        itemIndex = 0
        slideIndex = 0
        // Land on the first presentable item.
        if slideCount(at: 0, in: schedule, context: context) == 0 {
            _ = advanceItem(direction: +1, in: schedule, context: context)
        }
        presentCurrent(context: context)
    }

    func stop() {
        activeScheduleID = nil
        itemIndex = 0
        slideIndex = 0
    }

    // MARK: Navigation

    func next(context: ModelContext) {
        guard let schedule = activeSchedule(context) else { return }
        if slideIndex + 1 < slideCount(at: itemIndex, in: schedule, context: context) {
            slideIndex += 1
        } else if !advanceItem(direction: +1, in: schedule, context: context) {
            return   // already at the end
        }
        presentCurrent(context: context)
    }

    func previous(context: ModelContext) {
        guard let schedule = activeSchedule(context) else { return }
        if slideIndex > 0 {
            slideIndex -= 1
        } else if advanceItem(direction: -1, in: schedule, context: context) {
            // Entering the previous item from the back — land on its LAST slide.
            slideIndex = max(slideCount(at: itemIndex, in: schedule, context: context) - 1, 0)
        } else {
            return   // already at the start
        }
        presentCurrent(context: context)
    }

    /// Jump straight to an item (running-order click); presents immediately.
    func jump(toItem index: Int, context: ModelContext) {
        guard let schedule = activeSchedule(context) else { return }
        let items = schedule.sortedItems
        guard !items.isEmpty else { return }
        itemIndex = min(max(index, 0), items.count - 1)
        slideIndex = 0
        presentCurrent(context: context)
    }

    // MARK: Presentation

    func presentCurrent(context: ModelContext) {
        guard let schedule = activeSchedule(context) else { return }
        let items = schedule.sortedItems
        guard itemIndex >= 0, itemIndex < items.count else { return }
        present(item: items[itemIndex], slide: slideIndex, context: context)
    }

    /// One-shot: present an item OUTSIDE a running session (Show / double-click
    /// while not running) — same resolution + present path as the runner.
    func presentOnce(_ item: ScheduleItem, context: ModelContext) {
        present(item: item, slide: 0, context: context)
    }

    /// The current item's resolution — the panel reads this for its preview.
    func currentResolution(context: ModelContext) -> SessionResolution? {
        guard let schedule = activeSchedule(context) else { return nil }
        let items = schedule.sortedItems
        guard itemIndex >= 0, itemIndex < items.count else { return nil }
        return SessionService.resolve(items[itemIndex], context: context)
    }

    /// How many slides an item expands to right now (0 = missing/unpresentable).
    func slideCount(of item: ScheduleItem, context: ModelContext) -> Int {
        switch SessionService.resolve(item, context: context) {
        case .song(let song, let version):
            return max(songSlides(song: song, version: version).count, 1)
        case .bible, .media, .text, .blank:
            return 1
        case .missing:
            return 0
        }
    }

    // MARK: - Internals

    private func activeSchedule(_ context: ModelContext) -> ServiceSchedule? {
        guard let id = activeScheduleID else { return nil }
        var d = FetchDescriptor<ServiceSchedule>(predicate: #Predicate { $0.id == id })
        d.fetchLimit = 1
        return (try? context.fetch(d))?.first
    }

    private func slideCount(at index: Int, in schedule: ServiceSchedule, context: ModelContext) -> Int {
        let items = schedule.sortedItems
        guard index >= 0, index < items.count else { return 0 }
        return slideCount(of: items[index], context: context)
    }

    /// Move itemIndex to the nearest presentable item in `direction`,
    /// skipping missing ones. Returns false when none exists.
    private func advanceItem(direction: Int, in schedule: ServiceSchedule, context: ModelContext) -> Bool {
        let items = schedule.sortedItems
        var idx = itemIndex + direction
        while idx >= 0 && idx < items.count {
            if slideCount(of: items[idx], context: context) > 0 {
                itemIndex = idx
                slideIndex = 0
                return true
            }
            idx += direction
        }
        return false
    }

    private func present(item: ScheduleItem, slide: Int, context: ModelContext) {
        guard let pm else { return }
        switch SessionService.resolve(item, context: context) {
        case let .bible(text, reference, translationName):
            pm.showBibleVerse(text: text, reference: reference, translationName: translationName)

        case let .song(song, version):
            let slides = songSlides(song: song, version: version)
            guard !slides.isEmpty else {
                pm.showSongVerse(text: item.content, title: song.title, verseLabel: item.subtitle)
                return
            }
            let s = slides[min(max(slide, 0), slides.count - 1)]
            pm.showSongVerse(text: s.text, title: song.title, verseLabel: s.label,
                             slideIndex: s.index, slideCount: s.total,
                             song: song, version: version, lines: s.lines)

        case let .media(mediaItem):
            guard let video, let audio else { return }
            MediaPresenter.present(mediaItem, pm: pm, video: video, audio: audio)

        case let .text(title, content):
            // Session text items are dynamic slides too: templates resolve at
            // PRESENT time through the same token pipeline as Custom Slides.
            // No tokens → straight to screen (zero extra latency).
            if let searchIndex,
               SlideTemplate.containsTokens(title) || SlideTemplate.containsTokens(content) {
                let ctx = SlideTokenContext(index: searchIndex, modelContext: context)
                Task { [weak pm] in
                    let resolved = await SlideTokenResolver.resolveSlide(
                        title: title, subtitle: "", content: content, context: ctx)
                    pm?.showCustomText(text: resolved.content, title: resolved.title)
                }
            } else {
                pm.showCustomText(text: content, title: title)
            }

        case .blank:
            pm.goBlack()

        case .missing:
            break   // navigation skips these; a direct jump is a no-op
        }
    }

    /// Song slides built with the operator's CURRENT song options — a session
    /// stores intent, so lyric edits and slide-length changes flow through.
    private func songSlides(song: Song, version: SongVersion?) -> [SongSlide] {
        let d = UserDefaults.standard
        let maxLines = (d.object(forKey: "song_maxLinesPerSlide") as? Int) ?? 6
        let bilingual = (d.object(forKey: "song_bilingual") as? Bool) ?? false
        let bracket = d.string(forKey: "song_repeatBracket") ?? "none"
        let countStyle = d.string(forKey: "song_repeatCount") ?? "times"
        return buildSongSlides(song: song, version: version ?? song.activeVersion,
                               maxLines: maxLines, bilingual: bilingual, language: nil,
                               bracket: bracket, countStyle: countStyle)
    }
}
