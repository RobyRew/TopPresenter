//
//  WindowNotifications.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 11/06/2026.
//
//  Multi-window (tab) support plumbing:
//  - WindowReader: captures the hosting NSWindow and opts it into native tabbing
//  - onKeyWindowNotification: like onReceive, but only the KEY window reacts —
//    with multiple tabs open, a menu command or cross-view notification must act
//    once (in the frontmost tab), not once per window.
//  - PresentationCommandRouter: app-level singleton that handles OUTPUT commands
//    (black/freeze/clear/font size) exactly once, no matter how many tabs exist.
//

import SwiftUI
import AppKit

// MARK: - Window Reader

/// Captures the hosting NSWindow into a binding and enables native window tabbing
/// for the main control windows (File ▸ Filă Nouă ⌘T merges them as tabs).
struct WindowReader: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let hostWindow = view.window else { return }
            window = hostWindow
            if hostWindow.identifier?.rawValue.hasPrefix(WindowIdentifiers.main) == true {
                hostWindow.tabbingMode = .preferred
                hostWindow.tabbingIdentifier = WindowIdentifiers.main
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if window == nil {
            DispatchQueue.main.async {
                window = nsView.window
            }
        }
    }
}

// MARK: - Key-Window Notification Gating

extension View {
    /// Like `.onReceive(NotificationCenter.default.publisher(for:))` but the
    /// action only fires when this view's window is the key window. Use for any
    /// notification handler that must run ONCE app-wide (menu commands, cross-view
    /// selection messages) now that multiple tabs host the same views.
    func onKeyWindowNotification(
        _ name: Notification.Name,
        perform action: @escaping (Notification) -> Void
    ) -> some View {
        modifier(KeyWindowNotificationModifier(name: name, action: action))
    }
}

private struct KeyWindowNotificationModifier: ViewModifier {
    let name: Notification.Name
    let action: (Notification) -> Void

    @State private var window: NSWindow?

    func body(content: Content) -> some View {
        content
            .background(WindowReader(window: $window))
            .onReceive(NotificationCenter.default.publisher(for: name)) { notification in
                guard isKey else { return }
                action(notification)
            }
    }

    private var isKey: Bool {
        guard let window else { return false }
        if window === NSApp.keyWindow { return true }
        // Sheets presented on this window make the sheet key — still "ours"
        if let key = NSApp.keyWindow, key.sheetParent === window || key.parent === window {
            return true
        }
        return false
    }
}

// MARK: - Presentation Command Router

/// Handles output-wide menu commands exactly once. These act on the shared
/// PresentationManager, so they must NOT be handled per-window: with three tabs
/// open, ⌘B toggling black three times would be a no-op (or worse).
@MainActor
final class PresentationCommandRouter {
    private var tokens: [any NSObjectProtocol] = []

    init(pm: PresentationManager) {
        let center = NotificationCenter.default
        func on(_ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
            tokens.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                // queue: .main guarantees main-thread delivery; the observer
                // closure is typed nonisolated @Sendable, so assert isolation.
                MainActor.assumeIsolated(handler)
            })
        }

        on(.toggleBlackScreen) { pm.toggleBlack() }
        on(.toggleFreeze) { pm.toggleFreeze() }
        on(.clearOutput) { pm.clearOutput() }
        on(.increaseFontSize) { pm.fontSize = min(pm.fontSize + 2, PresentationDefaults.maxFontSize) }
        on(.decreaseFontSize) { pm.fontSize = max(pm.fontSize - 2, PresentationDefaults.minFontSize) }
        on(.resetFontSize) { pm.fontSize = PresentationDefaults.fontSize }
    }

    // isolated deinit (SE-0371): main-actor teardown may read the isolated tokens.
    isolated deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
