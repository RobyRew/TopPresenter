//
//  ContentAreaView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI

/// Routes the content area based on the selected sidebar item.
struct ContentAreaView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.selectedSidebarItem {
            case .bible:
                BibleView()
            case .songs:
                SongsView()
            case .media:
                MediaView()
            case .schedule:
                ScheduleView()
            case .customSlides:
                CustomSlidesView()
            }
        }
    }
}
