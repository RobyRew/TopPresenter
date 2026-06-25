//
//  ProfileView.swift
//  TopPresenter
//
//  A LOCAL profile / preferences screen (no online account) — presenter identity and
//  a few personal defaults, stored in UserDefaults via @AppStorage. Designed to grow:
//  add fields here and they persist automatically.
//

import SwiftUI

struct ProfileView: View {
    @AppStorage("profile_presenterName") private var presenterName = ""
    @AppStorage("profile_church") private var church = ""
    @AppStorage("profile_defaultLanguage") private var defaultLanguage = "ro"
    @AppStorage("song_maxLinesPerSlide") private var songMaxLines = 6
    @AppStorage("profile_confirmBeforeDelete") private var confirmBeforeDelete = true

    private let languages = ["ro", "en", "es", "ca"]

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section(String(localized: "Profil", comment: "Profile section")) {
                TextField(String(localized: "Nume prezentator", comment: "Field"), text: $presenterName)
                TextField(String(localized: "Biserică", comment: "Field"), text: $church)
                Picker(String(localized: "Limbă implicită", comment: "Field"), selection: $defaultLanguage) {
                    ForEach(languages, id: \.self) { Text($0.uppercased()).tag($0) }
                }
            }

            Section(String(localized: "Preferințe", comment: "Preferences section")) {
                Stepper(String(localized: "Linii per slide: \(songMaxLines)", comment: "Field"),
                        value: $songMaxLines, in: 2...12)
                Toggle(String(localized: "Confirmă înainte de ștergere", comment: "Field"), isOn: $confirmBeforeDelete)
            }

            Section(String(localized: "Despre", comment: "About section")) {
                LabeledContent(String(localized: "Versiune", comment: "Field"), value: appVersion)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(String(localized: "Account", comment: "Profile title"))
    }
}
