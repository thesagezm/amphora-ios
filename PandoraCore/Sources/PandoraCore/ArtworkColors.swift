//
//  ArtworkColors.swift
//  PandoraCore
//
//  Dominant-color extraction from artwork pixels — the shared derivation
//  behind Amphora's artwork-driven theming. Pure pixel math with no
//  platform dependencies: the app target feeds it RGBA bytes (iOS) and a
//  future Android port feeds it the same bytes from a Bitmap, so both
//  apps derive identical palettes from the same cover art.
//
//  Algorithm (deterministic, ~1k pixels):
//   1. Convert every pixel to HSV.
//   2. Skip near-black (v < 0.08) and gray (s < 0.10) pixels — they
//      describe lighting, not the cover's color.
//   3. Bucket by hue (12 buckets × 30°); a pixel's weight is
//      `s · (0.2 + 0.8·v)` — saturation-weighted with a floor so fully
//      saturated brights (pure red, neon covers) keep full weight and
//      only darkness fades a pixel out.
//   4. The winning bucket's weighted-average RGB is the dominant color;
//      the accent and both gradient stops are derived from it in HSV
//      space with fixed clamps.
//   5. If the total chromatic weight is negligible the cover is
//      effectively grayscale — return nil and let the caller fall back
//      to the brand palette.
//

/// An sRGB color component triple (0...1 per channel), platform-free so
/// it can be shared with a non-Apple port.
public struct PaletteColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

/// The artwork-derived theme for one cover: a vivid accent for controls
/// and two deep stops for the ambient background gradient.
public struct ArtworkColors: Equatable, Sendable {
    public let dominant: PaletteColor
    public let accent: PaletteColor
    public let backgroundTop: PaletteColor
    public let backgroundBottom: PaletteColor

    /// Amphora's brand palette (violet + gold, echoing the app icon) —
    /// used before the first artwork loads and for grayscale covers.
    public static let brand = ArtworkColors(
        dominant: PaletteColor(red: 0.424, green: 0.290, blue: 0.714),
        accent: PaletteColor(red: 0.949, green: 0.698, blue: 0.200),
        backgroundTop: PaletteColor(red: 0.133, green: 0.094, blue: 0.212),
        backgroundBottom: PaletteColor(red: 0.047, green: 0.039, blue: 0.078)
    )

    /// Number of hue buckets (30° each).
    static let hueBucketCount = 12

    /// Minimum total chromatic weight for a cover to count as colored.
    /// A handful of stray colored pixels must not theme the player; a
    /// region of ≥ ~2% of a 32×32 sample does.
    static let minimumChromaticWeight: Double = 8

    /// Extracts a palette from raw RGBA8 bytes (premultiplied alpha,
    /// 4 bytes per pixel, row-major). Returns nil for unusable input or
    /// an effectively grayscale image.
    public static func extract(
        fromRGBA8 pixels: [UInt8],
        width: Int,
        height: Int
    ) -> ArtworkColors? {
        guard width > 0, height > 0, pixels.count >= width * height * 4 else {
            return nil
        }

        var weightSums = [Double](repeating: 0, count: hueBucketCount)
        var weightedRed = [Double](repeating: 0, count: hueBucketCount)
        var weightedGreen = [Double](repeating: 0, count: hueBucketCount)
        var weightedBlue = [Double](repeating: 0, count: hueBucketCount)
        var totalWeight = 0.0

        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            let red = Double(pixels[offset]) / 255
            let green = Double(pixels[offset + 1]) / 255
            let blue = Double(pixels[offset + 2]) / 255
            let (hue, saturation, value) = rgbToHSV(red, green, blue)
            guard value >= 0.08, saturation >= 0.10 else { continue }
            let weight = saturation * (0.2 + 0.8 * value)
            guard weight > 0 else { continue }
            let bucket = min(hueBucketCount - 1, Int(hue * Double(hueBucketCount)))
            weightSums[bucket] += weight
            weightedRed[bucket] += red * weight
            weightedGreen[bucket] += green * weight
            weightedBlue[bucket] += blue * weight
            totalWeight += weight
        }

        guard totalWeight >= minimumChromaticWeight,
              let best = weightSums.indices.max(by: { weightSums[$0] < weightSums[$1] }),
              weightSums[best] > 0
        else { return nil }

        let sum = weightSums[best]
        let dominant = PaletteColor(
            red: weightedRed[best] / sum,
            green: weightedGreen[best] / sum,
            blue: weightedBlue[best] / sum
        )
        return ArtworkColors(
            dominant: dominant,
            accent: accent(from: dominant),
            backgroundTop: backgroundTop(from: dominant),
            backgroundBottom: backgroundBottom(from: dominant)
        )
    }

    /// The control accent: vivid and mid-brightness so it reads as a tint
    /// on dark backgrounds without glowing (fixed clamps, both ports).
    static func accent(from dominant: PaletteColor) -> PaletteColor {
        let (h, s, v) = rgbToHSV(dominant.red, dominant.green, dominant.blue)
        return hsvToColor(h, min(1, max(0.45, s * 1.2)), min(0.80, max(0.55, v)))
    }

    /// Deep tinted stop — clearly the cover's hue, near-black in value.
    static func backgroundTop(from dominant: PaletteColor) -> PaletteColor {
        let (h, s, v) = rgbToHSV(dominant.red, dominant.green, dominant.blue)
        return hsvToColor(h, min(1, s * 0.60), max(0.10, v * 0.32))
    }

    /// The gradient's floor: barely-tinted near-black.
    static func backgroundBottom(from dominant: PaletteColor) -> PaletteColor {
        let (h, s, v) = rgbToHSV(dominant.red, dominant.green, dominant.blue)
        return hsvToColor(h, min(1, s * 0.35), max(0.04, v * 0.10))
    }

    // MARK: - HSV conversion

    /// Returns hue in 0..<1, saturation and value in 0...1.
    static func rgbToHSV(
        _ red: Double, _ green: Double, _ blue: Double
    ) -> (hue: Double, saturation: Double, value: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        guard maxValue > 0, delta > 0 else { return (0, 0, maxValue) }
        var hue: Double
        if maxValue == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxValue == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / maxValue, maxValue)
    }

    static func hsvToColor(_ hue: Double, _ saturation: Double, _ value: Double) -> PaletteColor {
        let sector = ((Int(hue * 6) % 6) + 6) % 6
        let fraction = hue * 6 - Double(Int(hue * 6))
        let p = value * (1 - saturation)
        let q = value * (1 - fraction * saturation)
        let t = value * (1 - (1 - fraction) * saturation)
        switch sector {
        case 0: return PaletteColor(red: value, green: t, blue: p)
        case 1: return PaletteColor(red: q, green: value, blue: p)
        case 2: return PaletteColor(red: p, green: value, blue: t)
        case 3: return PaletteColor(red: p, green: q, blue: value)
        case 4: return PaletteColor(red: t, green: p, blue: value)
        default: return PaletteColor(red: value, green: p, blue: q)
        }
    }
}
