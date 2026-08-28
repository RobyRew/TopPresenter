//
//  StoreRecovery.swift
//  TopPresenter
//
//  Opening the library, in a way that cannot stop the app from starting.
//
//  THE BUG THIS REPLACES
//  ---------------------
//  Both containers were built as `try ModelContainer(...)` with `fatalError` in
//  the catch. That treats "can I open the store?" as an invariant, when it is an
//  I/O operation with several ordinary ways to fail: a `-wal` sidecar left
//  behind by a crash or a copy-while-open, a migration that cannot be inferred,
//  a disk that is full, a file the sandbox will not hand over.
//
//  Any one of those made TopPresenter crash on launch, with no message and no
//  way back in — and with no backup or restore anywhere in the app, an operator
//  had nothing to try. That is the worst failure this app can have: it happens
//  before anything is on screen, on the Sunday morning, and the library is
//  usually the only copy.
//
//  THE LADDER
//  ----------
//  Each rung is tried in order and NOTHING is ever deleted — only moved aside,
//  with the destination reported so the operator can get it back:
//
//   1. Open it.
//   2. Move the `-wal`/`-shm` sidecars aside and open again. This is the common
//      recoverable case: the store itself is intact and its sidecars are not.
//      It costs whatever was committed to the WAL and not yet checkpointed, so
//      it is second, not first, and the sidecars are kept.
//   3. Quarantine the whole store and start empty. The app launches, and says
//      exactly where the library went.
//   4. Fall back to memory. The store cannot be written at all — a full or
//      read-only disk — so the app still opens and can SAY so, instead of dying
//      in a way that looks like a broken app rather than a full disk.
//
//  The outcome is returned, not logged and forgotten: `MainWindowRoot` puts it
//  on screen, because a library that quietly emptied itself is indistinguishable
//  from one that was deleted.
//

import Foundation
import SwiftData

