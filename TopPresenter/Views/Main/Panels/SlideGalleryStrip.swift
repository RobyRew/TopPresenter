//
//  SlideGalleryStrip.swift
//  TopPresenter
//
//  What is coming next, under the preview.
//

import SwiftUI

/// A horizontal strip of the slides around the current one.
///
/// The preview card shows exactly one slide, so the operator could see what is
/// on the projector but not what the next press would put there — the only way
/// to look ahead was to leave the panel for the library. This shows the
/// neighbours, marks the live one, and lets either be selected or projected
/// directly.
struct SlideGalleryStrip: View {
    struct Item: Identifiable, Equatable {
        let id: String
        let label: String
        let text: String
    }

    var items: [Item]
    /// Index into `items` of the one currently selected. -1 for none.
    var currentIndex: Int
    /// Tap — make this the selection (preview only).
    var onSelect: (Int) -> Void
    /// Double-tap — put it on the projector.
    var onPresent: (Int) -> Void

    var body: some View {
        if items.count > 1 {
            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "Următoarele", comment: "Slide gallery heading — what comes next"))
                    .font(.system(size: 10, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .foregroundStyle(.tertiary)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        // LAZY: a chapter can be 176 verses (Psalmi 119), and a
                        // plain HStack would build every card to show six.
                        LazyHStack(spacing: 6) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                card(item, isCurrent: index == currentIndex)
                                    .id(item.id)
                                    // Stacked `.onTapGesture(count:)` makes AppKit
                                    // wait out the double-click interval before
                                    // delivering the single tap (AGENTS.md).
                                    .gesture(TapGesture(count: 2).onEnded { onPresent(index) })
                                    .simultaneousGesture(TapGesture().onEnded { onSelect(index) })
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                    // Keep the live slide in view as the operator steps, so the
                    // strip stays useful past the first screenful.
                    .onChange(of: currentIndex) { _, index in
                        guard items.indices.contains(index) else { return }
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(items[index].id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func card(_ item: Item, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white) : AnyShapeStyle(appAccent))
                .lineLimit(1)
            Text(item.text)
                .font(.system(size: 9))
                .foregroundStyle(isCurrent ? AnyShapeStyle(.white.opacity(0.9)) : AnyShapeStyle(.secondary))
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(6)
        .frame(width: 104, height: 62, alignment: .topLeading)
        .background(
            isCurrent ? AnyShapeStyle(appHighlight) : AnyShapeStyle(Color.secondary.opacity(0.1)),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isCurrent ? appHighlight : Color.clear, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .help(item.text.isEmpty ? item.label : "\(item.label)\n\(item.text)")
    }
}
