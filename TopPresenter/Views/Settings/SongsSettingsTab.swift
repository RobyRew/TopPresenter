//
//  SongsSettingsTab.swift
//  TopPresenter
//
//  Song defaults + the operator's result-priority ladder.
//

import SwiftUI

struct SongsSettingsTab: View {
    @Environment(SongPriorityStore.self) private var priority
    @Environment(SearchIndex.self) private var index

    @AppStorage("song_maxLinesPerSlide") private var maxLines = 6
    @AppStorage("song_sectionLabelsInAppLanguage") private var labelsInAppLanguage = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            defaultsSection
            Divider()
            prioritySection
        }
    }

    // MARK: Defaults

    private var defaultsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Implicit", comment: "Settings section — song defaults"))
                .font(.headline)

            Stepper(value: $maxLines, in: 2...12) {
                Text(String(localized: "Linii per slide: \(maxLines)", comment: "Setting — lines per slide"))
            }
            Text(String(localized: "Câte rânduri de versuri intră pe un slide înainte ca strofa să fie tăiată în două.",
                        comment: "Setting hint — lines per slide"))
                .font(.caption).foregroundStyle(.secondary)

            Toggle(isOn: $labelsInAppLanguage) {
                Text(String(localized: "Etichete de secțiune în limba aplicației",
                            comment: "Setting — localized section labels"))
            }
            Text(String(localized: "Strofele se numerotează („2/4”) și refrenul își ia numele din limba aplicației, în loc de eticheta scrisă în fișierul importat.",
                        comment: "Setting hint — localized section labels"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Priority

    @ViewBuilder
    private var prioritySection: some View {
        @Bindable var store = priority

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(String(localized: "Prioritatea rezultatelor", comment: "Settings section — result priority"))
                    .font(.headline)
                Spacer()
                Toggle("", isOn: $store.rules.isEnabled).labelsHidden()
            }
            Text(String(localized: "Când mai multe cântece se potrivesc la fel de bine cu ce ai căutat, ordinea de aici decide care apare primul. Categoriile se verifică de sus în jos; un cântec intră în prima categorie care i se potrivește.",
                        comment: "Settings hint — result priority"))
                .font(.caption).foregroundStyle(.secondary)

            ForEach(Array(store.rules.bands.enumerated()), id: \.element.id) { position, band in
                bandEditor(position: position, band: band)
            }
            .disabled(!store.rules.isEnabled)

            HStack {
                Button {
                    store.rules.bands.append(
                        SongPriorityBand(name: String(localized: "Categorie nouă", comment: "New priority band"),
                                         facet: .songbook))
                } label: {
                    Label(String(localized: "Adaugă categorie", comment: "Button"), systemImage: "plus")
                }
                Spacer()
                Button(String(localized: "Restabilește implicit", comment: "Button")) {
                    store.resetToStandard()
                }
            }
            .disabled(!store.rules.isEnabled)
        }
    }

    @ViewBuilder
    private func bandEditor(position: Int, band: SongPriorityBand) -> some View {
        @Bindable var store = priority
        let binding = Binding(
            get: { store.rules.bands.indices.contains(position) ? store.rules.bands[position] : band },
            set: { if store.rules.bands.indices.contains(position) { store.rules.bands[position] = $0 } })

        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "După", comment: "Picker — which song property a band groups by"),
                       selection: binding.facet) {
                    ForEach(SongFacet.allCases) { facet in
                        Text(facet.localizedName).tag(facet)
                    }
                }
                .onChange(of: binding.wrappedValue.facet) { _, _ in
                    // The listed values belong to the OLD facet; keeping them
                    // would silently match nothing.
                    binding.wrappedValue.values = []
                }

                Toggle(isOn: binding.restrictedToValues) {
                    Text(String(localized: "Doar valorile de mai jos", comment: "Toggle — restrict band to listed values"))
                }
                .toggleStyle(.checkbox)
                Text(binding.wrappedValue.restrictedToValues
                     ? String(localized: "Intră doar cântecele cu una dintre valorile listate.",
                              comment: "Hint — restricted band")
                     : String(localized: "Intră orice cântec care are această proprietate; cele listate trec în față.",
                              comment: "Hint — open band"))
                    .font(.caption).foregroundStyle(.secondary)

                valueList(binding)
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Text("\(position + 1).")
                    .font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                TextField("", text: binding.name).textFieldStyle(.roundedBorder).frame(maxWidth: 220)
                Text(binding.wrappedValue.facet.localizedName)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Toggle("", isOn: binding.isEnabled).labelsHidden().controlSize(.mini)
                Button { move(position, by: -1) } label: { Image(systemName: "chevron.up") }
                    .buttonStyle(.borderless).disabled(position == 0)
                Button { move(position, by: 1) } label: { Image(systemName: "chevron.down") }
                    .buttonStyle(.borderless)
                    .disabled(position >= store.rules.bands.count - 1)
                Button(role: .destructive) {
                    store.rules.bands.remove(at: position)
                } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder
    private func valueList(_ band: Binding<SongPriorityBand>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(band.wrappedValue.values.enumerated()), id: \.offset) { i, value in
                HStack(spacing: 6) {
                    Text("\(i + 1)").font(.caption.monospacedDigit()).foregroundStyle(.tertiary)
                        .frame(width: 16, alignment: .trailing)
                    Text(value).lineLimit(1)
                    Spacer()
                    Button { swapValue(band, i, i - 1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(i == 0)
                    Button { swapValue(band, i, i + 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless)
                        .disabled(i >= band.wrappedValue.values.count - 1)
                    Button(role: .destructive) {
                        band.wrappedValue.values.remove(at: i)
                    } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
                .font(.callout)
            }

            // Offered from the LIBRARY rather than typed: a book name that does
            // not match the songs exactly ranks nothing, and there is no way to
            // tell from the settings screen that it silently did nothing.
            let options = suggestions(for: band.wrappedValue.facet,
                                      excluding: Set(band.wrappedValue.values.map(searchFold)))
            Menu {
                if options.isEmpty {
                    Text(String(localized: "Nimic în bibliotecă", comment: "Empty value suggestions"))
                } else {
                    ForEach(options, id: \.self) { option in
                        Button(option) { band.wrappedValue.values.append(option) }
                    }
                }
            } label: {
                Label(String(localized: "Adaugă valoare", comment: "Button"), systemImage: "plus.circle")
                    .font(.caption)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(options.isEmpty)
        }
        .padding(.leading, 4)
    }

    // MARK: Helpers

    private func move(_ position: Int, by delta: Int) {
        let target = position + delta
        guard priority.rules.bands.indices.contains(position),
              priority.rules.bands.indices.contains(target) else { return }
        priority.rules.bands.swapAt(position, target)
    }

    private func swapValue(_ band: Binding<SongPriorityBand>, _ a: Int, _ b: Int) {
        guard band.wrappedValue.values.indices.contains(a),
              band.wrappedValue.values.indices.contains(b) else { return }
        band.wrappedValue.values.swapAt(a, b)
    }

    /// The values this facet actually has in the library, most common first.
    ///
    /// Read off the search projections, so it costs no SwiftData work and shows
    /// exactly the strings ranking will compare against.
    private func suggestions(for facet: SongFacet, excluding taken: Set<String>) -> [String] {
        var counts: [String: Int] = [:]
        for entry in index.songs {
            let value = facet.value(of: entry)
            guard !value.isEmpty, !taken.contains(searchFold(value)) else { continue }
            counts[value, default: 0] += 1
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(40).map(\.key)
    }
}
