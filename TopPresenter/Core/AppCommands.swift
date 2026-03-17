//
//  AppCommands.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 17/03/2026.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - File Menu Commands
struct FileCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Section {
                Button(String(localized: "New Schedule", comment: "Menu item")) {
                    NotificationCenter.default.post(name: .newSchedule, object: nil)
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            Section {
                Button(String(localized: "Import Bible...", comment: "Menu item")) {
                    NotificationCenter.default.post(name: .importBible, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command])

                Button(String(localized: "Import Songs...", comment: "Menu item")) {
                    NotificationCenter.default.post(name: .importSongs, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }

            Section {
                Button(String(localized: "Export Bible Module...", comment: "Menu item")) {
                    NotificationCenter.default.post(name: .exportBible, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command])

                Button(String(localized: "Batch Export...", comment: "Menu item")) {
                    NotificationCenter.default.post(name: .batchExport, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Presentation Menu Commands
struct PresentationCommands: Commands {
    var body: some Commands {
        CommandMenu(String(localized: "Presentation", comment: "Menu title")) {
            Button(String(localized: "Start Presentation", comment: "Menu item")) {
                NotificationCenter.default.post(name: .startPresentation, object: nil)
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "Black Screen", comment: "Menu item")) {
                NotificationCenter.default.post(name: .toggleBlackScreen, object: nil)
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button(String(localized: "Freeze/Unfreeze", comment: "Menu item")) {
                NotificationCenter.default.post(name: .toggleFreeze, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button(String(localized: "Clear Output", comment: "Menu item")) {
                NotificationCenter.default.post(name: .clearOutput, object: nil)
            }
            .keyboardShortcut(.escape, modifiers: [])

            Divider()

            Button(String(localized: "Increase Font Size", comment: "Menu item")) {
                NotificationCenter.default.post(name: .increaseFontSize, object: nil)
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button(String(localized: "Decrease Font Size", comment: "Menu item")) {
                NotificationCenter.default.post(name: .decreaseFontSize, object: nil)
            }
            .keyboardShortcut("-", modifiers: [.command])

            Button(String(localized: "Reset Font Size", comment: "Menu item")) {
                NotificationCenter.default.post(name: .resetFontSize, object: nil)
            }
            .keyboardShortcut("0", modifiers: [.command])
        }
    }
}

// MARK: - View Menu Commands
struct ViewCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            Button(String(localized: "Bible", comment: "Menu item")) {
                NotificationCenter.default.post(name: .navigateToBible, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button(String(localized: "Songs", comment: "Menu item")) {
                NotificationCenter.default.post(name: .navigateToSongs, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button(String(localized: "Media", comment: "Menu item")) {
                NotificationCenter.default.post(name: .navigateToMedia, object: nil)
            }
            .keyboardShortcut("3", modifiers: [.command])

            Button(String(localized: "Schedule", comment: "Menu item")) {
                NotificationCenter.default.post(name: .navigateToSchedule, object: nil)
            }
            .keyboardShortcut("4", modifiers: [.command])

            Button(String(localized: "Custom Slides", comment: "Menu item")) {
                NotificationCenter.default.post(name: .navigateToCustomSlides, object: nil)
            }
            .keyboardShortcut("5", modifiers: [.command])

            Divider()

            Button(String(localized: "Focus Search", comment: "Menu item")) {
                NotificationCenter.default.post(name: .focusSearch, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button(String(localized: "Quick Search", comment: "Menu item")) {
                NotificationCenter.default.post(name: .quickSearch, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command])
        }
    }
}

// MARK: - Help Menu Commands
struct HelpCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button(String(localized: "TopPresenter Help", comment: "Menu item")) {
                NSWorkspace.shared.open(URL(string: "https://github.com/user/TopPresenter")!)
            }

            Divider()

            Button(String(localized: "Keyboard Shortcuts", comment: "Menu item")) {
                NotificationCenter.default.post(name: .showKeyboardShortcuts, object: nil)
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Button(String(localized: "About TopPresenter", comment: "Menu item")) {
                NSApplication.shared.orderFrontStandardAboutPanel(
                    options: [
                        .applicationName: "TopPresenter",
                        .applicationVersion: "1.0.0",
                        .version: "1",
                        .credits: NSAttributedString(
                            string: "Professional worship presentation software for macOS.\n© 2026 TopPresenter",
                            attributes: [
                                .font: NSFont.systemFont(ofSize: 11),
                                .foregroundColor: NSColor.secondaryLabelColor
                            ]
                        )
                    ]
                )
            }
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    // File
    static let newSchedule = Notification.Name("TopPresenter.newSchedule")
    static let importBible = Notification.Name("TopPresenter.importBible")
    static let importSongs = Notification.Name("TopPresenter.importSongs")
    static let exportBible = Notification.Name("TopPresenter.exportBible")

    // Presentation
    static let startPresentation = Notification.Name("TopPresenter.startPresentation")
    static let toggleBlackScreen = Notification.Name("TopPresenter.toggleBlackScreen")
    static let toggleFreeze = Notification.Name("TopPresenter.toggleFreeze")
    static let clearOutput = Notification.Name("TopPresenter.clearOutput")
    static let increaseFontSize = Notification.Name("TopPresenter.increaseFontSize")
    static let decreaseFontSize = Notification.Name("TopPresenter.decreaseFontSize")
    static let resetFontSize = Notification.Name("TopPresenter.resetFontSize")

    // View / Navigation
    static let navigateToBible = Notification.Name("TopPresenter.navigateToBible")
    static let navigateToSongs = Notification.Name("TopPresenter.navigateToSongs")
    static let navigateToMedia = Notification.Name("TopPresenter.navigateToMedia")
    static let navigateToSchedule = Notification.Name("TopPresenter.navigateToSchedule")
    static let navigateToCustomSlides = Notification.Name("TopPresenter.navigateToCustomSlides")
    static let focusSearch = Notification.Name("TopPresenter.focusSearch")
    static let quickSearch = Notification.Name("TopPresenter.quickSearch")

    // Batch operations
    static let batchExport = Notification.Name("TopPresenter.batchExport")
    static let batchImportFiles = Notification.Name("TopPresenter.batchImportFiles")

    // Help
    static let showKeyboardShortcuts = Notification.Name("TopPresenter.showKeyboardShortcuts")
}
