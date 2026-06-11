//
//  SchedulePreviewPanel.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 04/04/2026.
//

import SwiftUI
import SwiftData

/// Right-side panel for Schedule: current/next item preview, go-live controls, running order.
struct SchedulePreviewPanel: View {
    @Environment(PresentationManager.self) private var pm
    @Environment(\.openWindow) private var openWindow

    @State private var currentSchedule: ServiceSchedule?
    @State private var currentItemIndex: Int = 0

    private var sortedItems: [ScheduleItem] {
        currentSchedule?.sortedItems ?? []
    }

    private var currentItem: ScheduleItem? {
        guard currentItemIndex >= 0, currentItemIndex < sortedItems.count else { return nil }
        return sortedItems[currentItemIndex]
    }

    private var nextItem: ScheduleItem? {
        let nextIdx = currentItemIndex + 1
        guard nextIdx < sortedItems.count else { return nil }
        return sortedItems[nextIdx]
    }

    private var isLive: Bool {
        pm.liveContent.isLive && !pm.isBlackScreen
    }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(contentType: .schedule)

            Divider()

            // Current item preview — previews the selected item before it goes live
            PresentationPreviewCard(pendingContent: pendingPreviewContent)
                .padding()

            Divider()

            // Schedule navigation controls
            scheduleControlsBar
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            Divider()

            // Presentation controls
            PresentationControlsBar()
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            // Running order (compact list of items)
            runningOrderList

            Divider()

            // Theme switcher + Layout Editor access
            PanelFooter()
        }
        .background(.background)
        .onKeyWindowNotification(.scheduleSelected) { notification in
            if let schedule = notification.object as? ServiceSchedule {
                currentSchedule = schedule
                currentItemIndex = 0
            }
        }
    }

    // MARK: - Schedule Controls Bar
    private var scheduleControlsBar: some View {
        VStack(spacing: 6) {
            // Current item info
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
                    Text("\(currentItemIndex + 1)/\(sortedItems.count)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Nav + Go Live
            HStack(spacing: 8) {
                Button {
                    if currentItemIndex > 0 {
                        currentItemIndex -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(currentItemIndex <= 0)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Button {
                    if let item = currentItem {
                        showItem(item)
                    }
                } label: {
                    Label(
                        isLive
                            ? String(localized: "Hide", comment: "Control button")
                            : String(localized: "Go Live", comment: "Control button"),
                        systemImage: isLive ? "eye.slash.fill" : "play.fill"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                }
                .buttonStyle(.borderedProminent)
                .tint(isLive ? .orange : .accentColor)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(currentItem == nil)

                Button {
                    if currentItemIndex < sortedItems.count - 1 {
                        currentItemIndex += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.body.weight(.semibold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.bordered)
                .disabled(currentItemIndex >= sortedItems.count - 1)
                .keyboardShortcut(.rightArrow, modifiers: [])
            }

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
                    Text("\(sortedItems.count) items")
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
                        Button {
                            currentItemIndex = index
                        } label: {
                            HStack(spacing: 8) {
                                // Position number
                                Text("\(index + 1)")
                                    .font(.caption2.monospacedDigit().bold())
                                    .foregroundStyle(index == currentItemIndex ? .white : .secondary)
                                    .frame(width: 20)

                                Image(systemName: iconForType(item.itemType))
                                    .font(.caption2)
                                    .foregroundStyle(index == currentItemIndex ? .white : .secondary)
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.caption)
                                        .foregroundStyle(index == currentItemIndex ? .white : .primary)
                                        .lineLimit(1)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle)
                                            .font(.caption2)
                                            .foregroundStyle(index == currentItemIndex ? .white.opacity(0.7) : .secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                // Live indicator
                                if index == currentItemIndex && isLive {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 6, height: 6)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                index == currentItemIndex
                                    ? Color.accentColor
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 4)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Helpers

    /// Maps the current schedule item to preview content, mirroring showItem(_:).
    private var pendingPreviewContent: PresentationPreviewCard.PendingContent {
        guard let item = currentItem else { return .init(text: "", reference: "") }
        switch item.itemType {
        case "bible":
            return .init(text: item.content, reference: item.subtitle)
        case "song":
            return .init(text: item.content, reference: item.title, subtitle: item.subtitle)
        case "blank":
            return .init(text: "", reference: "")
        default:
            return .init(text: item.content, reference: item.title)
        }
    }

    private func showItem(_ item: ScheduleItem) {
        if isLive {
            pm.clearOutput()
            return
        }
        switch item.itemType {
        case "bible":
            pm.showBibleVerse(text: item.content, reference: item.subtitle)
        case "song":
            pm.showSongVerse(text: item.content, title: item.title, verseLabel: item.subtitle)
        case "text":
            pm.showCustomText(text: item.content, title: item.title)
        case "blank":
            pm.goBlack()
        default:
            pm.showCustomText(text: item.content, title: item.title)
        }
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
