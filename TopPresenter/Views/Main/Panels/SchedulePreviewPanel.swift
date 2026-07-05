//
//  SchedulePreviewPanel.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//
//  Right-side panel for Schedule sessions — driven entirely by the shared
//  SessionRunner (the panel never calls pm.show* itself): current-item preview,
//  runner transport (start/prev/next/jump), and the running order with
//  missing-item indicators.
//

import SwiftUI
import SwiftData

struct SchedulePreviewPanel: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(LibraryManager.self) private var libraryManager
    @Environment(SessionRunner.self) private var runner
    @Environment(\.modelContext) private var modelContext

    /// The session shown here: the RUNNING one wins, else the browsed selection.
    private var schedule: ServiceSchedule? {
        if runner.isRunning, let id = runner.activeScheduleID,
           let running = try? modelContext.fetch(FetchDescriptor<ServiceSchedule>(
               predicate: #Predicate { $0.id == id })).first {
            return running
        }
        return libraryManager.selectedSchedule
    }

    private var sortedItems: [ScheduleItem] {
        schedule?.sortedItems ?? []
    }

    private var runningThis: Bool {
        runner.isRunning && runner.activeScheduleID == schedule?.id
    }

    /// The item the panel focuses on: the runner's current item while running,
    /// else the first item of the browsed session.
    private var currentIndex: Int {
        runningThis ? min(runner.itemIndex, max(sortedItems.count - 1, 0)) : 0
    }

    private var currentItem: ScheduleItem? {
        guard currentIndex >= 0, currentIndex < sortedItems.count else { return nil }
        return sortedItems[currentIndex]
    }

    private var nextItem: ScheduleItem? {
        let next = currentIndex + 1
        guard next < sortedItems.count else { return nil }
        return sortedItems[next]
    }

    private var isLive: Bool {
        pm.liveContent.isLive && !pm.isBlackScreen
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .schedule)

            Divider()

            // Current item preview — resolved from the library, like it will project.
            PresentationPreviewCard(pendingContent: pendingPreviewContent,
                                    pendingMedia: pendingPreviewMedia)
                .padding()

            Divider()

            runnerControlsBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            PresentationControlsBar()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            runningOrderList

            Divider()

            PanelFooter()
        }
        .background(.background)
    }

    // MARK: - Runner Controls Bar

    private var runnerControlsBar: some View {
        VStack(spacing: 6) {
            // Current item info + position
            if let item = currentItem {
                HStack(spacing: 6) {
                    Image(systemName: iconForType(item.itemType))
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text(item.title)
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                    Spacer()
                    if runningThis, let item = currentItem {
                        let slides = runner.slideCount(of: item, context: modelContext)
                        if slides > 1 {
                            Text(verbatim: "slide \(runner.slideIndex + 1)/\(slides) · ")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(verbatim: "\(currentIndex + 1)/\(sortedItems.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Transport: prev / start·stop / next
            HStack(spacing: 8) {
                Button {
                    runner.previous(context: modelContext)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!runningThis)
                .keyboardShortcut(.leftArrow, modifiers: [])
                .help(String(localized: "Slide-ul / elementul anterior", comment: "Tooltip"))

                if runningThis {
                    Button {
                        runner.stop()
                        pm.clearOutput()
                    } label: {
                        Label(String(localized: "Oprește", comment: "Control button — stop session"),
                              systemImage: "stop.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                } else {
                    Button {
                        if let schedule { runner.start(schedule, context: modelContext) }
                    } label: {
                        Label(String(localized: "Pornește sesiunea", comment: "Control button — start session"),
                              systemImage: "play.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(schedule == nil || sortedItems.isEmpty)
                }

                Button {
                    runner.next(context: modelContext)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(!runningThis)
                .keyboardShortcut(.rightArrow, modifiers: [])
                .help(String(localized: "Slide-ul / elementul următor", comment: "Tooltip"))
            }
            .lineLimit(1)

            // Next item preview
            if let next = nextItem {
                HStack(spacing: 4) {
                    Text(String(localized: "Next:", comment: "Label"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: iconForType(next.itemType))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(next.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(localized: "\(sortedItems.count - currentIndex - 1) rămase", comment: "Remaining session items"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Running Order List

    private var runningOrderList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(String(localized: "Running Order", comment: "Section title"))
                        .font(.caption.bold())
                    Spacer()
                    Text(String(localized: "\(sortedItems.count) items", comment: "Item count"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if sortedItems.isEmpty {
                    Text(String(localized: "No schedule selected", comment: "Placeholder"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding()
                } else {
                    ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                        runningOrderRow(index: index, item: item)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func runningOrderRow(index: Int, item: ScheduleItem) -> some View {
        let isCurrent = index == currentIndex && runningThis
        let isMissing = SessionService.resolve(item, context: modelContext).isMissing

        Button {
            if runningThis {
                runner.jump(toItem: index, context: modelContext)
            } else if let schedule {
                // Not running yet — clicking an item starts the session THERE.
                runner.start(schedule, context: modelContext)
                runner.jump(toItem: index, context: modelContext)
            }
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: "\(index + 1)")
                    .font(.caption2.monospacedDigit().bold())
                    .foregroundStyle(isCurrent ? .white : .secondary)
                    .frame(width: 20)

                Image(systemName: iconForType(item.itemType))
                    .font(.caption2)
                    .foregroundStyle(isCurrent ? .white : .secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? .white : .primary)
                        .lineLimit(1)
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption2)
                            .foregroundStyle(isCurrent ? .white.opacity(0.7) : .secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if isMissing {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                if isCurrent && isLive {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .opacity(isMissing ? 0.55 : 1)
            .background(
                isCurrent ? Color.accentColor : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Preview mapping

    /// Resolve the current item for the preview card — text-based kinds.
    private var pendingPreviewContent: PresentationPreviewCard.PendingContent? {
        guard let item = currentItem else { return nil }
        switch SessionService.resolve(item, context: modelContext) {
        case let .bible(text, reference, _):
            return .init(text: text, reference: reference)
        case let .song(song, version):
            // First slide's text as the preview — built with the SAME current
            // song options the runner presents with.
            let d = UserDefaults.standard
            let first = buildSongSlides(
                song: song, version: version ?? song.activeVersion,
                maxLines: (d.object(forKey: "song_maxLinesPerSlide") as? Int) ?? 6,
                bilingual: (d.object(forKey: "song_bilingual") as? Bool) ?? false,
                language: nil,
                bracket: d.string(forKey: "song_repeatBracket") ?? "none",
                countStyle: d.string(forKey: "song_repeatCount") ?? "times"
            ).first
            return .init(text: first?.text ?? song.title, reference: song.title,
                         subtitle: first?.label ?? "", lines: first?.lines ?? [])
        case let .text(title, content):
            return .init(text: content, reference: title)
        case .blank:
            return .init(text: "", reference: "")
        case .missing(let reason):
            return .init(text: reason, reference: item.title)
        case .media:
            return nil   // handled by pendingPreviewMedia
        }
    }

    /// Resolve the current item for the preview card — media kind.
    private var pendingPreviewMedia: PresentationPreviewCard.PendingMedia? {
        guard let item = currentItem,
              case let .media(mediaItem) = SessionService.resolve(item, context: modelContext)
        else { return nil }
        let thumb = mediaItem.thumbnailData.flatMap { NSImage(data: $0) }
        return .init(thumbnail: thumb, kindRaw: mediaItem.mediaType, name: mediaItem.name)
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "bible": return "book.fill"
        case "song": return "music.note"
        case "text": return "text.alignleft"
        case "media": return "photo"
        case "blank": return "rectangle"
        default: return "doc"
        }
    }
}
