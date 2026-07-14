//
//  CustomSlidesPreviewPanel.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftUI
import SwiftData

/// Right-side panel for Custom Slides: preview, slide navigation, presentation controls, basic style settings.
struct CustomSlidesPreviewPanel: View {
    @Environment(PresentationManager.self) private var pm

    @Query(sort: \PresentationSlide.order) private var slides: [PresentationSlide]

    @State private var currentSlideIndex: Int = 0

    private var currentSlide: PresentationSlide? {
        guard currentSlideIndex >= 0, currentSlideIndex < slides.count else { return nil }
        return slides[currentSlideIndex]
    }

    private var isLive: Bool {
        pm.liveContent.isLive && !pm.isBlackScreen
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .customSlides)

            Divider()

            // Preview display — previews the selected slide before it goes live
            PresentationPreviewCard(formatHint: "text", pendingContent: .init(
                text: currentSlide?.content ?? "",
                reference: currentSlide?.title ?? ""
            ))
            .padding()

            Divider()

            // Slide navigation controls
            slideControlsBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            // Presentation controls
            PresentationControlsBar()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            Spacer()

            Divider()

            // Theme switcher + Layout Editor access
            PanelFooter(format: "text")
        }
        .background(.background)
        .onKeyWindowNotification(.slideSelected) { notification in
            if let slideID = notification.object as? UUID,
               let idx = slides.firstIndex(where: { $0.id == slideID }) {
                currentSlideIndex = idx
            }
        }
    }

    // MARK: - Slide Controls Bar
    private var slideControlsBar: some View {
        VStack(spacing: 6) {
            // Current slide info
            if let slide = currentSlide {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.caption)
                        .foregroundStyle(appAccent)
                    Text(slide.title.isEmpty
                         ? String(localized: "Untitled", comment: "Placeholder")
                         : slide.title)
                        .font(.caption.bold())
                        .foregroundStyle(appAccent)
                        .lineLimit(1)
                    Spacer()
                    Text("\(currentSlideIndex + 1)/\(slides.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Nav + Show
            HStack(spacing: 8) {
                Button {
                    if currentSlideIndex > 0 {
                        currentSlideIndex -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(currentSlideIndex <= 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button {
                    if isLive {
                        pm.clearOutput()
                    } else if let slide = currentSlide {
                        pm.showCustomText(
                            text: slide.content, title: slide.title,
                            slideIndex: currentSlideIndex, slideCount: slides.count
                        )
                    }
                } label: {
                    Label(
                        isLive
                            ? String(localized: "Hide", comment: "Control button")
                            : String(localized: "Show", comment: "Control button"),
                        systemImage: isLive ? "eye.slash.fill" : "play.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(isLive ? .orange : appAccent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(currentSlide == nil)

                Button {
                    if currentSlideIndex < slides.count - 1 {
                        currentSlideIndex += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(currentSlideIndex >= slides.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }
        }
    }
}
