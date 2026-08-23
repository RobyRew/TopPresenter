//
//  ImportScanner.swift
//  TopPresenter
//
//  Turns whatever was dropped or picked — files, folders, folders of folders —
//  into the list of things we can actually import.
//
//  It replaces `DragDropImportHandler.expandToImportableFiles`, which had three
//  defects that all looked identical to the operator: the drop simply did
//  nothing, and nothing said why.
//
//    · it filtered on Bible/Song extensions only, so a folder of photos yielded
//      nothing at all
//    · it required an extension, so a folder of OpenSong files yielded nothing —
//      even though dropping one of those files DIRECTLY imports it fine
//    · it stopped at three levels, which any real songbook tree exceeds
//      (Cântări/Tineret/2026/Vara/… is four before a single file)
//
//  The depth cap was there for a good reason: a Documents tree full of multi-GB
//  drone footage would beach-ball the app. That protection is real and is kept —
//  but it comes from the EXTENSION FILTER, which never opens a file it cannot
//  use, not from refusing to look. What replaces the cap is a budget that says
//  when it stopped, so "there is more down there" is something the operator gets
//  told rather than something they have to guess.
//

import Foundation

nonisolated enum ImportScanner {

    /// Limits on how much of the filesystem one scan will look at.
    struct Budget: Sendable {
        /// The selected folder is depth 0. Eight covers every plausible library
        /// tree while still refusing to walk a whole home directory.
        var maxDepth = 8
        /// A real scraped song corpus is tens of thousands of files — 5 000 was
        /// sized for "a songbook", and turned a 27 000-song import into a
        /// truncation notice. The scan itself is directory enumeration plus an
        /// extension test, so the ceiling costs almost nothing to raise; what
        /// it still buys is a stop when someone points at their home folder.
        var maxCandidates = 100_000
        /// Entries LOOKED AT, importable or not. This is the one that stops a
        /// node_modules or a Photos library, where the file count dwarfs
        /// anything we would keep.
        var maxVisitedEntries = 1_000_000

        /// Extensionless files are the only ones the scanner OPENS, so this is
        /// the one that keeps a stray tree cheap. Raised with the rest: a
        /// corpus of extensionless OpenSong files is a real thing, and 400
        /// silently skipped everything past the first few hundred.
        var maxProbes = 20_000
        /// An OpenSong file is a few KB of XML. Anything past this is not one,
        /// and reading it would be pure cost.
        var maxProbeBytes = 2 * 1024 * 1024

        static let `default` = Budget()
    }

    /// Directories that never contain a worship library and always contain
    /// thousands of files.
    ///
    /// Without this, pointing the scanner anywhere near a code checkout walks
    /// `node_modules` — and since a probe OPENS every extensionless file, and
    /// npm packages are full of `LICENSE` and binstubs with no extension, it
    /// opened hundreds of them. macOS logged a decompression error for each.
    /// Skipping by name is cruder than it looks and exactly right here: these
    /// are conventions, not guesses.
    static let skippedDirectoryNames: Set<String> = [
        "node_modules", ".git", ".svn", ".hg", "Pods", "Carthage", ".build",
        "build", "DerivedData", ".swiftpm", "__pycache__", ".venv", "venv",
        "vendor", "target", ".next", ".nuxt", "dist", ".cache", ".gradle",
    ]

    /// Extensionless files that are conventionally NOT documents. Cheap to
    /// check, and it removes the overwhelming majority of what a probe would
    /// otherwise open.
    static let neverProbedNames: Set<String> = [
        "license", "licence", "readme", "changelog", "authors", "contributors",
        "copying", "notice", "makefile", "dockerfile", "procfile", "rakefile",
        "gemfile", "podfile", "cartfile", "brewfile", "vagrantfile",
    ]

    /// Why a scan stopped early. Always surfaced — a silent truncation is how
    /// "I dropped the folder and half of it is missing" happens.
    enum Truncation: Sendable, Equatable {
        case depth(Int)
        case candidates(Int)
        case entries(Int)
        case cancelled

        var message: String {
            switch self {
            case .depth(let limit):
                return String(localized: "Some subfolders are deeper than \(limit) levels and were not scanned.",
                              comment: "Import scan truncation")
            case .candidates(let limit):
                return String(localized: "More than \(limit) files were found; the rest were skipped.",
                              comment: "Import scan truncation")
            case .entries(let limit):
                return String(localized: "More than \(limit) entries were examined; the scan stopped there.",
                              comment: "Import scan truncation")
            case .cancelled:
                return String(localized: "The scan was cancelled.", comment: "Import scan truncation")
            }
        }
    }

    struct Result: Sendable {
        var files: [URL] = []
        /// Everything hit, in the order hit. Usually empty.
        var truncations: [Truncation] = []
        /// Entries examined — for the progress line on a big drop.
        var visitedEntries = 0
        /// Things the operator NAMED that yielded nothing: a file we cannot
        /// read, or a folder with nothing readable in it.
        ///
        /// Only top-level entries. A folder is a request to find what is
        /// usable inside it, so listing the four hundred unrelated files in a
        /// Documents tree would be noise — but dropping `notes.docx` and being
        /// shown an empty sheet is just baffling.
        var rejected: [URL] = []

        var wasTruncated: Bool { !truncations.isEmpty }
    }

    /// Expand a selection into importable sources.
    ///
    /// Pure file inspection and safe to run off-main; `isCancelled` is consulted
    /// every 256 entries so a huge tree stays interruptible.
    static func scan(
        _ urls: [URL],
        budget: Budget = .default,
        isCancelled: () -> Bool = { false }
    ) -> Result {
        let fm = FileManager.default
        var result = Result()
        var seen = Set<String>()
        var stopped = false

        func note(_ truncation: Truncation) {
            if !result.truncations.contains(truncation) { result.truncations.append(truncation) }
        }

        func add(_ url: URL) {
            guard result.files.count < budget.maxCandidates else {
                note(.candidates(budget.maxCandidates))
                stopped = true
                return
            }
            if seen.insert(url.standardizedFileURL.path).inserted { result.files.append(url) }
        }

        var probesUsed = 0

        /// True when a file with no extension is worth keeping.
        ///
        /// This is the ONLY place the scanner opens anything, so it is the only
        /// place that can be slow — and it was: every `LICENSE` in every npm
        /// package got opened. Three cheap refusals come before the read, and
        /// the read itself is a mapped prefix, not the file.
        func extensionlessFileIsImportable(_ url: URL) -> Bool {
            guard probesUsed < budget.maxProbes else { return false }
            guard !Self.neverProbedNames.contains(url.lastPathComponent.lowercased()) else { return false }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size > 0, size <= budget.maxProbeBytes else { return false }
            probesUsed += 1
            return ImportService.detectSongFormat(fileURL: url) != nil
                || ImportService.detectBibleFormat(fileURL: url) != nil
        }

        func walk(_ url: URL, depth: Int) {
            guard !stopped else { return }

            result.visitedEntries += 1
            if result.visitedEntries % 256 == 0, isCancelled() {
                note(.cancelled)
                stopped = true
                return
            }
            guard result.visitedEntries <= budget.maxVisitedEntries else {
                note(.entries(budget.maxVisitedEntries))
                stopped = true
                return
            }

            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

            if !isDirectory.boolValue {
                guard !url.lastPathComponent.hasPrefix(".") else { return }
                switch ImportCatalog.candidacy(of: url) {
                case .accept: add(url)
                case .probe: if extensionlessFileIsImportable(url) { add(url) }
                case .reject: return
                }
                return
            }

            // Never walk a build or dependency tree. Checked before anything
            // else touches the directory, including the USFM probe.
            if depth > 0, Self.skippedDirectoryNames.contains(url.lastPathComponent) { return }

            // Some folders ARE the document: a `.tptheme` package, a USFM book
            // set. Walking into them would import their parts as loose files.
            if ImportCatalog.directoryExtensions.contains(url.pathExtension.lowercased()) {
                add(url); return
            }
            if ImportService.detectBibleFormat(fileURL: url) == .usfm { add(url); return }

            guard depth < budget.maxDepth else {
                note(.depth(budget.maxDepth))
                return
            }

            let children = (try? fm.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for child in children.sorted(by: {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
            }) {
                walk(child, depth: depth + 1)
            }
        }

        for url in urls {
            let before = result.files.count
            walk(url, depth: 0)
            if result.files.count == before { result.rejected.append(url) }
        }
        return result
    }

    /// Open the security scopes for `roots`, run `body`, and close them again —
    /// whatever happens.
    ///
    /// Every scope opened has to be closed. The code this replaced opened one
    /// per dropped root and closed none, with a comment claiming they were
    /// "kept open until the function ends" and nothing that ever ended them.
    static func withScopedRoots<T>(_ roots: [URL], _ body: () throws -> T) rethrows -> T {
        var opened: [URL] = []
        for root in roots where root.startAccessingSecurityScopedResource() {
            opened.append(root)
        }
        defer { for root in opened { root.stopAccessingSecurityScopedResource() } }
        return try body()
    }
}
