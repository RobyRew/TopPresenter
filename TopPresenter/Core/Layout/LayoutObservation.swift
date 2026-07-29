import Foundation
import Observation

/// A per-box observation token.
///
/// The Observation framework tracks *stored properties of reference types*, and
/// it has no per-key granularity inside a `Dictionary`. `PresentationManager`
/// keeps every box of every presenter in ONE stored property (`profiles`), so
/// while that property was observed directly, nudging a single box by one point
/// invalidated every view that had ever read a layout value: the whole editor
/// canvas, the box list, all four inspector tabs, the preview.
///
/// Giving each box its own object restores granularity without giving up value
/// semantics. `LayoutProfile` stays a `struct`, so undo snapshots and theme
/// payloads remain free — and, more importantly, remain *correct*: a captured
/// snapshot cannot alias the live layout the way a graph of classes would. A
/// view body that touches `tick` subscribes to THIS box and to nothing else.
///
/// The counter wraps (`&+=`). Nothing reads its value — only the fact that it
/// changed — so wrapping is fine, and a wrap would need 4 billion edits to the
/// same box in one session anyway.
@Observable
final class BoxObservationToken {
    var tick: UInt32 = 0
    init() {}
}
