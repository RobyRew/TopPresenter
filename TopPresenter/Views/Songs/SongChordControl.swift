//
//  SongChordControl.swift
//  TopPresenter
//
//  Compact transpose / capo control shown in the song detail header for songs that
//  carry chords. DISPLAY-ONLY: it never edits the stored song — it drives
//  PresentationManager's ephemeral chord state (transpose semitones + capo), which
//  the chords casetá renders live on the output. Surfaces capo suggestions and the
//  recommended keys captured from the scrapers' `_extensions`.
//

import SwiftUI

/// True when any version of the song has at least one chord.
func songHasChords(_ song: Song) -> Bool {
    for v in song.versions {
        for s in v.sections where s.lines.contains(where: { !$0.chords.isEmpty }) { return true }
    }
    return false
}

struct SongChordControl: View {
    let song: Song
    let version: SongVersion?

    @Environment(PresentationManager.self) private var pm
    @State private var showPopover = false

    // MARK: Derived state

    private var songKey: String {
        HistoryStore.songKey(ccli: song.ccliNumber, title: song.title, source: song.collection?.sourceFormat ?? "")
    }
    private var originalKey: String {
        if let k = version?.key, !k.isEmpty { return k }
        return song.key
    }
    private var applies: Bool { pm.chordTransposeApplies(to: songKey) }
    private var semitones: Int { applies ? pm.chordTransposeSemitones : 0 }
    private var capo: Int { applies ? pm.chordCapo : 0 }

    private var soundingKey: String {
        guard !originalKey.isEmpty else { return "" }
        return ChordTransposer.transpose(originalKey, by: semitones,
                                         preferFlats: ChordTransposer.preferFlats(forKey: originalKey))
    }
    private var shapeKey: String {
        guard !soundingKey.isEmpty, capo > 0 else { return soundingKey }
        return ChordTransposer.transpose(soundingKey, by: -capo, preferFlats: ChordTransposer.preferFlats(forKey: soundingKey))
    }
    private var recommendedKeys: [String] {
        ChordTransposer.recommendedKeys(fromExtensionsJSON: song.extensionsJSON)
    }

    // MARK: Mutations (all pinned to this song)

    private func bump(_ delta: Int) {
        pm.setChordTranspose(semitones: semitones + delta, forSongKey: songKey)
    }
    private func setSounding(_ key: String) {
        let base = originalKey.isEmpty ? "C" : originalKey
        var s = ChordTransposer.semitones(fromKey: base, toKey: key)
        if s > 6 { s -= 12 }   // pick the nearer direction
        pm.setChordTranspose(semitones: s, forSongKey: songKey)
    }
    private var capoBinding: Binding<Int> {
        Binding(get: { capo }, set: { pm.setChordTranspose(capo: $0, forSongKey: songKey) })
    }
    private var chordsVisibleBinding: Binding<Bool> {
        Binding(get: { pm.isSectionVisible(.chords, in: "song") },
                set: { pm.setSectionVisible($0, for: .chords, in: "song") })
    }

    // MARK: Body

    var body: some View {
        Button { showPopover = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "guitars.fill").font(.caption2)
                Text(chipLabel).font(.caption)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background((semitones != 0 || capo > 0) ? AnyShapeStyle(appAccent.opacity(0.18)) : AnyShapeStyle(.quaternary), in: Capsule())
            .lineLimit(1)
        }
        .buttonStyle(.plain)
        .help(String(localized: "Acorduri și transpunere", comment: "Tooltip"))
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            popover.padding(14).frame(width: 290)
        }
    }

    private var chipLabel: String {
        var s = soundingKey.isEmpty ? String(localized: "Acorduri", comment: "Chords chip") : soundingKey
        if semitones != 0 { s += String(format: " (%+d)", semitones) }
        if capo > 0 { s += " · Capo \(capo)" }
        return s
    }

    // MARK: Popover

    private var popover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(String(localized: "Acorduri", comment: "Popover title"), systemImage: "guitars.fill")
                    .font(.headline)
                Spacer()
                if semitones != 0 || capo > 0 {
                    Button(String(localized: "Resetează", comment: "Reset transpose")) {
                        pm.setChordTranspose(semitones: 0, capo: 0, forSongKey: songKey)
                    }
                    .controlSize(.small)
                }
            }

            if !originalKey.isEmpty {
                HStack {
                    Text(String(localized: "Ton original", comment: "Original key")).foregroundStyle(.secondary)
                    Spacer()
                    Text(originalKey).fontWeight(.semibold)
                }.font(.caption)
            }

            // Transpose
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "Transpune", comment: "Transpose")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button { bump(-1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                        .buttonStyle(.plain).disabled(semitones <= -11)
                    Spacer()
                    VStack(spacing: 0) {
                        Text(soundingKey.isEmpty ? "—" : soundingKey)
                            .font(.title3.bold()).foregroundStyle(appAccent)
                        Text(String(format: "%+d", semitones) + " " + String(localized: "semitonuri", comment: "semitones"))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { bump(1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                        .buttonStyle(.plain).disabled(semitones >= 11)
                }
                Menu {
                    ForEach(ChordTransposer.keyWheel, id: \.self) { k in
                        Button { setSounding(k) } label: {
                            if k == soundingKey { Label(k, systemImage: "checkmark") } else { Text(k) }
                        }
                    }
                } label: {
                    Text(String(localized: "Alege tonul…", comment: "Pick key")).font(.caption)
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(originalKey.isEmpty)
            }

            // Capo
            Stepper(value: capoBinding, in: 0...11) {
                HStack {
                    Text(String(localized: "Capo", comment: "Capo"))
                    if capo > 0, !shapeKey.isEmpty {
                        Text(String(localized: "forme în \(shapeKey)", comment: "shapes in key"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(capo)").fontWeight(.semibold)
                }
            }
            .font(.callout)

            if !soundingKey.isEmpty {
                let suggestions = ChordTransposer.capoSuggestions(forSoundingKey: soundingKey)
                if !suggestions.isEmpty {
                    chipRow(String(localized: "Capo sugerat", comment: "Suggested capo"),
                            items: suggestions.map { s in (label: "Capo \(s.capo) · \(s.shapeKey)", action: { capoBinding.wrappedValue = s.capo }) })
                }
            }

            if !recommendedKeys.isEmpty {
                chipRow(String(localized: "Tonalități recomandate", comment: "Recommended keys"),
                        items: recommendedKeys.map { k in (label: k, action: { setSounding(k) }) })
            }

            Divider()
            Toggle(String(localized: "Arată acordurile pe ecran", comment: "Show chords on output"), isOn: chordsVisibleBinding)
                .font(.caption).toggleStyle(.switch).controlSize(.mini)
            Text(String(localized: "Doar afișare — nu modifică acordurile salvate.", comment: "Display-only note"))
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func chipRow(_ title: String, items: [(label: String, action: () -> Void)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        Button(item.label, action: item.action)
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }
            }
        }
    }
}
