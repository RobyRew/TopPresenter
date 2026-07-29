//
//  DestructiveConfirmation.swift
//  TopPresenter
//
//  ONE confirmation contract for every irreversible library deletion.
//
//  Nothing in the app undoes a delete — the undo stack only covers layout boxes —
//  so a mis-click in a context menu permanently destroys a song, a prepared
//  service, a slide or a media entry. That is a real hazard mid-service, when the
//  operator is right-clicking to reorder or find something under time pressure.
//
//  Bible modules and song collections already prompted, each with its own copy of
//  the same alert. This is that alert, once: bind the item that is about to be
//  deleted, and the confirmation names it and runs the deletion only on confirm.
//

import SwiftUI

struct DestructiveConfirmation<Item>: ViewModifier {
    let title: String
    @Binding var item: Item?
    let name: (Item) -> String
    let perform: (Item) -> Void

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding(
                get: { item != nil },
                set: { if !$0 { item = nil } }
            ),
            presenting: item
        ) { target in
            Button(String(localized: "Cancel", comment: "Alert button"), role: .cancel) {
                item = nil
            }
            Button(String(localized: "Delete", comment: "Alert button"), role: .destructive) {
                perform(target)
                item = nil
            }
        } message: { target in
            Text(String(localized: "Are you sure you want to delete \"\(name(target))\"? This cannot be undone.",
                        comment: "Alert message"))
        }
    }
}

extension View {
    /// Gates a destructive action behind a naming confirmation.
    /// - Parameters:
    ///   - title: alert title, e.g. "Delete Song".
    ///   - item: set to the doomed item to raise the alert; cleared on dismiss.
    ///   - name: how to label the item in the message.
    ///   - perform: the actual deletion, run only when the user confirms.
    func confirmDestructive<Item>(
        _ title: String,
        item: Binding<Item?>,
        name: @escaping (Item) -> String,
        perform: @escaping (Item) -> Void
    ) -> some View {
        modifier(DestructiveConfirmation(title: title, item: item, name: name, perform: perform))
    }
}
