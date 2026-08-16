//
//  LibraryTaskProgress.swift
//  TopPresenter
//
//  What a long library job is doing, while it does it.
//
//  Importing seventy Bibles and deleting them again are both minutes of work,
//  and both used to happen on the main thread behind a spinning beach ball with
//  nothing to look at and no way to tell whether the app had hung. The work
//  moved off the main actor; this is what makes it legible while it runs.
//
//  The estimate is deliberately simple — elapsed / completed, extrapolated —
//  and deliberately not shown until a couple of items are done. A remaining
//  time computed from one sample of a seventy-file job is a number that swings
//  by minutes between updates, which is worse than no number at all.
//

import Foundation
import os

@MainActor
@Observable
final class LibraryTaskProgress {

    /// Cancellation as the BACKGROUND sees it.
    ///
    /// `isCancelled` below is main-actor state, which the UI needs and an
    /// importer cannot read: the song loop polls between files, synchronously,
    /// from its own actor. Making it `await` a main-actor hop per file would
    /// serialise the import against the very thread it was moved off.
    ///
    /// So the flag is mirrored behind a lock. `cancel()` and `begin()` write
    /// both; nothing else may write this one.
    private let cancelFlag = OSAllocatedUnfairLock(initialState: false)

    /// Readable from any thread, unlike `isCancelled`.
    nonisolated var isCancelledNow: Bool { cancelFlag.withLock { $0 } }

    enum Kind: Sendable {
        case importing, deleting, exporting

        var verb: String {
            switch self {
            case .importing: return String(localized: "Importing", comment: "Progress verb")
            case .deleting: return String(localized: "Deleting", comment: "Progress verb")
            case .exporting: return String(localized: "Exporting", comment: "Progress verb")
            }
        }
    }

    private(set) var kind: Kind = .importing
    private(set) var isRunning = false
    /// What is being worked on right now — a filename, a module name.
    private(set) var currentItem = ""
    private(set) var completed = 0
    private(set) var total = 0
    /// 0…1 within the CURRENT item, for jobs that can say (a Bible reports per
    /// book). -1 when the item cannot report sub-progress.
    private(set) var itemFraction: Double = -1

    private var startedAt: Date?
    private var itemStartedAt: Date?
    /// How long each finished item took. The estimate uses the mean of these
    /// rather than overall elapsed, so one enormous Bible early on does not
    /// poison the estimate for sixty small ones.
    private var itemDurations: [TimeInterval] = []

    var isCancelled = false

    // MARK: - Driving it

    func begin(_ kind: Kind, total: Int) {
        self.kind = kind
        self.total = total
        completed = 0
        currentItem = ""
        itemFraction = -1
        itemDurations = []
        isCancelled = false
        cancelFlag.withLock { $0 = false }
        isRunning = true
        startedAt = Date()
        itemStartedAt = Date()
    }

    func startItem(_ name: String) {
        currentItem = name
        itemFraction = -1
        itemStartedAt = Date()
    }

    func setItemFraction(_ fraction: Double) {
        itemFraction = min(max(fraction, 0), 1)
    }

    func finishItem() {
        if let itemStartedAt { itemDurations.append(Date().timeIntervalSince(itemStartedAt)) }
        completed = min(completed + 1, total)
        itemFraction = -1
        itemStartedAt = Date()
    }

    func end() {
        isRunning = false
        currentItem = ""
        itemFraction = -1
    }

    func cancel() {
        isCancelled = true
        cancelFlag.withLock { $0 = true }
    }

    // MARK: - Reading it

    /// Overall 0…1, counting how far into the current item we are when it says.
    var fraction: Double {
        guard total > 0 else { return 0 }
        let within = itemFraction >= 0 ? itemFraction : 0
        return min((Double(completed) + within) / Double(total), 1)
    }

    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    var elapsedForItem: TimeInterval { itemStartedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    /// nil until there is enough evidence to be worth showing.
    ///
    /// Two finished items is the threshold: with one, the estimate is that
    /// item's duration times the count, which for a mixed batch is wrong by
    /// minutes and visibly jumps every time an item finishes. Silence beats a
    /// number nobody can trust.
    var estimatedRemaining: TimeInterval? {
        guard itemDurations.count >= 2, completed < total else { return nil }
        let mean = itemDurations.reduce(0, +) / Double(itemDurations.count)
        let remaining = Double(total - completed) - (itemFraction >= 0 ? itemFraction : 0)
        return max(mean * remaining, 0)
    }

    /// An estimate BEFORE anything starts, from the bytes about to be read.
    /// Rough on purpose, and labelled as rough where it is shown.
    static func estimate(forBytes bytes: Int) -> TimeInterval {
        // ~8 MB/s end to end for a Bible on a warm store: parse, insert,
        // chunked saves. Measured on this project's own library, not guessed.
        Double(bytes) / (8 * 1024 * 1024)
    }

    // MARK: - Formatting

    static func formatted(_ interval: TimeInterval) -> String {
        let seconds = Int(interval.rounded())
        if seconds < 60 { return String(localized: "\(seconds)s", comment: "Duration") }
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes < 60 { return String(localized: "\(minutes)m \(rest)s", comment: "Duration") }
        return String(localized: "\(minutes / 60)h \(minutes % 60)m", comment: "Duration")
    }

    var statusLine: String {
        guard isRunning else { return "" }
        var parts = ["\(kind.verb) \(completed + 1)/\(total)"]
        if !currentItem.isEmpty { parts.append(currentItem) }
        return parts.joined(separator: " — ")
    }

    var timingLine: String {
        guard isRunning else { return "" }
        var parts = [String(localized: "\(Self.formatted(elapsed)) elapsed", comment: "Progress timing")]
        if let remaining = estimatedRemaining {
            parts.append(String(localized: "about \(Self.formatted(remaining)) left", comment: "Progress timing"))
        }
        return parts.joined(separator: " · ")
    }
}