nonisolated enum StoreRecovery {

    enum Result: Sendable, Equatable {
        case opened
        /// The store was fine; its sidecars were not.
        case openedAfterMovingSidecars(movedTo: URL)
        /// The store could not be opened at all. It is at `movedTo`, untouched.
        case startedFreshAfterQuarantine(movedTo: URL, reason: String)
        /// Nothing on disk worked. This session keeps its data in memory only.
        case inMemoryFallback(reason: String)

        var isClean: Bool { self == .opened }

        /// Where the old files went, when anything was moved.
        var recoveredFolder: URL? {
            switch self {
            case .opened, .inMemoryFallback: return nil
            case .openedAfterMovingSidecars(let url): return url
            case .startedFreshAfterQuarantine(let url, _): return url
            }
        }

        var title: String {
            switch self {
            case .opened:
                return ""
            case .openedAfterMovingSidecars:
                return String(localized: "Biblioteca a fost reparată", comment: "Store recovery title")
            case .startedFreshAfterQuarantine:
                return String(localized: "Biblioteca nu a putut fi deschisă", comment: "Store recovery title")
            case .inMemoryFallback:
                return String(localized: "Nu se poate scrie pe disc", comment: "Store recovery title")
            }
        }

        /// Says what happened and, above all, WHERE the old data is. Never
        /// reassuring: the operator has to know a rebuild may be needed.
        var message: String {
            switch self {
            case .opened:
                return ""
            case .openedAfterMovingSidecars:
                return String(localized: """
                    Un fișier auxiliar rămas după o închidere bruscă a împiedicat deschiderea.                     A fost mutat deoparte și biblioteca s-a deschis. Ultimele modificări                     dinaintea închiderii ar putea lipsi.
                    """, comment: "Store recovery message")
            case .startedFreshAfterQuarantine:
                return String(localized: """
                    TopPresenter a pornit cu o bibliotecă goală. Cea veche NU a fost ștearsă —                     este păstrată intactă în dosarul de mai jos, iar importul o poate reface.
                    """, comment: "Store recovery message")
            case .inMemoryFallback(let reason):
                return String(localized: """
                    Biblioteca nu poate fi citită sau scrisă (\(reason)). TopPresenter                     funcționează, dar NIMIC din ce faci acum nu se salvează. Verifică spațiul                     liber pe disc și repornește.
                    """, comment: "Store recovery message")
            }
        }
    }

    struct Outcome: Sendable {
        let container: ModelContainer
        let result: Result
    }

    /// Opens `configuration`, recovering rather than trapping.
    ///
    /// - Parameter label: a stable ASCII identifier ("library", "history") used
    ///   in the recovery FOLDER NAME. Deliberately not localized: the folder
    ///   outlives the session and must not be renamed by a language change, and
    ///   an operator reading it over the phone needs it spellable.
    static func open(schema: Schema, configuration: ModelConfiguration, label: String) -> Outcome {
        // 1 — the ordinary path.
        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return Outcome(container: container, result: .opened)
        }

        let storeURL = configuration.url
        let firstError = (try? ModelContainer(for: schema, configurations: [configuration])) == nil
            ? describeFailure(schema: schema, configuration: configuration)
            : ""

        // 2 — sidecars aside, then try again.
        if let sidecarHome = moveSidecars(of: storeURL, label: label),
           let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return Outcome(container: container, result: .openedAfterMovingSidecars(movedTo: sidecarHome))
        }

        // 3 — quarantine the store itself and start empty.
        if let quarantine = quarantine(storeURL, label: label),
           let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            return Outcome(container: container,
                           result: .startedFreshAfterQuarantine(movedTo: quarantine, reason: firstError))
        }

        // 4 — memory, so the app opens and can say what happened.
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: [memory]) {
            return Outcome(container: container, result: .inMemoryFallback(reason: firstError))
        }

        // The schema itself is unusable — a programming error, not a disk one,
        // and there is genuinely nothing to fall back to.
        fatalError("The \(label) schema cannot be instantiated even in memory: \(firstError)")
    }

    // MARK: Steps

    /// The real error text, for the operator and the report.
    private static func describeFailure(schema: Schema, configuration: ModelConfiguration) -> String {
        do {
            _ = try ModelContainer(for: schema, configurations: [configuration])
            return ""
        } catch {
            return String(describing: error)
        }
    }

    /// Moves `-wal`/`-shm` into a timestamped folder. Returns where, or nil when
    /// there were none to move (in which case retrying would prove nothing).
    private static func moveSidecars(of storeURL: URL, label: String) -> URL? {
        let fm = FileManager.default
        let sidecars = ["-wal", "-shm"].map { URL(fileURLWithPath: storeURL.path + $0) }
            .filter { fm.fileExists(atPath: $0.path) }
        guard !sidecars.isEmpty else { return nil }

        guard let folder = makeRecoveryFolder(near: storeURL, label: label, kind: "sidecars") else { return nil }
        for sidecar in sidecars {
            try? fm.moveItem(at: sidecar, to: folder.appending(path: sidecar.lastPathComponent))
        }
        return folder
    }

    /// Moves the store AND its sidecars aside. Never deletes: this is somebody's
    /// only copy of a library it took months to build, and a store that SwiftData
    /// will not open can still be readable by other tools.
    private static func quarantine(_ storeURL: URL, label: String) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: storeURL.path) else { return nil }
        guard let folder = makeRecoveryFolder(near: storeURL, label: label, kind: "store") else { return nil }

        for suffix in ["", "-wal", "-shm"] {
            let file = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: file.path) else { continue }
            try? fm.moveItem(at: file, to: folder.appending(path: file.lastPathComponent))
        }
        return fm.fileExists(atPath: storeURL.path) ? nil : folder
    }

    /// A folder that does not exist yet.
    ///
    /// The name carries a timestamp for the operator's benefit, but uniqueness
    /// cannot rest on it: the stamp is second-precision, and two failures inside
    /// one second landed on the SAME folder. The move then failed because the
    /// name was taken, the store was left in place, and recovery fell all the
    /// way through to the in-memory rung — so a repeat failure silently stopped
    /// saving anything instead of quarantining. Caught by
    /// `asecondRecoveryDoesNotClobberTheFirst`.
    private static func makeRecoveryFolder(near storeURL: URL, label: String, kind: String) -> URL? {
        let fm = FileManager.default
        let stamp = ISO8601DateFormatter.recoveryStamp.string(from: Date())
        let parent = storeURL.deletingLastPathComponent()
        let base = "Recovered-\(label)-\(kind)-\(stamp)"

        for attempt in 0..<100 {
            let name = attempt == 0 ? base : "\(base)-\(attempt + 1)"
            let folder = parent.appending(path: name)
            guard !fm.fileExists(atPath: folder.path) else { continue }
            // `withIntermediateDirectories: false` so an existing folder is an
            // error rather than a silent reuse — that is the whole point here.
            if (try? fm.createDirectory(at: folder, withIntermediateDirectories: false)) != nil {
                return folder
            }
        }
        return nil
    }
}

private extension ISO8601DateFormatter {
    /// Filename-safe and sortable. `nonisolated(unsafe)` because it is only ever
    /// read, and recovery runs before there is an actor to hop to.
    nonisolated(unsafe) static let recoveryStamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withYear, .withMonth, .withDay, .withTime]
        f.timeZone = .current
        return f
    }()
}
