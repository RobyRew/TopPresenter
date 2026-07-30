import SwiftUI

/// A slider binding that snaps to `step` **without** using `Slider`'s `step:`.
///
/// On macOS, `Slider(value:in:step:)` renders an `NSSlider` with one tick mark
/// per step, and that is astonishingly expensive. Measured, main-thread CPU,
/// eight sliders:
///
/// - `in: 8...200, step: 2`  → **1918 ms** (~240 ms each)
/// - the same range with no `step:` → **55 ms** (~7 ms each)
///
/// A 35x difference, and with ~8 stepped sliders it was the single largest cost
/// in the Theme Editor: the Text tab took ~830 ms, of which its Text Global group
/// was ~827 ms, nearly all of it tick marks. A `0...1 step: 0.01` slider asks
/// AppKit for a hundred of them.
///
/// Snapping in the binding keeps the behaviour identical — the value still lands
/// on multiples of `step` — while the control stays continuous, which is what it
/// looked like anyway: the ticks were never drawn at inspector size.
///
/// Use `Slider(value: $x.snapped(2), in: 8...200)`, never `step:`.
extension Binding where Value == Double {
    func snapped(_ step: Double) -> Binding<Double> {
        guard step > 0 else { return self }
        return Binding(
            get: { wrappedValue },
            set: { newValue in
                let snappedValue = (newValue / step).rounded() * step
                // Avoid a redundant write: these properties persist on didSet.
                if snappedValue != wrappedValue { wrappedValue = snappedValue }
            }
        )
    }
}
