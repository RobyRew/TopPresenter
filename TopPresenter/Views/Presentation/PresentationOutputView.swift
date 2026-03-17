//
//  PresentationOutputView.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 14/03/2026.
//

import SwiftUI

/// The presentation output window — displayed on the external screen/projector.
/// Shows the current live content with configured styling.
struct PresentationOutputView: View {
    @Environment(PresentationManager.self) private var pm

    var body: some View {
        ZStack {
            // Black screen mode
            if pm.isBlackScreen {
                Color.black
                    .ignoresSafeArea()
            } else {
                // Background layer
                backgroundLayer

                // Content layer
                if pm.liveContent.isLive {
                    contentLayer
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                        .animation(.easeInOut(duration: pm.transitionDuration), value: pm.liveContent.mainText)
                }
            }
        }
        .ignoresSafeArea()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }

    // MARK: - Background Layer
    @ViewBuilder
    private var backgroundLayer: some View {
        ZStack {
            // Solid background color
            pm.outputBackgroundColor
                .ignoresSafeArea()

            // Background image
            if pm.outputUseBackgroundImage, let bgImage = pm.outputBackgroundImage {
                Image(nsImage: bgImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(pm.outputBackgroundOpacity)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Content Layer
    @ViewBuilder
    private var contentLayer: some View {
        VStack(spacing: 0) {
            Spacer()

            // Main text
            Text(pm.liveContent.mainText)
                .font(resolvedFont)
                .foregroundStyle(pm.outputTextColor)
                .multilineTextAlignment(pm.outputTextAlignment)
                .lineSpacing(pm.outputLineSpacing * pm.outputFontSize * 0.1)
                .shadow(
                    color: pm.outputShadowEnabled ? .black.opacity(0.8) : .clear,
                    radius: pm.outputShadowEnabled ? pm.outputShadowRadius : 0,
                    x: 0,
                    y: pm.outputShadowEnabled ? 2 : 0
                )
                .padding(.horizontal, pm.outputPadding)

            // Reference / Title
            if !pm.liveContent.reference.isEmpty {
                Text(pm.liveContent.reference)
                    .font(.system(size: pm.outputFontSize * 0.55, weight: .semibold))
                    .foregroundStyle(pm.outputTextColor.opacity(0.85))
                    .multilineTextAlignment(pm.outputTextAlignment)
                    .shadow(
                        color: pm.outputShadowEnabled ? .black.opacity(0.6) : .clear,
                        radius: pm.outputShadowEnabled ? pm.outputShadowRadius * 0.7 : 0
                    )
                    .padding(.top, pm.outputFontSize * 0.4)
                    .padding(.horizontal, pm.outputPadding)
            }

            // Subtitle (verse label, etc.)
            if !pm.liveContent.subtitle.isEmpty {
                Text(pm.liveContent.subtitle)
                    .font(.system(size: pm.outputFontSize * 0.4))
                    .foregroundStyle(pm.outputTextColor.opacity(0.6))
                    .multilineTextAlignment(pm.outputTextAlignment)
                    .padding(.top, 4)
                    .padding(.horizontal, pm.outputPadding)
            }

            Spacer()
        }
    }

    // MARK: - Font Resolution
    private var resolvedFont: Font {
        if pm.outputFontName == "System" || pm.outputFontName.isEmpty {
            return .system(size: pm.outputFontSize, weight: .regular)
        } else {
            return .custom(pm.outputFontName, size: pm.outputFontSize)
        }
    }
}

#Preview {
    let pm = PresentationManager()
    pm.liveContent.setBibleVerse(
        text: "For God so loved the world, that he gave his only begotten Son, that whosoever believeth in him should not perish, but have everlasting life.",
        reference: "John 3:16"
    )
    pm.liveContent.isLive = true

    return PresentationOutputView()
        .environment(pm)
        .frame(width: 800, height: 450)
}
