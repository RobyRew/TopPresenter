//
//  SettingsView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Application settings — lives IN the main window (sidebar ▸ Settings, ⌘,)
/// like History does, not in a separate window. Header + segmented sections;
/// the „Avansat" section only exists after the 10-click unlock on the sidebar
/// Settings row (SidebarView.registerSettingsClick) and re-locks when the
/// user leaves Settings (AppState.selectedSidebarItem didSet).
struct SettingsContentView: View {
    @Environment(AppState.self) private var appState
    @State private var tab = "interface"

    private var advancedUnlocked: Bool { appState.advancedSettingsUnlocked }

    private struct SettingsTab: Identifiable {
        let id: String
        let label: String
    }

    private var tabs: [SettingsTab] {
        var out: [SettingsTab] = [
            .init(id: "interface", label: String(localized: "Interfață", comment: "Settings tab")),
            .init(id: "bible", label: String(localized: "Biblie", comment: "Settings tab")),
            .init(id: "importExport", label: String(localized: "Import / Export", comment: "Settings tab")),
            .init(id: "projection", label: String(localized: "Proiecție", comment: "Settings tab")),
            .init(id: "updates", label: String(localized: "Actualizări", comment: "Settings tab")),
        ]
        if advancedUnlocked {
            out.append(.init(id: "advanced", label: String(localized: "Avansat", comment: "Settings tab")))
        }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case "bible": BibleSettingsTab()
                    case "importExport": ImportExportSettingsTab()
                    case "projection": ProjectionSettingsTab()
                    case "updates": UpdatesSettingsTab()
                    case "advanced" where advancedUnlocked: AdvancedSettingsTab()
                    default: InterfaceSettingsTab()
                    }
                }
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: advancedUnlocked) { _, unlocked in
            if !unlocked && tab == "advanced" { tab = "interface" }
        }
        // The 10-click unlock (or any future deep link) lands directly on
        // the requested tab.
        .onAppear(perform: consumeTabRequest)
        .onChange(of: appState.settingsTabRequest) { _, _ in consumeTabRequest() }
    }

    private func consumeTabRequest() {
        guard let requested = appState.settingsTabRequest else { return }
        if requested != "advanced" || advancedUnlocked { tab = requested }
        appState.settingsTabRequest = nil
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gearshape").font(.title2).foregroundStyle(appAccent)
            VStack(alignment: .leading, spacing: 1) {
                Text(String(localized: "Setări", comment: "Settings title")).font(.headline)
                Text(String(localized: "Preferințele aplicației", comment: "Settings subtitle"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Picker("", selection: $tab) {
                ForEach(tabs) { t in
                    Text(t.label).tag(t.id)
                }
            }
            .pickerStyle(.segmented).labelsHidden().fixedSize()

            Spacer()
        }
        .padding(12)
    }
}

// MARK: - Interface Settings Tab
struct InterfaceSettingsTab: View {
    @AppStorage("startupSection") private var startupSection: String = "bible"
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    @AppStorage("forceTouchClearAction") private var forceTouchAction: String = "clearAll"
    @AppStorage("sidebarRowSizeOption") private var sidebarRowSizeRaw = "system"
    @AppStorage("sidebarCustomIconSize") private var sidebarCustomSize = 14.0

    var body: some View {
        @Bindable var store = AccentStore.shared

        Form {
            Section {
                colorRow(String(localized: "Culoare accent", comment: "Setting label"),
                         isSelected: { store.option == $0 },
                         select: { store.option = $0 },
                         custom: Binding(get: { store.customAccent },
                                         set: { store.customAccent = $0; store.option = .custom }),
                         customActive: store.option == .custom)

                Toggle(String(localized: "Evidențierea folosește accentul", comment: "Setting label"),
                       isOn: $store.highlightFollowsAccent)
                if !store.highlightFollowsAccent {
                    colorRow(String(localized: "Culoare evidențiere", comment: "Setting label"),
                             isSelected: { store.highlightOption == $0 },
                             select: { store.highlightOption = $0 },
                             custom: Binding(get: { store.customHighlight },
                                             set: { store.customHighlight = $0; store.highlightOption = .custom }),
                             customActive: store.highlightOption == .custom)
                }

                Picker(String(localized: "Iconițe bară laterală:", comment: "Setting label"), selection: $sidebarRowSizeRaw) {
                    Text(String(localized: "Sistem", comment: "Sidebar icon size option")).tag("system")
                    Text(String(localized: "Mic", comment: "Sidebar icon size option")).tag("small")
                    Text(String(localized: "Mediu", comment: "Sidebar icon size option")).tag("medium")
                    Text(String(localized: "Mare", comment: "Sidebar icon size option")).tag("large")
                    Text(String(localized: "Personalizat", comment: "Sidebar icon size option")).tag("custom")
                }
                if sidebarRowSizeRaw == "custom" {
                    HStack(spacing: 10) {
                        Slider(value: $sidebarCustomSize, in: 11...20, step: 1) {
                            Text(String(localized: "Mărime", comment: "Setting label"))
                        } minimumValueLabel: {
                            Image(systemName: "textformat.size.smaller")
                        } maximumValueLabel: {
                            Image(systemName: "textformat.size.larger")
                        }
                        Text(verbatim: "\(Int(sidebarCustomSize)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            } header: {
                Text(String(localized: "Aspect", comment: "Settings section"))
            } footer: {
                Text(String(localized: "„Sistem” urmează culoarea de accent și mărimea iconițelor din Setările macOS. Evidențierea colorează selecțiile (versete, capitole, rezultate).", comment: "Settings info"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(String(localized: "General", comment: "Settings section")) {
                Picker(String(localized: "Secțiunea de start:", comment: "Setting label"), selection: $startupSection) {
                    Text(String(localized: "Biblie", comment: "Option")).tag("bible")
                    Text(String(localized: "Cântece", comment: "Option")).tag("songs")
                    Text(String(localized: "Program", comment: "Option")).tag("schedule")
                }

                Toggle(String(localized: "Confirmă înainte de ștergere", comment: "Setting label"), isOn: $confirmBeforeDelete)
            }

            Section(String(localized: "Acțiuni Trackpad", comment: "Settings section")) {
                Picker(String(localized: "Force Touch pe butonul Clear:", comment: "Setting label"), selection: $forceTouchAction) {
                    Label(String(localized: "Golește Tot (ecran + selecție)", comment: "Force touch option"), systemImage: "trash")
                        .tag("clearAll")
                    Label(String(localized: "Golește și Ecran Negru", comment: "Force touch option"), systemImage: "moon.fill")
                        .tag("goBlack")
                    Label(String(localized: "Golește și Mergi la Biblie", comment: "Force touch option"), systemImage: "book.closed")
                        .tag("gotoBible")
                    Label(String(localized: "Golește și Mergi la Cântece", comment: "Force touch option"), systemImage: "music.note.list")
                        .tag("gotoSongs")
                    Label(String(localized: "Îngheață Prezentarea", comment: "Force touch option"), systemImage: "lock.fill")
                        .tag("freeze")
                }

                Text(String(localized: "Apasă tare (Force Touch) pe butonul Clear pentru a executa acțiunea selectată.", comment: "Settings info"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// One color channel row (macOS System Settings-style): preset swatches
    /// + a native ColorPicker well for the fully custom color.
    private func colorRow(_ label: String,
                          isSelected: @escaping (AppAccentOption) -> Bool,
                          select: @escaping (AppAccentOption) -> Void,
                          custom: Binding<Color>,
                          customActive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
            HStack(spacing: 9) {
                ForEach(AppAccentOption.presets) { option in
                    swatch(option, selected: isSelected(option)) { select(option) }
                }
                ColorPicker("", selection: custom, supportsOpacity: false)
                    .labelsHidden()
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(customActive ? 0.8 : 0), lineWidth: 2)
                            .padding(-3)
                    )
                    .help(String(localized: "Personalizat", comment: "Accent option"))
            }
        }
        .padding(.vertical, 2)
    }

    /// One preset swatch: filled circle, selection ring, „Sistem” shows the
    /// LIVE system accent with a tiny window glyph.
    private func swatch(_ option: AppAccentOption, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(option.color)
                    .frame(width: 20, height: 20)
                if option == .system {
                    Image(systemName: "macwindow")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                if selected {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.8), lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(option.localizedName)
        .accessibilityLabel(option.localizedName)
    }
}

// MARK: - Bible Settings Tab
struct BibleSettingsTab: View {
    @AppStorage("autoSelectFirstModule") private var autoSelectFirstModule: Bool = true
    @AppStorage("rememberLastModule") private var rememberLastModule: Bool = true
    // Same key BibleView's footnote chip uses, so this actually toggles footnotes.
    @AppStorage("bibleShowFootnotes") private var showFootnotes: Bool = false
    @AppStorage("showBookCategoryColors") private var showBookCategoryColors: Bool = true
    @AppStorage("showBookCategoryLabels") private var showBookCategoryLabels: Bool = true

    var body: some View {
        Form {
            Section(String(localized: "Module", comment: "Settings section")) {
                Toggle(String(localized: "Selectează automat primul modul", comment: "Setting label"), isOn: $autoSelectFirstModule)
                Toggle(String(localized: "Reține ultimul modul folosit", comment: "Setting label"), isOn: $rememberLastModule)
            }

            Section(String(localized: "Conținut", comment: "Settings section")) {
                Toggle(String(localized: "Afișează note de subsol", comment: "Setting label"), isOn: $showFootnotes)
            }

            Section(String(localized: "Categorii Cărți", comment: "Settings section")) {
                Toggle(String(localized: "Colorează cărțile pe categorii", comment: "Setting label"), isOn: $showBookCategoryColors)
                Toggle(String(localized: "Afișează eticheta categoriei", comment: "Setting label"), isOn: $showBookCategoryLabels)
                    .disabled(!showBookCategoryColors)

                if showBookCategoryColors {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Previzualizare categorii:", comment: "Settings info"))
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 6) {
                            ForEach(BibleBookCategory.allCases, id: \.self) { category in
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(category.color)
                                        .frame(width: 20, height: 14)
                                    Text(category.localizedName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Import / Export Settings
struct ImportExportSettingsTab: View {
    @AppStorage("defaultExportFormat") private var defaultExportFormat: String = SupportedExportFormat.topPresenter.rawValue
    @AppStorage("autoDetectFormat") private var autoDetectFormat: Bool = true
    @AppStorage("includeMetadataOnExport") private var includeMetadata: Bool = true
    @AppStorage("exportPrettyPrint") private var prettyPrint: Bool = true

    var body: some View {
        Form {
            Section(String(localized: "Import", comment: "Settings section")) {
                Toggle(String(localized: "Detectare automată a formatului", comment: "Setting label"), isOn: $autoDetectFormat)

                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "Formate de import suportate:", comment: "Settings info"))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    ForEach(SupportedBibleFormat.allCases) { format in
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(format.displayName)
                                .font(.caption)
                            Spacer()
                            Text(format.fileExtensions.map { ".\($0)" }.joined(separator: ", "))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Section(String(localized: "Export", comment: "Settings section")) {
                Picker(String(localized: "Format export implicit:", comment: "Setting label"), selection: $defaultExportFormat) {
                    ForEach(SupportedExportFormat.allCases) { format in
                        Text(format.displayName).tag(format.rawValue)
                    }
                }

                Toggle(String(localized: "Include metadata în exporturi", comment: "Setting label"), isOn: $includeMetadata)
                Toggle(String(localized: "Formatare JSON (pretty-print)", comment: "Setting label"), isOn: $prettyPrint)
            }

            Section(String(localized: "Despre Formate", comment: "Settings section")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                        Text(String(localized: "TopPresenter JSON este formatul recomandat pentru fidelitate completă, inclusiv referințe încrucișate, note de subsol și titluri de secțiuni.", comment: "Settings info"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Projection Settings Tab
// Output/screen hardware settings — moved here from the Theme Editor: they
// configure the device, not the look, so they don't belong in themes.
struct ProjectionSettingsTab: View {
    @Environment(PresentationManager.self) private var pm

    var body: some View {
        @Bindable var pmBinding = pm

        Form {
            Section(String(localized: "Ecran de Proiecție", comment: "Settings section")) {
                Picker(String(localized: "Ecran:", comment: "Setting label"), selection: $pmBinding.presentationScreenIndex) {
                    Text(String(localized: "Auto", comment: "Picker option"))
                        .tag(nil as Int?)
                    ForEach(Array(pm.availableScreens.enumerated()), id: \.offset) { index, screen in
                        Text(screen.localizedName).tag(index as Int?)
                    }
                }

                Button(String(localized: "Reîmprospătează ecranele", comment: "Button")) {
                    pm.refreshScreens()
                }

                Picker(String(localized: "Nivel fereastră:", comment: "Setting label"), selection: $pmBinding.windowLevel) {
                    Text(String(localized: "Normal", comment: "Window level option")).tag("normal")
                    Text(String(localized: "Floating", comment: "Window level option")).tag("floating")
                    Text(String(localized: "Always on Top", comment: "Window level option")).tag("alwaysOnTop")
                    Text(String(localized: "Behind Desktop", comment: "Window level option")).tag("behindDesktop")
                }
            }

            Section(String(localized: "Comportament", comment: "Settings section")) {
                Text(String(localized: "Tranzițiile (efecte și durate pentru Intrare / Intermediar / Ieșire) se setează per prezentator în Editor de Teme ▸ Tranziții.", comment: "Settings hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(String(localized: "La deconectarea ecranului:", comment: "Setting label"), selection: Binding(
                    get: { pm.screenDisconnectAction.rawValue },
                    set: { pm.screenDisconnectAction = PresentationManager.ScreenDisconnectAction(rawValue: $0) ?? .ask }
                )) {
                    Text(String(localized: "Întreabă", comment: "Disconnect option")).tag("ask")
                    Text(String(localized: "Mută pe alt ecran", comment: "Disconnect option")).tag("moveToAvailable")
                    Text(String(localized: "Ecran negru", comment: "Disconnect option")).tag("goBlack")
                    Text(String(localized: "Nu face nimic", comment: "Disconnect option")).tag("doNothing")
                }
            }

            Section(String(localized: "Media (video pe tot ecranul)", comment: "Settings section")) {
                Toggle(String(localized: "Video în buclă implicit", comment: "Setting label"), isOn: $pmBinding.videoLoopsByDefault)

                Picker(String(localized: "Încadrare video:", comment: "Setting label"), selection: $pmBinding.fullscreenVideoFillRaw) {
                    Text(String(localized: "Încadrează", comment: "Content mode")).tag("fit")
                    Text(String(localized: "Umple", comment: "Content mode")).tag("fill")
                }
            }

            Section(String(localized: "Adaptare Automată", comment: "Settings section")) {
                Text(String(localized: "Layout-ul se adaptează automat la orice rezoluție, raport de aspect sau PPI: casetele sunt definite procentual, iar fonturile se scalează față de o înălțime de referință de 1080p.", comment: "Adaptive layout explanation"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let m = pm.targetScreenMetrics
                LabeledContent(String(localized: "Ecran țintă", comment: "Setting label")) {
                    Text("\(Int(m.resolution.width))×\(Int(m.resolution.height)) • \(m.aspectRatioLabel) • \(Int(m.ppi)) PPI")
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}
