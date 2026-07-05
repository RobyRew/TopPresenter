//
//  PinStore.swift
//  TopPresenter
//
//  Session-only song pins („Fixează sus"). App-global — one store shared by every
//  window/tab (LibraryManager is per-window, so pins there would diverge) — and
//  deliberately in-memory only: pins clear when the app quits, by construction.
//  No SwiftData field, no UserDefaults. Keyed by Song.id (ephemeral ⇒ UUID is fine).
//

import Foundation
import Observation

@Observable
final class PinStore {
    /// IDs of the songs pinned for this app run.
    private(set) var pinnedSongIDs: Set<UUID> = []

    var hasPins: Bool { !pinnedSongIDs.isEmpty }

    func isPinned(_ id: UUID) -> Bool { pinnedSongIDs.contains(id) }

    func togglePin(_ id: UUID) {
        if pinnedSongIDs.contains(id) {
            pinnedSongIDs.remove(id)
        } else {
            pinnedSongIDs.insert(id)
        }
    }

    func clearPins() { pinnedSongIDs.removeAll() }

    /// Splits an already-filtered/sorted list into (pinned, rest), preserving the
    /// input order in both halves. Pure + static so it's unit-testable.
    /// (MainActor like its callers — Song is a @Model.)
    static func partition(_ songs: [Song], pinnedIDs: Set<UUID>) -> (pinned: [Song], rest: [Song]) {
        guard !pinnedIDs.isEmpty else { return ([], songs) }
        var pinned: [Song] = []
        var rest: [Song] = []
        for song in songs {
            if pinnedIDs.contains(song.id) { pinned.append(song) } else { rest.append(song) }
        }
        return (pinned, rest)
    }
}
