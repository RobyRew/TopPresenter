import Foundation
import CoreText

/// The installed font families, enumerated at most once per process.
///
/// `NSFontManager.shared.availableFontFamilies` talks to the font server: it was
/// measured at **268 ms** on the first call and 0.1 ms on every call after. It
/// used to live in a `@State` initialiser on the Theme Editor sheet, which meant
/// the editor paid that 268 ms on the main thread during its first render —
/// whether or not the operator ever opened a font menu. It was the single
/// largest item in the ~867 ms first switch to the Text tab, and no amount of
/// view-level optimisation could reach it.
///
/// Core Text rather than `NSFontManager` on purpose: `CTFontManagerCopy…` is
/// thread-safe, so `warm()` can pay the cost off the main thread before anyone
/// needs the list.
enum FontFamilies {

    /// `static let` gives us Swift's thread-safe run-once initialisation, so the
    /// enumeration happens exactly once no matter who asks first.
    private static let cached: [String] = {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        // Families beginning with "." are system-internal (.AppleSystemUIFont and
        // friends); NSFontManager hides them and so do we.
        return names.filter { !$0.hasPrefix(".") }.sorted()
    }()

    static var all: [String] { cached }

    /// Enumerates the families on a background queue so the first UI that needs
    /// them doesn't block. Safe to call more than once — the work happens once.
    static func warm() {
        DispatchQueue.global(qos: .utility).async { _ = cached }
    }
}
