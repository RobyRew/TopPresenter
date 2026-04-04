//
//  CustomSlidesView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI
import SwiftData

/// Custom text slides editor.
struct CustomSlidesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PresentationManager.self) private var presentationManager

    @Query(sort: \PresentationSlide.order) private var slides: [PresentationSlide]

    @State private var selectedSlide: PresentationSlide?
    @State private var editingTitle = ""
    @State private var editingContent = ""
    @State private var editingSubtitle = ""

    var body: some View {
        HSplitView {
            // Slides list
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
                    VStack(alignment: .leading) {
                        Text(slide.title.isEmpty ? String(localized: "Untitled", comment: "Placeholder") : slide.title)
                            .font(.body)
                        Text(slide.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .tag(slide.id)
                    .contextMenu {
                        Button(String(localized: "Show on Screen", comment: "Context menu")) {
                            presentationManager.showCustomText(text: slide.content, title: slide.title)
                        }
                        Divider()
                        Button(String(localized: "Delete", comment: "Context menu"), role: .destructive) {
                            deleteSlide(slide)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .frame(minWidth: 200, maxWidth: 300)

            // Editor
            if selectedSlide != nil {
                VStack(spacing: 12) {
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

                    TextEditor(text: $editingContent)
                        .font(.body)
                        .onChange(of: editingContent) { _, newValue in
                            selectedSlide?.content = newValue
                        }

                    HStack {
                        Spacer()
                        Button {
                            try? modelContext.save()
                        } label: {
                            Label(
                                String(localized: "Save", comment: "Button"),
                                systemImage: "square.and.arrow.down"
                            )
                        }
                        .controlSize(.small)

                        Button {
                            presentationManager.showCustomText(
                                text: editingContent,
                                title: editingTitle
                            )
                        } label: {
                            Label(
                                String(localized: "Show", comment: "Button"),
                                systemImage: "play.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding()
            } else {
                VStack {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "Select or create a slide", comment: "Placeholder"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addSlide)) { _ in
            addSlide()
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
