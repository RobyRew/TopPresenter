//
//  SettingsView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import UniformTypeIdentifiers

/// Application settings window with tabbed sections.
struct SettingsView: View {
    @Environment(PresentationManager.self) private var presentationManager

    var body: some View {
        TabView {
            InterfaceSettingsTab()
                .tabItem {
                    Label(String(localized: "Interfață", comment: "Settings tab"), systemImage: "paintbrush")
                    ProjectionSettingsTab()
                .tabItem {
                    Label(String(localized: "Proiecție", comment: "Settings tab"), systemImage: "display")
                }
        }

            BibleSettingsTab()
                .tabItem {
                    Label(String(localized: "Biblie", comment: "Settings tab"), systemImage: "book.closed")
                    ProjectionSettingsTab()
                .tabItem {
                    Label(String(localized: "Proiecție", comment: "Settings tab"), systemImage: "display")
                }
        }

            ImportExportSettingsTab()
                .tabItem {
                    Label(String(localized: "Import / Export", comment: "Settings tab"), systemImage: "arrow.up.arrow.down")
                    ProjectionSettingsTab()
                .tabItem {
                    Label(String(localized: "Proiecție", comment: "Settings tab"), systemImage: "display")
                }
        }
            ProjectionSettingsTab()
                .tabItem {
                    Label(String(localized: "Proiecție", comment: "Settings tab"), systemImage: "display")
                }

            UpdatesSettingsTab()
                .tabItem {
                    Label(String(localized: "Actualizări", comment: "Settings tab"), systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 550, height: 480)
    }
}

// MARK: - Interface Settings Tab
struct InterfaceSettingsTab: View {
    @AppStorage("startupSection") private var startupSection: String = "bible"
    @AppStorage("confirmBeforeDelete") private var confirmBeforeDelete: Bool = true
    @AppStorage("forceTouchClearAction") private var forceTouchAction: String = "clearAll"

    var body: some View {
        Form {
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
        .frame(width: 520)
        .padding(.vertical, 8)
    }
}
