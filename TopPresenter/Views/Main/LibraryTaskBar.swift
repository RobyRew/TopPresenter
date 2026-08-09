//
//  LibraryTaskBar.swift
//  TopPresenter
//
//  The strip that appears at the bottom of the window while a long library job
//  runs — and the reason the app is usable while it does.
//
//  It replaces a beach ball. Importing seventy Bibles or deleting them again is
//  minutes of work, and the only thing the operator used to see was a frozen
//  window and a spinning cursor, with no way to tell a slow job from a hung
//  one. This says which item, how far in, how long it has taken and roughly how
//  long is left — and offers the one button that matters, Stop.
//

import Combine
import SwiftUI

struct LibraryTaskBar: View {
    @Environment(LibraryTaskRunner.self) private var tasks
    /// Ticks the clock so elapsed/remaining update while a single long file
    /// runs. One second is enough for a job measured in minutes, and cheap.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        if tasks.progress.isRunning {
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text(tasks.progress.statusLine)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(tasks.progress.timingLine)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Button(String(localized: "Stop", comment: "Button")) { tasks.cancel() }
                        .controlSize(.small)
                        .disabled(tasks.progress.isCancelled)
                }
                ProgressView(value: tasks.progress.fraction)
                    .progressViewStyle(.linear)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.regularMaterial)
            .overlay(alignment: .top) { Divider() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onReceive(tick) { now = $0 }
            // Reading `now` in the body is what makes the timing line tick;
            // without it SwiftUI has no reason to re-render between items.
            .id(tasks.progress.isRunning ? Int(now.timeIntervalSince1970) : 0)
        }
    }
}
