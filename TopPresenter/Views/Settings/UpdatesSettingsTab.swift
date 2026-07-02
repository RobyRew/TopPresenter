//
//  UpdatesSettingsTab.swift
//  TopPresenter
//
//  Settings ▸ Actualizări — the user-facing controls for Sparkle: opt out of
//  automatic checks, pick the cadence, allow silent install, join the beta channel,
//  check now, and open the full Versions list (install / roll back to any release).
//

import SwiftUI

struct UpdatesSettingsTab: View {
    @EnvironmentObject private var updater: UpdateController
    @State private var showVersions = false

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    private var autoCheck: Binding<Bool> {
        Binding(get: { updater.automaticallyChecksForUpdates }, set: { updater.automaticallyChecksForUpdates = $0 })
    }
    private var autoDownload: Binding<Bool> {
        Binding(get: { updater.automaticallyDownloadsUpdates }, set: { updater.automaticallyDownloadsUpdates = $0 })
    }
    private var beta: Binding<Bool> {
        Binding(get: { updater.useBetaChannel }, set: { updater.useBetaChannel = $0 })
    }
    private var interval: Binding<TimeInterval> {
        Binding(get: { updater.updateCheckInterval }, set: { updater.updateCheckInterval = $0 })
    }

    var body: some View {
        if UpdateController.updatesConfigured {
            configured
        } else {
            ContentUnavailableView {
                Label(String(localized: "Actualizări neconfigurate", comment: "Updates not set up"), systemImage: "arrow.triangle.2.circlepath")
            } description: {
                Text(String(localized: "Cheia de semnare Sparkle nu e configurată încă. Vezi UPDATES.md pentru pașii unici de configurare.", comment: "Updates not configured detail"))
            }
        }
    }

    private var configured: some View {
        Form {
            Section {
                Toggle(String(localized: "Caută actualizări automat", comment: "Setting"), isOn: autoCheck)
                Picker(String(localized: "Frecvență", comment: "Setting"), selection: interval) {
                    Text(String(localized: "La fiecare oră", comment: "Interval")).tag(TimeInterval(3600))
                    Text(String(localized: "La 2 ore", comment: "Interval")).tag(TimeInterval(7200))
                    Text(String(localized: "Zilnic", comment: "Interval")).tag(TimeInterval(86400))
                    Text(String(localized: "Săptămânal", comment: "Interval")).tag(TimeInterval(604800))
                }
                .disabled(!autoCheck.wrappedValue)
                Toggle(String(localized: "Descarcă și instalează automat", comment: "Setting"), isOn: autoDownload)
                    .disabled(!autoCheck.wrappedValue)
                Toggle(String(localized: "Include versiuni beta", comment: "Setting"), isOn: beta)
            } header: {
                Text(String(localized: "Actualizări automate", comment: "Section"))
            } footer: {
                Text(String(localized: "Verificarea rulează la pornire și apoi la intervalul ales. Notificările sunt discrete — poți dezactiva oricând.", comment: "Updates footer"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button(String(localized: "Caută acum", comment: "Button")) { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                    Spacer()
                    if let d = updater.lastUpdateCheckDate {
                        Text(String(localized: "Ultima verificare: \(d.formatted(date: .abbreviated, time: .shortened))", comment: "Last check"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Button(String(localized: "Toate versiunile…", comment: "Button — all versions")) { showVersions = true }
                LabeledContent(String(localized: "Versiune curentă", comment: "Field"), value: appVersion)
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showVersions) {
            VersionsView().environmentObject(updater).frame(width: 580, height: 540)
        }
    }
}
