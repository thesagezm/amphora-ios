//
//  ArtworkPaletteService.swift
//  Amphora
//
//  Glue between UIKit and the shared palette extractor: draws a decoded
//  artwork into a small RGBA8 buffer and runs `ArtworkColors.extract`
//  on it. The extraction math lives in PandoraCore unchanged, so the
//  Android port derives identical palettes from the same bytes.
//

import PandoraCore
import UIKit

enum ArtworkPaletteService {
    /// Downsample side cap — 1,024 pixels is plenty for a dominant hue
    /// and keeps the draw + loop far off the interaction budget.
    private static let sampleSide = 32

    /// The palette for an artwork URL, loading through the shared
    /// `ArtworkCache` (no second download — the views use the same
    /// image). nil when the artwork cannot be loaded or is effectively
    /// grayscale; callers keep their previous (or brand) palette.
    static func palette(for artworkURL: String) async -> ArtworkColors? {
        guard let image = await ArtworkCache.shared.image(for: artworkURL) else {
            return nil
        }
        guard let sample = rgba8Sample(from: image) else { return nil }
        return ArtworkColors.extract(
            fromRGBA8: sample.pixels, width: sample.width, height: sample.height
        )
    }

    /// Draws the image into a fixed 32×32 RGBA8 buffer (premultiplied
    /// last, device RGB) — the one UIKit-touching step; everything
    /// downstream is platform-free math.
    static func rgba8Sample(from image: UIImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        guard let cgImage = image.cgImage else { return nil }
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }
        return (pixels, side, side)
    }
}
