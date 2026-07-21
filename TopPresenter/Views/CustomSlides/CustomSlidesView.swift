//
//  CustomSlidesView.swift
//  TopPresenter
//
//  Custom Slides v2 — DYNAMIC slides. The editor stores TEMPLATES with
//  `{{…}}` tokens (see SlideTokenResolver): Bible passages, song data,
//  date/time, JSON APIs and RSS feeds. The „Inserează date” toolbar builds
//  tokens through small wizards (never hand-written syntax), the preview
//  resolves live, and „Prezintă” resolves fresh right before going live.
//

import SwiftUI
import SwiftData

struct CustomSlidesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PresentationManager.self) private var presentationManager
    @Environment(SearchIndex.self) private var searchIndex
    @Environment(LibraryManager.self) private var libraryManager

    @Query(sort: \PresentationSlide.order) private var slides: [PresentationSlide]

    @State private var selectedSlide: PresentationSlide?
    @State private var editingTitle = ""
    @State private var editingContent = ""
    @State private var editingSubtitle = ""

    // Live preview of the resolved template (debounced).
    @State private var previewTitle = ""
    @State private var previewContent = ""
    @State private var isPresenting = false

    var body: some View {
        ResizableSplit(storageKey: "split_custom", minLeading: 220, maxFraction: 0.5) {
            slidesList
        } trailing: {
            if selectedSlide != nil {
                editor
            } else {
                ContentUnavailableView {
                    Label(String(localized: "Niciun slide selectat", comment: "Placeholder"),
                          systemImage: "rectangle.stack.fill")
                } description: {
                    Text(String(localized: "Alege un slide din stânga sau creează unul nou. Slide-urile pot trage date live: versete, cântece, dată, API-uri, RSS.", comment: "Placeholder message"))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onKeyWindowNotification(.addSlide) { _ in
            addSlide()
        }
        // Make sure the active translation's verse index is (being) built —
        // the bible token wizard and preview read it.
        .onAppear {
            if let id = libraryManager.selectedBibleModule?.id {
                searchIndex.indexVerses(moduleID: id)
            }
        }
    }

    // MARK: - Left: slides list

    private var slidesList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Slides", comment: "Section title"))
                    .font(.headline)
                Spacer()
                Button {
                    addSlide()
                } label: {
                    Image(systemName: "plus")
                }
                .controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List(slides, selection: Binding(
                get: { selectedSlide?.id },
                set: { newID in
                    if let id = newID, let slide = slides.first(where: { $0.id == id }) {
                        selectSlide(slide)
                    }
                }
            )) { slide in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slide.title.isEmpty ? String(localized: "Untitled", comment: "Placeholder") : slide.title)
                            .font(.body)
                            .lineLimit(1)
                        Text(slide.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    let tokens = SlideTemplate.tokenCount(slide.title)
                        + SlideTemplate.tokenCount(slide.subtitle)
                        + SlideTemplate.tokenCount(slide.content)
                    if tokens > 0 {
                        Label("\(tokens)", systemImage: "bolt.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(appAccent)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(appAccent.opacity(0.12), in: Capsule())
                            .help(String(localized: "Slide dinamic — \(tokens) surse de date", comment: "Dynamic slide badge"))
                    }
                }
                .tag(slide.id)
                .contextMenu {
                    Button(String(localized: "Show on Screen", comment: "Context menu")) {
                        presentSlide(title: slide.title, content: slide.content)
                    }
                    Divider()
                    Button(String(localized: "Delete", comment: "Context menu"), role: .destructive) {
                        deleteSlide(slide)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Right: editor + token toolbar + live preview

    private var editor: some View {
        VStack(spacing: 10) {
            TextField(String(localized: "Title", comment: "Text field"), text: $editingTitle)
                .textFieldStyle(.roundedBorder)
                .font(.title3)
                .onChange(of: editingTitle) { _, newValue in
                    selectedSlide?.title = newValue
                }

            TextField(String(localized: "Subtitle", comment: "Text field"), text: $editingSubtitle)
                .textFieldStyle(.roundedBorder)
                .onChange(of: editingSubtitle) { _, newValue in
                    selectedSlide?.subtitle = newValue
                }

            SlideTokenToolbar { token in
                editingContent += (editingContent.isEmpty || editingContent.hasSuffix("\n") ? "" : " ") + token
            }

            TextEditor(text: $editingContent)
                .font(.body.monospaced())
                .onChange(of: editingContent) { _, newValue in
                    selectedSlide?.content = newValue
                }

            // Live preview of the RESOLVED slide (debounced; remote from cache).
            previewCard
                .frame(height: 130)

            HStack {
                Text(String(localized: "Datele dinamice se împrospătează la fiecare prezentare.", comment: "Editor hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    try? modelContext.save()
                } label: {
                    Label(String(localized: "Save", comment: "Button"), systemImage: "square.and.arrow.down")
                }
                .controlSize(.small)

                Button {
                    presentSlide(title: editingTitle, content: editingContent)
                } label: {
                    if isPresenting {
                        ProgressView().controlSize(.small).frame(minWidth: 60)
                    } else {
                        Label(String(localized: "Show", comment: "Button"), systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isPresenting)
            }
        }
        .padding()
        .task(id: "\(editingTitle)⟪\(editingSubtitle)⟪\(editingContent)") {
            // Debounce, then resolve for the preview (remote hits the cache).
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let context = SlideTokenContext(index: searchIndex, modelContext: modelContext)
            let resolved = await SlideTokenResolver.resolveSlide(
                title: editingTitle, subtitle: editingSubtitle, content: editingContent,
                context: context)
            guard !Task.isCancelled else { return }
            previewTitle = resolved.title
            previewContent = resolved.content
        }
    }

    private var previewCard: some View {
        VStack(spacing: 5) {
            if !previewTitle.isEmpty {
                Text(previewTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
            }
            Text(previewContent.isEmpty
                 ? String(localized: "Previzualizare — scrie sau inserează date", comment: "Preview placeholder")
                 : previewContent)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(previewContent.isEmpty ? .white.opacity(0.35) : .white)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.black, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
    }

    // MARK: - Actions

    /// Resolve fresh, THEN go live — a slide can never block the output
    /// (remote tokens are capped by RemoteContentService's hard timeout).
    private func presentSlide(title: String, content: String) {
        guard !isPresenting else { return }
        isPresenting = true
        let context = SlideTokenContext(index: searchIndex, modelContext: modelContext)
        Task {
            let resolved = await SlideTokenResolver.resolveSlide(
                title: title, subtitle: "", content: content, context: context)
            presentationManager.showCustomText(text: resolved.content, title: resolved.title)
            isPresenting = false
        }
    }

    private func addSlide() {
        let slide = PresentationSlide(
            title: String(localized: "New Slide", comment: "Default slide title"),
            content: "",
            slideType: "text",
            order: slides.count
        )
        modelContext.insert(slide)
        try? modelContext.save()
        selectSlide(slide)
    }

    private func selectSlide(_ slide: PresentationSlide) {
        selectedSlide = slide
        editingTitle = slide.title
        editingContent = slide.content
        editingSubtitle = slide.subtitle
        NotificationCenter.default.post(name: .slideSelected, object: slide.id)
    }

    private func deleteSlide(_ slide: PresentationSlide) {
        if selectedSlide?.id == slide.id {
            selectedSlide = nil
        }
        modelContext.delete(slide)
        try? modelContext.save()
    }
}

// MARK: - „Inserează date” toolbar (token wizards — no hand-written syntax)

private struct SlideTokenToolbar: View {
    /// Called with the composed token text, e.g. `{{bible:Ioan 3:16}}`.
    let insert: (String) -> Void

    @Environment(SearchIndex.self) private var index
    @Environment(\.modelContext) private var modelContext

    @State private var showBible = false
    @State private var showSong = false
    @State private var showRemote = false

    var body: some View {
        HStack(spacing: 8) {
            Label(String(localized: "Inserează date:", comment: "Token toolbar label"), systemImage: "bolt.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(appAccent)
                .labelStyle(.titleAndIcon)

            wizardButton(String(localized: "Verset", comment: "Token kind"), icon: "book.fill", flag: $showBible)
                .popover(isPresented: $showBible, arrowEdge: .bottom) {
                    BibleTokenWizard(insert: wrapInsert($showBible))
                }
            wizardButton(String(localized: "Cântec", comment: "Token kind"), icon: "music.note", flag: $showSong)
                .popover(isPresented: $showSong, arrowEdge: .bottom) {
                    SongTokenWizard(insert: wrapInsert($showSong))
                }

            Menu {
                Button(String(localized: "Data completă (duminică, 21 iulie 2026)", comment: "Date token")) { insert("{{date}}") }
                Button(String(localized: "Data scurtă (21.07.2026)", comment: "Date token")) { insert("{{date:dd.MM.yyyy}}") }
                Button(String(localized: "Ziua săptămânii", comment: "Date token")) { insert("{{date:EEEE}}") }
                Button(String(localized: "Ora (10:30)", comment: "Time token")) { insert("{{time}}") }
            } label: {
                Label(String(localized: "Dată/Oră", comment: "Token kind"), systemImage: "calendar")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            wizardButton(String(localized: "API/RSS", comment: "Token kind"), icon: "antenna.radiowaves.left.and.right", flag: $showRemote)
                .popover(isPresented: $showRemote, arrowEdge: .bottom) {
                    RemoteTokenWizard(insert: wrapInsert($showRemote))
                }

            Spacer()
        }
        .font(.caption)
    }

    private func wizardButton(_ title: String, icon: String, flag: Binding<Bool>) -> some View {
        Button {
            flag.wrappedValue = true
        } label: {
            Label(title, systemImage: icon)
        }
        .controlSize(.small)
    }

    private func wrapInsert(_ flag: Binding<Bool>) -> (String) -> Void {
        { token in
            insert(token)
            flag.wrappedValue = false
        }
    }
}

// MARK: Verse wizard — live parse preview over the ACTIVE translation

private struct BibleTokenWizard: View {
    let insert: (String) -> Void

    @Environment(SearchIndex.self) private var index
    @State private var reference = ""
    @State private var field = "text"

    private var resolved: String? {
        BibleTokenProvider.resolve(reference: reference, field: field,
                                   books: index.books, verses: index.verses)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Inserează un pasaj", comment: "Wizard title"))
                .font(.headline)
            TextField(String(localized: "Ioan 3:16-18, Psalmi 23…", comment: "Wizard placeholder"), text: $reference)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            Picker("", selection: $field) {
                Text(String(localized: "Textul", comment: "Bible token field")).tag("text")
                Text(String(localized: "Referința", comment: "Bible token field")).tag("ref")
                Text(String(localized: "Text + referință", comment: "Bible token field")).tag("full")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let resolved {
                Text(resolved)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(width: 280, alignment: .leading)
            } else if !reference.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(String(localized: "Referință nerecunoscută.", comment: "Wizard note"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Button(String(localized: "Inserează", comment: "Button")) {
                let f = field == "text" ? "" : "#\(field)"
                insert("{{bible:\(reference.trimmingCharacters(in: .whitespaces))\(f)}}")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(resolved == nil)
        }
        .padding(14)
    }
}

// MARK: Song wizard — index search + field choice

private struct SongTokenWizard: View {
    let insert: (String) -> Void

    @Environment(SearchIndex.self) private var index
    @State private var query = ""
    @State private var field = "first"

    private var matches: [SongIndexEntry] {
        index.searchSongs(query, limit: 8)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Inserează din cântec", comment: "Wizard title"))
                .font(.headline)
            TextField(String(localized: "Caută cântecul…", comment: "Wizard placeholder"), text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
            Picker(String(localized: "Câmp:", comment: "Wizard field label"), selection: $field) {
                Text(String(localized: "Primul vers", comment: "Song token field")).tag("first")
                Text(String(localized: "Titlul", comment: "Song token field")).tag("title")
                Text(String(localized: "Autorul", comment: "Song token field")).tag("author")
                Text(String(localized: "Cartea de cântări", comment: "Song token field")).tag("book")
                Text(String(localized: "Numărul", comment: "Song token field")).tag("number")
                Text(String(localized: "CCLI", comment: "Song token field")).tag("ccli")
                Text(String(localized: "Primul slide (text)", comment: "Song token field")).tag("slide1")
            }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(matches) { entry in
                    Button {
                        let f = field == "first" ? "" : "#\(field)"
                        insert("{{song:\(entry.title)\(f)}}")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "music.note").font(.caption2).foregroundStyle(appAccent)
                            Text(entry.title).lineLimit(1)
                            if !entry.author.isEmpty {
                                Text(entry.author).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.callout)
            .frame(width: 300, alignment: .leading)
        }
        .padding(14)
    }
}

// MARK: API/RSS wizard — with an inline „Testează” fetch

private struct RemoteTokenWizard: View {
    let insert: (String) -> Void

    @State private var kind = "url"
    @State private var address = ""
    @State private var field = ""
    @State private var testResult: String?
    @State private var isTesting = false

    private var token: String {
        let f = field.trimmingCharacters(in: .whitespaces)
        return "{{\(kind):\(address.trimmingCharacters(in: .whitespaces))\(f.isEmpty ? "" : "#\(f)")}}"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Inserează din API sau RSS", comment: "Wizard title"))
                .font(.headline)
            Picker("", selection: $kind) {
                Text(String(localized: "API (JSON)", comment: "Remote kind")).tag("url")
                Text(String(localized: "RSS / Atom", comment: "Remote kind")).tag("rss")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            TextField(String(localized: "https://…", comment: "Wizard placeholder"), text: $address)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)
            TextField(kind == "url"
                      ? String(localized: "Cale în JSON: items.0.title", comment: "Wizard placeholder")
                      : String(localized: "Câmp: 0.title / 0.description / 0.date", comment: "Wizard placeholder"),
                      text: $field)
                .textFieldStyle(.roundedBorder)
                .frame(width: 320)

            HStack(spacing: 8) {
                Button {
                    runTest()
                } label: {
                    if isTesting {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label(String(localized: "Testează", comment: "Button"), systemImage: "bolt.badge.checkmark")
                    }
                }
                .controlSize(.small)
                .disabled(isTesting || URL(string: address)?.scheme?.hasPrefix("http") != true)

                Button(String(localized: "Inserează", comment: "Button")) {
                    insert(token)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(URL(string: address)?.scheme?.hasPrefix("http") != true)
            }

            if let testResult {
                Text(testResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(width: 320, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
    }

    private func runTest() {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)) else { return }
        isTesting = true
        testResult = nil
        let kind = kind
        let f = field.trimmingCharacters(in: .whitespaces)
        Task {
            let value: String? = kind == "url"
                ? await RemoteContentService.shared.jsonValue(url: url, keypath: f)
                : await RemoteContentService.shared.rssValue(url: url, field: f)
            testResult = value ?? String(localized: "Nimic găsit — verifică URL-ul și calea.", comment: "Wizard test failure")
            isTesting = false
        }
    }
}
