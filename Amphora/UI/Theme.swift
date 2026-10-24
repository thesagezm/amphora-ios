//
//  Theme.swift
//  Amphora
//
//  Amphora's design tokens. The visual language is deliberately
//  self-contained — flat dark surfaces, generous continuous corner
//  radii, one accent gradient per theme, and an artwork-derived ambient
//  gradient on the full player — so a future Android port can reproduce
//  every value here one-for-one. No system material effects are part of
//  the look; translucency is expressed as plain opacity so it ports
//  directly.
//
//  The palette is user-selectable (Settings → Appearance): a background
//  appearance × an accent. The static tokens below read the live
//  selection from `ThemeController`, so a change re-renders every view
//  that touches them — SwiftUI's observation tracking works through
//  computed indirections like these, as long as the access happens
//  during a view's `body` evaluation.
//

import PandoraCore
import SwiftUI

// MARK: - User-selectable theme pieces

/// The background family. Pandora Night uses Pandora's brand blues
/// (#224099 deep / #00A0EE bright) cast over near-black; True Black is
/// OLED-pure with neutral surfaces.
enum ThemeAppearance: String, CaseIterable, Codable, Sendable, Identifiable {
    case dark
    case pandora
    case trueBlack

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Amphora Dark"
        case .pandora: return "Pandora Night"
        case .trueBlack: return "True Black"
        }
    }

    /// A small gradient preview chip for pickers.
    var previewGradient: LinearGradient {
        LinearGradient(
            colors: [palette.backgroundTop, palette.surfaceHighlight],
            startPoint: .top, endPoint: .bottom
        )
    }

    var palette: AppearancePalette {
        switch self {
        case .dark:
            return AppearancePalette(
                background: Color(red: 0.047, green: 0.039, blue: 0.078),
                backgroundTop: Color(red: 0.086, green: 0.075, blue: 0.137),
                surface: Color(red: 0.106, green: 0.094, blue: 0.157),
                surfaceHighlight: Color(red: 0.157, green: 0.141, blue: 0.227)
            )
        case .pandora:
            return AppearancePalette(
                background: Color(red: 0.024, green: 0.043, blue: 0.094),
                backgroundTop: Color(red: 0.051, green: 0.106, blue: 0.220),
                surface: Color(red: 0.063, green: 0.106, blue: 0.192),
                surfaceHighlight: Color(red: 0.106, green: 0.169, blue: 0.302)
            )
        case .trueBlack:
            return AppearancePalette(
                background: .black,
                backgroundTop: Color(red: 0.050, green: 0.050, blue: 0.050),
                surface: Color(red: 0.078, green: 0.078, blue: 0.078),
                surfaceHighlight: Color(red: 0.133, green: 0.133, blue: 0.133)
            )
        }
    }
}

/// The accent family: a primary color, the gradient partner it fades
/// into, and the glyph color that stays legible on a primary fill.
enum ThemeAccent: String, CaseIterable, Codable, Sendable, Identifiable {
    case gold
    case pandora
    case violet
    case aqua
    case rose

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gold: return "Gold"
        case .pandora: return "Pandora Blue"
        case .violet: return "Violet"
        case .aqua: return "Aqua"
        case .rose: return "Rose"
        }
    }

    var palette: AccentPalette {
        switch self {
        case .gold:
            // The app icon's gold, fading into its violet.
            return AccentPalette(
                primary: Color(red: 0.949, green: 0.698, blue: 0.200),
                secondary: Color(red: 0.424, green: 0.290, blue: 0.714),
                glyph: .black
            )
        case .pandora:
            // Pandora's brand pair: cerulean #00A0EE → deep blue #224099.
            return AccentPalette(
                primary: Color(red: 0.000, green: 0.627, blue: 0.933),
                secondary: Color(red: 0.133, green: 0.251, blue: 0.600),
                glyph: .black
            )
        case .violet:
            return AccentPalette(
                primary: Color(red: 0.545, green: 0.361, blue: 0.965),
                secondary: Color(red: 0.925, green: 0.282, blue: 0.600),
                glyph: .white
            )
        case .aqua:
            return AccentPalette(
                primary: Color(red: 0.176, green: 0.831, blue: 0.749),
                secondary: Color(red: 0.055, green: 0.647, blue: 0.914),
                glyph: .black
            )
        case .rose:
            return AccentPalette(
                primary: Color(red: 0.984, green: 0.443, blue: 0.522),
                secondary: Color(red: 0.753, green: 0.149, blue: 0.827),
                glyph: .black
            )
        }
    }
}

// MARK: - Palette values

struct AppearancePalette {
    let background: Color
    let backgroundTop: Color
    let surface: Color
    let surfaceHighlight: Color
}

struct AccentPalette {
    let primary: Color
    let secondary: Color
    /// Black or white — whichever keeps glyphs legible on `primary`.
    let glyph: Color

    var gradient: LinearGradient {
        LinearGradient(
            colors: [primary, secondary],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Live tokens

enum Theme {
    private static var selection: ThemeSelection { ThemeController.shared.selection }

    /// The app's floor.
    @MainActor static var background: Color { selection.appearance.palette.background }
    /// Elevated cards, mini player, list rows.
    @MainActor static var surface: Color { selection.appearance.palette.surface }
    /// Pressed / selected surfaces, text fields.
    @MainActor static var surfaceHighlight: Color {
        selection.appearance.palette.surfaceHighlight
    }
    /// The active accent.
    @MainActor static var accent: Color { selection.accent.palette.primary }
    /// The accent's gradient partner.
    @MainActor static var accentSecondary: Color { selection.accent.palette.secondary }
    /// Black or white — the glyph color that stays legible on `accent`.
    @MainActor static var accentGlyph: Color { selection.accent.palette.glyph }
    /// Whisper-soft strokes (used sparingly — surfaces, not borders,
    /// carry the structure).
    @MainActor static var stroke: Color { Color.white.opacity(0.07) }

    // MARK: Corner radii (continuous curves everywhere)

    static let radiusS: CGFloat = 10   // small thumbnails
    static let radiusM: CGFloat = 16   // cards, buttons, text fields
    static let radiusCard: CGFloat = 20 // the floating mini player card
    static let radiusL: CGFloat = 24   // large cards
    static let radiusArtwork: CGFloat = 28 // full-player artwork

    // MARK: Gradients

    /// The active accent's gradient, for prominent moments (sign-in
    /// button, progress fills).
    @MainActor static var brandGradient: LinearGradient { selection.accent.palette.gradient }

    /// Subtle vertical lift for full-screen surfaces outside the player.
    @MainActor static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [selection.appearance.palette.backgroundTop, background],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// The full player's ambient backdrop, derived from the current
    /// artwork (brand fallback before artwork loads). Deliberately
    /// independent of the theme — the artwork colors the player.
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

    /// Draws one List row as a soft rounded surface card — Amphora's
    /// list language everywhere (stations, history, bookmarks, search
    /// results). Fill only, no stroke: structure comes from the surface
    /// tone against the floor, never from a hard border. `tinted` marks
    /// an active row (e.g. the playing station) with a matte accent
    /// wash.
    func amphoraCardRow(tinted: Bool = false) -> some View {
        listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            )
            .listRowBackground(
                RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                    .fill(
                        tinted
                            ? AnyShapeStyle(Theme.accent.opacity(0.14))
                            : AnyShapeStyle(Theme.surface)
                    )
                    .padding(.vertical, 5)
            )
    }
}

extension ArtworkColors {
    /// The artwork's hue as a tint for small elements (badges, knobs).
    var accentColor: Color { accent.color }
}
