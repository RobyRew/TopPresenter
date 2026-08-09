//
//  OpenFileRouter.swift
//  TopPresenter
//
//  Double-clicking a TopPresenter file in Finder opens it here.
//
//  `.tptheme` and `.tpschedule` have been declared in Info.plist since they
//  existed, and double-clicking one did nothing at all: the declaration says
//  "this app owns the type", but nothing was listening for the open event.
//
//  THE TIMING PROBLEM, and why this buffers.
//
//  `application(_:open:)` fires as part of launch. On a COLD launch — the
//  common case, since the operator is double-clicking a file precisely because
//  the app is not running — it arrives before any window has a body, so posting
//  a notification then would shout into an empty room and the file would be
//  silently dropped. So URLs are held until a window says it is listening, and
//  delivered then. On a warm launch the window is already listening and the
//  buffer is drained immediately.
//

import AppKit
import SwiftUI

@MainActor
final class OpenFileRouter: NSObject, NSApplicationDelegate {

    // STATIC, and that matters: `@NSApplicationDelegateAdaptor` constructs its
    // own instance, so an instance-level buffer would be filled by the delegate
    // AppKit talks to and read from a different object entirely — the file
    // would vanish and the bug would look like "sometimes it just doesn't
    // open". Process-wide state is what this actually is.
    private static var pending: [URL] = []
    private static var isReady = false

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.deliver(urls)
    }

    /// Called once a window is up and listening for `.importFiles`.
    static func windowIsReady() {
        isReady = true
        guard !pending.isEmpty else { return }
        let buffered = pending
        pending = []
        post(buffered)
    }

    private static func deliver(_ urls: [URL]) {
        guard isReady else {
            pending.append(contentsOf: urls)
            return
        }
        post(urls)
    }

    private static func post(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        // Opened files go through the SAME sheet as a drop or a picked
        // selection — the operator sees what will happen before it happens,
        // and a file already in the library is recognised rather than doubled.
        NotificationCenter.default.post(name: .importFiles, object: nil, userInfo: ["urls": urls])
    }
}
