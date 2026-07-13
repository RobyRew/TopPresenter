//
//  ResizableSplit.swift
//  TopPresenter
//
//  THE module split: navigation/list pane LEFT (default one THIRD of the
//  width), content RIGHT — with a user-draggable divider, persisted per
//  module (fraction, so window resizes keep the proportion). Every module
//  (Bible, Songs, Media, Schedule, Custom Slides) uses this instead of
//  HSplitView, so behavior and feel are identical everywhere.
//
//  Bug rules (learned the hard way in BibleView):
//  - Drags MUST use `coordinateSpace: .global` — the divider itself moves
//    while resizing, so a local-space translation is measured against a
//    moving origin (feedback loop, jitter).
//  - Hover cursor push/pop is guarded while a drag runs.
//

import SwiftUI

struct ResizableSplit<Leading: View, Trailing: View>: View {
    /// UserDefaults key persisting the leading FRACTION (e.g. "split_bible").
    let storageKey: String
    var defaultFraction: Double = 1.0 / 3.0
    var minLeading: CGFloat = 240
    var maxFraction: CGFloat = 0.55
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @State private var fraction: Double = 0
    @State private var dragBaseWidth: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.width
            let stored = fraction > 0 ? fraction : loadFraction()
            let width = min(max(stored * total, minLeading), total * maxFraction)
            HStack(spacing: 0) {
                leading()
                    .frame(width: max(width, 0))
                divider(total: total, currentWidth: width)
                trailing()
                    .frame(maxWidth: .infinity)
            }
        }
        .onAppear { fraction = loadFraction() }
    }

    private func loadFraction() -> Double {
        let v = UserDefaults.standard.double(forKey: storageKey)
        return v > 0 ? v : defaultFraction
    }

    private func set(width: CGFloat, total: CGFloat) {
        guard total > 0 else { return }
        let clamped = min(max(width, minLeading), total * maxFraction)
        fraction = clamped / total
        UserDefaults.standard.set(fraction, forKey: storageKey)
    }

    private func divider(total: CGFloat, currentWidth: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 7)
            .overlay(
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(width: 1)
            )
            .contentShape(Rectangle())
            .onHover { inside in
                guard dragBaseWidth == nil else { return }
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        let base = dragBaseWidth ?? currentWidth
                        dragBaseWidth = base
                        set(width: base + v.translation.width, total: total)
                    }
                    .onEnded { _ in dragBaseWidth = nil }
            )
    }
}
