//
//  VersionsView.swift
//  TopPresenter
//
//  The in-app "all versions" list — reads the Sparkle appcast (the same feed Sparkle
//  uses, so version identifiers match exactly) and lets the user install or ROLL BACK
//  to any published release with one click. The install routes through Sparkle
//  (UpdateController.install), which verifies the EdDSA signature, installs, relaunches.
//

import SwiftUI

// MARK: - Appcast model + parser

struct AppcastItem: Identifiable {
    var title = ""
    var version = ""        // sparkle:version — what Sparkle compares + what we install
    var shortVersion = ""   // sparkle:shortVersionString — display
    var notes = ""          // <description> (HTML)
    var channel = ""        // "" = stable
    var pubDate = ""
    var url = ""
    var id: String { version.isEmpty ? shortVersion + url : version }
}

/// Minimal, namespace-agnostic appcast parser (element names arrive qualified, e.g.
/// "sparkle:version", because XMLParser namespace processing is off by default).
final class AppcastParser: NSObject, XMLParserDelegate {
    private var items: [AppcastItem] = []
    private var current: AppcastItem?
    private var text = ""

    func parse(_ data: Data) -> [AppcastItem] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return items
    }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?,
                qualifiedName: String?, attributes attr: [String: String]) {
        text = ""
        if el == "item" {
            current = AppcastItem()
        } else if el == "enclosure" {
            if let u = attr["url"] { current?.url = u }
            if let v = attr["sparkle:version"], !v.isEmpty { current?.version = v }
            if let s = attr["sparkle:shortVersionString"], !s.isEmpty { current?.shortVersion = s }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(data: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "title": current?.title = t
        case "sparkle:version": if !t.isEmpty { current?.version = t }
        case "sparkle:shortVersionString": if !t.isEmpty { current?.shortVersion = t }
        case "sparkle:channel": current?.channel = t
        case "pubDate": current?.pubDate = t
        case "description": if !t.isEmpty { current?.notes = t }
        case "item": if let c = current { items.append(c) }; current = nil
        default: break
        }
        text = ""
    }
}

private func stripHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
     .replacingOccurrences(of: "&nbsp;", with: " ")
     .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
     .trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - View

struct VersionsView: View {
    @EnvironmentObject private var updater: UpdateController
    @Environment(\.dismiss) private var dismiss
    @State private var items: [AppcastItem] = []
    @State private var loading = true
    @State private var error: String?

    private var currentShort: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(String(localized: "Toate versiunile", comment: "Versions title"), systemImage: "shippingbox")
                    .font(.headline)
                Spacer()
                Button(String(localized: "Închide", comment: "Close")) { dismiss() }
            }
            .padding(12)
            Divider()

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error {
                ContentUnavailableView(String(localized: "Nu s-au putut încărca versiunile", comment: "Error"),
                                       systemImage: "wifi.exclamationmark", description: Text(error))
            } else if items.isEmpty {
                ContentUnavailableView(String(localized: "Nicio versiune publicată încă", comment: "Empty"),
                                       systemImage: "shippingbox",
                                       description: Text(String(localized: "Apare aici după prima lansare cu actualizări.", comment: "Empty detail")))
            } else {
                List(items) { row($0) }
            }
        }
        .task { await load() }
    }

    @ViewBuilder
    private func row(_ item: AppcastItem) -> some View {
        let display = item.shortVersion.isEmpty ? item.version : item.shortVersion
        let isCurrent = !currentShort.isEmpty && item.shortVersion == currentShort
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(display).fontWeight(.semibold)
                    if !item.channel.isEmpty { tag(item.channel.uppercased(), .orange) }
                    if isCurrent { tag(String(localized: "curent", comment: "Current version tag"), .green) }
                }
                if !item.notes.isEmpty {
                    Text(stripHTML(item.notes)).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                if !item.pubDate.isEmpty {
                    Text(item.pubDate).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(isCurrent ? String(localized: "Reinstalează", comment: "Reinstall")
                             : String(localized: "Instalează", comment: "Install")) {
                updater.install(versionString: item.version)
                dismiss()
            }
            .disabled(item.version.isEmpty)
        }
        .padding(.vertical, 3)
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(color.opacity(0.2), in: Capsule()).foregroundStyle(color)
    }

    private func load() async {
        loading = true
        defer { loading = false }
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed) else {
            error = String(localized: "Feed-ul de actualizări lipsește.", comment: "Missing feed")
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            items = AppcastParser().parse(data)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
