//
//  CustomSlideLibrary.swift
//  TopPresenter
//
//  The slide-list filter, kept out of the view so it can be tested — the same
//  reason MediaLibrary.filter lives on its own.
//

import Foundation

enum CustomSlideLibrary {

    /// Slides matching `query`, in their existing order.
    ///
    /// Title, subtitle AND body are searched: a dynamic slide is usually
    /// remembered by the token it carries or the text it shows, not by whatever
    /// it happens to be titled — several are "Untitled" until someone names them.
    ///
    /// Diacritic-insensitive on purpose. The operator types on a keyboard whose
    /// layout may not be Romanian, and "anunturi" has to find „Anunțuri" or the
    /// search is worse than scrolling.
    static func filter(_ slides: [PresentationSlide], query: String) -> [PresentationSlide] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return slides }
        return slides.filter { slide in
            [slide.title, slide.subtitle, slide.content].contains { field in
                field.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
}
