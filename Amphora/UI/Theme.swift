//
//  Theme.swift
//  Amphora
//
//  Amphora's design tokens. The visual language is deliberately
//  self-contained — flat dark surfaces, generous continuous corner
//  radii, one violet→gold brand gradient echoing the app icon, and an
//  artwork-derived ambient gradient on the full player — so a future
//  Android port can reproduce every value here one-for-one. No system
//  material effects are part of the look; translucency is expressed as
//  plain opacity so it ports directly.
//

import PandoraCore
import SwiftUI

enum Theme {
    // MARK: Colors

    /// The app's floor — near-black with a violet cast.
    static let background = Color(red: 0.047, green: 0.039, blue: 0.078)
    /// Elevated cards, mini player, list rows.
    static let surface = Color(red: 0.106, green: 0.094, blue: 0.157)
    /// Pressed / selected surfaces, text fields.
    static let surfaceHighlight = Color(red: 0.157, green: 0.141, blue: 0.227)
    /// Brand accent — the icon's gold.
    static let accent = Color(red: 0.949, green: 0.698, blue: 0.200)
    /// Brand secondary — the icon's violet.
    static let violet = Color(red: 0.424, green: 0.290, blue: 0.714)
    /// Hairline strokes on cards over dark backgrounds.
    static let stroke = Color.white.opacity(0.08)

    // MARK: Corner radii (continuous curves everywhere)

    static let radiusS: CGFloat = 10   // small thumbnails
    static let radiusM: CGFloat = 16   // cards, buttons, text fields
    static let radiusCard: CGFloat = 20 // the floating mini player card
    static let radiusL: CGFloat = 24   // large cards
    static let radiusArtwork: CGFloat = 28 // full-player artwork

    // MARK: Gradients

    /// Violet → gold, for prominent brand moments (sign-in button,
    /// progress fills).
    static let brandGradient = LinearGradient(
        colors: [violet, accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle vertical lift for full-screen surfaces outside the player.
    static let backgroundGradient = LinearGradient(
        colors: [Color(red: 0.086, green: 0.075, blue: 0.137), background],
        startPoint: .top,
        endPoint: .bottom
    )

    /// The full player's ambient backdrop, derived from the current
    /// artwork (brand fallback before artwork loads).
    static func playerBackground(_ colors: ArtworkColors) -> LinearGradient {
        LinearGradient(
            colors: [colors.backgroundTop.color, colors.backgroundBottom.color],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

extension PaletteColor {
    /// The SwiftUI mapping of a platform-free palette color.
    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

extension View {
    /// Clears the system List background so the theme's floor shows
    /// through. Apply to the `List` itself.
    func amphoraListBackground() -> some View {
        scrollContentBackground(.hidden)
    }

    /// Draws one List row as a rounded surface card with a hairline
    /// stroke — Amphora's list language everywhere (stations, history,
    /// bookmarks, search results).
    func amphoraCardRow() -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            )
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                            .strokeBorder(Theme.stroke)
                    )
                    .padding(.vertical, 5)
            )
    }
}

extension ArtworkColors {
    /// The artwork's hue as a tint for small elements (badges, knobs).
    var accentColor: Color { accent.color }
}
