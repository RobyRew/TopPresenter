//
//  UpdateController.swift
//  TopPresenter
//
//  Thin wrapper around Sparkle's updater so the rest of the app (menu command,
//  Settings ▸ Updates, the in-app Versions picker) can drive it with plain Swift.
//  Sparkle handles the launch + scheduled checks, the quiet "update available" UI,
//  EdDSA signature verification, download → install → relaunch, opt-out, and the
//  optional silent auto-download. See UPDATES.md for the (per-app, one-time) setup.
//

import Foundation
import Combine
import Sparkle

@MainActor
final class UpdateController: ObservableObject {
    /// Mirrors the updater so the "Check for Updates…" menu item enables/disables.
    @Published var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController
    private let delegate = UpdaterDelegate()

    var updater: SPUUpdater { controller.updater }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: delegate,
                                                  userDriverDelegate: nil)
        // Start Sparkle only when a real EdDSA key is configured (a placeholder
        // SUPublicEDKey makes startUpdater abort) and never inside the test host.
        guard Self.updatesConfigured, !Self.isRunningTests else { return }
        controller.startUpdater()
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// True once `SUPublicEDKey` holds a real key (see UPDATES.md), not the placeholder.
    static var updatesConfigured: Bool {
        let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && !key.hasPrefix("REPLACE_WITH")
    }

    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func checkForUpdates() { controller.updater.checkForUpdates() }

    // MARK: Settings-bound conveniences

    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }
    var automaticallyDownloadsUpdates: Bool {
        get { updater.automaticallyDownloadsUpdates }
        set { updater.automaticallyDownloadsUpdates = newValue }
    }
    /// Seconds between scheduled checks while running (Info.plist seeds the default).
    var updateCheckInterval: TimeInterval {
        get { updater.updateCheckInterval }
        set { updater.updateCheckInterval = newValue }
    }
    var lastUpdateCheckDate: Date? { updater.lastUpdateCheckDate }

    /// Opt into the beta channel (else stable only).
    var useBetaChannel: Bool {
        get { delegate.useBetaChannel }
        set { delegate.useBetaChannel = newValue }
    }

    /// Install a SPECIFIC version (reinstall / downgrade): force Sparkle to pick that
    /// appcast item, verify its EdDSA signature, install + relaunch. The delegate
    /// resets itself when the check cycle finishes.
    func install(versionString: String) {
        delegate.targetVersion = versionString
        controller.updater.checkForUpdates()
    }
}

// MARK: - Sparkle delegate (channels + targeted-version install)

private final class UpdaterDelegate: NSObject, SPUUpdaterDelegate {
    var useBetaChannel = false
    var targetVersion: String?

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        useBetaChannel ? ["beta"] : []
    }

    func versionComparator(for updater: SPUUpdater) -> (any SUVersionComparison)? {
        guard let target = targetVersion else { return nil }
        return TargetVersionComparator(target: target)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        targetVersion = nil
    }
}

/// A comparator that ranks one specific version as the newest, so Sparkle selects
/// (and installs) exactly that appcast item — used for explicit reinstall/downgrade.
private final class TargetVersionComparator: NSObject, SUVersionComparison {
    let target: String
    private let standard = SUStandardVersionComparator()
    init(target: String) { self.target = target }

    func compareVersion(_ versionA: String, toVersion versionB: String) -> ComparisonResult {
        if versionA == target && versionB != target { return .orderedDescending }
        if versionB == target && versionA != target { return .orderedAscending }
        return standard.compareVersion(versionA, toVersion: versionB)
    }
}
