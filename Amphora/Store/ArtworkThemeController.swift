//
//  ArtworkThemeController.swift
//  Amphora
//
//  Owns the ambient theme derived from the current track's artwork.
//  Standalone from `AppStore` (it attaches directly to the player's
//  track-changed observers), so the theming layer stays an additive
//  module — and the palette math itself lives in PandoraCore
//  (`ArtworkColors`), shared verbatim with the Android port.
//

import PandoraCore
import SwiftUI

@MainActor
@Observable
final class ArtworkThemeController {
    static let shared = ArtworkThemeController()

    /// The ambient palette for the current track — brand fallback until
    /// artwork loads. Grayscale covers and ads keep the previous palette
    /// (ads carry no artwork and must not flash the theme).
    private(set) var colors: ArtworkColors = .brand

    /// Memoized palettes per artwork URL, capped (artwork URLs are
    /// session-scoped signed strings — a handful of entries is plenty).
    private var paletteCache: [String: ArtworkColors] = [:]
    /// Guard against out-of-order completions landing on the wrong track.
    private var paletteRequest = 0
    private var isAttached = false

    private init() {}

    /// Idempotent — call once at launch. The observer is formed on the
    /// main actor like every other `onTrackChanged` consumer.
    func attach(to player: PlayerService) {
        guard !isAttached else { return }
        isAttached = true
        player.onTrackChanged.append { [weak self] track in
            self?.update(for: track)
        }
    }

    private func update(for track: Track?) {
        guard let url = track?.artworkUrl else { return }
        if let cached = paletteCache[url] {
            colors = cached
            return
        }
        paletteRequest += 1
        let request = paletteRequest
        Task { [weak self] in
            let extracted = await ArtworkPaletteService.palette(for: url)
            guard let self, request == self.paletteRequest, let extracted else { return }
            self.colors = extracted
            if self.paletteCache.count > 24 { self.paletteCache.removeAll() }
            self.paletteCache[url] = extracted
        }
    }
}
