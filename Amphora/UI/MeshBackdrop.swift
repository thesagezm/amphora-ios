//
//  MeshBackdrop.swift
//  Amphora
//
//  The full player's backdrop: an iOS 18 `MeshGradient` fed from the
//  artwork palette (BitChord's artwork-driven mesh scene, adapted).
//  The design: a dark room lit by the current cover — the palette's
//  deep stops carry the floor, the accent pools as the light, corners
//  fall off into near-black. Points are static; when the track changes
//  the colors glide to the new palette in one animated seam (the
//  `ArtworkColors` change inside `.animation(value:)`), so a station
//  sweep reads as the room re-lighting, never as a cut.
//
//  Pure presentation: everything derives from the four `PaletteColor`s
//  PandoraCore already computes — the mesh math here is color mixing
//  in UI space, and the per-frame cost is zero (static mesh, redrawn
//  only when the palette changes).
//

import PandoraCore
import SwiftUI

struct MeshBackdrop: View {
    let colors: ArtworkColors

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: Self.points,
            colors: Self.meshColors(from: colors),
            smoothsColors: true
        )
        .animation(.easeInOut(duration: 0.65), value: colors)
        .overlay(topScrim)
        .accessibilityHidden(true)
    }

    /// Status-bar contrast: the player is a dark scene with white
    /// status glyphs, so when the palette's top stop is bright the top
    /// band gets a soft dark scrim (BitChord's artwork-luminance band,
    /// fed from the core's own luminance math). A dark cover needs
    /// nothing.
    private var topScrim: some View {
        LinearGradient(
            colors: [.black.opacity(Self.topScrimAlpha(colors)), .clear],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.22)
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Slightly pulled grid — the middle row drifts a touch off true so
    /// the pools read organic, not like a plaid.
    private static let points: [SIMD2<Float>] = [
        SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
        SIMD2(0, 0.5), SIMD2(0.5, 0.48), SIMD2(1, 0.52),
        SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1),
    ]

    /// The nine mesh colors, derived purely from the palette:
    /// top band = backgroundTop, floor = backgroundBottom, the accent
    /// pools mid-left as the room's light, the dominant color fills the
    /// right field, corners sink toward black (vignette).
    private static func meshColors(from colors: ArtworkColors) -> [Color] {
        let top = colors.backgroundTop
        let bottom = colors.backgroundBottom
        let light = colors.accent
        let field = colors.dominant

        // Row-major 3×3, matching `points`.
        let values: [PaletteColor] = [
            dim(top, 0.62), dim(top, 0.80), dim(top, 0.55),
            mix(light, top, 0.30), light, dim(field, 0.66),
            dim(bottom, 0.52), dim(bottom, 0.72), dim(bottom, 0.48),
        ]
        return values.map(\.color)
    }

    /// Scale a color toward black by `1 - factor`.
    private static func dim(_ c: PaletteColor, _ factor: Double) -> PaletteColor {
        PaletteColor(red: c.red * factor, green: c.green * factor, blue: c.blue * factor)
    }

    private static func mix(
        _ a: PaletteColor, _ b: PaletteColor, _ t: Double
    ) -> PaletteColor {
        PaletteColor(
            red: a.red + (b.red - a.red) * t,
            green: a.green + (b.green - a.green) * t,
            blue: a.blue + (b.blue - a.blue) * t
        )
    }

    /// 0 for a dark top stop, up to 0.38 once it is genuinely bright —
    /// under that the scrim would read as a smudge instead of contrast.
    private static func topScrimAlpha(_ colors: ArtworkColors) -> Double {
        let luminance = colors.backgroundTop.relativeLuminance
        return min(max((luminance - 0.45) * 1.2, 0), 0.38)
    }
}
