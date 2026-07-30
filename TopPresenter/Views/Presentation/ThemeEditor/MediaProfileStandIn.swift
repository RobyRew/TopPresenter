import SwiftUI

/// A stand-in for the full-screen media on the Theme Editor canvas.
///
/// The media profile ships every built-in text box HIDDEN on purpose, so a photo
/// or video is never covered by default, and it carries no media boxes of its
/// own — the profile exists for overlays: a logo, a clock, a watermark. The
/// consequence on the canvas was an entirely black rectangle with nothing in it,
/// so there was no way to see where an overlay would actually sit.
///
/// This plays the part the sample verse plays for Bible and the sample lyric for
/// Songs: it is not real content, it just shows the operator what the media will
/// occupy. Drawn only when nothing real is live, and never in the output.
struct MediaProfileStandIn: View {
    var body: some View {
        ZStack {
            // A soft diagonal wash rather than flat grey, so a white overlay and a
            // dark one are both legible against it while positioning.
            LinearGradient(
                colors: [Color(white: 0.30), Color(white: 0.13)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.white.opacity(0.35))
                Text(String(localized: "Media pe tot ecranul",
                            comment: "Theme editor canvas stand-in for the media profile"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Text(String(localized: "Casetele de aici sunt suprapuneri",
                            comment: "Theme editor canvas hint — media profile boxes are overlays"))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .allowsHitTesting(false)
    }
}
